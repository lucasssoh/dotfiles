-- ============================================================
-- LSP/JAVA.LUA
-- jdtls config, factored out so it can be shared between:
--   - ftplugin/java.lua, which attaches when a .java buffer is opened
--   - the warmup autocmd in lsp/mason.lua, which starts jdtls as soon as
--     a Java project folder is opened, without waiting for a .java file
--     to be opened by hand. jdtls indexes and diagnoses the whole
--     workspace on startup, which is what lets nvim-tree's diagnostic
--     icons (lua/plugins/nvimtree.lua) show errors/warnings on files
--     nobody has opened yet.
-- ============================================================
local M = {}

M.root_markers = { "pom.xml", "mvnw", "gradlew", ".git", "build.gradle" }

-- leetcode.nvim's solutions folder (its default storage.home). It has no
-- build file, so it gets rooted by hand: each file there is a standalone
-- `class Solution`. jdtls treats them as non-project files -- their names
-- ("1.two-sum.java") are not valid class names -- which is what keeps the
-- dozens of `class Solution` from clashing as duplicates, while still
-- giving completion and semantic errors (checked on jdtls 1.60, Java 25).
M.leetcode_root = vim.fn.stdpath("data") .. "/leetcode"

--- @param source string file path to search upward from
--- @return string? root_dir
function M.find_root(source)
    if vim.startswith(source, M.leetcode_root .. "/") then
        return M.leetcode_root
    end
    return require("jdtls.setup").find_root(M.root_markers, source)
end

--- Finds a usable lombok.jar, or nil.
---
--- This used to be a single hardcoded "/home/lucas/.local/share/nvim/mason/
--- packages/jdtls/lombok.jar", which had two problems on a machine that is
--- not the one it was written on:
---
---   * it bakes in a username, so it is wrong for anyone else and for any
---     $XDG_DATA_HOME that is not the default;
---   * it depends on Mason having already installed jdtls. On a fresh
---     install, opening a .java file before Mason has run points the JVM at
---     a file that does not exist.
---
--- That second case is the one that matters, because a missing javaagent is
--- not a degraded experience -- it is fatal. `java -javaagent:/nope` makes
--- the JVM refuse to start at all, so jdtls dies on launch and Java support
--- is simply gone, with an error that says nothing about Lombok. Hence the
--- resolver below AND the nil case being handled at the call site: no jar
--- means no -javaagent flag, which costs the Lombok annotations and keeps
--- everything else working.
---
--- Mason first, since that jar ships with the jdtls it will actually run;
--- then the stable location scripts/dev_setup.sh downloads to (pinned
--- version, sha1-verified), which is what covers a machine where Mason has
--- not run yet.
local function find_lombok()
    local candidates = {
        vim.fn.stdpath("data") .. "/mason/packages/jdtls/lombok.jar",
        vim.fn.expand("~/.local/share/java/lombok.jar"),
    }
    for _, path in ipairs(candidates) do
        if vim.fn.filereadable(path) == 1 then
            return path
        end
    end
    return nil
end

local function build_config(root_dir)
    -- Unique workspace name based on the root folder name
    local project_name = vim.fn.fnamemodify(root_dir, ":p:h:t")
    -- expand("~") rather than the hardcoded /home/lucas it used to be, for
    -- the same reason as the lombok path above. Deliberately NOT
    -- stdpath("cache"): that resolves to ~/.cache/nvim, a different folder,
    -- which would orphan every jdtls workspace already indexed here and
    -- force a full re-index of each Java project. De-hardcoding the
    -- username is the fix; moving the data is not part of it.
    local workspace_dir = vim.fn.expand("~/.cache/jdtls/workspace/") .. project_name

    local cmd = { "jdtls" }

    local lombok_path = find_lombok()
    if lombok_path then
        table.insert(cmd, "--jvm-arg=-javaagent:" .. lombok_path)
    else
        vim.notify(
            "jdtls : lombok.jar introuvable, annotations Lombok desactivees.\n"
                .. "Lancer scripts/dev_setup.sh, ou :MasonInstall jdtls",
            vim.log.levels.WARN
        )
    end

    vim.list_extend(cmd, { "-data", workspace_dir })

    return {
        cmd = cmd,
        root_dir = root_dir,
        settings = {
            java = {
                signatureHelp = { enabled = true },
                contentProvider = { preferred = "fernflower" },
                eclipse = { downloadSources = true },
                maven = { downloadSources = true },
            },
        },
        handlers = root_dir == M.leetcode_root and {
            -- Drop the "<file> is a non-project file, only syntax errors are
            -- reported" warning jdtls pins on line 1 of every solution. It
            -- is expected there, and wrong anyway: semantic errors do show.
            ["textDocument/publishDiagnostics"] = function(err, result, ctx)
                result.diagnostics = vim.tbl_filter(function(d)
                    return not d.message:find("is a non-project file", 1, true)
                end, result.diagnostics)
                vim.lsp.diagnostic.on_publish_diagnostics(err, result, ctx)
            end,
        } or nil,
        on_attach = function(client, bufnr)
            require("lsp-zero").default_keymaps({ buffer = bufnr })
        end,
    }
end

--- Starts jdtls, or attaches to an already running instance for the same
--- project root.
--- @param bufnr integer? defaults to the current buffer
function M.start(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    local root_dir = M.find_root(vim.api.nvim_buf_get_name(bufnr))
    if not root_dir then
        print("JDTLS : Unable to find project path")
        return
    end
    require("jdtls").start_or_attach(build_config(root_dir), nil, { bufnr = bufnr })
end

return M
