-- ============================================================
-- colors.lua — Central color palette
-- ============================================================
-- Single source of truth for the Hyprland palette. Values in the
-- 0xAARRGGBB format expected by Hyprland. Loaded by hyprland.lua via
-- require("colors") and consumed by hl.config() (borders, decorations).
-- ============================================================

return {
    background = "0xff1c1c1e",
    surface    = "0xff2c2c2e",
    overlay    = "0xff3a3a3c",
    muted      = "0xff636366",
    subtle     = "0xff8e8e93",
    text       = "0xffe5e5ea",
    accent     = "0xffa8b4c4",   -- Primary accent (desaturated blue / platinum)
    accent2    = "0xffd0ffff",   -- Secondary accent (light cyan)
    accent3    = "0xffc8823c",   -- Tertiary accent (fox orange)
    urgent     = "0xffff453a",
    warning    = "0xffffd60a",
    success    = "0xff30d158"
}

-- ============================================================
-- CSS mirror (#RRGGBB) for Waybar / Rofi / Dunst
-- These tools can't require() a Lua file: any palette change must be
-- ported by hand into waybar/style.css and rofi/launcher.rasi.
-- ============================================================
-- background:  #1c1c1e
-- surface:     #2c2c2e
-- overlay:     #3a3a3c
-- muted:       #636366
-- subtle:      #8e8e93
-- text:        #e5e5ea
-- accent:      #a8b4c4
-- accent2:     #d0ffff
-- accent3:     #c8823c
-- urgent:      #ff453a
-- warning:     #ffd60a
-- success:     #30d158
