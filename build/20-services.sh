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

# --- Task 4: first boot
systemctl enable fh-first-boot.service
chmod 0440 /etc/sudoers.d/wheel
