# fedora-hypr Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Fedora bootc image (`ghcr.io/bakedbean/fedora-hypr:44`) that boots the Framework 12 into an Omarchy-flavored Hyprland desktop, installed to the external drive `/dev/sda`.

**Architecture:** One repo builds one OCI image from `ghcr.io/ublue-os/base-main:44`. `build/` scripts install packages (Fedora repos + five pinned COPRs); `system/` is copied verbatim onto `/` and holds the image-owned config under `/usr/share/fedora-hypr`, helper scripts `/usr/bin/fh-*`, systemd units, and `/etc/skel`. A first-boot oneshot creates the user and installs Flatpaks. Theme switching is Omarchy's engine (a `colors.toml` per theme rendered through `*.tpl` templates into `~/.config/fedora-hypr/current/theme/`), renamed and re-pathed.

**Tech Stack:** bootc 1.16, podman 6, Fedora 44, Hyprland 0.56, greetd + tuigreet, uwsm, Walker/Elephant, Waybar, mako, swaybg, SwayOSD, Alacritty, bash. CI: GitHub Actions → ghcr.io.

**Spec:** `docs/superpowers/specs/2026-09-20-fedora-hypr-design.md`

## Global Constraints

- Base image: `ghcr.io/ublue-os/base-main:44` (Fedora 44). The `FROM` tag is the only place the release number appears.
- Every helper script is named `fh-*` and lives in `system/usr/bin/`. No `omarchy-*` names anywhere in `system/` except in attribution comments.
- Image-owned config root: `/usr/share/fedora-hypr` (exported as `$FH_PATH`). User state root: `~/.config/fedora-hypr`. Toggle state: `~/.local/state/fedora-hypr/toggles`.
- Login: greetd + tuigreet → `uwsm start -- hyprland-uwsm.desktop`. No SDDM.
- No LUKS. Filesystem: btrfs. Bootloader: whatever `bootc install` picks (GRUB).
- User: `eben`, in `wheel`, created at first boot, not at build time.
- COPR repos are added during the build and **removed at the end of the build** so the runtime image carries no third-party repo definitions.
- Ported Omarchy files keep the MIT notice: add `# Adapted from Omarchy (MIT) — https://github.com/basecamp/omarchy` as the second line of every ported script and a `LICENSE.omarchy` at the repo root.
- Commit after every task. Conventional-commit messages.
- Each build is verified with `bootc container lint` (last `RUN` in the Containerfile) and the checks listed in the task.

Source of ported material on this machine: `~/.local/share/omarchy` (Omarchy 3.8.5) and `~/.config/{hypr,waybar,walker,alacritty}`.

---

## File map

| Path | Responsibility |
|---|---|
| `Containerfile` | FROM base-main, COPY system/, RUN build scripts, lint |
| `Makefile` | `build`, `shell`, `check`, `vm`, `push`, `install-sda` |
| `build/repos/*.repo` | COPR definitions (copied in, removed after install) |
| `build/10-packages.sh` | `dnf install` lists |
| `build/20-services.sh` | `systemctl enable`, greetd default target, cleanup |
| `build/packages/{fedora,copr-*}.txt` | one package per line, `#` comments |
| `system/usr/share/fedora-hypr/default/hypr/*.conf` | canonical Hyprland config, sourced by the user's `hyprland.conf` |
| `system/usr/share/fedora-hypr/default/{waybar,mako,walker,swayosd}/` | canonical app configs |
| `system/usr/share/fedora-hypr/themed/*.tpl` | theme templates |
| `system/usr/share/fedora-hypr/themes/<name>/` | ported themes (colors.toml, backgrounds/) |
| `system/usr/share/fedora-hypr/flatpaks.txt` | Flatpak app IDs for first boot |
| `system/usr/bin/fh-*` | helper scripts |
| `system/usr/lib/systemd/system/fh-first-boot.service` | user + flatpak oneshot |
| `system/usr/share/wayland-sessions/hyprland-uwsm.desktop` | session file for uwsm |
| `system/etc/greetd/config.toml` | tuigreet config |
| `system/etc/profile.d/fedora-hypr.sh` | exports `FH_PATH` |
| `system/etc/skel/.config/**` | per-user seed config |
| `.github/workflows/build.yml` | build + push to ghcr on push/schedule |
| `README.md` | usage |

---

### Task 1: Repo scaffold and first successful build

**Files:**
- Create: `Containerfile`, `Makefile`, `.gitignore`, `build/10-packages.sh`, `build/20-services.sh`, `LICENSE`, `LICENSE.omarchy`

**Interfaces:**
- Produces: `make build` → image `localhost/fedora-hypr:44`; `make shell` → bash inside it; `make check` → runs `tests/check.sh` inside it (added in Task 2).
- Build scripts run as root in the build container with `set -euo pipefail`; they may assume `/ctx` is a bind mount of the repo's `build/` dir.

- [ ] **Step 1: Write the Containerfile**

```dockerfile
FROM ghcr.io/ublue-os/base-main:44

# Image-owned files: scripts, defaults, themes, units, skel
COPY system/ /

# Build scripts run with the repo's build/ dir mounted at /ctx
RUN --mount=type=bind,source=build,target=/ctx \
    --mount=type=cache,dst=/var/cache/dnf \
    /ctx/10-packages.sh && \
    /ctx/20-services.sh

RUN bootc container lint
```

- [ ] **Step 2: Write the build scripts as no-ops that prove the wiring**

`build/10-packages.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
echo "10-packages: nothing to install yet"
```

`build/20-services.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
echo "20-services: nothing to enable yet"
```

`chmod +x build/*.sh`

- [ ] **Step 3: Write the Makefile**

```makefile
IMAGE   ?= localhost/fedora-hypr
TAG     ?= 44
REMOTE  ?= ghcr.io/bakedbean/fedora-hypr
PODMAN  ?= podman

.PHONY: build shell check push

build:
	$(PODMAN) build -t $(IMAGE):$(TAG) .

shell: build
	$(PODMAN) run --rm -it $(IMAGE):$(TAG) bash

check: build
	$(PODMAN) run --rm -v ./tests:/tests:ro,z $(IMAGE):$(TAG) bash /tests/check.sh

push: build
	$(PODMAN) tag $(IMAGE):$(TAG) $(REMOTE):$(TAG)
	$(PODMAN) push $(REMOTE):$(TAG)
```

(Tabs, not spaces, for recipe lines.)

- [ ] **Step 4: Licenses and .gitignore**

`LICENSE`: MIT, copyright 2026 Eben Goodman.
`LICENSE.omarchy`: copy of `~/.local/share/omarchy/LICENSE`.
`.gitignore`:
```
vm/
*.raw
*.qcow2
```

- [ ] **Step 5: Build and verify**

Run: `make build`
Expected: ends with `bootc container lint` passing and `Successfully tagged localhost/fedora-hypr:44`.

Run: `podman run --rm localhost/fedora-hypr:44 cat /etc/os-release | grep VERSION_ID`
Expected: `VERSION_ID=44`

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "build: scaffold Containerfile, Makefile, licenses"
```

---

### Task 2: Package layer

**Files:**
- Create: `build/repos/dtutila-hyprland.repo`, `build/repos/washkinazy-wayland-wm-extras.repo`, `build/repos/mineiro-utility-belt.repo`, `build/repos/agaspar-omedora-4.repo`, `build/repos/whelanh-omarchy.repo`
- Create: `build/packages/fedora.txt`, `build/packages/copr.txt`
- Modify: `build/10-packages.sh`
- Create: `tests/check.sh`

**Interfaces:**
- Produces: binaries on `$PATH` in the image: `Hyprland hyprlock hypridle hyprpicker hyprsunset hyprpolkitagent uwsm walker elephant waybar mako swaybg swayosd grim slurp satty wl-copy alacritty starship lazygit mise impala bluetui wiremix gum greetd tuigreet gpu-screen-recorder hyprland-preview-share-picker`.
- Produces: `tests/check.sh` — the image self-check that later tasks append to.

- [ ] **Step 1: Write the failing check**

`tests/check.sh`:
```bash
#!/usr/bin/env bash
# Runs inside the built image. Every check prints PASS/FAIL; exits 1 on any FAIL.
set -uo pipefail
fail=0
check() { if "$@" >/dev/null 2>&1; then echo "PASS $*"; else echo "FAIL $*"; fail=1; fi; }

# --- Task 2: packages
for b in Hyprland hyprlock hypridle hyprpicker hyprsunset hyprpolkitagent uwsm \
         walker elephant waybar mako swaybg swayosd grim slurp satty wl-copy \
         alacritty starship lazygit mise impala bluetui wiremix gum greetd tuigreet \
         gpu-screen-recorder hyprland-preview-share-picker firefox chromium nautilus \
         fish nvim btop bat eza fd rg zoxide jq dust tldr fastfetch magick \
         fcitx5 fprintd flatpak; do
  check command -v "$b"
done
check rpm -q nerd-fonts-jetbrainsmono nerd-fonts-firacode jetbrains-mono-fonts \
      fontawesome-6-free-fonts google-noto-sans-fonts yaru-icon-theme kvantum \
      libva-intel-media-driver xdg-desktop-portal-hyprland xdg-desktop-portal-gtk \
      qt5-qtwayland qt6-qtwayland podman-docker gnome-keyring-pam fprintd-pam iwd
# No third-party repos left in the runtime image
check test -z "$(ls /etc/yum.repos.d/_copr_* 2>/dev/null | grep -v ublue-os)"

exit $fail
```

- [ ] **Step 2: Run it to see it fail**

Run: `make check`
Expected: many `FAIL command -v ...` lines, exit 1.

- [ ] **Step 3: Write the COPR repo files**

Every file uses this shape; only the `[id]`, `name`, owner/project in the URLs, and the optional `includepkgs` line differ.

`build/repos/dtutila-hyprland.repo`:
```ini
[copr:copr.fedorainfracloud.org:dtutila:hyprland]
name=Copr repo for hyprland owned by dtutila
baseurl=https://download.copr.fedorainfracloud.org/results/dtutila/hyprland/fedora-$releasever-$basearch/
type=rpm-md
skip_if_unavailable=False
gpgcheck=1
gpgkey=https://download.copr.fedorainfracloud.org/results/dtutila/hyprland/pubkey.gpg
repo_gpgcheck=0
enabled=1
enabled_metadata=1
```

`build/repos/washkinazy-wayland-wm-extras.repo`: same with `washkinazy/wayland-wm-extras`, plus:
```ini
includepkgs=walker,elephant,swayosd,nerd-fonts-jetbrainsmono,nerd-fonts-firacode
```

`build/repos/mineiro-utility-belt.repo`: `mineiro/utility-belt`, plus:
```ini
includepkgs=impala,bluetui
```

`build/repos/agaspar-omedora-4.repo`: `agaspar/omedora-4`, plus:
```ini
includepkgs=satty,starship,lazygit,lazydocker,mise,gpu-screen-recorder
```

`build/repos/whelanh-omarchy.repo`: `whelanh/omarchy`, plus:
```ini
includepkgs=hyprland-preview-share-picker
```

Why `includepkgs`: three of these COPRs also ship their own `hyprland`, `mpv`, `aquamarine`, etc. Restricting each repo to the packages we want from it means the Hyprland stack comes only from `dtutila` and nothing overrides Fedora's own packages.

- [ ] **Step 4: Write the package lists**

`build/packages/fedora.txt`:
```
# session / system
greetd
tuigreet
flatpak
iwd
power-profiles-daemon
fprintd
fprintd-pam
gnome-keyring
gnome-keyring-pam
libsecret
libva-intel-media-driver
xdg-desktop-portal-gtk
qt5-qtwayland
qt6-qtwayland
xdg-terminal-exec
# shell / wm helpers
waybar
mako
swaybg
grim
slurp
wl-clipboard
brightnessctl
playerctl
pamixer
wiremix
gum
# terminal + cli
alacritty
fish
tmux
neovim
btop
bat
eza
fd-find
ripgrep
zoxide
jq
du-dust
tldr
fastfetch
ImageMagick
podman-docker
# browsers + desktop apps
chromium
nautilus
nautilus-python
sushi
gvfs-mtp
gvfs-nfs
gvfs-smb
evince
imv
mpv
gnome-calculator
gnome-disk-utility
fcitx5
fcitx5-gtk
fcitx5-qt
# fonts / themes
jetbrains-mono-fonts
google-noto-sans-fonts
fontawesome-6-free-fonts
yaru-icon-theme
kvantum
```
(`firefox`, `bluez`, `avahi`, `nss-mdns`, `cups`, `fwupd`, `plymouth`, `podman`, `toolbox`, `wireplumber`, `fzf`, Noto CJK/emoji are already in base-main — verified with `rpm -q`.)

`build/packages/copr.txt`:
```
# dtutila/hyprland
hyprland
hyprlock
hypridle
hyprpicker
hyprsunset
hyprpolkitagent
hyprshot
hyprland-guiutils
xdg-desktop-portal-hyprland
uwsm
# washkinazy/wayland-wm-extras
walker
elephant
swayosd
nerd-fonts-jetbrainsmono
nerd-fonts-firacode
# mineiro/utility-belt
impala
bluetui
# agaspar/omedora-4
satty
starship
lazygit
lazydocker
mise
gpu-screen-recorder
# whelanh/omarchy
hyprland-preview-share-picker
```

- [ ] **Step 5: Write 10-packages.sh**

```bash
#!/usr/bin/env bash
# Install packages from Fedora repos and pinned COPRs. Runs inside the build container.
set -euo pipefail

pkgs() { grep -vE '^\s*(#|$)' "$1"; }

# COPRs are only present during the build; 20-services.sh removes them.
cp /ctx/repos/*.repo /etc/yum.repos.d/

# shellcheck disable=SC2046
dnf -y install --setopt=install_weak_deps=False \
  $(pkgs /ctx/packages/fedora.txt) \
  $(pkgs /ctx/packages/copr.txt)

dnf clean all
```

- [ ] **Step 6: Add repo cleanup to 20-services.sh**

Replace the body with:
```bash
#!/usr/bin/env bash
set -euo pipefail

# Drop build-time COPR definitions so the runtime image has no third-party repos.
rm -f /etc/yum.repos.d/copr:copr.fedorainfracloud.org:{dtutila,washkinazy,mineiro,agaspar,whelanh}:*.repo
```
Note: `cp` in step 5 copies files named like `dtutila-hyprland.repo`; dnf identifies repos by the `[section]` id, not the filename. Adjust the `rm` to the filenames actually copied: `rm -f /etc/yum.repos.d/{dtutila,washkinazy,mineiro,agaspar,whelanh}-*.repo`.

- [ ] **Step 7: Build and run the check**

Run: `make check`
Expected: every line `PASS`, exit 0. If a package name fails to resolve, `dnf` aborts the build and names it; fix the list, do not `--skip-unavailable`.

- [ ] **Step 8: Commit**

```bash
git add -A && git commit -m "build: install Hyprland desktop stack from Fedora + pinned COPRs"
```

---

### Task 3: Session plumbing — greetd, uwsm session, profile env, services

**Files:**
- Create: `system/etc/greetd/config.toml`, `system/usr/share/wayland-sessions/hyprland-uwsm.desktop`, `system/etc/profile.d/fedora-hypr.sh`, `system/etc/NetworkManager/conf.d/wifi-backend-iwd.conf`, `system/etc/environment.d/50-fedora-hypr.conf`
- Modify: `build/20-services.sh`, `tests/check.sh`

**Interfaces:**
- Produces: `$FH_PATH=/usr/share/fedora-hypr` in every login shell and in the uwsm session environment.
- Produces: greetd enabled as the display manager; getty on tty1 disabled.

- [ ] **Step 1: Append checks**

Append to `tests/check.sh` before `exit $fail`:
```bash
# --- Task 3: session plumbing
check test -f /etc/greetd/config.toml
check grep -q 'uwsm start' /etc/greetd/config.toml
check test -f /usr/share/wayland-sessions/hyprland-uwsm.desktop
check test "$(systemctl is-enabled greetd 2>/dev/null)" = enabled
check test "$(systemctl is-enabled getty@tty1 2>/dev/null)" = disabled
check bash -lc 'test "$FH_PATH" = /usr/share/fedora-hypr'
check grep -q 'wifi.backend=iwd' /etc/NetworkManager/conf.d/wifi-backend-iwd.conf
check test "$(systemctl is-enabled iwd 2>/dev/null)" = enabled
check test "$(systemctl is-enabled fh-first-boot 2>/dev/null)" = enabled || true  # enabled in Task 4
```
(Leave the last line commented out until Task 4 — `systemctl is-enabled` on a missing unit fails.)

- [ ] **Step 2: Run check, expect Task 3 FAILs**

Run: `make check` — expected: the new lines FAIL.

- [ ] **Step 3: greetd config**

`system/etc/greetd/config.toml`:
```toml
[terminal]
vt = 1

[default_session]
command = "tuigreet --time --remember --asterisks --cmd 'uwsm start -- hyprland-uwsm.desktop'"
user = "greeter"
```

- [ ] **Step 4: uwsm session file**

`system/usr/share/wayland-sessions/hyprland-uwsm.desktop`:
```ini
[Desktop Entry]
Name=Hyprland (uwsm)
Comment=Hyprland managed by uwsm
Exec=Hyprland
Type=Application
DesktopNames=Hyprland
```
uwsm reads `Exec=` and `DesktopNames=` from this file and wraps Hyprland in a systemd user scope.

- [ ] **Step 5: Environment**

`system/etc/profile.d/fedora-hypr.sh`:
```sh
export FH_PATH=/usr/share/fedora-hypr
```

`system/etc/environment.d/50-fedora-hypr.conf` (picked up by systemd user manager → uwsm session):
```
FH_PATH=/usr/share/fedora-hypr
```

- [ ] **Step 6: NetworkManager on iwd**

`system/etc/NetworkManager/conf.d/wifi-backend-iwd.conf`:
```ini
[device]
wifi.backend=iwd
```
Impala (the Wi-Fi TUI) speaks to iwd directly; NetworkManager keeps VPN/ethernet/DNS working.

- [ ] **Step 7: Enable services in 20-services.sh**

Append:
```bash
systemctl enable greetd.service
systemctl disable getty@tty1.service
systemctl enable iwd.service
systemctl enable power-profiles-daemon.service
systemctl enable bluetooth.service
systemctl enable fprintd.service 2>/dev/null || true   # socket/dbus activated on Fedora; harmless
```

- [ ] **Step 8: Build, check, commit**

Run: `make check` → all PASS.

```bash
git add -A && git commit -m "feat: greetd + uwsm session, FH_PATH env, iwd backend"
```

---

### Task 4: First boot — user creation and Flatpaks

**Files:**
- Create: `system/usr/bin/fh-first-boot`, `system/usr/lib/systemd/system/fh-first-boot.service`, `system/usr/share/fedora-hypr/flatpaks.txt`, `system/etc/sudoers.d/wheel`
- Modify: `build/20-services.sh`, `tests/check.sh`

**Interfaces:**
- Produces: on first boot, user `eben` (uid 1000, groups `wheel`, home `/var/home/eben` seeded from `/etc/skel`, password `changeme` expired). Env `FH_USER` overrides the name; `FH_SKIP_FLATPAK=1` skips Flatpak work (used in tests).
- Produces: Flathub remote + every app in `flatpaks.txt` installed system-wide.

- [ ] **Step 1: Append checks**

```bash
# --- Task 4: first boot
check test "$(systemctl is-enabled fh-first-boot 2>/dev/null)" = enabled
check systemd-analyze verify /usr/lib/systemd/system/fh-first-boot.service
check bash -c 'FH_SKIP_FLATPAK=1 FH_USER=testuser fh-first-boot && id -nG testuser | grep -qw wheel && test -d /var/home/testuser'
check bash -c 'FH_SKIP_FLATPAK=1 FH_USER=testuser fh-first-boot'   # idempotent: second run succeeds
check test -f /etc/sudoers.d/wheel
```

- [ ] **Step 2: Run check, expect FAIL**

- [ ] **Step 3: The script**

`system/usr/bin/fh-first-boot`:
```bash
#!/usr/bin/env bash
# First-boot setup: create the primary user and install Flatpak apps.
# bootc does not ship /var, so anything under /var/home must be created here, not at build time.
set -euo pipefail

user="${FH_USER:-eben}"
home="/var/home/$user"

if ! id "$user" &>/dev/null; then
  useradd --create-home --home-dir "$home" --uid 1000 --groups wheel --shell /usr/bin/fish "$user"
  echo "$user:changeme" | chpasswd
  chage --lastday 0 "$user"    # force password change at first login
  echo "fh-first-boot: created user $user"
fi

if [[ "${FH_SKIP_FLATPAK:-0}" != 1 ]]; then
  flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  mapfile -t apps < <(grep -vE '^\s*(#|$)' /usr/share/fedora-hypr/flatpaks.txt)
  if ((${#apps[@]})); then
    flatpak install -y --noninteractive flathub "${apps[@]}" || echo "fh-first-boot: some flatpaks failed; rerun fh-first-boot later" >&2
  fi
fi
```
`chmod +x`.

Note `useradd --uid 1000`: on the second run `id` short-circuits, so the test's "idempotent" check passes. `--shell /usr/bin/fish` requires `fish` (Task 2).

- [ ] **Step 4: The unit**

`system/usr/lib/systemd/system/fh-first-boot.service`:
```ini
[Unit]
Description=fedora-hypr first boot (user + flatpaks)
ConditionPathExists=!/var/lib/fedora-hypr/first-boot.done
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/fh-first-boot
ExecStartPost=/usr/bin/mkdir -p /var/lib/fedora-hypr
ExecStartPost=/usr/bin/touch /var/lib/fedora-hypr/first-boot.done

[Install]
WantedBy=multi-user.target
```
`Before=greetd.service` is deliberately **not** set: the greeter should not wait on Flatpak downloads. The user exists after the first `useradd` (seconds), so login works while Flatpaks install in the background.

- [ ] **Step 5: sudoers and flatpak list**

`system/etc/sudoers.d/wheel` (mode 0440):
```
%wheel ALL=(ALL) ALL
```
(Fedora's default sudoers already has this; the file makes it explicit and survives `/etc` merges.)

`system/usr/share/fedora-hypr/flatpaks.txt`:
```
org.signal.Signal
com.spotify.Client
md.obsidian.Obsidian
io.typora.Typora
org.libreoffice.LibreOffice
com.obsproject.Studio
org.kde.kdenlive
com.github.PintaProject.Pinta
com.github.xournalpp.xournalpp
org.localsend.localsend_app
com.onepassword.OnePassword
```
(IDs verified against Flathub during implementation with `flatpak search`; drop any that don't resolve rather than guessing.)

- [ ] **Step 6: Enable in 20-services.sh**

Append: `systemctl enable fh-first-boot.service` and `chmod 0440 /etc/sudoers.d/wheel`.

- [ ] **Step 7: Build, check, commit**

`make check` → all PASS.
```bash
git add -A && git commit -m "feat: first-boot user creation and flatpak install"
```

---

### Task 5: Theme engine

**Files:**
- Create: `system/usr/bin/fh-theme-set`, `fh-theme-set-templates`, `fh-theme-bg-next`, `fh-theme-list`, `fh-theme-current`, `fh-restart-waybar`, `fh-restart-swayosd`, `fh-restart-mako`, `fh-restart-hyprctl`
- Create: `system/usr/share/fedora-hypr/themed/{hyprland.conf,hyprlock.conf,waybar.css,walker.css,mako.ini,alacritty.toml,swayosd.css,btop.theme,gum.env.conf,hyprland-preview-share-picker.css,chromium.theme}.tpl`
- Create: `system/usr/share/fedora-hypr/themes/<name>/{colors.toml,backgrounds/,btop.theme,...}` for all 19 themes
- Create: `tests/theme_test.sh`; modify `tests/check.sh`

**Interfaces:**
- Consumes: `$FH_PATH` (Task 3).
- Produces: `fh-theme-set <name>` → populates `~/.config/fedora-hypr/current/theme/` with rendered files and `~/.config/fedora-hypr/current/theme.name`; `~/.config/fedora-hypr/current/background` symlink. `fh-theme-list` prints theme names one per line. `fh-theme-current` prints the current name. Hook: if `~/.config/fedora-hypr/hooks/theme-set` is executable it is called with the theme name.
- Theme lookup order: `~/.config/fedora-hypr/themes/<name>` overlays `$FH_PATH/themes/<name>`. User templates in `~/.config/fedora-hypr/themed/*.tpl` override built-ins.

- [ ] **Step 1: Write the failing test**

`tests/theme_test.sh`:
```bash
#!/usr/bin/env bash
# Exercises the theme engine in a throwaway HOME inside the image. No compositor needed:
# every fh-restart-* is guarded by pgrep and becomes a no-op.
set -euo pipefail
export HOME; HOME=$(mktemp -d)
export FH_PATH=/usr/share/fedora-hypr

fh-theme-set tokyo-night
cur="$HOME/.config/fedora-hypr/current"
test "$(cat "$cur/theme.name")" = tokyo-night
grep -q 'rgb(7aa2f7)' "$cur/theme/hyprland.conf"          # {{ accent_strip }}
grep -q 'background-color=#1a1b26' "$cur/theme/mako.ini"    # {{ background }}
grep -q '@define-color foreground #a9b1d6' "$cur/theme/waybar.css"
grep -q 'background = "#1a1b26"' "$cur/theme/alacritty.toml"
test -L "$cur/background" && test -f "$(readlink "$cur/background")"
test "$(fh-theme-current)" = tokyo-night
fh-theme-list | grep -qx tokyo-night
fh-theme-list | grep -qx rose-pine

# switching themes swaps atomically and cycles backgrounds within a theme
fh-theme-set gruvbox
test "$(fh-theme-current)" = gruvbox
first=$(readlink "$cur/background"); fh-theme-bg-next; second=$(readlink "$cur/background")
test "$first" != "$second" || test "$(ls "$cur/theme/backgrounds" | wc -l)" -le 1

# user overlay wins over built-in
mkdir -p "$HOME/.config/fedora-hypr/themes/tokyo-night"
echo 'accent = "#ff0000"' > "$HOME/.config/fedora-hypr/themes/tokyo-night/colors.toml"
fh-theme-set tokyo-night
grep -q 'rgb(ff0000)' "$cur/theme/hyprland.conf"

# unknown theme is an error
! fh-theme-set does-not-exist 2>/dev/null

echo "theme_test: OK"
```

Append to `tests/check.sh`:
```bash
# --- Task 5: theme engine
check bash /tests/theme_test.sh
```

- [ ] **Step 2: Run, expect FAIL** (`fh-theme-set: command not found`).

- [ ] **Step 3: Port the themes**

```bash
src=~/.local/share/omarchy/themes
dst=system/usr/share/fedora-hypr/themes
mkdir -p "$dst"
for t in "$src"/*/; do
  n=$(basename "$t")
  mkdir -p "$dst/$n"
  cp "$t"/colors.toml "$dst/$n/" 2>/dev/null || true
  cp -r "$t"/backgrounds "$dst/$n/" 2>/dev/null || true
  for f in btop.theme icons.theme preview.png; do [ -f "$t/$f" ] && cp "$t/$f" "$dst/$n/"; done
done
ls "$dst" | wc -l    # expect 19
find "$dst" -name colors.toml | wc -l   # expect 19; any theme without one: run
#   ~/.local/share/omarchy/bin/omarchy-theme-colors-from-alacritty "$dst/<name>" if it has alacritty.toml, else drop the theme
```
Skip `neovim.lua`, `vscode.json`, `keyboard.rgb`, `unlock.png`, `preview-unlock.png` — out of scope (AstroNvim, no VS Code, no RGB keyboard, hyprlock uses the template).

- [ ] **Step 4: Port the templates**

```bash
src=~/.local/share/omarchy/default/themed
dst=system/usr/share/fedora-hypr/themed
mkdir -p "$dst"
for f in hyprland.conf hyprlock.conf waybar.css walker.css mako.ini alacritty.toml swayosd.css btop.theme gum.env.conf hyprland-preview-share-picker.css chromium.theme; do
  sed -e 's|~/.local/share/omarchy/default|/usr/share/fedora-hypr/default|g' \
      -e 's|~/.config/omarchy|~/.config/fedora-hypr|g' \
      "$src/$f.tpl" > "$dst/$f.tpl"
done
grep -rn omarchy "$dst" && echo "LEFTOVER REFERENCES — fix by hand" || echo clean
```
`mako.ini.tpl` starts with `include=~/.local/share/omarchy/default/mako/core.ini` → becomes `/usr/share/fedora-hypr/default/mako/core.ini`; that file is created in Task 6. `hyprlock.conf.tpl` references `$FH_PATH`-free paths only after the sed; read it and confirm.

- [ ] **Step 5: Write fh-theme-set-templates**

`system/usr/bin/fh-theme-set-templates` — port of `omarchy-theme-set-templates` with these substitutions and nothing else changed:
- `TEMPLATES_DIR="$FH_PATH/themed"`
- `USER_TEMPLATES_DIR="$HOME/.config/fedora-hypr/themed"`
- `NEXT_THEME_DIR="$HOME/.config/fedora-hypr/current/next-theme"`
- Add `: "${FH_PATH:=/usr/share/fedora-hypr}"` at the top so it works from a bare shell.
- Second line: `# Adapted from Omarchy (MIT) — https://github.com/basecamp/omarchy`

The renderer (unchanged logic): read `colors.toml` key/values, emit a sed script mapping `{{ key }}`→value, `{{ key_strip }}`→value without `#`, `{{ key_rgb }}`→`r,g,b`; render every `*.tpl` (user first, then built-in) into `NEXT_THEME_DIR` unless a file of that name already exists there (theme-specific overrides win).

- [ ] **Step 6: Write fh-theme-set**

```bash
#!/usr/bin/env bash
# Adapted from Omarchy (MIT) — https://github.com/basecamp/omarchy
# Apply a theme: render templates into ~/.config/fedora-hypr/current/theme and reload apps.
set -uo pipefail
: "${FH_PATH:=/usr/share/fedora-hypr}"

if [[ -z ${1:-} ]]; then echo "Usage: fh-theme-set <theme-name>" >&2; exit 1; fi

state="$HOME/.config/fedora-hypr"
current="$state/current/theme"
next="$state/current/next-theme"
user_themes="$state/themes"
themes="$FH_PATH/themes"

name=$(echo "$1" | sed -E 's/<[^>]+>//g' | tr '[:upper:]' '[:lower:]' | tr ' ' '-')

if [[ ! -d $themes/$name && ! -d $user_themes/$name ]]; then
  echo "Theme '$name' does not exist" >&2; exit 1
fi

rm -rf "$next"; mkdir -p "$next"
cp -r "$themes/$name/." "$next/" 2>/dev/null
cp -r "$user_themes/$name/." "$next/" 2>/dev/null   # user overlay wins

fh-theme-set-templates

rm -rf "$current"; mv "$next" "$current"
echo "$name" > "$state/current/theme.name"

[[ ${FH_THEME_SKIP_BACKGROUND:-0} == 1 ]] || fh-theme-bg-next

fh-restart-waybar
fh-restart-swayosd
fh-restart-mako
fh-restart-hyprctl

hook="$state/hooks/theme-set"
[[ -x $hook ]] && "$hook" "$name" >/dev/null
exit 0
```

- [ ] **Step 7: fh-theme-bg-next, fh-theme-list, fh-theme-current, fh-restart-\***

`fh-theme-bg-next`: port of `omarchy-theme-bg-next` with paths `~/.config/omarchy` → `~/.config/fedora-hypr`. Its swaybg relaunch must tolerate no compositor: wrap the two `setsid uwsm-app -- swaybg ...` lines as `if [[ -n ${WAYLAND_DISPLAY:-} ]]; then ...; fi`. The symlink update happens regardless (that is what the test checks).

`fh-theme-list`:
```bash
#!/usr/bin/env bash
: "${FH_PATH:=/usr/share/fedora-hypr}"
{ ls "$FH_PATH/themes"; ls "$HOME/.config/fedora-hypr/themes" 2>/dev/null; } | sort -u
```

`fh-theme-current`:
```bash
#!/usr/bin/env bash
cat "$HOME/.config/fedora-hypr/current/theme.name" 2>/dev/null
```

`fh-restart-waybar`:
```bash
#!/usr/bin/env bash
pgrep -x waybar >/dev/null || exit 0
pkill -x waybar; sleep 0.2
setsid uwsm-app -- waybar >/dev/null 2>&1 &
```
`fh-restart-swayosd`: same pattern with `swayosd-server`.
`fh-restart-mako`: `pgrep -x mako >/dev/null && makoctl reload; exit 0`.
`fh-restart-hyprctl`: `pgrep -x Hyprland >/dev/null && hyprctl reload >/dev/null; exit 0`.

`chmod +x system/usr/bin/fh-*`.

- [ ] **Step 8: Build, test, commit**

`make check` → `PASS bash /tests/theme_test.sh`.
```bash
git add -A && git commit -m "feat: theme engine with 19 ported themes"
```

---

### Task 6: Default desktop config + /etc/skel

**Files:**
- Create: `system/usr/share/fedora-hypr/default/hypr/{autostart,envs,looknfeel,input,windows,apps}.conf`, `default/hypr/bindings/{media,clipboard,tiling-v2,utilities}.conf`, `default/hypr/apps/*.conf`
- Create: `system/usr/share/fedora-hypr/default/mako/core.ini`, `default/walker/themes/fh-default/{layout.xml,style.css}`, `default/waybar/{config.jsonc,style.css}`, `default/swayosd/{config.toml,style.css}`, `default/hypridle.conf`, `default/hyprlock.conf`
- Create: `system/etc/skel/.config/hypr/{hyprland,monitors,input,bindings,envs,looknfeel,autostart}.conf`, `skel/.config/{alacritty/alacritty.toml,waybar/config.jsonc,waybar/style.css,walker/config.toml,mako/config,btop/btop.conf,swayosd/config.toml,fastfetch/config.jsonc,uwsm/env}`
- Modify: `tests/check.sh`

**Interfaces:**
- Consumes: `~/.config/fedora-hypr/current/theme/*` (Task 5), `fh-*` scripts (Tasks 5, 7).
- Produces: a Hyprland config that passes `Hyprland --verify-config` for a fresh skel user, and app configs that `include`/`import` the current theme files.

- [ ] **Step 1: Append checks**

```bash
# --- Task 6: default config + skel
check bash -c '
  export HOME=$(mktemp -d); cp -r /etc/skel/. "$HOME"; export FH_PATH=/usr/share/fedora-hypr
  FH_THEME_SKIP_BACKGROUND=1 fh-theme-set tokyo-night
  Hyprland --verify-config'
check bash -c '! grep -rl omarchy /usr/share/fedora-hypr/default /etc/skel | grep -v LICENSE'
check test -f /usr/share/fedora-hypr/default/mako/core.ini
check grep -q "fedora-hypr/current/theme/alacritty.toml" /etc/skel/.config/alacritty/alacritty.toml
```
If `Hyprland --verify-config` needs a display in this Hyprland version (it should not), replace that check with `hyprctl` being absent is fine; fall back to `bash -c 'grep -q "^source = /usr/share/fedora-hypr/default/hypr/autostart.conf" $HOME/.config/hypr/hyprland.conf'`.

- [ ] **Step 2: Run, expect FAIL**

- [ ] **Step 3: Port default Hyprland config**

```bash
src=~/.local/share/omarchy/default/hypr
dst=system/usr/share/fedora-hypr/default/hypr
mkdir -p "$dst/bindings" "$dst/apps"
port() { sed -e 's|~/.local/share/omarchy/default|/usr/share/fedora-hypr/default|g' \
             -e 's|\$OMARCHY_PATH/default|/usr/share/fedora-hypr/default|g' \
             -e 's|~/.config/omarchy|~/.config/fedora-hypr|g' \
             -e 's|~/.local/state/omarchy|~/.local/state/fedora-hypr|g' \
             -e 's|omarchy-|fh-|g' "$1" > "$2"; }
for f in autostart envs looknfeel input windows apps; do port "$src/$f.conf" "$dst/$f.conf"; done
for f in media clipboard tiling-v2 utilities; do port "$src/bindings/$f.conf" "$dst/bindings/$f.conf"; done
for f in "$src"/apps/*.conf; do port "$f" "$dst/apps/$(basename "$f")"; done
```

Then edit by hand:

`default/hypr/autostart.conf` — replace the whole file with:
```
exec-once = uwsm-app -- hypridle
exec-once = uwsm-app -- mako
exec-once = ! fh-toggle-enabled waybar-off && uwsm-app -- waybar
exec-once = uwsm-app -- fcitx5 --disable notificationitem
exec-once = uwsm-app -- swaybg -i ~/.config/fedora-hypr/current/background -m fill
exec-once = systemctl --user start hyprpolkitagent.service
exec-once = uwsm-app -- swayosd-server
exec-once = fh-first-run
exec-once = fh-powerprofiles-init
exec-once = uwsm-app -- fh-hyprland-monitor-watch

# Slow app launch fix -- set systemd vars
exec-once = systemctl --user import-environment $(env | cut -d'=' -f 1)
exec-once = dbus-update-activation-environment --systemd --all
```
(polkit-gnome → hyprpolkitagent; `omarchy-hook post-boot` dropped.)

`default/hypr/envs.conf`: keep everything; the `source = ~/.config/fedora-hypr/current/theme/gum.env.conf` line stays (rendered by Task 5).

`default/hypr/apps.conf` and `apps/*.conf`: delete entries for apps we don't ship (`steam`, `retroarch`, `moonlight`, `geforce`, `davinci-resolve`, `jetbrains`, `qemu`, `telegram`, `bitwarden`) — remove both the file and its `source =` line in `apps.conf`. Keep `1password browser hyprshot localsend pip system terminals typora walker webcam-overlay`.

`default/hypr/bindings/utilities.conf` and others: every `bindd = ... exec, fh-xxx` that appears must exist by the end of Task 7. Run `grep -ho 'fh-[a-z0-9-]*' "$dst"/**/*.conf | sort -u` and save the list — that is Task 7's required set. Remove bindings for features out of scope: anything referencing `fh-menu-keybindings`? **keep**; `fh-launch-screensaver`, `fh-toggle-screensaver`, `fh-cmd-apple-display-*`, `fh-toggle-hybrid-gpu`, `fh-launch-editor` (keep — maps to `$terminal -e nvim`), `fh-voxtype`/dictation → **remove**.

- [ ] **Step 4: Port app defaults**

- `default/mako/core.ini` ← `~/.local/share/omarchy/default/mako/core.ini` (verbatim).
- `default/walker/themes/fh-default/{layout.xml,style.css}` ← `default/walker/themes/omarchy-default/`, with `@import` paths rewritten to `~/.config/fedora-hypr/current/theme/walker.css`.
- `default/waybar/config.jsonc` and `style.css` ← from `~/.local/share/omarchy/config/waybar/` (Omarchy's stock, **not** the user's customised one — that has RadioBar/wsx modules that aren't in this image). Apply the `port` sed. Replace the `custom/omarchy` module: `"format": "<span font='omarchy'></span>"` → `"format": ""` (a plain Font Awesome icon; the omarchy.ttf glyph font isn't shipped), `on-click: fh-menu`. Remove the `custom/update` module (its `exec` was `omarchy-update-available`; bootc has no cheap equivalent — YAGNI).
- `default/swayosd/{config.toml,style.css}` ← `~/.local/share/omarchy/config/swayosd/`, `@import` → current theme `swayosd.css`.
- `default/hypridle.conf`, `default/hyprlock.conf` ← `~/.local/share/omarchy/config/hypr/{hypridle,hyprlock}.conf` with `port` sed; any `omarchy-lock-screen` → `hyprlock`.

- [ ] **Step 5: Write skel**

`system/etc/skel/.config/hypr/hyprland.conf`:
```
# fedora-hypr defaults (image-owned — don't edit; override below)
source = /usr/share/fedora-hypr/default/hypr/autostart.conf
source = /usr/share/fedora-hypr/default/hypr/bindings/media.conf
source = /usr/share/fedora-hypr/default/hypr/bindings/clipboard.conf
source = /usr/share/fedora-hypr/default/hypr/bindings/tiling-v2.conf
source = /usr/share/fedora-hypr/default/hypr/bindings/utilities.conf
source = /usr/share/fedora-hypr/default/hypr/envs.conf
source = /usr/share/fedora-hypr/default/hypr/looknfeel.conf
source = /usr/share/fedora-hypr/default/hypr/input.conf
source = /usr/share/fedora-hypr/default/hypr/windows.conf
source = ~/.config/fedora-hypr/current/theme/hyprland.conf

# Your overrides (these files are yours)
source = ~/.config/hypr/monitors.conf
source = ~/.config/hypr/input.conf
source = ~/.config/hypr/bindings.conf
source = ~/.config/hypr/envs.conf
source = ~/.config/hypr/looknfeel.conf
source = ~/.config/hypr/autostart.conf

# Runtime toggles
source = ~/.local/state/fedora-hypr/toggles/hypr/*.conf
```

`skel/.config/hypr/bindings.conf`:
```
# App launchers — edit freely
$terminal = uwsm-app -- alacritty
$browser = uwsm-app -- firefox
$webapp = $browser --new-window
$fileManager = uwsm-app -- nautilus --new-window
$music = uwsm-app -- flatpak run com.spotify.Client
$messenger = uwsm-app -- flatpak run org.signal.Signal
$passwordManager = uwsm-app -- flatpak run com.onepassword.OnePassword

bindd = SUPER, RETURN, Terminal, exec, $terminal
bindd = SUPER, F, File manager, exec, $fileManager
bindd = SUPER, B, Web browser, exec, $browser
bindd = SUPER, M, Music, exec, $music
bindd = SUPER, N, Neovim, exec, $terminal -e nvim
bindd = SUPER, T, Top, exec, $terminal -e btop
bindd = SUPER, D, Lazy Docker, exec, $terminal -e lazydocker
bindd = SUPER, G, Messenger, exec, $messenger
bindd = SUPER, O, Obsidian, exec, uwsm-app -- flatpak run md.obsidian.Obsidian
bindd = SUPER, SLASH, Password manager, exec, $passwordManager
```

`skel/.config/hypr/monitors.conf`: port of `~/.config/hypr/monitors.conf` (Framework 12 internal panel scale); `input.conf`, `looknfeel.conf`, `envs.conf`, `autostart.conf`: copy the user's current versions through the `port` sed. Anything referencing packages not in this image (check with `grep -o 'exec[^,]*, [a-z-]*' | sort -u`) is removed.

`skel/.config/alacritty/alacritty.toml`: the user's current file with `general.import = [ "~/.config/fedora-hypr/current/theme/alacritty.toml" ]`; keep the FiraCode Nerd Font (shipped via `nerd-fonts-firacode`).

`skel/.config/waybar/config.jsonc`:
```jsonc
// Your Waybar config. Defaults live in /usr/share/fedora-hypr/default/waybar/.
// To customise, copy that file here and edit — this include is replaced entirely.
{ "include": "/usr/share/fedora-hypr/default/waybar/config.jsonc" }
```
`skel/.config/waybar/style.css`: `@import "/usr/share/fedora-hypr/default/waybar/style.css";`

`skel/.config/walker/config.toml`: the user's current file with `theme = "fh-default"`, `additional_theme_location = "/usr/share/fedora-hypr/default/walker/themes/"`, and `command = "fh-restart-walker"`.

`skel/.config/mako/config`:
```
include=~/.config/fedora-hypr/current/theme/mako.ini
```

`skel/.config/swayosd/config.toml`: `include` of the default (swayosd supports a single config path; if it has no include, copy the default file into skel instead and note it).

`skel/.config/btop/btop.conf`: `color_theme = "~/.config/fedora-hypr/current/theme/btop.theme"` plus `theme_background = False`.

`skel/.config/uwsm/env`:
```
export FH_PATH=/usr/share/fedora-hypr
```

`skel/.config/fastfetch/config.jsonc`: Omarchy's `config/fastfetch/config.jsonc` with the logo line pointing at nothing (`"logo": { "type": "none" }`).

- [ ] **Step 6: Build, check, commit**

`make check` → all PASS, including `Hyprland --verify-config`.
```bash
git add -A && git commit -m "feat: default Hyprland/Waybar/mako/Walker config and skel"
```

---

### Task 7: Helper scripts

**Files:**
- Create in `system/usr/bin/`: every name in the required set from Task 6 step 3, which will be approximately:
  `fh-menu fh-menu-keybindings fh-launch-walker fh-launch-browser fh-launch-webapp fh-launch-or-focus fh-launch-or-focus-webapp fh-launch-or-focus-tui fh-launch-tui fh-launch-floating-terminal-with-presentation fh-launch-wifi fh-launch-bluetooth fh-launch-audio fh-launch-editor fh-webapp-install fh-webapp-remove fh-cmd-screenshot fh-cmd-screenrecord fh-cmd-terminal-cwd fh-toggle-enabled fh-toggle-nightlight fh-toggle-idle fh-toggle-waybar fh-toggle-notification-silencing fh-toggle-suspend fh-toggle-touchpad fh-restart-walker fh-restart-hypridle fh-restart-hyprsunset fh-restart-terminal fh-restart-btop fh-hyprland-monitor-watch fh-powerprofiles-init fh-first-run fh-update fh-cmd-present fh-cmd-missing fh-lock-screen fh-theme-menu fh-theme-bg-menu`
- Create: `tests/scripts_test.sh`; modify `tests/check.sh`; modify `build/10-packages.sh` (add `ShellCheck` to a build-only install, removed after)

**Interfaces:**
- Consumes: Task 5 theme scripts; Task 6 bindings (the required set is *derived from* the bindings — every `fh-*` referenced in `default/hypr/**` and `default/waybar/config.jsonc` must exist).
- Produces: `fh-update` = `sudo bootc upgrade && flatpak update -y` + reboot prompt via gum. `fh-menu` = Walker-dmenu menu tree.

- [ ] **Step 1: Write the failing test**

`tests/scripts_test.sh`:
```bash
#!/usr/bin/env bash
set -uo pipefail
fail=0
# 1. every fh-* referenced by config exists and is executable
for s in $(grep -rho 'fh-[a-z0-9-]*' /usr/share/fedora-hypr/default /etc/skel | sort -u); do
  if [[ -x /usr/bin/$s ]]; then echo "PASS exists $s"; else echo "FAIL missing $s"; fail=1; fi
done
# 2. every script parses and passes shellcheck (warnings allowed, errors not)
for s in /usr/bin/fh-*; do
  bash -n "$s" && shellcheck -S error "$s" && echo "PASS lint $(basename "$s")" || { echo "FAIL lint $s"; fail=1; }
done
# 3. no omarchy leftovers outside attribution comments
if grep -l 'omarchy' /usr/bin/fh-* | xargs -r grep -L 'Adapted from Omarchy' | grep -q .; then
  echo "FAIL omarchy references remain"; fail=1
elif grep -h 'omarchy' /usr/bin/fh-* | grep -v 'Adapted from Omarchy' | grep -q .; then
  echo "FAIL omarchy references remain (non-attribution lines)"; fail=1
else echo "PASS no omarchy leftovers"; fi
# 4. behaviour that runs headless
export HOME; HOME=$(mktemp -d)
fh-toggle-enabled waybar-off && { echo "FAIL toggle default should be off"; fail=1; } || echo "PASS toggle default off"
fh-toggle-waybar >/dev/null 2>&1; fh-toggle-enabled waybar-off && echo "PASS toggle on" || { echo "FAIL toggle on"; fail=1; }
fh-cmd-present bash && echo "PASS cmd-present" || { echo "FAIL cmd-present"; fail=1; }
fh-cmd-missing definitely-not-a-cmd && echo "PASS cmd-missing" || { echo "FAIL cmd-missing"; fail=1; }
exit $fail
```
Append `check bash /tests/scripts_test.sh` to `tests/check.sh`. Add `ShellCheck` to `build/packages/fedora.txt` under a `# build-only` comment and add `dnf -y remove ShellCheck` to the **end** of `20-services.sh`… no: the test runs *inside* the image, so ShellCheck must be present. Keep it in the image (5 MB). Simpler.

- [ ] **Step 2: Run, expect FAIL** (missing scripts).

- [ ] **Step 3: Port scripts mechanically, then fix by hand**

```bash
src=~/.local/share/omarchy/bin
dst=system/usr/bin
port() {
  { head -1 "$src/$1"; echo "# Adapted from Omarchy (MIT) — https://github.com/basecamp/omarchy"; tail -n +2 "$src/$1"; } |
  sed -e 's|~/.local/share/omarchy/default|/usr/share/fedora-hypr/default|g' \
      -e 's|\$OMARCHY_PATH|$FH_PATH|g' \
      -e 's|~/.config/omarchy|~/.config/fedora-hypr|g' \
      -e 's|\$HOME/.config/omarchy|$HOME/.config/fedora-hypr|g' \
      -e 's|~/.local/state/omarchy|~/.local/state/fedora-hypr|g' \
      -e 's|\$HOME/.local/state/omarchy|$HOME/.local/state/fedora-hypr|g' \
      -e 's|omarchy-|fh-|g' -e 's|OMARCHY_|FH_|g' \
      -e '/^# omarchy:/d' > "$dst/${1/omarchy-/fh-}"
  chmod +x "$dst/${1/omarchy-/fh-}"
}
for s in launch-walker launch-browser launch-webapp launch-or-focus launch-or-focus-webapp launch-or-focus-tui launch-tui \
         launch-floating-terminal-with-presentation launch-wifi launch-bluetooth launch-audio launch-editor \
         webapp-install webapp-remove cmd-terminal-cwd toggle-enabled toggle-nightlight toggle-idle toggle-waybar \
         toggle-notification-silencing toggle-suspend toggle-touchpad restart-walker restart-hypridle restart-hyprsunset \
         restart-terminal restart-btop hyprland-monitor-watch powerprofiles-init cmd-present cmd-missing menu-keybindings; do
  port "omarchy-$s"
done
```

Hand fixes after porting (read each script; these are the known Arch-isms):
- `fh-launch-browser`: uses `xdg-settings get default-web-browser`; keep. Ensure fallback is `firefox`.
- `fh-webapp-install`: writes `~/.local/share/applications/*.desktop` with `Exec=fh-launch-webapp <url>`; `fh-launch-webapp` runs `chromium --app=...`. Keep; chromium is native.
- `fh-toggle-nightlight`: uses `hyprsunset` via `hyprctl hyprsunset` — keep.
- `fh-powerprofiles-init`: `powerprofilesctl` — present via power-profiles-daemon. Keep.
- `fh-launch-wifi` → `impala`, `fh-launch-bluetooth` → `bluetui`, `fh-launch-audio` → `wiremix`: keep.
- `fh-cmd-screenshot` and `fh-cmd-screenrecord`: **write new** (Omarchy 3.8 moved these into `omarchy-menu`/`hyprshot`):

`fh-cmd-screenshot`:
```bash
#!/usr/bin/env bash
# Screenshot a region (default), window, or output; annotate in satty; copy to clipboard and save.
set -euo pipefail
mode="${1:-region}"   # region | window | output
dir="${XDG_PICTURES_DIR:-$HOME/Pictures}/Screenshots"; mkdir -p "$dir"
out="$dir/$(date +%Y-%m-%d_%H-%M-%S).png"
case "$mode" in
  region) hyprshot -m region --raw ;;
  window) hyprshot -m window --raw ;;
  output) hyprshot -m output --raw ;;
  *) echo "usage: fh-cmd-screenshot [region|window|output]" >&2; exit 1 ;;
esac | satty --filename - --output-filename "$out" --early-exit --copy-command wl-copy
```

`fh-cmd-screenrecord`:
```bash
#!/usr/bin/env bash
# Toggle a screen recording of the focused output with gpu-screen-recorder (audio: default sink).
set -euo pipefail
dir="${XDG_VIDEOS_DIR:-$HOME/Videos}"; mkdir -p "$dir"
if pgrep -x gpu-screen-recorder >/dev/null; then
  pkill -SIGINT -x gpu-screen-recorder
  notify-send "Screen recording saved" -t 2000
else
  out="$dir/$(date +%Y-%m-%d_%H-%M-%S).mp4"
  mon=$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .name')
  setsid gpu-screen-recorder -w "$mon" -f 60 -a default_output -o "$out" >/dev/null 2>&1 &
  notify-send "Screen recording started" -t 2000
fi
```

`fh-first-run`:
```bash
#!/usr/bin/env bash
# Runs once per user from Hyprland exec-once: pick the default theme and seed state dirs.
set -euo pipefail
marker="$HOME/.local/state/fedora-hypr/first-run.done"
[[ -f $marker ]] && exit 0
mkdir -p "$HOME/.local/state/fedora-hypr/toggles/hypr" "$HOME/.config/fedora-hypr/current"
[[ -f $HOME/.config/fedora-hypr/current/theme.name ]] || fh-theme-set tokyo-night
touch "$marker"
```

`fh-update`:
```bash
#!/usr/bin/env bash
# Stage the next OS image and update Flatpaks. Reboot to activate the image.
set -euo pipefail
sudo bootc upgrade
flatpak update -y --noninteractive
sudo bootc status
if gum confirm "Reboot now to activate the new image?"; then systemctl reboot; fi
```

`fh-lock-screen`: `exec hyprlock`.

`fh-theme-menu`: `fh-theme-list | fh-launch-walker --dmenu -p "Theme…" | xargs -r fh-theme-set`.
`fh-theme-bg-menu`: `fh-theme-bg-next` (a single-entry "next background" action is enough — YAGNI).

- [ ] **Step 4: Write fh-menu**

Port `omarchy-menu` keeping only these branches: **Apps, Learn, Trigger→(Capture, Toggle), Style→(Theme, Background), Setup→(Wifi, Bluetooth, Audio, Power profile), Update, Power(Lock, Suspend, Reboot, Shutdown)**. Delete `Install`, `Remove`, `About`, `System`, `Hardware`, `Reminder`, `Share`, `Font`, `Screensaver`, `Setup→Defaults/Config/Security/System`. Keep the `menu()` helper and `go_to_menu` dispatch exactly. Update → `fh-launch-floating-terminal-with-presentation fh-update`. Every `omarchy-` reference becomes `fh-`; every command it calls must be in the required set or removed.

- [ ] **Step 5: Build, test, commit**

`make check` → all PASS.
```bash
git add -A && git commit -m "feat: fh-* helper scripts and menu"
```

---

### Task 8: VM smoke test target

**Files:**
- Create: `vm.sh`; modify `Makefile` (`vm` target), `README.md` (prereqs)

**Interfaces:**
- Produces: `make vm` boots the image in QEMU with UEFI, virtio-gpu, 4 GB RAM. First run installs to `vm/disk.raw` via `bootc install to-disk`; later runs boot the existing disk unless `FRESH=1`.
- Host prereqs (Arch): `sudo pacman -S --needed qemu-desktop edk2-ovmf`. Rootful podman is needed for `bootc install` (loop devices).

- [ ] **Step 1: vm.sh**

```bash
#!/usr/bin/env bash
# Install the built image into a raw disk (via bootc, rootful podman) and boot it in QEMU.
set -euo pipefail
IMAGE="${IMAGE:-localhost/fedora-hypr:44}"
DISK="${DISK:-vm/disk.raw}"
OVMF_CODE=/usr/share/edk2/x64/OVMF_CODE.4m.fd
OVMF_VARS=/usr/share/edk2/x64/OVMF_VARS.4m.fd

mkdir -p vm
if [[ ! -f $DISK || ${FRESH:-0} == 1 ]]; then
  rm -f "$DISK"; truncate -s 20G "$DISK"
  # rootful podman sees the rootless image only if we pass it through; copy once.
  sudo podman image exists "$IMAGE" || podman image scp "$USER@localhost::$IMAGE" root@localhost::
  sudo podman run --rm --privileged --pid=host --security-opt label=type:unconfined_t \
    -v /dev:/dev -v /var/lib/containers:/var/lib/containers -v "$PWD/vm:/vm" \
    "$IMAGE" bootc install to-disk --via-loopback --wipe --filesystem btrfs --generic-image "/vm/$(basename "$DISK")"
  sudo chown "$USER" "$DISK"
fi
[[ -f vm/OVMF_VARS.fd ]] || cp "$OVMF_VARS" vm/OVMF_VARS.fd

exec qemu-system-x86_64 -enable-kvm -m 4096 -smp 4 -cpu host \
  -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
  -drive if=pflash,format=raw,file=vm/OVMF_VARS.fd \
  -drive file="$DISK",format=raw,if=virtio \
  -device virtio-gpu-gl -display gtk,gl=on \
  -device virtio-keyboard -device virtio-tablet \
  -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
  -audiodev pipewire,id=a0 -device intel-hda -device hda-output,audiodev=a0
```
`chmod +x vm.sh`. Makefile: `vm: build` → `./vm.sh`. If `podman image scp` to root fails on this host, the fallback is `make push` then `IMAGE=ghcr.io/bakedbean/fedora-hypr:44 ./vm.sh` after `sudo podman pull`.

- [ ] **Step 2: Run it**

Run: `make vm`
Expected, in order: GRUB → Plymouth/boot → tuigreet on tty1. Log in as `eben` / `changeme`, set a new password → Hyprland starts with Waybar, tokyo-night wallpaper. Press SUPER+RETURN → Alacritty. SUPER+SPACE → Walker. Run `fh-theme-set gruvbox` in the terminal → colours change without restart. `journalctl -u fh-first-boot` shows user creation and Flatpak progress.

Record what fails, fix in the relevant earlier task's files, rebuild, `FRESH=1 make vm`. Do not proceed until login → Hyprland → theme switch works in the VM.

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "build: qemu vm smoke test target"
```

---

### Task 9: CI — build and push to ghcr.io

**Files:**
- Create: `.github/workflows/build.yml`, `README.md`

- [ ] **Step 1: Workflow**

```yaml
name: build
on:
  push:
    branches: [main]
    paths-ignore: ['docs/**', 'README.md']
  schedule:
    - cron: '30 5 * * *'   # daily, after ublue's base-main rebuild
  workflow_dispatch:

permissions:
  contents: read
  packages: write

env:
  IMAGE: ghcr.io/${{ github.repository }}
  TAG: '44'

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Build
        run: |
          sudo podman build -t "$IMAGE:$TAG" -t "$IMAGE:$TAG-$(date +%Y%m%d)" .
      - name: Self-check
        run: sudo podman run --rm -v ./tests:/tests:ro "$IMAGE:$TAG" bash /tests/check.sh
      - name: Login
        run: echo "${{ secrets.GITHUB_TOKEN }}" | sudo podman login ghcr.io -u "${{ github.actor }}" --password-stdin
      - name: Push
        run: |
          sudo podman push "$IMAGE:$TAG"
          sudo podman push "$IMAGE:$TAG-$(date +%Y%m%d)"
```
The date tag gives `bootc switch ghcr.io/bakedbean/fedora-hypr:44-20260920` as a way to pin to a known-good build.

- [ ] **Step 2: README**

Sections: what this is (two sentences), host prereqs, `make build / check / vm`, install to a disk (the Task 10 commands), day-2 (`fh-update`, `bootc rollback`, `bootc switch` to a date tag), layout (the file map above), attribution to Omarchy.

- [ ] **Step 3: Push and watch**

```bash
git add -A && git commit -m "ci: build and push image to ghcr.io" && git push
gh run watch --exit-status
```
Expected: green. Then: `gh api /user/packages/container/fedora-hypr --jq .visibility` — if `private`, make it public in the GitHub package settings (bootc on the target must pull anonymously).

Verify pull from the image: `podman pull ghcr.io/bakedbean/fedora-hypr:44`.

---

### Task 10: Install to `/dev/sda` and prove it out

**Files:** none new. This is an operations task with a confirmation gate.

- [ ] **Step 1: Confirm target and offer backup — STOP and ask the user**

`lsblk -o NAME,SIZE,TRAN,MODEL /dev/sda` must show the 931.5G USB "1TB Card". Ask the user to confirm wiping it. Offer: unlock `/dev/sda2` (LUKS) and `rsync` its `/home` to `~/data/omarchy-trial-home/` first. Do not continue without an explicit yes.

- [ ] **Step 2: Install**

```bash
sudo podman pull ghcr.io/bakedbean/fedora-hypr:44
sudo podman run --rm --privileged --pid=host --security-opt label=type:unconfined_t \
  -v /dev:/dev -v /var/lib/containers:/var/lib/containers \
  ghcr.io/bakedbean/fedora-hypr:44 \
  bootc install to-disk --wipe --filesystem btrfs /dev/sda
```
Expected: ends with `Installation complete!`. `lsblk /dev/sda` shows an EFI partition and a btrfs root.

- [ ] **Step 3: Boot and run the done-criteria checklist**

Reboot, F12 → USB drive. On the Framework 12, in Hyprland, tick each:

- [ ] greetd → login → Hyprland with Waybar and wallpaper
- [ ] Wi-Fi via `fh-launch-wifi` (impala) connects
- [ ] brightness keys, volume keys (SwayOSD overlay), audio output
- [ ] suspend on lid close + resume
- [ ] `fprintd-enroll` then fingerprint at hyprlock
- [ ] touchpad gestures (3-finger workspace swipe)
- [ ] `fh-theme-set` across 3 themes: Hyprland border, Waybar, mako, Alacritty, Walker all change
- [ ] `fh-menu` every branch opens something
- [ ] Flatpaks present (`flatpak list`) after `fh-first-boot` finishes
- [ ] `fh-update` → reboot → `bootc status` shows the new image booted; `sudo bootc rollback` → reboot → previous image booted; `/home` untouched both times

Any failure: fix in the repo, push, `bootc upgrade`, re-tick. Record hardware findings (e.g. a needed kernel arg) in `README.md` under "Framework 12 notes".

- [ ] **Step 4: Commit README notes**

```bash
git add -A && git commit -m "docs: framework 12 verification notes" && git push
```

---

## Self-review

**Spec coverage:** §1 layout → Task 1; §2 packages → Task 2 (sources changed from spec: Hyprland is no longer in Fedora 44 repos, so the whole hypr stack comes from `dtutila/hyprland`; `polkit-gnome` → `hyprpolkitagent`; `gnome-themes-extra` dropped — not packaged); §3 config/scripts/theme/menu/update/first-boot → Tasks 3–7; §4 install/test loop → Tasks 8–10; CI → Task 9; done criteria → Task 10 step 3.

**Placeholders:** none — every script and config is either given in full or produced by a stated command over a stated source file with a stated grep verifying the result.

**Name consistency:** `FH_PATH`, `~/.config/fedora-hypr/{current/{theme,theme.name,background,next-theme},themes,themed,hooks}`, `~/.local/state/fedora-hypr/toggles/hypr`, `fh-theme-set`, `fh-theme-set-templates`, `fh-theme-bg-next`, `fh-theme-list`, `fh-theme-current`, `fh-restart-{waybar,swayosd,mako,hyprctl,walker,…}`, `fh-first-boot`, `fh-first-run`, `fh-update`, `fh-menu`, `fh-toggle-enabled` are used with the same names in Tasks 5, 6, 7, 10 and in `tests/*.sh`.
