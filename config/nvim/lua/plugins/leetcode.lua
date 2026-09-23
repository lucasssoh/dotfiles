-- ============================================================
-- PLUGINS/LEETCODE.LUA
-- LeetCode in nvim: `nvim leetcode.nvim`, or :Leet from a running session.
--
-- Sign-in goes through Firefox (lua/leetcode_auth.lua) instead of pasting a
-- cookie: signed in on leetcode.com in Firefox means signed in here, and a
-- missing or expired session opens the login page in Firefox by itself.
-- The plugin's cookie prompt stays reachable as the fallback.
--
-- Java completion/diagnostics come from jdtls, rooted on the solutions
-- folder by lua/lsp/java.lua.
-- ============================================================
return {
    "kawre/leetcode.nvim",
    build = ":LeetCache",
    cmd = "Leet",
    -- Loaded at startup only for `nvim leetcode.nvim`, whose VimEnter the
    -- plugin itself hooks; otherwise :Leet loads it on demand.
    lazy = vim.fn.argv(0, -1) ~= "leetcode.nvim",
    dependencies = {
        "nvim-telescope/telescope.nvim",
        "muniftanjim/nui.nvim",
        "nvim-lua/plenary.nvim",
        "nvim-tree/nvim-web-devicons",
    },
    opts = {
        arg = "leetcode.nvim",
        lang = "java",
        injector = {
            -- Added to the plugin's default java.util.* / java.math.*, and
            -- not sent on submit. Streams and functional interfaces show up
            -- often enough to be worth not importing by hand.
            java = { imports = { "import java.util.function.*;", "import java.util.stream.*;" } },
        },
        hooks = {
            -- Only in solution buffers, so they can use short leader keys
            -- without taking them anywhere else.
            question_enter = {
                function(question)
                    local function map(lhs, sub, desc)
                        vim.keymap.set("n", "<leader>" .. lhs, "<Cmd>Leet " .. sub .. "<CR>",
                            { buffer = question.bufnr, desc = "LeetCode : " .. desc })
                    end
                    map("r", "run", "run")
                    map("s", "submit", "submit")
                    map("d", "desc", "toggle description")
                    map("c", "console", "console")
                    map("p", "list", "problem list")
                    map("m", "menu", "menu")
                end,
            },
            -- No cookie at all (first run, or the plugin deleted an expired
            -- one): go straight to the Firefox login instead of showing the
            -- sign-in page and waiting for a key press.
            enter = {
                function()
                    if vim.fn.filereadable(require("leetcode_auth").cookie_file) == 0 then
                        vim.schedule(require("leetcode.command").cookie_prompt)
                    end
                end,
            },
        },
    },
    config = function(_, opts)
        local leetcode = require("leetcode")
        leetcode.setup(opts)

        local auth = require("leetcode_auth")

        -- Refresh the cookie from Firefox before the plugin checks it, so a
        -- session renewed in the browser is picked up with no prompt. Both
        -- the VimEnter autocmd and :Leet look `start` up on the module at
        -- call time, so replacing the field covers both.
        local start = leetcode.start
        leetcode.start = function(...)
            auth.sync()
            return start(...)
        end

        -- Everything that asks for a cookie goes through cookie_prompt: the
        -- sign-in page button, :Leet cookie update, and a session expiring
        -- mid-use. It now asks Firefox, and falls back to the original
        -- paste prompt if no session showed up before the timeout.
        local cmd = require("leetcode.command")
        local paste_prompt = cmd.cookie_prompt
        cmd.cookie_prompt = function(cb)
            auth.login(function(str)
                if not str then
                    vim.notify("LeetCode : pas de session Firefox, colle le cookie à la main", vim.log.levels.WARN)
                    return paste_prompt(cb)
                end
                local err = require("leetcode.cache.cookie").set(str)
                if err then
                    vim.notify("LeetCode : cookie Firefox refusé (" .. err .. ")", vim.log.levels.ERROR)
                    return paste_prompt(cb)
                end
                vim.notify("LeetCode : connecté via Firefox")
                cmd.start_user_session()
                pcall(cb, true)
            end)
        end
    end,
}
