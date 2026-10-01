-- See https://wiki.hypr.land/Configuring/Basics/Window-Rules/
-- Adapted from third-party MIT-licensed code; see LICENSE-THIRD-PARTY in the source repo

fh.window(".*", { suppress_event = "maximize" })

-- Tag all windows for default opacity (apps can override with -default-opacity tag).
fh.window(".*", { tag = "+default-opacity" })

-- Fix some dragging issues with XWayland.
fh.window(
  {
    class = "^$",
    title = "^$",
    xwayland = true,
    float = true,
    fullscreen = false,
    pin = false,
  },
  { no_focus = true }
)

-- App-specific tweaks (may remove default-opacity tag).
require("default.hypr.apps")

-- Apply default opacity after apps have had a chance to opt out.
fh.window({ tag = "default-opacity" }, { opacity = "0.985 0.96" })
