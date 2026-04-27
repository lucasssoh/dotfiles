local wezterm = require 'wezterm'
local config = wezterm.config_builder()

-- --- POLICE (FIN & ÉTROIT) ---
config.font = wezterm.font_with_fallback({
  {
    family = 'Iosevka NF',
    weight = 'Regular',
  },
})
config.font_size = 12.0
config.line_height = 1.0

config.front_end = "WebGpu" -- Plus moderne/fluide
config.freetype_load_target = "Light"
config.automatically_reload_config = true
-- --- APPARENCE ---
config.window_background_opacity = 0.90
config.macos_window_background_blur = 20 -- Active le flou (même sous Linux/Wayland)
config.window_decorations = "RESIZE" -- Look clean pour Hyprland
config.window_padding = { left = 2, right = 2, top = 2, bottom = 2 }
config.cursor_blink_rate = 1300

-- --- THÈME COULEURS (Humanoid Dark) ---
config.colors = {
  foreground = "#f8f8f2",
  background = "#111011",
  cursor_bg = "#ffffff", -- Ton curseur blanc
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
}

-- --- RACCOURCIS ---
config.disable_default_key_bindings = true -- On garde les bases
config.keys = {
  { key = 'c', mods = 'CTRL|SHIFT', action = wezterm.action.CopyTo 'Clipboard' },
  { key = 'v', mods = 'CTRL|SHIFT', action = wezterm.action.PasteFrom 'Clipboard' },
  { key = 'F5', mods = 'CTRL|SHIFT', action = wezterm.action.ReloadConfiguration },
}

return config
