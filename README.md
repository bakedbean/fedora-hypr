# fedora-hypr

## `make vm`

`make vm` builds the image, installs it to a raw disk with `bootc install`, and boots it in QEMU for
local smoke testing.

**Host prereqs (Arch):**

```
sudo pacman -S --needed qemu-desktop edk2-ovmf
```

Rootful podman is required for `bootc install` (it needs loop devices), so `vm.sh` shells out to `sudo
podman`; your user needs KVM access (typically the `kvm` group) and `sudo`.

**Behavior:**

- First run: creates a 20G `vm/disk.raw`, loads the image into rootful podman's store if it isn't there
  already, and runs `bootc install to-disk --via-loopback --wipe --filesystem btrfs --generic-image`
  against it.
- Later runs: boot the existing `vm/disk.raw` as-is.
- `FRESH=1 make vm`: force a wipe and reinstall to `vm/disk.raw` even if it already exists — use this
  after rebuilding the image to pick up changes.
- OVMF firmware paths default to the Arch locations and can be overridden with the `OVMF_CODE` /
  `OVMF_VARS` env vars on other distros.
