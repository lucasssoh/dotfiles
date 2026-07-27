return {
  "numToStr/Comment.nvim",
  dependencies = {
    "JoosepAlviste/nvim-ts-context-commentstring",
  },
  config = function()
    -- Required setup for recent versions of the context plugin
    require('ts_context_commentstring').setup {
      enable_autocmd = false,
    }

    require("Comment").setup({
      -- Handles contextual comments (e.g. HTML inside PHP/JS)
      pre_hook = require("ts_context_commentstring.integrations.comment_nvim").create_pre_hook(),
    })
  end
}
