#!/usr/bin/env bash
# Runs inside the built image. Every check prints PASS/FAIL; exits 1 on any FAIL.
set -uo pipefail
fail=0
check() { if "$@" >/dev/null 2>&1; then echo "PASS $*"; else echo "FAIL $*"; fail=1; fi; }

# --- Task 2: packages
for b in Hyprland hyprlock hypridle hyprpicker hyprsunset uwsm \
         walker elephant waybar mako swaybg grim slurp satty wl-copy \
         alacritty starship lazygit mise impala bluetui wiremix gum greetd tuigreet \
         gpu-screen-recorder hyprland-preview-share-picker firefox nautilus \
         fish nvim btop bat eza fd rg zoxide jq dust tldr fastfetch magick \
         fcitx5 flatpak; do
  check command -v "$b"
done
check test -x /usr/libexec/hyprpolkitagent
check rpm -q fprintd
check command -v chromium-browser
check command -v swayosd-server
check command -v swayosd-client
check rpm -q nerd-fonts-jetbrainsmono nerd-fonts-firacode jetbrains-mono-fonts \
      fontawesome-6-free-fonts google-noto-sans-fonts yaru-icon-theme kvantum \
      libva-intel-media-driver xdg-desktop-portal-hyprland xdg-desktop-portal-gtk \
      qt5-qtwayland qt6-qtwayland podman-docker gnome-keyring-pam fprintd-pam iwd
# No third-party repos left in the runtime image
check bash -c '! ls /etc/yum.repos.d/ | grep -Eq "^(dtutila|washkinazy|mineiro|agaspar|whelanh)-"'

# --- Task 3: session plumbing
check test -f /etc/greetd/config.toml
check grep -q 'uwsm start' /etc/greetd/config.toml
check test -f /usr/share/wayland-sessions/hyprland-uwsm.desktop
check test "$(systemctl is-enabled greetd 2>/dev/null)" = enabled
check test "$(systemctl is-enabled getty@tty1 2>/dev/null)" = disabled
check bash -lc 'test "$FH_PATH" = /usr/share/fedora-hypr'
check grep -q 'wifi.backend=iwd' /etc/NetworkManager/conf.d/wifi-backend-iwd.conf
check test "$(systemctl is-enabled iwd 2>/dev/null)" = enabled

# --- Task 4: first boot
check test "$(systemctl is-enabled fh-first-boot 2>/dev/null)" = enabled
check systemd-analyze verify /usr/lib/systemd/system/fh-first-boot.service
check bash -c 'FH_SKIP_FLATPAK=1 FH_USER=testuser fh-first-boot && id -nG testuser | grep -qw wheel && test -d /var/home/testuser'
check bash -c 'FH_SKIP_FLATPAK=1 FH_USER=testuser fh-first-boot'   # idempotent: second run succeeds
check test -f /etc/sudoers.d/wheel
check bash -c 'FH_SKIP_FLATPAK=1 FH_USER=testuser2 fh-first-boot && test -f /var/lib/fedora-hypr/first-boot.done'
check grep -q '^Restart=on-failure' /usr/lib/systemd/system/fh-first-boot.service

# --- Task 5: theme engine
check bash /tests/theme_test.sh

# --- Task 6: default config + skel
# Hyprland refuses to run as root without --i-am-really-stupid, and needs
# XDG_RUNTIME_DIR set even for a headless --verify-config; check.sh runs as
# root in the build container, so both are supplied here.
check bash -c '
  export HOME=$(mktemp -d); cp -r /etc/skel/. "$HOME"; export FH_PATH=/usr/share/fedora-hypr
  export XDG_RUNTIME_DIR=$(mktemp -d); chmod 700 "$XDG_RUNTIME_DIR"
  FH_THEME_SKIP_BACKGROUND=1 fh-theme-set tokyo-night
  Hyprland --verify-config --i-am-really-stupid'
check bash -c '! grep -rl omarchy /usr/share/fedora-hypr/default /etc/skel | grep -v LICENSE'
check test -f /usr/share/fedora-hypr/default/mako/core.ini
check grep -q "fedora-hypr/current/theme/alacritty.toml" /etc/skel/.config/alacritty/alacritty.toml
check bash -c 'sed "s|//.*||" /usr/share/fedora-hypr/default/waybar/config.jsonc | jq .'
check bash -c 'sed "s|//.*||" /etc/skel/.config/waybar/config.jsonc | jq .'
check bash -c '! grep -rn "@import \"~" /usr/share/fedora-hypr /etc/skel'
check test -f /etc/skel/.config/walker/themes/fh-default/style.css
check grep -q "../fedora-hypr/current/theme/swayosd.css" /etc/skel/.config/swayosd/style.css
check bash -c '! grep -q dbus-update-activation-environment /usr/share/fedora-hypr/default/hypr/autostart.conf'

# --- Task 7: helper scripts
check bash /tests/scripts_test.sh

exit $fail
