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
        -- Les codes explicites (#ff0000, rgb(), hsl()...) sont colores
        -- partout : une variable ne peut pas leur ressembler. Les noms
        -- de couleurs (Red, Green...), eux, se confondent avec des
        -- identifiants, donc ils ne s'allument que dans les fichiers
        -- qui parlent vraiment de couleur.
        filetypes = {
          "*",
          css = { names = true },
          scss = { names = true },
          sass = { names = true },
          less = { names = true },
          stylus = { names = true },
        },
        user_default_options = {
          names = false,
          RGB = true,
          RRGGBB = true,
          RRGGBBAA = true,
          rgb_fn = true,
          hsl_fn = true,
          css_fn = true,
        },
      })
    end,
  },
}
