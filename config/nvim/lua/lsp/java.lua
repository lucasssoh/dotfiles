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

--- @param source string file path to search upward from
--- @return string? root_dir
function M.find_root(source)
    return require("jdtls.setup").find_root(M.root_markers, source)
end

local function build_config(root_dir)
    -- Absolute path to Lombok installed by Mason
    local lombok_path = "/home/lucas/.local/share/nvim/mason/packages/jdtls/lombok.jar"

    -- Unique workspace name based on the root folder name
    local project_name = vim.fn.fnamemodify(root_dir, ":p:h:t")
    local workspace_dir = "/home/lucas/.cache/jdtls/workspace/" .. project_name

    return {
        cmd = {
            "jdtls",
            "--jvm-arg=-javaagent:" .. lombok_path,
            "-data", workspace_dir,
        },
        root_dir = root_dir,
        settings = {
            java = {
                signatureHelp = { enabled = true },
                contentProvider = { preferred = "fernflower" },
                eclipse = { downloadSources = true },
                maven = { downloadSources = true },
            },
        },
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
