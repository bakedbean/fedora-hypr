-- Laptop multimedia keys for volume and LCD brightness (with OSD).
-- Adapted from third-party MIT-licensed code; see LICENSE-THIRD-PARTY in the source repo

local locked = { locked = true }
local locked_repeat = { locked = true, repeating = true }

local function bind(keys, description, command, options)
  -- Each bind gets its own options table: fh.bind writes the description into it.
  local opts = {}
  for key, value in pairs(options) do
    opts[key] = value
  end
  fh.bind(keys, description, command, opts)
end

bind("XF86AudioRaiseVolume", "Volume up", "swayosd-client --output-volume raise", locked_repeat)
bind("XF86AudioLowerVolume", "Volume down", "swayosd-client --output-volume lower", locked_repeat)
bind("XF86AudioMute", "Mute", "swayosd-client --output-volume mute-toggle", locked_repeat)
bind("XF86AudioMicMute", "Mute microphone", "fh-audio-input-mute", locked_repeat)
bind("XF86MonBrightnessUp", "Brightness up", "fh-brightness-display +5%", locked_repeat)
bind("XF86MonBrightnessDown", "Brightness down", "fh-brightness-display 5%-", locked_repeat)
bind("SHIFT + XF86MonBrightnessUp", "Brightness maximum", "fh-brightness-display 100%", locked_repeat)
bind("SHIFT + XF86MonBrightnessDown", "Brightness minimum", "fh-brightness-display 1%", locked_repeat)
bind("XF86KbdBrightnessUp", "Keyboard brightness up", "fh-brightness-keyboard up", locked_repeat)
bind("XF86KbdBrightnessDown", "Keyboard brightness down", "fh-brightness-keyboard down", locked_repeat)
bind("XF86KbdLightOnOff", "Keyboard backlight cycle", "fh-brightness-keyboard cycle", locked)
bind("XF86TouchpadToggle", "Toggle touchpad", "fh-toggle-touchpad", locked)
bind("XF86TouchpadOn", "Enable touchpad", "fh-toggle-touchpad on", locked)
bind("XF86TouchpadOff", "Disable touchpad", "fh-toggle-touchpad off", locked)

-- Precise 1% multimedia adjustments with Alt modifier.
bind("ALT + XF86AudioRaiseVolume", "Volume up precise", "swayosd-client --output-volume +1", locked_repeat)
bind("ALT + XF86AudioLowerVolume", "Volume down precise", "swayosd-client --output-volume -1", locked_repeat)
bind("ALT + XF86MonBrightnessUp", "Brightness up precise", "fh-brightness-display +1%", locked_repeat)
bind("ALT + XF86MonBrightnessDown", "Brightness down precise", "fh-brightness-display 1%-", locked_repeat)

-- Requires playerctl.
bind("XF86AudioNext", "Next track", "swayosd-client --playerctl next", locked)
bind("XF86AudioPause", "Pause", "swayosd-client --playerctl play-pause", locked)
bind("XF86AudioPlay", "Play", "swayosd-client --playerctl play-pause", locked)
bind("XF86AudioPrev", "Previous track", "swayosd-client --playerctl previous", locked)

-- Switch audio output with Super + Mute.
bind("SUPER + XF86AudioMute", "Switch audio output", "fh-audio-output-switch", locked)
