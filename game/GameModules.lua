-- ============================================================
-- GameModules · 逻辑侧门面
-- 界面和命令只从这里拿模块，不直接碰 game/module 里的单例。
--   Checkers  六角跳棋
--   Dkp       公会积分
--   Timer     开怪倒计时
--   Roster    参战名单
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
