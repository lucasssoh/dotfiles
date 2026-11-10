local wezterm = require 'wezterm'
local config = wezterm.config_builder()
local act = wezterm.action

-- =========================
-- FONT
-- =========================
config.font = wezterm.font_with_fallback({
  {
    family = 'GoogleSansCode Nerd Font Mono', 
--[[     family = 'JetBrains Mono', ]]
    weight = 'Regular',
  },
})
-- 13.0, not 12.0: sized for a 14" 1920x1200 panel (~162 DPI) at scale 1.
-- The previous 12.0 was tuned on a 15.6" 1920x1080 (~143 DPI), where the
-- same point size renders ~13% larger physically. Point sizes are
-- resolution-independent, not DENSITY-independent -- moving to a denser
-- panel at the same compositor scale shrinks the text on screen.
config.font_size = 13.0
config.line_height = 1.0
config.front_end = "OpenGL"
config.prefer_egl = true
config.freetype_load_target = "Light"
config.automatically_reload_config = true

-- =========================
-- APPEARANCE
-- =========================
-- Light or dark, following the desktop (the portal's color-scheme, the bar's
-- toggle). WezTerm re-reads this file by itself when it changes. wezterm.gui
-- is absent when the config is read outside the GUI (the CLI, the mux).
local light = wezterm.gui ~= nil and wezterm.gui.get_appearance():find("Light") ~= nil

-- In dark, a 40% black veil: the blur behind already darkens the wallpaper.
-- In light, a cream veil can't stay that thin: over a dark wallpaper (one
-- with no light version stays dark in light mode) dark text would sink.
-- 85% holds on every wallpaper and looks the same whatever is behind.
config.window_background_opacity = light and 0.85 or 0.4
config.macos_window_background_blur = 0
config.window_decorations = "NONE"
config.window_padding = { left = 4, right = 4, top = 2, bottom = 2 }
config.cursor_blink_rate = 0
config.use_fancy_tab_bar = false

-- Cursor smear (wezterm PR #7737, not in upstream yet; `cc-pkg-mng wezterm
-- smear` builds it). config_builder raises on unknown keys, so the pcall
-- keeps the packaged build working. Frames are only redrawn during a jump,
-- nothing when idle.
--
-- 0.08 s, not the 0.15 default: the corners ease out exponentially, so the
-- tail of a long jump takes about 2.3x the duration to land -- ~350 ms at
-- 0.15, which dragged. ~180 ms now.
--
-- The variable is set only when the key exists: nvim's smear-cursor.nvim
-- (nvim/lua/cursor.lua) stands down on it, and stays on everywhere else.
if pcall(function()
  config.cursor_smear = true
  config.cursor_animation_duration = 0.08
end) then
  config.set_environment_variables = { WEZTERM_CURSOR_SMEAR = '1' }
end

-- =========================
-- PANE FOCUS VISUAL
-- =========================
config.inactive_pane_hsb = {
  saturation = 0.9,
  brightness = 1.0,
}

-- =========================
-- COLORS
-- =========================
-- The tab bar is painted with its own colours, not with the window's
-- background and its opacity. Its tones are therefore derived from those two
-- values: the bar is exactly as see-through as the terminal, so the
-- compositor's blur shows through it too, and it follows any change to
-- window_background_opacity. The active tab is a denser veil of the same
-- colour (black in dark, cream in light): a white one over black turns
-- opaque cream, as WezTerm does not blend it.
local background = light and "#f5f3ee" or "#000000"
local function veil(extra)
  local r, g, b = background:match("#(%x%x)(%x%x)(%x%x)")
  local alpha = math.min(1, config.window_background_opacity + extra)
  return string.format("rgba(%d, %d, %d, %.2f)",
    tonumber(r, 16), tonumber(g, 16), tonumber(b, 16), alpha)
end

local function tab_bar(ink, dim, hover)
  return {
    background = veil(0),
    active_tab = { bg_color = veil(0.18), fg_color = ink },
    inactive_tab = { bg_color = veil(0), fg_color = dim },
    inactive_tab_hover = { bg_color = veil(0.08), fg_color = hover },
    new_tab = { bg_color = veil(0), fg_color = dim },
    new_tab_hover = { bg_color = veil(0.08), fg_color = ink },
  }
end

if light then
  -- The shell's light inks (quickshell/bar/theme/DrawerTheme.qml), the same
  -- as nvim's coucou light: neutral greys, the cream panel, dark accents.
  config.colors = {
    foreground = "#1c1c1e",
    background = background,
    cursor_bg = "#1c1c1e",
    cursor_fg = "#f5f3ee",
    cursor_border = "#1c1c1e",
    selection_fg = "#1c1c1e",
    selection_bg = "#dedad2",
    split = "#c4c3be",
    ansi = {
      "#1c1c1e", "#b3261e", "#24692a", "#6e5c0f",
      "#1d6386", "#6b4a96", "#006b75", "#86868b",
    },
    brights = {
      "#56565b", "#c4473f", "#2f7d36", "#875000",
      "#1f56b8", "#7d5aa8", "#2b7a82", "#c4c3be",
    },
    tab_bar = tab_bar("#1c1c1e", "#86868b", "#3f3f44"),
  }
else
  config.colors = {
    foreground = "#f8f8f2",
    background = background,
    cursor_bg = "#ffffff",
    selection_fg = "#f8f8f2",
    selection_bg = "#484e54",
    split = "#605b51",
    ansi = {
      "#232629", "#b0151a", "#028902", "#ffb400",
      "#0082c9", "#6d61a1", "#008b8b", "#f8f8f2",
    },
    brights = {
      "#484e54", "#b0151a", "#028902", "#ffb400",
      "#0082c9", "#6d61a1", "#008b8b", "#fcfcf6",
    },
    tab_bar = tab_bar("#f8f8f2", "#8a8a8a", "#dddddd"),
  }
end

-- =========================
-- SHORTCUTS
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
  { key = 'LeftArrow',  mods = 'ALT|SHIFT', action = act.AdjustPaneSize { 'Left', 5 } },
  { key = 'RightArrow', mods = 'ALT|SHIFT', action = act.AdjustPaneSize { 'Right', 5 } },
  { key = 'UpArrow',    mods = 'ALT|SHIFT', action = act.AdjustPaneSize { 'Up', 5 } },
  { key = 'DownArrow',  mods = 'ALT|SHIFT', action = act.AdjustPaneSize { 'Down', 5 } },
  -- =========================
  -- TABS
  -- =========================
  { key = 't', mods = 'ALT|SHIFT', action = act.SpawnTab 'CurrentPaneDomain' },
  { key = 'w', mods = 'ALT|SHIFT', action = act.CloseCurrentTab { confirm = false } },
  { key = 'n', mods = 'ALT|SHIFT', action = act.ActivateTabRelative(1) },
  { key = 'p', mods = 'ALT|SHIFT', action = act.ActivateTabRelative(-1) },

  -- =========================
  -- Wezterm copy
  -- =========================
  { key = "Escape", mods = "CTRL",action = act.ActivateCopyMode,},
  -- =========================
  -- Font zoom (Ctrl+0 to reset, mirrors browser/VSCode convention)
  -- =========================
  { key = '0', mods = 'CTRL', action = act.ResetFontSize },
}

-- Ctrl+Scroll to zoom font size — not bound by default in wezterm.
-- mouse_bindings extends the builtin mouse bindings (click/drag select,
-- right-click paste, ...) rather than replacing them, so this is additive.
config.mouse_bindings = {
  {
    event = { Down = { streak = 1, button = { WheelUp = 1 } } },
    mods = 'CTRL',
    action = act.IncreaseFontSize,
  },
  {
    event = { Down = { streak = 1, button = { WheelDown = 1 } } },
    mods = 'CTRL',
    action = act.DecreaseFontSize,
  },
}

wezterm.on('format-tab-title', function(tab, panes, tabs, hover, max_width)
  local pane = tab.active_pane
  return string.format(' tab %d:%d ', tab.tab_index + 1, pane.pane_id)
end)

config.key_tables = {
  copy_mode = {
    { key = "h", mods = "NONE", action = act.CopyMode "MoveLeft" },
    { key = "j", mods = "NONE", action = act.CopyMode "MoveDown" },
    { key = "k", mods = "NONE", action = act.CopyMode "MoveUp" },
    { key = "l", mods = "NONE", action = act.CopyMode "MoveRight" },

    { key = "v", mods = "NONE", action = act.CopyMode { SetSelectionMode = "Cell" } },
    { key = "y", mods = "NONE", action = act.CopyTo "ClipboardAndPrimarySelection" },
    { key = "/", mods = "NONE", action = act.Search "CurrentSelectionOrEmptyString" },
  }
}

return config
