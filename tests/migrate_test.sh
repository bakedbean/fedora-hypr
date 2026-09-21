#!/usr/bin/env bash
# Host-side test for tools/migrate-home.sh (make test-migrate). Builds a fabricated
# Omarchy home, migrates it into a fake mounted disk with --dest, and asserts on the
# rewrites. Never touches the real HOME or a block device; needs no root (chown/setfattr
# are skipped when not root).
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
script=$here/../tools/migrate-home.sh
fail=0
check() { if "$@" >/dev/null 2>&1; then echo "PASS $*"; else echo "FAIL $*"; fail=1; fi; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
src=$tmp/src
dest=$tmp/disk
home=$dest/var/home/eben
mkdir -p "$src" "$home"

# --- fabricated source home ---------------------------------------------------
cat > "$src/.zshrc" <<EOF
# fake zshrc
export ZSH="$src/.oh-my-zsh"
if command -v fzf &> /dev/null; then
  if [[ -f /usr/share/fzf/completion.zsh ]]; then
    source /usr/share/fzf/completion.zsh
  fi
  if [[ -f /usr/share/fzf/key-bindings.zsh ]]; then
    source /usr/share/fzf/key-bindings.zsh
  fi
fi
alias ff='$src/bin/ff'
[ -s "$src/.bun/_bun" ] && source "$src/.bun/_bun"
# CCI configuration
export FAKE_API_KEY=not-a-real-key
export OTHER_TOKEN=also-fake
export PROD_READ_ONLY_DSN=postgres://fake
if [ -f '$src/Downloads/google-cloud-sdk/path.zsh.inc' ]; then . '$src/Downloads/google-cloud-sdk/path.zsh.inc'; fi
export PATH=\$HOME/.local/bin:\$PATH
EOF
echo 'export EDITOR=nvim' > "$src/.zprofile"
mkdir -p "$src/.ssh" "$src/.config/gh" "$src/.oh-my-zsh/custom" "$src/.config/tmux" "$src/.config/btop" \
  "$src/.config/lazygit" "$src/.config/git" "$src/.config/fastfetch" "$src/.config/radiobar" \
  "$src/dotfiles/astronvim" "$src/RadioBar/linux" "$src/RadioBar/build" "$src/RadioBar/tools/__pycache__" \
  "$src/.local/bin" "$src/.local/share/fonts" "$src/.local/share/applications/icons" \
  "$src/.config/waybar/scripts" "$src/.config/hypr" "$src/.config/fish" "$src/.cargo/bin" "$src/.config/omarchy"
chmod 700 "$src/.ssh"; echo fake-key > "$src/.ssh/id_ed25519"; chmod 600 "$src/.ssh/id_ed25519"
echo 'x' > "$src/.config/gh/hosts.yml"; echo 'x' > "$src/.oh-my-zsh/oh-my-zsh.sh"
echo 'x' > "$src/.config/starship.toml"; echo x > "$src/.config/tmux/tmux.conf"; echo x > "$src/.config/radiobar/stations.json"
printf 'color_theme = "current"\n' > "$src/.config/btop/btop.conf"
mkdir -p "$src/.config/btop/themes"; ln -s "$src/.config/omarchy/current/theme/btop.theme" "$src/.config/btop/themes/current.theme"
chmod 700 "$home"
echo 'x' > "$src/dotfiles/astronvim/init.lua"; ln -s "$src/dotfiles/astronvim" "$src/.config/nvim"
echo 'x' > "$src/RadioBar/linux/radiobar"; chmod +x "$src/RadioBar/linux/radiobar"
echo 'x' > "$src/RadioBar/build/junk"; echo 'x' > "$src/RadioBar/tools/__pycache__/junk.pyc"
ln -s "$src/RadioBar/linux/radiobar" "$src/.local/bin/radiobar"
echo 'x' > "$src/.local/share/fonts/f.ttf"
# an old-format user theme + the current-theme copy with one extra background + Wallpapers
th=$src/.config/omarchy/themes/my-theme
mkdir -p "$th/backgrounds" "$src/.config/omarchy/current/theme/backgrounds" "$src/Wallpapers"
printf '[colors.primary]\nbackground = "#191724"\nforeground = "#e0def4"\n' > "$th/alacritty.toml"
printf 'include=~/.local/share/omarchy/default/mako/core.ini\n' > "$th/mako.ini"
printf 'source = ~/.config/omarchy/current/theme/hyprland-extra.conf\n' > "$th/hyprland.conf"
printf 'jpg' > "$th/backgrounds/a.jpg"; printf 'lua' > "$th/neovim.lua"; printf 'md' > "$th/README.md"
echo my-theme > "$src/.config/omarchy/current/theme.name"
printf 'jpg' > "$src/.config/omarchy/current/theme/backgrounds/a.jpg"; printf 'png' > "$src/.config/omarchy/current/theme/backgrounds/extra.png"
printf 'png' > "$src/Wallpapers/w.png"
# stub of omarchy-theme-colors-from-alacritty: writes colors.toml into the theme dir it is given
fake_conv=$tmp/fake-colors; printf '#!/bin/bash\nprintf "[colors]\\nbackground = \\"#191724\\"\\n" > "$1/colors.toml"\n' > "$fake_conv"; chmod +x "$fake_conv"
echo 'x' > "$src/.config/fish/config.fish"; echo x > "$src/.cargo/bin/waybar-docker"; echo x > "$src/.config/omarchy/x"
echo 'x' > "$src/.local/share/applications/icons/Discord.png"
cat > "$src/.local/share/applications/Discord.desktop" <<EOF
[Desktop Entry]
Name=Discord
Exec=omarchy-launch-webapp https://discord.com/channels/@me
Icon=/home/eben/.local/share/applications/icons/Discord.png
EOF
printf '[Desktop Entry]\nName=Cliamp\nExec=cliamp\n' > "$src/.local/share/applications/Cliamp.desktop"
cat > "$src/.local/share/applications/claude-code-url-handler.desktop" <<'EOF'
[Desktop Entry]
Name=Claude Code URL Handler
Exec="/home/eben/.local/bin/claude" --handle-uri %u
Type=Application
NoDisplay=true
MimeType=x-scheme-handler/claude-code;
EOF
cat > "$src/.local/share/applications/userapp-Firefox-ABC123.desktop" <<'EOF'
[Desktop Entry]
Name=Firefox
TryExec=/opt/firefox-bin/firefox-bin
Exec=/opt/firefox-bin/firefox-bin %u
Icon=firefox
Type=Application
MimeType=x-scheme-handler/http;
EOF
cat > "$src/.config/waybar/config.jsonc" <<EOF
{
  "include": ["$src/.config/waybar/wsx.jsonc"],
  "modules-left": ["custom/omarchy", "hyprland/workspaces#main"],
  "modules-center": ["clock", "custom/update", "custom/voxtype", "custom/idle-indicator"],
  "modules-right": ["custom/wsx", "custom/docker"],
  "custom/omarchy": {
    "format": "<span font='omarchy'>\\ue900</span>",
    "on-click": "omarchy-menu",
    "tooltip-format": "Omarchy Menu\\n\\nSuper + Alt + Space"
  },
  "custom/update": {
    "format": "",
    "exec": "omarchy-update-available",
    "on-click": "omarchy-launch-floating-terminal-with-presentation omarchy-update",
    "interval": 21600
  },
  "custom/docker": {
    "exec": "~/.cargo/bin/waybar-docker",
    "return-type": "json"
  },
  "clock": {
    "format": "{:%H:%M,}",
    "tooltip": false, // same-line comment after a trailing comma
  },
  "custom/radio": {
    "exec": "RADIOBAR_SCROLL_WINDOW=25 radiobar status",
    "on-click": "radiobar click"
  },
  "cpu": {
    // trailing comma below is deliberate: waybar tolerates it, jq does not
    "on-click": "omarchy-launch-or-focus-tui btop",
    "on-click-right": "some-missing-binary",
  },
  "custom/voxtype": {
    "exec": "omarchy-voxtype-status",
    "return-type": "json",
    "format-icons": {
      "idle": "",
      "recording": "x"
    },
    "on-click": "omarchy-voxtype-model"
  },
  "custom/idle-indicator": {
    "on-click": "omarchy-toggle-idle",
    "exec": "\$OMARCHY_PATH/default/waybar/indicators/idle.sh",
    "return-type": "json"
  }
}
EOF
cat > "$src/.config/waybar/style.css" <<'EOF'
@import "../omarchy/current/theme/waybar.css";
#custom-omarchy { padding: 0; }
#custom-voxtype { padding: 0; }
/* a future `omarchy font set` must not jog the bar */
EOF
echo '{ "custom/wsx": { "exec": "wsx waybar status" } }' > "$src/.config/waybar/wsx.jsonc"
echo '#custom-wsx { padding: 0; }' > "$src/.config/waybar/wsx.css"
echo 'old' > "$src/.config/waybar/config.jsonc.bak"; echo old > "$src/.config/waybar/style.css.bak.123"
printf '#!/bin/sh\necho hi\n' > "$src/.config/waybar/scripts/get_weather.sh"; chmod +x "$src/.config/waybar/scripts/get_weather.sh"
cat > "$src/.config/hypr/bindings.conf" <<'EOF'
# Application bindings
$terminal = uwsm-app -- xdg-terminal-exec
bindd = SUPER, RETURN, Terminal, exec, $terminal --dir="$(omarchy-cmd-terminal-cwd)"
bindd = SUPER SHIFT, M, Music, exec, omarchy-launch-or-focus spotify
bindd = SUPER SHIFT ALT, M, Music TUI, exec, omarchy-launch-or-focus-tui cliamp
bindd = SUPER SHIFT, R, RadioBar play/pause, exec, radiobar toggle
bindd = SUPER SHIFT, G, Signal, exec, omarchy-launch-or-focus signal "uwsm-app -- signal-desktop"
bindd = SUPER SHIFT, O, Obsidian, exec, omarchy-launch-or-focus "^obsidian$" "uwsm-app -- obsidian"
bindd = SUPER SHIFT, W, Typora, exec, uwsm-app -- typora --enable-wayland-ime
bindd = SUPER SHIFT, SLASH, Passwords, exec, uwsm-app -- 1password
bindd = SUPER ALT, C, Claudette, exec, omarchy-launch-or-focus claudette-app
bindd = SUPER SHIFT, A, ChatGPT, exec, omarchy-launch-webapp "https://chatgpt.com"
bindd = SUPER SHIFT, C, Calendar, exec, omarchy-launch-webapp "https://app.hey.com/calendar/weeks/"
bindd = SUPER SHIFT, E, Email, exec, omarchy-launch-webapp "https://app.hey.com"

# Overwrite existing bindings, like putting Omarchy Menu on Super + Space
# unbind = SUPER, SPACE
# bindd = SUPER, SPACE, Omarchy menu, exec, omarchy-menu
EOF
for f in input monitors envs autostart; do echo "# $f" > "$src/.config/hypr/$f.conf"; done
printf "# Change the default Omarchy look'n'feel\ngeneral {\n  gaps_in = 5\n}\n" > "$src/.config/hypr/looknfeel.conf"
echo 'source = ~/.local/share/omarchy/default/hypr/autostart.conf' > "$src/.config/hypr/hyprland.conf"
echo 'old' > "$src/.config/hypr/bindings.conf.bak.1"

# --- run -----------------------------------------------------------------------
run() { env SUDO_USER=fakeuser HOME="$src" FH_COLORS_FROM_ALACRITTY="$fake_conv" bash "$script" --dest "$dest" "$@"; }
check run --dry-run
check bash -c "! test -e '$home/.zshrc'"      # dry-run writes nothing
out=$tmp/out.txt
run > "$out" 2>&1; rc=$?
check test "$rc" -eq 0
# ShellCheck: the host's if present, else the image's (ShellCheck is a build/test dependency of the image)
if command -v shellcheck >/dev/null 2>&1; then
  check shellcheck -S error "$script"
else
  check podman run --rm -v "$here/../tools:/tools:ro,z" localhost/fedora-hypr:44 shellcheck -S error /tools/migrate-home.sh
fi

# .zshrc split
check bash -c "! grep -q API_KEY '$home/.zshrc'"
check bash -c "! grep -q PROD_READ_ONLY_DSN '$home/.zshrc'"
check grep -qF '[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local' "$home/.zshrc"
check grep -q '^# CCI configuration' "$home/.zshrc.local"
check grep -q '^export FAKE_API_KEY=' "$home/.zshrc.local"
check grep -q '^export PROD_READ_ONLY_DSN=' "$home/.zshrc.local"
check test "$(stat -c %a "$home/.zshrc.local")" = 600
check test "$(stat -c %a "$home")" = 700                    # the home dir's own mode survives the staged rsync
check bash -c "! grep -qF '$src' '$home/.zshrc'"          # source home path rewritten to \$HOME
check grep -qF 'export ZSH="$HOME/.oh-my-zsh"' "$home/.zshrc"
check grep -qF '"$HOME/Downloads/google-cloud-sdk/path.zsh.inc"' "$home/.zshrc"   # single quotes would not expand
check grep -q '/usr/share/fzf/shell/key-bindings.zsh' "$home/.zshrc"
check bash -c "! grep -q 'source /usr/share/fzf/completion.zsh' '$home/.zshrc'"
check zsh -n "$home/.zshrc"
check grep -q 'export PATH=$HOME/.local/bin' "$home/.zshrc"                         # tail after the block survives

# plain copies
check test -f "$home/.zprofile"
check test "$(stat -c %a "$home/.ssh")" = 700
check test "$(stat -c %a "$home/.ssh/id_ed25519")" = 600
check test -f "$home/.config/gh/hosts.yml"
check test -f "$home/.oh-my-zsh/oh-my-zsh.sh"
check test -f "$home/.config/starship.toml"
check test -f "$home/.config/tmux/tmux.conf"
check grep -qx 'color_theme = "current"' "$home/.config/btop/btop.conf"
check test -L "$home/.config/btop/themes/current.theme"
check test "$(readlink "$home/.config/btop/themes/current.theme")" = ../../fedora-hypr/current/theme/btop.theme
check test -d "$home/.local/bin"
check grep -qx '  .local/bin' "$out"          # created parent dirs are listed (and chowned/labelled when root)
check grep -qx '  .local' "$out"
check grep -qx '  .config' "$out"
check test -f "$home/.config/radiobar/stations.json"
check test -f "$home/dotfiles/astronvim/init.lua"
check test -L "$home/.config/nvim"
check test -f "$home/RadioBar/linux/radiobar"
check bash -c "! test -e '$home/RadioBar/build'"
check bash -c "! test -e '$home/RadioBar/tools/__pycache__'"
check test -L "$home/.local/bin/radiobar"
check test "$(readlink "$home/.local/bin/radiobar")" = /home/eben/RadioBar/linux/radiobar
check test -f "$home/.local/share/fonts/f.ttf"
# themes + backgrounds + wallpapers
ft=$home/.config/fedora-hypr/themes/my-theme
check test -f "$ft/alacritty.toml"
check grep -qxF 'include=/usr/share/fedora-hypr/default/mako/core.ini' "$ft/mako.ini"
check grep -qxF 'source = ~/.config/fedora-hypr/current/theme/hyprland-extra.conf' "$ft/hyprland.conf"
check bash -c "! grep -rqi omarchy '$ft'"
check bash -c "! test -e '$ft/neovim.lua'"
check bash -c "! test -e '$ft/README.md'"
check test -f "$ft/backgrounds/a.jpg"
check test -f "$ft/colors.toml"                                   # written by the stubbed converter
check grep -q 'my-theme (colors.toml: generated)' "$out"
check test -f "$home/.config/fedora-hypr/backgrounds/my-theme/extra.png"
check bash -c "! test -e '$home/.config/fedora-hypr/backgrounds/my-theme/a.jpg'"   # already in the theme itself
check grep -q 'fh-theme-set my-theme' "$out"
check test -f "$home/Wallpapers/w.png"
check bash -c "! test -e '$home/.config/omarchy'"

# never copied
check bash -c "! test -e '$home/.config/fish'"
check bash -c "! test -e '$home/.cargo'"
check bash -c "! test -e '$home/.config/omarchy'"
check bash -c "! test -e '$home/.config/waybar/config.jsonc.bak'"
check bash -c "! test -e '$home/.config/waybar/style.css.bak.123'"
check bash -c "! test -e '$home/.config/hypr/bindings.conf.bak.1'"
check bash -c "! test -e '$home/.config/hypr/hyprland.conf'"     # skel's stays

# desktop entries: exactly the two allowlisted files, nothing else (no icons/, no webapps)
ap=$home/.local/share/applications
check test "$(ls "$ap" | sort | tr '\n' ' ')" = "claude-code-url-handler.desktop userapp-Firefox-ABC123.desktop "
check cmp -s "$src/.local/share/applications/claude-code-url-handler.desktop" "$ap/claude-code-url-handler.desktop"
check grep -qxF 'Exec="/home/eben/.local/bin/claude" --handle-uri %u' "$ap/claude-code-url-handler.desktop"
check grep -qxF 'Exec=firefox %u' "$ap/userapp-Firefox-ABC123.desktop"
check grep -qxF 'TryExec=firefox' "$ap/userapp-Firefox-ABC123.desktop"
check bash -c "! grep -q firefox-bin '$ap/userapp-Firefox-ABC123.desktop'"
check grep -qxF 'MimeType=x-scheme-handler/http;' "$ap/userapp-Firefox-ABC123.desktop"
check bash -c "! test -e '$ap/Discord.desktop'"
check bash -c "! test -e '$ap/Cliamp.desktop'"
check bash -c "! test -e '$ap/icons'"
check grep -q '^== desktop files: claude-code-url-handler.desktop userapp-Firefox-ABC123.desktop$' "$out"

# waybar
wb=$home/.config/waybar
check bash -c "sed 's|//.*||' '$wb/config.jsonc' | jq ."
check bash -c "! grep -qi voxtype '$wb/config.jsonc'"
check bash -c "! grep -qi omarchy '$wb/config.jsonc'"
check bash -c "! grep -q 'custom/update' '$wb/config.jsonc'"
check bash -c "sed 's|//.*||' '$wb/config.jsonc' | jq -e '.\"modules-center\" == [\"clock\", \"custom/idle-indicator\"]'"
check bash -c "sed 's|//.*||' '$wb/config.jsonc' | jq -e '.\"modules-left\"[0] == \"custom/menu\"'"
check bash -c "sed 's|//.*||' '$wb/config.jsonc' | jq -e '.\"custom/menu\".\"on-click\" == \"fh-menu\"'"
menu_glyph=$(sed 's|//.*||' "$here/../system/usr/share/fedora-hypr/default/waybar/config.jsonc" | jq -r '."custom/menu".format')
check test -n "$menu_glyph"
check bash -c "sed 's|//.*||' '$wb/config.jsonc' | jq -e --arg g '$menu_glyph' '.\"custom/menu\".format == \$g'"
check bash -c "sed 's|//.*||' '$wb/config.jsonc' | jq -e '.clock.format == \"{:%H:%M,}\"'"   # ",}" inside a string untouched
check bash -c "sed 's|//.*||' '$wb/config.jsonc' | jq -e '.clock.tooltip == false'"              # trailing comma + same-line // comment
check bash -c "sed 's|//.*||' '$wb/config.jsonc' | jq -e '.\"custom/docker\".exec == \"waybar-docker\"'"
check bash -c "sed 's|//.*||' '$wb/config.jsonc' | jq -e '.\"custom/idle-indicator\".exec == \"/usr/share/fedora-hypr/default/waybar/indicators/idle.sh\"'"
check bash -c "sed 's|//.*||' '$wb/config.jsonc' | jq -e '.cpu.\"on-click\" == \"fh-launch-or-focus-tui btop\"'"
check grep -q 'some-missing-binary' "$out"        # unknown on-click reported, but kept
check bash -c "! grep -q RADIOBAR_SCROLL_WINDOW '$out'"   # env-prefixed commands are resolved past the assignment
check bash -c "! grep -q 'config.jsonc: radiobar' '$out'"
check grep -q 'some-missing-binary' "$wb/config.jsonc"
check test -f "$wb/wsx.jsonc"
check test -f "$wb/wsx.css"
check test -x "$wb/scripts/get_weather.sh"
check grep -q '@import "../fedora-hypr/current/theme/waybar.css"' "$wb/style.css"
check grep -q '#custom-menu' "$wb/style.css"
check bash -c "! grep -qi omarchy '$wb/style.css'"

# hypr
hy=$home/.config/hypr
check bash -c "! grep -q 'omarchy-' '$hy/bindings.conf'"
check bash -c "! grep -qi omarchy '$hy/bindings.conf'"
check bash -c "! grep -qiE 'obsidian|typora|hey\.com|claudette|cliamp' '$hy/bindings.conf'"
check grep -q 'radiobar toggle' "$hy/bindings.conf"
check grep -qF 'fh-launch-or-focus signal "uwsm-app -- flatpak run org.signal.Signal"' "$hy/bindings.conf"
check grep -qF 'ChatGPT' "$hy/bindings.conf"     # neighbouring webapp binds survive the filter
check grep -qF 'uwsm-app -- flatpak run com.onepassword.OnePassword' "$hy/bindings.conf"
check grep -qF 'fh-launch-webapp "https://chatgpt.com"' "$hy/bindings.conf"
for f in input looknfeel monitors envs autostart; do check test -f "$hy/$f.conf"; done
check bash -c "! grep -qi omarchy '$hy/looknfeel.conf'"
check grep -q 'gaps_in = 5' "$hy/looknfeel.conf"

# idempotent: second run succeeds and leaves the same tree
before=$(cd "$home" && find . | sort | md5sum)
check run
check test "$before" = "$(cd "$home" && find . | sort | md5sum)"
check grep -q 'restorecon' "$out"

# missing target home aborts
check bash -c "! (SUDO_USER=fakeuser HOME=$src bash '$script' --dest '$tmp/nohome')"

# --- refusals: a .zshrc whose secrets block cannot be split must not be written at all ----------
declare -A ZRC=(
  [nostart]=$'# x\n## CCI configuration\nexport FAKE_API_KEY=k\nexport PROD_READ_ONLY_DSN=d'
  [noend]=$'# x\n# CCI configuration\nexport FAKE_API_KEY=k\nexport OTHER=1'
  [leaked]=$'# x\nexport LEAKED_TOKEN=k\n# CCI configuration\nexport A=1\nexport PROD_READ_ONLY_DSN=d'
  [nosplit-secret]=$'# x\nexport SOME_API_KEY=k'
)
refuse_case() {  # <name> [extra args]; asserts rc!=0 and target untouched
  local name=$1; shift
  local s=$tmp/src-$name d=$tmp/disk-$name
  mkdir -p "$s/.config/hypr" "$d/var/home/eben"
  printf '%s\n' "${ZRC[$name]}" > "$s/.zshrc"; echo x > "$s/.zprofile"
  local snap; snap=$(find "$d" | sort)
  if env SUDO_USER=fakeuser HOME="$s" bash "$script" --dest "$d" "$@" >/dev/null 2>&1; then return 1; fi
  [[ $snap == "$(find "$d" | sort)" ]]
}
check refuse_case nostart
check refuse_case noend
check refuse_case leaked
check refuse_case nosplit-secret --no-split
# a theme with an un-rewritable omarchy reference refuses and leaves the target untouched
bs=$tmp/src-badtheme; bd=$tmp/disk-badtheme; mkdir -p "$bs/.config/omarchy/themes/bad" "$bd/var/home/eben"
printf '# plain\n' > "$bs/.zshrc"; echo x > "$bs/.zprofile"
printf 'exec = ~/.local/share/omarchy/bin/omarchy-theme-bg-next\n' > "$bs/.config/omarchy/themes/bad/hyprland.conf"
snap=$(find "$bd" | sort | md5sum)
check bash -c "! env SUDO_USER=fakeuser HOME='$bs' bash '$script' --dest '$bd' --no-split"
check test "$snap" = "$(find "$bd" | sort | md5sum)"
# the converter being absent is a warning, not a failure
ms=$tmp/src-noconv; md=$tmp/disk-noconv; mkdir -p "$ms/.config/omarchy/themes/plain" "$md/var/home/eben"
printf '# plain\n' > "$ms/.zshrc"; printf 'x' > "$ms/.config/omarchy/themes/plain/alacritty.toml"
check env SUDO_USER=fakeuser HOME="$ms" FH_COLORS_FROM_ALACRITTY=/nonexistent bash "$script" --dest "$md" --no-split
check bash -c "! test -e '$md/var/home/eben/.config/fedora-hypr/themes/plain/colors.toml'"

# --no-split with a clean .zshrc (no markers, no secrets) is accepted
ns=$tmp/src-ok; nd=$tmp/disk-ok; mkdir -p "$ns" "$nd/var/home/eben"; printf '# plain\nalias l=ls\n' > "$ns/.zshrc"
check env SUDO_USER=fakeuser HOME="$ns" bash "$script" --dest "$nd" --no-split
check grep -qx 'alias l=ls' "$nd/var/home/eben/.zshrc"

exit $fail
