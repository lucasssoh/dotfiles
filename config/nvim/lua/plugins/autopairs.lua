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
            -- Simplified here to allow closing more often
            ignored_next_char = "[%w%.]",
            -- Force closing even if there are spaces after
            enable_check_bracket_line = false,
        })

        -- --- ADD SPECIFIC RULES ---
        -- Forces the brace to be added even under strict conditions
        autopairs.add_rules({
          Rule("{ ", " }")
            :with_pair(function() return false end)
            :with_move(function(opts)
                return opts.prev_char:match(".%}") ~= nil
            end)
            :use_key("}"),
        })

        -- Integration with nvim-cmp (unchanged)
        local cmp_status, cmp = pcall(require, "cmp")
        if cmp_status then
            local cmp_autopairs = require("nvim-autopairs.completion.cmp")
            cmp.event:on("confirm_done", cmp_autopairs.on_confirm_done())
        end
    end,
}
