# Hardware detection

The `hardware` unit installs the drivers and tools for your CPU and GPU. The profiles and package lists are in [`scripts/lib/hardware.sh`](../scripts/lib/hardware.sh).

You can see what it finds without installing anything:

```bash
./scripts/hardware-detect.sh             # full report: packages, codec swaps, things to do by hand
./scripts/hardware-detect.sh --packages  # just the package names
./scripts/hardware-detect.sh --notes     # just the things to do by hand
./scripts/hardware-detect.sh --json      # for scripts
```

## Profiles

| Profile | Matches | Adds |
|---|---|---|
| Intel, recent | Gen8 (Broadwell) and newer by name, and any model ≥ `0x8C` (Tiger Lake onwards) | The iHD VAAPI driver, oneVPL, `intel_gpu_top`, `thermald` |
| Intel, older | Older Intel chips, or ones it doesn't recognise | `thermald` |
| AMD | Any AMD chip. Zen is family ≥ `0x17` | `radeontop` |
| Every machine | | SOF audio firmware, `power-profiles-daemon`, `fwupd`, `vainfo` and `vulkaninfo`, sensor and inventory tools, `powertop` and `turbostat` |

## Codec swaps

For H.264 and HEVC decoding in hardware, the unit turns on RPM Fusion (free and nonfree) and swaps three packages:

| Fedora package | Replaced by |
|---|---|
| `ffmpeg-free` | `ffmpeg` |
| `libva-intel-media-driver` | `intel-media-driver` |
| `mesa-va-drivers` | `mesa-va-drivers-freeworld` |

Restart Firefox and mpv afterwards. A warning tells you if `vainfo` still shows no H.264 decoding. The list is `hw_codec_swaps` in `hardware.sh`.

## Things to do by hand

Listed at the end of the install, for you to do:

- Lenovo's battery conservation mode. The bar's [power drawer](bar/power.md) switches it too;
- the NVIDIA proprietary driver;
- `i915.enable_dpcd_backlight`, to make the brightness keys work on OLED screens.

## Measuring power

Run `powertop` or `turbostat` as root. On Meteor Lake, trust `turbostat` over `powertop` for package C-state figures.

## When it runs

It runs with every install, and again after an `upgrade` or an edit that changes the profiles in `hardware.sh`. You can also run it yourself:

```bash
cc-pkg-mng install hardware
```

If some packages fail to install, they're listed at the end.
