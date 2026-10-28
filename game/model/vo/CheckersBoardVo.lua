-- ============================================================
-- CheckersBoardVo · 121 格上的棋子归属，0 表示空
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App

local CheckersBoardVo = App.newclz("CheckersBoardVo")

for i = 1, 121 do
	CheckersBoardVo[i] = 0
end

function CheckersBoardVo:ctor()
	for i = 1, 121 do
		self[i] = 0
	end
end

App.CheckersBoardVo = CheckersBoardVo
