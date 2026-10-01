# Hardware detection

The `hardware` unit looks at your CPU and GPU and installs only the drivers and tools your machine actually needs. The profiles and package lists are in [`scripts/lib/hardware.sh`](../scripts/lib/hardware.sh).

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

CPUs that come out after this table was written still match through these family and model rules, so nothing needs editing.

## Codec swaps

Fedora's own media packages can't decode H.264 or HEVC in hardware. So the unit turns on RPM Fusion (free and nonfree) and swaps them for the RPM Fusion versions:

| Fedora package | Replaced by |
|---|---|
| `ffmpeg-free` | `ffmpeg` |
| `libva-intel-media-driver` | `intel-media-driver` |
| `mesa-va-drivers` | `mesa-va-drivers-freeworld` |

This list is `hw_codec_swaps` in `hardware.sh`. If `vainfo` still shows no H.264 decoding afterwards, you'll get a warning. Restart Firefox and mpv so they pick up the new driver.

## Things to do by hand

These are printed for you, never run automatically:

- the NVIDIA proprietary driver (it needs a third-party repo, a kernel module, and care with Secure Boot);
- Lenovo's battery conservation mode;
- `i915.enable_dpcd_backlight`, to make the brightness keys work on OLED screens.

## Measuring power

`powertop` and `turbostat` are installed, but you run them yourself, as root. On Meteor Lake, trust `turbostat` over `powertop` for package C-state figures.

## When it runs

It runs with every install, and again after an `upgrade` or an edit that changes the profiles in `hardware.sh`. You can also run it yourself:

```bash
cc-pkg-mng install hardware
```

If some packages fail to install, they're listed at the end.
