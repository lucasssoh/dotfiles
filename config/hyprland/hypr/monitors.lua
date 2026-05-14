-- ============================================================
-- MONITORS.LUA — Configuration multi-écrans dynamique
-- ============================================================
-- Laptop seul    : écran interne activé automatiquement
-- Écran externe  : détecté et placé à droite automatiquement
-- ============================================================

-- Écran interne du laptop
hl.monitor({ output = "eDP-1", mode = "preferred", position = "0x0", scale = 1 })
hl.monitor({ output = "eDP-2", mode = "1920x1080@144Hz", position = "0x0", scale = 1 })
-- Écrans externes : placés automatiquement à droite du laptop
-- Remplace "HDMI-A-1" par le vrai nom (lance `hyprctl monitors`)
hl.monitor({ output = "HDMI-A-1", mode = "preferred", position = "auto", scale = 1 })
hl.monitor({ output = "DP-1",     mode = "preferred", position = "auto", scale = 1 })
hl.monitor({ output = "DP-2",     mode = "preferred", position = "auto", scale = 1 })

-- Fallback : tout écran inconnu branché → activé automatiquement
hl.monitor({ output = "",         mode = "preferred", position = "auto", scale = 1 })

-- Workspaces laptop
hl.workspace_rule({ workspace = "1",  monitor = "eDP-2" })
hl.workspace_rule({ workspace = "2",  monitor = "eDP-2" })
hl.workspace_rule({ workspace = "3",  monitor = "eDP-2" })
hl.workspace_rule({ workspace = "4",  monitor = "eDP-2" })
hl.workspace_rule({ workspace = "5",  monitor = "eDP-2" })
hl.workspace_rule({ workspace = "6",  monitor = "eDP-2" })
hl.workspace_rule({ workspace = "7",  monitor = "eDP-2" })

-- Workspaces écran externe (décommente quand branché)
-- hl.workspace_rule({ workspace = "8",  monitor = "HDMI-A-1", default = true })
-- hl.workspace_rule({ workspace = "9",  monitor = "HDMI-A-1" })
-- hl.workspace_rule({ workspace = "10", monitor = "HDMI-A-1" })
