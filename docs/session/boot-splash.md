# Boot splash

The word **coucou** on black when the machine starts, **byebye** when it shuts down, with a thin progress bar and the boot log underneath, one line at a time.

It's optional: `init` asks, and `cc-pkg-mng install plymouth` adds it later.

| | |
|:---:|:---:|
| ![Boot splash](../screenshots/v1.0.0/plymouth-boot.webp)<br>Boot | ![Shutdown splash](../screenshots/v1.0.0/plymouth-shutdown.webp)<br>Shutdown |

## Change it

| Tool | Use |
|---|---|
| [`make-assets.py`](../../config/boot/plymouth/make-assets.py) | Regenerates the images. Use `--width` if your screen isn't 1920 px wide |
| [`simulate.py`](../../config/boot/plymouth/simulate.py) | Renders the animation to a video. Takes `--width/--height`, or `--heads 1920x1200,3840x2160` for several screens |
| [`preview.sh`](../../config/boot/plymouth/preview.sh) | Shows the real splash on a spare console. Takes `--sweep`, `--password` and `--status` |

The layout and animation are in [`theme/coucou.script`](../../config/boot/plymouth/theme/coucou.script). With several screens, the splash is sized for the smallest one.

## If the splash doesn't show

Add `plymouth.debug` to the kernel command line, then read `/var/log/plymouth-debug.log`.
