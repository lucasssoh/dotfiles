local jdtls = require("jdtls")

-- 1. Absolute path to Lombok installed by Mason
local lombok_path = "/home/lucas/.local/share/nvim/mason/packages/jdtls/lombok.jar"

-- 2. Find the project root (where pom.xml is located)
local root_markers = { "pom.xml", "mvnw", "gradlew", ".git", "build.gradle" }
local root_dir = require("jdtls.setup").find_root(root_markers)

if not root_dir then
    print("JDTLS : Unable to find project path")
    return
end

-- 3. Define a unique workspace name based on the root folder name
local project_name = vim.fn.fnamemodify(root_dir, ":p:h:t")
local workspace_dir = "/home/lucas/.cache/jdtls/workspace/" .. project_name

-- 4. Server configuration
local config = {
    cmd = {
        "jdtls",
        "-javaagent:" .. lombok_path,
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
        -- If you use lsp-zero, it handles your keymaps here
        require("lsp-zero").default_keymaps({ buffer = bufnr })
    end,
}

-- 5. Lancement
jdtls.start_or_attach(config)
