#!/usr/bin/env bash
# Migrate the author's Omarchy home config onto a fedora-hypr disk.
#
# Run on the Omarchy machine, as the user, with the target drive attached:
#   sudo tools/migrate-home.sh /dev/sda3 [--dry-run]
#   tools/migrate-home.sh --dest /mnt/target [--dry-run]     # already-mounted disk (or a test tree)
# Options:
#   --dest DIR    mount root of an already-mounted target disk (instead of a block device)
#   --src DIR     source home (default: $SUDO_USER's home, else $HOME)
#   --user NAME   target user whose home under var/home/ is written (default: eben)
#   --no-split    do not look for the "# CCI configuration" .. PROD_READ_ONLY_DSN block in .zshrc
#                 (only for a .zshrc without it; the secret-pattern guard still refuses obvious secrets)
#   --dry-run     mount read-only, rsync -n, write nothing
#
# Copies a curated set of dotfiles from the invoking user's home ($SUDO_USER) into
# <disk>/var/home/<user> (bootc keeps it under ostree/deploy/default/var when the raw
# filesystem is mounted), rewriting Omarchy-isms to their fedora-hypr equivalents on the
# way. Secrets in ~/.zshrc are split out into ~/.zshrc.local (mode 600). Idempotent.
#
# Files written from a non-SELinux host carry no label, so as root the copied paths get
# security.selinux xattrs set explicitly; run `restorecon -Rv ~` on the Fedora side too.
# Nothing here is ever printed except paths and summaries — never file contents.
#
# Known limitations (documented, not fixed):
#   - rewrites are literal seds on the copied files; the jq validation strips "//..." which would also
#     eat a URL inside a JSON string (none in the author's config today)
#   - the image-binary allowlist in in_image() is hand-maintained; an unlisted binary drops a .desktop
#     file (always reported, never silent)
#   - the target uid/gid is fixed at 1000:1000 (the first user fh-first-boot-user creates)
#   - files copied by an earlier run that a later run would drop (changed drop rules) are not removed
#   - source-home literals (/home/<user>) are replaced textually; a longer path sharing the prefix would match
#   - waybar module-block removal is indentation-bound (2-space top-level blocks) and list-entry removal handles
#     single-line arrays only; a config in another shape fails closed via the jq validation
#   - on re-run, a real directory already at <target>/.config/nvim is left in place (the symlink is not forced)
#   - a CRLF .zshrc is unsupported (markers are matched on LF lines)
#   - labels are only user_home_t / ssh_home_t; run `restorecon -Rv ~` on Fedora for its finer-grained types
set -euo pipefail

usage() { sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

DEV= DEST= SRC= DRY=0 NOSPLIT=0 TARGET_USER=eben
while [[ $# -gt 0 ]]; do
  case $1 in
    --dest) DEST=$2; shift 2 ;;
    --src) SRC=$2; shift 2 ;;
    --user) TARGET_USER=$2; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --no-split) NOSPLIT=1; shift ;;
    -h|--help) usage ;;
    -*) echo "unknown option: $1" >&2; usage 1 ;;
    *) [[ -z $DEV ]] || { echo "unexpected argument: $1" >&2; usage 1; }; DEV=$1; shift ;;
  esac
done
[[ -n $DEV || -n $DEST ]] || { echo "need a block device or --dest DIR" >&2; usage 1; }
[[ -z $DEV || -z $DEST ]] || { echo "give either a device or --dest, not both" >&2; exit 1; }

# --- source home: the invoking user's, not root's ------------------------------------
SRC_USER=${SUDO_USER:-$(id -un)}
if [[ -z $SRC ]]; then
  SRC=$(getent passwd "$SRC_USER" 2>/dev/null | cut -d: -f6 || true)
  [[ -n $SRC && -d $SRC ]] || SRC=$HOME
fi
SRC=${SRC%/}
[[ -d $SRC ]] || { echo "source home $SRC does not exist" >&2; exit 1; }
# Absolute paths inside dotfiles are rewritten from these to $HOME
SRC_HOME_LITERALS=("$SRC" "/home/$SRC_USER")

IS_ROOT=0; [[ $EUID -eq 0 ]] && IS_ROOT=1
UID_GID=1000:1000   # fh-first-boot-user creates the first user as uid 1000
need() { command -v "$1" >/dev/null 2>&1 || { echo "missing tool: $1" >&2; exit 1; }; }
need rsync; need jq; need awk; need perl
(( IS_ROOT )) && need setfattr

# --- mount -------------------------------------------------------------------------
MNT= MOUNTED=0
cleanup() {
  if (( MOUNTED )); then
    if umount "$MNT"; then echo "unmounted $MNT"; MOUNTED=0
    else echo "WARNING: could not unmount $MNT; unmount it yourself before unplugging" >&2; fi
  fi
  [[ -n ${WORK:-} ]] && rm -rf "$WORK"
  if [[ -n ${TMPMNT:-} && -d $TMPMNT && $MOUNTED -eq 0 ]]; then rmdir "$TMPMNT" 2>/dev/null || true; fi
  return 0
}
trap cleanup EXIT
if [[ -n $DEV ]]; then
  (( IS_ROOT )) || { echo "mounting $DEV needs root (sudo)" >&2; exit 1; }
  [[ -b $DEV ]] || { echo "$DEV is not a block device" >&2; exit 1; }
  TMPMNT=$(mktemp -d /tmp/migrate-home.XXXXXX); MNT=$TMPMNT
  if (( DRY )); then mount -o ro "$DEV" "$MNT"; else mount "$DEV" "$MNT"; fi; MOUNTED=1
  echo "mounted $DEV on $MNT"
else
  MNT=${DEST%/}
  [[ -d $MNT ]] || { echo "--dest $MNT is not a directory" >&2; exit 1; }
fi

TARGET=
for cand in "$MNT/var/home/$TARGET_USER" "$MNT/ostree/deploy/default/var/home/$TARGET_USER"; do
  [[ -d $cand ]] && { TARGET=$cand; break; }
done
[[ -n $TARGET ]] || {
  echo "target home not found: neither $MNT/var/home/$TARGET_USER nor" >&2
  echo "  $MNT/ostree/deploy/default/var/home/$TARGET_USER exists (boot the disk once first)" >&2
  exit 1
}
echo "source: $SRC"
echo "target: $TARGET"
(( DRY )) && echo "DRY RUN: nothing will be written"

# directories under the target before we write anything: whatever exists afterwards and is not
# in this list was created by this run and needs ownership + label too (I-2)
PRE_DIRS=$(find "$TARGET" -mindepth 1 -maxdepth 4 -type d 2>/dev/null | sort || true)
TARGET_MODE=$(stat -c %a "$TARGET")

WORK=$(mktemp -d)   # staging tree for everything that is rewritten before copying
STAGE=$WORK/stage
mkdir -p "$STAGE"
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# bookkeeping for the summary
TOUCHED=()     # paths (relative to home) written on the target; chown + label targets
SKIPPED=()     # source paths that did not exist
DROPPED=()     # .desktop files not copied, with reason
REWRITES=()    # human-readable rewrites applied
UNKNOWN_CMDS=() # on-click/exec targets we could not vouch for (kept)
CREATED_DIRS=() # parent dirs this run created under the target (chown + label, non-recursive)

RSYNC=(rsync -a --no-owner --no-group --mkpath)
(( DRY )) && RSYNC+=(--dry-run)

# copy <src-rel-path> [rsync excludes...]: plain rsync from SRC into TARGET, creating parents
copy() {
  local rel=$1; shift
  local from=$SRC/$rel to=$TARGET/$rel
  if [[ ! -e $from && ! -L $from ]]; then SKIPPED+=("$rel"); return 0; fi
  if [[ -d $from && ! -L $from ]]; then from=$from/ to=$to/; fi
  "${RSYNC[@]}" "$@" -- "$from" "$to"
  TOUCHED+=("$rel")
  echo "copied  $rel"
}

# --- helpers for the rewritten copies ----------------------------------------------
# rewrite_home_paths FILE: literal source-home paths -> $HOME (and re-quote '...' so it expands)
rewrite_home_paths() {
  local f=$1 lit
  for lit in "${SRC_HOME_LITERALS[@]}"; do
    sed -i "s|$lit|\$HOME|g" "$f"
  done
  sed -i "s|'\(\$HOME[^']*\)'|\"\1\"|g" "$f"
}

# Can the first word of a command be expected on the fedora-hypr image?
# fh-* scripts are looked up in this repo; other names against an allowlist of shipped binaries.
IMAGE_BINS=" bash sh env systemctl notify-send pkill pgrep hyprctl xdg-terminal-exec uwsm-app uwsm flatpak
 alacritty btop imv mpv wiremix radiobar wsx waybar-docker chromium-browser firefox nautilus nvim lazygit
 lazydocker fastfetch dust pamixer playerctl brightnessctl walker hyprshot satty hyprlock hypridle hyprpicker
 wl-copy wl-paste grim slurp gum zsh tmux bat eza fd rg zoxide jq tldr magick impala bluetui swayosd-client
 gnome-calculator evince fcitx5 fcitx5-configtool \$TERMINAL activate "
in_image() {
  local cmd=$1 name
  # skip leading VAR=value assignments (e.g. RADIOBAR_SCROLL_WINDOW=25 radiobar status)
  while [[ $cmd =~ ^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+ ]]; do cmd=${cmd#"${BASH_REMATCH[0]}"}; done
  cmd=${cmd%% *}
  cmd=${cmd#\"}; cmd=${cmd%\"}
  name=${cmd##*/}
  case $cmd in
    fh-*) [[ -x $REPO/system/usr/bin/$cmd ]]; return ;;
    \$HOME/*|\~/*) return 0 ;;      # lives in the home we are migrating
    /usr/share/fedora-hypr/*) return 0 ;;
    /*) [[ -x $cmd ]] && [[ " $IMAGE_BINS " == *" $name "* ]]; return ;;
  esac
  [[ " $IMAGE_BINS " == *" $name "* ]]
}

# --- 1. .zshrc split ----------------------------------------------------------------
if [[ -f $SRC/.zshrc ]]; then
  z=$STAGE/.zshrc; zl=$STAGE/.zshrc.local
  awk -v local="$zl" -v nosplit="$NOSPLIT" '
    # secrets block: from "# CCI configuration" through the PROD_READ_ONLY_DSN export
    !nosplit && /^# CCI configuration/ { inblock=1; found=1; print "[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local"; }
    inblock { print > local; if ($0 ~ /^export PROD_READ_ONLY_DSN/) { inblock=0; closed=1 }; next }
    # fzf block: Omarchy sources /usr/share/fzf/*.zsh; Fedora ships /usr/share/fzf/shell/*.zsh
    /^if command -v fzf/ {
      print "if command -v fzf &> /dev/null; then"
      print "  if [[ -d /usr/share/fzf/shell ]]; then"
      print "    for f in /usr/share/fzf/shell/completion.zsh /usr/share/fzf/shell/key-bindings.zsh; do"
      print "      [[ -f $f ]] && source \"$f\""
      print "    done"
      print "  else"
      print "    for f in /usr/share/fzf/completion.zsh /usr/share/fzf/key-bindings.zsh; do"
      print "      [[ -f $f ]] && source \"$f\""
      print "    done"
      print "  fi"
      print "fi"
      infzf=1; next
    }
    infzf { if ($0 ~ /^fi$/) infzf=0; next }
    { print }
    # exit 2: start marker never seen (unless --no-split); exit 3: end marker never seen
    END { if (!nosplit && !found) exit 2; if (inblock && !closed) exit 3 }
  ' "$SRC/.zshrc" > "$z" || {
    case $? in
      2) echo "refusing: no '# CCI configuration' start marker in .zshrc (secrets would be copied in the clear)." >&2
         echo "  Pass --no-split only if this .zshrc really has no secrets block." >&2 ;;
      3) echo "refusing: '# CCI configuration' block in .zshrc never ends with 'export PROD_READ_ONLY_DSN'" >&2 ;;
      *) echo "refusing: could not rewrite .zshrc" >&2 ;;
    esac
    exit 1
  }
  rewrite_home_paths "$z"
  if [[ -s $zl ]]; then
    chmod 600 "$zl"
    REWRITES+=(".zshrc: secrets block (# CCI configuration .. PROD_READ_ONLY_DSN) moved to .zshrc.local")
  else
    rm -f "$zl"
  fi
  # independent guard: nothing that looks like a secret assignment may remain in the world-readable copy
  if grep -Eq '(API_KEY|_TOKEN|SECRET|PASSWORD|_PASS|DSN)=' "$z"; then
    echo "refusing: rewritten .zshrc still contains a secret-looking assignment (API_KEY/_TOKEN/SECRET/PASSWORD/_PASS/DSN)" >&2
    exit 1
  fi
  if grep -q 'command -v fzf' "$SRC/.zshrc"; then
    REWRITES+=(".zshrc: fzf block sources /usr/share/fzf/shell/*.zsh (Fedora) with fallback")
  fi
  REWRITES+=(".zshrc: $SRC -> \$HOME")
  # the source .zshrc still has the secrets: a moved-out key must never remain in the copy
  if [[ -s $zl ]] && grep -qxFf <(grep -E '^export [A-Z0-9_]+=' "$zl") "$z"; then
    echo "refusing: a line from the secrets block is still in the rewritten .zshrc" >&2; exit 1
  fi
  TOUCHED+=(.zshrc); [[ -s $zl ]] && TOUCHED+=(.zshrc.local)
else
  SKIPPED+=(.zshrc)
fi

# --- 2. desktop entries --------------------------------------------------------------
apps=.local/share/applications
if [[ -d $SRC/$apps ]]; then
  mkdir -p "$STAGE/$apps"
  [[ -d $SRC/$apps/icons ]] && cp -r "$SRC/$apps/icons" "$STAGE/$apps/" && TOUCHED+=("$apps/icons")
  shopt -s nullglob
  for f in "$SRC/$apps"/*.desktop; do
    name=${f##*/}
    exe=$(sed -n 's/^Exec=//p' "$f" | head -n1)
    exe=${exe//omarchy-/fh-}
    if [[ -n $exe ]] && ! in_image "$exe"; then
      DROPPED+=("$name (Exec: ${exe%% *})")
      continue
    fi
    sed 's/omarchy-/fh-/g' "$f" > "$STAGE/$apps/$name"   # Icon=/home/<user>/... stays: /home resolves on Fedora
    TOUCHED+=("$apps/$name")
  done
  shopt -u nullglob
  REWRITES+=("$apps/*.desktop: omarchy- -> fh-; entries whose Exec is not in the image dropped")
fi

# --- 3. waybar -----------------------------------------------------------------------
wb=.config/waybar
if [[ -d $SRC/$wb ]]; then
  mkdir -p "$STAGE/$wb"
  for f in config.jsonc style.css wsx.jsonc wsx.css; do
    [[ -f $SRC/$wb/$f ]] || { SKIPPED+=("$wb/$f"); continue; }
    cp "$SRC/$wb/$f" "$STAGE/$wb/$f"; TOUCHED+=("$wb/$f")
  done
  if [[ -d $SRC/$wb/scripts ]]; then
    rsync -a --exclude='*.bak*' "$SRC/$wb/scripts/" "$STAGE/$wb/scripts/"; TOUCHED+=("$wb/scripts")
  fi
  cfg=$STAGE/$wb/config.jsonc
  if [[ -f $cfg ]]; then
    # drop a top-level "custom/<name>": { ... } block (2-space indent, as waybar configs are written)
    drop_module() {
      local mod=$1
      awk -v mod="$mod" '
        $0 ~ "^  \"" mod "\": \\{" { skip=1; next }
        skip && /^  \},?$/ { skip=0; next }
        !skip { print }
      ' "$cfg" > "$cfg.tmp" && mv "$cfg.tmp" "$cfg"
      sed -i -e "s|\"$mod\", ||g" -e "s|, \"$mod\"||g" -e "s|\"$mod\"||g" "$cfg"
      REWRITES+=("$wb/config.jsonc: removed module $mod")
    }
    drop_module custom/voxtype
    if ! in_image fh-update-available; then drop_module custom/update; fi
    # the menu button's glyph comes from the image's default config (the omarchy icon font is not shipped)
    menu_glyph=$(sed 's|//.*||' "$REPO/system/usr/share/fedora-hypr/default/waybar/config.jsonc" | jq -r '."custom/menu".format')
    [[ -n $menu_glyph && $menu_glyph != null ]] || { echo "refusing: no custom/menu format in the image default waybar config" >&2; exit 1; }
    sed -i \
      -e 's|omarchy-|fh-|g' \
      -e 's|\$OMARCHY_PATH/default/waybar/indicators/|/usr/share/fedora-hypr/default/waybar/indicators/|g' \
      -e 's|~/\.cargo/bin/waybar-docker|waybar-docker|g' \
      -e 's|"custom/omarchy"|"custom/menu"|g' \
      -e "s|<span font='omarchy'>[^<]*</span>|$menu_glyph|g" \
      -e 's|Omarchy Menu|fedora-hypr Menu|g' \
      "$cfg"
    rewrite_home_paths "$cfg"
    # waybar tolerates a trailing comma before a } / ] on a following line, jq does not; normalise so the
    # result validates. Newline-anchored on purpose: ",}" inside a string on one line is left alone;
    # a same-line "// comment" after the comma is allowed.
    perl -0pi -e 's/,([ \t]*(?:\/\/[^\n]*)?\n(?:\s*\/\/[^\n]*\n)*\s*[\]}])/$1/g' "$cfg"
    REWRITES+=("$wb/config.jsonc: omarchy- -> fh-; \$OMARCHY_PATH indicators -> /usr/share/fedora-hypr; ~/.cargo/bin/waybar-docker -> waybar-docker; custom/omarchy -> custom/menu")
    if ! sed 's|//.*||' "$cfg" | jq . >/dev/null 2>&1; then
      echo "refusing: rewritten $wb/config.jsonc does not parse (sed 's|//.*||' | jq .)" >&2; exit 1
    fi
    if grep -qi omarchy "$cfg"; then
      echo "WARNING: $wb/config.jsonc still mentions omarchy; review by hand" >&2
    fi
    # on-click/exec targets we cannot vouch for: report, keep
    while IFS= read -r cmd; do
      [[ -n $cmd ]] || continue
      in_image "$cmd" || UNKNOWN_CMDS+=("$wb/config.jsonc: ${cmd%% *}")
    done < <(sed 's|//.*||' "$cfg" | jq -r '.. | objects | to_entries[] | select(.key | test("^(on-click|on-scroll|exec)")) | .value | strings')
  fi
  css=$STAGE/$wb/style.css
  if [[ -f $css ]]; then
    sed -i \
      -e 's|omarchy-|fh-|g' \
      -e 's|\.\./omarchy/|../fedora-hypr/|g' \
      -e 's|#custom-omarchy|#custom-menu|g' \
      -e 's|omarchy|fedora-hypr|g' \
      "$css"
    REWRITES+=("$wb/style.css: theme @import -> ../fedora-hypr/current/theme; #custom-omarchy -> #custom-menu")
  fi
fi

# --- 4. hypr overrides ----------------------------------------------------------------
hy=.config/hypr
if [[ -d $SRC/$hy ]]; then
  mkdir -p "$STAGE/$hy"
  for f in bindings input looknfeel monitors envs autostart; do
    [[ -f $SRC/$hy/$f.conf ]] || { SKIPPED+=("$hy/$f.conf"); continue; }
    grep -v -e cliamp -e claudette -e '[Oo]marchy [Mm]enu' "$SRC/$hy/$f.conf" \
      | sed \
          -e 's|omarchy-|fh-|g' \
          -e 's|uwsm-app -- signal-desktop|uwsm-app -- flatpak run org.signal.Signal|g' \
          -e 's|uwsm-app -- obsidian|uwsm-app -- flatpak run md.obsidian.Obsidian|g' \
          -e 's|uwsm-app -- typora|uwsm-app -- flatpak run io.typora.Typora|g' \
          -e 's|uwsm-app -- 1password|uwsm-app -- flatpak run com.onepassword.OnePassword|g' \
          -e '/^[[:space:]]*#/ s|[Oo]marchy|fedora-hypr|g' \
      > "$STAGE/$hy/$f.conf" || true
    rewrite_home_paths "$STAGE/$hy/$f.conf"
    TOUCHED+=("$hy/$f.conf")
    if grep -qi omarchy "$STAGE/$hy/$f.conf"; then
      echo "WARNING: $hy/$f.conf still mentions omarchy; review by hand" >&2
    fi
  done
  REWRITES+=("$hy/*.conf: omarchy- -> fh-; cliamp/claudette/'omarchy menu' lines dropped; signal/obsidian/typora/1password -> flatpak run")
fi

# --- 5. plain copies (after every rewrite has succeeded: a refusal above must leave the target untouched)
copy .zprofile
copy .gitconfig
copy .ssh
copy .config/gh
copy .oh-my-zsh
for p in .config/starship.toml .config/tmux .config/lazygit .config/git \
         .config/fastfetch .config/radiobar .local/share/fonts dotfiles; do
  copy "$p"
done
# btop: btop.conf as-is (color_theme = "current"); themes/current.theme becomes a relative symlink to the
# image's rendered theme (Omarchy's points into ~/.config/omarchy). Written via the stage below.
if [[ -d $SRC/.config/btop ]]; then
  copy .config/btop --exclude=/themes/current.theme
  mkdir -p "$STAGE/.config/btop/themes"
  ln -sfn ../../fedora-hypr/current/theme/btop.theme "$STAGE/.config/btop/themes/current.theme"
  TOUCHED+=(.config/btop/themes/current.theme)
  REWRITES+=(".config/btop/themes/current.theme -> ../../fedora-hypr/current/theme/btop.theme")
fi
copy RadioBar --exclude=/build --exclude=__pycache__
# ~/.config/nvim is a symlink into ~/dotfiles: copied as a symlink (rsync -a); make sure it resolves
if [[ -L $SRC/.config/nvim ]]; then
  copy .config/nvim
  link=$(readlink "$SRC/.config/nvim"); resolved=$link
  for lit in "${SRC_HOME_LITERALS[@]}"; do resolved=${resolved/#"$lit"/$TARGET}; done
  if (( ! DRY )) && [[ ! -e $resolved ]]; then
    echo "WARNING: .config/nvim -> $link does not resolve on the target ($resolved missing)" >&2
  fi
elif [[ -d $SRC/.config/nvim ]]; then
  copy .config/nvim
fi

# ~/.local/bin/radiobar: recreate as an absolute symlink. /home -> var/home on Fedora, so the
# same /home/<user> path resolves there.
if [[ -e $SRC/RadioBar/linux/radiobar ]]; then
  if (( ! DRY )); then
    mkdir -p "$TARGET/.local/bin"
    ln -sfn "/home/$TARGET_USER/RadioBar/linux/radiobar" "$TARGET/.local/bin/radiobar"
  fi
  TOUCHED+=(.local/bin/radiobar)
  echo "linked  .local/bin/radiobar -> /home/$TARGET_USER/RadioBar/linux/radiobar"
fi

# --- 6. write the staged tree ---------------------------------------------------------
# rsync of "stage/" -> "target/" would also apply the stage root's mode/mtime to the home dir itself:
# mirror the home's attributes onto the stage root first, and restore the mode afterwards regardless
chmod "$TARGET_MODE" "$STAGE"; touch -r "$TARGET" "$STAGE"
"${RSYNC[@]}" -- "$STAGE/" "$TARGET/"
(( DRY )) || chmod "$TARGET_MODE" "$TARGET"
echo "staged  $(cd "$STAGE" && find . -type f -o -type l | wc -l) rewritten files -> $TARGET"

# parent directories created by this run (I-2): not inside any copied path, so they need their own chown/label
if (( ! DRY )); then
  while IFS= read -r d; do
    [[ -n $d ]] || continue
    rel=${d#"$TARGET"/}
    inside=0
    for t in "${TOUCHED[@]}"; do [[ $rel == "$t" || $rel == "$t"/* ]] && { inside=1; break; }; done
    (( inside )) || CREATED_DIRS+=("$rel")
  done < <(comm -13 <(printf '%s\n' "$PRE_DIRS") <(find "$TARGET" -mindepth 1 -maxdepth 4 -type d | sort))
fi

# --- 7. ownership + SELinux labels ---------------------------------------------------
label_for() { if [[ $1 == .ssh* ]]; then echo unconfined_u:object_r:ssh_home_t:s0; else echo unconfined_u:object_r:user_home_t:s0; fi; }
LABEL_FAILED=0
if (( IS_ROOT && ! DRY )); then
  for rel in "${TOUCHED[@]}"; do
    p=$TARGET/$rel
    [[ -e $p || -L $p ]] || continue
    chown -h -R "$UID_GID" "$p"
    find "$p" -exec setfattr -h -n security.selinux -v "$(label_for "$rel")" {} + \
      || { echo "WARNING: setfattr failed under $p (restorecon on the Fedora side will fix it)" >&2; LABEL_FAILED=1; }
  done
  for rel in "${CREATED_DIRS[@]}"; do
    p=$TARGET/$rel
    chown -h "$UID_GID" "$p"
    setfattr -h -n security.selinux -v "$(label_for "$rel")" "$p" \
      || { echo "WARNING: setfattr failed on $p (restorecon on the Fedora side will fix it)" >&2; LABEL_FAILED=1; }
  done
  echo "chowned $UID_GID and labelled ${#TOUCHED[@]} paths + ${#CREATED_DIRS[@]} created parent dirs"
elif (( ! DRY )); then
  echo "not root: skipped chown/setfattr (run restorecon on the Fedora side)"
fi
(( DRY )) || [[ ! -f $TARGET/.zshrc.local ]] || chmod 600 "$TARGET/.zshrc.local"

# --- summary --------------------------------------------------------------------------
echo
echo "== copied (${#TOUCHED[@]})"; printf '  %s\n' "${TOUCHED[@]}"
if (( ${#CREATED_DIRS[@]} )); then echo "== parent dirs created (${#CREATED_DIRS[@]})"; printf '  %s\n' "${CREATED_DIRS[@]}"; fi
if (( ${#SKIPPED[@]} )); then echo "== not present in source, skipped"; printf '  %s\n' "${SKIPPED[@]}"; fi
if (( ${#DROPPED[@]} )); then echo "== dropped .desktop files (binary not in the image)"; printf '  %s\n' "${DROPPED[@]}"; fi
if (( ${#UNKNOWN_CMDS[@]} )); then echo "== commands not known to be in the image (kept, check them)"; printf '  %s\n' "${UNKNOWN_CMDS[@]}"; fi
echo "== rewrites"; printf '  %s\n' "${REWRITES[@]}"
cat <<EOF
== next steps
  1. boot the drive and log in as $TARGET_USER
  2. sudo restorecon -Rv ~        (belt and braces for the SELinux labels set here$( (( LABEL_FAILED )) && echo "; REQUIRED: some labels failed"))
  3. open nvim once to let AstroNvim install its plugins
  4. fh-update if the image changed since the drive was installed
EOF
