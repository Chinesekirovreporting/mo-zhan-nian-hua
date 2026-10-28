-- ============================================================
-- SyncLimit · 同步约束
-- 都在 NetManager。跳棋全量快照仍是明文 H+B，不改成 ~S。
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App
local State = App.SyncState

App.SyncLimit = {
	Pack = {
		id    = "Pack",
		state = State.Ready,
		title = "序列化与压缩",
		note  = "WriteValue / Pack。结构化包才走。跳棋短明文不走这里。",
	},
	Fragment = {
		id    = "Fragment",
		state = State.InUse,
		title = "分片与重组",
		note  = "超长正文切成 ~F，收齐再派发。",
	},
	Version = {
		id    = "Version",
		state = State.InUse,
		title = "快照与增量",
		note  = "旧序号丢掉。跳棋看 appliedH / appliedB，结构化包看主题版本。",
	},
	Commit = {
		id    = "Commit",
		state = State.Ready,
		title = "事务确认",
		note  = "~T 发出后等 ~A。超时重试。玩法未调用。",
	},
	Rate = {
		id    = "Rate",
		state = State.InUse,
		title = "限速保护",
		note  = "队列最多 60 条，相邻两条至少隔 0.12 秒。",
	},
}
