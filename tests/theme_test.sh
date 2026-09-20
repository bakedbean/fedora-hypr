#!/usr/bin/env bash
# Exercises the theme engine in a throwaway HOME inside the image. No compositor needed:
# every fh-restart-* is guarded by pgrep and becomes a no-op.
set -euo pipefail
export HOME; HOME=$(mktemp -d)
export FH_PATH=/usr/share/fedora-hypr

fh-theme-set tokyo-night
cur="$HOME/.config/fedora-hypr/current"
test "$(cat "$cur/theme.name")" = tokyo-night
grep -q 'rgb(7aa2f7)' "$cur/theme/hyprland.conf"          # {{ accent_strip }}
grep -q 'background-color=#1a1b26' "$cur/theme/mako.ini"    # {{ background }}
grep -q '@define-color foreground #a9b1d6' "$cur/theme/waybar.css"
grep -q 'background = "#1a1b26"' "$cur/theme/alacritty.toml"
test -L "$cur/background" && test -f "$(readlink "$cur/background")"
test "$(fh-theme-current)" = tokyo-night
fh-theme-list | grep -qx tokyo-night
fh-theme-list | grep -qx rose-pine

# switching themes swaps atomically and cycles backgrounds within a theme
fh-theme-set gruvbox
test "$(fh-theme-current)" = gruvbox
first=$(readlink "$cur/background"); fh-theme-bg-next; second=$(readlink "$cur/background")
test "$first" != "$second" || test "$(ls "$cur/theme/backgrounds" | wc -l)" -le 1

# user overlay wins over built-in
mkdir -p "$HOME/.config/fedora-hypr/themes/tokyo-night"
echo 'accent = "#ff0000"' > "$HOME/.config/fedora-hypr/themes/tokyo-night/colors.toml"
fh-theme-set tokyo-night
grep -q 'rgb(ff0000)' "$cur/theme/hyprland.conf"

# unknown theme is an error
! fh-theme-set does-not-exist 2>/dev/null

echo "theme_test: OK"
