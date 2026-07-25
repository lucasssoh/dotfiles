-- ============================================================
-- colors.lua — Palette de couleurs centrale
-- ============================================================
-- Source unique de vérité pour la palette Hyprland. Valeurs au format
-- 0xAARRGGBB attendu par Hyprland. Chargé par hyprland.lua via
-- require("colors") et consommé par hl.config() (bordures, décorations).
-- ============================================================

return {
    background = "0xff1c1c1e",
    surface    = "0xff2c2c2e",
    overlay    = "0xff3a3a3c",
    muted      = "0xff636366",
    subtle     = "0xff8e8e93",
    text       = "0xffe5e5ea",
    accent     = "0xff6b9fff",   -- Accent primaire (bleu)
    accent2    = "0xffd0ffff",   -- Accent secondaire (cyan clair)
    accent3    = "0xffc8823c",   -- Accent tertiaire (orange renard)
    urgent     = "0xffff453a",
    warning    = "0xffffd60a",
    success    = "0xff30d158"
}

-- ============================================================
-- Miroir CSS (#RRGGBB) pour Waybar / Rofi / Dunst
-- Ces outils ne peuvent pas faire require() sur un fichier Lua : toute
-- modification de palette doit être reportée manuellement dans
-- waybar/style.css et rofi/launcher.rasi.
-- ============================================================
-- background:  #1c1c1e
-- surface:     #2c2c2e
-- overlay:     #3a3a3c
-- muted:       #636366
-- subtle:      #8e8e93
-- text:        #e5e5ea
-- accent:      #6b9fff
-- accent2:     #d0ffff
-- accent3:     #c8823c
-- urgent:      #ff453a
-- warning:     #ffd60a
-- success:     #30d158
