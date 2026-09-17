# Hardware detection

[`scripts/lib/hardware.sh`](../scripts/lib/hardware.sh) maps the CPU's CPUID family/model to a *profile*, and profiles to Fedora packages — because what a machine needs is driven by the microarchitecture generation, not the marketing name. Intel Gen8+ gets the iHD VAAPI driver, oneVPL and `thermald`; any Zen gets `radeontop` (Mesa already ships the AMD VAAPI drivers on Fedora 44); everything gets SOF audio firmware, `power-profiles-daemon` and the VAAPI/Vulkan diagnostics.

It is built to handle CPUs released after it was last edited. Two rules do that:

- **Intel** — family 6, model ≥ `0x8C` (Tiger Lake, the first Xe iGPU) → the modern profile. Lunar Lake, Arrow Lake, Panther Lake, Nova Lake and anything later land on it with no edit.
- **AMD** — family ≥ `0x17` (Zen) → the Zen profile. Zen 6 (expected family `0x1B`) and beyond land on it with no edit.

An unlisted CPU is reported as *matched by forward rule* rather than by name: the package set is already right, and adding the codename to the table is purely cosmetic. Anything that must **not** be automated — the NVIDIA proprietary stack (third-party repo, kmod rebuild, Secure Boot), Lenovo battery conservation mode, the `i915.enable_dpcd_backlight` workaround for OLED brightness keys — is printed as a manual follow-up instead of being run.

```bash
./scripts/hardware-detect.sh            # report + packages + follow-ups
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

## Verification

`scripts/install-hardware.sh` installs with `--skip-unavailable`, which is silent
about names it drops, so it re-queries every package afterwards with `rpm -q` and
names anything that did not land.
