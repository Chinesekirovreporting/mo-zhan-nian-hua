-- ============================================================
-- RosterModule · 当前团队 / 小队名单
-- 每一行是 RosterUnitVo。List 结束时走本机 sync。
--
-- 同步 · App.SyncScheme.ServerPull
--   List 向暴雪读当前队伍：团队用 raid，小队用 player 加 party，否则只有自己。
--   GROUP_ROSTER_UPDATE 由界面触发重新 List，模块不发插件消息。
--   sync 只把单位数组交给界面。不用房主快照，也不用 ~S / ~D / ~T。
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App

local RosterModule = App.newclz("RosterModule", App.AbstractModule)

function RosterModule:ctor()
	App.AbstractModule.ctor(self, "Roster")
	self.units = {}
end

-- 同步：本机读一个单位。不发插件消息。
function RosterModule:Read(unit)
	local _, classFile = UnitClass(unit)
	return App.RosterUnitVo:new(
		unit,
		UnitName(unit) or "未知",
		classFile,
		UnitLevel(unit) or 0
	)
end

-- 同步：App.SyncScheme.ServerPull。读完走本机 sync，不发插件消息。
function RosterModule:List()
	self.units = {}
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do
			self.units[#self.units + 1] = self:Read("raid" .. i)
		end
	elseif IsInGroup() then
		self.units[#self.units + 1] = self:Read("player")
		for i = 1, GetNumSubgroupMembers() do
			self.units[#self.units + 1] = self:Read("party" .. i)
		end
	else
		self.units[#self.units + 1] = self:Read("player")
	end
	self.model = self.units
	self:sync("list")
	return self.units
end

local inst = RosterModule:new()
App._modules.Roster = inst
inst:enterModule()
