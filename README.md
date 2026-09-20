# fedora-hypr

A [bootc](https://containers.github.io/bootc/) image, built on `ghcr.io/ublue-os/base-main`, that boots
into an Omarchy-flavored Hyprland desktop on Fedora. It replaces Omarchy's Arch/pacman base with an
immutable, container-built, atomically-updated Fedora image while keeping the same look, keybindings,
theming, and helper-script workflow.

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
  sudo podman load`, skipped if rootful podman already has it), and runs `bootc install to-disk
  --via-loopback --wipe --filesystem btrfs --generic-image` against it inside a privileged container.
- Later runs: boot the existing `vm/disk.raw` as-is (no reinstall).
- `FRESH=1 make vm`: force a wipe and reinstall to `vm/disk.raw` even if it already exists — use this
  after rebuilding the image to pick up changes.
- Boots with UEFI (OVMF), virtio-gpu (GL), 4 GB RAM, virtio net/keyboard/tablet, and a pipewire audio
  device. OVMF firmware paths default to the Arch locations
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

## Day 2

- `fh-update` — pull and stage the latest image (wraps `bootc upgrade`); reboot to apply.
- `sudo bootc rollback` — boot the previous deployment if an update regresses something; reboot to
  apply. `/home` is untouched by upgrades and rollbacks.
- `sudo bootc switch ghcr.io/bakedbean/fedora-hypr:44-YYYYMMDD` — pin to a specific known-good dated
  build instead of tracking the rolling `:44` tag; switch back to `:44` later to resume tracking.

## CI

`.github/workflows/build.yml` builds the image, runs `tests/check.sh` inside it, and pushes
`ghcr.io/bakedbean/fedora-hypr:44` and `ghcr.io/bakedbean/fedora-hypr:44-YYYYMMDD` on every push to
`main`, on a daily schedule (after ublue's `base-main` rebuilds), and on manual dispatch. The tag is
derived from the `Containerfile`'s `FROM` line the same way the `Makefile` derives it, so it's never
hard-coded in the workflow.

## Layout

```
fedora-hypr/
├── Containerfile               # FROM ghcr.io/ublue-os/base-main:44 … RUN bootc container lint
├── build/                      # scripts run during image build
│   ├── 10-packages.sh          # dnf install from Fedora repos + pinned COPRs
│   ├── 20-services.sh          # systemctl enable greetd, fh-first-boot; drop COPR repo files
│   ├── packages/                 # fedora.txt / copr.txt package lists
│   └── repos/                    # pinned .repo files for COPRs used at build time
├── system/                     # copied verbatim onto / in the image (COPY system/ /)
│   ├── usr/bin/fh-*             # helper scripts (theming, launchers, toggles, first-boot, update, …)
│   ├── usr/share/fedora-hypr/
│   │   ├── default/               # canonical hypr/waybar/mako/swaybg/hyprlock/hypridle configs
│   │   ├── themed/                # theme-parameterized templates (*.tpl)
│   │   ├── themes/<name>/         # ported theme color definitions
│   │   └── flatpaks.txt           # Flatpaks installed by fh-first-boot
│   ├── usr/lib/systemd/system/    # fh-first-boot.service
│   └── etc/
│       ├── skel/.config/          # thin per-user config seeded on first login, sources the defaults
│       ├── greetd/config.toml     # tuigreet → uwsm start Hyprland
│       └── ...                    # NetworkManager, environment.d, sudoers.d, profile.d
├── tests/                       # check.sh (in-image self-check) + scripts_test.sh, theme_test.sh
├── vm.sh                        # install-to-raw-disk + QEMU boot for local smoke testing
├── Makefile                     # build / shell / check / push / vm targets
└── .github/workflows/build.yml  # CI: build, self-check, push to ghcr.io
```

Three layers, same split Omarchy uses:

- **Image layer** (`Containerfile`, `build/`): what's installed. Change = rebuild + `bootc upgrade`.
- **System layer** (`system/`): config and scripts owned by the image under `/usr`, read-only on the
  running system, versioned with the image.
- **User layer** (`~/.config`, seeded from `/etc/skel` on first login): the user's overrides, persisted
  across upgrades.

## Attribution

The desktop look, keybindings, theme set, and helper-script model are ported from
[Omarchy](https://github.com/basecamp/omarchy) by DHH, MIT licensed (see `LICENSE.omarchy`). This
project replaces Omarchy's Arch/pacman base with a Fedora bootc image; the config and script layer is
adapted from Omarchy's source, not copied verbatim.

## Framework 12 notes

_(Verification on Framework 12 hardware is tracked as a follow-on task; this section will be filled in
with any hardware-specific findings — e.g. required kernel args — once that pass is done.)_
