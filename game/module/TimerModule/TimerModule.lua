-- ============================================================
-- TimerModule · 开怪倒计时
-- 状态在 TimerVo。写入后 sync，界面读 self.model。
--
-- 同步 · 不同步倒计时状态
--   Announce 的 SendChatMessage 是可见公告，频道 RAID / PARTY / SAY，不算同步。
--   sync 只通知本机界面，不发插件消息。不用房主快照，也不用 ~S / ~D / ~T。
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App

local TimerModule = App.newclz("TimerModule", App.AbstractModule)

function TimerModule:ctor()
	App.AbstractModule.ctor(self, "Timer")
end

function TimerModule:init()
	self.model = App.TimerVo:new()
	self._tick = nil
	self:sync("init")
end

function TimerModule:Ensure()
	if self.model.ensured then return end
	self.model.ensured = true
	self.model.remain = (App.Core.Store:GetKey("timerMinutes", 3)) * 60
	self.model.running = false
	self.model.endAt = 0
	self:sync("ensure")
end

-- 同步：可见公告用的频道，RAID / PARTY / SAY。这不是插件消息通道。
function TimerModule:Channel()
	if IsInRaid() then return "RAID" end
	if IsInGroup() then return "PARTY" end
	return "SAY"
end

-- 同步：可见公告。不算状态同步，其他客户端的倒计时不会跟着变。
function TimerModule:Announce(text)
	SendChatMessage("【墨战年华】" .. text, self:Channel())
end

function TimerModule:StatusText()
	if self.model.running then return "进行中" end
	if self.model.remain <= 0 then return "已结束" end
	return "已暂停 / 待开始"
end

function TimerModule:ParseMinutes(text)
	local v = tonumber(text)
	if not v or v <= 0 then v = 3 end
	v = math.min(120, v)
	App.Core.Store:Set("timerMinutes", v)
	return v
end

function TimerModule:StopTick()
	if self._tick then
		self._tick:Cancel()
		self._tick = nil
	end
end

-- 同步：本机扣秒。到点的 Announce 是可见公告。sync("done") 只通知本机界面。
function TimerModule:OnTick()
	if not self.model.running then
		self:StopTick()
		return
	end
	self.model.remain = self.model.endAt - App.Core.Time:Now()
	if self.model.remain <= 0 then
		self.model.remain = 0
		self.model.running = false
		self:StopTick()
		self:Announce("倒计时结束，开怪！")
		self:sync("done")
		return
	end
	self:sync("tick")
end

function TimerModule:StartTick()
	self:StopTick()
	self._tick = App.Core.Time:Every(0.2, function()
		self:OnTick()
	end)
end

-- 返回本次解析出的分钟数；没解析时是 nil，输入框不必改写。
-- 同步：本机开始。公告走 Announce。sync 不发插件消息。
function TimerModule:Start(text)
	self:Ensure()
	local parsed
	if self.model.remain <= 0 then
		parsed = self:ParseMinutes(text)
		self.model.remain = parsed * 60
	end
	self.model.endAt = App.Core.Time:Now() + self.model.remain
	self.model.running = true
	self:StartTick()
	self:Announce("开怪倒计时 " .. App.Core.Time:Format(self.model.remain) .. " 开始，请就位。")
	self:sync("start")
	return parsed
end

-- 同步：本机暂停。不发公告，也不发插件消息。
function TimerModule:Pause()
	self:Ensure()
	if not self.model.running then return end
	self.model.remain = math.max(0, self.model.endAt - App.Core.Time:Now())
	self.model.running = false
	self:StopTick()
	self:sync("pause")
end

-- 同步：本机重设剩余时间。不发公告，也不发插件消息。
function TimerModule:Reset(text)
	self:Ensure()
	self.model.running = false
	self:StopTick()
	local parsed = self:ParseMinutes(text)
	self.model.remain = parsed * 60
	self:sync("reset")
	return parsed
end

-- 同步：本机改分钟数。进行中不改。不发插件消息。
function TimerModule:SetMinutes(text)
	self:Ensure()
	if self.model.running then return nil end
	local parsed = self:ParseMinutes(text)
	self.model.remain = parsed * 60
	self:sync("set")
	return parsed
end

-- 同步：再发一次可见公告，不改变其他客户端的倒计时。
function TimerModule:Say()
	self:Ensure()
	self:Announce("倒计时 " .. App.Core.Time:Format(self.model.remain) .. "，请准备。")
end

local inst = TimerModule:new()
App._modules.Timer = inst
inst:enterModule()
