-- Picture-in-picture overlays.
-- Adapted from third-party MIT-licensed code; see LICENSE-THIRD-PARTY in the source repo
fh.window({ title = "(Picture.?in.?[Pp]icture)" }, { tag = "+pip" })
fh.window({ tag = "pip" }, {
  tag = "-default-opacity",
  float = true,
  pin = true,
  size = { 600, 338 },
  keep_aspect_ratio = true,
  border_size = 0,
  opacity = "1 1",
  move = { "(monitor_w-window_w-40)", "(monitor_h*0.04)" },
})
