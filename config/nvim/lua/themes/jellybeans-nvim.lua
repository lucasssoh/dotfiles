
return {
  "metalelf0/jellybeans-nvim",
  name = "jellybeans-nvim",
  priority = 1000, 
  lazy = false,
  dependencies = {
    "rktjmp/lush.nvim",
  },
  config = function()
    vim.cmd.colorscheme("jellybeans-nvim")
  end,
}
