local jdtls = require("jdtls")

-- 1. Le chemin absolu vers Lombok installé par Mason
local lombok_path = "/home/lucas/.local/share/nvim/mason/packages/jdtls/lombok.jar"

-- 2. Trouver la racine du projet (là où se trouve le pom.xml)
local root_markers = { "pom.xml", "mvnw", "gradlew", ".git" }
local root_dir = require("jdtls.setup").find_root(root_markers)

if not root_dir then
    print("JDTLS : Unable to find project path")
    return
end

-- 3. Définir un nom de workspace unique basé sur le nom du dossier racine
local project_name = vim.fn.fnamemodify(root_dir, ":p:h:t")
local workspace_dir = "/home/lucas/.cache/jdtls/workspace/" .. project_name

-- 4. La configuration du serveur
local config = {
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
        -- Si tu utilises lsp-zero, il gère tes raccourcis ici
        require("lsp-zero").default_keymaps({ buffer = bufnr })
    end,
}

-- 5. Lancement
jdtls.start_or_attach(config)
