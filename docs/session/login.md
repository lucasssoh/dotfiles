# Login screen

A login screen on the first console, with greetd and tuigreet, in JetBrains Mono. After you log in, the word **coucou** stays until the desktop shows.

It's optional: `init` asks, and this adds it later:

```bash
cc-pkg-mng install greeter
```

It replaces the display manager you had.

| To change | Edit |
|---|---|
| The greeter | [`greetd/`](../../config/boot/login/greetd/) |
| The console font | Run [`make-console-font.py`](../../config/boot/login/make-console-font.py) (`--cell WxH`, `--preview`). It writes to [`console/`](../../config/boot/login/console/) |
