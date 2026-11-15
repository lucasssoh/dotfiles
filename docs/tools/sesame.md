# Sésame

Sésame brings every password asked for outside a terminal to one card in the middle of the screen. It shows what asks and which command asked for it, then waits for you. `su` and `sudo` keep asking in the terminal.

| Who asks | When | The card |
|---|---|---|
| **The system** (polkit) | An app or a command needs administrator rights: `pkexec`, a service to start, a setting in Balise | Your password |
| **ssh** | A `git push`, `git pull` or `ssh` to a server, with a passphrase-protected key | The key's passphrase, or a host to trust |
| **git** | Signing in to a remote over HTTPS | User name and password |
| **gpg** | Signing or decrypting with a protected key | The key's passphrase |

Under **Asked by**, the card lists the processes behind the request, the one asking last. Run by an agent, a push reads `claude › git push origin master › ssh git@github.com …`. `Return` answers and `Esc` cancels; the command then fails as if you had typed nothing. While the card is up, it takes the keyboard and the mouse.

No key is kept in memory, so every push asks again. That way nothing pushes without you. ssh and git use the card from the terminal too (`SSH_ASKPASS`, set in [`hyprland.lua`](../../config/hyprland/hypr/hyprland.lua)). gpg uses it unless `gpg-agent.conf` already sets a `pinentry-program`; on a text console, gpg falls back to its usual pinentry.

`qs -c bar ipc call bar sesameDemo polkit` shows the card with a made-up request (`ssh`, `polkit`, `gpg`, `retry` or `confirm`), so you can look at it. Answering it sends nothing.

The service behind it runs as `systemd --user` (`sesame.service`). It's built from [`sesame-src`](../../config/hyprland/sesame-src/) on edge and installed as a package on stable, like Manette.
