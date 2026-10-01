-- Avoid overly wide single-window layouts on wide screens.
-- Adapted from third-party MIT-licensed code; see LICENSE-THIRD-PARTY in the source repo
hl.config({
  layout = {
    single_window_aspect_ratio = { 1, 1 },
  },
})
