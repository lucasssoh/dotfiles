return {
    "kawre/leetcode.nvim",
    build = ":LeetCache",
    dependencies = {
        "nvim-telescope/telescope.nvim",
        "muniftanjim/nui.nvim",
        "nvim-lua/plenary.nvim",
        "nvim-tree/nvim-web-devicons",
    },
    opts = {
        arg = "leetcode.nvim",
        lang = "java", -- Puisque tu travailles sur tes exercices en Java
    },
}
