# Audio

The equalizer's bands. Levels and devices are in the [mixer](../bar/mixer.md).

The five bands (60 Hz, 250 Hz, 1 kHz, 4 kHz and 12 kHz) and the four equalizers that can run at once are in [`config/pipewire/50-equalizer.conf`](../../config/pipewire/50-equalizer.conf).

After an edit, run `cc-pkg-mng install audio`. The sound cuts out for a moment.

Name a node you add `eq_slot_…` or `eq_out_…`.
