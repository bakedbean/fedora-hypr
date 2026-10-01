-- Webcam overlay for screen recording.
-- Adapted from third-party MIT-licensed code; see LICENSE-THIRD-PARTY in the source repo
fh.window({ title = "WebcamOverlay" }, {
  float = true,
  pin = true,
  no_initial_focus = true,
  no_dim = true,
  move = { "(monitor_w-window_w-40)", "(monitor_h-window_h-40)" },
})
