-- https://wiki.hypr.land/Configuring/Basics/Variables/#input
-- Adapted from third-party MIT-licensed code; see LICENSE-THIRD-PARTY in the source repo

hl.config({
  input = {
    kb_layout = "us",
    kb_variant = "",
    kb_model = "",
    kb_options = "compose:caps",
    kb_rules = "",

    follow_mouse = 1,

    -- -1.0 - 1.0, 0 means no modification.
    sensitivity = 0,

    touchpad = {
      natural_scroll = false,
    },
  },

  misc = {
    key_press_enables_dpms = true, -- key press will trigger wake
    mouse_move_enables_dpms = true, -- mouse move will trigger wake
  },
})
