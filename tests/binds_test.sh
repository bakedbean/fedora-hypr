#!/usr/bin/env bash
# Runs inside the built image. Evaluates the skel hyprland.lua (image defaults +
# skel overrides) with tests/hypr_binds.lua and fails if the same modifier+key
# combination is bound more than once — Hyprland dispatches EVERY bind matching
# a combo, so a duplicate means two actions fire — or if an app launcher in the
# skel bindings.lua sits on plain SUPER + letter (reserved for window management
# in default/hypr/bindings/tiling-v2.lua).
set -uo pipefail

# Intentional duplicates: tiling-v2.lua binds cycle_next AND bring_to_top on the
# same combo so the newly focused window is also raised. "MODS|KEY" form.
allow=(
  "ALT|TAB"
  "ALT SHIFT|TAB"
)
# The skel's own SUPER + letter binds, kept from before the SUPER SHIFT rule.
skel_super_letter_allow=("SUPER|B")

h=$(mktemp -d); cp -r /etc/skel/. "$h"
binds=$(HOME=$h FH_PATH=/usr/share/fedora-hypr lua "$(dirname "$0")/hypr_binds.lua") || { echo "FAIL evaluating hyprland.lua"; exit 1; }
combos=$(cut -f1,2 <<<"$binds" | tr '\t' '|')

fail=0
total=$(grep -c . <<<"$combos")
if ((total < 100)); then echo "FAIL only $total binds found"; fail=1; fi

while IFS= read -r combo; do
  [[ -z $combo ]] && continue
  allowed=0
  for a in "${allow[@]}"; do [[ $combo == "$a" ]] && allowed=1; done
  if ((allowed)); then echo "PASS allowed duplicate bind: $combo"; else echo "FAIL duplicate bind: $combo"; fail=1; fi
done < <(sort <<<"$combos" | uniq -d)

# Every bind outside the lid switch carries a description (SUPER + K lists them).
while IFS=$'\t' read -r mods key desc _; do
  [[ -z $desc && $key != SWITCH:* ]] && { echo "FAIL bind without description: $mods $key"; fail=1; }
done <<<"$binds"

# Skel app launchers: no new plain SUPER + letter binds.
skel_only=$(HOME=$h lua -e '
  hl = setmetatable({ dsp = setmetatable({}, { __index = function() return function() return {} end end }),
    bind = function(k) print(k) end }, { __index = function() return function() end end })
  fh = { bind = function(k) print(k) end }
  dofile(os.getenv("HOME") .. "/.config/hypr/bindings.lua")')
while IFS= read -r keys; do
  norm=$(tr -d ' ' <<<"$keys" | tr '+' ' ' | tr '[:lower:]' '[:upper:]')
  if [[ $norm =~ ^SUPER\ [A-Z]$ ]]; then
    combo="SUPER|${norm#SUPER }"
    ok=0; for a in "${skel_super_letter_allow[@]}"; do [[ $combo == "$a" ]] && ok=1; done
    ((ok)) || { echo "FAIL skel binds an app on plain SUPER + letter: $keys"; fail=1; }
  fi
done <<<"$skel_only"

echo "binds_test: $total binds scanned"
exit $fail
