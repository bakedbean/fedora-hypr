<p align="center">
  <img src="docs/hypedora-logo.png" alt="HYPEDORA" width="320">
</p>

# Hypedora

A [bootc](https://containers.github.io/bootc/) image, built on `ghcr.io/ublue-os/base-main`, that boots
into an opinionated Hyprland desktop on Fedora: an immutable, container-built, atomically-updated
image with a curated look, keybindings, a theme engine, and a helper-script workflow driven from a
single menu. The image and its on-disk paths keep the `fedora-hypr` name (`ghcr.io/bakedbean/fedora-hypr`,
`/usr/share/fedora-hypr`, `~/.config/fedora-hypr`, `fh-*` scripts).

## Host prereqs

- `podman` — rootless is enough for `make build` / `make check`. `make vm` and installing to a disk
  need rootful podman too, since `bootc install` requires loop devices.
- For `make vm`: QEMU + OVMF/UEFI firmware and KVM. On Arch:
  ```
  sudo pacman -S --needed qemu-desktop edk2-ovmf
  ```
  Your user needs KVM access (typically via the `kvm` group) and `sudo`, since `vm.sh` shells out to
  `sudo podman` to run `bootc install to-disk`.

## `make build` / `make check` / `make vm`

```
make build   # podman build -t localhost/fedora-hypr:<TAG> .
make check   # build, then run tests/check.sh inside the image
make vm      # build, then install to vm/disk.raw and boot it in QEMU
```

`TAG` is derived from the `FROM ghcr.io/ublue-os/base-main:<TAG>` line in the `Containerfile`, so it
always tracks the base image's Fedora version (currently `44`).

`make vm` runs `vm.sh`:

- First run: creates a 20G `vm/disk.raw`, loads the image into rootful podman's store (`podman save |
  sudo podman load`, skipped if rootful podman already has the same image id), and runs `bootc install to-disk
  --via-loopback --wipe --filesystem btrfs --generic-image` against it inside a privileged container.
- Later runs: boot the existing `vm/disk.raw` as-is (no reinstall).
- `FRESH=1 make vm`: force a wipe and reinstall to `vm/disk.raw` even if it already exists — use this
  after rebuilding the image to pick up changes.
- Exposes a QEMU monitor on `vm/monitor.sock` and the guest serial console on `vm/serial.sock` (the
  install adds `console=ttyS0,115200 console=tty0` kargs, so a `serial-getty@ttyS0` login and the
  kernel/systemd boot log are on it). Serial console: `socat -,raw,echo=0 UNIX-CONNECT:vm/serial.sock`
  (Ctrl-C to detach); `vm/serial.log` keeps a copy. Log in as `eben`/`changeme`.
  Your host's Hyprland intercepts SUPER combos before QEMU sees them, so inject keys through the
  monitor instead, e.g. to open a terminal with SUPER+RETURN in the guest:
  ```
  echo 'sendkey meta_l-ret' | socat - UNIX-CONNECT:vm/monitor.sock
  # or: echo 'sendkey meta_l-ret' | nc -U vm/monitor.sock
  ```
  (`sendkey meta_l-shift-b`, `sendkey ctrl-alt-f2`, … — key names as in `qemu-system-x86_64
  -monitor stdio` → `sendkey ?`). Once Hyprland is running in the guest, Ctrl+Alt+Fn VT switching
  from the QEMU window no longer works because the compositor owns input; use the monitor
  (`sendkey ctrl-alt-f2`) or read `vm/serial.log` instead.
- Boots with UEFI (OVMF), virtio-gpu (GL) as the only GPU (`-vga none`; with QEMU's default VGA
  card also present Hyprland renders on the wrong DRM card and the window stays black), 4 GB RAM,
  virtio net/keyboard/tablet, and a pipewire audio device. OVMF firmware paths default to the Arch locations
  (`/usr/share/edk2/x64/OVMF_{CODE,VARS}.4m.fd`) and can be overridden with the `OVMF_CODE` /
  `OVMF_VARS` env vars on other distros.
- Expected boot sequence: GRUB → Plymouth → tuigreet on tty1. Log in, set a password → Hyprland with
  Waybar and the default wallpaper.

If loading the image into rootful podman's store fails on your host, fall back to `make push` then, on
the host, `sudo podman pull ghcr.io/bakedbean/fedora-hypr:44` and
`IMAGE=ghcr.io/bakedbean/fedora-hypr:44 ./vm.sh`.

## Install to a disk

**First install, from a local build** (no need to push to a registry first):

```
podman save localhost/fedora-hypr:44 | sudo podman load
sudo podman run --rm --privileged --pid=host --security-opt label=type:unconfined_t \
  -v /dev:/dev -v /var/lib/containers:/var/lib/containers \
  localhost/fedora-hypr:44 \
  bootc install to-disk --wipe --filesystem btrfs /dev/sdX
```

Replace `/dev/sdX` with the real target disk — this wipes it. Confirm the target first with
`lsblk -o NAME,SIZE,TRAN,MODEL`.

**Moving to the CI-built image** once it's pushed to `ghcr.io` (see CI below):

```
sudo bootc switch ghcr.io/bakedbean/fedora-hypr:44
```

This re-points the booted system at the registry image without a reinstall; `bootc upgrade` from then
on pulls new layers of that image.

## First login

The disk boots to tuigreet on tty1. Log in as `eben` with password `changeme`. Once Hyprland is up, a
floating terminal prompts you to change it (`fh-setup-password`; also under Setup → Password in
`fh-menu`) — the password is not expired at the PAM level because tuigreet cannot run the
change-password conversation. SSH is disabled by default, so the window with the default password is
local-only. The user and its default theme are created by `fh-first-boot-user.service` before greetd
comes up, so the first session already has its colours and wallpaper. The Flatpak apps in `system/usr/share/fedora-hypr/flatpaks.txt` (Signal, Spotify,
1Password, …) are installed in the background by `fh-first-boot-flatpaks.service` once the network is
up; it retries every minute until every app is present. Watch it with
`journalctl -fu fh-first-boot-flatpaks`. To turn SSH on: `sudo systemctl enable --now sshd` (a
`system-preset` keeps it off across the first-boot `preset-all`).

**Fingerprint:** PAM is already configured for fingerprint auth (login, sudo, polkit, hyprlock). Run
`fh-setup-fingerprint` (or Setup → Fingerprint in the `fh-menu`) to enrol a finger.

## Day 2

- A Waybar icon (`custom/update`, `fh-update-available`) appears in the bar when an update is
  available or already staged; click it to run `fh-update` in a floating terminal. It polls hourly
  and on a Waybar refresh signal, caches its result for 10 minutes, and never shows a false
  positive — no timer runs on the machine on its own, this is purely an indicator.
- `fh-update` — pull and stage the latest image (wraps `bootc upgrade`); reboot to apply.
- `sudo bootc rollback` — boot the previous deployment if an update regresses something; reboot to
  apply. `/home` is untouched by upgrades and rollbacks.
- `sudo bootc switch ghcr.io/bakedbean/fedora-hypr:44-YYYYMMDD` — pin to a specific known-good dated
  build instead of tracking the rolling `:44` tag; switch back to `:44` later to resume tracking.
- Boot splash: the image ships a Plymouth theme (`hypedora`: centred HYPEDORA wordmark and progress bar)
  and the `quiet splash` kernel args in `/usr/lib/bootc/kargs.d/10-fedora-hypr.toml`. bootc applies
  `kargs.d` on install and reconciles it on upgrade, so installs made before the theme landed get the
  args with their next `fh-update`; if the splash still doesn't show, check with `rpm-ostree kargs` and
  add them once with `sudo rpm-ostree kargs --append=quiet --append=splash` (then reboot).
- Screensaver: an Alacritty-based terminal screensaver (animated by `tte` from
  `terminaltexteffects`) starts after 2.5 minutes idle and shows the HYPEDORA wordmark
  (`~/.config/fedora-hypr/branding/screensaver.txt`, seeded from `logo.txt`) with a random text
  effect; the system locks 2 minutes after that. Toggle it off with Trigger → Toggle → Screensaver
  in `fh-menu` (or `fh-toggle-screensaver`); edit or restore its wordmark with Style → Screensaver
  (or `fh-branding-screensaver text|reset`).

## CI

`.github/workflows/build.yml` builds the image, runs `tests/check.sh` inside it, and pushes
`ghcr.io/bakedbean/fedora-hypr:44` and `ghcr.io/bakedbean/fedora-hypr:44-YYYYMMDD` on every push to
`main`, on a weekly schedule (Sunday 05:30 UTC, after ublue's `base-main` rebuilds), and on manual
dispatch (`gh workflow run build`). The tag is
derived from the `Containerfile`'s `FROM` line the same way the `Makefile` derives it, so it's never
hard-coded in the workflow.

## Layout

```
fedora-hypr/
├── Containerfile               # FROM ghcr.io/ublue-os/base-main:44 … RUN bootc container lint
├── build/                      # scripts run during image build
│   ├── 10-packages.sh          # dnf install from Fedora repos + pinned COPRs
│   ├── 15-initramfs.sh         # rebuild the initramfs so the Plymouth theme is inside it (own layer: cached across config edits)
│   ├── 20-services.sh          # systemctl enable greetd + first-boot units, disable sshd, authselect; drop COPR repo files; gsettings
│   ├── packages/                 # fedora.txt / copr.txt package lists
│   └── repos/                    # pinned .repo files for COPRs used at build time
├── system/                     # copied verbatim onto / in the image (COPY system/ /)
│   ├── usr/bin/fh-*             # helper scripts (theming, launchers, toggles, first-boot, update, …)
│   ├── usr/share/fedora-hypr/
│   │   ├── default/               # canonical hypr/waybar/mako/swayosd/hyprlock/hypridle configs
│   │   ├── themed/                # theme-parameterized templates (*.tpl)
│   │   ├── themes/<name>/         # ported theme color definitions
│   │   ├── flatpaks.txt           # Flatpaks installed by fh-first-boot-flatpaks
│   │   └── icons/                 # icons for the stock TUI launcher entries (Docker, Disk Usage)
│   ├── usr/lib/systemd/system/    # fh-first-boot-user.service, fh-first-boot-flatpaks.service
│   ├── usr/lib/tmpfiles.d/        # /var/cache/tuigreet
│   ├── usr/lib/systemd/system-preset/ # keep sshd/getty@tty1 disabled through first-boot preset-all
│   ├── usr/lib/bootc/kargs.d/     # quiet splash
│   ├── usr/share/plymouth/themes/hypedora/  # boot splash (HYPEDORA logo; tools/gen-plymouth-logo.py)
│   └── etc/
│       ├── skel/.config/          # thin per-user config seeded on first login, sources the defaults
│       │                            # (hypridle.conf / hyprlock.conf live here: both only search ~/.config/hypr)
│       ├── skel/.local/share/applications/  # Alacritty.desktop (xdg-terminal-exec keys), Docker + Disk Usage TUI launchers
│       ├── greetd/config.toml     # tuigreet → uwsm start -e -D Hyprland hyprland.desktop (RPM-owned session)
│       ├── plymouth/plymouthd.conf # Theme=hypedora
│       └── ...                    # NetworkManager, environment.d, sudoers.d, profile.d
├── tests/                       # check.sh (in-image self-check) + scripts_test.sh, theme_test.sh, binds_test.sh
├── tools/                       # migrate-home.sh (existing home → drive), gen-plymouth-logo.py (HYPEDORA wordmark)
├── vm.sh                        # install-to-raw-disk + QEMU boot for local smoke testing
├── Makefile                     # build / shell / check / push / vm targets
└── .github/workflows/build.yml  # CI: build, self-check, push to ghcr.io
```

Three layers:

- **Image layer** (`Containerfile`, `build/`): what's installed. Change = rebuild + `bootc upgrade`.
- **System layer** (`system/`): config and scripts owned by the image under `/usr`, read-only on the
  running system, versioned with the image.
- **User layer** (`~/.config`, seeded from `/etc/skel` on first login): the user's overrides, persisted
  across upgrades.

## Attribution

Parts of the helper scripts, theme engine, default configs and boot-splash script are adapted from
third-party MIT-licensed work; the copyright and permission notice is in `LICENSE-THIRD-PARTY`, and
each adapted file says so in its header. Everything else is under `LICENSE`.

## Framework 12 notes

_(Verification on Framework 12 hardware is tracked as a follow-on task; this section will be filled in
with any hardware-specific findings — e.g. required kernel args — once that pass is done.)_
