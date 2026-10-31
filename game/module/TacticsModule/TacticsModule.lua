-- ============================================================
-- TacticsModule · 战术绘画板
--   笔权、笔画、队长裁决。本文件不画线，界面见 TacticsView。
--
-- 同步 · 队长权威 + 明文 D|
--   频道：只有一个队伍频道（有团队用 RAID，否则 PARTY，都没有才
--         INSTANCE_CHAT）。不进公会。前缀仍是 MZCHK，经 SendTo 发出。
--   封包：D|Q 请求，D|K 笔权，D|S 一笔，D|U 撤销，D|X 清空，
--         D|R 要快照，D|H 全量。不改成 ~S / ~D / ~T。
--   队长每 4 秒发 D|K。序号落后才发 D|R，队长至少隔 4 秒回一次 D|H。
--   只有 D|Q| 去重。旧序号丢掉，同一序号重复无害。
--   不在队伍里只在本机画，不发包。离开队伍或进入队伍都清空。
--   不写 MoZhanNianHuaDB。收包不进 EventManager。
--   本机：sync 把画布交给界面，不发插件消息。
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App

local Net = App._modules.Net

local TacticsModule = App.newclz("TacticsModule", App.AbstractModule)

TacticsModule.MAX_STROKES = 80
TacticsModule.MAX_POINTS = 80
TacticsModule.MIN_DIST = 8
TacticsModule.HOST_EVERY = 4
TacticsModule.ASK_EVERY = 4
TacticsModule.TEXT_MAX = 24
TacticsModule.PART_BUDGET = 180
TacticsModule.COLORS = {
	{ 0.106, 0.098, 0.086 },
	{ 0.702, 0.196, 0.157 },
	{ 0.176, 0.420, 0.435 },
	{ 0.545, 0.329, 0.180 },
	{ 0.710, 0.545, 0.216 },
}

local TOOLS = { P = true, L = true, A = true, R = true, E = true, T = true }

function TacticsModule:init()
	self.seq = 0
	self.holder = ""
	self.strokes = {}
	self.pending = nil
	self.retryStroke = nil
	self.pendingTries = 0
	self.pendingAt = 0
	self.lastK = 0
	self.lastH = 0
	self.lastAsk = 0
	self.lastCommitAt = 0
	self.acc = 0
	self._seen = {}
	self._lastSweep = 0
	self._snap = nil
	self._outbox = nil
	self._outboxSeq = -1
	self.model = {
		seq = 0,
		holder = "",
		strokes = self.strokes,
		pending = nil,
		canDraw = true,
		inGroup = false,
	}
	self.wasInside = self:InGroup()
	self.needHello = self.wasInside and not self:IsLeader()
	local mod = self
	App.system:On(App.NetEvents.GROUP_ROSTER_UPDATE, function()
		mod:OnRoster()
	end)
	self:BuildDriver()
	self:Publish("init")
end

function TacticsModule:BuildDriver()
	if self._ticking then return end
	self._ticking = true
	App:addManager(self)
end

function TacticsModule:Publish(why)
	self.model.seq = self.seq
	self.model.holder = self.holder or ""
	self.model.strokes = self.strokes
	self.model.pending = self.pending
	self.model.canDraw = self:CanDraw()
	self.model.inGroup = self:InGroup()
	self:sync(why)
end

function TacticsModule:ResetBoard()
	self.seq = 0
	self.holder = ""
	self.strokes = {}
	self.pending = nil
	self.retryStroke = nil
	self.pendingTries = 0
	self.pendingAt = 0
	self._snap = nil
	self._outbox = nil
	self._outboxSeq = -1
end

-- ------------------------------------------------------------
-- 队伍
-- ------------------------------------------------------------

function TacticsModule:Bare(name)
	if type(name) ~= "string" or name == "" then return "" end
	return name:match("^([^%-]+)") or name
end

function TacticsModule:Me()
	local name = (Net and Net:Me()) or UnitName("player") or "player"
	return self:Bare(name)
end

function TacticsModule:GroupChannel()
	local Channel = App.SyncChannel
	if IsInRaid() then return Channel.Raid.id end
	if IsInGroup() then return Channel.Party.id end
	if Net and Net:InInstanceGroup() then return Channel.InstanceChat.id end
end

function TacticsModule:InGroup()
	return self:GroupChannel() ~= nil
end

function TacticsModule:IsLeader()
	if not self:InGroup() then return true end
	if type(UnitIsGroupLeader) == "function" then
		return UnitIsGroupLeader("player") and true or false
	end
	if IsInRaid() and type(IsRaidLeader) == "function" then
		return IsRaidLeader() and true or false
	end
	if type(UnitIsPartyLeader) == "function" then
		return UnitIsPartyLeader("player") and true or false
	end
	return false
end

function TacticsModule:NameInGroup(name)
	name = self:Bare(name)
	if name == "" then return false end
	if name == self:Me() then return true end
	if IsInRaid() then
		local i = 1
		local n = GetNumGroupMembers()
		while i <= n do
			if self:Bare(UnitName("raid" .. i)) == name then return true end
			i = i + 1
		end
		return false
	end
	if IsInGroup() then
		local i = 1
		local n = GetNumSubgroupMembers()
		while i <= n do
			if self:Bare(UnitName("party" .. i)) == name then return true end
			i = i + 1
		end
	end
	return false
end

function TacticsModule:CanDraw()
	if not self:InGroup() then return true end
	return self.holder == self:Me()
end

function TacticsModule:LeaderName()
	if not self:InGroup() then return self:Me() end
	if type(UnitIsGroupLeader) ~= "function" then return nil end
	if UnitIsGroupLeader("player") then return self:Me() end
	local i, n, prefix = 1, 0, nil
	if IsInRaid() then
		n, prefix = GetNumGroupMembers(), "raid"
	elseif IsInGroup() then
		n, prefix = GetNumSubgroupMembers(), "party"
	end
	while prefix and i <= n do
		local unit = prefix .. i
		if UnitIsGroupLeader(unit) then
			return self:Bare(UnitName(unit))
		end
		i = i + 1
	end
end

function TacticsModule:FromLeader(sender)
	local name = self:LeaderName()
	if not name or name == "" then return true end
	return name == self:Bare(sender)
end

function TacticsModule:OnRoster()
	local inside = self:InGroup()
	if inside ~= self.wasInside then
		self.wasInside = inside
		self:ResetBoard()
		self.lastAsk = 0
		self:Publish("roster")
		if inside and not self:IsLeader() then
			self:RequestSnapshot()
		elseif inside then
			self:SendK()
		end
		return
	end
	if inside and self:IsLeader() and self.holder ~= "" and not self:NameInGroup(self.holder) then
		self.holder = ""
		self:SendK()
		self:Publish("pen")
	end
end

-- ------------------------------------------------------------
-- 编码
-- ------------------------------------------------------------

function TacticsModule:ClipChars(text, maxChars)
	local n, i = 0, 1
	local len = #text
	while i <= len do
		local b = text:byte(i)
		local w = 1
		if b >= 240 then w = 4
		elseif b >= 224 then w = 3
		elseif b >= 192 then w = 2
		end
		if i + w - 1 > len then w = 1 end
		if n + 1 > maxChars then return text:sub(1, i - 1) end
		n = n + 1
		i = i + w
	end
	return text
end

function TacticsModule:CleanText(text)
	text = tostring(text or "")
	text = text:gsub("[|%c;/]", "")
	if text == "" then return "" end
	return self:ClipChars(text, self.TEXT_MAX)
end

function TacticsModule:CleanPoints(tool, points)
	local raw = {}
	local i = 1
	local src = points or {}
	while i <= #src do
		local p = src[i]
		local x = math.floor(tonumber(p and p.x) or -1)
		local y = math.floor(tonumber(p and p.y) or -1)
		if x >= 0 and x <= 999 and y >= 0 and y <= 999 then
			raw[#raw + 1] = { x = x, y = y }
		end
		i = i + 1
	end
	if #raw == 0 then return {} end
	if tool ~= "P" then
		if #raw == 1 then return { raw[1] } end
		return { raw[1], raw[#raw] }
	end
	local out = { raw[1] }
	local min2 = self.MIN_DIST * self.MIN_DIST
	i = 2
	while i <= #raw - 1 do
		local last = out[#out]
		local p = raw[i]
		local dx = p.x - last.x
		local dy = p.y - last.y
		if dx * dx + dy * dy >= min2 then
			out[#out + 1] = p
		end
		if #out >= self.MAX_POINTS - 1 then break end
		i = i + 1
	end
	if #raw >= 2 then
		out[#out + 1] = raw[#raw]
	end
	while #out > self.MAX_POINTS do
		table.remove(out, 2)
	end
	return out
end

function TacticsModule:Valid(tool, points, text)
	if not TOOLS[tool] then return false end
	if tool == "T" then
		return #points >= 1 and text ~= ""
	end
	if tool == "P" then
		return #points >= 1
	end
	if #points < 2 then return false end
	return points[1].x ~= points[2].x or points[1].y ~= points[2].y
end

function TacticsModule:Normalize(tool, color, points, text)
	if not TOOLS[tool] then return nil end
	color = math.floor(tonumber(color) or 1)
	if color < 1 or color > #self.COLORS then color = 1 end
	points = self:CleanPoints(tool, points)
	text = self:CleanText(text)
	if not self:Valid(tool, points, text) then return nil end
	return tool, color, points, text
end

function TacticsModule:EncodePoints(tool, points, text)
	if tool == "T" then
		local p = points[1]
		return string.format("%d,%d;%s", p.x, p.y, text or "")
	end
	local t = {}
	local i = 1
	while i <= #points do
		t[i] = string.format("%d,%d", points[i].x, points[i].y)
		i = i + 1
	end
	return table.concat(t, ";")
end

function TacticsModule:DecodePayload(tool, payload)
	if type(payload) ~= "string" or not TOOLS[tool] then return nil, "" end
	if #payload > 2000 then return nil, "" end
	if tool == "T" then
		local x, y, text = payload:match("^(%d+),(%d+);(.*)$")
		x, y = tonumber(x), tonumber(y)
		if not x or not y then return nil, "" end
		return { { x = x, y = y } }, text or ""
	end
	local points = {}
	for xs, ys in payload:gmatch("(%d+),(%d+)") do
		points[#points + 1] = { x = tonumber(xs), y = tonumber(ys) }
	end
	if #points == 0 then return nil, "" end
	return points, ""
end

function TacticsModule:EncodeStroke(stroke)
	local payload = self:EncodePoints(stroke.tool, stroke.points, stroke.text)
	return string.format("%d^%s^%d^%s", stroke.id or 0, stroke.tool, stroke.color, payload)
end

function TacticsModule:DecodeStroke(piece)
	local id, tool, color, payload = piece:match("^(%d+)%^([PLARET])%^(%d)%^(.*)$")
	if not id then return nil end
	local points, text = self:DecodePayload(tool, payload)
	if not points then return nil end
	points = self:CleanPoints(tool, points)
	text = self:CleanText(text)
	if not self:Valid(tool, points, text) then return nil end
	color = tonumber(color) or 1
	if color < 1 or color > #self.COLORS then color = 1 end
	return App.TacticsStrokeVo:new(tonumber(id), tool, color, points, text)
end

function TacticsModule:Rest(parts, from)
	if not parts[from] then return "" end
	if not parts[from + 1] then return parts[from] end
	local t = {}
	local i = from
	while i <= #parts do
		t[#t + 1] = parts[i]
		i = i + 1
	end
	return table.concat(t, "|")
end

function TacticsModule:SameStroke(stroke, tool, color, payload)
	if not stroke then return false end
	if stroke.tool ~= tool or stroke.color ~= color then return false end
	return self:EncodePoints(stroke.tool, stroke.points, stroke.text) == payload
end

-- ------------------------------------------------------------
-- 发送
-- ------------------------------------------------------------

function TacticsModule:Send(text)
	if not self:InGroup() then return false end
	if type(text) ~= "string" or text == "" or text:sub(1, 1) == "~" then return false end
	local channel = self:GroupChannel()
	if not channel or not Net then return false end
	return Net:SendTo(channel, text)
end

function TacticsModule:SendK()
	if not self:InGroup() or not self:IsLeader() then return end
	self.lastK = GetTime()
	self:Send(string.format("D|K|%d|%s", self.seq, self.holder or ""))
end

function TacticsModule:EncodeRequest(stroke)
	return string.format(
		"D|Q|S|%s|%d|%s",
		stroke.tool,
		stroke.color,
		self:EncodePoints(stroke.tool, stroke.points, stroke.text)
	)
end

function TacticsModule:SnapshotChunks()
	if #self.strokes == 0 then return { "" } end
	local parts = {}
	local cur = ""
	local i = 1
	while i <= #self.strokes do
		local piece = self:EncodeStroke(self.strokes[i])
		local nextPiece = (cur == "") and piece or (cur .. "/" .. piece)
		if cur ~= "" and #nextPiece > self.PART_BUDGET then
			parts[#parts + 1] = cur
			cur = piece
		else
			cur = nextPiece
		end
		i = i + 1
	end
	if cur ~= "" then parts[#parts + 1] = cur end
	if #parts == 0 then parts[1] = "" end
	return parts
end

-- 全量按片进队列，每秒只放一片。一次塞满会顶过 NetManager 的 60 条上限。
function TacticsModule:QueueSnapshot()
	if not self:IsLeader() or not self:InGroup() then return end
	if self._outbox and self._outboxSeq == self.seq and #self._outbox > 0 then return end
	if self._outboxSeq == self.seq and GetTime() - (self.lastH or 0) < self.HOST_EVERY then
		return
	end
	local chunks = self:SnapshotChunks()
	local n = #chunks
	local holder = self.holder or ""
	local box = {}
	local i = 1
	while i <= n do
		box[i] = string.format("D|H|%d|%s|%d|%d|%s", self.seq, holder, i, n, chunks[i])
		i = i + 1
	end
	self.lastH = GetTime()
	self._outbox = box
	self._outboxSeq = self.seq
end

function TacticsModule:FlushSnapshot()
	local box = self._outbox
	if not box or #box == 0 then
		self._outbox = nil
		return
	end
	if self._outboxSeq ~= self.seq then
		self._outbox = nil
		return
	end
	local text = box[1]
	if not self:Send(text) then return end
	table.remove(box, 1)
	if #box == 0 then self._outbox = nil end
end

function TacticsModule:RequestSnapshot()
	if self:IsLeader() or not self:InGroup() then return end
	local now = GetTime()
	if now - (self.lastAsk or 0) < self.ASK_EVERY then return end
	self.lastAsk = now
	self:Send("D|R|" .. tostring(self.seq))
end

function TacticsModule:PushStroke(stroke)
	self.strokes[#self.strokes + 1] = stroke
	while #self.strokes > self.MAX_STROKES do
		table.remove(self.strokes, 1)
	end
end

function TacticsModule:CommitLocal(tool, color, points, text)
	self.seq = self.seq + 1
	local stroke = App.TacticsStrokeVo:new(self.seq, tool, color, points, text)
	self._outbox = nil
	self:PushStroke(stroke)
	self.lastCommitAt = GetTime()
	if self:InGroup() and self:IsLeader() then
		self:Send(string.format(
			"D|S|%d|%d|%s|%d|%s",
			self.seq,
			stroke.id,
			tool,
			color,
			self:EncodePoints(tool, points, text)
		))
	end
	self:Publish("stroke")
	return true
end

function TacticsModule:RepeatStroke(sender, tool, color, payload)
	local last = self.strokes[#self.strokes]
	if not last or self.holder ~= sender then return false end
	if GetTime() - (self.lastCommitAt or 0) >= 10 then return false end
	return self:SameStroke(last, tool, color, payload)
end

function TacticsModule:ApplyUndo()
	if #self.strokes == 0 then return false end
	local last = table.remove(self.strokes)
	self._outbox = nil
	self.seq = self.seq + 1
	if self:InGroup() and self:IsLeader() then
		self:Send(string.format("D|U|%d|%d", self.seq, last.id or 0))
	end
	self:Publish("undo")
	return true
end

function TacticsModule:ApplyClear()
	if #self.strokes == 0 then return false end
	self.strokes = {}
	self._outbox = nil
	self.seq = self.seq + 1
	if self:InGroup() and self:IsLeader() then
		self:Send(string.format("D|X|%d", self.seq))
	end
	self:Publish("clear")
	return true
end

-- ------------------------------------------------------------
-- 界面调用
-- ------------------------------------------------------------

function TacticsModule:TakePen()
	if not self:InGroup() then return false end
	if self.holder == self:Me() then return true end
	if self:IsLeader() then
		if self.holder ~= "" and self:NameInGroup(self.holder) then return false end
		self.holder = self:Me()
		self:SendK()
		self:Publish("pen")
		return true
	end
	self:Send("D|Q|TAKE")
	return true
end

function TacticsModule:DropPen()
	if not self:InGroup() then return false end
	if self.holder ~= self:Me() then return false end
	if self:IsLeader() then
		self.holder = ""
		self:SendK()
		self:Publish("pen")
		return true
	end
	self:Send("D|Q|DROP")
	return true
end

function TacticsModule:SubmitStroke(tool, color, points, text)
	if not self:CanDraw() then return false end
	if self.pending or self.retryStroke then return false end
	tool, color, points, text = self:Normalize(tool, color, points, text)
	if not tool then return false end
	if not self:InGroup() or self:IsLeader() then
		return self:CommitLocal(tool, color, points, text)
	end
	local stroke = App.TacticsStrokeVo:new(0, tool, color, points, text)
	stroke.pending = true
	self.pending = stroke
	self.pendingTries = 0
	self.pendingAt = GetTime()
	self:Send(self:EncodeRequest(stroke))
	self:Publish("pending")
	return true
end

function TacticsModule:Undo()
	if not self:CanDraw() then return false end
	if self.pending or self.retryStroke then return false end
	if #self.strokes == 0 then return false end
	if not self:InGroup() or self:IsLeader() then
		return self:ApplyUndo()
	end
	self:Send("D|Q|U")
	return true
end

function TacticsModule:ClearBoard()
	if not self:CanDraw() then return false end
	local hadPending = self.pending or self.retryStroke
	self.pending = nil
	self.retryStroke = nil
	self.pendingTries = 0
	if hadPending then self:Publish("pending") end
	if #self.strokes == 0 then return hadPending and true or false end
	if not self:InGroup() or self:IsLeader() then
		return self:ApplyClear()
	end
	self:Send("D|Q|X")
	return true
end

function TacticsModule:FailPending()
	if not self:CanDraw() or not self:InGroup() or self:IsLeader() then
		self.pending = nil
		self.retryStroke = nil
		self.pendingTries = 0
		self:Publish("drop")
		return
	end
	if self.pending then
		local stroke = self.pending
		self.pending = nil
		self.pendingTries = 1
		self.retryStroke = stroke
		self.pendingAt = GetTime()
		self:Publish("drop")
		self:Send(self:EncodeRequest(stroke))
		return
	end
	if self.retryStroke then
		self.retryStroke = nil
		self.pendingTries = 0
		self:Publish("drop")
	end
end

-- ------------------------------------------------------------
-- 收包
-- ------------------------------------------------------------

function TacticsModule:DuplicateRequest(sender, text)
	if type(text) ~= "string" or text:sub(1, 4) ~= "D|Q|" then return false end
	local now = GetTime()
	local seen = self._seen
	if now - (self._lastSweep or 0) > 10 then
		self._lastSweep = now
		for k, t in pairs(seen) do
			if now - t > 1.5 then seen[k] = nil end
		end
	end
	local key = tostring(sender) .. "\0" .. text
	local t = seen[key]
	if t and now - t <= 1.5 then return true end
	seen[key] = now
	return false
end

function TacticsModule:AcceptSeq(seq)
	seq = tonumber(seq) or 0
	if seq <= self.seq then return false end
	if seq > self.seq + 1 then
		self:RequestSnapshot()
		return false
	end
	return true
end

function TacticsModule:OnRequest(p, sender)
	if not self:IsLeader() or not self:InGroup() then return end
	local act = p[3]
	if act == "TAKE" then
		if self.holder ~= "" and self.holder ~= sender and self:NameInGroup(self.holder) then
			self:SendK()
			return
		end
		if self.holder == sender then
			self:SendK()
			return
		end
		self.holder = sender
		self:SendK()
		self:Publish("pen")
	elseif act == "DROP" then
		if self.holder ~= sender then return end
		self.holder = ""
		self:SendK()
		self:Publish("pen")
	elseif act == "S" then
		if self.holder ~= sender then return end
		local decoded, decodedText = self:DecodePayload(p[4], self:Rest(p, 6))
		if not decoded then return end
		local tool, color, points, text = self:Normalize(p[4], p[5], decoded, decodedText)
		if not tool then return end
		local payload = self:EncodePoints(tool, points, text)
		if self:RepeatStroke(sender, tool, color, payload) then return end
		self:CommitLocal(tool, color, points, text)
	elseif act == "U" then
		if self.holder ~= sender then return end
		self:ApplyUndo()
	elseif act == "X" then
		if self.holder ~= sender then return end
		self:ApplyClear()
	end
end

function TacticsModule:OnPen(p)
	if self:IsLeader() then return end
	local seq = tonumber(p[3]) or 0
	local holder = p[4] or ""
	if seq < self.seq then return end
	local holderChanged = self.holder ~= holder
	self.holder = holder
	if seq > self.seq then
		self:Publish("pen")
		self:RequestSnapshot()
		return
	end
	if (self.pending or self.retryStroke) and GetTime() - (self.pendingAt or 0) >= self.HOST_EVERY then
		self:FailPending()
		return
	end
	if holderChanged then self:Publish("pen") end
end

function TacticsModule:OnStroke(p)
	if self:IsLeader() then return end
	local seq = tonumber(p[3]) or 0
	if not self:AcceptSeq(seq) then return end
	local id = tonumber(p[4]) or 0
	local payload = self:Rest(p, 7)
	local decoded, decodedText = self:DecodePayload(p[5], payload)
	if not decoded then return end
	local tool, color, points, text = self:Normalize(p[5], p[6], decoded, decodedText)
	if not tool then return end
	payload = self:EncodePoints(tool, points, text)
	self.seq = seq
	if self:SameStroke(self.pending, tool, color, payload) then
		self.pending = nil
	end
	if self:SameStroke(self.retryStroke, tool, color, payload) then
		self.retryStroke = nil
		self.pendingTries = 0
	end
	self:PushStroke(App.TacticsStrokeVo:new(id, tool, color, points, text))
	self:Publish("stroke")
end

function TacticsModule:OnUndo(p)
	if self:IsLeader() then return end
	local seq = tonumber(p[3]) or 0
	if not self:AcceptSeq(seq) then return end
	local id = tonumber(p[4]) or 0
	self.seq = seq
	local i = #self.strokes
	while i >= 1 do
		if self.strokes[i].id == id then
			table.remove(self.strokes, i)
			break
		end
		i = i - 1
	end
	self:Publish("undo")
end

function TacticsModule:OnClear(p)
	if self:IsLeader() then return end
	local seq = tonumber(p[3]) or 0
	if not self:AcceptSeq(seq) then return end
	self.seq = seq
	self.strokes = {}
	self.pending = nil
	self.retryStroke = nil
	self:Publish("clear")
end

function TacticsModule:OnAsk(p, sender)
	if not self:IsLeader() or not self:InGroup() then return end
	local their = tonumber(p[3]) or 0
	-- 队长重载后序号从 0 开始，别人手里的笔画还在。先把序号抬过去，
	-- 否则新的一笔会被当成旧包丢掉。空画布不回写，免得把别人擦掉。
	if their > self.seq and #self.strokes == 0 then
		self.seq = their
		self:SendK()
		self:Publish("seq")
		return
	end
	if their >= self.seq then return end
	self:QueueSnapshot()
end

function TacticsModule:TakeSnapshot(p)
	if self:IsLeader() then return end
	local seq = tonumber(p[3]) or 0
	if seq <= self.seq then return end
	local holder = p[4] or ""
	local part = tonumber(p[5]) or 0
	local total = tonumber(p[6]) or 0
	local body = self:Rest(p, 7)
	if part < 1 or total < 1 or part > total or total > 40 then return end
	local box = self._snap
	if box and seq < box.seq then return end
	if not box or box.seq ~= seq then
		box = { seq = seq, holder = holder, total = total, parts = {}, got = 0 }
		self._snap = box
	end
	if total ~= box.total then return end
	if not box.parts[part] then
		box.parts[part] = body
		box.got = box.got + 1
	end
	if box.got < box.total then return end
	local list = {}
	local i = 1
	while i <= box.total do
		if box.parts[i] == nil then return end
		list[i] = box.parts[i]
		i = i + 1
	end
	local strokes = {}
	local joined = table.concat(list, "/")
	if joined ~= "" then
		for piece in joined:gmatch("[^/]+") do
			local stroke = self:DecodeStroke(piece)
			if stroke then strokes[#strokes + 1] = stroke end
		end
	end
	self.strokes = strokes
	self.seq = seq
	self.holder = holder
	self.pending = nil
	self.retryStroke = nil
	self.pendingTries = 0
	self._snap = nil
	self:Publish("snapshot")
end

function TacticsModule:OnMessage(text, sender)
	if not self:InGroup() then return end
	if type(text) ~= "string" or text:sub(1, 2) ~= "D|" then return end
	if self:DuplicateRequest(sender, text) then return end
	local p = { strsplit("|", text) }
	local kind = p[2]
	if kind == "Q" then
		self:OnRequest(p, sender)
	elseif kind == "R" then
		self:OnAsk(p, sender)
	elseif not self:FromLeader(sender) then
		return
	elseif kind == "K" then
		self:OnPen(p)
	elseif kind == "S" then
		self:OnStroke(p)
	elseif kind == "U" then
		self:OnUndo(p)
	elseif kind == "X" then
		self:OnClear(p)
	elseif kind == "H" then
		self:TakeSnapshot(p)
	end
end

function TacticsModule:update(elapsed)
	self.acc = (self.acc or 0) + (elapsed or 0)
	if self.acc < 1 then return end
	self.acc = 0
	if self.needHello then
		self.needHello = false
		self:RequestSnapshot()
	end
	if not self:InGroup() then return end
	local now = GetTime()
	if self:IsLeader() then
		self:FlushSnapshot()
		if now - (self.lastK or 0) >= self.HOST_EVERY then
			self:SendK()
		end
		if self.holder ~= "" and not self:NameInGroup(self.holder) then
			self.holder = ""
			self:SendK()
			self:Publish("pen")
		end
		return
	end
	if (self.pending or self.retryStroke) and now - (self.pendingAt or 0) >= 8 then
		self:FailPending()
	end
end

local inst = TacticsModule:new("Tactics")
App._modules.Tactics = inst
inst:enterModule()

if Net then
	Net:On(function(text, sender)
		inst:OnMessage(text, sender)
	end)
end
