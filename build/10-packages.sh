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

# Some packages install their main binary outside $PATH or under a distro-specific
# name; symlink them so the tool names documented in this repo's interface actually
# resolve via `command -v`.
ln -sf /usr/libexec/hyprpolkitagent /usr/bin/hyprpolkitagent
ln -sf /usr/libexec/fprintd /usr/bin/fprintd
ln -sf /usr/bin/chromium-browser /usr/bin/chromium
ln -sf /usr/bin/swayosd-server /usr/bin/swayosd
