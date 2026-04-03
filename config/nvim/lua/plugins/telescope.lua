return {
    "nvim-telescope/telescope.nvim",
    tag = "0.1.5",
    dependencies = {
        "nvim-lua/plenary.nvim",
        { "nvim-telescope/telescope-fzf-native.nvim", build = "make" },
    },
    config = function()
        local telescope = require("telescope")
        telescope.setup({
            defaults = {
                mappings = {
                    i = {
                        ["<C-M-j>"] = "move_selection_next",
                        ["<C-M-k>"] = "move_selection_previous",
                    },
                },
            },
        })
        telescope.load_extension("fzf")

        local builtin = require("telescope.builtin")
        vim.keymap.set("n", "<leader>ff", builtin.find_files, {})
        vim.keymap.set("n", "<leader>fg", builtin.live_grep,  {})
        vim.keymap.set("n", "<leader>fb", builtin.buffers,    {})
    end,
}
