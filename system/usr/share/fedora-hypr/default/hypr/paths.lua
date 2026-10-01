-- Shared path constants for fedora-hypr's Hyprland Lua modules.
-- Adapted from third-party MIT-licensed code; see LICENSE-THIRD-PARTY in the source repo
-- Lua files loaded with require() have separate local scopes, so modules that
-- need these paths import this table instead of repeating os.getenv() lookups.

local home = os.getenv("HOME")

-- A variable that is set but empty means "unset" (XDG Base Directory spec);
-- bash's ${VAR:-fallback} in the sibling tools treats it the same way.
local function env_or(name, fallback)
  local value = os.getenv(name)
  if value == nil or value == "" then
    return fallback
  end
  return value
end

return {
  home = home,
  config_home = home .. "/.config",
  -- The toggle scripts write here regardless of XDG_STATE_HOME.
  state_dir = home .. "/.local/state/fedora-hypr",
  fh_path = env_or("FH_PATH", "/usr/share/fedora-hypr"),
}
