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
-- rebascule d'abord chaque fenetre concernee sur le fichier suivant.
-- L'arbre n'est choisi que s'il ne reste plus aucun fichier ouvert.

local M = {}

-- Vrai pendant que QuitPre gere un :q : M.close ne doit alors pas
-- fermer la fenetre lui-meme, :q s'en charge juste apres.
local closing = false

-- Un buffer "fichier" : ce que bufferline affiche et sur quoi on veut
-- atterrir. L'arbre (buftype nofile), le dashboard alpha, les terminaux
-- et les flottants LSP sont ecartes.
local function is_file(b)
    return vim.api.nvim_buf_is_valid(b)
        and vim.bo[b].buflisted
        and vim.bo[b].buftype == ""
end

-- Les buffers fichier, dans l'ordre ou bufferline les affiche
-- (sort_by = "id" par defaut, soit l'ordre des numeros).
local function files()
    return vim.tbl_filter(is_file, vim.api.nvim_list_bufs())
end

-- Sur quoi retomber une fois `buf` supprime : le voisin de droite
-- dans la bufferline, sinon celui de gauche -- le meme atterrissage
-- que le X. nil = il ne restait que `buf`.
local function neighbour(buf)
    local bufs = files()
    for i, b in ipairs(bufs) do
        if b == buf then
            return bufs[i + 1] or bufs[i - 1]
        end
    end
    return bufs[1]
end

-- La fenetre de l'arbre, s'il est ouvert.
local function tree_win()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        local b = vim.api.nvim_win_get_buf(win)
        if vim.bo[b].filetype == "NvimTree" then
            return win
        end
    end
end

-- Ferme le buffer `buf` (defaut : le courant) en gardant les
-- fenetres ouvertes. `force` jette les modifications non sauvees.
function M.close(buf, force)
    buf = buf or vim.api.nvim_get_current_buf()
    if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].filetype == "NvimTree" then
        return false
    end

    if vim.bo[buf].modified and not force then
        vim.notify(
            "Fichier modifie : :w pour enregistrer, <leader>X pour fermer sans enregistrer.",
            vim.log.levels.WARN
        )
        return false
    end

    local repl = neighbour(buf)
    -- Plus aucun fichier a editer : l'arbre prend la place. Pendant
    -- :q (closing), on le laisse fermer la fenetre tout seul.
    local tree = (not repl and not closing) and tree_win() or nil

    for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
            if tree then
                pcall(vim.api.nvim_win_close, win, true)
            else
                local target = repl or vim.api.nvim_create_buf(true, false)
                vim.api.nvim_win_set_buf(win, target)
                -- Alpha reprend la main juste apres si le dashboard
                -- est dispo.
                repl = target
            end
        end
    end

    if tree and vim.api.nvim_win_is_valid(tree) then
        vim.api.nvim_set_current_win(tree)
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

-- ============================================================
-- ":bd" passe par M.close
-- ============================================================
-- Vim choisit le buffer alternatif -- souvent l'arbre -- pour la
-- fenetre du fichier ferme. Une commande utilisateur ne peut pas
-- s'appeler "bd" (E183 : il faut une majuscule), donc <CR> en
-- mode commande reecrit "bd" et "bdelete" en Bdelete au passage.
vim.api.nvim_create_user_command("Bdelete", function(opts)
    local args = opts.fargs
    if #args == 0 then
        args = { tostring(vim.api.nvim_get_current_buf()) }
    end
    for _, arg in ipairs(args) do
        local n = tonumber(arg)
        if not n then
            n = vim.fn.bufnr(arg)
        end
        if n and n > 0 then
            M.close(n, opts.bang)
        end
    end
end, { bang = true, nargs = "*", complete = "buffer", desc = "Close buffer, landing on the next file buffer" })

vim.keymap.set("c", "<CR>", function()
    if vim.fn.getcmdtype() ~= ":" then
        return "<CR>"
    end
    local line = vim.fn.getcmdline()
    -- Mot entier : ":bdel" (une abreviation Vim valide) ne doit pas
    -- etre pris pour ":bd el".
    local function parse(cmd)
        local bang, rest = line:match("^%s*" .. cmd .. "(!?)%s*$")
        if bang then
            return bang, ""
        end
        return line:match("^%s*" .. cmd .. "(!?)%s+(.*)$")
    end
    local bang, rest = parse("bdelete")
    if not bang then
        bang, rest = parse("bd")
    end
    if not bang then
        return "<CR>"
    end
    -- <C-u> efface la ligne tapee puis execute Bdelete : <Cmd> ne
    -- s'execute pas depuis une expression de mode commande.
    return "<C-u>Bdelete" .. bang .. (rest ~= "" and (" " .. rest) or "") .. "<CR>"
end, { expr = true, desc = "Route :bd and :bdelete through Bdelete" })

return M
