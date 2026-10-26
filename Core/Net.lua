-- ============================================================
-- Core Module · 插件消息通道（AddOn Message）
--   · 注册前缀，挑一个可用频道（RAID > PARTY > GUILD）
--   · 只负责收发纯文本包，协议由使用方定义（见 Core/Checkers）
--   · 不在队伍 / 公会里时静默失败，调用方可回落到本机模式
-- ============================================================
local ADDON_NAME, MZ = ...

local Net = {}
MZ.Modules.Net = Net
MZ.Net = Net

Net.PREFIX    = "MZCHK"
Net.MAXLEN    = 240     -- 暴雪单包上限 255，留点余量
Net.listeners = {}

local prefixOK = false

local function RegisterPrefix()
	if prefixOK then return true end
	local api = (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) or RegisterAddonMessagePrefix
	if type(api) ~= "function" then return false end
	prefixOK = pcall(api, Net.PREFIX) and true or false
	return prefixOK
end

function Net:Me()
	return UnitName("player") or "player"
end

--- 当前可用的广播频道；nil 表示孤身一人（只能本机演练）
function Net:Channel()
	local list = self:Channels()
	return list[1]
end

--- 所有可用频道（团队/队伍 + 公会）
--- 两端组织关系不对等时（一个组着队、一个只在公会），只发单个频道会单向失联：
--- 主机发 PARTY 客人收不到，客人发 GUILD 主机收得到 —— 于是主机能走、客人看不到棋局。
--- 所以全部发一遍，接收端按（发送者 + 正文）去重。
function Net:Channels()
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

function Net:Available()
	return #self:Channels() > 0
end

function Net:Send(text)
	if type(text) ~= "string" or #text == 0 or #text > self.MAXLEN then return false end
	local chans = self:Channels()
	if #chans == 0 or not RegisterPrefix() then return false end
	local api = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
	if type(api) ~= "function" then return false end

	local sent = false
	for i = 1, #chans do
		if pcall(api, self.PREFIX, text, chans[i]) then sent = true end
	end
	return sent
end

function Net:On(fn)
	if type(fn) == "function" then table.insert(self.listeners, fn) end
end

function Net:Fire(text, sender)
	for i = 1, #self.listeners do
		pcall(self.listeners[i], text, sender)
	end
end

-- 载入即注册前缀：部分客户端不注册就收不到别人的包
RegisterPrefix()

-- ------------------------------------------------------------
-- 收包：CHAT_MSG_ADDON（前缀、正文、频道、发送者）
-- 事件总线会把事件名放在参数首位，故第二个形参才是前缀
-- 注意：本文件先于 App 门面加载，故用 Modules 里的原始事件表
-- ------------------------------------------------------------
local Event = MZ.Modules.Event

-- 多频道同时发送会让同一条包到达两次（比如既在队伍又在公会），
-- 这里只对 Q| 开头的「请求包」去重：请求不幂等，重复会多执行一次。
-- 状态包（C|SIT、C|RDY、P、W、H、B）本身幂等或带 seq，重复无害，
-- 不去重——否则玩家离座后马上坐回原位会被自己吞掉。
Net.DEDUP = 1.5
local seen, lastSweep = {}, 0

local function Duplicate(sender, text)
	if text:sub(1, 2) ~= "Q|" then return false end
	local now = GetTime()
	if now - lastSweep > 10 then
		lastSweep = now
		for k, t in pairs(seen) do
			if now - t > Net.DEDUP then seen[k] = nil end
		end
	end
	local key = sender .. "\0" .. text
	local t = seen[key]
	if t and now - t <= Net.DEDUP then return true end
	seen[key] = now
	return false
end

Event:On("CHAT_MSG_ADDON", function(_, prefix, text, channel, sender)
	if prefix ~= Net.PREFIX then return end
	local name = tostring(sender or "")
	if name == "" then return end
	local bare = name:match("^([^%-]+)") or name
	if bare == Net:Me() then return end   -- 个别客户端会把自己的包回显
	local body = tostring(text or "")
	if Duplicate(bare, body) then return end
	Net:Fire(body, bare, channel)
end)
