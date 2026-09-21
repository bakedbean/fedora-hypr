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
         zsh chsh nvim btop bat eza fd rg zoxide jq dust tldr fastfetch magick \
         fcitx5 flatpak; do
  check command -v "$b"
done
check test -x /usr/libexec/hyprpolkitagent
# pinned to 0.56.x: 0.57 drops .conf/hyprlang support (AGENTS.md, Lua config migration)
check bash -c "rpm -q hyprland | grep -q '^hyprland-0.56'"
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
check grep -q 'hyprland.desktop' /etc/greetd/config.toml
# greetd must run as the user its RPM creates (sysusers), not a made-up one
check getent passwd "$(sed -n 's/^user = "\(.*\)"/\1/p' /etc/greetd/config.toml)"
check grep -q 'd /var/cache/tuigreet 0755 greetd greetd' /usr/lib/tmpfiles.d/fedora-hypr.conf
# session launches via the RPM-owned hyprland.desktop (start-hyprland); we ship no session file of our own
check test -x "$(sed -n 's/^Exec=//p' /usr/share/wayland-sessions/hyprland.desktop)"
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
# Nautilus + GTK file choosers show hidden files by default (gschema override, compiled in)
check test -f /usr/share/glib-2.0/schemas/10-fedora-hypr.gschema.override
check test "$(gsettings get org.gnome.nautilus.preferences show-hidden-files)" = true
check test "$(gsettings get org.gtk.gtk4.Settings.FileChooser show-hidden)" = true

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

# --- Screensaver: tte (terminaltexteffects) port of Omarchy's terminal screensaver
check command -v tte fh-launch-screensaver fh-screensaver fh-toggle-screensaver fh-branding-screensaver
check bash -c 'tte --version'
check test -s /usr/share/fedora-hypr/logo.txt
check bash -c '! grep -qi omarchy /usr/share/fedora-hypr/logo.txt'
check test -f /etc/skel/.config/fedora-hypr/branding/screensaver.txt
check bash -c 'diff -q /usr/share/fedora-hypr/logo.txt /etc/skel/.config/fedora-hypr/branding/screensaver.txt'
check grep -q fh-launch-screensaver /etc/skel/.config/hypr/hypridle.conf
check grep -q 'org.fedorahypr.screensaver' /usr/share/fedora-hypr/default/hypr/apps/screensaver.conf
check grep -q 'apps/screensaver.conf' /usr/share/fedora-hypr/default/hypr/apps.conf
check test -f /usr/share/fedora-hypr/default/alacritty/screensaver.toml
check grep -q -- '--config-file /usr/share/fedora-hypr/default/alacritty/screensaver.toml' /usr/bin/fh-launch-screensaver
check grep -q 'pkill -f org.fedorahypr.screensaver' /usr/bin/fh-system-lock
check grep -q fh-toggle-screensaver /usr/bin/fh-menu
check grep -q fh-branding-screensaver /usr/bin/fh-menu
# tte can render the shipped logo without a tty (frame-rate 0 = no throttling, "print"
# reveals the whole canvas and exits) -- a real behavioural check, not just --version
check bash -c 'timeout 10 tte -i /usr/share/fedora-hypr/logo.txt --frame-rate 0 --no-eol print --final-gradient-stops ffffff </dev/null | grep -q .'

# --- Rust binaries (rust-build stage) + direnv + podman socket for waybar-docker
check command -v wsx
check command -v waybar-docker
check command -v direnv
# wsx creates its state dir under HOME on start; root's HOME in the build container is not writable that way
check bash -c 'HOME=$(mktemp -d) wsx --version'
# no socket in the build container: waybar-docker must still emit a JSON module payload and exit 0
check bash -c 'DOCKER_HOST=unix:///nonexistent timeout 10 waybar-docker | jq -e .class'
check grep -q DOCKER_HOST /etc/environment.d/50-fedora-hypr.conf
# environment.d expands ${XDG_RUNTIME_DIR} (it has no %t specifier); probe the real generator
check bash -c 'XDG_RUNTIME_DIR=/run/user/1000 /usr/lib/systemd/user-environment-generators/30-systemd-environment-d-generator | grep -qx "DOCKER_HOST=unix:///run/user/1000/podman/podman.sock"'
check test -f /usr/lib/systemd/user/podman.socket
# podman-docker prints an "Emulate Docker CLI" banner on every docker call unless this file exists
check test -f /etc/containers/nodocker
check grep -q 'exec-once = systemctl --user start podman.socket' /usr/share/fedora-hypr/default/hypr/autostart.conf

# --- Updates: fh-update-available (Waybar custom/update indicator, no host bootc deployment here)
check command -v fh-update-available skopeo
check grep -q '"custom/update"' /usr/share/fedora-hypr/default/waybar/config.jsonc
# no bootc host in the build/check container: bootc status is unavailable, so the script must never
# print a false positive here — exit 1, empty stdout
check bash -c '[ -z "$(fh-update-available)" ]'
check bash -c 'fh-update-available; test $? -eq 1'
# scoped sudoers rule: %wheel gets passwordless sudo for exactly this bootc status invocation
check visudo -cf /etc/sudoers.d/fh-update-available
check test "$(stat -c %a /etc/sudoers.d/fh-update-available)" = 440
check grep -qF '/usr/sbin/bootc status --format json' /etc/sudoers.d/fh-update-available

# --- GRUB drop-in (gfxterm + hidden menu)
check test -f /usr/lib/bootupd/grub2-static/configs.d/05_terminal.cfg
check grep -q "terminal_output gfxterm" /usr/lib/bootupd/grub2-static/configs.d/05_terminal.cfg

# --- Boot splash: Plymouth hypedora theme, selected, inside the initramfs, kargs
T=/usr/share/plymouth/themes/hypedora
for f in hypedora.plymouth hypedora.script logo.png progress_bar.png progress_box.png entry.png bullet.png lock.png; do
  check test -f "$T/$f"
done
check rpm -q plymouth-plugin-script
check test -f /usr/lib64/plymouth/script.so   # ModuleName=script needs the plugin
check grep -q '^ModuleName=script' "$T/hypedora.plymouth"
check grep -q "^ScriptFile=$T/hypedora.script" "$T/hypedora.plymouth"
check bash -c 'fc-list | grep -qi cantarell'   # Font= in hypedora.plymouth
check test "$(plymouth-set-default-theme)" = hypedora
check bash -c 'plymouth-set-default-theme --list | grep -qx hypedora'
check grep -q '^Theme=hypedora' /etc/plymouth/plymouthd.conf
# the logo is the Omarchy-style wordmark: same height, wider (8 letters); regenerate with tools/gen-plymouth-logo.py
check bash -c 'read -r w h < <(magick identify -format "%w %h" /usr/share/plymouth/themes/hypedora/logo.png); test "$h" = 188 && test "$w" -gt 800'
# ported theme carries only the attribution line
check bash -c 'test "$(grep -ril omarchy /usr/share/plymouth)" = /usr/share/plymouth/themes/hypedora/hypedora.script'
check bash -c 'test "$(grep -ic omarchy /usr/share/plymouth/themes/hypedora/hypedora.script)" = 1 && grep -q "^# Adapted from Omarchy (MIT)" /usr/share/plymouth/themes/hypedora/hypedora.script'
# theme is inside the shipped initramfs (rebuilt by build/20-services.sh)
check bash -c 'KVER=$(ls /usr/lib/modules | head -1); lsinitrd "/usr/lib/modules/$KVER/initramfs.img" | grep -q hypedora/logo.png'
check bash -c 'KVER=$(ls /usr/lib/modules | head -1); lsinitrd "/usr/lib/modules/$KVER/initramfs.img" | grep -q lib64/plymouth/script.so'
check bash -c 'KVER=$(ls /usr/lib/modules | head -1); lsinitrd "/usr/lib/modules/$KVER/initramfs.img" | sed -n "/^dracut modules:/,/^====/p" | grep -qx ostree'
check test ! -e /var/roothome   # dracut helper dir removed again (lint: nothing under /var)
# kernel args: bootc applies kargs.d at install and reconciles the diff on upgrade
check test -f /usr/lib/bootc/kargs.d/10-fedora-hypr.toml
check python3 -c 'import tomllib; k = tomllib.load(open("/usr/lib/bootc/kargs.d/10-fedora-hypr.toml", "rb"))["kargs"]; assert "quiet" in k and "splash" in k'

exit $fail
