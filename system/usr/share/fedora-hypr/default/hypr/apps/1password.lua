-- Keep 1Password out of screen shares and float it.
-- Adapted from third-party MIT-licensed code; see LICENSE-THIRD-PARTY in the source repo
fh.window("^(1[p|P]assword)$", { no_screen_share = true, tag = "+floating-window" })
