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

    -- Handles contextual comments (e.g. HTML inside PHP/JS)
    local ts_hook = require("ts_context_commentstring.integrations.comment_nvim").create_pre_hook()

    require("Comment").setup({
      -- Repli sur le commentstring du filetype quand le hook ne trouve rien.
      -- Sans parser treesitter pour la langue, le hook rend nil, et Comment
      -- tente alors son propre calcul treesitter, qui casse sur nvim 0.12
      -- (get_parser rend nil au lieu de lever une erreur) : rien n'etait
      -- commente, juste "[Comment.nvim] nil". C'etait le cas de Rust.
      pre_hook = function(ctx)
        return ts_hook(ctx) or vim.bo.commentstring
      end,
    })
  end
}
