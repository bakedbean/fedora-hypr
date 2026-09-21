#!/usr/bin/env bash
set -euo pipefail

# Drop build-time COPR definitions so the runtime image has no third-party repos.
rm -f /etc/yum.repos.d/{dtutila,washkinazy,mineiro,agaspar,whelanh}-*.repo

# --- Task 3: session plumbing
systemctl enable greetd.service
systemctl disable getty@tty1.service
systemctl enable iwd.service
systemctl enable power-profiles-daemon.service
systemctl enable bluetooth.service
systemctl enable fprintd.service 2>/dev/null || true   # socket/dbus activated on Fedora; harmless
# base-main enables sshd; a desktop image should not listen by default.
systemctl disable sshd.service

# Fingerprint auth for login/sudo/polkit via PAM (enrol with fh-setup-fingerprint)
authselect enable-feature with-fingerprint
# authselect drops a checksum under /var, which bootc images must not ship (lint
# warning). Removing it is safe: `authselect current/check` still work from
# /etc/authselect, and the next authselect run recreates it.
rm -rf /var/lib/authselect

# --- Task 4: first boot (user creation before greetd; flatpaks once the network is up)
systemctl enable fh-first-boot-user.service
systemctl enable fh-first-boot-flatpaks.service
chmod 0440 /etc/sudoers.d/wheel
chmod 0440 /etc/sudoers.d/fh-update-available

# --- GSettings defaults (system/usr/share/glib-2.0/schemas/*.gschema.override): compile them
# into gschemas.compiled so Nautilus/GTK pick them up without any per-user step.
glib-compile-schemas /usr/share/glib-2.0/schemas

# --- Boot splash: Plymouth "hypedora" theme (system/usr/share/plymouth/themes/hypedora,
# selected by system/etc/plymouth/plymouthd.conf) must be inside the initramfs, which
# base-main ships prebuilt. Rebuild it the way ublue does; dracut's plymouth module copies
# the default theme + script.so from plymouth-plugin-script. "quiet splash" come from
# system/usr/lib/bootc/kargs.d/10-fedora-hypr.toml. Adds ~1 min to the build.
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
