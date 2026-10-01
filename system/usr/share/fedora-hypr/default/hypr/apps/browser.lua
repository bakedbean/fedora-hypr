-- Browser tags and styling.
-- Adapted from third-party MIT-licensed code; see LICENSE-THIRD-PARTY in the source repo
fh.window("((google-)?[cC]hrom(e|ium)|[bB]rave-browser|[mM]icrosoft-edge|Vivaldi-stable|helium)", { tag = "+chromium-based-browser" })
fh.window("([fF]irefox|zen|librewolf)", { tag = "+firefox-based-browser" })
fh.window({ tag = "chromium-based-browser" }, { tag = "-default-opacity" })
fh.window({ tag = "firefox-based-browser" }, { tag = "-default-opacity" })

-- Video apps: remove chromium browser tag so they don't get opacity applied.
fh.window("(chrome-youtube.com__-Default|chrome-app.zoom.us__wc_home-Default)", { tag = "-chromium-based-browser" })
fh.window("(chrome-youtube.com__-Default|chrome-app.zoom.us__wc_home-Default)", { tag = "-default-opacity" })

-- Force chromium-based browsers into a tile to deal with --app bug.
fh.window({ tag = "chromium-based-browser" }, { tile = true })

-- Only a subtle opacity change, but not for video sites.
fh.window({ tag = "chromium-based-browser" }, { opacity = "1.0 0.985" })
fh.window({ tag = "firefox-based-browser" }, { opacity = "1.0 0.985" })

-- Hide the screen-sharing notification bar (the "Hide" button on it is broken on Wayland).
fh.window({ title = ".*is sharing.*" }, { workspace = "special silent" })
