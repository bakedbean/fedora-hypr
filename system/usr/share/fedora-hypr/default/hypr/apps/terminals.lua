-- Define terminal tag to style them uniformly.
-- Adapted from third-party MIT-licensed code; see LICENSE-THIRD-PARTY in the source repo
fh.window("(Alacritty|kitty|com.mitchellh.ghostty|foot)", { tag = "+terminal" })
fh.window({ tag = "terminal" }, { tag = "-default-opacity" })
fh.window({ tag = "terminal" }, { opacity = "0.985 0.96" })
