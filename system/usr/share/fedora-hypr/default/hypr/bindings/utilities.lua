-- Menus, toggles, captures, notifications and other utility bindings.
-- Adapted from third-party MIT-licensed code; see LICENSE-THIRD-PARTY in the source repo

-- Menus.
fh.bind("SUPER + SPACE", "Launch apps", "fh-launch-walker")
fh.bind("SUPER + CTRL + E", "Emoji picker", "fh-launch-walker -m symbols")
fh.bind("SUPER + CTRL + C", "Capture menu", "fh-menu capture")
fh.bind("SUPER + CTRL + O", "Toggle menu", "fh-menu toggle")
fh.bind("SUPER + ALT + SPACE", "fedora-hypr menu", "fh-menu")
fh.bind("SUPER + SHIFT + code:201", "fedora-hypr menu", "fh-menu")
fh.bind("SUPER + ESCAPE", "System menu", "fh-menu system")
fh.bind("XF86PowerOff", "Power menu", "fh-menu system", { locked = true })
fh.bind("SUPER + K", "Show key bindings", "fh-menu-keybindings")
fh.bind("XF86Calculator", "Calculator", "gnome-calculator")

-- Aesthetics.
fh.bind("SUPER + SHIFT + SPACE", "Toggle top bar", "fh-toggle-waybar")
fh.bind("SUPER + CTRL + SPACE", "Theme background menu", "fh-menu background")
fh.bind("SUPER + SHIFT + CTRL + SPACE", "Theme menu", "fh-menu theme")
fh.bind("SUPER + BACKSPACE", "Toggle window transparency", "fh-hyprland-window-transparency-toggle")
fh.bind("SUPER + SHIFT + BACKSPACE", "Toggle window gaps", "fh-hyprland-window-gaps-toggle")
fh.bind("SUPER + CTRL + BACKSPACE", "Toggle single-window square aspect", "fh-hyprland-window-single-square-aspect-toggle")

-- Notifications. xkbcommon names the comma keysym "comma"; the upper-case
-- "COMMA" does not match in Lua binds.
fh.bind("SUPER + comma", "Dismiss last notification", "makoctl dismiss")
fh.bind("SUPER + SHIFT + comma", "Dismiss all notifications", "makoctl dismiss --all")
fh.bind("SUPER + CTRL + comma", "Toggle silencing notifications", "fh-toggle-notification-silencing")
fh.bind("SUPER + ALT + comma", "Invoke last notification", "makoctl invoke")
fh.bind("SUPER + SHIFT + ALT + comma", "Restore last notification", "makoctl restore")

-- Toggles.
fh.bind("SUPER + CTRL + I", "Toggle locking on idle", "fh-toggle-idle")
fh.bind("SUPER + CTRL + N", "Toggle nightlight", "fh-toggle-nightlight")
fh.bind("SUPER + CTRL + Delete", "Toggle laptop display", "fh-hyprland-monitor-internal toggle")
fh.bind("SUPER + CTRL + ALT + Delete", "Toggle laptop display mirroring", "fh-hyprland-monitor-internal-mirror toggle")
fh.bind("switch:on:Lid Switch", nil, "fh-hw-external-monitors && fh-hyprland-monitor-internal off", { locked = true })
fh.bind("switch:off:Lid Switch", nil, "fh-hyprland-monitor-internal on", { locked = true })

-- Captures.
fh.bind("PRINT", "Screenshot", "fh-capture-screenshot")
fh.bind("ALT + PRINT", "Screenrecording", "fh-menu screenrecord")
fh.bind("SUPER + PRINT", "Color picker", "pkill hyprpicker || hyprpicker -a")
fh.bind("SUPER + CTRL + PRINT", "Extract text (OCR) from screenshot", "fh-capture-text-extraction")

-- Transcoding.
fh.bind("SUPER + CTRL + PERIOD", "Transcode", "fh-transcode")

-- Reminders.
fh.bind("SUPER + CTRL + ALT + R", "Show reminders", "fh-reminder show")
fh.bind("SUPER + SHIFT + CTRL + R", "Clear reminders", "fh-reminder clear")

-- Waybar-less information.
fh.bind("SUPER + CTRL + ALT + T", "Show time", 'notify-send -u low "    $(date +"%A %H:%M  ·  %d %B %Y  ·  Week %V")"')
fh.bind("SUPER + CTRL + ALT + B", "Show battery remaining", 'notify-send -u low "$(fh-battery-status)"')
fh.bind("SUPER + CTRL + ALT + W", "Show weather", 'notify-send -u low "$(fh-weather-status)"')

-- Control panels.
fh.bind("SUPER + CTRL + A", "Audio controls", "fh-launch-audio")
fh.bind("SUPER + CTRL + B", "Bluetooth controls", "fh-launch-bluetooth")
fh.bind("SUPER + CTRL + W", "Wifi controls", "fh-launch-wifi")
fh.bind("SUPER + CTRL + T", "Activity", "fh-launch-tui btop")

-- Zoom.
fh.bind("SUPER + CTRL + Z", "Zoom in", function()
  local zoom = hl.get_config("cursor.zoom_factor") or 1
  hl.config({ cursor = { zoom_factor = zoom + 1 } })
end)
fh.bind("SUPER + CTRL + ALT + Z", "Reset zoom", function()
  hl.config({ cursor = { zoom_factor = 1 } })
end)

-- Lock system.
fh.bind("SUPER + CTRL + L", "Lock system", "fh-system-lock")
