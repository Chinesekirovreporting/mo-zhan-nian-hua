-- ============================================================
-- CheckersCellVo · 棋盘一格
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App

local CheckersCellVo = App.newclz("CheckersCellVo")

CheckersCellVo.id = 0
CheckersCellVo.u = 0
CheckersCellVo.v = 0
CheckersCellVo.x = 0
CheckersCellVo.y = 0
CheckersCellVo.arm = 0

function CheckersCellVo:ctor(id, u, v, x, y, arm)
	self.id = id or 0
	self.u = u or 0
	self.v = v or 0
	self.x = x or 0
	self.y = y or 0
	self.arm = arm or 0
end

App.CheckersCellVo = CheckersCellVo
