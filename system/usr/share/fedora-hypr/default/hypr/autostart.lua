-- Session processes, started once per Hyprland start (the old exec-once).
-- Adapted from third-party MIT-licensed code; see LICENSE-THIRD-PARTY in the source repo

hl.on("hyprland.start", function()
  -- Slow app launch fix -- set systemd vars before starting session services.
  hl.exec_cmd("systemctl --user import-environment $(env | cut -d'=' -f 1)")

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
