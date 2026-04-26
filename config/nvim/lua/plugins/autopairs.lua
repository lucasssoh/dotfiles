return {
    "windwp/nvim-autopairs",
    event = "InsertEnter",
    config = function()
        local autopairs = require("nvim-autopairs")

        autopairs.setup({
            check_ts = true, -- Utilise Treesitter pour être plus intelligent
            ts_config = {
                lua = { "string" }, -- Ne pas ajouter de paires dans les chaînes de caractères Lua
                javascript = { "template_string" },
            },
            -- Désactive l'ajout de paire si le curseur est juste devant un caractère alphanumérique
            ignored_next_char = [=[[%w%%%'%[%"%.%]]=],
        })

        -- --- LA MAGIE DE L'INDENTATION (TOUCHE ENTRÉE) ---
        -- Cette partie permet de faire : { + Entrée -> {
        --                                           | (curseur ici)
        --                                         }
        local cmp_autopairs = require("nvim-autopairs.completion.cmp")
        local cmp_status, cmp = pcall(require, "cmp")
        if cmp_status then
            cmp.event:on("confirm_done", cmp_autopairs.on_confirm_done())
        end
    end,
}
