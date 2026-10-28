-- ============================================================
-- GlobalEvents · 代码全局事件
-- 按模块记下事件名字符串。暴雪事件在 NetEvents。
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App

App.GlobalEvents = {
	-- 壳
	READY        = "MZ_READY",
	PAGE_CHANGED = "MZ_PAGE_CHANGED",
}
