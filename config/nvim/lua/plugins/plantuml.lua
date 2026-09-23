-- ============================================================
-- PLUGINS/PLANTUML.LUA
-- Coloration des .puml. Ni nvim ni nvim-treesitter n'ont de syntaxe
-- PlantUML : sans ce plugin, un diagramme s'affiche tout blanc.
--
-- Le reste de l'outillage PlantUML est dans ftplugin/plantuml.lua :
-- aperçu en direct, export, lint (plantuml -syntax), et plantuml-lsp pour
-- la complétion -- hors Mason, qui n'a aucun paquet PlantUML. Ici, la
-- seule commande qui doit exister hors d'un .puml : :PumlFromJava.
-- ============================================================
return {
    "aklt/plantuml-syntax",
    ft = "plantuml",
    init = function()
        -- Depuis n'importe quel buffer, pas seulement un .puml : on la lance
        -- justement depuis du Java. Voir lua/puml_java.lua.
        vim.api.nvim_create_user_command("PumlFromJava", function(opts)
            require("puml_java").generate(opts.args)
        end, { nargs = "?", complete = "dir", desc = "Diagramme de classes depuis le code Java" })
    end,
}
