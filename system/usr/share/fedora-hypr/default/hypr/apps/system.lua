-- Floating windows, media windows and other system-wide window rules.
-- Adapted from third-party MIT-licensed code; see LICENSE-THIRD-PARTY in the source repo

fh.window({ tag = "floating-window" }, { float = true, center = true, size = { 875, 600 } })

fh.window(
  "(org.fedorahypr.bluetui|org.fedorahypr.impala|org.fedorahypr.wiremix|org.fedorahypr.btop|org.fedorahypr.terminal|org.fedorahypr.bash|org.codeberg.dnkl.foot|org.gnome.NautilusPreviewer|org.gnome.Evince|com.gabm.satty|About|TUI.float|imv|mpv)",
  { tag = "+floating-window" }
)
fh.window({
  class = "(xdg-desktop-portal-gtk|sublime_text|DesktopEditors|org.gnome.Nautilus)",
  title = "^(Open.*Files?|Open [F|f]older.*|Save.*Files?|Save.*As|Save|All Files|.*wants to [open|save].*|[C|c]hoose.*)",
}, { tag = "+floating-window" })
fh.window("org.gnome.Calculator", { float = true })

-- No transparency on media windows.
local media = "^(zoom|vlc|mpv|org.kde.kdenlive|com.obsproject.Studio|com.github.PintaProject.Pinta|imv|org.gnome.NautilusPreviewer)$"
fh.window(media, { tag = "-default-opacity" })
fh.window(media, { opacity = "1 1" })

-- Popped window rounding.
fh.window({ tag = "pop" }, { rounding = 8 })

-- Prevent idle while open.
fh.window({ tag = "noidle" }, { idle_inhibit = "always" })
