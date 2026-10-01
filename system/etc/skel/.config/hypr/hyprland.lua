-- Learn how to configure Hyprland: https://wiki.hypr.land/Configuring/Start/

local fh_path = os.getenv("FH_PATH")
if fh_path == nil or fh_path == "" then
  fh_path = "/usr/share/fedora-hypr"
end
local bootstrap = fh_path .. "/default/hypr/bootstrap.lua"

-- Rollback guard: an image from before the Lua config (`bootc rollback`) has no
-- Lua defaults. Step aside so the next login falls back to the legacy
-- hyprland.conf that the migration left in place, and keep a terminal and a way
-- out on hand for this session.
local probe = io.open(bootstrap, "r")
if not probe then
  local self = os.getenv("HOME") .. "/.config/hypr/hyprland.lua"
  os.rename(self, self .. ".rolled-back")
  hl.bind("SUPER + RETURN", hl.dsp.exec_cmd("alacritty"))
  hl.bind("SUPER + ESCAPE", hl.dsp.exit())
  hl.notification.create({
    text = "This image has no Lua Hyprland config. Log out (SUPER + ESCAPE) and back in to use your previous hyprland.conf.",
    timeout = 60000,
  })
  return
end
probe:close()

-- Module paths for fedora-hypr's defaults and your overrides below.
dofile(bootstrap)

-- Disable all fedora-hypr default bindings. Add your own in hypr/bindings.lua.
-- fh_default_bindings = false

-- fedora-hypr defaults (image-owned; don't edit, override below).
require("default.hypr.defaults")

-- Your overrides (these files are yours). They load after the defaults, so
-- image updates can improve the defaults without rewriting ~/.config/hypr.
-- A Lua error in one of them is reported and skipped rather than taking the
-- defaults (and their keybindings) down with it.
local function user(module)
  if os.getenv("FH_VERIFY_STRICT") == "1" then
    return require(module) -- fh-migrate-hypr-lua and the image tests want every error
  end
  local ok, err = pcall(require, module)
  if not ok then
    hl.notification.create({ text = "Skipped " .. module .. ": " .. tostring(err), timeout = 30000 })
  end
end

user("hypr.monitors")
user("hypr.input")
user("hypr.bindings")
user("hypr.envs")
user("hypr.looknfeel")
user("hypr.autostart")

-- Runtime toggles.
require("default.hypr.toggles")

-- Add any other personal Hyprland configuration below.
-- fh.window("qemu", { workspace = "5" })
