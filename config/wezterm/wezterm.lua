local wezterm = require 'wezterm'
local config = wezterm.config_builder()
local act = wezterm.action

-- =========================
-- POLICE
-- =========================
config.font = wezterm.font_with_fallback({
  {
    family = 'Iosevka NF',
    weight = 'Regular',
  },
})

config.font_size = 12.0
config.line_height = 1.0

config.front_end = "OpenGL"
config.prefer_egl = true
config.freetype_load_target = "Light"
config.automatically_reload_config = true

-- =========================
-- APPARENCE
-- =========================
config.window_background_opacity = 0.90
config.macos_window_background_blur = 0
config.window_decorations = "NONE"
config.window_padding = { left = 4, right = 4, top = 2, bottom = 2 }

config.cursor_blink_rate = 1300
config.use_fancy_tab_bar = false

-- =========================
-- PANE FOCUS VISUAL (GRISAGE INACTIF)
-- =========================
config.inactive_pane_hsb = {
  saturation = 0.55,  -- désature les panes non focus
  brightness = 0.45,  -- les assombrit légèrement
}

-- =========================
-- COULEURS
-- =========================
config.colors = {
  foreground = "#f8f8f2",
  background = "#111011",

  cursor_bg = "#ffffff",

  selection_fg = "#f8f8f2",
  selection_bg = "#484e54",

  ansi = {
    "#232629", "#b0151a", "#028902", "#ffb400",
    "#0082c9", "#6d61a1", "#008b8b", "#f8f8f2",
  },

  brights = {
    "#484e54", "#b0151a", "#028902", "#ffb400",
    "#0082c9", "#6d61a1", "#008b8b", "#fcfcf6",
  },

  tab_bar = {
    background = "rgba(17, 16, 17, 0.75)",

    active_tab = {
      bg_color = "rgba(17, 16, 17, 0.92)",
      fg_color = "#f8f8f2",
    },

    inactive_tab = {
      bg_color = "rgba(10, 10, 10, 0.55)",
      fg_color = "#777777",
    },

    inactive_tab_hover = {
      bg_color = "rgba(30, 30, 30, 0.75)",
      fg_color = "#dddddd",
    },

    new_tab = {
      bg_color = "rgba(10, 10, 10, 0.85)",
      fg_color = "#666666",
    },

    new_tab_hover = {
      bg_color = "rgba(30, 30, 30, 0.75)",
      fg_color = "#ffffff",
    },
  },
}

-- =========================
-- RACCOURCIS
-- =========================
config.disable_default_key_bindings = true

config.keys = {

  -- Copy / Paste
  { key = 'c', mods = 'CTRL|SHIFT', action = act.CopyTo 'Clipboard' },
  { key = 'v', mods = 'CTRL|SHIFT', action = act.PasteFrom 'Clipboard' },

  -- Reload config
  { key = 'F5', mods = 'CTRL|SHIFT', action = act.ReloadConfiguration },

  -- =========================
  -- PANES (ALT+SHIFT + hjkl)
  -- =========================
  { key = 'h', mods = 'ALT|SHIFT', action = act.ActivatePaneDirection 'Left' },
  { key = 'j', mods = 'ALT|SHIFT', action = act.ActivatePaneDirection 'Down' },
  { key = 'k', mods = 'ALT|SHIFT', action = act.ActivatePaneDirection 'Up' },
  { key = 'l', mods = 'ALT|SHIFT', action = act.ActivatePaneDirection 'Right' },

  -- Split
  { key = 'v', mods = 'ALT|SHIFT', action = act.SplitVertical { domain = 'CurrentPaneDomain' } },
  { key = 's', mods = 'ALT|SHIFT', action = act.SplitHorizontal { domain = 'CurrentPaneDomain' } },

  -- Close pane
  { key = 'x', mods = 'ALT|SHIFT', action = act.CloseCurrentPane { confirm = false } },

  -- Resize panes
  { key = 'LeftArrow', mods = 'ALT|SHIFT', action = act.AdjustPaneSize { 'Left', 5 } },
  { key = 'RightArrow', mods = 'ALT|SHIFT', action = act.AdjustPaneSize { 'Right', 5 } },
  { key = 'UpArrow', mods = 'ALT|SHIFT', action = act.AdjustPaneSize { 'Up', 5 } },
  { key = 'DownArrow', mods = 'ALT|SHIFT', action = act.AdjustPaneSize { 'Down', 5 } },

  -- =========================
  -- TABS (simple cyclique)
  -- =========================
  { key = 't', mods = 'ALT|SHIFT', action = act.SpawnTab 'CurrentPaneDomain' },
  { key = 'w', mods = 'ALT|SHIFT', action = act.CloseCurrentTab { confirm = false } },

  { key = 'n', mods = 'ALT|SHIFT', action = act.ActivateTabRelative(1) },
  { key = 'p', mods = 'ALT|SHIFT', action = act.ActivateTabRelative(-1) },
}

return config
