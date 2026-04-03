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

local function load_saved_theme()
    local f = io.open(cache_file, "r")
    if f then
        local name = f:read("*l")
        local bg   = f:read("*l")
        f:close()
        if name and themes[name] then
            return name, bg or "default"
        end
    end
    return "melange", "default"
end

local function apply_bg(bg)
    local color = nil
    if bg == "black" then
        color = "#000000"
    elseif bg == "transparent" then
        color = "NONE"
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

local function apply_theme(name, bg)
    local ok, err = pcall(vim.cmd.colorscheme, name)
    if not ok then
        print("Error applying theme: " .. err)
        return
    end
    apply_bg(bg or "default")
    vim.cmd("doautocmd ColorScheme")
end

local function save_theme(name, bg)
    local f = io.open(cache_file, "w")
    if f then
        f:write(name .. "\n" .. (bg or "default"))
        f:close()
    end
end

vim.api.nvim_create_user_command("SetTheme", function(opts)
    local bg   = "default"
    local name = nil

    for _, arg in ipairs(vim.split(opts.args, "%s+")) do
        local val = arg:match("^%-%-bg=(.+)$")
        if val then
            if val ~= "black" and val ~= "transparent" and val ~= "default" then
                print("Unknown bg: " .. val .. " (available: black, transparent, default)")
                return
            end
            bg = val
        else
            name = arg
        end
    end

    if not name then
        print("Usage: SetTheme [--bg=black|transparent|default] <theme>")
        return
    end

    if not themes[name] then
        local available = table.concat(vim.tbl_keys(themes), ", ")
        print("Unknown theme: " .. name .. " (available: " .. available .. ")")
        return
    end

    apply_theme(name, bg)
    save_theme(name, bg)
    print("Theme applied: " .. name .. " (bg: " .. bg .. ")")
end, {
    nargs = "+",
    complete = function(arglead, cmdline, cursorpos)
        if arglead:match("^%-%-bg") then
            return { "--bg=black", "--bg=transparent", "--bg=default" }
        end

        if cmdline:match("%-%-bg=%S+") then
            return vim.tbl_keys(themes)
        end

        local results = { "--bg=black", "--bg=transparent", "--bg=default" }
        for name in pairs(themes) do
            table.insert(results, name)
        end
        return results
    end,
})

-- Démarrage : charge le thème + bg sauvegardés
local saved_name, saved_bg = load_saved_theme()

vim.api.nvim_create_autocmd("VimEnter", {
    once = true,
    callback = function()
        apply_bg(saved_bg)
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
