-- ============================================================
-- DkpRosterVo · 公会名册里的一个人（不含分数）
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App

local DkpRosterVo = App.newclz("DkpRosterVo")

DkpRosterVo.name = ""
DkpRosterVo.level = 0
DkpRosterVo.classFile = nil
DkpRosterVo.online = false
DkpRosterVo.inGuild = false

function DkpRosterVo:ctor(name, level, classFile, online, inGuild)
	self.name = name or ""
	self.level = level or 0
	self.classFile = classFile
	self.online = online and true or false
	self.inGuild = inGuild and true or false
end

App.DkpRosterVo = DkpRosterVo
