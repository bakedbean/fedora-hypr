-- Window management on SUPER + letter / arrow; app launchers live on SUPER SHIFT.
-- Adapted from third-party MIT-licensed code; see LICENSE-THIRD-PARTY in the source repo

-- Close windows.
fh.bind("SUPER + W", "Close window", hl.dsp.window.close())
fh.bind("CTRL + ALT + DELETE", "Close all windows", "fh-hyprland-window-close-all")

-- Control tiling.
fh.bind("SUPER + J", "Toggle window split", hl.dsp.layout("togglesplit"))
fh.bind("SUPER + P", "Pseudo window", hl.dsp.window.pseudo())
fh.bind("SUPER + T", "Toggle window floating/tiling", hl.dsp.window.float({ action = "toggle" }))
fh.bind("SUPER + F", "Full screen", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
fh.bind("SUPER + CTRL + F", "Tiled full screen", hl.dsp.window.fullscreen_state({ internal = 0, client = 2 }))
fh.bind("SUPER + ALT + F", "Full width", hl.dsp.window.fullscreen({ mode = "maximized" }))
fh.bind("SUPER + O", "Pop window out (float & pin)", "fh-hyprland-window-pop")
fh.bind("SUPER + L", "Toggle workspace layout", "fh-hyprland-workspace-layout-toggle")

-- Move focus with SUPER + arrow keys.
fh.bind("SUPER + LEFT", "Focus on left window", hl.dsp.focus({ direction = "l" }))
fh.bind("SUPER + RIGHT", "Focus on right window", hl.dsp.focus({ direction = "r" }))
fh.bind("SUPER + UP", "Focus on above window", hl.dsp.focus({ direction = "u" }))
fh.bind("SUPER + DOWN", "Focus on below window", hl.dsp.focus({ direction = "d" }))

-- Switch workspaces with SUPER + [1-9; 0], move windows with SHIFT (silently with SHIFT + ALT).
for workspace = 1, 10 do
  local key = "code:" .. tostring(workspace + 9)
  fh.bind("SUPER + " .. key, "Switch to workspace " .. workspace, hl.dsp.focus({ workspace = tostring(workspace) }))
  fh.bind("SUPER + SHIFT + " .. key, "Move window to workspace " .. workspace, hl.dsp.window.move({ workspace = tostring(workspace) }))
  fh.bind(
    "SUPER + SHIFT + ALT + " .. key,
    "Move window silently to workspace " .. workspace,
    hl.dsp.window.move({ workspace = tostring(workspace), follow = false })
  )
end

-- Control scratchpad.
fh.bind("SUPER + S", "Toggle scratchpad", hl.dsp.workspace.toggle_special("scratchpad"))
fh.bind("SUPER + ALT + S", "Move window to scratchpad", hl.dsp.window.move({ workspace = "special:scratchpad", follow = false }))

-- TAB between workspaces.
fh.bind("SUPER + TAB", "Next workspace", hl.dsp.focus({ workspace = "e+1" }))
fh.bind("SUPER + SHIFT + TAB", "Previous workspace", hl.dsp.focus({ workspace = "e-1" }))
fh.bind("SUPER + CTRL + TAB", "Former workspace", hl.dsp.focus({ workspace = "previous" }))

-- Move workspaces to other monitors.
fh.bind("SUPER + SHIFT + ALT + LEFT", "Move workspace to left monitor", hl.dsp.workspace.move({ monitor = "l" }))
fh.bind("SUPER + SHIFT + ALT + RIGHT", "Move workspace to right monitor", hl.dsp.workspace.move({ monitor = "r" }))
fh.bind("SUPER + SHIFT + ALT + UP", "Move workspace to up monitor", hl.dsp.workspace.move({ monitor = "u" }))
fh.bind("SUPER + SHIFT + ALT + DOWN", "Move workspace to down monitor", hl.dsp.workspace.move({ monitor = "d" }))

-- Swap active window with the one next to it with SUPER + SHIFT + arrow keys.
fh.bind("SUPER + SHIFT + LEFT", "Swap window to the left", hl.dsp.window.swap({ direction = "l" }))
fh.bind("SUPER + SHIFT + RIGHT", "Swap window to the right", hl.dsp.window.swap({ direction = "r" }))
fh.bind("SUPER + SHIFT + UP", "Swap window up", hl.dsp.window.swap({ direction = "u" }))
fh.bind("SUPER + SHIFT + DOWN", "Swap window down", hl.dsp.window.swap({ direction = "d" }))

-- Cycle through applications on active workspace. The same combo also raises the
-- newly focused window (Hyprland runs every bind on a combo, in order).
fh.bind("ALT + TAB", "Focus on next window", hl.dsp.window.cycle_next())
fh.bind("ALT + SHIFT + TAB", "Focus on previous window", hl.dsp.window.cycle_next({ next = false }))
fh.bind("ALT + TAB", "Reveal active window on top", hl.dsp.window.bring_to_top())
fh.bind("ALT + SHIFT + TAB", "Reveal active window on top", hl.dsp.window.bring_to_top())

-- Cycle through monitors.
fh.bind("CTRL + ALT + TAB", "Focus on next monitor", hl.dsp.focus({ monitor = "+1" }))
fh.bind("CTRL + ALT + SHIFT + TAB", "Focus on previous monitor", hl.dsp.focus({ monitor = "-1" }))

-- Resize active window (code:20 is the - key, code:21 the = key).
fh.bind("SUPER + code:20", "Expand window left", hl.dsp.window.resize({ x = -100, y = 0, relative = true }))
fh.bind("SUPER + code:21", "Shrink window left", hl.dsp.window.resize({ x = 100, y = 0, relative = true }))
fh.bind("SUPER + SHIFT + code:20", "Shrink window up", hl.dsp.window.resize({ x = 0, y = -100, relative = true }))
fh.bind("SUPER + SHIFT + code:21", "Expand window down", hl.dsp.window.resize({ x = 0, y = 100, relative = true }))

-- Scroll through existing workspaces with SUPER + scroll.
fh.bind("SUPER + mouse_down", "Scroll active workspace forward", hl.dsp.focus({ workspace = "e+1" }))
fh.bind("SUPER + mouse_up", "Scroll active workspace backward", hl.dsp.focus({ workspace = "e-1" }))

-- Move/resize windows with SUPER + LMB/RMB and dragging.
fh.bind("SUPER + mouse:272", "Move window", hl.dsp.window.drag(), { mouse = true })
fh.bind("SUPER + mouse:273", "Resize window", hl.dsp.window.resize(), { mouse = true })

-- Toggle groups.
fh.bind("SUPER + G", "Toggle window grouping", hl.dsp.group.toggle())
fh.bind("SUPER + ALT + G", "Move active window out of group", hl.dsp.window.move({ out_of_group = true }))

-- Join groups.
fh.bind("SUPER + ALT + LEFT", "Move window to group on left", hl.dsp.window.move({ into_group = "l" }))
fh.bind("SUPER + ALT + RIGHT", "Move window to group on right", hl.dsp.window.move({ into_group = "r" }))
fh.bind("SUPER + ALT + UP", "Move window to group on top", hl.dsp.window.move({ into_group = "u" }))
fh.bind("SUPER + ALT + DOWN", "Move window to group on bottom", hl.dsp.window.move({ into_group = "d" }))

-- Navigate a single set of grouped windows.
fh.bind("SUPER + ALT + TAB", "Next window in group", hl.dsp.group.next())
fh.bind("SUPER + ALT + SHIFT + TAB", "Previous window in group", hl.dsp.group.prev())

-- Window navigation for grouped windows.
fh.bind("SUPER + CTRL + LEFT", "Move grouped window focus left", hl.dsp.group.prev())
fh.bind("SUPER + CTRL + RIGHT", "Move grouped window focus right", hl.dsp.group.next())

-- Scroll through a set of grouped windows with SUPER + ALT + scroll.
fh.bind("SUPER + ALT + mouse_down", "Next window in group", hl.dsp.group.next())
fh.bind("SUPER + ALT + mouse_up", "Previous window in group", hl.dsp.group.prev())

-- Activate window in a group by number.
for index = 1, 5 do
  fh.bind("SUPER + ALT + code:" .. tostring(index + 9), "Switch to group window " .. index, hl.dsp.group.active({ index = index }))
end

-- Cycle monitor scaling with SUPER + /.
fh.bind("SUPER + code:61", "Cycle monitor scaling", "fh-hyprland-monitor-scaling-cycle")
fh.bind("SUPER + ALT + code:61", "Cycle monitor scaling backwards", "fh-hyprland-monitor-scaling-cycle --reverse")
