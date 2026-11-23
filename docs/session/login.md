# Login screen

A login screen on the first console, with greetd and tuigreet, in JetBrains Mono. After login, the word **coucou** stays until the desktop shows.

It's optional: `init` asks, and this adds it later:

```bash
cc-pkg-mng install greeter
```

It replaces the display manager in place.

Another desktop installed next to coucou-shell can be picked in the session menu (`F3`). coucou-shell's background services only run in Hyprland.

| To change | Edit |
|---|---|
| The greeter | [`greetd/`](../../config/boot/login/greetd/) |
| The console font | Run [`make-console-font.py`](../../config/boot/login/make-console-font.py) (`--cell WxH`, `--preview`). It writes to [`console/`](../../config/boot/login/console/) |
