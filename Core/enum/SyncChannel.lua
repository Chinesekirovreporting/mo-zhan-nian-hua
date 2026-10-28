-- ============================================================
-- SyncChannel · 插件消息频道
-- 队伍频道只留一个：团队优先，其次小队，都没有才用副本。
-- 在公会时再追加公会，同一条包发到「一个队伍频道 + 公会」。
-- id 是发给暴雪的频道名。
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App
local State = App.SyncState

App.SyncChannel = {
	Party = {
		id    = "PARTY",
		state = State.InUse,
		title = "小队",
		note  = "最多 5 人。有团队时不用。",
	},
	Raid = {
		id    = "RAID",
		state = State.InUse,
		title = "团队",
		note  = "最多 40 人。有团队时优先用这个。",
	},
	Guild = {
		id    = "GUILD",
		state = State.InUse,
		title = "公会",
		note  = "跨地图。叠在队伍频道上，不是二选一。",
	},
	InstanceChat = {
		id    = "INSTANCE_CHAT",
		state = State.InUse,
		title = "副本",
		note  = "小队和团队都不在时的替补，不和 RAID 并行。",
	},
	Whisper = {
		id    = "WHISPER",
		state = State.Ready,
		title = "密语",
		note  = "点对点。SendWhisper 已有，玩法未调用。",
	},
	Officer = {
		id    = "OFFICER",
		state = State.Reject,
		title = "官员",
		note  = "只到官员，会把公会拆成两半。",
	},
	Battleground = {
		id    = "BATTLEGROUND",
		state = State.Reject,
		title = "战场",
		note  = "战场同阵营。本插件不走这里。",
	},
	RaidWarning = {
		id    = "RAID_WARNING",
		state = State.Reject,
		title = "团队警告",
		note  = "不是插件消息通道，不能拿来做状态同步。",
	},
}
