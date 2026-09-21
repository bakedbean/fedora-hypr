# AGENTS.md — working on fedora-hypr

Read this before touching anything. It is the operating manual for agents (and humans)
continuing this project. README.md is the user-facing doc; this file is the one that
explains *how the project is built, why it is shaped this way, and what has already
bitten us*.

## What this is

A Fedora **bootc** (image-mode) desktop that boots into an **Omarchy-flavored Hyprland**
session. The whole OS is defined by this repo: `Containerfile` → OCI image →
`ghcr.io/bakedbean/fedora-hypr:44` → installed with `bootc install`, updated with
`bootc upgrade`, rolled back with `bootc rollback`. Target hardware is a Framework 12
(Intel); proving ground is an external USB drive and a QEMU VM.

Design authority, in order: `docs/superpowers/specs/2026-09-20-fedora-hypr-design.md`
(the spec) → `docs/superpowers/plans/2026-09-20-fedora-hypr.md` (the plan; parts of it
were overridden during implementation — the code and this file win where they differ).

## Layout (what lives where and why)

```
Containerfile              stage rust-build (wsx, waybar-docker) → FROM ghcr.io/ublue-os/base-main:44@sha256:…; packages → COPY --from=rust-build → COPY plymouth → initramfs → COPY system/ → services → lint
                           both FROMs are digest-pinned (see "Updates"); tools/bump-base.sh / `make bump-base` re-pins
build/10-packages.sh       dnf install from build/packages/{fedora,copr}.txt; COPRs from build/repos/*.repo
build/15-initramfs.sh      dracut rebuild so the Plymouth theme is in the initramfs; own layer so it caches across system/ edits
build/20-services.sh       systemctl enable/disable, authselect, cleanup; COPR repo files removed here; gschema compile
system/                    copied verbatim onto / in the image
  usr/bin/fh-*             ~100 helper scripts (menu, theme, capture, toggles, launchers, first-boot, update-check, screensaver)
  usr/bin/{wsx,waybar-docker}  Rust binaries from the rust-build stage (author's Waybar modules)
  etc/environment.d/50-fedora-hypr.conf  FH_PATH only (environment.d cannot expand $HOME/${XDG_RUNTIME_DIR})
  usr/share/uwsm/env       session env sourced by uwsm's sh preloader: ~/.local/bin on PATH, DOCKER_HOST (podman socket)
  usr/share/fedora-hypr/
    default/hypr/          canonical Hyprland config (autostart, bindings/, apps/, toggles/, envs, looknfeel…)
    default/{waybar,mako,swayosd,alacritty}/  canonical app configs (alacritty/ only has screensaver.toml so far)
    themed/*.tpl           theme templates rendered by fh-theme-set-templates
    themes/<name>/         19 themes: colors.toml, backgrounds/, btop.theme, [light.mode]
    flatpaks.txt           installed by fh-first-boot-flatpaks
    logo.txt               HYPEDORA half-block wordmark tte animates for the screensaver (see "Screensaver")
  etc/skel/                per-user seed; hyprland.conf sources the defaults then user overrides
  etc/greetd/config.toml   tuigreet → uwsm start -e -D Hyprland hyprland.desktop (RPM-owned session)
  usr/lib/systemd/system/  fh-first-boot-user.service, fh-first-boot-flatpaks.service
  usr/lib/systemd/system-preset/05-fedora-hypr.preset   disable sshd + getty@tty1 (survives first-boot preset-all)
  usr/share/plymouth/themes/hypedora/   boot splash (Omarchy's script-module theme, HYPEDORA wordmark); selected by etc/plymouth/plymouthd.conf
  usr/lib/bootc/kargs.d/10-fedora-hypr.toml   kernel args "quiet splash" (bootc applies at install, reconciles on upgrade)
  usr/share/glib-2.0/schemas/10-fedora-hypr.gschema.override   system-wide GSettings defaults (Nautilus/GTK show hidden files); compiled in 20-services.sh
tests/check.sh             in-image self-check (~170 checks); runs theme_test.sh, scripts_test.sh, binds_test.sh
tests/migrate_test.sh      HOST-side test of tools/migrate-home.sh on a fabricated home (make test-migrate)
tools/migrate-home.sh      copies the author's Omarchy home onto a target drive (see "Migrating a home from Omarchy")
tools/bump-base.sh         re-pins the Containerfile FROM digests (weekly CI run commits the result; `make bump-base` locally)
tools/gen-plymouth-logo.py regenerates the HYPEDORA logo.png from Omarchy's logo (see "Boot splash")
tools/gen-screensaver-logo.py  regenerates logo.txt (half-block ASCII) reusing gen-plymouth-logo.py's glyph code (see "Screensaver")
vm.sh / make vm            QEMU smoke test (see Debugging)
.github/workflows/build.yml  test-migrate (host) → build (registry layer cache) → check → push :44 and :44-YYYYMMDD on push to main + weekly (weekly also re-pins bases and commits)
```

Three layers, keep them separate:
- **Image layer** (`Containerfile`, `build/`): what is installed. Change = rebuild + `bootc upgrade`.
- **System layer** (`system/usr/…`): config/scripts owned by the image, read-only at runtime.
- **User layer** (`/etc/skel` → `~/.config`): the user's overrides; survives upgrades; the image never edits it after first login.

Rule of thumb: if a file must be reachable by a *relative path from `~/.config`*
(GTK CSS `@import`, hypridle/hyprlock config discovery), it belongs in skel. Everything
else image-owned goes under `/usr/share/fedora-hypr`. Keep `/etc` small (bootc 3-way merges it).

## Daily workflow

```
make build      # rebuild localhost/fedora-hypr:44 (config-only changes are fast; package layer is cached)
make check      # REQUIRED before commit: runs tests/check.sh inside the image; must be all PASS, lint 0 warnings
make vm         # boot the image in QEMU; FRESH=1 make vm reinstalls the disk (needed after image changes)
make push       # manual push to ghcr (normally CI does this)
make bump-base  # re-pin the FROM digests to today's base-main/fedora (CI does this weekly and commits it)
```

To try a change on the machine itself without waiting for CI (~5 min cached, ~15 min cold):
`sudo podman build -t localhost/fedora-hypr:44 .` (root storage — bootc only sees root's) then
`sudo bootc switch --transport containers-storage localhost/fedora-hypr:44` and reboot;
`sudo bootc switch ghcr.io/bakedbean/fedora-hypr:44` returns to the published image. The
SELinux on the machine denies a container reading `--mount=type=bind` sources under `$HOME`
(`user_home_t`) unless they are relabelled, so the Containerfile's bind mounts carry `,z`
(relabels `build/` to `container_file_t`; harmless, and a no-op on CI's Ubuntu runner).

Quick loop without a rebuild (scripts/config only; cannot delete files):
```
podman run --rm -v ./system:/overlay:ro,z -v ./tests:/tests:ro,z localhost/fedora-hypr:44 \
  bash -c 'cp -r /overlay/. / && bash /tests/check.sh'
```

Every change that adds a script, unit, config path, or package **adds a check** to
`tests/check.sh` (or one of the test scripts). Existence checks are the floor; prefer a
behavioral probe (`Hyprland --verify-config`, running the script with a temp `HOME`).
The plan-originated bugs that reached the VM all passed 79/79 existence checks.

Commits: conventional (`feat:`, `fix:`, `build:`, `ci:`, `docs:`, `test:`). Push to `main`
triggers CI; the machine picks it up with `fh-update` (= `bootc upgrade` + flatpak update).
Fedora release bump = change the `FROM` tag (`TAG` is derived from it everywhere) and run
`make bump-base` so the digest matches. **`git pull` before pushing**: the weekly CI run commits a
`build: re-pin base images to current digests` to `main` on your behalf.

## Conventions

- Login shell is **zsh** (the author's shell); `FH_PATH` reaches it via `/etc/profile.d` → `/etc/zprofile`.
- Helper scripts are `fh-*` in `system/usr/bin`, `#!/usr/bin/env bash`, executable,
  `shellcheck -S error` clean. Ported ones carry `# Adapted from Omarchy (MIT) — https://github.com/basecamp/omarchy`
  as line 2. **No other `omarchy` strings anywhere in `system/`** (case-insensitive; filenames too).
- `$FH_PATH=/usr/share/fedora-hypr`; every script defaults it: `: "${FH_PATH:=/usr/share/fedora-hypr}"`.
  User state: `~/.config/fedora-hypr/{current/{theme,theme.name,background},themes,themed,hooks}`,
  toggles in `~/.local/state/fedora-hypr/toggles/hypr/`.
- Binary names in this image: `chromium-browser`, `swayosd-server`/`swayosd-client`, `hyprshot`, `satty`,
  `gpu-screen-recorder`, `impala`, `bluetui`, `wiremix`, `alacritty`, `uwsm-app`, `gum`, `walker`/`elephant`,
  polkit = `systemctl --user start hyprpolkitagent.service`. No compatibility symlinks in `/usr/bin`.
- App launchers are bound on **SUPER SHIFT** (SUPER+letter collides with tiling binds in
  `default/hypr/bindings/tiling-v2.conf`; `tests/binds_test.sh` fails on duplicates).
- Nothing is written under `/var` or `/usr/local` at build time (lint must stay at 0 warnings).
  Runtime state dirs come from `tmpfiles.d`, `StateDirectory=`, or the first-boot scripts.
- Anything the image can't do at build time (users, `/var/home`, Flatpaks) happens in the
  first-boot units. `fh-first-boot-user` is a fast `oneshot` ordered `Before=greetd.service`;
  `fh-first-boot-flatpaks` is `Type=simple` so it **never** gates `graphical.target`.

## Updates

CI builds and pushes `:44`/`:44-YYYYMMDD` on every push to `main`, weekly (Sunday 05:30 UTC, after
ublue's `base-main` rebuild), and on manual dispatch (`gh workflow run build`). A push build pulls
the **registry layer cache** (`ghcr.io/bakedbean/fedora-hypr-cache`, `podman build --cache-from/--cache-to`)
so a `system/`-only change rebuilds just the COPY + services layers (~4–5 min instead of ~15; a
`build/` change still re-runs `dnf`, since bind-mounted context content is part of the layer key —
verified). For the cache to hit, the bases must not move under us: `base-main:44` is rebuilt daily,
so both `FROM`s are **pinned by digest**. The weekly/dispatch run (`FRESH=true`) re-pins them to the
current digests (`tools/bump-base.sh`), builds without `--cache-from`, and — only after check + push
succeed — commits the new pins to `main` as `github-actions[bot]` (a `GITHUB_TOKEN` push does not
re-trigger the workflow). So base/package updates arrive weekly; a push in between builds on last
week's base by design. Nothing on the
machine polls or applies updates automatically: `fh-update-available` (Waybar `custom/update`,
signal 7, hourly `interval`) is an indicator only — it prints `staged`/`available` and exits 0 when
`bootc status --format json`'s `.status.staged` is non-null or the booted image's digest differs
from the registry's (via `skopeo inspect`), else prints nothing and exits 1 so Waybar hides the
module; results are cached under `${XDG_RUNTIME_DIR:-/tmp}/fh-update-available` for 10 minutes.
Clicking it runs `fh-update` (= `bootc upgrade` + flatpak update) in a floating terminal, which
clears the cache and signals Waybar to refresh. `bootc status` requires root, so
`system/etc/sudoers.d/fh-update-available` grants `%wheel` passwordless sudo for exactly one
command line — `/usr/sbin/bootc status --format json`, no arguments allowed to vary — and
`fh-update-available` calls `sudo -n` that exact command (`-n` so it never hangs on a password
prompt if the rule is somehow missing). It's scoped this tightly (one absolute binary path, one
fixed argument list, read-only subcommand) so the access granted is exactly "read bootc status
unprivileged", nothing else `bootc`/`sudo` can do. Any failure (rule missing, offline, skopeo
digest mismatch check failing) is treated as "up to date" — the indicator never shows a false
positive.

## Boot splash

`system/usr/share/plymouth/themes/hypedora/` is Omarchy's Plymouth theme (`ModuleName=script`: centred
logo, fake-then-real progress bar, LUKS password dialog) with `hypedora.script` verbatim apart from the
attribution line, and the same asset PNGs. `logo.png` (869×188) reads **HYPEDORA** in the identical
pixel style: `tools/gen-plymouth-logo.py` recovers the 81×19 cell grid of Omarchy's `logo.png` (pitch 79/8 px),
cuts the letters, derives P (R minus its leg), E (C plus a middle bar) and D (O with a straight left stem),
recomposes with the original 2-cell spacing and colour, and self-checks by regenerating OMARCHY against the
source (mean alpha diff 1/255). Run it in a container if Pillow/numpy are missing on the host (usage in
its docstring); `docs/hypedora-logo-preview.png` is the 2× preview on the splash background.
Three pieces make it show up: `system/etc/plymouth/plymouthd.conf` (`Theme=hypedora`, the file
`plymouth-set-default-theme` would write), `plymouth-plugin-script` in `build/packages/fedora.txt`
(base-main ships only the two-step/text plugins), and an **initramfs rebuild** in `build/15-initramfs.sh` —
base-main ships a prebuilt `/usr/lib/modules/$KVER/initramfs.img`, and Plymouth loads the theme from the
initramfs, so it is regenerated with `dracut --no-hostonly --reproducible --add ostree` (dracut's `plymouth`
module copies the default theme + plugin; `/var/roothome` is created for the `/root` symlink and removed
again; ~1 min of build time, in its own layer right after a COPY of just the Plymouth files so other
`system/` edits don't repeat it). `system/usr/lib/bootc/kargs.d/10-fedora-hypr.toml` adds `quiet splash`
(plymouthd shows the splash only with `splash`/`rhgb` on the cmdline). bootc honours `kargs.d` at
install **and** on `bootc upgrade`/`switch` — the diff between the booted and the new image's kargs.d is
applied to the bootloader entries (bootc docs, "Kernel arguments": "changes to kargs.d files included in
a container build are honored post-install") — so an existing install picks the args up on its next
update; `rpm-ostree kargs` (present in the image) shows the result and is only a fallback for adding
them by hand. Verified so far only inside the image (`tests/check.sh`: theme selected, inside the
initramfs, kargs parse); not yet seen on a real boot — if the splash does not appear, look at
`journalctl -b -u plymouth-start` and `cat /proc/cmdline` (needs `splash`) first.

## Screensaver

Ported from Omarchy's `omarchy-launch-screensaver`/`omarchy-screensaver`: `fh-launch-screensaver`
opens a fullscreen Alacritty (`--class=org.fedorahypr.screensaver`, `--config-file
/usr/share/fedora-hypr/default/alacritty/screensaver.toml`) on every monitor running
`fh-screensaver`, which loops `tte -i ~/.config/fedora-hypr/branding/screensaver.txt --random-effect
...` until a keypress, click, or focus loss (`hyprctl activewindow`'s class no longer matches).
Only the Alacritty branch was ported (ghostty/foot/kitty are not shipped). `tte` is
`terminaltexteffects`, pulled from the `agaspar/omedora-4` COPR (`build/repos/agaspar-omedora-4.repo`
`includepkgs`, `build/packages/copr.txt`). `fh-toggle-screensaver` flips the
`screensaver-off` state toggle `fh-launch-screensaver` checks; `fh-branding-screensaver text|reset`
edits or restores the wordmark (Omarchy's third mode, `image`, needs `omarchy-transcode-ascii`,
which was never ported as `fh-transcode-ascii`, so it was dropped). `fh-system-lock` kills any
running screensaver (`pkill -f org.fedorahypr.screensaver`) so it never fights the lock screen, and
hypridle's skel config starts the screensaver at Omarchy's 150s timeout before locking at 152s
(screensaver activity resets hypridle's own idle timer, hence "half + 2s margin" rather than
150+300). The window rule lives in its own `default/hypr/apps/screensaver.conf` (fullscreen, float,
slide animation), sourced from `apps.conf`.

`system/usr/share/fedora-hypr/logo.txt` is the HYPEDORA wordmark `tte` animates — half-block ASCII
(`█`/`▀`/`▄`/` `, two pixel-grid rows per text line), generated by `tools/gen-screensaver-logo.py`,
which imports `tools/gen-plymouth-logo.py` by file path (its glyph recovery/derivation/composition
code, name has a dash so a plain `import` won't do it) instead of duplicating it, then renders the
composed H Y P E D O R A boolean cell grid as text instead of a PNG. Deterministic (same source PNG
alpha channel in, same text out); run it the same way as `gen-plymouth-logo.py` if Pillow/numpy are
missing on the host. `fh-first-run` seeds `~/.config/fedora-hypr/branding/screensaver.txt` from
`$FH_PATH/logo.txt` if the user doesn't have one yet (mirrors its theme-seeding step); `/etc/skel`
also carries a pre-seeded copy so a freshly created account has it before first login.
`tools/migrate-home.sh` only copies an Omarchy user's `~/.config/omarchy/branding/screensaver.txt`
across if it differs from Omarchy's own stock `~/.local/share/omarchy/logo.txt` — i.e. they
customised it — otherwise it leaves fedora-hypr's HYPEDORA default in place.

## Package sourcing

Hyprland is **not in Fedora repos** (retired since F43 after a hyprutils SONAME break).
Sources, all pinned in `build/repos/*.repo` with `includepkgs` except the Hyprland one:
- `dtutila/hyprland` — hyprland, hyprlock, hypridle, hyprpicker, hyprsunset, hyprpolkitagent, hyprshot, xdg-desktop-portal-hyprland, uwsm (F44 + F45 chroots)
- `washkinazy/wayland-wm-extras` — walker, elephant, swayosd, nerd-fonts-{jetbrainsmono,firacode}
- `mineiro/utility-belt` — impala, bluetui
- `agaspar/omedora-4` — satty, starship, lazygit, lazydocker, mise, gpu-screen-recorder
- `whelanh/omarchy` — hyprland-preview-share-picker
Rust binaries not packaged anywhere (`wsx`, `waybar-docker`) are built in the `rust-build` stage of the
Containerfile (`registry.fedoraproject.org/fedora:44` + cargo; rustc 1.98 there, wsx needs ≥1.85). wsx is
pinned by `ARG WSX_REF` (a commit of github.com/bakedbean/workspacex) — bump it to update wsx; waybar-docker
is `cargo install`ed by version. Cargo registry and target dirs are `--mount=type=cache`d, so a rebuild
after a bump is incremental (~2 min cold). The stage does not ship; only the two binaries are copied.
If a COPR dies, alternatives with F44 builds: `sachesi/hyprland` (no uwsm). Check with
`curl -s 'https://copr.fedorainfracloud.org/api_3/project?ownername=X&projectname=Y' | jq .chroot_repos`.
A failed CI build is safe: the machine keeps its last good image.

## Debugging a boot (learned the hard way)

- `make vm` → QEMU window. Once Hyprland runs, the guest owns the keyboard and the host's
  Hyprland eats SUPER, so inject keys through the monitor socket:
  `echo 'sendkey meta_l-spc' | socat - UNIX-CONNECT:vm/monitor.sock`
- Serial console (login shell in the guest, from the host):
  `socat -,raw,echo=0 UNIX-CONNECT:vm/serial.sock` — log in `eben`/`changeme`. If the shell
  seems to swallow input, run `exec bash --norc` (interactive shells that probe terminal
  capabilities can stall over a dumb serial line). `vm/serial.log` keeps the kernel/systemd boot log.
- Scripted probes from the host: `{ printf 'CMD\n'; sleep 6; } | socat - UNIX-CONNECT:vm/serial.sock`.
- First things to look at in the guest:
  `systemctl list-jobs` (anything "waiting" on `graphical.target`?), `systemctl status greetd fh-first-boot-user`,
  `journalctl --user -b | grep -v xdg-desktop-portal | grep -iE 'uwsm|wayland-wm|Hyprland|Failed'`,
  `hyprctl -i 0 monitors`, `ls ~/.config/fedora-hypr/current/`.

## Things that already bit us (don't repeat)

- Fedora's greetd user is `greetd`, not Arch's `greeter`.
- `chage --lastday 0` (forced password change) breaks tuigreet: PAM returns `NEW_AUTHTOK_REQD`
  and tuigreet can't run the change dialog. We ship `changeme` and prompt in-session (`fh-setup-password`).
- systemd runs `preset-all` on first boot (image ships an empty `/etc/machine-id`), which
  re-enables anything `systemctl disable`d at build time. Use a preset file.
- A `Type=oneshot` unit `WantedBy=multi-user.target` blocks `graphical.target` until it exits;
  uwsm waits 60 s for `graphical.target` before starting the compositor.
- GTK CSS `@import` does not expand `~`; theme CSS for Walker/SwayOSD/Waybar must sit in
  `~/.config` and import the theme with a relative path (`../fedora-hypr/current/theme/x.css`).
- hypridle/hyprlock only look in `~/.config/hypr` (and XDG dirs), not our `default/` tree.
- QEMU adds a default VGA device unless `-vga none`; with two GPUs Hyprland renders on the one
  the window doesn't show. Black screen + captured keyboard = compositor running, look at outputs.
- Walker 2.x needs the `elephant` daemon; both are started from `autostart.conf`.
- `xdg-terminal-exec` needs `X-TerminalArg*` keys in the terminal's `.desktop` (shipped in skel).
- `pkill <name>` can match the calling `fh-restart-<name>` script; use `pkill -x`.
- Omarchy's theme engine builds a sed script from `colors.toml`; values are escaped for `\ | &`
  and theme names are whitelisted (`^[a-z0-9-]+$`) — keep both.
- The Containerfile copies `system/` **after** the package layer on purpose; don't move it.
- Starting `Hyprland` directly (not via `start-hyprland` / `uwsm start … hyprland.desktop`) triggers a startup banner in 0.56+.
- Removing a package an existing account depends on is a *migration*: dropping `fish` left the installed
  user with a login shell that no longer existed, so every terminal AND every `login` bounced. Recovery
  needs to be done from outside; see below. When removing something users may reference from
  `~`/`/etc/passwd`, add a README note and a fallback in the image where cheap.
- **Each bootc deployment has its own `/etc`.** `usermod`/`chsh` in deployment B does nothing for
  deployment A. To fix an unbootable-login state, mount the disk on another machine and edit
  `ostree/deploy/default/deploy/*/etc/passwd` in **every** deployment (a shell present in each, e.g. `/bin/bash`).
- **Editing a bootc disk's `/etc` from a non-SELinux host strips the SELinux label** (`sed -i` writes a new
  file); Fedora's login stack then refuses `/etc/passwd`. After editing, restore it:
  `setfattr -n security.selinux -v 'system_u:object_r:passwd_file_t:s0' .../etc/passwd` (check a sibling
  file with `getfattr -n security.selinux` for the right value). Prefer in-place edits from a running
  deployment whenever one still logs in.
- `chsh` is missing from base-main (lost hardlink of `chfn`); `10-packages.sh` restores it.
- Building **from a terminal inside the Hyprland session** leaks `NOTIFY_SOCKET` (uwsm's compositor unit
  is `Type=notify`, Hyprland passes it on) into `podman build`; crun bind-mounts the socket's directory
  into the build container, so the package layer ends up with an empty `/run/user/1000/systemd/notify`
  and `bootc container lint` warns `nonempty-run-tmp`. `make build` runs podman under `env -u NOTIFY_SOCKET`;
  do the same for any hand-run `podman build`. CI (no session) is unaffected.
- **environment.d cannot reference the manager's own variables** (`$HOME`, `${XDG_RUNTIME_DIR}`): the
  generator only expands what earlier environment.d files defined, so `DOCKER_HOST=unix://${XDG_RUNTIME_DIR}/…`
  reached the session as that literal string (a check that pre-set `XDG_RUNTIME_DIR` for the generator hid
  it). And Fedora's `/etc/profile` does not add `~/.local/bin` (Arch's does), so under uwsm — which builds
  the session env by sourcing `/etc/profile` + `~/.profile` with `sh`, not zsh — Waybar could not find
  user-installed tools (RadioBar). Session-wide env that needs expansion goes in `/usr/share/uwsm/env`
  (uwsm looks in `XDG_CONFIG_HOME`, `XDG_CONFIG_DIRS`, `XDG_DATA_DIRS` for `uwsm/env`); `PATH` is on
  uwsm's `always_export` list. Verify with `systemctl --user show-environment` on a booted system.

## Migrating a home from Omarchy

`tools/migrate-home.sh` copies the author's dotfiles from the Omarchy machine onto a fedora-hypr drive
(`sudo tools/migrate-home.sh /dev/sdX3`, or `--dest DIR` for an already-mounted disk; `--dry-run` first).
It copies shell (`.zshrc` split so the secrets block lands in `~/.zshrc.local`, mode 600), `.ssh`, oh-my-zsh,
tmux/btop/lazygit/git/fastfetch/starship, `dotfiles` + the `.config/nvim` symlink (AstroNvim), RadioBar, fonts,
`.local/share/applications`, Waybar and the `~/.config/hypr/*.conf` overrides — rewriting `omarchy-`→`fh-`,
`$OMARCHY_PATH`→`/usr/share/fedora-hypr`, `~/.cargo/bin/waybar-docker`→`waybar-docker`, native apps→`flatpak run`,
dropping the voxtype module, and rewriting `custom/update`'s `exec`/`on-click`/`tooltip-format` to
`fh-update-available`/`fh-update` instead of dropping it; of `.local/share/applications` only `claude-code-url-handler.desktop`
(verbatim) and `userapp-Firefox-*.desktop` (Exec → `firefox`) are copied. User themes from `~/.config/omarchy/themes`
(old per-app format) go to `~/.config/fedora-hypr/themes/<name>/` with paths rewritten and `colors.toml` generated by
Omarchy's converter when present; backgrounds added only to the current theme go to `~/.config/fedora-hypr/backgrounds/<theme>/`;
`~/Wallpapers` is copied as-is. Rewritten Waybar JSON is validated with jq; `tests/migrate_test.sh` (`make test-migrate`, host-side,
no root) covers the rewrites on a fabricated home. **SELinux caveat**: a non-SELinux host writes unlabelled
files, so as root the script sets `security.selinux` (`user_home_t`, `ssh_home_t` for `.ssh`) on everything
it copied and chowns to 1000:1000; still run `sudo restorecon -Rv ~` after the first login. On a raw bootc
disk the home is under `ostree/deploy/default/var/home/<user>`; the script finds either layout.
`tools/` and `tests/` may say "omarchy" (they rewrite it); `system/` still must not.

## Reference material on the host (read-only)

- Omarchy 3.8.5 install: `~/.local/share/omarchy` (`bin/`, `default/`, `themes/`, `config/`).
  When porting a script: copy, apply the path sed used in the plan (Task 7), rename `omarchy-`→`fh-`,
  drop Arch/pacman/limine/snapper call sites, add the attribution line.
- The author's current Omarchy config: `~/.config/hypr`, `~/.config/waybar`, `~/.config/walker`.
- Omarchy is MIT (`LICENSE.omarchy`).

## Current state and open items

**Lua config migration (blocking Hyprland ≥0.57):** Hyprland deprecates the `.conf`/hyprlang
format in 0.56 and removes it in 0.57 (https://hypr.land/news/26_lua/). All of `default/hypr/**`
and skel are `.conf`; Hyprland is pinned to 0.56.x in `build/packages/copr.txt` until this is done.
Plan: wait for Omarchy to migrate its defaults, then re-port from theirs (tools:
https://github.com/loeclos/hypr-migrate). The deprecation banner at login is expected until then.

Done and verified in the VM: first boot (user, theme render, Flatpaks in background), tuigreet login,
Hyprland session with Waybar/wallpaper/mako/Walker/SwayOSD/polkit, in-session password change,
theme switching, sshd off. CI publishes to ghcr.

Not yet verified (needs the Framework 12): Wi-Fi via impala, brightness/volume keys, suspend/resume,
fingerprint (`fh-setup-fingerprint`; PAM `with-fingerprint` is enabled), touchpad gestures, Flatpak
app class names in `default/hypr/apps/*.conf` (1Password/LocalSend may differ under Flatpak),
`bootc upgrade` → `bootc rollback` round trip, the Plymouth splash on a real boot (see "Boot splash"). Record hardware findings under "Framework 12 notes" in README.

Known deferred minors: `fh-brightness-display-apple` needs unpackaged `asdcontrol`; keybindings viewer
(`SUPER K`) sizing; Waybar weather polls wttr.in every 60 s; no headless parse check for
hypridle/hyprlock beyond config discovery; `bootc-fetch-apply-updates.timer` deliberately not enabled
(it reboots on its own — `fh-update` is manual).

Ideas parked, not started: Niri as a second session (one package + config dir + session file; theme
engine and menu are compositor-agnostic); LUKS + TPM2 for a primary-OS install (`bootc install to-filesystem`
after manual `cryptsetup`).
