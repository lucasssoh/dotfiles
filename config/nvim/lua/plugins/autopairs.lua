return {
    "windwp/nvim-autopairs",
    event = "InsertEnter",
    config = function()
        local autopairs = require("nvim-autopairs")
        local Rule = require('nvim-autopairs.rule')

        autopairs.setup({
            check_ts = true, 
            ts_config = {
                lua = { "string" }, 
                javascript = { "template_string" },
            },
            -- On simplifie ici pour permettre la fermeture plus souvent
            ignored_next_char = "[%w%.]", 
            -- Force la fermeture même s'il y a des espaces après
            enable_check_bracket_line = false, 
        })

        -- --- AJOUTER LES RÈGLES SPÉCIFIQUES ---
        -- Cela force l'ajout de l'accolade même dans des conditions strictes
        autopairs.add_rules({
          Rule("{ ", " }")
            :with_pair(function() return false end)
            :with_move(function(opts)
                return opts.prev_char:match(".%}") ~= nil
            end)
            :use_key("}"),
        })

        -- Intégration avec nvim-cmp (inchangé)
        local cmp_status, cmp = pcall(require, "cmp")
        if cmp_status then
            local cmp_autopairs = require("nvim-autopairs.completion.cmp")
            cmp.event:on("confirm_done", cmp_autopairs.on_confirm_done())
        end
    end,
}
