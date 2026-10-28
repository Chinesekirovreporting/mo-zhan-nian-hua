-- ============================================================
-- SyncState · 一条同步条目现在处在哪一档
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App

App.SyncState = {
	InUse  = "in_use", -- 玩法在用
	Ready  = "ready",  -- 通道备用，玩法还没调用
	Reject = "reject", -- 明确不用
}
