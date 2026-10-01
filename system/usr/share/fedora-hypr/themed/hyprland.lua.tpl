-- Theme colours for Hyprland, rendered by fh-theme-set-templates.
local active_border_color = "rgb({{ accent_strip }})"

hl.config({
  general = {
    col = {
      active_border = active_border_color,
    },
  },

  group = {
    col = {
      border_active = active_border_color,
    },
  },
})
