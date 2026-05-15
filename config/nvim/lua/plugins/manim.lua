-- config/nvim/lua/plugins/manim.lua
local M = {}
local augroup = vim.api.nvim_create_augroup("ManimAutoRender", { clear = true })

-- ── Helpers ──────────────────────────────────────────────────────────────────

local function get_wezterm_panes()
    local raw = vim.fn.system("wezterm cli list --format json 2>/dev/null")
    if vim.v.shell_error ~= 0 or raw == "" then return {} end
    local ok, parsed = pcall(vim.json.decode, raw)
    if not ok or type(parsed) ~= "table" then return {} end
    local panes = {}
    for _, entry in ipairs(parsed) do
        if entry.pane_id ~= nil then
            table.insert(panes, tostring(entry.pane_id))
        end
    end
    return panes
end

local function get_manim_classes()
    local filepath = vim.fn.expand("%:p")
    if filepath == "" then return {} end
    local classes = {}
    for _, line in ipairs(vim.fn.readfile(filepath)) do
        local cls = line:match("^class%s+(%w+)%s*%(.*Scene.*%)")
        if cls then
            table.insert(classes, cls)
        end
    end
    return classes
end

local function complete(arg_lead, cmd_line, _)
    local args = vim.split(cmd_line, "%s+", { trimempty = true })
    local n = #args
    if n < 3 or (n == 2 and arg_lead ~= "") then
        local panes = get_wezterm_panes()
        return vim.tbl_filter(function(p)
            return p:find(arg_lead, 1, true)
        end, panes)
    end
    local classes = get_manim_classes()
    return vim.tbl_filter(function(c)
        return c:find(arg_lead, 1, true)
    end, classes)
end

-- ── Core ─────────────────────────────────────────────────────────────────────

local function render_and_display(viewer_pane, class_name)
    local filepath = vim.fn.expand("%:p")
    local filename_no_ext = vim.fn.expand("%:t:r")
    local gif_dir = vim.fn.getcwd()
        .. string.format("/media/videos/%s/480p15/", filename_no_ext)

    local manim_bin = vim.fn.expand("~/.local/bin/manim")
    if vim.fn.executable(manim_bin) ~= 1 then
        vim.notify("manim not found in ~/.local/bin/", vim.log.levels.ERROR)
        return
    end

    vim.notify(string.format("Rendering [%s] -> pane %s", class_name, viewer_pane), vim.log.levels.INFO)

    local render_cmd = string.format(
        "%s -ql --format gif %s %s",
        manim_bin, vim.fn.shellescape(filepath), class_name
    )

    vim.fn.jobstart({ "bash", "-c", render_cmd }, {
        detach = false,
        on_exit = function(_, code)
            if code ~= 0 then
                vim.notify(
                    string.format("Manim failed (exit %d) -- check class '%s'", code, class_name),
                    vim.log.levels.WARN
                )
                return
            end

            local matches = vim.fn.glob(gif_dir .. class_name .. "*.gif", false, true)
            if #matches == 0 then
                vim.notify("No GIF found in " .. gif_dir, vim.log.levels.WARN)
                return
            end
            local gif_path = matches[#matches]

            -- Clear le pane (envoie q pour quitter --hold, puis clear)
            local display_cmd = string.format(
                "wezterm cli send-text --pane-id %s --no-paste $'q\\n' && " ..
                "sleep 0.1 && " ..
                "wezterm cli send-text --pane-id %s --no-paste $'clear\\n' && " ..
                "sleep 0.1 && " ..
                "wezterm cli send-text --pane-id %s --no-paste %s$'\\n'",
                viewer_pane,
                viewer_pane,
                viewer_pane,
                vim.fn.shellescape("wezterm imgcat --hold " .. gif_path)
            )
            vim.fn.jobstart({ "bash", "-c", display_cmd }, { detach = true })
            vim.notify(string.format("Preview updated [%s]", class_name), vim.log.levels.INFO)
        end,
    })
end

local function register_autocmd(viewer_pane, class_name)
    vim.api.nvim_clear_autocmds({ group = augroup })
    vim.api.nvim_create_autocmd("BufWritePost", {
        group = augroup,
        pattern = "*.py",
        callback = function()
            render_and_display(viewer_pane, class_name)
        end,
    })
    vim.notify(
        string.format("Auto-render enabled -- class: %s | pane: %s", class_name, viewer_pane),
        vim.log.levels.INFO
    )
end

local function run_command(opts)
    local args = vim.split(opts.args, "%s+", { trimempty = true })
    local viewer_pane = args[1]
    local class_name  = args[2]
    if not viewer_pane or not class_name then
        vim.notify("Usage: :Manim <pane_id> <class_name>", vim.log.levels.ERROR)
        return
    end
    register_autocmd(viewer_pane, class_name)
    render_and_display(viewer_pane, class_name)
end

-- ── Spec Lazy ────────────────────────────────────────────────────────────────

return {
    "manim-custom-config",
    virtual = true,
    init = function()
        vim.api.nvim_create_user_command("Manim", run_command, {
            nargs = "+",
            complete = complete,
            desc = "Manim live render. Usage: :Manim <pane_id> <class_name>",
        })
    end,
}
