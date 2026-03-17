local wezterm = require 'wezterm'
local config = {}

-- --- APPARENCE (On garde tes réglages) ---
config.window_background_opacity = 0.85
config.kde_window_background_blur = true 
config.font = wezterm.font { family = 'JetBrainsMono Nerd Font', weight = 'Bold' }
config.font_size = 11.0
config.color_scheme = 'Hyper'

-- --- MULTIPLEXAGE & INTERFACE ---
config.enable_tab_bar = true
config.hide_tab_bar_if_only_one_tab = true
-- On ne met PAS de window_decorations pour garder celles du DE

config.inactive_pane_hsb = {
  saturation = 0.2,
  brightness = 0.8,
}


-- --- RACCOURCIS POUR LES PANNEAUX (MULTIPLEXING) ---
config.keys = {
  -- Diviser verticalement (Split vertical)
  { key = 'v', mods = 'ALT', action = wezterm.action.SplitVertical({ domain = 'CurrentPaneDomain' }) },
  -- Diviser horizontalement (Split horizontal)
  { key = 'h', mods = 'ALT', action = wezterm.action.SplitHorizontal({ domain = 'CurrentPaneDomain' }) },
  -- Fermer le panneau actuel
  { key = 'x', mods = 'ALT', action = wezterm.action.CloseCurrentPane({ confirm = true }) },
  -- Naviguer entre les panneaux avec ALT + Flèches
  { key = 'LeftArrow',  mods = 'ALT', action = wezterm.action.ActivatePaneDirection('Left') },
  { key = 'RightArrow', mods = 'ALT', action = wezterm.action.ActivatePaneDirection('Right') },
  { key = 'UpArrow',    mods = 'ALT', action = wezterm.action.ActivatePaneDirection('Up') },
  { key = 'DownArrow',  mods = 'ALT', action = wezterm.action.ActivatePaneDirection('Down') },

-- REDIMENSIONNER (Resizing) avec SHIFT + ALT + Flèches
  -- On utilise un pas de 5 pour que ça aille assez vite
  { key = 'LeftArrow',  mods = 'SHIFT|ALT', action = wezterm.action.AdjustPaneSize({ 'Left', 5 }) },
  { key = 'RightArrow', mods = 'SHIFT|ALT', action = wezterm.action.AdjustPaneSize({ 'Right', 5 }) },
  { key = 'UpArrow',    mods = 'SHIFT|ALT', action = wezterm.action.AdjustPaneSize({ 'Up', 5 }) },
  { key = 'DownArrow',  mods = 'SHIFT|ALT', action = wezterm.action.AdjustPaneSize({ 'Down', 5 }) },

  -- Le Zoom (ALT + Z) reste super utile pour isoler un terminal
  { key = 'z', mods = 'ALT', action = wezterm.action.TogglePaneZoomState },
}

return config