-- ============================================================
-- 插件壳的事件名。玩法自己的名字在 game/Names.lua。
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App

App.Ev = {
	READY        = "MZ_READY",
	PAGE_CHANGED = "MZ_PAGE_CHANGED",
}
