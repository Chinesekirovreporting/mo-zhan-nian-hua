-- ============================================================
-- GameModules · 逻辑侧门面
-- 界面和命令只从这里拿模块，不直接碰 game/module 里的单例。
--   Checkers  六角跳棋。房主权威 + 全量快照，明文 H/B/C/Q/W/P/E/R
--   Dkp       公会积分。名册向服务器拉，分数留在本机存档
--   Timer     开怪倒计时。可见公告，不同步状态
--   Roster    参战名单。向服务器拉当前队伍
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App

local M = App._modules
assert(M.Checkers and M.Dkp and M.Timer and M.Roster, "GameModules: 逻辑模块未就绪")

local GameModules = {
	Checkers = M.Checkers,
	Dkp      = M.Dkp,
	Timer    = M.Timer,
	Roster   = M.Roster,
}

function GameModules:Get(name)
	return self[name]
end

App.GameModules = GameModules
