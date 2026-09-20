#!/usr/bin/env bash
# Install the built image into a raw disk (via bootc, rootful podman) and boot it in QEMU.
set -euo pipefail
IMAGE="${IMAGE:-localhost/fedora-hypr:44}"
DISK="${DISK:-vm/disk.raw}"
OVMF_CODE="${OVMF_CODE:-/usr/share/edk2/x64/OVMF_CODE.4m.fd}"
OVMF_VARS="${OVMF_VARS:-/usr/share/edk2/x64/OVMF_VARS.4m.fd}"

for f in "$OVMF_CODE" "$OVMF_VARS"; do
  if [[ ! -f $f ]]; then
    echo "OVMF firmware not found at $f." >&2
    echo "Install it with: sudo pacman -S --needed qemu-desktop edk2-ovmf" >&2
    echo "(or set OVMF_CODE/OVMF_VARS to point at your distro's paths)" >&2
    exit 1
  fi
done

mkdir -p vm
if [[ ! -f $DISK || ${FRESH:-0} == 1 ]]; then
  # Install into a temp file and only rename on success, so a failed install
  # never leaves a bootable-looking $DISK behind.
  tmp="$DISK.tmp"; rm -f "$tmp"; truncate -s 20G "$tmp"
  trap 'rm -f "$tmp"' ERR
  # rootful podman needs its own copy of the image; (re)load it from the rootless
  # store whenever the two stores hold different image ids (i.e. after a rebuild).
  [[ "$(podman image inspect -f '{{.Id}}' "$IMAGE")" == "$(sudo podman image inspect -f '{{.Id}}' "$IMAGE" 2>/dev/null)" ]] ||
    podman save "$IMAGE" | sudo podman load
  sudo podman run --rm --privileged --pid=host --security-opt label=type:unconfined_t \
    -v /dev:/dev -v /var/lib/containers:/var/lib/containers -v "$PWD/vm:/vm" \
    "$IMAGE" bootc install to-disk --via-loopback --wipe --filesystem btrfs --generic-image \
      --karg console=ttyS0,115200 --karg console=tty0 "/vm/$(basename "$tmp")"
  sudo chown "$USER" "$tmp"; mv "$tmp" "$DISK"; trap - ERR
fi
[[ -f vm/OVMF_VARS.fd ]] || cp "$OVMF_VARS" vm/OVMF_VARS.fd
rm -f vm/monitor.sock vm/serial.sock

# The host compositor swallows SUPER combos before QEMU sees them, so a QEMU monitor
# is exposed on vm/monitor.sock for injecting keys, and the guest serial console on
# vm/serial.sock for logging in from the host (see README, "make vm").

exec qemu-system-x86_64 -enable-kvm -m 4096 -smp 4 -cpu host \
  -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
  -drive if=pflash,format=raw,file=vm/OVMF_VARS.fd \
  -drive file="$DISK",format=raw,if=virtio \
  -vga none -device virtio-gpu-gl -display gtk,gl=on \
  -device virtio-keyboard -device virtio-tablet \
  -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
  -audiodev pipewire,id=a0 -device intel-hda -device hda-output,audiodev=a0 \
  -monitor unix:vm/monitor.sock,server,nowait \
  -chardev socket,id=ser0,path=vm/serial.sock,server=on,wait=off,logfile=vm/serial.log \
  -serial chardev:ser0
