-- Your WezTerm settings, over the author's. Reloaded on save.
-- Every key: https://wezterm.org/config/lua/config/
-- Uncomment a line to use it. The values shown are the author's.
--
-- Keys at the top apply in both modes; `light` and `dark` below apply only
-- when the desktop is in that mode. `colors` is merged key by key, `tab_bar` included.
local wezterm = require 'wezterm'

return {
  -- Font ---------------------------------------------------------------
  -- font = wezterm.font("Adwaita Mono"),
  -- Also installed:
  -- font = wezterm.font("JetBrains Mono"),
  -- font = wezterm.font("GoogleSansCode Nerd Font Mono"),
  -- font_size = 13.0,
  -- line_height = 1.0,
  -- harfbuzz_features = { "calt=0", "liga=0" },   -- no ligatures

  -- Window -------------------------------------------------------------
  -- window_background_opacity = 1.0,              -- below 1, the blur shows through
  -- window_padding = { left = 4, right = 4, top = 2, bottom = 2 },
  -- window_decorations = "NONE",                  -- "TITLE | RESIZE" for a frame
  -- initial_cols = 120,
  -- initial_rows = 32,

  -- Tab bar ------------------------------------------------------------
  -- enable_tab_bar = true,
  -- hide_tab_bar_if_only_one_tab = false,
  -- tab_bar_at_bottom = false,
  -- use_fancy_tab_bar = false,
  -- tab_max_width = 16,

  -- Cursor -------------------------------------------------------------
  -- default_cursor_style = "SteadyBlock",         -- SteadyBar, BlinkingUnderline…
  -- cursor_blink_rate = 0,

  -- Panes --------------------------------------------------------------
  -- inactive_pane_hsb = { saturation = 1.0, brightness = 1.0 },

  -- Shell --------------------------------------------------------------
  -- default_prog = { "/usr/bin/fish", "-l" },
  -- scrollback_lines = 3500,

  -- Keys ---------------------------------------------------------------
  -- A `keys` list replaces all of the author's keys.
  -- keys = { { key = "t", mods = "CTRL|SHIFT", action = wezterm.action.SpawnTab "CurrentPaneDomain" } },

  -- Colours, one scheme for both modes ---------------------------------
  -- Replaces the author's colours. Names: https://wezterm.org/colorschemes/
  -- color_scheme = "Catppuccin Mocha",

  -- Colours per mode ---------------------------------------------------
  light = {
    -- color_scheme = "Catppuccin Latte",
    -- window_background_opacity = 0.9,
    colors = {
      -- foreground = "#1c1c1e",
      -- background = "#f5f3ee",
      -- cursor_bg = "#1c1c1e",
      -- cursor_fg = "#f5f3ee",
      -- selection_fg = "#1c1c1e",
      -- selection_bg = "#dedad2",
      -- split = "#c4c3be",
      -- ansi    = { "#1c1c1e", "#b3261e", "#24692a", "#6e5c0f", "#1d6386", "#6b4a96", "#006b75", "#86868b" },
      -- brights = { "#56565b", "#c4473f", "#2f7d36", "#875000", "#1f56b8", "#7d5aa8", "#2b7a82", "#c4c3be" },
      -- tab_bar = {                                -- follows background by default
      --   active_tab = { bg_color = "#dbd9d5", fg_color = "#1c1c1e" },
      --   inactive_tab = { fg_color = "#86868b" },
      -- },
    },
  },
  dark = {
    -- color_scheme = "Catppuccin Mocha",
    -- window_background_opacity = 0.6,
    colors = {
      -- foreground = "#e8e8e3",
      -- background = "#101010",
      -- cursor_bg = "#ffffff",
      -- selection_fg = "#e8e8e3",
      -- selection_bg = "#484e54",
      -- split = "#605b51",
      -- ansi    = { "#232629", "#b0151a", "#028902", "#ffb400", "#0082c9", "#6d61a1", "#008b8b", "#f8f8f2" },
      -- brights = { "#484e54", "#b0151a", "#028902", "#ffb400", "#0082c9", "#6d61a1", "#008b8b", "#fcfcf6" },
      -- tab_bar = {                                -- follows background by default
      --   active_tab = { bg_color = "#2b2b2a", fg_color = "#e8e8e3" },
      --   inactive_tab = { fg_color = "#7c7c80" },
      -- },
    },
  },
}
