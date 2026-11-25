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

-- Opaque by default, a plain dark or light terminal. A
-- window_background_opacity below 1 in local.lua lets the compositor's
-- blur show through, the tab bar included.
config.window_background_opacity = 1.0
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
-- background and its opacity. They are derived from those two once
-- local.lua has had its say (see the end of this file): the bar is as
-- see-through as the terminal, and the active tab a step toward the ink.
local background = light and "#f5f3ee" or "#0a0a0a"
local tab_inks = light and { "#1c1c1e", "#86868b", "#3f3f44" }
                        or { "#e8e8e3", "#7c7c80", "#c8c8c4" }

local function rgb(hex)
  local r, g, b = tostring(hex):match("^#(%x%x)(%x%x)(%x%x)")
  if not r then return nil end
  return { tonumber(r, 16), tonumber(g, 16), tonumber(b, 16) }
end

local function tab_bar(bg, alpha)
  local base = rgb(bg) or rgb(background)
  local ink = rgb(tab_inks[1])
  local function tone(f)
    return string.format("rgba(%d, %d, %d, %.2f)",
      math.floor(base[1] + (ink[1] - base[1]) * f + 0.5),
      math.floor(base[2] + (ink[2] - base[2]) * f + 0.5),
      math.floor(base[3] + (ink[3] - base[3]) * f + 0.5),
      alpha)
  end
  return {
    background = tone(0),
    -- Active tab blends with the terminal below (no colour step); inactive
    -- tabs stay slightly shaded so the active one reads as framed.
    active_tab = { bg_color = tone(0), fg_color = tab_inks[1] },
    inactive_tab = { bg_color = tone(0.08), fg_color = tab_inks[2] },
    inactive_tab_hover = { bg_color = tone(0.04), fg_color = tab_inks[3] },
    new_tab = { bg_color = tone(0), fg_color = tab_inks[2] },
    new_tab_hover = { bg_color = tone(0.04), fg_color = tab_inks[1] },
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
  }
else
  config.colors = {
    foreground = "#e8e8e3",
    background = background,
    cursor_bg = "#ffffff",
    selection_fg = "#e8e8e3",
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
  { key = 'b', mods = 'ALT|SHIFT', action = act.ActivateTabRelative(-1) },

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

wezterm.on('format-tab-title', function(tab, tabs, panes, config, hover, max_width)
  local pane = tab.active_pane
  local num = string.format('%d', pane.pane_id)
  local title = num
  -- Aerate the left side of the tab bar: push the first tab a bit right.
  if tab.tab_index == 0 then
    title = '      ' .. title
  end
  return ' ' .. title .. ' '
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

-- Your own settings: ~/.config/wezterm/local.lua, a link to
-- config/wezterm/local.lua in the repo. It returns a table of config keys
-- (https://wezterm.org/config/lua/config/), for both modes, with optional
-- `light` and `dark` tables applied over it in that mode only; or a
-- function(config, wezterm, light). A `colors` table is merged key by key;
-- a `color_scheme` drops the author's colours.
-- wezterm.lua and local.lua are links into the repo: an editor saves the
-- file they point to, and a watch on the link alone never hears it.
local function watch_real(path)
  wezterm.add_to_config_reload_watch_list(path)
  local p = io.popen('readlink -f "' .. path .. '"')
  if not p then return end
  local real = p:read("*l")
  p:close()
  if real and real ~= "" and real ~= path then
    wezterm.add_to_config_reload_watch_list(real)
  end
end
if wezterm.config_file then watch_real(wezterm.config_file) end

local local_path = os.getenv("HOME") .. "/.config/wezterm/local.lua"
local user_tab_bar = {}
local f = io.open(local_path, "r")
if f then
  f:close()
  watch_real(local_path)

  local function set(k, v)
    local ok, err = pcall(function() config[k] = v end)
    if not ok then wezterm.log_error("local.lua: " .. tostring(err)) end
  end
  -- Tables merge key by key (tab_bar keeps what you leave out); lists
  -- such as ansi replace.
  local function merge(dst, src)
    for k, v in pairs(src) do
      if type(v) == "table" and type(dst[k]) == "table" and #v == 0 then
        merge(dst[k], v)
      else
        dst[k] = v
      end
    end
  end
  local function apply(t)
    if type(t.colors) == "table" and type(t.colors.tab_bar) == "table" then
      merge(user_tab_bar, t.colors.tab_bar)
    end
    if t.color_scheme ~= nil and t.colors == nil then set("colors", nil) end
    for k, v in pairs(t) do
      if k == "light" or k == "dark" then
        -- applied after
      elseif k == "colors" and type(v) == "table" and type(config.colors) == "table" then
        local colors = config.colors
        for ck, cv in pairs(v) do
          if ck ~= "tab_bar" then
            if type(cv) == "table" and type(colors[ck]) == "table" and #cv == 0 then
              merge(colors[ck], cv)
            else
              colors[ck] = cv
            end
          end
        end
        set("colors", colors)
      else
        set(k, v)
      end
    end
  end

  local ok, user = pcall(dofile, local_path)
  if not ok then
    wezterm.log_error("local.lua: " .. tostring(user))
  elseif type(user) == "function" then
    local ok2, err = pcall(user, config, wezterm, light)
    if not ok2 then wezterm.log_error("local.lua: " .. tostring(err)) end
  elseif type(user) == "table" then
    apply(user)
    local mode = light and user.light or user.dark
    if type(mode) == "table" then apply(mode) end
  end
end

-- The tab bar, from the final background and opacity, under what
-- local.lua gave for it.
if type(config.colors) == "table" then
  local colors = config.colors
  local bar = tab_bar(colors.background, config.window_background_opacity or 1)
  local function deep(dst, src)
    for k, v in pairs(src) do
      if type(v) == "table" and type(dst[k]) == "table" then deep(dst[k], v) else dst[k] = v end
    end
  end
  deep(bar, user_tab_bar)
  colors.tab_bar = bar
  config.colors = colors
end

return config
