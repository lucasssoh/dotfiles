-- ============================================================
-- MONITORS.LUA — Configuration multi-écrans dynamique & HDR
-- ============================================================
--
-- Aucun nom de connecteur en dur ici : l'assignation des workspaces
-- (1-7 interne / 8-10 externe) et le tuning scale/HDR de l'externe
-- sont résolus PAR RÔLE (interne = eDP*/LVDS*/DSI*, externe = le
-- reste) par scripts/workspace-manager.sh.
--
-- IMPORTANT : ce script pose ses règles à l'exécution (hyprctl eval),
-- rien n'est écrit dans un fichier Lua. Elles sont donc effacées à
-- chaque `hyprctl reload` ou redémarrage de session, et doivent être
-- rejouées manuellement : bash ~/.config/hypr/scripts/workspace-manager.sh
-- (pas d'autostart ni de service hotplug actuellement branché).
--
-- Ce fichier ne fait qu'activer tout écran branché à son mode
-- préféré ; le manager surcharge ensuite scale/bitdepth/cm sur
-- l'externe détecté.

hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })
