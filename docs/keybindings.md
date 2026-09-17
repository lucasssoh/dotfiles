# Key bindings

AZERTY layout. The source of truth is [`config/hyprland/hypr/keybinds.lua`](../config/hyprland/hypr/keybinds.lua) — the key symbols there (`ampersand`, `eacute`, …) are the characters the AZERTY number row produces, not physical keys 1–10.

Holding `Super` brings up a cheatsheet in the bar; it disappears on release.

## Launching

| Binding | Action |
|---|---|
| `Super + Enter` | WezTerm |
| `Super + Space` | App launcher (fuzzel) |
| `Super + E` | Nemo (file manager) |
| `Super + B` | Firefox |
| `Super + W` | Prisme — wallpaper picker |
| `Super + F` | Liseuse — resume the book you were reading, or pick one (`F1` inside a book for its manual) |
| `Super + V` | Clipboard history (cliphist through rofi) |

## Screenshots

| Binding | Action |
|---|---|
| `Super + S` | Full screen → annotate in `satty` → clipboard |
| `Super + Shift + S` | Region (`slurp`) → annotate → clipboard |

## Roue — radial wheels

Press, aim while holding, release to confirm.

| Binding | Wheel |
|---|---|
| `Super + Delete` | Power menu |
| `Super + Shift + Delete` | Power profile |
| `Super + O` | Display layout |
| `Copilot` key | Actions wheel (`--toggle`: the same key closes it) |

## Windows

| Binding | Action |
|---|---|
| `Super + Q` | Close window |
| `Super + H` / `J` / `K` / `L` | Focus left / down / up / right |
| `Super + Shift + H/J/K/L` | Move the window in that direction |
| `Super + Shift + F` | Fullscreen |
| `Super + Ctrl + F` | Maximise |
| `Super + Shift + Space` | Toggle floating |
| `Super + P` | Pseudo-tile |
| `Super + T` | Toggle split direction |
| `Super + R` | Resize mode — then `H/J/K/L` to resize, `Escape` or `Enter` to leave |
| `Super + left-drag` | Move window |
| `Super + right-drag` | Resize window |

## Workspaces

| Binding | Action |
|---|---|
| `Super + 1..0` | Switch to workspace |
| `Super + Shift + 1..0` | Move the window there |
| `Super + scroll` | Previous / next workspace |
| `Super + C` | Compact workspaces (close the gaps) |
| `Super + U` | Toggle the `magic` scratchpad |
| `Super + Shift + U` | Send the window to `magic` |

## Shell and session

| Binding | Action |
|---|---|
| `Super + Z` | Zen mode — hide the bar |
| `Super + N` | Night mode |
| `Super + I` | Notification centre |
| `Super + Escape` | Lock (hyprlock) |
| `Super + Shift + R` | `hyprctl reload` |
| `Super + Shift + M` | Exit Hyprland |

## Media and hardware keys

All of these keep working on the lock screen.

| Key | Action |
|---|---|
| Volume up / down | `wpctl`, 5 % steps, capped at 100 % |
| Mute / mic mute | `wpctl` toggle |
| Brightness up / down | [`brightness.sh`](../config/hyprland/hypr/scripts/brightness.sh) — never reaches 0, so the screen cannot go black |
| Play / pause, previous, next | `playerctl` |

## Touchpad

| Gesture | Action |
|---|---|
| 3-finger horizontal swipe | Previous / next workspace |
