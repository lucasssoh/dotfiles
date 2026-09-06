local parsers = {
  "lua", "javascript", "typescript", "tsx", "python",
  "java", "c_sharp", "json", "markdown", "markdown_inline",
  "bash", "html", "css", "yaml", "vim", "vimdoc",
}

return {
  "nvim-treesitter/nvim-treesitter",
  branch = "main",
  build = ":TSUpdate",
  lazy = false,
  config = function()
    require("nvim-treesitter").setup()
    require("nvim-treesitter").install(parsers)

    vim.api.nvim_create_autocmd("FileType", {
      pattern = parsers,
      callback = function()
        vim.treesitter.start()
      end,
    })
  end,
}
