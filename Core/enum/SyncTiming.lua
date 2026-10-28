-- ============================================================
-- SyncTiming · 同步时机
-- 帧回调只抽发送队列，不按帧同步状态。
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App
local State = App.SyncState

App.SyncTiming = {
	Frame = {
		id    = "Frame",
		state = State.InUse,
		title = "帧回调",
		note  = "OnUpdate 每帧抽队列。发送间隔 0.12 秒，不按帧同步状态。",
	},
	Click = {
		id    = "Click",
		state = State.InUse,
		title = "用户点击",
		note  = "走子、入座、准备、开局才发包。",
	},
	System = {
		id    = "System",
		state = State.InUse,
		title = "系统事件",
		note  = "CHAT_MSG_ADDON 收插件消息。名册事件只触发本机重新拉取。",
	},
	Code = {
		id    = "Code",
		state = State.Reject,
		title = "代码事件",
		note  = "App.eventManager 和模块 sync 只刷新本机，不发插件消息。",
	},
	Heartbeat = {
		id    = "Heartbeat",
		state = State.InUse,
		title = "周期心跳",
		note  = "跳棋逻辑每秒看一次。心跳 8 秒，房主全量广播 4 秒。",
	},
	Request = {
		id    = "Request",
		state = State.InUse,
		title = "主动请求",
		note  = "对不上时约每 2 秒发 R 或 R|序号。resync 还没有监听者。",
	},
}
