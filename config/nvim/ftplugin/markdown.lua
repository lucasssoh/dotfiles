-- ============================================================
-- FTPLUGIN/MARKDOWN.LUA — active le mode slide sur les decks mdp
-- ============================================================
-- Tout ce que pose ccslide est BUFFER-LOCAL : sur un .java, un .qml ou
-- même un markdown ordinaire, aucun de ces mappings n'existe. Alt reste
-- donc entièrement disponible ailleurs, et <leader> n'est jamais touché.
-- ============================================================

local ok, ccslide = pcall(require, "ccslide")
if not ok then
    return
end

local buf = vim.api.nvim_get_current_buf()

if ccslide.detect(buf) then
    ccslide.attach(buf)
end

-- Pour un markdown quelconque qu'on veut présenter malgré tout (un cours
-- récupéré tel quel, par exemple) : :CcslideOn l'ouvre au mode slide.
vim.api.nvim_buf_create_user_command(buf, "CcslideOn", function()
    ccslide.attach(vim.api.nvim_get_current_buf())
    vim.notify("ccslide : mode slide activé")
end, { desc = "Activer le mode slide sur ce buffer" })
