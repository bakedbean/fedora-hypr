-- Session environment variables.
-- Adapted from third-party MIT-licensed code; see LICENSE-THIRD-PARTY in the source repo

local paths = require("default.hypr.paths")
local require_optional = require("default.hypr.require_optional")

-- GUM environment variables for styling purposes (rendered by the theme engine).
require_optional.module("fedora-hypr.current.theme.gum-env")

-- Cursor size.
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

-- Force all apps to use Wayland.
hl.env("GDK_BACKEND", "wayland,x11,*")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_STYLE_OVERRIDE", "kvantum")
hl.env("MOZ_ENABLE_WAYLAND", "1")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "wayland")
hl.env("OZONE_PLATFORM", "wayland")
hl.env("XDG_SESSION_TYPE", "wayland")

-- Allow better support for screen sharing (Google Meet, Discord, etc).
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")

-- Use XCompose file.
hl.env("XCOMPOSEFILE", paths.home .. "/.XCompose")

hl.config({
  xwayland = {
    force_zero_scaling = true,
  },

  -- Don't show update news on first launch.
  ecosystem = {
    no_update_news = true,
  },
})
