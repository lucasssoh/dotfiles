# Veille

A big clock that appears when you're up late, with the occasional message.

<picture><source media="(prefers-color-scheme: dark)" srcset="../screenshots/veille-dark.webp"><img src="../screenshots/veille.webp" alt="Veille at 2 a.m."></picture>

Its settings are in [`quickshell/bar/veille.json`](../../config/hyprland/quickshell/bar/veille.json), and changes apply as soon as you save:

| Key | Controls |
|---|---|
| `enabled`, `language`, `monitor` | On or off, the language of the messages, and which screen it shows on (empty means the focused one) |
| `showSeconds`, `showDate` | How the clock looks |
| `messageIntervalMinutes`, `messageHoldSeconds`, `curatedRatio` | How often messages appear |
| `thresholds` | The time each phase starts |
| `phases` | Whether it shows, and how it looks, in each phase |
| `muteWhileGaming`, `respectZenMode` | When it stays out of the way |

To see it without waiting up, [move the shell's clock](clock-agenda.md#try-another-time).
