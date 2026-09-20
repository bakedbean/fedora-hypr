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

exit $fail
