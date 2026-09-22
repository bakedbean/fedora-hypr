export FH_PATH=/usr/share/fedora-hypr

# Set defaults before Fedora's nano-default-editor.sh; preserve explicit user choices.
export EDITOR="${EDITOR:-nvim}"
export VISUAL="${VISUAL:-$EDITOR}"
