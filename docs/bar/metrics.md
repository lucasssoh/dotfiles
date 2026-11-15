# Metrics

The figures at the left of the bar, after the clock, and the network rate on the right.

| Figure | Shows |
|---|---|
| CPU | Load and frequency |
| Temperature | The CPU's |
| Fan | Its speed. Hidden when the machine has no fan sensor |
| Memory | What's in use |
| Power draw | In watts, on battery only |
| Network rate | Download speed, in the right-hand group |

They're read every 3 seconds, while you can see them. With the screen off or the bar hidden in [zen mode](index.md#zen-mode), nothing is read.

There's nothing to set up. The figures come from Pouls, a service of the `pouls` unit that runs as `systemd --user` (`pouls.service`). It also tells the bar when the charger comes or goes: see [Power](power.md).
