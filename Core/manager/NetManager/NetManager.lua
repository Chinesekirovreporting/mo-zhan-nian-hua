-- ============================================================
-- Net · 通信通道（AddOn Message）
-- 只走插件消息，不把数据打进可见聊天。
-- 短明文仍是 Send：跳棋的 H/B/C/Q/W/P/E/R 不改封包。
-- 超长正文自动切片，收齐再交给原来的 "message"。
-- 结构化数据走快照、增量、事务。发出去之前限速排队。
-- 收到的包在本对象上派发，不进 EventManager。
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App
local Channel = App.SyncChannel

local NetManager = App.Class("NetManager", App.Manager)

NetManager.ALPH = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
NetManager.MIN_GAP = 0.12
NetManager.MAX_QUEUE = 60
NetManager.CHUNK = 200
NetManager.MAX_BODY = 8000
NetManager.MAX_PARTS = 40
NetManager.PART_TTL = 8
NetManager.TX_RETRY = 4
NetManager.TX_WAIT = 1.2
NetManager.TX_TTL = 30
NetManager.WINDOW = 64

function NetManager:ctor()
	App.Manager.ctor(self)
	self.PREFIX = "MZCHK"
	self.MAXLEN = 240
	self._prefixOK = false
	self._queue = {}
	self._nextSendAt = 0
	self._parts = {}
	self._tx = {}
	self._txSeq = 0
	self._doneTx = {}
	self._fid = 0
	self._localVer = {}
	self._remoteVer = {}
	self._b64map = nil
	self:_registerPrefix()
	self:_bindAddon()
end

function NetManager:update(_dt)
	self:Flush()
	self:RetryTx()
	self:SweepParts()
end

function NetManager:_registerPrefix()
	if self._prefixOK then return true end
	local api = (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) or RegisterAddonMessagePrefix
	if type(api) ~= "function" then return false end
	self._prefixOK = pcall(api, self.PREFIX) and true or false
	return self._prefixOK
end

function NetManager:Me()
	return UnitName("player") or "player"
end

--- 当前可用的广播频道；nil 表示孤身一人（只能本机演练）
function NetManager:Channel()
	local list = self:Channels()
	return list[1]
end

--- 所有可用频道（团队/队伍 + 公会）。
--- 副本队伍只有在没有团队/小队频道时才用，避免同一条包走两次。
function NetManager:Channels()
	local list = {}
	local inRaid = type(IsInRaid) == "function" and IsInRaid()
	local inParty = type(IsInGroup) == "function" and IsInGroup()
	if inRaid then
		list[#list + 1] = Channel.Raid.id
	elseif inParty then
		list[#list + 1] = Channel.Party.id
	elseif self:InInstanceGroup() then
		list[#list + 1] = Channel.InstanceChat.id
	end
	if type(IsInGuild) == "function" and IsInGuild() then
		list[#list + 1] = Channel.Guild.id
	end
	return list
end

function NetManager:InInstanceGroup()
	if not LE_PARTY_CATEGORY_INSTANCE then return false end
	if type(IsInGroup) ~= "function" then return false end
	local ok, inside = pcall(IsInGroup, LE_PARTY_CATEGORY_INSTANCE)
	return ok and inside and true or false
end

function NetManager:Available()
	return #self:Channels() > 0
end

function NetManager:TopicOk(topic)
	return type(topic) == "string" and topic:match("^[%w_]+$") ~= nil and #topic <= 24
end

-- ------------------------------------------------------------
-- 发送
-- ------------------------------------------------------------

--- 短明文，或超长时自动切片。跳棋继续用这个。
function NetManager:Send(text)
	if type(text) ~= "string" or text == "" then return false end
	if text:sub(1, 1) == "~" then return false end
	return self:SendFramed(text)
end

--- 只发到一个频道。智慧树用公会，不进队伍频道。
function NetManager:SendTo(channel, text)
	if type(channel) ~= "string" or channel == "" then return false end
	if type(text) ~= "string" or text == "" or text:sub(1, 1) == "~" then return false end
	return self:SendFramed(text, channel)
end

--- 点对点插件消息，对方看不到聊天文字。
function NetManager:SendWhisper(name, text)
	if type(name) ~= "string" or name == "" then return false end
	if type(text) ~= "string" or text == "" or #text > self.MAXLEN then return false end
	if text:sub(1, 1) == "~" then return false end
	return self:Enqueue(text, Channel.Whisper.id, name)
end

--- 整包快照。返回是否入队，以及版本号。
function NetManager:SendSnapshot(topic, value)
	if not self:TopicOk(topic) then return false end
	local packed = self:Pack(value)
	if not packed then return false end
	local ver = (self._localVer[topic] or 0) + 1
	local body = string.format("~S|%s|%d|%s", topic, ver, packed)
	if not self:SendFramed(body) then return false end
	self._localVer[topic] = ver
	return true, ver
end

--- 相对 baseVer 的增量。baseVer 不传时用本机上次发出的版本。
function NetManager:SendDelta(topic, value, baseVer)
	if not self:TopicOk(topic) then return false end
	baseVer = tonumber(baseVer) or self._localVer[topic]
	if not baseVer then return false end
	local packed = self:Pack(value)
	if not packed then return false end
	local ver = baseVer + 1
	local body = string.format("~D|%s|%d|%d|%s", topic, ver, baseVer, packed)
	if not self:SendFramed(body) then return false end
	self._localVer[topic] = ver
	return true, ver
end

--- 发出去后等对方回执。失败或超时回调 false。
function NetManager:Commit(topic, value, onDone)
	if not self:TopicOk(topic) then return false end
	local packed = self:Pack(value)
	if not packed then return false end
	self._txSeq = self._txSeq + 1
	local tx = self._txSeq
	local body = string.format("~T|%d|%s|%s", tx, topic, packed)
	if not self:SendFramed(body) then return false end
	self._tx[tx] = { body = body, tries = 1, at = GetTime(), onDone = onDone }
	return true, tx
end

function NetManager:SendFramed(body, channel)
	if type(body) ~= "string" or body == "" or #body > self.MAX_BODY then return false end
	if #body <= self.MAXLEN then return self:Enqueue(body, channel) end
	return self:EnqueueParts(body, channel)
end

function NetManager:EnqueueParts(body, channel)
	local chunk = self.CHUNK
	local n = math.ceil(#body / chunk)
	if n < 2 or n > self.MAX_PARTS then return false end
	self._fid = (self._fid % 65535) + 1
	local fid = string.format("%04x", self._fid)
	local pieces = {}
	local i = 1
	while i <= n do
		local part = body:sub((i - 1) * chunk + 1, i * chunk)
		local head = string.format("~F|%s|%d|%d|%s|", fid, i, n, self:Sum(part))
		pieces[i] = head .. part
		if #pieces[i] > self.MAXLEN then return false end
		i = i + 1
	end
	local chans = channel and { channel } or self:Channels()
	if #chans == 0 then return false end
	if #self._queue + n * #chans > self.MAX_QUEUE then return false end
	i = 1
	while i <= n do
		if channel then
			if not self:Enqueue(pieces[i], channel) then return false end
		elseif not self:Enqueue(pieces[i]) then
			return false
		end
		i = i + 1
	end
	return true
end

function NetManager:Enqueue(text, channel, target)
	if not self:_registerPrefix() then return false end
	local jobs = {}
	if channel then
		jobs[1] = { channel = channel, target = target }
	else
		local chans = self:Channels()
		local i = 1
		while i <= #chans do
			jobs[i] = { channel = chans[i] }
			i = i + 1
		end
	end
	if #jobs == 0 then return false end
	if #self._queue + #jobs > self.MAX_QUEUE then return false end
	local i = 1
	while i <= #jobs do
		self._queue[#self._queue + 1] = {
			text = text,
			channel = jobs[i].channel,
			target = jobs[i].target,
		}
		i = i + 1
	end
	return true
end

function NetManager:Flush()
	local now = GetTime()
	if now < (self._nextSendAt or 0) then return end
	local job = table.remove(self._queue, 1)
	if not job then return end
	local api = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
	if type(api) ~= "function" then
		table.insert(self._queue, 1, job)
		self._nextSendAt = now + 1
		return
	end
	pcall(api, self.PREFIX, job.text, job.channel, job.target)
	self._nextSendAt = now + self.MIN_GAP
end

-- ------------------------------------------------------------
-- 序列化 / 压缩 / 可打印编码。实现在 NetCodec，这里只转发。
-- ------------------------------------------------------------

function NetManager:WriteValue(value)
	return App.NetCodec.WriteValue(self, value)
end

function NetManager:ReadValue(str, i)
	return App.NetCodec.ReadValue(self, str, i)
end

function NetManager:Sum(text)
	return App.NetCodec.Sum(self, text)
end

function NetManager:Compress(src)
	return App.NetCodec.Compress(self, src)
end

function NetManager:Decompress(src)
	return App.NetCodec.Decompress(self, src)
end

function NetManager:Encode64(data)
	return App.NetCodec.Encode64(self, data)
end

function NetManager:Decode64(data)
	return App.NetCodec.Decode64(self, data)
end

function NetManager:Pack(value)
	return App.NetCodec.Pack(self, value)
end

function NetManager:Unpack(text)
	return App.NetCodec.Unpack(self, text)
end
function NetManager:On(fn, thisArg)
	if type(fn) ~= "function" then return end
	return self:on("message", fn, thisArg)
end

function NetManager:Fire(text, sender, channel)
	self:emit("message", text, sender, channel)
end

function NetManager:Dispatch(body, sender, channel)
	local head = body:sub(1, 2)
	if head == "~F" then
		self:OnFragment(body, sender, channel)
		return
	end
	if head == "~S" then
		self:OnSnapshot(body, sender)
		return
	end
	if head == "~D" then
		self:OnDelta(body, sender)
		return
	end
	if head == "~T" then
		self:OnCommit(body, sender)
		return
	end
	if head == "~A" then
		self:OnAck(body, sender)
		return
	end
	self:Fire(body, sender, channel)
end

function NetManager:OnFragment(body, sender, channel)
	local fid, idx, count, sum, chunk = body:match("^~F|(%x+)|(%d+)|(%d+)|(%x%x%x%x)|(.*)$")
	idx = tonumber(idx)
	count = tonumber(count)
	if not fid or not idx or not count then return end
	if idx < 1 or idx > count or count > self.MAX_PARTS or count < 2 then return end
	if self:Sum(chunk) ~= sum then return end
	local key = sender .. "|" .. fid
	local box = self._parts[key]
	if not box then
		box = { n = count, got = {}, at = GetTime() }
		self._parts[key] = box
	end
	if box.n ~= count then return end
	box.got[idx] = chunk
	box.at = GetTime()
	local full = ""
	local i = 1
	while i <= count do
		if not box.got[i] then return end
		full = full .. box.got[i]
		i = i + 1
	end
	self._parts[key] = nil
	self:Dispatch(full, sender, channel)
end

function NetManager:OnSnapshot(body, sender)
	local topic, ver, packed = body:match("^~S|([%w_]+)|(%d+)|(.*)$")
	ver = tonumber(ver)
	if not topic or not ver then return end
	local value, ok = self:Unpack(packed)
	if not ok then return end
	local key = sender .. "|" .. topic
	local cur = self._remoteVer[key] or 0
	if ver <= cur then return end
	self._remoteVer[key] = ver
	self:emit("snapshot", topic, value, ver, sender)
end

function NetManager:OnDelta(body, sender)
	local topic, ver, baseVer, packed = body:match("^~D|([%w_]+)|(%d+)|(%d+)|(.*)$")
	ver = tonumber(ver)
	baseVer = tonumber(baseVer)
	if not topic or not ver or not baseVer then return end
	local key = sender .. "|" .. topic
	local cur = self._remoteVer[key] or 0
	if ver <= cur then return end
	if baseVer ~= cur then
		self:emit("resync", topic, sender, cur, baseVer)
		return
	end
	local value, ok = self:Unpack(packed)
	if not ok then return end
	self._remoteVer[key] = ver
	self:emit("delta", topic, value, ver, baseVer, sender)
end

function NetManager:OnCommit(body, sender)
	local tx, topic, packed = body:match("^~T|(%d+)|([%w_]+)|(.*)$")
	if not tx or not topic then return end
	local value, ok = self:Unpack(packed)
	self:Enqueue(string.format("~A|%s|%s", tx, ok and "1" or "0"))
	if not ok then return end
	local mark = sender .. "|" .. tx
	if self._doneTx[mark] then return end
	self._doneTx[mark] = GetTime()
	self:emit("commit", topic, value, tonumber(tx), sender)
end

function NetManager:OnAck(body, sender)
	local tx, ok = body:match("^~A|(%d+)|([01])$")
	tx = tonumber(tx)
	if not tx then return end
	local pending = self._tx[tx]
	if not pending then return end
	self._tx[tx] = nil
	local good = ok == "1"
	self:emit("ack", tx, good, sender)
	if pending.onDone then pending.onDone(good, tx) end
end

function NetManager:RetryTx()
	if #self._queue > 0 then return end
	local now = GetTime()
	local due = {}
	for tx, pending in pairs(self._tx) do
		if now - pending.at >= self.TX_WAIT then
			due[#due + 1] = tx
		end
	end
	local i = 1
	while i <= #due do
		local tx = due[i]
		local pending = self._tx[tx]
		if pending then
			if pending.tries >= self.TX_RETRY then
				self._tx[tx] = nil
				self:emit("ack", tx, false, nil)
				if pending.onDone then pending.onDone(false, tx) end
			elseif self:SendFramed(pending.body) then
				pending.tries = pending.tries + 1
				pending.at = now
			end
		end
		i = i + 1
	end
end

function NetManager:SweepParts()
	local now = GetTime()
	for key, box in pairs(self._parts) do
		if now - box.at > self.PART_TTL then
			self._parts[key] = nil
		end
	end
	for mark, at in pairs(self._doneTx) do
		if now - at > self.TX_TTL then
			self._doneTx[mark] = nil
		end
	end
end

function NetManager:_bindAddon()
	local event = App.system
	if not event then
		error("Net: 系统事件未就绪")
	end
	local net = self
	event:On("CHAT_MSG_ADDON", function(_, prefix, text, channel, sender)
		if prefix ~= net.PREFIX then return end
		local name = tostring(sender or "")
		if name == "" then return end
		local bare = name:match("^([^%-]+)") or name
		if bare == net:Me() then return end
		net:Dispatch(tostring(text or ""), bare, channel)
	end)
end

local Net = NetManager:new()
App._modules.Net = Net
App.netManager = Net
App:addManager(Net)
