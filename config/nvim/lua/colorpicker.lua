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
    "norcalli/nvim-colorizer.lua",
    config = function()
      require("colorizer").setup({
        "*", -- tous les fichiers
      }, {
        RGB = true,
        RRGGBB = true,
        names = true,
        RRGGBBAA = true,
        rgb_fn = true,
        hsl_fn = true,
        css = true,
        css_fn = true,
      })
    end,
  
} 
}
