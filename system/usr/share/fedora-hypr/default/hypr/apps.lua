-- App-specific tweaks: every file in default/hypr/apps, in sorted order.
-- Adapted from third-party MIT-licensed code; see LICENSE-THIRD-PARTY in the source repo

local paths = require("default.hypr.paths")
local require_all = require("default.hypr.require_all")

require_all.files(paths.fh_path .. "/default/hypr/apps", "default.hypr.apps")
