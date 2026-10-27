-- ============================================================
-- Net · 底层通信（AddOn Message）
-- 继承 Manager。自己的 "message" 是代码事件，只在这条对象上派发。
-- 系统事件 CHAT_MSG_ADDON 从 SystemEvent 进来。
-- 协议由使用方定义（见 Checkers）。不在队伍 / 公会里时静默失败。
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App

local NetManager = App.Class("NetManager", App.Manager)

function NetManager:ctor()
	App.Manager.ctor(self)
	self.PREFIX = "MZCHK"
	self.MAXLEN = 240
	self.DEDUP  = 1.5
	self._prefixOK = false
	self._seen = {}
	self._lastSweep = 0
	self:_registerPrefix()
	self:_bindAddon()
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

--- 所有可用频道（团队/队伍 + 公会）
--- 两端组织关系不对等时，只发单个频道会单向失联，所以全部发一遍。
--- 接收端按（发送者 + 正文）对请求包去重。
function NetManager:Channels()
	local list = {}
	if type(IsInRaid) == "function" and IsInRaid() then
		list[#list + 1] = "RAID"
	elseif type(IsInGroup) == "function" and IsInGroup() then
		list[#list + 1] = "PARTY"
	end
	if type(IsInGuild) == "function" and IsInGuild() then
		list[#list + 1] = "GUILD"
	end
	return list
end

function NetManager:Available()
	return #self:Channels() > 0
end

function NetManager:Send(text)
	if type(text) ~= "string" or #text == 0 or #text > self.MAXLEN then return false end
	local chans = self:Channels()
	if #chans == 0 or not self:_registerPrefix() then return false end
	local api = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
	if type(api) ~= "function" then return false end

	local sent = false
	for i = 1, #chans do
		if pcall(api, self.PREFIX, text, chans[i]) then sent = true end
	end
	return sent
end

function NetManager:On(fn, thisArg)
	if type(fn) ~= "function" then return end
	return self:on("message", fn, thisArg)
end

function NetManager:Fire(text, sender, channel)
	self:emit("message", text, sender, channel)
end

-- 多频道同时发送会让同一条包到达两次。
-- 只对 Q| 开头的请求包去重：请求不幂等。状态包重复无害。
function NetManager:_duplicate(sender, text)
	if text:sub(1, 2) ~= "Q|" then return false end
	local now = GetTime()
	if now - self._lastSweep > 10 then
		self._lastSweep = now
		for k, t in pairs(self._seen) do
			if now - t > self.DEDUP then self._seen[k] = nil end
		end
	end
	local key = sender .. "\0" .. text
	local t = self._seen[key]
	if t and now - t <= self.DEDUP then return true end
	self._seen[key] = now
	return false
end

function NetManager:_bindAddon()
	local event = App.eventManager
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
		local body = tostring(text or "")
		if net:_duplicate(bare, body) then return end
		net:Fire(body, bare, channel)
	end)
end

local Net = NetManager:new()
App._modules.Net = Net
App.netManager = Net
App:addManager(Net)
