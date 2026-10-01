#!/usr/bin/env bash
# Runs inside the built image, as root (check.sh). Behavioural checks for the Lua
# Hyprland config: the skel config loads under Hyprland's own verifier with every
# theme and every toggle, the rollback guard and the per-module pcall work, and
# fh-migrate-hypr-lua turns an existing .conf account (tests/fixtures/legacy-hypr)
# into a config that loads, keeping the .conf files as a backup.
#
# Hyprland --verify-config refuses to run as root, so everything that loads the
# config runs as an unprivileged user.
set -uo pipefail
fail=0
pass() { echo "PASS $*"; }
flunk() { echo "FAIL $*"; fail=1; }
check() { if "$@" >/dev/null 2>&1; then pass "$*"; else flunk "$*"; fi; }

FH=/usr/share/fedora-hypr
FIXTURE=/tests/fixtures/legacy-hypr/home
U=hyprtest
id "$U" &>/dev/null || useradd -m "$U" >/dev/null 2>&1

new_home() {
  local h
  h=$(mktemp -d /tmp/hyprhome.XXXXXX)
  [[ ${1:-} == skel ]] && cp -r /etc/skel/. "$h"
  [[ ${1:-} == fixture ]] && cp -r "$FIXTURE/." "$h"
  chown -R "$U:$U" "$h"
  echo "$h"
}

# as_user HOME CMD [ENV=VAL...]: run CMD with bash as the test user and a clean env.
as_user() {
  local home=$1 cmd=$2
  shift 2
  local rt
  rt=$(mktemp -d)
  chown "$U" "$rt"
  chmod 700 "$rt"
  runuser -u "$U" -- env -i PATH=/usr/bin:/usr/sbin HOME="$home" FH_PATH=$FH XDG_RUNTIME_DIR="$rt" "$@" bash -c "$cmd"
}

# Loads the config the way a session would; FH_VERIFY_STRICT makes a broken user
# module fail the check instead of being skipped with a notification.
verify() {
  as_user "$1" 'Hyprland --verify-config -c "$HOME/.config/hypr/hyprland.lua" 2>&1' FH_VERIFY_STRICT=1 "${@:2}"
}

verify_ok() {
  local out
  out=$(verify "$@") && grep -q "config ok" <<<"$out"
}

# --- fresh account (skel) --------------------------------------------------------
h=$(new_home skel)
if verify_ok "$h"; then pass "skel config loads before any theme is rendered"; else flunk "skel config without a theme"; verify "$h"; fi

for theme in "$FH"/themes/*/; do
  theme=$(basename "$theme")
  as_user "$h" "fh-theme-set $theme" FH_THEME_SKIP_BACKGROUND=1 >/dev/null 2>&1
  if [[ -f $h/.config/fedora-hypr/current/theme/hyprland.lua ]] && verify_ok "$h"; then
    pass "skel config loads with theme $theme"
  else
    flunk "skel config with theme $theme"; verify "$h"
  fi
done
check grep -q 'hl.env("GUM_CONFIRM_PROMPT_FOREGROUND", "#' "$h/.config/fedora-hypr/current/theme/gum-env.lua"

# every toggle on at once, including the name-as-data ones
t=$h/.local/state/fedora-hypr/toggles/hypr
cp "$FH"/default/hypr/toggles/*.lua "$t/"
echo "some touchpad \"with quotes\"" >"$t/touchpad-disabled.name"
echo "eDP-1" >"$t/internal-monitor-disable.name"
echo "DP-1 eDP-1" >"$t/internal-monitor-mirror.name"
chown -R "$U:$U" "$t"
if verify_ok "$h"; then pass "skel config loads with every toggle on"; else flunk "every toggle on"; verify "$h"; fi
check as_user "$h" 'fh-hyprland-toggle-enabled window-no-gaps && fh-hyprland-toggle-enabled touchpad-disabled && fh-hyprland-toggle-disabled nonexistent-toggle'

# a user module that throws is skipped (defaults still load) unless strict
h=$(new_home skel)
echo 'error("broken on purpose")' >>"$h/.config/hypr/bindings.lua"
if verify "$h" | grep -q "config ok"; then
  flunk "a throwing user module passes strict verification"
else
  pass "a throwing user module fails strict verification"
fi
# Hyprland reports an error raised inside require() even under pcall, so the
# "rest still loads" half is checked with the stub harness: every default bind
# and the later user modules still register.
echo 'fh.bind("SUPER + CTRL + ALT + F12", "Loaded after the broken module", "true")' >>"$h/.config/hypr/autostart.lua"
if binds=$(HOME=$h FH_PATH=$FH lua /tests/hypr_binds.lua 2>&1) && grep -q "Loaded after the broken module" <<<"$binds"; then
  pass "a throwing user module is skipped, the rest loads"
else
  flunk "a throwing user module took the config down"; echo "$binds" | tail -3
fi

# rollback guard: an image without Lua defaults makes hyprland.lua step aside
h=$(new_home skel)
as_user "$h" 'Hyprland --verify-config -c "$HOME/.config/hypr/hyprland.lua" >/dev/null 2>&1' FH_PATH=/nonexistent
check test -f "$h/.config/hypr/hyprland.lua.rolled-back"
check test ! -e "$h/.config/hypr/hyprland.lua"

# --- migration of an existing .conf account ------------------------------------------
h=$(new_home fixture)
# The account had a rendered theme from before the Lua templates existed.
as_user "$h" 'fh-theme-set tokyo-night' FH_THEME_SKIP_BACKGROUND=1 >/dev/null 2>&1
rm -f "$h"/.config/fedora-hypr/current/theme/*.lua
git_conf=$(cd "$h/.config/hypr" && sha256sum ./*.conf)

out=$(as_user "$h" 'fh-migrate-hypr-lua 2>&1')
rc=$?
hy=$h/.config/hypr
report=$h/.local/state/fedora-hypr/hypr-lua-migration.report
if ((rc == 0)) && [[ -f $hy/hyprland.lua ]]; then pass "fh-migrate-hypr-lua migrates the fixture account"; else flunk "migration rc=$rc"; echo "$out"; fi
if verify_ok "$h"; then pass "migrated config loads"; else flunk "migrated config does not load"; verify "$h"; fi
check test "$(cd "$hy" && sha256sum ./*.conf)" = "$git_conf"           # .conf files untouched
check bash -c "ls -d '$hy'/legacy-conf-*/ | grep -q . && test -f '$hy'/legacy-conf-*/hyprland.conf && test -f '$hy'/legacy-conf-*/extra.conf"
check test -f "$h/.config/fedora-hypr/current/theme/hyprland.lua"      # theme re-rendered for Lua
check test -f "$h/.config/fedora-hypr/current/theme/gum-env.lua"
check test -f "$hy/.luarc.json"
# every module, in hyprland.conf's order: statements written between two sources
# land between them (later lines still override earlier ones)
order=$(sed -n 's/^user("hypr\.\(.*\)")$/\1/p' "$hy/hyprland.lua" | tr '\n' ' ')
check test "$order" = "monitors input bindings envs hyprland-inline looknfeel autostart hyprland-inline-2 "
check grep -qF 'hl.env("FIXTURE_EARLY", "1")' "$hy/hyprland-inline.lua"
check grep -q 'require("hypr.extra")' "$hy/bindings.lua"                 # nested source -> require
check grep -qF 'hl.window_rule({ match = { class = "^(org.example.app)$" }, float = true, size = "800 600" })' "$hy/extra.lua"
check grep -qF 'hl.workspace_rule({ workspace = "5", layout = "scrolling" })' "$hy/extra.lua"
check grep -qF 'hl.window_rule({ match = { fullscreen = true }, border_color = "0xffeb6f92" })' "$hy/extra.lua"
check grep -qF 'hl.window_rule({ match = { class = "^(pavucontrol)$", title = "^(Volume, Control)$" }, float = true })' "$hy/extra.lua"
check grep -qF 'hl.bind("SUPER + SHIFT + R", hl.dsp.exec_cmd("radiobar toggle"), { description = "RadioBar play/pause" })' "$hy/bindings.lua"
check grep -qF 'hl.dsp.exec_cmd("uwsm-app -- xdg-terminal-exec --dir=\"$(fh-cmd-terminal-cwd)\" tmux new")' "$hy/bindings.lua"
check grep -qF 'https://example.com/#frag' "$hy/bindings.lua"               # ## is a literal #
check grep -qF 'hl.unbind("SUPER + SPACE")' "$hy/bindings.lua"
check grep -qF 'hl.bind("SUPER + ALT + mouse:272", hl.dsp.window.resize(), { mouse = true })' "$hy/bindings.lua"
check grep -qF 'hl.dsp.window.resize({ x = -10, y = 0, relative = true }), { repeating = true }' "$hy/bindings.lua"
check grep -qF 'hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })' "$hy/monitors.lua"
check grep -qF 'transform = 1' "$hy/monitors.lua"
check grep -qF 'hl.on("hyprland.start", function() hl.exec_cmd("uwsm-app -- radiobar") end)' "$hy/autostart.lua"
check grep -qF '{ colors = { "rgba(ff0000ee)", "rgba(00ff00ee)" }, angle = 90 }' "$hy/looknfeel.lua"
check grep -qF 'hl.curve("myCurve"' "$hy/looknfeel.lua"
check grep -qF 'hl.device({ name = "some-mouse", sensitivity = -0.5 })' "$hy/input.lua"
check grep -qF 'hl.env("FIXTURE_INLINE", "1")' "$hy/hyprland-inline-2.lua"
# a submap's binds stay out of the global keymap (all FIXME) and binds after `submap = reset` are back
check bash -c "! grep -E '^hl\.bind\(\"(H|escape)\"' '$hy/bindings.lua'"
check grep -qF "inside submap 'resize'" "$report"
check grep -qF 'hl.bind("SUPER + CTRL + J", hl.dsp.exec_cmd("after-submap"), { description = "After the submap" })' "$hy/bindings.lua"
# what can't be converted (or Hyprland rejects) is a FIXME comment, listed in the report
for pattern in "pass, class" "someunknowndispatcher" "exec = echo every-reload" "no_such_option"; do
  check grep -qF "$pattern" "$report"
done
check bash -c "! grep -v '^--' '$hy'/*.lua | grep -q someunknowndispatcher"
# toggles: Lua twins and names-as-data; the .conf originals moved to the backup (flags.conf stays)
t=$h/.local/state/fedora-hypr/toggles/hypr
check test -f "$t/window-no-gaps.lua"
check test "$(cat "$t/touchpad-disabled.name")" = pixa3854:00-093a:0274-touchpad
check test "$(cat "$t/internal-monitor-disable.name")" = eDP-1
check test -f "$t/flags.conf"
check test ! -e "$t/window-no-gaps.conf"
check bash -c "test -f '$hy'/legacy-conf-*/toggles/touchpad-disabled.conf"
# a second run is a no-op
before=$(ls -d "$hy"/legacy-conf-* | wc -l)
check as_user "$h" fh-migrate-hypr-lua
check test "$(ls -d "$hy"/legacy-conf-* | wc -l)" = "$before"

# the real account's shape: old skel plus nothing else migrates with nothing to review
h=$(new_home)
mkdir -p "$h/.config/hypr" "$h/.local/state/fedora-hypr/toggles/hypr"
for f in autostart bindings envs hypridle hyprland hyprlock input looknfeel monitors; do
  sed '/(fixture)/d; /^# --- fixture/,$d' "$FIXTURE/.config/hypr/$f.conf" >"$h/.config/hypr/$f.conf"
done
chown -R "$U:$U" "$h"
if as_user "$h" 'fh-migrate-hypr-lua >/dev/null 2>&1' && verify_ok "$h" &&
  ! grep -q '^review ' "$h/.local/state/fedora-hypr/hypr-lua-migration.report"; then
  pass "an unmodified old skel account migrates with nothing to review"
else
  flunk "old skel account migration"; cat "$h/.local/state/fedora-hypr/hypr-lua-migration.report"
fi

# generated module names never collide with a user's own file: a sourced
# hyprland-inline.conf keeps its name, the inline chunks around it take the next free ones
h=$(new_home)
mkdir -p "$h/.config/hypr"
printf '%s\n' 'env = INLINE_A,1' 'source = ~/.config/hypr/hyprland-inline.conf' 'env = INLINE_B,1' >"$h/.config/hypr/hyprland.conf"
echo 'env = FROM_USER_FILE,1' >"$h/.config/hypr/hyprland-inline.conf"
chown -R "$U:$U" "$h"
check as_user "$h" fh-migrate-hypr-lua
check grep -qF 'hl.env("FROM_USER_FILE", "1")' "$h/.config/hypr/hyprland-inline.lua"
check grep -qF 'hl.env("INLINE_A", "1")' "$h/.config/hypr/hyprland-inline-2.lua"
check grep -qF 'hl.env("INLINE_B", "1")' "$h/.config/hypr/hyprland-inline-3.lua"
check test "$(sed -n 's/^user("hypr\.\(.*\)")$/\1/p' "$h/.config/hypr/hyprland.lua" | tr '\n' ' ')" = "hyprland-inline-2 hyprland-inline hyprland-inline-3 "
if verify_ok "$h"; then pass "collision-free inline modules load"; else flunk "collision case"; verify "$h"; fi

# When the conversion fails, the old hyprland.conf can't stay in charge (it sources
# the image's .conf defaults, which are gone): the skel Lua config is installed,
# and every file that was there before is byte-for-byte unchanged -- including a
# hand-written theme hyprland.lua with a line the verifier rejects.
broken=$(mktemp -d)
cp -r "$FH/." "$broken/"
chmod 755 "$broken"
echo 'hl.this_does_not_exist()' >>"$broken/default/hypr/envs.lua"
h=$(new_home fixture)
mkdir -p "$h/.config/fedora-hypr/current/theme"
printf '%s\n' 'hl.config({ general = { no_such_theme_option = 1 } })' >"$h/.config/fedora-hypr/current/theme/hyprland.lua"
chown -R "$U:$U" "$h"
snapshot() { (cd "$h" && find . -type f -exec sha256sum {} + | LC_ALL=C sort); }
before=$(snapshot)
check as_user "$h" 'fh-migrate-hypr-lua >/dev/null 2>&1' FH_PATH="$broken"
after=$(snapshot)
changed=$(LC_ALL=C comm -23 <(echo "$before") <(echo "$after"))
if [[ -z $changed ]]; then pass "a failed conversion leaves every existing file unchanged"; else flunk "a failed conversion changed:"; echo "$changed"; fi
added=$(comm -13 <(cut -c67- <<<"$before" | LC_ALL=C sort) <(cut -c67- <<<"$after" | LC_ALL=C sort) | tr '\n' ' ')
check test "$added" = "./.config/hypr/.luarc.json ./.config/hypr/autostart.lua ./.config/hypr/bindings.lua ./.config/hypr/envs.lua ./.config/hypr/hyprland.lua ./.config/hypr/input.lua ./.config/hypr/looknfeel.lua ./.config/hypr/monitors.lua ./.local/state/fedora-hypr/hypr-lua-migration.report ./.local/state/fedora-hypr/toggles/hypr/flags.lua "
check cmp /etc/skel/.config/hypr/hyprland.lua "$h/.config/hypr/hyprland.lua"
check grep -q 'could not be converted' "$h/.local/state/fedora-hypr/hypr-lua-migration.report"
check bash -c "! ls -d '$h'/.config/hypr/legacy-conf-*"

# --- convert (no verification: fh-theme-set and migrate-home use it) ------------------
# Old-syntax window rules either translate to the same meaning or stay a FIXME as a whole.
h=$(new_home)
cat >"$h/rules.conf" <<'CONF'
windowrulev2 = opacity 0.8, float, class:foo
windowrulev2 = bordercolor rgba(255,0,0,1) rgba(0,255,0,1), noblur, class:foo
windowrulev2 = size 800 600, center, class:foo
windowrulev2 = center 1, class:foo
windowrulev2 = float, class:^(a, b)$, title:negative:^(x)$
windowrulev2 = noborder, norounding, floating:1, pinned:0, initialClass:^(z)$
windowrulev2 = float, noblur, bogus 3, class:foo
windowrulev2 = float, onworkspace:1
windowrule = float, title:^(has match: inside)$
windowrule = float, ^(kitty)$
windowrule = match:class x, border_color 0xff112233
CONF
conv=$(/usr/libexec/fedora-hypr/hypr-conf2lua convert "$h/rules.conf")
for line in \
  'hl.window_rule({ match = { class = "foo" }, opacity = 0.8, float = true })' \
  'hl.window_rule({ match = { class = "foo" }, border_color = "rgba(255,0,0,1) rgba(0,255,0,1)", no_blur = true })' \
  'hl.window_rule({ match = { class = "foo" }, size = "800 600", center = true })  -- conf2lua: centred in the work area, was the whole monitor' \
  'hl.window_rule({ match = { class = "foo" }, center = true })' \
  'hl.window_rule({ match = { class = "^(a, b)$", title = "negative:^(x)$" }, float = true })' \
  'hl.window_rule({ match = { float = true, pin = false, initial_class = "^(z)$" }, border_size = 0, rounding = 0 })' \
  "-- FIXME(conf2lua): unknown windowrulev2 effect 'bogus'" \
  "-- FIXME(conf2lua): unknown windowrulev2 prop 'onworkspace'" \
  'hl.window_rule({ match = { title = "^(has match: inside)$" }, float = true })' \
  '-- FIXME(conf2lua): rule needs effects and at least one prop:value' \
  'hl.window_rule({ match = { class = "x" }, border_color = "0xff112233" })'; do
  if grep -qF -- "$line" <<<"$conv"; then pass "convert: $line"; else flunk "convert: $line"; fi
done
mkdir -p "$h/.config/hypr"
echo "$conv" >"$h/.config/hypr/hyprland.lua"
chown -R "$U:$U" "$h"
if verify_ok "$h"; then pass "converted old-syntax rules load"; else flunk "converted old-syntax rules"; verify "$h"; fi

# --- plumbing -----------------------------------------------------------------------
check test -x /usr/libexec/fedora-hypr/hypr-conf2lua
check test -f /usr/lib/systemd/user/fh-migrate-hypr-lua.service
check test "$(readlink -f /usr/lib/systemd/user/graphical-session-pre.target.wants/fh-migrate-hypr-lua.service)" = /usr/lib/systemd/user/fh-migrate-hypr-lua.service
check test "$(systemctl --global is-enabled fh-migrate-hypr-lua.service)" = static
check bash -c 'rt=$(mktemp -d); chown '"$U"' "$rt"; runuser -u '"$U"' -- env XDG_RUNTIME_DIR="$rt" systemd-analyze --user verify /usr/lib/systemd/user/fh-migrate-hypr-lua.service'
check grep -qx 'Before=graphical-session-pre.target' /usr/lib/systemd/user/fh-migrate-hypr-lua.service
check grep -qx 'ExecStart=/usr/bin/fh-migrate-hypr-lua' /usr/lib/systemd/user/fh-migrate-hypr-lua.service
# uwsm starts the compositor only after graphical-session-pre.target
check grep -q '^After=.*graphical-session-pre.target' /usr/lib/systemd/user/wayland-wm@.service
# no .conf Hyprland config is left in the image or skel (hypridle/hyprlock belong to other programs)
check bash -c '! find /usr/share/fedora-hypr/default/hypr -name "*.conf" | grep -q .'
check bash -c '! ls /etc/skel/.config/hypr/*.conf | grep -vE "/(hypridle|hyprlock)\.conf$"'
# ported Lua carries the attribution comment on line 2 when it carries one at all
attribution='-- Adapted from third-party MIT-licensed code; see LICENSE-THIRD-PARTY in the source repo'
for f in $(grep -rl 'MIT-licensed' /usr/share/fedora-hypr/default/hypr); do
  if [[ $(sed -n 2p "$f") == "$attribution" ]]; then pass "attribution on line 2 of $f"; else flunk "attribution line of $f"; fi
done

echo "hypr_lua_test: $([[ $fail == 0 ]] && echo OK || echo FAILED)"
exit $fail
