-- ============================================================
-- MONITORS.LUA — Configuration multi-écrans dynamique & HDR
-- ============================================================

-- ============================================================
-- 1. ÉCRANS (Laptops & Externes)
-- ============================================================

-- Écran interne du laptop (SDR standard)
hl.monitor({ output = "eDP-1", mode = "preferred", position = "0x0", scale = 1 })
hl.monitor({ output = "eDP-2", mode = "1920x1080@144Hz", position = "0x0", scale = 1 })

-- Écran externe branché en USB-C (Recommandé pour G-Sync / DP Alt Mode)
hl.monitor({ 
    output = "DP-9", 
    mode = "2560x1440@180Hz", 
    position = "auto", 
    scale = 1.2,              -- Évite de plisser les yeux sur Neovim à 1m
    bitdepth = 10,            -- Pipeline 10-bits requis pour le HDR
    cm = "hdr",               -- Active la gestion des couleurs HDR d'Hyprland
    sdrbrightness = 1.2       -- Ajuste la luminosité SDR pour le terminal/web
})

-- Écran externe branché en HDMI (Alternative direct-dGPU)
hl.monitor({ 
    output = "HDMI-A-1", 
    mode = "2560x1440@180Hz", 
    position = "auto", 
    scale = 1.2,
    bitdepth = 10,
    cm = "hdr",
    sdrbrightness = 1.2
})

-- Fallback : tout écran inconnu branché → activé automatiquement
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })


-- ============================================================
-- 2. RÈGLES DES WORKSPACES
-- ============================================================

-- Workspaces assignés à l'écran du laptop
hl.workspace_rule({ workspace = "1", monitor = "eDP-2" })
hl.workspace_rule({ workspace = "2", monitor = "eDP-2" })
hl.workspace_rule({ workspace = "3", monitor = "eDP-2" })
hl.workspace_rule({ workspace = "4", monitor = "eDP-2" })
hl.workspace_rule({ workspace = "5", monitor = "eDP-2" })
hl.workspace_rule({ workspace = "6", monitor = "eDP-2" })
hl.workspace_rule({ workspace = "7", monitor = "eDP-2" })

-- Workspaces assignés à ton futur écran externe (sur DP-9 en priorité)
hl.workspace_rule({ workspace = "8",  monitor = "DP-9", default = true })
hl.workspace_rule({ workspace = "9",  monitor = "DP-9" })
hl.workspace_rule({ workspace = "10", monitor = "DP-9" })

-- Fallback des workspaces si tu branches l'écran en HDMI plutôt qu'en USB-C
hl.workspace_rule({ workspace = "8",  monitor = "HDMI-A-1" })
hl.workspace_rule({ workspace = "9",  monitor = "HDMI-A-1" })
hl.workspace_rule({ workspace = "10", monitor = "HDMI-A-1" })
