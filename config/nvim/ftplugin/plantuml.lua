-- ============================================================
-- FTPLUGIN/PLANTUML.LUA — outillage des .puml
-- ============================================================
-- Trois pièces indépendantes, chacune ignorée si son binaire manque :
--
--   1. Aperçu   <A-p> aperçu en direct (lua/umlive.lua), sans :w.
--               :PumlLiseuse ouvre le fichier dans la liseuse.
--   2. Lint     plantuml -syntax, erreurs en vim.diagnostic.
--   3. LSP      plantuml-lsp pour la complétion et le survol.
--
-- La coloration vient de lua/plugins/plantuml.lua (aklt/plantuml-syntax).
-- ============================================================

local buf = vim.api.nvim_get_current_buf()

-- ============================================================
-- 1. Aperçu
-- ============================================================
-- En direct : une fenêtre à côté du terminal, redessinée à chaque
-- frappe à partir du buffer en mémoire. Voir lua/umlive.lua et bin/umlive.
vim.keymap.set("n", "<A-p>", function()
    require("umlive").toggle()
end, { buffer = buf, silent = true, desc = "plantuml: aperçu en direct" })

-- La liseuse, elle, lit le FICHIER (elle le rend en PDF, un diagramme
-- par page) : pour relire ou imprimer, pas pour écrire. D'où le :update.
local liseuse = vim.fn.expand("~/.local/bin/liseuse")
if vim.fn.executable(liseuse) == 1 then
    vim.api.nvim_buf_create_user_command(buf, "PumlLiseuse", function()
        vim.cmd("silent update")
        vim.system({ liseuse, "open", vim.api.nvim_buf_get_name(buf) }, { detach = true })
    end, { desc = "Ouvrir ce .puml dans la liseuse" })
end

-- ============================================================
-- 2. Lint : plantuml -syntax
-- ============================================================
-- Le buffer passe par stdin, donc le lint voit ce qui est tapé, pas ce
-- qui est sauvé. La sortie donne un verdict par diagramme, dans l'ordre
-- des @startuml du fichier (mesuré sur plantuml 1.2026.2) :
--
--     CLASS               ERROR
--     (4 entities)        1                  <- ligne, 0 = le @startuml
--                         Syntax Error? ...
--
-- Le numéro de ligne est RELATIF au @startuml de son diagramme : sur un
-- fichier à plusieurs diagrammes, il faut le recaler sur le bon.
--
-- ~0,55 s par passe (la JVM), d'où l'attente d'une pause de frappe et
-- l'abandon d'une passe dépassée par une plus récente.

local ns = vim.api.nvim_create_namespace("plantuml_lint")
local DEBOUNCE_MS = 600

local function diagram_starts(lines)
    local starts = {}
    for i, l in ipairs(lines) do
        if l:match("^%s*@start") then
            starts[#starts + 1] = i - 1
        end
    end
    return starts
end

local function parse(out, starts)
    local diags, lines, k, i = {}, vim.split(out, "\n", { trimempty = true }), 0, 1
    while i <= #lines do
        k = k + 1
        if lines[i] == "ERROR" then
            local rel, msg = tonumber(lines[i + 1]), lines[i + 2]
            if rel and starts[k] then
                diags[#diags + 1] = {
                    lnum = starts[k] + rel,
                    col = 0,
                    severity = vim.diagnostic.severity.ERROR,
                    source = "plantuml",
                    message = msg or "Syntax Error",
                }
            end
            i = i + 3
        else
            -- Diagramme valide : son type, puis "(n entities)".
            i = i + 1
            if lines[i] and lines[i]:match("^%(") then
                i = i + 1
            end
        end
    end
    return diags
end

if vim.fn.executable("plantuml") == 1 then
    local timer, job, gen = vim.uv.new_timer(), nil, 0

    local function lint()
        if not vim.api.nvim_buf_is_valid(buf) then
            return
        end
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        local starts = diagram_starts(lines)
        if #starts == 0 then
            vim.diagnostic.reset(ns, buf)
            return
        end
        if job then
            job:kill(9)
        end
        gen = gen + 1
        local mine = gen
        job = vim.system({ "plantuml", "-syntax" }, { stdin = table.concat(lines, "\n"), text = true },
            function(res)
                vim.schedule(function()
                    -- Une passe plus récente est partie entre-temps : son
                    -- résultat compte, pas celui-ci.
                    if mine ~= gen or not vim.api.nvim_buf_is_valid(buf) then
                        return
                    end
                    job = nil
                    vim.diagnostic.set(ns, buf, parse(res.stdout or "", starts))
                end)
            end)
    end

    vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "InsertLeave", "TextChanged" }, {
        buffer = buf,
        group = vim.api.nvim_create_augroup("plantuml_lint_" .. buf, { clear = true }),
        callback = function()
            timer:stop()
            timer:start(DEBOUNCE_MS, 0, vim.schedule_wrap(lint))
        end,
    })
    vim.api.nvim_create_autocmd("BufWipeout", {
        buffer = buf,
        once = true,
        callback = function()
            timer:stop()
            timer:close()
        end,
    })
end

-- ============================================================
-- 3. LSP : plantuml-lsp (complétion, survol)
-- ============================================================
-- Pas dans Mason : installé par `go install` (voir install.sh), d'où le
-- chemin ~/go/bin ou ~/.local/bin en plus du PATH.
--
-- Lancé SANS --exec-path, et c'est voulu : ses diagnostics passent par
-- le même plantuml -syntax, mais sans recaler les lignes des fichiers à
-- plusieurs diagrammes. Le lint ci-dessus s'en charge, lui.
--
-- Pas de --stdlib-path non plus : il n'apporte que la complétion de la
-- stdlib PlantUML (C4, AWS...), inutile pour de l'UML de cours.

local lsp_bin = vim.fn.exepath("plantuml-lsp")
if lsp_bin == "" then
    for _, p in ipairs({ "~/.local/bin/plantuml-lsp", "~/go/bin/plantuml-lsp" }) do
        if vim.fn.executable(vim.fn.expand(p)) == 1 then
            lsp_bin = vim.fn.expand(p)
            break
        end
    end
end

if lsp_bin ~= "" then
    local file = vim.api.nvim_buf_get_name(buf)
    -- Ce qui branche la complétion sur nvim-cmp (lsp/mason.lua).
    local ok, cmp_lsp = pcall(require, "cmp_nvim_lsp")
    vim.lsp.start({
        name = "plantuml_lsp",
        cmd = { lsp_bin },
        root_dir = vim.fs.root(file, ".git") or vim.fs.dirname(file),
        capabilities = ok and cmp_lsp.default_capabilities() or nil,
    }, { bufnr = buf })
end
