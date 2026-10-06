-- ============================================================
-- BOUSSOLE.LUA — dire à Boussole sur quel fichier on est
-- ============================================================
-- Pendant une séance, Boussole demande « c'est en lien avec la séance ? »
-- quand autre chose que la fiche occupe l'écran un moment. Pour un
-- terminal, le titre de la fenêtre ne dit pas quel dossier on édite : ce
-- module le lui dit. Il envoie, sur le socket de Boussole :
--   * le fichier du buffer courant, et si nvim a le focus (FocusGained /
--     FocusLost, que wezterm transmet) ;
--   * à chaque :w, combien de lignes ont été ajoutées depuis la dernière
--     écriture.
-- Jamais le contenu. Rien n'est envoyé si Boussole ne tourne pas : un
-- socket absent, et c'est tout.
-- ============================================================

local M = {}

local SOCKET = (os.getenv("XDG_RUNTIME_DIR") or "") .. "/boussole.sock"

local focused = true
-- Lignes du buffer à la dernière écriture, par buffer.
local baseline = {}

local function file_of(buf)
    if vim.bo[buf].buftype ~= "" then return nil end
    local name = vim.api.nvim_buf_get_name(buf)
    if name == "" then return nil end
    return vim.fn.fnamemodify(name, ":p")
end

local function send(msg)
    if not vim.uv.fs_stat(SOCKET) then return end
    local pipe = vim.uv.new_pipe(false)
    pipe:connect(SOCKET, function(err)
        if err then
            pipe:close()
            return
        end
        pipe:write(vim.json.encode(msg) .. "\n", function()
            pipe:close()
        end)
    end)
end

local function report(buf, written)
    local file = file_of(buf)
    if not file then return end
    send({ cmd = "editor", file = file, focus = focused, written = written or 0 })
end

function M.setup()
    local group = vim.api.nvim_create_augroup("Boussole", { clear = true })
    vim.api.nvim_create_autocmd({ "VimEnter", "BufEnter" }, {
        group = group,
        callback = function(ev)
            if baseline[ev.buf] == nil then
                baseline[ev.buf] = vim.api.nvim_buf_line_count(ev.buf)
            end
            if focused then report(ev.buf) end
        end,
    })
    vim.api.nvim_create_autocmd("FocusGained", {
        group = group,
        callback = function()
            focused = true
            report(vim.api.nvim_get_current_buf())
        end,
    })
    vim.api.nvim_create_autocmd({ "FocusLost", "VimLeavePre" }, {
        group = group,
        callback = function()
            focused = false
            report(vim.api.nvim_get_current_buf())
        end,
    })
    vim.api.nvim_create_autocmd("BufWritePost", {
        group = group,
        callback = function(ev)
            local n = vim.api.nvim_buf_line_count(ev.buf)
            local added = math.max(0, n - (baseline[ev.buf] or n))
            baseline[ev.buf] = n
            report(ev.buf, added)
        end,
    })
end

return M
