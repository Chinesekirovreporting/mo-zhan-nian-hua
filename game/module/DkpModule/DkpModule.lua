-- ============================================================
-- DkpModule · 公会积分
-- 分数在 DkpMemberVo，流水在 DkpLogVo，名册在 DkpRosterVo。
--
-- 同步 · 名册是 App.SyncScheme.ServerPull；分数留在本机
--   ScanGuild 向暴雪读公会名册（等级、职业、在线）。分数不在这次拉取里。
--   GUILD_ROSTER_UPDATE 只让界面重新拉取，模块本身不订这个事件。
--   EP/GP 与流水写在 MoZhanNianHuaDB。没有跨客户端账本。
--   写入后的 sync 只刷新本机界面，不发插件消息。
--   不用对等式 CRDT：无中心合并容易重复入账。不用 ~S / ~D / ~T。
--   张贴到公会频道是可见聊天，发生在界面，不算状态同步。
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App

local DkpModule = App.newclz("DkpModule", App.AbstractModule)
DkpModule.MAX_LOG = 200

function DkpModule:ctor()
	App.AbstractModule.ctor(self, "Dkp")
	self.classMap = {}
end

function DkpModule:MemberOf(raw)
	return App.DkpMemberVo:From(raw)
end

function DkpModule:BuildClassMap()
	if next(self.classMap) then return end
	for token, loc in pairs(LOCALIZED_CLASS_NAMES_MALE or {}) do
		self.classMap[loc] = token
	end
	for token, loc in pairs(LOCALIZED_CLASS_NAMES_FEMALE or {}) do
		if not self.classMap[loc] then self.classMap[loc] = token end
	end
end

function DkpModule:ResolveClass(cls, idx)
	self:BuildClassMap()
	local colors = RAID_CLASS_COLORS
	if type(cls) == "string" then
		if colors and colors[cls] then return cls end
		if self.classMap[cls] then return self.classMap[cls] end
	end
	if type(idx) == "string" and colors and colors[idx] then return idx end
	return nil
end

-- 同步：本机读存档。不发插件消息。
function DkpModule:DB()
	local db = App.Core.Store:Get()
	if type(db.dkp) ~= "table" then db.dkp = {} end
	local d = db.dkp
	if type(d.members) ~= "table" then d.members = {} end
	if type(d.log) ~= "table" then d.log = {} end
	return d
end

function DkpModule:Members()
	return self:DB().members
end

function DkpModule:Log()
	return self:DB().log
end

function DkpModule:Peek(name)
	local vo = self:MemberOf(self:Members()[name])
	return vo.ep, vo.gp
end

function DkpModule:Net(name)
	return self:MemberOf(self:Members()[name]):Net()
end

function DkpModule:PR(name)
	return self:MemberOf(self:Members()[name]):PR()
end

-- delta > 0 记 EP；delta < 0 记 GP
-- 同步：本机写入 MoZhanNianHuaDB 后 sync。分数不跨客户端，不用 CRDT，不发插件消息。
function DkpModule:AddEntry(name, delta, reason)
	local d = self:DB()
	local vo = self:MemberOf(d.members[name])
	if delta > 0 then
		vo.ep = vo.ep + delta
	else
		vo.gp = vo.gp + (-delta)
	end
	d.members[name] = vo
	table.insert(d.log, App.DkpLogVo:new(name, delta, reason or "", time()))
	while #d.log > self.MAX_LOG do table.remove(d.log, 1) end
	self.model = self.roster or vo
	self:sync("entry")
end

-- 同步：本机撤销最后一条流水后 sync。不发插件消息，也不回放给其他客户端。
function DkpModule:UndoLast()
	local d = self:DB()
	local last = table.remove(d.log)
	if not last then return nil end

	local vo = self:MemberOf(d.members[last.name])
	if last.delta > 0 then
		vo.ep = math.max(0, vo.ep - last.delta)
	else
		vo.gp = math.max(0, vo.gp + last.delta)
	end
	d.members[last.name] = vo
	self.model = self.roster or vo
	self:sync("undo")
	return last
end

-- 同步：App.SyncScheme.ServerPull。只读公会名册，不拉分数，不发插件消息。
function DkpModule:ScanGuild()
	self.roster = {}
	if not (IsInGuild and IsInGuild()) then
		self.model = self.roster
		self:sync("guild")
		return self.roster
	end
	if not (GetNumGuildMembers and GetGuildRosterInfo) then
		self.model = self.roster
		self:sync("guild")
		return self.roster
	end

	local n = GetNumGuildMembers() or 0
	for i = 1, n do
		local ok, name, _, _, level, class, _, _, _, online, _, classIdx =
			pcall(GetGuildRosterInfo, i)
		if ok and name then
			local short = string.match(name, "^([^-]+)") or name
			self.roster[#self.roster + 1] = App.DkpRosterVo:new(
				short,
				level or 0,
				self:ResolveClass(class, classIdx),
				online and true or false,
				true
			)
		end
	end
	self.model = self.roster
	self:sync("guild")
	return self.roster
end

-- 同步：ServerPull 之后补上只有本地分数、不在公会名册里的人。
function DkpModule:Roster()
	local list = self:ScanGuild()
	local seen = {}
	for i = 1, #list do
		seen[list[i].name] = true
	end
	for name in pairs(self:Members()) do
		if not seen[name] then
			list[#list + 1] = App.DkpRosterVo:new(name, 0, nil, false, false)
		end
	end
	self.roster = list
	self.model = list
	self:sync("roster")
	return list
end

-- 过滤、排序，并给出全员净分。界面只负责画 shown。
function DkpModule:Arrange(list, sortBy, query)
	local shown = {}
	query = query or ""
	for i = 1, #list do
		local m = list[i]
		if query == "" or string.find(string.lower(m.name), query, 1, true) then
			shown[#shown + 1] = m
		end
	end
	if sortBy == "name" then
		table.sort(shown, function(a, b) return a.name < b.name end)
	elseif sortBy == "pr" then
		table.sort(shown, function(a, b)
			local pa, pb = self:PR(a.name), self:PR(b.name)
			if pa == pb then return a.name < b.name end
			return pa > pb
		end)
	else
		table.sort(shown, function(a, b)
			local na, nb = self:Net(a.name), self:Net(b.name)
			if na == nb then return a.name < b.name end
			return na > nb
		end)
	end
	local total = 0
	for i = 1, #list do
		total = total + self:Net(list[i].name)
	end
	return shown, total
end

function DkpModule:PostLine(name)
	local ep, gp = self:Peek(name)
	return string.format("[DKP] %s 现有 %d 分（EP %d / GP %d）", name, ep - gp, ep, gp)
end

local inst = DkpModule:new()
App._modules.Dkp = inst
inst:enterModule()
