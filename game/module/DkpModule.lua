-- ============================================================
-- DkpModule · 公会积分
-- 单一积分池：EP 获得，GP 消耗。净分 = EP - GP，PR = EP / GP。
-- 名册只读名单 / 等级 / 职业，分数写在本地存档。
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App

local DkpModule = App.newclz("DkpModule", App.AbstractModule)
local MAX_LOG = 200

local localToToken = {}

local function Normalize(raw)
	if type(raw) == "table" then
		return tonumber(raw.ep) or 0, tonumber(raw.gp) or 0
	elseif type(raw) == "number" then
		return raw, 0
	end
	return 0, 0
end

local function BuildClassMap()
	if next(localToToken) then return end
	for token, loc in pairs(LOCALIZED_CLASS_NAMES_MALE or {}) do
		localToToken[loc] = token
	end
	for token, loc in pairs(LOCALIZED_CLASS_NAMES_FEMALE or {}) do
		if not localToToken[loc] then localToToken[loc] = token end
	end
end

local function ResolveClass(cls, idx)
	BuildClassMap()
	local colors = RAID_CLASS_COLORS
	if type(cls) == "string" then
		if colors and colors[cls] then return cls end
		if localToToken[cls] then return localToToken[cls] end
	end
	if type(idx) == "string" and colors and colors[idx] then return idx end
	return nil
end

function DkpModule:ctor()
	App.AbstractModule.ctor(self, "Dkp")
end

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
	return Normalize(self:Members()[name])
end

function DkpModule:Net(name)
	local ep, gp = self:Peek(name)
	return ep - gp
end

function DkpModule:PR(name)
	local ep, gp = self:Peek(name)
	return ep / math.max(1, gp)
end

-- delta > 0 记 EP；delta < 0 记 GP
function DkpModule:AddEntry(name, delta, reason)
	local d = self:DB()
	local ep, gp = Normalize(d.members[name])
	if delta > 0 then
		ep = ep + delta
	else
		gp = gp + (-delta)
	end
	d.members[name] = { ep = ep, gp = gp }
	table.insert(d.log, {
		name   = name,
		delta  = delta,
		reason = reason or "",
		at     = time(),
	})
	while #d.log > MAX_LOG do table.remove(d.log, 1) end
end

function DkpModule:UndoLast()
	local d = self:DB()
	local last = table.remove(d.log)
	if not last then return nil end

	local ep, gp = Normalize(d.members[last.name])
	if last.delta > 0 then
		ep = math.max(0, ep - last.delta)
	else
		gp = math.max(0, gp + last.delta)
	end
	d.members[last.name] = { ep = ep, gp = gp }
	return last
end

function DkpModule:ScanGuild()
	local list = {}
	if not (IsInGuild and IsInGuild()) then return list end
	if not (GetNumGuildMembers and GetGuildRosterInfo) then return list end

	local n = GetNumGuildMembers() or 0
	for i = 1, n do
		local ok, name, _, _, level, class, _, _, _, online, _, classIdx =
			pcall(GetGuildRosterInfo, i)
		if ok and name then
			local short = string.match(name, "^([^-]+)") or name
			list[#list + 1] = {
				name      = short,
				level     = level or 0,
				classFile = ResolveClass(class, classIdx),
				online    = online and true or false,
				inGuild   = true,
			}
		end
	end
	return list
end

local inst = DkpModule:new()
App._modules.Dkp = inst
inst:enterModule()
