-- ============================================================
-- THEME.LUA
-- ============================================================
local themes_path = vim.fn.stdpath("config") .. "/lua/themes"
local cache_file  = vim.fn.stdpath("data") .. "/theme.txt"
local themes = {}

for _, file in ipairs(vim.fn.readdir(themes_path)) do
    local name = file:match("^(.+)%.lua$")
    if name then
        themes[name] = "themes." .. name
    end
end

-- The cache holds three lines: the theme, the surface (default, black or
-- transparent) and the scheme (auto, light or dark). Two settings that
-- used to share the second line: `light` there meant "light, opaque".
-- A file from then still reads the same.
local function load_saved_theme()
    local f = io.open(cache_file, "r")
    if f then
        local name   = f:read("*l")
        local bg     = f:read("*l") or "default"
        local scheme = f:read("*l")
        f:close()
        if not scheme then
            scheme = (bg == "light") and "light" or "dark"
        end
        if bg == "light" then
            bg = "default"
        end
        if name and themes[name] then
            return name, bg, scheme
        end
    end
    return "melange", "default", "auto"
end

-- The desktop's scheme, as WezTerm reads it too (org.gnome.desktop.interface
-- color-scheme is what the portal serves). ~7 ms, once at startup and then
-- only when the monitor below says it changed. Dark when there is no
-- desktop to ask (SSH, a tty).
local function system_background()
    local ok, res = pcall(function()
        return vim.system({ "gsettings", "get", "org.gnome.desktop.interface", "color-scheme" }, { text = true }):wait()
    end)
    if not ok or res.code ~= 0 then
        return "dark"
    end
    return res.stdout:match("prefer%-dark") and "dark" or "light"
end

local function resolve_background(scheme)
    if scheme == "light" or scheme == "dark" then
        return scheme
    end
    return system_background()
end

local active_bg = "default"
local active_name, active_scheme = nil, "auto"

-- Relative luminance of a highlight colour. nvim_get_hl hands colours back
-- as 0xRRGGBB integers; strings are accepted too so the helper stays usable
-- from the palette-style call sites.
local function luminance(color)
    if type(color) == "string" then
        color = tonumber((color:gsub("^#", "")), 16)
    end
    if type(color) ~= "number" then
        return nil
    end

    local function channel(c)
        c = c / 255
        return c <= 0.04045 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4
    end

    local r = math.floor(color / 0x10000) % 0x100
    local g = math.floor(color / 0x100) % 0x100
    local b = color % 0x100
    return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
end

-- Selection is a highlight, not a surface: without its background there is
-- no way left to tell what is selected. Everything else is fair game.
local keep_bg = {
    Visual = true,
    VisualNOS = true,
}

-- coucou marks the active tab with a pill (lua/plugins/bufferline.lua):
-- every bufferline group of the selected tab, its file-type icon
-- included (BufferLineDevIconLuaSelected…), keeps that fill. Other
-- themes paint their selected tab like the editor, so clearing it there
-- is still right.
local function keep(name)
    return keep_bg[name]
        or (vim.g.colors_name == "coucou" and name:match("^BufferLine.*Selected$") ~= nil)
end

-- Remove every panel/surface background instead of patching a fixed list of
-- groups, so the whole UI lets the terminal's own translucency through --
-- nvim-tree, statusline, tabline, floats, popups, lualine, plugins.
--
-- Surfaces are recognised by luminance rather than by name: the editor's
-- backgrounds are dark in a dark colourscheme and light in a light one,
-- while accent blocks (search, popup selection, mode indicators, cursor)
-- sit at the opposite end. That keeps working for any installed theme
-- without listing every group each one defines.
local function clear_backgrounds()
    if active_bg ~= "transparent" then
        return
    end

    local dark = vim.o.background ~= "light"

    local function is_surface(color)
        local l = luminance(color)
        if not l then
            return false
        end
        return dark and l < 0.2 or (not dark and l > 0.6)
    end

    for name, attrs in pairs(vim.api.nvim_get_hl(0, {})) do
        -- Linked groups follow their target, which is handled on its own.
        if not attrs.link and not attrs.reverse and not keep(name) and is_surface(attrs.bg) then
            local hl = vim.deepcopy(attrs)
            hl.bg = nil
            hl.ctermbg = nil
            -- Copying the definition would keep `default = true` (bufferline
            -- sets it on every group), and nvim_set_hl would then refuse to
            -- override the very group we are trying to change.
            hl.default = nil
            -- A dark-on-dark group (separator, group label) would become
            -- invisible once its background goes away: use Normal's
            -- foreground instead of keeping a colour nothing can read.
            if is_surface(attrs.fg) then
                hl.fg = nil
                hl.ctermfg = nil
            end
            pcall(vim.api.nvim_set_hl, 0, name, hl)
        end
    end
end

-- Some plugin groups only come into existence when the screen is first
-- drawn (lualine's section transitions, bufferline's icon highlights), so a
-- single synchronous pass leaves them opaque. Run once now and again shortly
-- after the first redraw; by then those groups are cached and the second pass
-- is what sticks.
local function apply_transparency()
    clear_backgrounds()
    vim.schedule(clear_backgrounds)
    vim.defer_fn(clear_backgrounds, 250)
end

local function apply_bg(bg)
    if bg == "transparent" then
        apply_transparency()
        return
    end

    local color = nil
    if bg == "black" then
        color = "#000000"
    else
        return
    end

    local groups = {
        "Normal",
        "NormalNC",
        "EndOfBuffer",
        "LineNr",
        "LineNrAbove",
        "LineNrBelow",
        -- Nvim-tree
        "NvimTreeNormal",
        "NvimTreeNormalNC",
        "NvimTreeEndOfBuffer",
        "NvimTreeWinSeparator",
    }

    for _, group in ipairs(groups) do
        vim.api.nvim_set_hl(0, group, { bg = color })
    end
end

local function apply_theme(name, bg, scheme)
    active_bg = bg or "default"
    active_name = name
    active_scheme = scheme or "auto"
    -- Read by lualine's coucou theme so its b/c segments are born
    -- transparent instead of being painted and then cleared.
    vim.g.theme_bg = active_bg

    -- Set before colorscheme() so a theme's colors/*.lua can branch on
    -- vim.o.background (used by coucou's dark/light palette switch).
    vim.o.background = resolve_background(active_scheme)

    local ok, err = pcall(vim.cmd.colorscheme, name)
    if not ok then
        print("Error applying theme: " .. err)
        return
    end
    -- Fire the plugins' own ColorScheme handlers first, then clear: several
    -- of them (bufferline, coucou) rebuild their groups from that event.
    vim.cmd("doautocmd ColorScheme")
    apply_bg(active_bg)
end

local function save_theme(name, bg, scheme)
    local f = io.open(cache_file, "w")
    if f then
        f:write(name .. "\n" .. (bg or "default") .. "\n" .. (scheme or "auto"))
        f:close()
    end
end

-- In `auto`, follow the desktop while nvim runs: `gsettings monitor` blocks
-- until the setting changes, so nothing runs between two switches (the same
-- watcher as wallpaper-follow-scheme). A job, not vim.system: nvim stops its
-- jobs when it exits, so no monitor outlives the editor.
local follow_job = nil

local function follow_system(on)
    if not on then
        if follow_job then
            pcall(vim.fn.jobstop, follow_job)
            follow_job = nil
        end
        return
    end
    if follow_job or vim.fn.executable("gsettings") == 0 or #vim.api.nvim_list_uis() == 0 then
        return
    end
    follow_job = vim.fn.jobstart({ "gsettings", "monitor", "org.gnome.desktop.interface", "color-scheme" }, {
        on_stdout = function(_, lines)
            for _, line in ipairs(lines) do
                if line:find("color-scheme", 1, true) then
                    local bg = line:match("prefer%-dark") and "dark" or "light"
                    if active_scheme == "auto" and active_name and bg ~= vim.o.background then
                        apply_theme(active_name, active_bg, "auto")
                    end
                end
            end
        end,
        on_exit = function()
            follow_job = nil
        end,
    })
    if follow_job <= 0 then
        follow_job = nil
    end
end

-- :SetTheme [--auto|--light|--dark] [--bg=default|black|transparent] <theme>
-- A flag left out keeps its current value.
vim.api.nvim_create_user_command("SetTheme", function(opts)
    local bg     = active_bg
    local scheme = active_scheme
    local name   = nil

    for _, arg in ipairs(vim.split(opts.args, "%s+")) do
        local flag = arg:match("^%-%-(%a+)$")
        if flag == "auto" or flag == "light" or flag == "dark" then
            scheme = flag
        else
            local val = arg:match("^%-%-bg=(.+)$")
            if val == "light" then
                -- What --bg=light meant before the scheme had its own flag.
                scheme = "light"
            elseif val then
                if val ~= "black" and val ~= "transparent" and val ~= "default" then
                    print("Unknown bg: " .. val .. " (available: default, black, transparent)")
                    return
                end
                bg = val
            else
                name = arg
            end
        end
    end

    if not name then
        print("Usage: SetTheme [--auto|--light|--dark] [--bg=default|black|transparent] <theme>")
        return
    end

    if not themes[name] then
        local available = table.concat(vim.tbl_keys(themes), ", ")
        print("Unknown theme: " .. name .. " (available: " .. available .. ")")
        return
    end

    apply_theme(name, bg, scheme)
    save_theme(name, bg, scheme)
    follow_system(scheme == "auto")
    print("Theme applied: " .. name .. " (" .. scheme .. ", bg: " .. bg .. ")")
end, {
    nargs = "+",
    complete = function(arglead)
        local flags = { "--auto", "--light", "--dark", "--bg=default", "--bg=black", "--bg=transparent" }
        if arglead:match("^%-") then
            return vim.tbl_filter(function(f) return vim.startswith(f, arglead) end, flags)
        end
        local names = vim.tbl_keys(themes)
        table.sort(names)
        return vim.tbl_filter(function(n) return vim.startswith(n, arglead) end, names)
    end,
})

-- Startup: load the saved theme + bg
local saved_name, saved_bg, saved_scheme = load_saved_theme()
active_bg = saved_bg
active_name = saved_name
active_scheme = saved_scheme
vim.g.theme_bg = active_bg

-- Set before the active theme's colorscheme() runs below (lazy.nvim's
-- config() for the priority=1000 spec fires synchronously inside
-- require("lazy").setup(), which happens after this module returns —
-- so this assignment lands in time for colors/*.lua to see it).
vim.o.background = resolve_background(saved_scheme)

-- A bare :colorscheme (or one that reloads itself) repaints backgrounds
-- from scratch; reapply transparency after it when that is the active mode.
vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("ThemeTransparency", { clear = true }),
    callback = function()
        if active_bg == "transparent" then
            apply_transparency()
        end
    end,
})

vim.api.nvim_create_autocmd("VimEnter", {
    once = true,
    callback = function()
        apply_bg(saved_bg)
        follow_system(saved_scheme == "auto")
    end,
})

-- Cover plugins that finish loading after startup (VeryLazy and later).
vim.api.nvim_create_autocmd("User", {
    pattern = { "LazyDone", "VeryLazy" },
    callback = function()
        if active_bg == "transparent" then
            vim.schedule(clear_backgrounds)
        end
    end,
})

local specs = {}
for name, module in pairs(themes) do
    local ok, spec = pcall(require, module)
    if ok then
        spec.lazy = false
        if name ~= saved_name then
            spec.config = nil
            spec.priority = nil
        else
            spec.priority = 1000
        end
        table.insert(specs, spec)
    end
end

return specs
