local parsers = {
  "lua", "javascript", "typescript", "tsx", "python",
  "java", "c_sharp", "json", "markdown", "markdown_inline",
  "bash", "html", "css", "yaml", "vim", "vimdoc",
  -- Injecté dans le markdown par markdown_inline (requête
  -- injections.scm : latex_block -> latex). Sans lui, aucun noeud
  -- latex n'existe et render-markdown ne voit pas les formules.
  "latex",
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
