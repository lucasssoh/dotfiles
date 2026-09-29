# Hardware detection

The hardware phase detects the CPU and GPU and installs only the drivers and tools this machine needs. The profiles and package lists live in [`scripts/lib/hardware.sh`](../scripts/lib/hardware.sh).

```bash
./scripts/hardware-detect.sh             # report, packages, codec swaps, manual follow-ups
./scripts/hardware-detect.sh --packages  # package names only
./scripts/hardware-detect.sh --notes     # manual follow-ups only
./scripts/hardware-detect.sh --json      # machine-readable
./install --detect                       # same report, from a bare clone
```

## Profiles

| Profile | Matches | Adds |
|---|---|---|
| Intel modern | Gen8 (Broadwell) and later by name, and any model ≥ `0x8C` (Tiger Lake onwards) | iHD VAAPI driver, oneVPL, `intel_gpu_top`, `thermald` |
| Intel legacy | older or unrecognised Intel | `thermald` |
| AMD | any; Zen is family ≥ `0x17` | `radeontop` |
| every machine | | SOF audio firmware, `power-profiles-daemon`, `fwupd`, `vainfo`/`vulkaninfo`, sensors and inventory tools, `powertop` and `turbostat` |

CPUs newer than the table are matched by these family/model rules, with no edit needed.

## Codec swaps

Fedora's media packages lack H.264/HEVC hardware decoding. The phase replaces them with their RPM Fusion versions, enabling RPM Fusion free and nonfree:

| Fedora | Replaced by |
|---|---|
| `ffmpeg-free` | `ffmpeg` |
| `libva-intel-media-driver` | `intel-media-driver` |
| `mesa-va-drivers` | `mesa-va-drivers-freeworld` |

The table is `hw_codec_swaps` in `hardware.sh`. The phase warns if `vainfo` still shows no H.264 decoding afterwards. Restart Firefox and mpv to pick up the new driver.

## Manual follow-ups

Printed, never run:

- the NVIDIA proprietary driver (third-party repo, kernel module, Secure Boot);
- Lenovo battery conservation mode;
- `i915.enable_dpcd_backlight` for OLED brightness keys.

## Power measurement

`powertop` and `turbostat` are installed but run by hand, as root. On Meteor Lake, trust `turbostat` rather than `powertop` for package C-state residency.

## Running it

```bash
./install hardware              # this phase alone
cc-pkg-mng update --system      # re-run after editing hardware.sh
```

Packages that fail to install are listed at the end of the run.
