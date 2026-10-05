-- Session processes, started once per Hyprland start (the old exec-once).
-- Adapted from third-party MIT-licensed code; see LICENSE-THIRD-PARTY in the source repo

hl.on("hyprland.start", function()
  -- Slow app launch fix -- set systemd vars before starting session services.
  hl.exec_cmd("systemctl --user import-environment $(env | cut -d'=' -f 1)")

  -- pam_gnome_keyring starts the keyring daemon at login and unlocks it, but the daemon exits
  -- after 120 s unless the session calls --start (GNOME's autostart entry, OnlyShowIn=GNOME, is
  -- skipped here); a secret requested later then D-Bus-activates a locked daemon and prompts.
  hl.exec_cmd("gnome-keyring-daemon --start --components=secrets")

  hl.exec_cmd(fh.launch("hypridle"))
  hl.exec_cmd(fh.launch("mako"))
  hl.exec_cmd("! fh-toggle-enabled waybar-off && " .. fh.launch("waybar"))
  hl.exec_cmd(fh.launch("fcitx5 --disable notificationitem"))
  hl.exec_cmd(fh.launch("swaybg -i ~/.config/fedora-hypr/current/background -m fill"))
  hl.exec_cmd(fh.launch("elephant"))
  hl.exec_cmd(fh.launch("env GSK_RENDERER=cairo walker --gapplication-service"))
  hl.exec_cmd("systemctl --user start hyprpolkitagent.service")
  hl.exec_cmd(fh.launch("swayosd-server"))
  hl.exec_cmd("fh-first-run")
  hl.exec_cmd("fh-powerprofiles-init")
  hl.exec_cmd("systemctl --user start podman.socket")
  hl.exec_cmd(fh.launch("fh-hyprland-monitor-watch"))
end)
