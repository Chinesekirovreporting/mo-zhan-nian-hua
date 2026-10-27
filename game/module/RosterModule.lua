-- ============================================================
-- RosterModule · 当前团队 / 小队名单
-- 只给出单位和读数。着色和行控件留给 RosterView。
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App

local RosterModule = App.newclz("RosterModule", App.AbstractModule)

function RosterModule:ctor()
	App.AbstractModule.ctor(self, "Roster")
end

function RosterModule:Read(unit)
	local _, classFile = UnitClass(unit)
	return {
		unit      = unit,
		name      = UnitName(unit) or "未知",
		classFile = classFile,
		level     = UnitLevel(unit) or 0,
	}
end

function RosterModule:List()
	local list = {}
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do
			list[#list + 1] = self:Read("raid" .. i)
		end
	elseif IsInGroup() then
		list[#list + 1] = self:Read("player")
		for i = 1, GetNumSubgroupMembers() do
			list[#list + 1] = self:Read("party" .. i)
		end
	else
		list[#list + 1] = self:Read("player")
	end
	return list
end

local inst = RosterModule:new()
App._modules.Roster = inst
inst:enterModule()
