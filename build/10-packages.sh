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

# Drop build-time-only content so `bootc container lint` has nothing to warn about.
# These are transient dnf/systemd-tmpfiles/scriptlet artifacts of this RUN step, not
# content the image needs to ship: /run and /tmp are always ephemeral, and none of
# the /var paths below have a systemd tmpfiles.d entry, so on a real bootc system
# they would never persist anyway (the owning services recreate their own state).
rm -rf /run/dnf /run/selinux-policy /tmp/nvim.root
rm -f /var/log/dnf5.log
rm -rf /var/cache/libdnf5 /var/cache/ldconfig/aux-cache
rm -rf /var/lib/dnf/repos
rm -rf /var/lib/ead /var/lib/fprint /var/lib/iwd /var/lib/power-profiles-daemon
rm -rf /var/lib/greetd/.config
