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
        cmp.setup({
            mapping = cmp.mapping.preset.insert({
                ["<C-Space>"] = cmp.mapping.complete(),
                ["<CR>"]      = cmp.mapping.confirm({ select = true }),
                ["<Tab>"]     = cmp.mapping.select_next_item(),
                ["<S-Tab>"]   = cmp.mapping.select_prev_item(),
            }),
        })

        require("mason").setup({})
        require("mason-lspconfig").setup({
            ensure_installed = {"jdtls", "ts_ls", "pyright", "lua_ls", "clangd"},
            handlers = { lsp_zero.default_setup, jdtls = lsp_zero.noop },
        })

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
