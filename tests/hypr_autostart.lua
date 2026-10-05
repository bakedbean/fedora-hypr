-- Evaluate ~/.config/hypr/hyprland.lua (HOME and FH_PATH from the environment)
-- against a stub `hl` and print every command it runs, one per line:
--   PHASE<TAB>COMMAND
-- PHASE is "load" for hl.exec_cmd() at config load (what --verify-config and
-- every reload execute) and "start" for one made by a hyprland.start handler,
-- which this script fires after loading. Used by tests/check.sh.
local noop
noop = setmetatable({}, {
  __index = function()
    return noop
  end,
  __call = function()
    return noop
  end,
})

local phase, on_start = "load", {}
hl = setmetatable({
  exec_cmd = function(cmd)
    print(phase .. "\t" .. tostring(cmd))
  end,
  on = function(event, fn)
    if event == "hyprland.start" then
      table.insert(on_start, fn)
    end
  end,
  get_config = function() end,
}, {
  __index = function()
    return noop
  end,
})

dofile(os.getenv("HOME") .. "/.config/hypr/hyprland.lua")
phase = "start"
for _, fn in ipairs(on_start) do
  fn()
end
