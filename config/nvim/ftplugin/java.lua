local home = os.getenv("HOME")
local jdtls = require('jdtls')

-- Détection de la racine du projet
local root_markers = {'mvnw', 'gradlew', '.git', 'pom.xml'}
local root_dir = require('jdtls.setup').find_root(root_markers)

-- Nom du projet basé sur le dossier pour séparer les caches
local project_name = vim.fn.fnamemodify(root_dir, ":p:h:t")
local workspace_dir = home .. "/.cache/jdtls/workspace/" .. project_name

local config = {
    cmd = {
        'jdtls',
        '-data', workspace_dir,
    },
    root_dir = root_dir,
    settings = {
        java = {
            signatureHelp = { enabled = true },
            contentProvider = { preferred = 'fernflower' },
        }
    },
    -- Utilise les capacités de lsp-zero
    on_attach = function(client, bufnr)
        require('lsp-zero').default_keymaps({buffer = bufnr})
    end,
}

jdtls.start_or_attach(config)
