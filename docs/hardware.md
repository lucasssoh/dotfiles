# Hardware detection

[`scripts/lib/hardware.sh`](../scripts/lib/hardware.sh) maps the CPU's CPUID family/model to a *profile*, and profiles to Fedora packages — because what a machine needs is driven by the microarchitecture generation, not the marketing name. Intel Gen8+ gets the iHD VAAPI driver, oneVPL and `thermald`; any Zen gets `radeontop` (Mesa already ships the AMD VAAPI drivers on Fedora 44); everything gets SOF audio firmware, `power-profiles-daemon` and the VAAPI/Vulkan diagnostics.

It is built to handle CPUs released after it was last edited. Two rules do that:

- **Intel** — family 6, model ≥ `0x8C` (Tiger Lake, the first Xe iGPU) → the modern profile. Lunar Lake, Arrow Lake, Panther Lake, Nova Lake and anything later land on it with no edit.
- **AMD** — family ≥ `0x17` (Zen) → the Zen profile. Zen 6 (expected family `0x1B`) and beyond land on it with no edit.

An unlisted CPU is reported as *matched by forward rule* rather than by name: the package set is already right, and adding the codename to the table is purely cosmetic. Anything that must **not** be automated — the NVIDIA proprietary stack (third-party repo, kmod rebuild, Secure Boot), Lenovo battery conservation mode, the `i915.enable_dpcd_backlight` workaround for OLED brightness keys — is printed as a manual follow-up instead of being run.

```bash
./scripts/hardware-detect.sh            # report + packages + swaps + follow-ups
./scripts/hardware-detect.sh --packages # bare list, one per line
./scripts/hardware-detect.sh --json     # machine-readable
```

## When it runs

The hardware phase is part of `./install system`, and can be run alone:

```bash
./install hardware
```

`cc-pkg-mng` treats it as a target of its own: editing `scripts/lib/hardware.sh`,
`scripts/install-hardware.sh` or `scripts/hardware-detect.sh` marks the hardware
phase as changed, which `cc-pkg-mng update --system` then picks up.

## Codec swaps

Fedora builds its media stack without the patent-encumbered codecs, and the
result is **silent**: every package installs, `vainfo` reports a working
driver, and H.264/HEVC video decodes on the CPU anyway. Measured in a Firefox
video tab on the IdeaPad, the decoder process sat at ~18% of a core with no
`/dev/dri` handle open at all, and the fan ran on an otherwise idle machine.
Nothing logs an error — heat is the only symptom.

So after the package block, `install-hardware.sh` replaces each stripped
package with its RPM Fusion twin (`hw_codec_swaps` in `lib/hardware.sh` holds
the table):

| Stripped | Full | Repo |
| --- | --- | --- |
| `ffmpeg-free` | `ffmpeg` | RPM Fusion **free** |
| `libva-intel-media-driver` | `intel-media-driver` | RPM Fusion **nonfree** |
| `mesa-va-drivers` | `mesa-va-drivers-freeworld` | RPM Fusion **free** |

Both repos get enabled, not just free. Unlike the NVIDIA stack — which stays a
manual follow-up because it needs a kmod rebuild, a reboot and can break Secure
Boot — this is safe to automate: it is a package swap and nothing else.

A pair is applied as a `dnf swap` when the stripped half is installed and as a
plain install when it is not, because both cases occur: `ffmpeg` carries
`Conflicts: ffmpeg-free` so a plain install *fails*, while `mesa-va-drivers`
does not exist on Fedora 44 at all (folded into `mesa-dri-drivers`) so its
freeworld counterpart is simply added. The freeworld and nonfree drivers install
to `/usr/lib64/dri-freeworld` and `/usr/lib64/dri-nonfree`, both of which libva
searches *before* `/usr/lib64/dri` — which is what makes them win.

Because the broken state looks perfectly healthy at the package level, the step
verifies the **capability** rather than the install: it greps `vainfo` for an
H.264 `VAEntrypointVLD` and warns if it is still missing. Note that a running
application keeps whatever driver it loaded at startup, so Firefox and mpv need
a restart before the change shows up.

## Verification

`scripts/install-hardware.sh` installs with `--skip-unavailable`, which is silent
about names it drops, so it re-queries every package afterwards with `rpm -q` and
names anything that did not land.
