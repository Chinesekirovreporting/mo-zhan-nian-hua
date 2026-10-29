-- ============================================================
-- WisdomModule · 公会智慧树
-- 一棵树挂在公会名下。离开也会长，浇水和施肥让它长得更快。
--
-- 同步 · 公会园丁 + 明文快照，不走跳棋字母，也不走 ~S / ~D / ~T
--   包以 Z| 开头，只发 GUILD。跳棋收到会自己丢掉。
--   在线、名字序最小的人是园丁。只有园丁改照料数。
--   挂机寸数用种下时间推算，各端相同，不另发包。
--   Z|P 报在线，Z|N 要快照，Z|Q|W / Z|Q|F 请求照料，
--   Z|H 是整份树，Z|E 是园丁退回。旧序号丢掉。
--   看见比自己旧的快照，就把手里较新的整份再发一次。
--   采摘的悟性只写 MoZhanNianHuaDB，不进快照。
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App

local STAGES = {
	{ 0, "种子" },
	{ 8, "萌芽" },
	{ 30, "嫩芽" },
	{ 80, "幼苗" },
	{ 160, "小树" },
	{ 300, "成树" },
	{ 520, "繁茂" },
	{ 800, "古树" },
	{ 1200, "智慧树" },
	{ 1800, "通天" },
}

local TIPS = {
	"年轮不记单次的浇灌，只记大家来过。",
	"树不说话。养分够了，它自己会往上长。",
	"离开的时候它也在长，回来看一眼就好。",
	"施肥要隔得开。树记住的是间隔。",
	"这棵树没有单独的主人。",
	"悟性是摘给自己的，树高是大家的。",
	"一寸一寸长，比一口气拔起来稳。",
	"公会在，树就在。人散了，年轮还在。",
}

local WisdomModule = App.newclz("WisdomModule", App.AbstractModule)

WisdomModule.WATER_CD = 15 * 60
WisdomModule.FERT_CD = 60 * 60
WisdomModule.WATER_GAIN = 12
WisdomModule.FERT_GAIN = 36
WisdomModule.IDLE_STEP = 10 * 60
WisdomModule.FRUIT_STEP = 40
WisdomModule.GRACE = 8
WisdomModule.PRESENCE = 24
WisdomModule.PULSE = 8
WisdomModule.ANNOUNCE = 20
WisdomModule.HOLD = 30

function WisdomModule:ctor()
	App.AbstractModule.ctor(self, "Wisdom")
	self.model = App.WisdomTreeVo:new()
	self.water = {}
	self.fert = {}
	self.log = {}
	self.presence = {}
	self.inbox = {}
	self._seenQ = {}
	self.care = 0
	self.seq = 0
	self.plantedAt = 0
	self.seen = 0
	self.wisdom = 0
	self.quote = ""
	self.lastName = ""
	self.lastAct = ""
	self.lastAt = 0
	self.note = ""
	self.noteUntil = 0
	self.hold = { W = 0, F = 0 }
	self.loaded = false
	self.graced = false
	self.graceUntil = 0
	self.watching = false
	self.key = nil
end

function WisdomModule:init()
	local mod = self
	App.system:On(App.NetEvents.PLAYER_ENTERING_WORLD, function()
		mod:Ensure()
		mod:FollowGuild()
	end)
	App.system:On(App.NetEvents.GUILD_ROSTER_UPDATE, function()
		if mod.loaded then mod:FollowGuild() end
	end)
	App.timerManager:Every(1, function()
		mod:OnSecond()
	end)
	App.timerManager:Every(self.PULSE, function()
		mod:OnPulse()
	end)
end

function WisdomModule:Me()
	local name = UnitName("player") or "player"
	return string.match(name, "^([^-]+)") or name
end

function WisdomModule:GuildName()
	if not (IsInGuild and IsInGuild()) then return nil end
	if not GetGuildInfo then return nil end
	local name = GetGuildInfo("player")
	if type(name) ~= "string" or name == "" then return nil end
	return name
end

function WisdomModule:InGuild()
	return type(self.key) == "string" and self.key ~= "@"
end

function WisdomModule:Clock(sec)
	sec = math.max(0, math.floor((sec or 0) + 0.5))
	return string.format("%02d:%02d", math.floor(sec / 60), sec % 60)
end

function WisdomModule:Note(text)
	self.note = text or ""
	self.noteUntil = GetTime() + 4
end

function WisdomModule:Bucket()
	local db = App.Core.Store:Get()
	if type(db.wisdom) ~= "table" then db.wisdom = {} end
	if type(db.wisdom.trees) ~= "table" then db.wisdom.trees = {} end
	return db.wisdom.trees
end

function WisdomModule:CopyTouches(src)
	local map = {}
	if type(src) ~= "table" then return map end
	for name, rec in pairs(src) do
		if type(name) == "string" and type(rec) == "table" then
			map[name] = App.WisdomTouchVo:new(tonumber(rec.last) or 0, tonumber(rec.count) or 0)
		end
	end
	return map
end

function WisdomModule:ReadStore()
	local store = self.key and self:Bucket()[self.key] or nil
	if type(store) ~= "table" then store = {} end
	self.seq = tonumber(store.seq) or 0
	self.plantedAt = tonumber(store.plantedAt) or 0
	self.care = tonumber(store.care) or 0
	self.seen = tonumber(store.seen) or 0
	self.wisdom = tonumber(store.wisdom) or 0
	self.quote = type(store.quote) == "string" and store.quote or ""
	self.lastName = type(store.lastName) == "string" and store.lastName or ""
	if store.lastAct == "W" or store.lastAct == "F" then
		self.lastAct = store.lastAct
	else
		self.lastAct = ""
	end
	self.lastAt = tonumber(store.lastAt) or 0
	self.water = self:CopyTouches(store.water)
	self.fert = self:CopyTouches(store.fert)
	self.log = {}
	if type(store.log) == "table" then
		for i = 1, #store.log do
			local row = store.log[i]
			if type(row) == "table" and type(row.name) == "string" then
				self.log[#self.log + 1] = App.WisdomCareVo:new(row.name, row.act, row.at)
			end
		end
	end
	while #self.log > 12 do table.remove(self.log, 1) end
end

function WisdomModule:Save()
	if not self.key then return end
	local log = {}
	for i = 1, #self.log do
		local row = self.log[i]
		log[i] = { name = row.name, act = row.act, at = row.at }
	end
	local function dump(map)
		local out = {}
		for name, rec in pairs(map) do
			out[name] = { last = rec.last or 0, count = rec.count or 0 }
		end
		return out
	end
	self:Bucket()[self.key] = {
		seq = self.seq,
		plantedAt = self.plantedAt,
		care = self.care,
		seen = self.seen,
		wisdom = self.wisdom,
		quote = self.quote,
		lastName = self.lastName,
		lastAct = self.lastAct,
		lastAt = self.lastAt,
		water = dump(self.water),
		fert = dump(self.fert),
		log = log,
	}
end

function WisdomModule:PlantSolo()
	if self.plantedAt > 0 then return end
	self.plantedAt = time()
	if self.seq < 1 then self.seq = 1 end
	self:Save()
end

function WisdomModule:Swap(key)
	if self.key then self:Save() end
	self.key = key
	self.presence = {}
	self.inbox = {}
	self._seenQ = {}
	self.hold = { W = 0, F = 0 }
	self:ReadStore()
	if key == "@" then
		self.graced = true
		self.graceUntil = 0
		self:PlantSolo()
	else
		self.graced = false
		self.graceUntil = GetTime() + self.GRACE
		self:Send("Z|P")
	end
	self:Refresh()
	self:sync("guild")
end

function WisdomModule:FollowGuild()
	if not self.loaded then return end
	local name = self:GuildName()
	if name then
		if self.key ~= name then self:Swap(name) end
		return
	end
	if IsInGuild and IsInGuild() then return end
	if self.key ~= "@" then self:Swap("@") end
end

function WisdomModule:Ensure()
	if self.loaded then return end
	self.loaded = true
	local name = self:GuildName()
	if name then
		self.key = name
		self.graced = false
		self.graceUntil = GetTime() + self.GRACE
	elseif IsInGuild and IsInGuild() then
		self.key = nil
		self.graced = false
		self.graceUntil = 0
	else
		self.key = "@"
		self.graced = true
		self.graceUntil = 0
	end
	if self.key then
		self:ReadStore()
		if self.key == "@" then self:PlantSolo() end
	end
	self:Refresh()
	self:sync("load")
	if name then self:Send("Z|P") end
end

function WisdomModule:GardenerName()
	if not self:InGuild() then return self:Me() end
	local now = GetTime()
	local best = self:Me()
	local dead = {}
	for name, at in pairs(self.presence) do
		if now - at > self.PRESENCE then
			dead[#dead + 1] = name
		elseif name < best then
			best = name
		end
	end
	for i = 1, #dead do
		self.presence[dead[i]] = nil
	end
	return best
end

function WisdomModule:IsGardener()
	return self:GardenerName() == self:Me()
end

function WisdomModule:Send(text)
	if not self:InGuild() then return false end
	local net = (App.Core and App.Core.Net) or App._modules.Net
	if not net then return false end
	return net:SendTo(App.SyncChannel.Guild.id, text)
end

function WisdomModule:EncodeMap(map)
	local parts = {}
	for name, rec in pairs(map or {}) do
		if type(name) == "string" and name ~= "" and #name <= 48 and not string.find(name, "[:;|]", 1) then
			parts[#parts + 1] = string.format("%s:%d:%d", name, rec.last or 0, rec.count or 0)
		end
	end
	if #parts == 0 then return "-" end
	table.sort(parts)
	return table.concat(parts, ";")
end

function WisdomModule:DecodeMap(blob)
	local map = {}
	if type(blob) ~= "string" or blob == "" or blob == "-" then return map end
	local now = time()
	for item in string.gmatch(blob, "[^;]+") do
		local name, last, count = string.match(item, "^([^:]+):(%d+):(%d+)$")
		last = tonumber(last)
		count = tonumber(count)
		if name and name ~= "" and #name <= 48 and not string.find(name, "[|;]", 1) and last and count then
			if count >= 0 and count <= 9999 and last >= 0 and last <= now + 120 then
				map[name] = App.WisdomTouchVo:new(last, count)
			end
		end
	end
	return map
end

function WisdomModule:Pack()
	local lastName = self.lastName ~= "" and self.lastName or "-"
	local lastAct = (self.lastAct == "W" or self.lastAct == "F") and self.lastAct or "-"
	return string.format("Z|H|%d|%d|%d|%s|%s|%s|%s|%d",
		self.seq or 0,
		self.plantedAt or 0,
		self.care or 0,
		self:EncodeMap(self.water),
		self:EncodeMap(self.fert),
		lastName,
		lastAct,
		self.lastAt or 0)
end

function WisdomModule:MapCount(map)
	local n = 0
	for _ in pairs(map or {}) do n = n + 1 end
	return n
end

function WisdomModule:TrimMaps()
	local function drop(map)
		local victim, oldest
		for name, rec in pairs(map) do
			local last = rec.last or 0
			if not oldest or last < oldest then
				victim = name
				oldest = last
			end
		end
		if victim then map[victim] = nil end
	end
	if self:MapCount(self.water) >= self:MapCount(self.fert) then
		drop(self.water)
	else
		drop(self.fert)
	end
end

function WisdomModule:Broadcast()
	if not self:InGuild() or self.plantedAt <= 0 or not self.graced then return false end
	local text = self:Pack()
	local guard = 0
	while #text > 7000 and guard < 80 do
		self:TrimMaps()
		text = self:Pack()
		guard = guard + 1
	end
	if guard > 0 then self:Save() end
	local ok = self:Send(text)
	if ok then self.lastBroadcast = GetTime() end
	return ok
end

function WisdomModule:OfferNewer()
	if not self.graced then return end
	if GetTime() - (self.lastOffer or 0) < 8 then return end
	self.lastOffer = GetTime()
	self:Broadcast()
end

function WisdomModule:Tend()
	if self.plantedAt > 0 then return false end
	if self:InGuild() and (not self.graced or not self:IsGardener()) then return false end
	self.plantedAt = time()
	if self.seq < 1 then self.seq = 1 end
	self:Save()
	self:Broadcast()
	return true
end

function WisdomModule:Remember(name, act, at)
	if type(name) ~= "string" or name == "" or name == "-" then return end
	if act ~= "W" and act ~= "F" then return end
	at = tonumber(at) or 0
	if at <= 0 then return end
	local top = self.log[#self.log]
	if top and top.name == name and top.act == act and top.at == at then return end
	self.log[#self.log + 1] = App.WisdomCareVo:new(name, act, at)
	while #self.log > 12 do table.remove(self.log, 1) end
end

function WisdomModule:Remain(act)
	local map = act == "F" and self.fert or self.water
	local cd = act == "F" and self.FERT_CD or self.WATER_CD
	local best = 0
	local rec = map and map[self:Me()]
	if rec and rec.last and rec.last > 0 then
		local elapsed = time() - rec.last
		if elapsed >= 0 and elapsed < cd then best = cd - elapsed end
	end
	local held = self.hold and self.hold[act] or 0
	if held > 0 then
		local elapsed = time() - held
		if elapsed >= 0 and elapsed < self.HOLD and (self.HOLD - elapsed) > best then
			best = self.HOLD - elapsed
		end
	end
	return best
end

function WisdomModule:ApplyCare(name, act, quiet)
	if act ~= "W" and act ~= "F" then return false end
	local map = act == "F" and self.fert or self.water
	local cd = act == "F" and self.FERT_CD or self.WATER_CD
	local gain = act == "F" and self.FERT_GAIN or self.WATER_GAIN
	local rec = map[name]
	local now = time()
	if rec and rec.last and rec.last > 0 then
		local elapsed = now - rec.last
		if elapsed >= 0 and elapsed < cd then
			if name == self:Me() then
				self:Note("还要等一等")
				if not quiet then
					self:Refresh()
					self:sync("wait")
				end
			else
				self:Send("Z|E|" .. name .. "|还要等一等")
			end
			return false
		end
	end
	if not rec then
		rec = App.WisdomTouchVo:new(0, 0)
		map[name] = rec
	end
	if self.plantedAt <= 0 then
		self.plantedAt = now
		if self.seq < 1 then self.seq = 1 end
	end
	rec.last = now
	rec.count = (rec.count or 0) + 1
	self.care = self.care + gain
	self.seq = (self.seq or 0) + 1
	self.lastName = name
	self.lastAct = act
	self.lastAt = now
	self:Remember(name, act, now)
	if name == self:Me() then
		self:Note(act == "F" and "施过肥了" or "浇过水了")
	end
	self:Save()
	if quiet then return true end
	self:Broadcast()
	self:Refresh()
	self:sync("care")
	return true
end

function WisdomModule:Queue(name, act)
	if #self.inbox >= 40 then return end
	for i = 1, #self.inbox do
		local row = self.inbox[i]
		if row.name == name and row.act == act then return end
	end
	self.inbox[#self.inbox + 1] = { name = name, act = act }
end

function WisdomModule:FlushInbox()
	local list = self.inbox or {}
	self.inbox = {}
	if not self.key then return end
	if not self:InGuild() then
		for i = 1, #list do
			if list[i].name == self:Me() then
				self:ApplyCare(self:Me(), list[i].act)
			end
		end
		return
	end
	if not self:IsGardener() then
		local sent = false
		for i = 1, #list do
			if list[i].name == self:Me() then
				if self:Send("Z|Q|" .. list[i].act) then
					sent = true
					self.hold[list[i].act] = time()
				end
			end
		end
		if sent then self:Note("已交给园丁") end
		return
	end
	local any = false
	for i = 1, #list do
		if self:ApplyCare(list[i].name, list[i].act, true) then any = true end
	end
	if any then
		self:Broadcast()
		self:Refresh()
		self:sync("care")
	end
end

function WisdomModule:FinishGrace()
	self.graced = true
	if not self:InGuild() then
		self:FlushInbox()
		return
	end
	self:Send("Z|P")
	if self:IsGardener() then
		self:Tend()
		self:FlushInbox()
	else
		self:FlushInbox()
		self:Send("Z|N")
	end
end

function WisdomModule:Care(act)
	self:Ensure()
	self:FollowGuild()
	if self.key == nil then
		self:Note("正在确认公会")
		self:Refresh()
		self:sync("wait")
		return false
	end
	if self:Remain(act) > 0 then
		self:Note("还要等一等")
		self:Refresh()
		self:sync("wait")
		return false
	end
	if not self.graced then
		self:Queue(self:Me(), act)
		self:Note("等园丁核对")
		self:Refresh()
		self:sync("wait")
		return true
	end
	if self:InGuild() and not self:IsGardener() then
		local ok = self:Send("Z|Q|" .. act)
		if ok then
			self.hold[act] = time()
			self:Note("已交给园丁")
		else
			self:Note("公会频道没发出去")
		end
		self:Refresh()
		self:sync("wait")
		return ok
	end
	return self:ApplyCare(self:Me(), act)
end

function WisdomModule:Water()
	return self:Care("W")
end

function WisdomModule:Fertilize()
	return self:Care("F")
end

function WisdomModule:Pick()
	self:Ensure()
	self:Refresh()
	local ready = self.model.fruitReady or 0
	if ready <= 0 then
		self:Note("果子还没熟")
		self:Refresh()
		self:sync("pick")
		return false
	end
	self.wisdom = (self.wisdom or 0) + ready
	self.seen = (self.seen or 0) + ready
	self.quote = TIPS[math.random(#TIPS)]
	self:Note("采下 " .. ready .. " 枚智慧果")
	self:Save()
	self:Refresh()
	self:sync("pick")
	return true
end

function WisdomModule:Watch(on)
	self:Ensure()
	self.watching = on and true or false
	if on and self:InGuild() then
		self:Send("Z|P")
		if self.graced then
			if self:IsGardener() then
				self:Tend()
				self:Broadcast()
			else
				self:Send("Z|N")
			end
		end
	end
	self:Refresh()
	self:sync("watch")
end

function WisdomModule:StageOf(growth)
	local stage, name = 1, STAGES[1][2]
	for i = 1, #STAGES do
		if growth >= STAGES[i][1] then
			stage = i
			name = STAGES[i][2]
		end
	end
	local nxt = STAGES[stage + 1]
	if not nxt then return stage, name, nil, nil end
	return stage, name, nxt[1], nxt[2]
end

function WisdomModule:CarerCount()
	local seen, n = {}, 0
	local function add(map)
		for name in pairs(map) do
			if not seen[name] then
				seen[name] = true
				n = n + 1
			end
		end
	end
	add(self.water)
	add(self.fert)
	return n
end

function WisdomModule:RankText()
	local score = {}
	local function add(map, key)
		for name, rec in pairs(map) do
			local row = score[name]
			if not row then
				row = { w = 0, f = 0 }
				score[name] = row
			end
			row[key] = rec.count or 0
		end
	end
	add(self.water, "w")
	add(self.fert, "f")
	local list = {}
	for name, row in pairs(score) do
		list[#list + 1] = { name = name, w = row.w, f = row.f, n = row.w + row.f }
	end
	if #list == 0 then return "还没有人照料" end
	table.sort(list, function(a, b)
		if a.n == b.n then return a.name < b.name end
		return a.n > b.n
	end)
	local lines = {}
	local n = math.min(5, #list)
	for i = 1, n do
		local row = list[i]
		lines[i] = string.format("%d  %s　浇%d　肥%d", i, row.name, row.w, row.f)
	end
	return table.concat(lines, "\n")
end

function WisdomModule:LogText()
	if #self.log == 0 then return "年轮上还是空白" end
	local lines = {}
	local shown = 0
	for i = #self.log, 1, -1 do
		shown = shown + 1
		if shown > 5 then break end
		local row = self.log[i]
		local word = row.act == "F" and "施肥" or "浇水"
		lines[#lines + 1] = word .. "　" .. row.name
	end
	return table.concat(lines, "\n")
end

function WisdomModule:Refresh()
	local idle, remain = 0, self.IDLE_STEP
	if self.plantedAt > 0 then
		local span = time() - self.plantedAt
		if span < 0 then span = 0 end
		idle = math.floor(span / self.IDLE_STEP)
		if idle > 20000 then idle = 20000 end
		remain = self.IDLE_STEP - (span % self.IDLE_STEP)
	end
	local growth = idle + (self.care or 0)
	local stage, name, nextAt, nextName = self:StageOf(growth)
	local total = math.floor(growth / self.FRUIT_STEP)
	local ready = math.max(0, total - (self.seen or 0))
	local waterSec = self:Remain("W")
	local fertSec = self:Remain("F")
	local model = self.model
	model.stage = stage
	model.stageName = name
	model.fruitReady = ready
	model.waterReady = waterSec <= 0
	model.heightText = string.format("树高 %d 尺", growth)
	if nextAt then
		model.nutrientText = string.format("挂机 %d　照料 %d　·　距%s还差 %d", idle, self.care or 0, nextName, nextAt - growth)
	else
		model.nutrientText = string.format("挂机 %d　照料 %d　·　已经通天", idle, self.care or 0)
	end
	if self.plantedAt > 0 then
		model.idleText = self:Clock(remain) .. " 后长一寸"
	else
		model.idleText = "还没种下"
	end
	model.fruitText = string.format("可采摘 %d 枚　·　悟性 %d", ready, self.wisdom or 0)
	model.quote = self.quote or ""
	model.cdText = "浇水 " .. (waterSec > 0 and self:Clock(waterSec) or "可浇")
		.. "　　施肥 " .. (fertSec > 0 and self:Clock(fertSec) or "可施")
	if self.note ~= "" and GetTime() <= (self.noteUntil or 0) then
		model.banner = self.note
	elseif self.key == nil then
		model.banner = "正在确认公会"
	elseif self:InGuild() then
		model.banner = string.format("园丁 %s　·　%d 人照料过", self:GardenerName(), self:CarerCount())
	else
		model.banner = "未入会，这棵树先自己养着"
	end
	model.rankText = self:RankText()
	model.logText = self:LogText()
	return model
end

function WisdomModule:OnSecond()
	if not self.loaded then return end
	self:FollowGuild()
	if not self.graced and self.graceUntil > 0 and GetTime() >= self.graceUntil then
		self:FinishGrace()
	end
	self:Refresh()
	self:sync("tick")
end

function WisdomModule:OnPulse()
	if not self.loaded or not self:InGuild() then return end
	self:Send("Z|P")
	if not self.graced then return end
	if not self:IsGardener() then
		if self.watching and self.plantedAt <= 0 then
			self:Send("Z|N")
		end
		return
	end
	self:Tend()
	if GetTime() - (self.lastBroadcast or 0) >= self.ANNOUNCE then
		self:Broadcast()
	end
end

function WisdomModule:Seen(sender, act)
	local now = GetTime()
	local key = tostring(sender) .. "\0" .. tostring(act)
	local prev = self._seenQ[key]
	if prev and now - prev < 2 then return true end
	self._seenQ[key] = now
	return false
end

function WisdomModule:OnSnapshot(p)
	local seq = tonumber(p[3])
	local planted = tonumber(p[4])
	local care = tonumber(p[5])
	if not seq or not planted or not care then return end
	if type(p[6]) ~= "string" or type(p[7]) ~= "string" then return end
	if seq <= 0 or seq > 10000000 then return end
	if planted <= 0 or planted > time() + 120 then return end
	if care < 0 or care > 1000000 then return end
	if seq < self.seq then
		self:OfferNewer()
		return
	end
	local newer = seq > self.seq
	local earlier = seq == self.seq and self.plantedAt > planted and care >= (self.care or 0)
	if not newer and not earlier then return end
	self.seq = seq
	self.plantedAt = planted
	self.care = care
	self.water = self:DecodeMap(p[6])
	self.fert = self:DecodeMap(p[7])
	local lastName = p[8]
	local lastAct = p[9]
	local lastAt = tonumber(p[10]) or 0
	if type(lastName) == "string" and lastName ~= "-" then
		self.lastName = lastName
	end
	if lastAct == "W" or lastAct == "F" then
		self.lastAct = lastAct
		self.lastAt = lastAt
		self:Remember(lastName, lastAct, lastAt)
	end
	self.hold.W = 0
	self.hold.F = 0
	self:Save()
	self:Refresh()
	self:sync("snap")
end

function WisdomModule:OnAsk()
	if not self.graced or not self:IsGardener() then return end
	if self.plantedAt <= 0 then
		self:Tend()
		return
	end
	if GetTime() - (self.lastBroadcast or 0) < 4 then return end
	self:Broadcast()
end

function WisdomModule:OnRequest(sender, act)
	if act ~= "W" and act ~= "F" then return end
	if not self.graced then
		self:Queue(sender, act)
		return
	end
	if not self:IsGardener() then return end
	if self:Seen(sender, act) then return end
	self:ApplyCare(sender, act)
end

function WisdomModule:OnDeny(p)
	if p[3] ~= self:Me() then return end
	local reason = p[4]
	if type(reason) ~= "string" or reason == "" then reason = "园丁没有收下" end
	self:Note(reason)
	self:Refresh()
	self:sync("deny")
end

function WisdomModule:OnMessage(text, sender, channel)
	if channel ~= App.SyncChannel.Guild.id then return end
	if type(text) ~= "string" or text:sub(1, 2) ~= "Z|" then return end
	if type(sender) ~= "string" or sender == "" then return end
	self:Ensure()
	self:FollowGuild()
	if not self:InGuild() then return end
	self.presence[sender] = GetTime()
	local p = { strsplit("|", text) }
	local kind = p[2]
	if kind == "H" then
		self:OnSnapshot(p)
	elseif kind == "N" then
		self:OnAsk()
	elseif kind == "Q" then
		self:OnRequest(sender, p[3])
	elseif kind == "E" then
		self:OnDeny(p)
	end
end

local inst = WisdomModule:new()
App._modules.Wisdom = inst
inst:enterModule()

local Net = App._modules.Net
if Net then
	Net:On(function(text, sender, channel)
		inst:OnMessage(text, sender, channel)
	end)
end
