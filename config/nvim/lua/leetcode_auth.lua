-- ============================================================
-- LEETCODE_AUTH.LUA
-- Sign in to leetcode.nvim through Firefox instead of pasting a cookie.
--
-- LeetCode offers no OAuth to third-party apps, so there is no token to
-- receive the way Claude Code does. What stands in for it: the browser is
-- the login form, and its cookie jar is the token store. Firefox keeps its
-- cookies unencrypted in cookies.sqlite (no keyring to unlock, unlike
-- Chromium), so reading LEETCODE_SESSION + csrftoken is one sqlite3 query.
--
-- Two entry points, both used by lua/plugins/leetcode.lua:
--   - sync()  : before leetcode.nvim starts, copy Firefox's cookie into the
--               plugin's cookie file. Staying signed in on leetcode.com in
--               Firefox is then enough to stay signed in in nvim.
--   - login() : when the plugin needs a cookie, open the login page in
--               Firefox and poll the cookie jar until the session appears.
-- ============================================================
local M = {}

local HOSTS = "'leetcode.com', '.leetcode.com'"
local LOGIN_URL = "https://leetcode.com/accounts/login/"
local POLL_MS = 1000
local TIMEOUT_MS = 3 * 60 * 1000

-- Where leetcode.nvim reads its cookie (storage.cache in its config). Kept in
-- sync with the plugin's default rather than read from it, because sync()
-- runs before the plugin has set its storage paths up.
M.cookie_file = vim.fn.stdpath("cache") .. "/leetcode/cookie"

--- Firefox's default profile directory, or nil.
---
--- The [Install…] section is the profile Firefox actually launches;
--- `Default=1` under [ProfileN] is the legacy flag and can point elsewhere
--- (it does on this machine), so it only serves as a fallback.
--- @return string?
local function profile_dir()
    for _, base in ipairs({ "~/.config/mozilla/firefox", "~/.mozilla/firefox" }) do
        base = vim.fn.expand(base)
        local ini = base .. "/profiles.ini"
        if vim.fn.filereadable(ini) == 1 then
            local section, install, legacy, path = nil, nil, nil, nil
            for line in io.lines(ini) do
                local s = line:match("^%[(.+)%]$")
                if s then
                    section, path = s, nil
                elseif section then
                    local k, v = line:match("^(%w+)=(.*)$")
                    if section:match("^Install") and k == "Default" then
                        install = install or v
                    elseif k == "Path" then
                        path = v
                    elseif k == "Default" and v == "1" and path then
                        legacy = legacy or path
                    end
                end
            end
            local rel = install or legacy
            if rel then
                return rel:sub(1, 1) == "/" and rel or (base .. "/" .. rel)
            end
        end
    end
end

--- sqlite3 command reading the leetcode cookies from a snapshot of the jar.
---
--- Firefox keeps cookies.sqlite open and writes new rows to the -wal file
--- first, so the main file alone can miss a login from a few seconds ago.
--- Copying both and reading the copy sees them, without touching the live
--- database. `expiry` switched from seconds to milliseconds in recent
--- Firefox; the CASE accepts either.
--- @return string[]? argv
local function query_cmd()
    local dir = profile_dir()
    if not dir or vim.fn.filereadable(dir .. "/cookies.sqlite") == 0 then
        return
    end
    local sql = ("SELECT name || '=' || value FROM moz_cookies"
        .. " WHERE host IN (%s) AND name IN ('LEETCODE_SESSION', 'csrftoken')"
        .. " AND (CASE WHEN expiry > 100000000000 THEN expiry / 1000 ELSE expiry END)"
        .. " > CAST(strftime('%%s', 'now') AS INTEGER)"
        .. " ORDER BY name"):format(HOSTS)
    local script = [[
tmp=$(mktemp -d) && trap 'rm -rf "$tmp"' EXIT
cp "$1/cookies.sqlite" "$tmp/c.sqlite" || exit 1
[ -f "$1/cookies.sqlite-wal" ] && cp "$1/cookies.sqlite-wal" "$tmp/c.sqlite-wal"
sqlite3 -readonly "$tmp/c.sqlite" "$2"
]]
    return { "sh", "-c", script, "sh", dir, sql }
end

--- Turns sqlite3's output into the "a=b; c=d" string leetcode.nvim expects,
--- or nil unless both cookies are there.
--- @param out string?
--- @return string?
local function parse(out)
    local csrf = (out or ""):match("csrftoken=[^\n]+")
    local session = (out or ""):match("LEETCODE_SESSION=[^\n]+")
    if csrf and session then
        return session .. "; " .. csrf
    end
end

--- The leetcode cookie string from Firefox, or nil (synchronous, ~10 ms).
--- @return string?
function M.from_firefox()
    local cmd = query_cmd()
    if not cmd then
        return
    end
    return parse(vim.system(cmd, { text = true }):wait().stdout)
end

--- Copies Firefox's cookie into leetcode.nvim's cookie file when it differs.
--- Never removes or overwrites with nothing: a Firefox that is signed out
--- leaves the file as is, and the plugin decides whether it still works.
function M.sync()
    local str = M.from_firefox()
    if not str then
        return
    end
    local current = vim.fn.filereadable(M.cookie_file) == 1 and vim.fn.readfile(M.cookie_file)[1]
    if current ~= str then
        vim.fn.mkdir(vim.fn.fnamemodify(M.cookie_file, ":h"), "p")
        vim.fn.writefile({ str }, M.cookie_file)
    end
end

local polling = false

--- Gets a cookie from Firefox, opening the login page if there is none yet.
--- `on_done(str)` runs on the main loop, with nil after TIMEOUT_MS.
--- @param on_done fun(cookie: string?)
function M.login(on_done)
    local now = M.from_firefox()
    if now then
        return on_done(now)
    end
    if polling then
        return vim.notify("LeetCode : connexion déjà en cours dans Firefox", vim.log.levels.INFO)
    end

    local cmd = query_cmd()
    if not cmd then
        vim.notify("LeetCode : profil Firefox introuvable", vim.log.levels.ERROR)
        return on_done(nil)
    end

    -- Hands the URL to the running Firefox if there is one, detached so
    -- that closing nvim does not take the browser with it.
    vim.system({ "firefox", "--new-window", LOGIN_URL }, { detach = true })
    vim.notify("LeetCode : connecte-toi dans Firefox, nvim récupère la session tout seul")

    polling = true
    local deadline = vim.uv.now() + TIMEOUT_MS
    local function poll()
        vim.system(cmd, { text = true }, vim.schedule_wrap(function(res)
            local str = parse(res.stdout)
            if str or vim.uv.now() >= deadline then
                polling = false
                return on_done(str)
            end
            vim.defer_fn(poll, POLL_MS)
        end))
    end
    vim.defer_fn(poll, POLL_MS)
end

return M
