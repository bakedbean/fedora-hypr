-- Shared helpers for fedora-hypr's Hyprland Lua configuration (the global `fh` table).
-- Adapted from third-party MIT-licensed code; see LICENSE-THIRD-PARTY in the source repo

fh = fh or {}

local function shell_quote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

fh.shell_quote = shell_quote

-- Bind keys ("SUPER + SHIFT + B") to a dispatcher. A string dispatcher is a
-- shell command, run like the old `exec` dispatcher.
function fh.bind(keys, description, dispatcher, options)
  local opts = options or {}

  if description then
    opts.description = description
  end

  if type(dispatcher) == "string" then
    dispatcher = hl.dsp.exec_cmd(dispatcher)
  end

  hl.bind(keys, dispatcher, opts)
end

-- Run a command through uwsm-app so it gets its own systemd scope.
function fh.launch(command)
  return "uwsm-app -- " .. command
end

-- The Lua equivalent of exec-once. Top-level hl.exec_cmd() would also run on
-- every reload and under `Hyprland --verify-config`; hyprland.start does not.
function fh.exec_on_start(command)
  hl.on("hyprland.start", function()
    hl.exec_cmd(command)
  end)
end

function fh.launch_on_start(command)
  fh.exec_on_start(fh.launch(command))
end

function fh.notify(message)
  return "notify-send -u low " .. shell_quote(message)
end

-- Window rule: match is a class regex or a table of match props.
function fh.window(match, rules)
  rules.match = rules.match or {}

  if type(match) == "string" then
    rules.match.class = match
  else
    for key, value in pairs(match) do
      rules.match[key] = value
    end
  end

  hl.window_rule(rules)
end

-- Layer rule matched on the layer namespace.
function fh.layer(namespace, rules)
  rules.match = { namespace = namespace }
  hl.layer_rule(rules)
end
