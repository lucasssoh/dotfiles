-- ============================================================
-- PLUGINS/PLANTUML.LUA
-- Coloration des .puml. Ni nvim ni nvim-treesitter n'ont de syntaxe
-- PlantUML : sans ce plugin, un diagramme s'affiche tout blanc.
--
-- Le reste de l'outillage PlantUML est dans ftplugin/plantuml.lua :
-- aperçu dans la liseuse, lint (plantuml -syntax), et plantuml-lsp pour
-- la complétion -- hors Mason, qui n'a aucun paquet PlantUML.
-- ============================================================
return {
    "aklt/plantuml-syntax",
    ft = "plantuml",
}
