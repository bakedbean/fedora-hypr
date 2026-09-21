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
