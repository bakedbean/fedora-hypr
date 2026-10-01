-- Runtime toggles: flag modules copied in by fh-hyprland-toggle, plus device and monitor names as data.
-- Adapted from third-party MIT-licensed code; see LICENSE-THIRD-PARTY in the source repo

local paths = require("default.hypr.paths")
local require_all = require("default.hypr.require_all")

local toggles_dir = paths.state_dir .. "/toggles/hypr"
package.path = toggles_dir .. "/?.lua;" .. package.path

-- Only copies of $FH_PATH/default/hypr/toggles/*.lua land here as code.
require_all.files(toggles_dir, nil, { reload = true })

-- Device and monitor names come from hardware (USB descriptors, EDID) and must
-- never be loaded as code, so the scripts store them as plain text instead.
local function read_words(name)
  local file = io.open(toggles_dir .. "/" .. name, "r")
  if not file then
    return nil
  end

  local line = file:read("*l")
  file:close()
  if not line or line == "" then
    return nil
  end

  local words = {}
  for word in line:gmatch("%S+") do
    table.insert(words, word)
  end
  return words, line
end

-- fh-toggle-touchpad: the whole line is the device name (it may contain spaces).
local _, touchpad = read_words("touchpad-disabled.name")
if touchpad then
  hl.device({ name = touchpad, enabled = false })
end

-- fh-hyprland-monitor-internal: "<internal output>".
local internal = read_words("internal-monitor-disable.name")
if internal then
  hl.monitor({ output = internal[1], disabled = true })
end

-- fh-hyprland-monitor-internal-mirror: "<external output> <internal output>".
local mirror = read_words("internal-monitor-mirror.name")
if mirror and mirror[2] then
  hl.monitor({ output = mirror[1], mode = "preferred", position = "auto", scale = 1, mirror = mirror[2] })
end
