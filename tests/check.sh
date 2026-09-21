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
         zsh nvim btop bat eza fd rg zoxide jq dust tldr fastfetch magick \
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
check grep -q 'uwsm start -- fedora-hypr.desktop' /etc/greetd/config.toml
# greetd must run as the user its RPM creates (sysusers), not a made-up one
check getent passwd "$(sed -n 's/^user = "\(.*\)"/\1/p' /etc/greetd/config.toml)"
check grep -q 'd /var/cache/tuigreet 0755 greetd greetd' /usr/lib/tmpfiles.d/fedora-hypr.conf
# our own session entry: never overwrite the RPM-owned hyprland-uwsm.desktop
check test -f /usr/share/wayland-sessions/fedora-hypr.desktop
check rpm -V hyprland
check test "$(systemctl is-enabled greetd 2>/dev/null)" = enabled
check test "$(systemctl is-enabled getty@tty1 2>/dev/null)" = disabled
check bash -lc 'test "$FH_PATH" = /usr/share/fedora-hypr'
check grep -q 'wifi.backend=iwd' /etc/NetworkManager/conf.d/wifi-backend-iwd.conf
check test "$(systemctl is-enabled iwd 2>/dev/null)" = enabled
check test "$(systemctl is-enabled sshd 2>/dev/null)" = disabled
# first boot runs preset-all (empty machine-id); our preset must win over 90-default's "enable sshd"
check test -f /usr/lib/systemd/system-preset/05-fedora-hypr.preset
check grep -q '^disable sshd.service' /usr/lib/systemd/system-preset/05-fedora-hypr.preset
check grep -q '^disable getty@tty1.service' /usr/lib/systemd/system-preset/05-fedora-hypr.preset
check grep -q pam_fprintd /etc/pam.d/system-auth
check grep -q 'fingerprint:enabled = true' /etc/skel/.config/hypr/hyprlock.conf
check zsh -lc 'test "$FH_PATH" = /usr/share/fedora-hypr'

# --- Task 4: first boot (two units: user creation before greetd, flatpaks once online)
check test "$(systemctl is-enabled fh-first-boot-user 2>/dev/null)" = enabled
check test "$(systemctl is-enabled fh-first-boot-flatpaks 2>/dev/null)" = enabled
check systemd-analyze verify /usr/lib/systemd/system/fh-first-boot-user.service
check systemd-analyze verify /usr/lib/systemd/system/fh-first-boot-flatpaks.service
check grep -q '^Before=greetd.service' /usr/lib/systemd/system/fh-first-boot-user.service
check bash -c '! grep -q network /usr/lib/systemd/system/fh-first-boot-user.service'
check grep -q '^After=network-online.target fh-first-boot-user.service' /usr/lib/systemd/system/fh-first-boot-flatpaks.service
check grep -q '^Restart=on-failure' /usr/lib/systemd/system/fh-first-boot-flatpaks.service
check grep -q '^Type=simple' /usr/lib/systemd/system/fh-first-boot-flatpaks.service
check grep -q '^Type=oneshot' /usr/lib/systemd/system/fh-first-boot-user.service
check bash -c 'FH_USER=testuser fh-first-boot-user && id -nG testuser | grep -qw wheel && test -d /var/home/testuser'
# password is NOT expired (tuigreet cannot run the PAM change conversation); a marker drives fh-setup-password instead
check bash -c '! grep -q "chage" /usr/bin/fh-first-boot-user'
check grep -q -- "--shell /usr/bin/zsh" /usr/bin/fh-first-boot-user
check test -x /usr/bin/fh-setup-password
check test -f /var/home/testuser/.local/state/fedora-hypr/password-change-pending
check test "$(stat -c %U /var/home/testuser/.local/state/fedora-hypr/password-change-pending)" = testuser
check grep -q fh-setup-password /usr/bin/fh-first-run
check grep -q fh-setup-password /usr/bin/fh-menu
# the theme is rendered into the new HOME before any Hyprland session, as that user
check bash -c 'test "$(cat /var/home/testuser/.config/fedora-hypr/current/theme.name)" = tokyo-night'
check test -L /var/home/testuser/.config/fedora-hypr/current/background
check test -f /var/home/testuser/.config/fedora-hypr/current/theme/hyprland.conf
check test "$(stat -c %U /var/home/testuser/.config/fedora-hypr/current/theme.name)" = testuser
check bash -c 'FH_USER=testuser fh-first-boot-user'   # idempotent: second run succeeds
check test -f /etc/sudoers.d/wheel
check bash -c 'FH_USER=testuser2 fh-first-boot-user && test -f /var/lib/fedora-hypr/user.done'
# flatpaks: an empty list succeeds and writes the marker; a failing app leaves no marker
check bash -c 'rm -f /var/lib/fedora-hypr/flatpaks.done; FH_FLATPAKS_LIST=/dev/null fh-first-boot-flatpaks && test -f /var/lib/fedora-hypr/flatpaks.done'
check bash -c 'rm -f /var/lib/fedora-hypr/flatpaks.done; l=$(mktemp); echo org.example.DoesNotExist > "$l"; ! FH_FLATPAKS_LIST=$l fh-first-boot-flatpaks && ! test -f /var/lib/fedora-hypr/flatpaks.done'

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
# a FRESH skel HOME with no theme rendered yet must still parse (hyprlang noerror around the theme source)
check bash -c '
  export HOME=$(mktemp -d); cp -r /etc/skel/. "$HOME"; export FH_PATH=/usr/share/fedora-hypr
  export XDG_RUNTIME_DIR=$(mktemp -d); chmod 700 "$XDG_RUNTIME_DIR"
  Hyprland --verify-config --i-am-really-stupid'
# hypridle/hyprlock only search ~/.config/hypr, so their configs live in skel (users own them)
check test -f /etc/skel/.config/hypr/hypridle.conf
check test -f /etc/skel/.config/hypr/hyprlock.conf
check bash -c '
  export HOME=$(mktemp -d); cp -r /etc/skel/. "$HOME"; export FH_PATH=/usr/share/fedora-hypr
  export XDG_RUNTIME_DIR=$(mktemp -d); chmod 700 "$XDG_RUNTIME_DIR"
  FH_THEME_SKIP_BACKGROUND=1 fh-theme-set tokyo-night
  ! (timeout 2 hypridle 2>&1 | grep -q "No hypridle.conf")'
check bash -c '
  export HOME=$(mktemp -d); cp -r /etc/skel/. "$HOME"; export FH_PATH=/usr/share/fedora-hypr
  export XDG_RUNTIME_DIR=$(mktemp -d); chmod 700 "$XDG_RUNTIME_DIR"
  FH_THEME_SKIP_BACKGROUND=1 fh-theme-set tokyo-night
  ! (timeout 2 hyprlock 2>&1 | grep -q "Could not find config")'
# xdg-terminal-exec maps --app-id/--title/--dir onto alacritty flags via the skel desktop entry
check bash -c '
  export HOME=$(mktemp -d); cp -r /etc/skel/. "$HOME"
  out=$(XTE_DEBUG=1 xdg-terminal-exec --app-id=x -e true 2>&1)
  ! grep -q "has no TerminalArgAppId" <<<"$out" && grep -q -- "--class=x" <<<"$out"'
check bash /tests/binds_test.sh
check bash -c '! grep -rl omarchy /usr/share/fedora-hypr/default /etc/skel | grep -v LICENSE'
check test -f /usr/share/fedora-hypr/default/mako/core.ini
check grep -q "fedora-hypr/current/theme/alacritty.toml" /etc/skel/.config/alacritty/alacritty.toml
check bash -c 'sed "s|//.*||" /usr/share/fedora-hypr/default/waybar/config.jsonc | jq .'
check bash -c 'sed "s|//.*||" /etc/skel/.config/waybar/config.jsonc | jq .'
check bash -c '! grep -rn "@import \"~" /usr/share/fedora-hypr /etc/skel'
check test -f /etc/skel/.config/walker/themes/fh-default/style.css
check grep -q "../fedora-hypr/current/theme/swayosd.css" /etc/skel/.config/swayosd/style.css
check bash -c '! grep -q dbus-update-activation-environment /usr/share/fedora-hypr/default/hypr/autostart.conf'
check grep -q 'exec-once = systemctl --user import-environment' /usr/share/fedora-hypr/default/hypr/autostart.conf
check grep -q -- '--dmenu --maxheight "$menu_height" --minheight "$menu_height"' /usr/bin/fh-menu-keybindings
check grep -q 'FH_PATH:=/usr/share/fedora-hypr' /usr/bin/fh-hyprland-toggle
check bash -c 'grep -q fh-theme-set-gnome /usr/bin/fh-theme-set && grep -q fh-restart-btop /usr/bin/fh-theme-set'
check test -f /usr/share/fedora-hypr/themes/white/light.mode
check grep -q fh-setup-fingerprint /usr/bin/fh-menu

# --- Task 7: helper scripts
check bash /tests/scripts_test.sh
check grep -q 'exec-once = uwsm-app -- elephant' /usr/share/fedora-hypr/default/hypr/autostart.conf

exit $fail
