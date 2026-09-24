-- ============================================================
-- FTPLUGIN/MARKDOWN.LUA — aperçu en direct, et mode slide sur les decks mdp
-- ============================================================
-- Tout ce qui est posé ici est BUFFER-LOCAL : sur un .java, un .qml,
-- aucun de ces mappings n'existe. Alt reste donc disponible ailleurs, et
-- <leader> n'est jamais touché.
--
-- <A-p> veut dire « voir le rendu » partout : aperçu en direct sur un
-- markdown ordinaire (lua/mdlive.lua), présentation mdp sur un deck
-- (ccslide), aperçu PlantUML sur un .puml. :MdLive ouvre l'aperçu même
-- sur un deck.
-- ============================================================

local buf = vim.api.nvim_get_current_buf()

vim.api.nvim_buf_create_user_command(buf, "MdLive", function()
    require("mdlive").toggle()
end, { desc = "Aperçu markdown en direct" })

local ok, ccslide = pcall(require, "ccslide")
local deck = ok and ccslide.detect(buf)

if deck then
    ccslide.attach(buf)
else
    vim.keymap.set("n", "<A-p>", function()
        require("mdlive").toggle()
    end, { buffer = buf, silent = true, desc = "markdown: aperçu en direct" })
end

if ok then
    -- Pour un markdown quelconque qu'on veut présenter malgré tout (un cours
    -- récupéré tel quel, par exemple) : :CcslideOn l'ouvre au mode slide.
    vim.api.nvim_buf_create_user_command(buf, "CcslideOn", function()
        ccslide.attach(vim.api.nvim_get_current_buf())
        vim.notify("ccslide : mode slide activé")
    end, { desc = "Activer le mode slide sur ce buffer" })
end
