-- Hyprland bootstrap: Lua module path for fedora-hypr's defaults and the user's overrides.
-- Adapted from third-party MIT-licensed code; see LICENSE-THIRD-PARTY in the source repo

local home = os.getenv("HOME")
local fh_path = os.getenv("FH_PATH")
if fh_path == nil or fh_path == "" then
  fh_path = "/usr/share/fedora-hypr"
end

-- `hyprctl reload` re-runs hyprland.lua in the same Lua state, so drop the
-- modules it loads or require() would hand back the cached first load.
local reload_prefixes = {
  "default.hypr",
  "hypr",
  "fedora-hypr.current.theme",
}

local function should_reload_module(module)
  for _, prefix in ipairs(reload_prefixes) do
    if module == prefix or module:sub(1, #prefix + 1) == prefix .. "." then
      return true
    end
  end

  return false
end

local modules_to_reload = {}
for module in pairs(package.loaded) do
  if should_reload_module(module) then
    table.insert(modules_to_reload, module)
  end
end

for _, module in ipairs(modules_to_reload) do
  package.loaded[module] = nil
end

-- User modules (hypr.*, fedora-hypr.current.theme.*) from ~/.config, defaults
-- (default.hypr.*) from $FH_PATH.
package.path = home .. "/.config/?.lua;" .. fh_path .. "/?.lua;" .. package.path
