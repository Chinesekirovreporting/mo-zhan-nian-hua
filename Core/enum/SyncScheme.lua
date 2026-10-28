-- ============================================================
-- SyncScheme · 同步方案
-- 玩法只采用房主全量快照和服务器拉取。新的结构化数据用 Structured。
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App
local State = App.SyncState

App.SyncScheme = {
	HostSnapshot = {
		id    = "HostSnapshot",
		state = State.InUse,
		title = "房主权威 + 全量快照",
		place = "CheckersModule",
		note  = "房主广播全体。跳棋用明文 H/B，走子由房主裁决。座位声明先落地，快照再纠偏。",
	},
	ServerPull = {
		id    = "ServerPull",
		state = State.InUse,
		title = "服务器拉取",
		place = "RosterModule / DkpModule:ScanGuild",
		note  = "名册和公会名单向暴雪接口拉。积分分数留在本机存档。",
	},
	Structured = {
		id    = "Structured",
		state = State.Ready,
		title = "快照 / 增量 / 事务",
		place = "NetManager",
		note  = "~S / ~D / ~T 已实现，玩法未调用。新的结构化同步用这个。",
	},
	Lockstep = {
		id    = "Lockstep",
		state = State.Reject,
		title = "锁步 / 帧同步",
		place = "无",
		note  = "没有共同帧时钟。一人卡住不能拖住全团。",
	},
	Crdt = {
		id    = "Crdt",
		state = State.Reject,
		title = "对等式 CRDT",
		place = "无",
		note  = "无中心合并容易重复入账。",
	},
}
