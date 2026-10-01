-- App launchers — edit freely.
-- Plain SUPER + <letter> is reserved for window management (see
-- /usr/share/fedora-hypr/default/hypr/bindings/tiling-v2.lua); apps live on
-- SUPER SHIFT so they never collide with it.
--
-- fh.bind(keys, description, command-or-dispatcher[, options]): a string runs
-- as a shell command. To change a default binding, unbind it first:
--   hl.unbind("SUPER + SPACE")
--   fh.bind("SUPER + SPACE", "fedora-hypr menu", "fh-menu")

local terminal = "uwsm-app -- alacritty"
local browser = "fh-launch-browser"
local file_manager = "uwsm-app -- nautilus --new-window"

fh.bind("SUPER + RETURN", "Terminal", terminal .. ' --working-directory="$(fh-cmd-terminal-cwd)"')
fh.bind("SUPER + B", "Firefox", "uwsm-app -- firefox")

fh.bind("SUPER + SHIFT + RETURN", "Browser", browser)
fh.bind("SUPER + SHIFT + B", "Browser", browser)
fh.bind("SUPER + SHIFT + F", "File manager", file_manager)
fh.bind("SUPER + SHIFT + M", "Music", 'fh-launch-or-focus spotify "uwsm-app -- flatpak run com.spotify.Client"')
fh.bind("SUPER + SHIFT + N", "Editor", "fh-launch-editor")
fh.bind("SUPER + SHIFT + T", "Activity", "fh-launch-tui btop")
fh.bind("SUPER + SHIFT + D", "Docker", "fh-launch-tui lazydocker")
fh.bind("SUPER + SHIFT + G", "Signal", 'fh-launch-or-focus signal "uwsm-app -- flatpak run org.signal.Signal"')
fh.bind("SUPER + SHIFT + SLASH", "Passwords", "uwsm-app -- flatpak run com.onepassword.OnePassword")
