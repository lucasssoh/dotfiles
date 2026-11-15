# Audio

PipeWire, the equalizer's filter chains and the Bluetooth audio policy. Levels and devices are in the [mixer](../bar/mixer.md).

The `audio` unit links [`50-equalizer.conf`](../../config/pipewire/50-equalizer.conf), which holds the four five-band filter chains (60, 250, 1k, 4k and 12k Hz) behind the mixer's equalizer. It also links the WirePlumber Bluetooth policy and runs `bt-audio-switch` as a `systemd --user` service.

When this configuration changes, **the audio stack is restarted**, so the sound cuts out for a moment.

If you add a node to the equalizer file, keep the `eq_slot_` or `eq_out_` prefix in its name. Otherwise the bar will think it's a real output device.
