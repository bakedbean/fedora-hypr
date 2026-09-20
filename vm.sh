#!/usr/bin/env bash
# Install the built image into a raw disk (via bootc, rootful podman) and boot it in QEMU.
set -euo pipefail
IMAGE="${IMAGE:-localhost/fedora-hypr:44}"
DISK="${DISK:-vm/disk.raw}"
OVMF_CODE="${OVMF_CODE:-/usr/share/edk2/x64/OVMF_CODE.4m.fd}"
OVMF_VARS="${OVMF_VARS:-/usr/share/edk2/x64/OVMF_VARS.4m.fd}"

if [[ ! -f $OVMF_CODE ]]; then
  echo "OVMF firmware not found at $OVMF_CODE." >&2
  echo "Install it with: sudo pacman -S --needed qemu-desktop edk2-ovmf" >&2
  echo "(or set OVMF_CODE/OVMF_VARS to point at your distro's paths)" >&2
  exit 1
fi

mkdir -p vm
if [[ ! -f $DISK || ${FRESH:-0} == 1 ]]; then
  rm -f "$DISK"; truncate -s 20G "$DISK"
  # rootful podman needs its own copy of the image; load it from the rootless store once.
  sudo podman image exists "$IMAGE" || podman save "$IMAGE" | sudo podman load
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
