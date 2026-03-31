return {
  "numToStr/Comment.nvim",
  dependencies = {
    "JoosepAlviste/nvim-ts-context-commentstring",
  },
  config = function()
    -- Configuration indispensable pour les versions récentes du plugin de contexte
    require('ts_context_commentstring').setup {
      enable_autocmd = false,
    }

    require("Comment").setup({
      -- Permet de gérer les commentaires contextuels (ex: HTML dans PHP/JS)
      pre_hook = require("ts_context_commentstring.integrations.comment_nvim").create_pre_hook(),
    })
  end
}
