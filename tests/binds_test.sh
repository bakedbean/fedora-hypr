#!/usr/bin/env bash
# Runs inside the built image. Fails if the same modifier+key combination is bound
# more than once across the image defaults and the skel bindings.conf — Hyprland
# dispatches EVERY bind matching a combo, so a duplicate means two actions fire.
set -uo pipefail

# Intentional duplicates: tiling-v2.conf binds cyclenext AND bringactivetotop on the
# same combo so the newly focused window is also raised. Normalised "MODS|KEY" form.
allow=(
  "ALT|TAB"
  "ALT SHIFT|TAB"
)

files=(/usr/share/fedora-hypr/default/hypr/bindings/*.conf /etc/skel/.config/hypr/bindings.conf)

normalise() {
  # stdin: "MODS, KEY" per line -> "SORTED UPPER MODS|UPPER KEY"
  while IFS='|' read -r mods key; do
    mods=$(tr ' ' '\n' <<<"${mods^^}" | grep -v '^$' | sort | tr '\n' ' ')
    printf '%s|%s\n' "${mods% }" "${key^^}"
  done
}

combos=$(
  cat "${files[@]}" |
    sed -nE 's/^[[:space:]]*bind[a-z]*[[:space:]]*=[[:space:]]*([^,]*),[[:space:]]*([^,]*),.*/\1|\2/p' |
    sed -E 's/[[:space:]]+\|/|/; s/\|[[:space:]]+/|/; s/[[:space:]]+$//' |
    normalise
)

dups=$(sort <<<"$combos" | uniq -d)
fail=0
while IFS= read -r combo; do
  [[ -z $combo ]] && continue
  allowed=0
  for a in "${allow[@]}"; do [[ $combo == "$a" ]] && allowed=1; done
  if ((allowed)); then
    echo "PASS allowed duplicate bind: $combo"
  else
    echo "FAIL duplicate bind: $combo"; fail=1
  fi
done <<<"$dups"

total=$(wc -l <<<"$combos")
echo "binds_test: $total binds scanned"
exit $fail
