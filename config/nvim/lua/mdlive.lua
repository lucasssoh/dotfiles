-- ============================================================
-- MDLIVE.LUA — aperçu markdown en direct (côté nvim)
-- ============================================================
-- La fenêtre est bin/mdview (voir son en-tête : GTK 4 natif, mise à jour
-- par bloc, style de la liseuse). Ce module lui envoie sur son stdin :
--   * tout le buffer, après une pause de frappe -- depuis la mémoire de
--     nvim, donc sans :w ;
--   * la ligne du curseur seule quand elle bouge, pour que l'aperçu la
--     suive.
-- Un seul aperçu par nvim : il suit le buffer markdown courant. Il meurt
-- avec nvim (stdin fermé), à la bascule, ou quand on ferme sa fenêtre.
-- ============================================================

local M = {}

local VIEWER = vim.fn.stdpath("config") .. "/bin/mdview"
-- Le texte : assez court pour paraître immédiat. Une frappe coûte ~5 ms
-- côté fenêtre (un seul bloc reconverti), c'est la pause qui fait le délai.
local TEXT_MS = 150
-- Le curseur : plus court, rien n'est reconverti.
local CURSOR_MS = 40

local job, group
local sent = { buf = nil, tick = nil, line = nil }
local text_timer, cursor_timer = vim.uv.new_timer(), vim.uv.new_timer()

local function is_md(buf)
    return vim.bo[buf].filetype == "markdown"
end

local function send(msg)
    if job then
        vim.fn.chansend(job, vim.json.encode(msg) .. "\n")
    end
end

local function send_text()
    local buf = vim.api.nvim_get_current_buf()
    if not job or not is_md(buf) then
        return
    end
    local tick = vim.api.nvim_buf_get_changedtick(buf)
    local line = vim.api.nvim_win_get_cursor(0)[1]
    if sent.buf == buf and sent.tick == tick then
        return
    end
    local name = vim.api.nvim_buf_get_name(buf)
    send({
        text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n"),
        cursor = line,
        name = name ~= "" and vim.fs.basename(name) or "[sans nom]",
        -- Les images et liens relatifs se résolvent depuis le dossier du
        -- fichier ; un buffer jamais sauvé prend le dossier courant.
        dir = name ~= "" and vim.fs.dirname(name) or vim.fn.getcwd(),
    })
    sent.buf, sent.tick, sent.line = buf, tick, line
end

local function send_cursor()
    local buf = vim.api.nvim_get_current_buf()
    if not job or not is_md(buf) or sent.buf ~= buf then
        return
    end
    local line = vim.api.nvim_win_get_cursor(0)[1]
    if line ~= sent.line then
        send({ cursor = line })
        sent.line = line
    end
end

local function later(timer, ms, fn)
    timer:stop()
    timer:start(ms, 0, vim.schedule_wrap(fn))
end

function M.running()
    return job ~= nil
end

function M.stop()
    if job then
        vim.fn.chanclose(job, "stdin")
    end
end

function M.start()
    if job then
        return
    end
    if vim.fn.executable(VIEWER) == 0 then
        vim.notify("mdlive : bin/mdview introuvable", vim.log.levels.ERROR)
        return
    end
    sent = { buf = nil, tick = nil, line = nil }
    job = vim.fn.jobstart({ VIEWER }, {
        stderr_buffered = true,
        on_stderr = function(_, data)
            local text = vim.trim(table.concat(data or {}, "\n"))
            -- GTK prévient bruyamment de choses sans conséquence (thème,
            -- portail) : seules les vraies erreurs Python remontent.
            if text:find("Traceback", 1, true) then
                vim.notify("mdlive : " .. text, vim.log.levels.WARN)
            end
        end,
        on_exit = function()
            job = nil
            if group then
                pcall(vim.api.nvim_del_augroup_by_id, group)
                group = nil
            end
        end,
    })
    if job <= 0 then
        job = nil
        vim.notify("mdlive : échec du lancement", vim.log.levels.ERROR)
        return
    end

    group = vim.api.nvim_create_augroup("mdlive", { clear = true })
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "BufEnter" }, {
        group = group,
        callback = function()
            later(text_timer, TEXT_MS, send_text)
        end,
    })
    vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
        group = group,
        callback = function()
            later(cursor_timer, CURSOR_MS, send_cursor)
        end,
    })
    send_text()
end

function M.toggle()
    if job then
        M.stop()
    else
        M.start()
    end
end

return M
