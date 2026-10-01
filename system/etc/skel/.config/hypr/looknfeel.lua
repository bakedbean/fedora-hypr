-- Change the default fedora-hypr look'n'feel.

-- https://wiki.hypr.land/Configuring/Basics/Variables/#general
hl.config({
  general = {
    -- Small gaps between windows, no borders.
    gaps_in = 2,
    gaps_out = 2,
    border_size = 0,

    -- Use master layout instead of dwindle.
    -- layout = "master",
  },
})

-- https://wiki.hypr.land/Configuring/Basics/Variables/#decoration
-- hl.config({
--   decoration = {
--     -- Use round window corners.
--     rounding = 8,
--   },
-- })

-- https://wiki.hypr.land/Configuring/Basics/Variables/#layout
-- hl.config({
--   layout = {
--     -- Avoid overly wide single-window layouts on wide screens.
--     single_window_aspect_ratio = { 1, 1 },
--   },
-- })

-- Scrolling layout: full screen width per window.
hl.config({
  scrolling = {
    column_width = 1.0,
  },
})
