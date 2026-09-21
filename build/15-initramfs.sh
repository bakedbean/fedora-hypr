#!/usr/bin/env bash
set -euo pipefail

# Boot splash: Plymouth "hypedora" theme (system/usr/share/plymouth/themes/hypedora,
# selected by system/etc/plymouth/plymouthd.conf) must be inside the initramfs, which
# base-main ships prebuilt. Rebuild it the way ublue does; dracut's plymouth module copies
# the default theme + script.so from plymouth-plugin-script. "quiet splash" come from
# system/usr/lib/bootc/kargs.d/10-fedora-hypr.toml. Adds ~1 min to the build, which is why
# this is its own layer: the Containerfile copies only the Plymouth files before it, so
# every other system/ change reuses it from cache.
[[ "$(plymouth-set-default-theme)" == hypedora ]]
KVER=$(ls /usr/lib/modules | head -1)
# /root -> var/roothome exists only on a booted system; give dracut the target so the
# initramfs gets the symlink without an "installing '/root'" error, then remove it again
# (nothing under /var may ship).
mkdir -p /var/roothome
dracut --no-hostonly --kver "$KVER" --reproducible --add ostree -f "/usr/lib/modules/$KVER/initramfs.img"
rmdir /var/roothome
# (grep without -q: with pipefail, an early grep exit would kill lsinitrd with SIGPIPE → 141)
lsinitrd "/usr/lib/modules/$KVER/initramfs.img" | grep hypedora/logo.png >/dev/null
