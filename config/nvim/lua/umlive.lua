-- ============================================================
-- UMLIVE.LUA — aperçu PlantUML en direct (côté nvim)
-- ============================================================
-- Le serveur est bin/umlive (voir son en-tête) : il garde une JVM
-- plantuml chaude, et affiche chaque rendu dans imv (Firefox à défaut).
-- Ce module ne fait que lui envoyer, sur son stdin, le diagramme sous
-- le curseur à chaque changement du buffer -- depuis la mémoire de nvim,
-- donc sans :w.
--
-- Un seul aperçu par nvim : il suit le buffer .puml courant. Il meurt
-- avec nvim (stdin fermé), ou à la bascule <A-p>.
-- ============================================================

local M = {}

local SERVER = vim.fn.stdpath("config") .. "/bin/umlive"
-- Assez court pour paraître immédiat, assez long pour ne pas rendre
-- chaque lettre d'un mot tapé d'une traite : un rendu coûte ~45 ms.
local DEBOUNCE_MS = 120

local job, last, group
local timer = vim.uv.new_timer()

--- Le diagramme qui contient le curseur, sinon celui qui le précède,
--- sinon le premier. Renvoie son texte et la ligne (1-based) de son
--- @start. Sans aucun @start, tout le buffer (plantuml accepte).
local function current_diagram(buf)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local cur = vim.api.nvim_win_get_cursor(0)[1]
    local start
    for i = 1, #lines do
        if lines[i]:match("^%s*@start") then
            if i <= cur or not start then
                start = i
            end
            if i > cur then
                break
            end
        end
    end
    if not start then
        return table.concat(lines, "\n"), 1
    end
    local stop = #lines
    for i = start + 1, #lines do
        if lines[i]:match("^%s*@end") then
            stop = i
            break
        end
    end
    return table.concat(lines, "\n", start, stop), start
end

local function send()
    local buf = vim.api.nvim_get_current_buf()
    if not job or vim.bo[buf].filetype ~= "plantuml" then
        return
    end
    local source, first = current_diagram(buf)
    local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t")
    local msg = vim.json.encode({ source = source, first = first, name = name ~= "" and name or "[sans nom]" })
    -- Déplacer le curseur DANS le même diagramme ne change rien : pas de
    -- rendu pour rien.
    if msg == last then
        return
    end
    last = msg
    vim.fn.chansend(job, msg .. "\n")
end

local function schedule_send()
    timer:stop()
    timer:start(DEBOUNCE_MS, 0, vim.schedule_wrap(send))
end

function M.running()
    return job ~= nil
end

function M.stop()
    if job then
        -- Fermer stdin suffit : umlive prévient la page, ferme la fenêtre
        -- et tue sa JVM.
        vim.fn.chanclose(job, "stdin")
    end
end

function M.start()
    if job then
        return
    end
    if vim.fn.executable(SERVER) == 0 or vim.fn.executable("plantuml") == 0 then
        vim.notify("umlive : plantuml ou bin/umlive introuvable", vim.log.levels.ERROR)
        return
    end
    last = nil
    job = vim.fn.jobstart({ SERVER }, {
        stderr_buffered = true,
        on_stderr = function(_, data)
            local text = vim.trim(table.concat(data or {}, "\n"))
            if text ~= "" then
                vim.notify("umlive : " .. text, vim.log.levels.WARN)
            end
        end,
        on_exit = function()
            job = nil
            if group then
                vim.api.nvim_del_augroup_by_id(group)
                group = nil
            end
        end,
    })
    if job <= 0 then
        job = nil
        vim.notify("umlive : échec du lancement", vim.log.levels.ERROR)
        return
    end

    group = vim.api.nvim_create_augroup("umlive", { clear = true })
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "CursorMoved", "CursorMovedI", "BufEnter" }, {
        group = group,
        callback = schedule_send,
    })
    send()
end

function M.toggle()
    if job then
        M.stop()
    else
        M.start()
    end
end

return M
