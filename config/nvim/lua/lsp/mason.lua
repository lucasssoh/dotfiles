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
            ensure_installed = { "ts_ls", "pyright", "lua_ls", "clangd" },
            handlers = { lsp_zero.default_setup },
        })
    end,
}
