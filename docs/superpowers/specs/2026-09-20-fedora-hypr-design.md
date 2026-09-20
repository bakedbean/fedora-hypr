# fedora-hypr — Design

**Date:** 2026-09-20
**Status:** approved (brainstorm complete)
**Target hardware:** Framework Laptop 12 (Intel), proving out on external USB drive `/dev/sda`

## Goal

A Fedora Atomic (bootc) desktop image running Hyprland that reproduces the parts
of Omarchy the author likes — theme switching, the app/tool stack, the menu and
keybindings, and painless updates — without depending on Arch or on the upstream
Omarchy repo. The whole machine is defined by one git repo; changes ship as image
rebuilds and are applied with `bootc upgrade`, with rollback built in.

Success = "proved out" when, on the Framework 12 booted from the USB drive:

- boots to Hyprland via greetd/tuigreet
- Wi-Fi, brightness, audio, suspend/resume, fingerprint, touchpad gestures work
- `fh-theme-set` switches Hyprland, Waybar, mako, Alacritty, Walker, wallpaper together
- `fh-menu` covers the `omarchy-menu` entries the author actually uses
- a rebuild → `bootc upgrade` → `bootc rollback` round-trips cleanly

Non-goals (for now): Niri, LUKS/TPM, NVIDIA, tracking upstream Omarchy, Neovim
theming (AstroNvim handles its own colorschemes).

## Decisions made during brainstorming

| Question | Decision | Why |
|---|---|---|
| Fedora flavor | bootc image on `ghcr.io/ublue-os/base-main:44` | Machine defined by a repo; ublue maintains kernel/firmware/codec base incl. Framework quirks; no desktop payload |
| Port strategy | Clean-room, Omarchy-flavored (not baking upstream Omarchy) | Full ownership; no patch set against a fast-moving upstream; only ~40 of Omarchy's 284 scripts are actually used |
| Compositors | Hyprland only | Niri deferred |
| Disk encryption | none | Proof-of-concept on external drive; `bootc install to-disk` doesn't do LUKS natively |
| Login manager | greetd + tuigreet | Lighter than SDDM; login screen is the least "Omarchy" part |
| Containers | podman (rootless) with `docker` alias | Fedora-native; rootful docker in an immutable image is friction |
| Browser | Firefox (primary) + Chromium (web apps) both in image | Native portals/PipeWire integration; `chromium --app=URL` needs a native binary |
| Editor | neovim package only; AstroNvim config is a user dotfile | Author uses AstroNvim, not omarchy-nvim |
| Dev toolchains | `mise` in image; Fedora `toolbox` available | No Arch distrobox — Arch was never a preference |
| GUI apps | Flatpak, installed by first-boot service | Keep image small; apps update independently |
| Remote | `github.com/bakedbean/fedora-hypr`, public | CI builds + pushes to `ghcr.io/bakedbean/fedora-hypr` |

## 1. Repository layout

```
fedora-hypr/
├── Containerfile              # FROM ghcr.io/ublue-os/base-main:44 … RUN bootc container lint
├── build/                     # scripts run during image build
│   ├── 10-packages.sh         # dnf install from Fedora repos + COPRs
│   ├── 20-source-builds.sh    # walker/elephant/wiremix/impala/bluetui (multi-stage)
│   └── 30-services.sh         # systemctl enable greetd, fh-first-boot, timers
├── system/                    # copied verbatim onto / in the image
│   ├── usr/bin/fh-*           # helper scripts (see §3)
│   ├── usr/share/fedora-hypr/
│   │   ├── default/           # canonical hypr/waybar/mako/walker/alacritty configs
│   │   └── themes/<name>/     # ported theme dirs
│   ├── usr/lib/systemd/{system,user}/
│   └── etc/skel/.config/      # thin per-user config that sources the defaults
├── Makefile                   # build / lint / vm / install targets
├── .github/workflows/build.yml
└── docs/superpowers/specs/
```

Three layers:

- **Image layer** (`Containerfile`, `build/`): what is installed. Change = rebuild + `bootc upgrade`.
- **System layer** (`system/`): config and scripts owned by the image under `/usr`. Read-only on the
  running system; versioned with the image. Equivalent of Omarchy's `~/.local/share/omarchy/{bin,default,themes}`.
- **User layer** (`~/.config`, seeded from `/etc/skel` on first login): the author's overrides.
  Persist across upgrades. Same default/override split Omarchy uses.

The author's existing `~/dotfiles` (fish, tmux, AstroNvim, starship) stays a separate repo cloned on
first login; the image does not own it.

## 2. Package layer

**Image — Fedora repos**

- Compositor: `hyprland hyprlock hypridle hyprpicker hyprsunset xdg-desktop-portal-hyprland xdg-desktop-portal-gtk uwsm`
- Shell: `waybar mako swaybg swayosd grim slurp satty wl-clipboard brightnessctl playerctl pamixer wireplumber polkit-gnome`
- Session/system: `greetd tuigreet plymouth power-profiles-daemon iwd bluez avahi nss-mdns cups`
- Framework 12: `fprintd fwupd intel-media-driver`
- Terminal/CLI: `alacritty fish bash-completion starship tmux neovim btop bat eza fd fzf ripgrep zoxide jq dust tldr lazygit fastfetch imagemagick mise podman podman-docker`
- Browsers: `firefox chromium`
- Desktop apps needing system integration: `nautilus sushi gvfs-mtp gvfs-nfs gvfs-smb evince imv mpv gnome-calculator gnome-keyring gnome-disk-utility fcitx5 fcitx5-gtk fcitx5-qt`
- Fonts/themes: JetBrains Mono Nerd Font, `google-noto-*` (sans, cjk, emoji), `fontawesome-fonts`, `yaru-icon-theme`, `gnome-themes-extra`, `kvantum`

Exact Fedora package names to be verified during implementation (`dnf search` inside the base image);
items known to be uncertain: nerd-font packaging, `hyprsunset`, `swayosd`, `ghostty`.

**Image — COPR or source-built** (not in Fedora)

- `walker` + `elephant` (Go; multi-stage build)
- `wiremix`, `impala`, `bluetui` (Rust; `cargo install` in build stage, copy binaries)
- `hyprland-preview-share-picker` (source)
- `ghostty` (Fedora repo if present, else COPR `pgdev/ghostty`)
- `gum` (GitHub release binary)
- `gpu-screen-recorder` (COPR)

**Flatpak** (installed by `fh-first-boot.service`, not in image)

`signal, spotify, obsidian, typora, libreoffice, obs-studio, kdenlive, pinta, xournalpp, localsend, 1password`

**Dropped** (Arch/Omarchy-install specific): `yay expac kernel-modules-hook ufw ufw-docker tzupdate
plocate tobi-try omarchy-walker omarchy-nvim asdcontrol cliamp aether brave docker`.
`firewalld` comes with base-main.

## 3. Config & script layer

Naming: all helper scripts are `fh-*` so they cannot collide with another image if the author
ever `bootc switch`es.

| Image path | Contents | Omarchy equivalent |
|---|---|---|
| `/usr/share/fedora-hypr/default/` | canonical hypr/waybar/mako/walker/alacritty configs | `~/.local/share/omarchy/default/` |
| `/usr/share/fedora-hypr/themes/<name>/` | per-theme colour fragments + wallpapers | `~/.local/share/omarchy/themes/` |
| `/usr/bin/fh-*` | helper scripts | `~/.local/share/omarchy/bin/` |
| `/etc/skel/.config/` | thin user config sourcing the defaults | Omarchy `~/.config` seeding |
| `/usr/lib/systemd/{system,user}/` | greetd config, `fh-first-boot.service` | install scripts |

**Hyprland config pattern.** `~/.config/hypr/hyprland.conf` is a short file of `source =` lines:
first `/usr/share/fedora-hypr/default/hypr/*.conf`, then local `bindings.conf`, `monitors.conf`,
`input.conf`, `looknfeel.conf`, `envs.conf`, `autostart.conf` overrides. Image updates change
the defaults; overrides persist. Initial override content is ported from the author's current
`~/.config/hypr/*.conf`.

**Theme system.** `fh-theme-set <name>`:
1. symlink `~/.config/fedora-hypr/current/theme` → `/usr/share/fedora-hypr/themes/<name>`
2. link/copy each app's colour file into place (hypr, waybar, mako, alacritty, walker, gtk)
3. link `~/.config/fedora-hypr/current/background` → chosen wallpaper
4. reload: `hyprctl reload`, `pkill -SIGUSR2 waybar`, `makoctl reload`, restart swaybg

`fh-theme-menu` is a Walker dmenu picker over the theme dirs. Omarchy's 19 theme dirs are plain
config fragments and port near-verbatim; ported initially: the ones in the author's current install.

**Menu.** `fh-menu` ports `omarchy-menu` (Walker dmenu mode): Apps / Learn / Theme / Setup /
Update / Power. Arch-specific entries become bootc ones: Update → `fh-update`,
Snapshots → `bootc rollback` picker.

**Scripts ported (~40).** Only those bound to keys or menu entries: theme-set/theme-menu,
screenshot/screenrecord, webapp-install/remove, launch-* wrappers, toggle-* (nightlight, idle,
waybar), power-menu, update, keybindings viewer, first-run, monitor-watch, powerprofiles-init.

**Updates.**
- `fh-update` = `bootc upgrade && flatpak update -y` then prompt to reboot.
- CI rebuilds daily and on push; `bootc-fetch-apply-updates.timer` stages images automatically.
- Fedora major bump = change the `FROM` tag; same upgrade/rollback path.

**First boot / first login.**
- `fh-first-boot.service` (system oneshot, `ConditionPathExists=!/var/home/eben`): create user
  `eben` (wheel, home from `/etc/skel`, temporary expired password), add Flathub, install the
  Flatpak list.
- `fh-first-run` (from Hyprland `exec-once`, guarded by a marker file): set default theme and
  wallpaper, offer fingerprint enrollment.

## 4. Install and test loop

**One-time install from the current Arch machine (rootful podman):**

```
sudo podman build -t localhost/fedora-hypr:44 .
sudo podman run --rm -it localhost/fedora-hypr:44 bash      # optional inspection
sudo podman run --rm --privileged --pid=host \
  --security-opt label=type:unconfined_t \
  -v /dev:/dev -v /var/lib/containers:/var/lib/containers \
  localhost/fedora-hypr:44 \
  bootc install to-disk --wipe --filesystem btrfs /dev/sda
```

This destroys the Omarchy 3.2.2 trial install currently on `/dev/sda`; the author is asked to
confirm at that step and offered a copy of its `/home` first. Result: EFI + btrfs root, GRUB.
Boot via Framework boot menu (F12) → USB.

**Iteration:**
- *Fast loop (no laptop reboot):* `make vm` — `bootc install to-disk` into a raw file, boot with
  qemu + virtio-gpu. Catches service/config/missing-binary errors in ~2 min.
- *Real loop:* push to `ghcr.io/bakedbean/fedora-hypr:44` (CI, or manual `podman push` before
  CI exists). On the USB system: `bootc switch ghcr.io/bakedbean/fedora-hypr:44` once, then
  `bootc upgrade && reboot` thereafter. The drive is never re-flashed after the first install.

## Risks / open items

- Fedora package-name drift and COPR availability for the next Fedora release — a failed CI
  build leaves the machine on the last good image, so this is a delay, not a breakage.
- `/etc` 3-way merge conflicts if local `/etc` edits accumulate — mitigated by keeping config
  in `/usr` (image) or `~` (user).
- Walker/Elephant version pinning — Omarchy tracks its own fork; we build upstream tags.
- Framework 12 fingerprint reader under `fprintd` on Fedora — expected to work (same kernel),
  to be verified in the done-criteria pass.
