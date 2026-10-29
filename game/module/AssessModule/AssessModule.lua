-- ============================================================
-- AssessModule · 木桩考核
-- 记公会成员打木桩的每次秒伤，留平均和最高，界面做排行。
--
-- 一次考核：对木桩打出第一下开始，停手超过结算秒数结束。
-- 秒伤 = 有效伤害 / （最后一下 - 第一下）。短于最短秒数的丢掉。
-- 有效伤害 = 打出的伤害 - 过量 + 吸收。默认只算同一只木桩。
-- 平均是各次秒伤的算术平均，不是把所有伤害再除总时间。
--
-- 同步 · 本机读战斗日志，结果留在 MoZhanNianHuaDB.assess
--   COMBAT_LOG_EVENT_UNFILTERED 只推动本机记账。
--   写入后的 sync 只刷新本机界面，不发插件消息。
--   张贴到公会频道是可见聊天，发生在界面。
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App

local BIT_PLAYER = 0x00000400
local BIT_PET = 0x00001000
local BIT_GUARDIAN = 0x00002000
local BIT_CONTROL_PLAYER = 0x00000100

local DUMMY_PARTS = { "木桩", "假人", "沙袋", "dummy" }

local SWING = {
	SWING_DAMAGE = true,
}

local SPELL = {
	SPELL_DAMAGE = true,
	SPELL_PERIODIC_DAMAGE = true,
	RANGE_DAMAGE = true,
	DAMAGE_SHIELD = true,
	DAMAGE_SPLIT = true,
}

local function HasBit(flags, bit)
	flags = tonumber(flags) or 0
	if not bit or bit == 0 then return false end
	return math.floor(flags / bit) % 2 == 1
end

local AssessModule = App.newclz("AssessModule", App.AbstractModule)
AssessModule.MAX_SAMPLES = 40

function AssessModule:ctor()
	App.AbstractModule.ctor(self, "Assess")
	self.sessions = {}
	self.guildNames = {}
	self.guildClass = {}
	self.groupClass = {}
	self.petOwners = {}
	self.classMap = {}
	self._hit = {}
	self._guildAsk = 0
	self._petScan = 0
end

function AssessModule:Time()
	if App.Core and App.Core.Time then return App.Core.Time end
	return App._modules.Time
end

function AssessModule:Ready()
	local store = App.storeManager
	return store and store._ready and true or false
end

function AssessModule:init()
	local mod = self
	App.system:On(App.NetEvents.COMBAT_LOG_EVENT_UNFILTERED, function(_, ...)
		mod:OnCombatEvent(...)
	end)
	App.system:On(App.NetEvents.GUILD_ROSTER_UPDATE, function()
		mod:RefreshGuild()
	end)
	App.system:On(App.NetEvents.GROUP_ROSTER_UPDATE, function()
		mod:RefreshPets()
	end)
	App.system:On(App.NetEvents.PLAYER_ENTERING_WORLD, function()
		mod:RefreshPets()
		mod:RefreshGuild()
		mod:RequestGuild()
	end)
	self:Time():Every(1, function()
		mod:Sweep()
	end)
end

function AssessModule:ShortName(name)
	if type(name) ~= "string" or name == "" then return nil end
	return string.match(name, "^([^-]+)") or name
end

function AssessModule:DB()
	local db = App.Core.Store:Get()
	if type(db.assess) ~= "table" then db.assess = {} end
	local d = db.assess
	if type(d.records) ~= "table" then d.records = {} end
	if type(d.filter) ~= "table" then d.filter = {} end
	local f = d.filter
	if type(f.minSeconds) ~= "number" then f.minSeconds = 10 end
	if f.minSeconds < 5 then f.minSeconds = 5 end
	if f.minSeconds > 600 then f.minSeconds = 600 end
	if type(f.idleSeconds) ~= "number" then f.idleSeconds = 4 end
	if f.idleSeconds < 2 then f.idleSeconds = 2 end
	if f.idleSeconds > 60 then f.idleSeconds = 60 end
	if type(f.guildOnly) ~= "boolean" then f.guildOnly = true end
	if type(f.includePets) ~= "boolean" then f.includePets = true end
	if type(f.singleTarget) ~= "boolean" then f.singleTarget = true end
	if f.rankBy ~= "max" and f.rankBy ~= "avg" and f.rankBy ~= "last" then
		f.rankBy = "max"
	end
	if type(f.excludeNames) ~= "table" then f.excludeNames = {} end
	if type(f.excludeSpells) ~= "table" then f.excludeSpells = {} end
	if type(f.dummyNames) ~= "table" then f.dummyNames = {} end
	return d
end

function AssessModule:Filters()
	return self:DB().filter
end

function AssessModule:BuildClassMap()
	if next(self.classMap) then return end
	for token, loc in pairs(LOCALIZED_CLASS_NAMES_MALE or {}) do
		self.classMap[loc] = token
	end
	for token, loc in pairs(LOCALIZED_CLASS_NAMES_FEMALE or {}) do
		if not self.classMap[loc] then self.classMap[loc] = token end
	end
end

function AssessModule:ResolveClass(cls, idx)
	self:BuildClassMap()
	local colors = RAID_CLASS_COLORS
	if type(cls) == "string" then
		if colors and colors[cls] then return cls end
		if self.classMap[cls] then return self.classMap[cls] end
	end
	if type(idx) == "string" and colors and colors[idx] then return idx end
	return nil
end

function AssessModule:RefreshGuild()
	self.guildNames = {}
	self.guildClass = {}
	if not (IsInGuild and IsInGuild()) then return end
	if not (GetNumGuildMembers and GetGuildRosterInfo) then return end
	local n = GetNumGuildMembers() or 0
	for i = 1, n do
		local ok, name, _, _, _, class, _, _, _, _, _, classFile =
			pcall(GetGuildRosterInfo, i)
		if ok and name then
			local short = self:ShortName(name)
			if short then
				self.guildNames[short] = true
				self.guildClass[short] = self:ResolveClass(class, classFile)
			end
		end
	end
end

function AssessModule:RequestGuild()
	if not (IsInGuild and IsInGuild()) then return end
	if not GuildRoster then return end
	local now = GetTime()
	if now - (self._guildAsk or 0) < 2 then return end
	self._guildAsk = now
	pcall(GuildRoster)
end

function AssessModule:EnsureGuild()
	if next(self.guildNames) then return end
	self:RefreshGuild()
	if not next(self.guildNames) then self:RequestGuild() end
end

function AssessModule:PetToken(unit)
	if unit == "player" then return "playerpet" end
	local kind, index = string.match(unit, "^(%a+)(%d+)$")
	if kind and index then return kind .. "pet" .. index end
	return nil
end

function AssessModule:RefreshPets()
	local function take(unit)
		if not UnitExists or not UnitExists(unit) then return end
		local owner = self:ShortName(UnitName(unit))
		if not owner then return end
		local _, classFile = UnitClass(unit)
		if classFile then self.groupClass[owner] = classFile end
		local pet = self:PetToken(unit)
		if pet and UnitExists(pet) then
			local guid = UnitGUID(pet)
			if guid then self.petOwners[guid] = owner end
		end
	end
	take("player")
	if IsInRaid and IsInRaid() then
		local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
		for i = 1, n do take("raid" .. i) end
	elseif IsInGroup and IsInGroup() then
		local n = (GetNumSubgroupMembers and GetNumSubgroupMembers()) or 0
		for i = 1, n do take("party" .. i) end
	end
end

function AssessModule:ClassOf(name)
	return self.guildClass[name] or self.groupClass[name]
end

function AssessModule:IsDummy(destName)
	if type(destName) ~= "string" or destName == "" then return false end
	local lower = string.lower(destName)
	for i = 1, #DUMMY_PARTS do
		if string.find(lower, DUMMY_PARTS[i], 1, true) then return true end
	end
	local extra = self:Filters().dummyNames
	for i = 1, #extra do
		local needle = extra[i]
		if type(needle) == "string" and needle ~= "" and string.find(destName, needle, 1, true) then
			return true
		end
	end
	return false
end

function AssessModule:IsExcludedName(name)
	local list = self:Filters().excludeNames
	local lower = string.lower(name)
	for i = 1, #list do
		if type(list[i]) == "string" and string.lower(list[i]) == lower then
			return true
		end
	end
	return false
end

function AssessModule:IsExcludedSpell(spellId, spellName)
	local list = self:Filters().excludeSpells
	if #list == 0 then return false end
	local id = spellId and tostring(spellId) or nil
	for i = 1, #list do
		local item = list[i]
		if type(item) == "string" then
			if spellName and item == spellName then return true end
			if id and item == id then return true end
		end
	end
	return false
end

function AssessModule:Accept(name)
	if not name or name == "" then return false end
	if self:IsExcludedName(name) then return false end
	local f = self:Filters()
	if not f.guildOnly then return true end
	if self.guildNames[name] then return true end
	if next(self.guildNames) then return false end
	return true
end

-- 两种战斗日志前缀都认：新客户端第三参是布尔，旧客户端直接是 GUID。
function AssessModule:ReadPrefix(...)
	local subevent = select(2, ...)
	if type(subevent) ~= "string" then return nil end
	local hit = self._hit
	hit.subevent = subevent
	if type(select(3, ...)) == "boolean" then
		hit.sourceGUID = select(4, ...)
		hit.sourceName = select(5, ...)
		hit.sourceFlags = select(6, ...)
		hit.destGUID = select(8, ...)
		hit.destName = select(9, ...)
		hit.base = 12
	else
		hit.sourceGUID = select(3, ...)
		hit.sourceName = select(4, ...)
		hit.sourceFlags = select(5, ...)
		hit.destGUID = select(6, ...)
		hit.destName = select(7, ...)
		hit.base = 9
	end
	return hit
end

function AssessModule:ReadHit(...)
	local swing = SWING[select(2, ...)]
	local spell = SPELL[select(2, ...)]
	if not swing and not spell then return nil end
	local hit = self:ReadPrefix(...)
	if not hit then return nil end
	local base = hit.base

	local amount, overkill, absorbed
	if swing then
		hit.spellId = nil
		hit.spellName = nil
		amount = tonumber(select(base, ...)) or 0
		overkill = tonumber(select(base + 1, ...)) or 0
		absorbed = tonumber(select(base + 5, ...)) or 0
	else
		hit.spellId = select(base, ...)
		hit.spellName = select(base + 1, ...)
		amount = tonumber(select(base + 3, ...)) or 0
		overkill = tonumber(select(base + 4, ...)) or 0
		absorbed = tonumber(select(base + 8, ...)) or 0
	end
	if overkill < 0 then overkill = 0 end
	if absorbed < 0 then absorbed = 0 end
	local total = amount - overkill + absorbed
	if total <= 0 then return nil end
	hit.total = total
	return hit
end

function AssessModule:ActorName(hit)
	local flags = hit.sourceFlags
	if HasBit(flags, BIT_PLAYER) then
		return self:ShortName(hit.sourceName)
	end
	if not self:Filters().includePets then return nil end
	if not (HasBit(flags, BIT_PET) or HasBit(flags, BIT_GUARDIAN)) then return nil end
	if not HasBit(flags, BIT_CONTROL_PLAYER) then return nil end
	local owner = hit.sourceGUID and self.petOwners[hit.sourceGUID]
	if owner then return owner end
	local now = GetTime()
	if now - (self._petScan or 0) >= 1 then
		self._petScan = now
		self:RefreshPets()
		if hit.sourceGUID then return self.petOwners[hit.sourceGUID] end
	end
	return nil
end

function AssessModule:OnCombatEvent(...)
	if not self:Ready() then return end
	if CombatLogGetCurrentEventInfo then
		local subevent = select(2, CombatLogGetCurrentEventInfo())
		if subevent then
			self:OnCombat(CombatLogGetCurrentEventInfo())
			return
		end
	end
	if select(2, ...) then
		self:OnCombat(...)
	end
end

function AssessModule:NoteSummon(...)
	local hit = self:ReadPrefix(...)
	if not hit or not HasBit(hit.sourceFlags, BIT_PLAYER) then return end
	local owner = self:ShortName(hit.sourceName)
	if owner and hit.destGUID then self.petOwners[hit.destGUID] = owner end
end

function AssessModule:OnCombat(...)
	if select(2, ...) == "SPELL_SUMMON" then
		self:NoteSummon(...)
		return
	end
	local hit = self:ReadHit(...)
	if not hit then return end
	if not self:IsDummy(hit.destName) then return end
	if self:IsExcludedSpell(hit.spellId, hit.spellName) then return end
	self:EnsureGuild()
	local name = self:ActorName(hit)
	if not name or not self:Accept(name) then return end
	self:Note(name, hit.total, hit.destGUID)
end

function AssessModule:Note(name, amount, guid)
	local now = GetTime()
	local f = self:Filters()
	local idle = f.idleSeconds or 4
	local s = self.sessions[name]
	if s and (now - s.last) >= idle then
		if self:Finish(name) then self:Publish("commit") end
		s = nil
	end
	if not s then
		self.sessions[name] = {
			start = now,
			last = now,
			damage = amount,
			guid = guid,
		}
		self:Publish("live")
		return
	end
	if f.singleTarget and s.guid and guid and s.guid ~= guid then return end
	s.damage = s.damage + amount
	s.last = now
	if not s.guid then s.guid = guid end
end

function AssessModule:Finish(name)
	local s = self.sessions[name]
	if not s then return false end
	self.sessions[name] = nil
	if not self:Accept(name) then return false end
	local seconds = s.last - s.start
	local minSec = self:Filters().minSeconds or 10
	if seconds < minSec or s.damage <= 0 then return false end
	self:SaveSample(name, self:ClassOf(name), s.damage / seconds, s.damage, seconds, time())
	return true
end

function AssessModule:SaveSample(name, classFile, dps, damage, seconds, at)
	local records = self:DB().records
	local rec = records[name]
	if type(rec) ~= "table" then
		rec = { samples = {} }
		records[name] = rec
	end
	if classFile and classFile ~= "" then rec.classFile = classFile end
	if type(rec.samples) ~= "table" then rec.samples = {} end
	rec.samples[#rec.samples + 1] = {
		dps = dps,
		damage = damage,
		seconds = seconds,
		at = at,
	}
	while #rec.samples > self.MAX_SAMPLES do
		table.remove(rec.samples, 1)
	end
end

function AssessModule:Sweep()
	if not self:Ready() then return end
	local now = GetTime()
	local idle = self:Filters().idleSeconds or 4
	local changed = false
	for name, s in pairs(self.sessions) do
		if not self:Accept(name) then
			self.sessions[name] = nil
		elseif s and (now - s.last) >= idle then
			if self:Finish(name) then changed = true end
		end
	end
	if changed or next(self.sessions) then
		self:Publish(changed and "commit" or "live")
	end
end

function AssessModule:Publish(why)
	self._why = why or self._why
	if self._armed then return end
	self._armed = true
	local mod = self
	self:Time():After(0.25, function()
		mod._armed = false
		local reason = mod._why or "sync"
		mod._why = nil
		mod.model = { why = reason }
		mod:sync(reason)
	end)
end

function AssessModule:FormatDps(n)
	n = math.floor((tonumber(n) or 0) + 0.5)
	if n >= 10000 then
		return string.format("%.1f万", n / 10000)
	end
	return tostring(n)
end

function AssessModule:LiveList()
	local now = GetTime()
	local list = {}
	for name, s in pairs(self.sessions) do
		local elapsed = now - s.start
		if elapsed < 0 then elapsed = 0 end
		local dps = elapsed > 0 and (s.damage / elapsed) or 0
		list[#list + 1] = {
			name = name,
			dps = dps,
			seconds = elapsed,
			damage = s.damage,
		}
	end
	table.sort(list, function(a, b)
		if a.dps == b.dps then return a.name < b.name end
		return a.dps > b.dps
	end)
	return list
end

function AssessModule:Arrange(query)
	local rows = {}
	query = string.lower(query or "")
	local records = self:DB().records
	for name, raw in pairs(records) do
		if type(name) == "string" and not self:IsExcludedName(name) then
			if query == "" or string.find(string.lower(name), query, 1, true) then
				local vo = App.AssessRecordVo:From(name, raw)
				if #vo.samples > 0 then
					rows[#rows + 1] = vo
				end
			end
		end
	end
	local by = self:Filters().rankBy or "max"
	table.sort(rows, function(a, b)
		local ka, kb
		if by == "avg" then
			ka, kb = a:Avg(), b:Avg()
		elseif by == "last" then
			local la, lb = a:Last(), b:Last()
			ka = la and la.dps or 0
			kb = lb and lb.dps or 0
		else
			ka, kb = a:Max(), b:Max()
		end
		if ka == kb then return a.name < b.name end
		return ka > kb
	end)
	return rows
end

function AssessModule:SetNumber(key, value)
	value = tonumber(value)
	if not value then return end
	local f = self:Filters()
	if key == "minSeconds" then
		f.minSeconds = math.max(5, math.min(600, math.floor(value)))
	elseif key == "idleSeconds" then
		f.idleSeconds = math.max(2, math.min(60, math.floor(value)))
	else
		return
	end
	self:Publish("filter")
end

function AssessModule:Toggle(key)
	if key ~= "guildOnly" and key ~= "includePets" and key ~= "singleTarget" then return end
	local f = self:Filters()
	f[key] = not f[key]
	self:Publish("filter")
	return f[key]
end

function AssessModule:CycleRank()
	local f = self:Filters()
	local nextBy = { max = "avg", avg = "last", last = "max" }
	f.rankBy = nextBy[f.rankBy] or "max"
	self:Publish("rank")
	return f.rankBy
end

function AssessModule:AddList(key, text)
	if key ~= "excludeNames" and key ~= "excludeSpells" and key ~= "dummyNames" then
		return false
	end
	text = strtrim(text or "")
	if text == "" or string.len(text) > 48 then return false end
	local list = self:Filters()[key]
	local lower = string.lower(text)
	for i = 1, #list do
		if type(list[i]) == "string" and string.lower(list[i]) == lower then
			return false
		end
	end
	if #list >= 40 then return false end
	list[#list + 1] = text
	self:Publish("filter")
	return true
end

function AssessModule:RemoveList(key, text)
	if key ~= "excludeNames" and key ~= "excludeSpells" and key ~= "dummyNames" then return end
	local list = self:Filters()[key]
	for i = #list, 1, -1 do
		if list[i] == text then table.remove(list, i) end
	end
	self:Publish("filter")
end

function AssessModule:UndoLast(name)
	local rec = self:DB().records[name]
	if type(rec) ~= "table" or type(rec.samples) ~= "table" then return nil end
	local last = table.remove(rec.samples)
	if not last then return nil end
	if #rec.samples == 0 then self:DB().records[name] = nil end
	self:Publish("undo")
	return last
end

function AssessModule:Remove(name)
	if not name then return end
	self:DB().records[name] = nil
	self.sessions[name] = nil
	self:Publish("remove")
end

function AssessModule:Clear()
	self:DB().records = {}
	self.sessions = {}
	self:Publish("clear")
end

function AssessModule:PostText()
	local rows = self:Arrange("")
	if #rows == 0 then return nil end
	local function line(n)
		local parts = {}
		for i = 1, n do
			local r = rows[i]
			parts[i] = string.format("%d.%s 高%s/均%s", i, r.name, self:FormatDps(r:Max()), self:FormatDps(r:Avg()))
		end
		return "[考核] " .. table.concat(parts, " ")
	end
	local n = math.min(5, #rows)
	local text = line(n)
	if string.len(text) > 250 and n > 3 then
		text = line(3)
	end
	return text
end

local inst = AssessModule:new()
App._modules.Assess = inst
inst:enterModule()
