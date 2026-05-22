return {
  {
    "ziontee113/color-picker.nvim",
    config = function()
      require("color-picker").setup()

      local opts = { noremap = true, silent = true }
      vim.keymap.set("n", "<C-c>", "<cmd>PickColor<cr>", opts)
      vim.keymap.set("i", "<C-c>", "<cmd>PickColorInsert<cr>", opts)
    end,
  },
  {
    -- Remplacement du vieux fork de norcalli par celui de NvChad
    "NvChad/nvim-colorizer.lua",
    config = function()
      require("colorizer").setup({
        filetypes = { "*" }, -- Syntaxe propre pour cibler tous les fichiers
        user_default_options = {
          RGB = true,
          RRGGBB = true,
          names = true,
          RRGGBBAA = true,
          rgb_fn = true,
          hsl_fn = true,
          css = true,
          css_fn = true,
        },
      })
    end,
  },
}
