-- ============================================================
-- RosterUnitVo · 名单里的一个单位
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App

local RosterUnitVo = App.newclz("RosterUnitVo")

RosterUnitVo.unit = ""
RosterUnitVo.name = "未知"
RosterUnitVo.classFile = nil
RosterUnitVo.level = 0

function RosterUnitVo:ctor(unit, name, classFile, level)
	self.unit = unit or ""
	self.name = name or "未知"
	self.classFile = classFile
	self.level = level or 0
end

App.RosterUnitVo = RosterUnitVo
