#!/usr/bin/env bash
# Install the pinned tether RPM (Containerfile tether-fetch stage); dnf resolves its deps
# (bluez-obexd, gtk-layer-shell, ...) from the Fedora repos. Runs inside the build container.
set -euo pipefail

dnf -y install --setopt=install_weak_deps=False /ctx/tether.rpm
dnf clean all
rm -f /ctx/tether.rpm

# Same transient build artifacts 10-packages.sh drops, so `bootc container lint` stays clean.
rm -rf /run/dnf /run/selinux-policy
rm -f /var/log/dnf5.log
rm -rf /var/cache/libdnf5 /var/cache/ldconfig/aux-cache
rm -rf /var/lib/dnf/repos
