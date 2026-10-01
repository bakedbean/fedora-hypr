-- fedora-hypr's Hyprland defaults: helpers, defaults, and current theme overrides.
-- Adapted from third-party MIT-licensed code; see LICENSE-THIRD-PARTY in the source repo

require("default.hypr.helpers")
local require_optional = require("default.hypr.require_optional")

-- Image-owned defaults; don't edit these, override them from ~/.config/hypr.
require("default.hypr.autostart")
if _G.fh_default_bindings ~= false then
  require("default.hypr.bindings.media")
  require("default.hypr.bindings.clipboard")
  require("default.hypr.bindings.tiling-v2")
  require("default.hypr.bindings.utilities")
end
require("default.hypr.envs")
require("default.hypr.looknfeel")
require("default.hypr.input")
require("default.hypr.windows")

-- Current theme overrides, rendered at first login (absent on a fresh HOME).
require_optional.module("fedora-hypr.current.theme.hyprland")
