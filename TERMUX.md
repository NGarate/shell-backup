# Herdr from Termux (Android)

Herdr runs on your computer; Termux connects to its named session. Prepare SSH
access and install Herdr on that computer first. `setup.sh` targets desktop
macOS/Linux, not native Android.

## Connection and widget

Install Termux and Termux:Widget from the same source. In Termux:

```bash
pkg install openssh
pkg install mosh  # Optional; also requires mosh-server on the computer and UDP access
mkdir -p ~/.ssh ~/.shortcuts
chmod 700 ~/.ssh ~/.shortcuts
```

Add an alias to `~/.ssh/config`, replacing the example values:

```sshconfig
Host laptop
    HostName 192.168.1.20
    User your-user
    Port 22
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
    ConnectTimeout 10
    ServerAliveInterval 30
    ServerAliveCountMax 3
```

The key must already be authorized on the computer. First run `ssh laptop` to
verify the connection and host fingerprint. Passwords and encrypted keys use
normal SSH prompts; use an SSH agent if you want to avoid repeated key prompts.

From a copy of this repository in Termux:

```bash
cp termux-shortcuts/Herdr ~/.shortcuts/Herdr
chmod 700 ~/.shortcuts/Herdr
```

Edit `HOST` and `SESION` at the top of the copied shortcut (defaults: `laptop`
and `personal`). User, port and key are configured only in `~/.ssh/config`.
`TRANSPORTE=auto` tries Mosh when available, then SSH if it fails;
`TRANSPORTE=ssh` uses SSH directly. Detaching normally or cancelling Mosh does
not open a new connection. The shortcut loads remote Bash's login environment
and includes `~/.local/bin` and `/opt/homebrew/bin` when finding Herdr.

Add the Termux:Widget widget to the Android home screen, refresh it and tap
**Herdr**. To diagnose a failure, run `bash ~/.shortcuts/Herdr` in Termux.

On the desktop, use the same session:

```bash
herdr session attach personal
```

Detach with **Ctrl+Space**, then `q`. Reopen the widget to resume. Herdr keeps
the pane processes running after disconnecting; the computer must remain
reachable. Mosh also needs `mosh-server` on the host and UDP connectivity,
normally ports 60000–61000.

## Touch buttons

[termux.properties](./termux.properties) contains the active settings and two
rows of buttons. Copy it to `~/.termux/termux.properties` after creating
`~/.termux`. If you already have settings, back up the file and merge the values,
replacing the existing `extra-keys` block including its continuation lines.
Run `termux-reload-settings` to apply.

| Button | Tap | Swipe up |
|---|---|---|
| ESC / TAB | Escape / Tab | Herdr help / sidebar |
| CTRL | Control | Alt |
| Arrows | Arrow key | Focus pane in that direction |
| Tab+ | New tab | New workspace |
| Ant / Sig | Previous / next tab | Page Up / Page Down |
| Div | Split right | Split down |
| Work | Workspaces | Goto picker |
| Zoom | Zoom pane | Copy mode |
| Herdr | Prefix | Detach |

The macros expect **Ctrl+Space**, configured by `setup.sh`. On an older or
manually configured host, set this in `~/.config/herdr/config.toml`:

```toml
[keys]
prefix = "ctrl+space"
```

If `[keys]` exists, edit its `prefix` without duplicating the section. Reload
Herdr's configuration or reattach. In pickers, use ordinary arrows, Enter and Esc.

For missing glyphs, put your chosen Nerd Font TTF at `~/.termux/font.ttf` and run
`termux-reload-settings`. Touch gestures, rendering and real remote reconnects
still need validation on Android; the repository tests mock the connection.
