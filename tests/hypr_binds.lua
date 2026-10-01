-- Evaluate ~/.config/hypr/hyprland.lua (HOME and FH_PATH from the environment)
-- against a stub `hl` and print every keybinding it registers, one per line:
--   MODS<TAB>KEY<TAB>DESCRIPTION<TAB>KIND<TAB>ARG
-- MODS is the sorted, upper-cased modifier list; KIND is "exec" with the shell
-- command as ARG, or the hl.dsp path of any other dispatcher ("function" for a
-- Lua function). Used by tests/binds_test.sh.
local function proxy(path)
  return setmetatable({ path = path }, {
    __index = function(self, key)
      return proxy(self.path .. "." .. key)
    end,
    __call = function(self, first)
      if self.path == "hl.dsp.exec_cmd" then
        return { kind = "exec", arg = first }
      end
      return { kind = self.path, arg = "" }
    end,
  })
end

local noop
noop = setmetatable({}, {
  __index = function()
    return noop
  end,
  __call = function()
    return noop
  end,
})

local function emit(keys, dispatcher, opts)
  local mods, key = {}, nil
  for part in tostring(keys):gmatch("[^+]+") do
    part = part:gsub("^%s+", ""):gsub("%s+$", "")
    local upper = part:upper()
    if upper == "SUPER" or upper == "SHIFT" or upper == "CTRL" or upper == "ALT" then
      table.insert(mods, upper)
    else
      key = part
    end
  end
  table.sort(mods)
  local kind, arg = "function", ""
  if type(dispatcher) == "table" then
    kind, arg = dispatcher.kind, dispatcher.arg or ""
  end
  print(table.concat({ table.concat(mods, " "), (key or ""):upper(), (opts and opts.description) or "", kind, arg }, "\t"))
  return noop
end

hl = setmetatable({ dsp = proxy("hl.dsp"), bind = emit, get_config = function() end }, {
  __index = function()
    return noop
  end,
})

dofile(os.getenv("HOME") .. "/.config/hypr/hyprland.lua")
