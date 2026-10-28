-- ============================================================
-- CheckersOffsetVo · 邻格的 u / v 偏移
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App

local CheckersOffsetVo = App.newclz("CheckersOffsetVo")

CheckersOffsetVo.du = 0
CheckersOffsetVo.dv = 0

function CheckersOffsetVo:ctor(du, dv)
	self.du = du or 0
	self.dv = dv or 0
end

App.CheckersOffsetVo = CheckersOffsetVo
