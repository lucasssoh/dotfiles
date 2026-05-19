return {
  -- 1. Le rendu visuel immersif dans le terminal
  {
    "MeanderingProgrammer/render-markdown.nvim",
    dependencies = { 
      "nvim-treesitter/nvim-treesitter", 
      "nvim-tree/nvim-web-devicons" 
    },
    ft = { "markdown" }, -- Lazy-load : s'active uniquement pour le Markdown
    config = function()
      require("render-markdown").setup({
        heading = {
          enabled = true,
          render_modes = true,
          sign = true,
          icons = { "󰲡 ", "󰲣 ", "󰲥 ", "󰲧 ", "󰲩 ", "󰲫 " },
          position = "overlay",
          signs = { "󰫎 " },
          width = "full",
          left_margin = 0,
          left_pad = 0,
          right_pad = 0,
          min_width = 0,
          border = false,
          backgrounds = {
            "RenderMarkdownH1Bg", "RenderMarkdownH2Bg", "RenderMarkdownH3Bg",
            "RenderMarkdownH4Bg", "RenderMarkdownH5Bg", "RenderMarkdownH6Bg",
          },
          foregrounds = {
            "RenderMarkdownH1", "RenderMarkdownH2", "RenderMarkdownH3",
            "RenderMarkdownH4", "RenderMarkdownH5", "RenderMarkdownH6",
          },
        },
        code = {
          enabled = true,
          render_modes = true,
          sign = true,
          style = "full",
          position = "left",
          language_pad = 0,
          language_name = true,
          disable_background = { "diff" },
          width = "full",
          left_margin = 0,
          left_pad = 0,
          right_pad = 0,
          min_width = 0,
          border = "thin",
          above = "▄",
          below = "▀",
          highlight = "RenderMarkdownCode",
          highlight_inline = "RenderMarkdownCodeInline",
        },
        checkbox = {
          enabled = true,
          render_modes = true,
          position = "inline",
          unchecked = { icon = "󰄱 ", highlight = "RenderMarkdownUnchecked" },
          checked = { icon = "󰱒 ", highlight = "RenderMarkdownChecked" },
          custom = {
            todo = { raw = "[-]", rendered = "󰗡 Todo", highlight = "RenderMarkdownTodo" },
          },
        },
        pipe_table = {
          enabled = true,
          render_modes = true,
          preset = "none",
          style = "full",
          cell = "padded",
          padding = 1,
          border = {
            "┌", "┬", "┐", "├", "┼", "┤", "└", "┴", "┘", "│", "─",
          },
        },
        callout = {
          note = { raw = "[!NOTE]", rendered = "󰋽 Note", highlight = "RenderMarkdownInfo" },
          tip = { raw = "[!TIP]", rendered = "󰌶 Tip", highlight = "RenderMarkdownSuccess" },
          warning = { raw = "[!WARNING]", rendered = "󰀪 Warning", highlight = "RenderMarkdownWarn" },
          caution = { raw = "[!CAUTION]", rendered = "󰳦 Caution", highlight = "RenderMarkdownError" },
          todo = { raw = "[!TODO]", rendered = "󰗡 Todo", highlight = "RenderMarkdownInfo" },
        },
      })
    end,
  },
}
