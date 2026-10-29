-- ============================================================
-- NetEvents · 收集到的暴雪事件
-- 字符串集。订阅走 App.system 的 On / Once / Off。
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App

App.NetEvents = {
	ADDON_LOADED          = "ADDON_LOADED",
	GROUP_ROSTER_UPDATE   = "GROUP_ROSTER_UPDATE",
	GUILD_ROSTER_UPDATE   = "GUILD_ROSTER_UPDATE",
	PLAYER_ENTERING_WORLD = "PLAYER_ENTERING_WORLD",
	COMBAT_LOG_EVENT_UNFILTERED = "COMBAT_LOG_EVENT_UNFILTERED",
}
