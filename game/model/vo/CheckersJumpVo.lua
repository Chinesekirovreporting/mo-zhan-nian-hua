-- ============================================================
-- CheckersJumpVo · 一跳的中点与落点
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App

local CheckersJumpVo = App.newclz("CheckersJumpVo")

CheckersJumpVo.mid = 0
CheckersJumpVo.dest = 0

function CheckersJumpVo:ctor(mid, dest)
	self.mid = mid or 0
	self.dest = dest or 0
end

App.CheckersJumpVo = CheckersJumpVo
