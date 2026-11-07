-- ============================================================
-- LSP/MASON.LUA
-- ============================================================
return {
    "VonHeikemen/lsp-zero.nvim",
    branch = "v3.x",
    dependencies = {
        "williamboman/mason.nvim",
        "williamboman/mason-lspconfig.nvim",
        "neovim/nvim-lspconfig",
        "hrsh7th/nvim-cmp",
        "hrsh7th/cmp-nvim-lsp",
        "L3MON4D3/LuaSnip",
        "mfussenegger/nvim-jdtls",
    },
    config = function()
        local lsp_zero = require("lsp-zero")
        lsp_zero.on_attach(function(client, bufnr)
            lsp_zero.default_keymaps({ buffer = bufnr })
        end)

        local cmp = require("cmp")
        -- Snippets : les serveurs (rust-analyzer surtout) completent `fn`,
        -- `match`, `println!`... avec des champs a remplir. Ils s'ouvrent
        -- avec les snippets natifs de nvim (vim.snippet) ; Tab/S-Tab passent
        -- au champ suivant/precedent quand le menu est ferme. Avant, Tab ne
        -- faisait que parcourir le menu : on restait bloque dans le premier
        -- champ.
        cmp.setup({
            snippet = {
                expand = function(args) vim.snippet.expand(args.body) end,
            },
            mapping = cmp.mapping.preset.insert({
                ["<C-Space>"] = cmp.mapping.complete(),
                ["<CR>"]      = cmp.mapping.confirm({ select = true }),
                ["<Tab>"]     = cmp.mapping(function(fallback)
                    if cmp.visible() then
                        cmp.select_next_item()
                    elseif vim.snippet.active({ direction = 1 }) then
                        vim.snippet.jump(1)
                    else
                        fallback()
                    end
                end, { "i", "s" }),
                ["<S-Tab>"]   = cmp.mapping(function(fallback)
                    if cmp.visible() then
                        cmp.select_prev_item()
                    elseif vim.snippet.active({ direction = -1 }) then
                        vim.snippet.jump(-1)
                    else
                        fallback()
                    end
                end, { "i", "s" }),
            }),
        })

        require("mason").setup({})
        require("mason-lspconfig").setup({
            -- omnisharp needs the .NET SDK on PATH (dotnet) to run --
            -- already true on this machine. No custom handler needed, same
            -- as ts_ls/pyright/clangd: default_setup covers it, unlike
            -- jdtls which needs its own workspace/lombok wiring below.
            ensure_installed = {"jdtls", "ts_ls", "pyright", "ruff", "lua_ls", "clangd", "omnisharp"},
            handlers = { lsp_zero.default_setup, jdtls = lsp_zero.noop },
            -- mason-lspconfig v2 ignores `handlers` and vim.lsp.enable()s
            -- every installed server itself, so the noop above no longer
            -- keeps jdtls out: each Java buffer got a second jdtls, without
            -- Lombok or a workspace, beside the one from lsp/java.lua.
            automatic_enable = { exclude = { "jdtls" } },
        })

        -- Rust : rust-analyzer vient de dnf (scripts/dev_setup.sh), pas de
        -- Mason, pour rester a la version exacte de rustc. Mason ne l'active
        -- donc pas : on le fait ici. Le diagnostic a la sauvegarde passe par
        -- clippy plutot que `cargo check` -- memes erreurs, plus les lints.
        vim.lsp.config("rust_analyzer", {
            capabilities = require("cmp_nvim_lsp").default_capabilities(),
            settings = { ["rust-analyzer"] = {
                check = { command = "clippy" },
                -- Les diagnostics que rust-analyzer calcule lui-meme, sur le
                -- buffer non sauvegarde (noms inconnus, types incompatibles,
                -- match incomplets...). Les "experimentaux" en ajoutent
                -- beaucoup : immediats, avant meme le passage de clippy.
                diagnostics = { experimental = { enable = true } },
            } },
        })
        vim.lsp.enable("rust_analyzer")

        -- =========================================================
        -- JAVA WARMUP
        -- Start jdtls as soon as a Java project folder is opened, instead
        -- of waiting for a .java file to be opened by hand. jdtls indexes
        -- and diagnoses the whole workspace on startup, so this is what
        -- makes nvim-tree's diagnostic icons (lua/plugins/nvimtree.lua)
        -- show errors/warnings on files nobody has opened yet.
        -- =========================================================
        vim.api.nvim_create_autocmd("VimEnter", {
            once = true,
            callback = function()
                local cwd = vim.fn.getcwd()
                -- fake filename so find_root's ":p:h" resolves back to cwd itself
                local root_dir = require("lsp.java").find_root(cwd .. "/x")
                if not root_dir then
                    return
                end
                local java_file = vim.fn.globpath(root_dir, "**/*.java", false, true)[1]
                if not java_file then
                    return
                end
                require("lsp.java").start(vim.fn.bufadd(java_file))
            end,
        })
    end,
}
