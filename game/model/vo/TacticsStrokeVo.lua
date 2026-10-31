-- ============================================================
-- TacticsStrokeVo · 战术画板的一笔
-- 坐标是画布宽高的千分比，0–999。
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App

local TacticsStrokeVo = App.newclz("TacticsStrokeVo")

TacticsStrokeVo.id = 0
TacticsStrokeVo.tool = "P"
TacticsStrokeVo.color = 1
TacticsStrokeVo.text = ""
TacticsStrokeVo.pending = false
TacticsStrokeVo.points = {}

function TacticsStrokeVo:ctor(id, tool, color, points, text)
	self.id = id or 0
	self.tool = tool or "P"
	self.color = color or 1
	self.text = text or ""
	self.pending = false
	self.points = {}
	local src = points or {}
	local i = 1
	while i <= #src do
		local p = src[i]
		self.points[i] = {
			x = (p and p.x) or 0,
			y = (p and p.y) or 0,
		}
		i = i + 1
	end
end

App.TacticsStrokeVo = TacticsStrokeVo
