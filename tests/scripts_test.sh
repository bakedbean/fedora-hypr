#!/usr/bin/env bash
# Runs inside the built image. Every check prints PASS/FAIL; exits 1 on any FAIL.
set -uo pipefail
fail=0
# 1. every fh-* referenced by config OR by another fh-* script exists and is executable
# (grepping /usr/bin/fh-* itself closes the transitive call graph: a ported
# script calling a helper that was never ported would otherwise pass silently)
#
# fh-default is excluded: it's the Walker theme id set in Task 6's
# ~/.config/walker/config.toml (theme = "fh-default"), not a command — it
# just happens to match the fh-<name> pattern this grep is scanning for.
for s in $(grep -rho 'fh-[a-z0-9-]*' /usr/share/fedora-hypr/default /etc/skel /usr/bin/fh-* | sort -u); do
  [[ $s == fh-default ]] && continue
  if [[ -x /usr/bin/$s ]]; then echo "PASS exists $s"; else echo "FAIL missing $s"; fail=1; fi
done
# 2. every script parses and passes shellcheck (warnings allowed, errors not)
for s in /usr/bin/fh-*; do
  bash -n "$s" && shellcheck -S error "$s" && echo "PASS lint $(basename "$s")" || { echo "FAIL lint $s"; fail=1; }
done
# 3. no omarchy leftovers outside attribution comments
if grep -il 'omarchy' /usr/bin/fh-* | xargs -r grep -Li 'Adapted from Omarchy' | grep -q .; then
  echo "FAIL omarchy references remain"; fail=1
elif grep -hi 'omarchy' /usr/bin/fh-* | grep -vi 'Adapted from Omarchy' | grep -q .; then
  echo "FAIL omarchy references remain (non-attribution lines)"; fail=1
else echo "PASS no omarchy leftovers"; fi
# 4. behaviour that runs headless
export HOME; HOME=$(mktemp -d)
fh-toggle-enabled waybar-off && { echo "FAIL toggle default should be off"; fail=1; } || echo "PASS toggle default off"
fh-toggle-waybar >/dev/null 2>&1; fh-toggle-enabled waybar-off && echo "PASS toggle on" || { echo "FAIL toggle on"; fail=1; }
fh-cmd-present bash && echo "PASS cmd-present" || { echo "FAIL cmd-present"; fail=1; }
fh-cmd-missing definitely-not-a-cmd && echo "PASS cmd-missing" || { echo "FAIL cmd-missing"; fail=1; }
# 5. fix-round-1 additions: Hyprland toggle configs shipped, chromium-browser.desktop
# exists (fh-launch-webapp's fallback target), xdg-user-dirs is installed, and every
# non-fh binary the ported scripts shell out to is actually present in the image.
test -d /usr/share/fedora-hypr/default/hypr/toggles && echo "PASS toggles dir exists" || { echo "FAIL toggles dir missing"; fail=1; }
test -f /usr/share/applications/chromium-browser.desktop && echo "PASS chromium-browser.desktop exists" || { echo "FAIL chromium-browser.desktop missing"; fail=1; }
command -v xdg-user-dirs-update >/dev/null && echo "PASS xdg-user-dirs-update present" || { echo "FAIL xdg-user-dirs-update missing"; fail=1; }
for b in hyprshot satty gpu-screen-recorder slurp grim wl-copy hyprpicker notify-send \
         mpv ffmpeg ffprobe v4l2-ctl tesseract magick xdg-terminal-exec uwsm-app \
         swayosd-client swayosd-server impala bluetui wiremix gum socat xkbcli upower \
         bootc flatpak elephant walker; do
  command -v "$b" >/dev/null && echo "PASS command -v $b" || { echo "FAIL missing command $b"; fail=1; }
done
exit $fail
