-- ============================================================
-- BUFFERS.LUA
-- ============================================================
-- ":q" ferme une *fenetre*, jamais un buffer. Le fichier reste
-- "listed" (:ls le montre encore), et bufferline tourne en
-- mode = "buffers" : il affiche exactement les buffers listes.
-- D'ou l'onglet qui survit au :q. Seul le X de bufferline le
-- retire vraiment, parce que son close_command par defaut est
-- "bdelete! %d" -- une suppression de buffer, pas de fenetre.
--
-- Ce module fait ce que fait le X, mais sans casser le layout :
-- ":bdelete" tout court ferme aussi les fenetres qui affichaient
-- le buffer (et quitte nvim si c'etait la derniere), donc on
-- rebascule d'abord chaque fenetre concernee sur un autre buffer.

local M = {}

-- Les buffers listes, dans l'ordre ou bufferline les affiche
-- (sort_by = "id" par defaut, soit l'ordre des numeros).
local function listed()
    return vim.tbl_filter(function(b)
        return vim.api.nvim_buf_is_valid(b) and vim.bo[b].buflisted
    end, vim.api.nvim_list_bufs())
end

-- Sur quoi retomber une fois `buf` supprime : le voisin de droite
-- dans la bufferline, sinon celui de gauche -- le meme atterrissage
-- que le X. nil = il ne restait que `buf`.
local function neighbour(buf)
    local bufs = listed()
    for i, b in ipairs(bufs) do
        if b == buf then
            return bufs[i + 1] or bufs[i - 1]
        end
    end
    return bufs[1]
end

-- Ferme le buffer `buf` (defaut : le courant) en gardant les
-- fenetres ouvertes. `force` jette les modifications non sauvees.
function M.close(buf, force)
    buf = buf or vim.api.nvim_get_current_buf()
    if not vim.api.nvim_buf_is_valid(buf) then
        return false
    end

    if vim.bo[buf].modified and not force then
        vim.notify(
            "Buffer modifie : :w d'abord, ou <leader>X pour fermer sans sauver.",
            vim.log.levels.WARN
        )
        return false
    end

    local repl = neighbour(buf)

    for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
            if not repl then
                -- Plus rien a afficher : un buffer vide plutot que la
                -- fermeture de la fenetre (alpha reprend la main juste
                -- apres si le dashboard est dispo).
                repl = vim.api.nvim_create_buf(true, false)
            end
            vim.api.nvim_win_set_buf(win, repl)
        end
    end

    pcall(vim.api.nvim_buf_delete, buf, { force = force == true })
    return true
end

-- ============================================================
-- ":q" ferme aussi le fichier
-- ============================================================
-- QuitPre se declenche avant que :q ne ferme la fenetre courante.
-- On en profite pour delister le buffer qui s'y trouve : la fenetre
-- se ferme comme d'habitude, mais l'onglet disparait avec elle.
--
-- Garde-fous, pour que :q reste :q dans tous les autres cas :
--  - buffers fichier uniquement (buftype "", listed) -- pas nvim-tree,
--    pas les flottants d'LSP, pas les terminaux, pas alpha ;
--  - buffer non modifie : sinon :q doit echouer sur E37, pas perdre
--    le travail en silence ;
--  - buffer affiche dans une seule fenetre : fermer un split ne doit
--    pas fermer le fichier resté visible ailleurs ;
--  - au moins deux fenetres non flottantes : si c'est la derniere,
--    nvim s'arrete de toute facon, rien a delister.
local closing = false

vim.api.nvim_create_autocmd("QuitPre", {
    group = vim.api.nvim_create_augroup("CoucouQuitClosesBuffer", { clear = true }),
    callback = function()
        if closing then
            return
        end

        local buf = vim.api.nvim_get_current_buf()
        if vim.bo[buf].buftype ~= "" or not vim.bo[buf].buflisted or vim.bo[buf].modified then
            return
        end

        local showing, panes = 0, 0
        for _, win in ipairs(vim.api.nvim_list_wins()) do
            if vim.api.nvim_win_get_config(win).relative == "" then
                panes = panes + 1
                if vim.api.nvim_win_get_buf(win) == buf then
                    showing = showing + 1
                end
            end
        end
        if showing ~= 1 or panes < 2 then
            return
        end

        closing = true
        M.close(buf)
        closing = false
    end,
})

return M
