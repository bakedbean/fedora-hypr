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

-- Current theme overrides, rendered at first login (absent on a fresh HOME). A user
-- theme's own hyprland.lua (or one converted from its hyprland.conf) is not ours to
-- vouch for: an error in it is reported without losing the defaults loaded above.
local ok, err = pcall(require_optional.module, "fedora-hypr.current.theme.hyprland")
if not ok then
  if os.getenv("FH_VERIFY_STRICT") == "1" then
    error(err, 0)
  end
  hl.notification.create({ text = "Skipped the theme's hyprland.lua: " .. tostring(err), timeout = 30000 })
end
