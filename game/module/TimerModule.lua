-- ============================================================
-- TimerModule · 开怪倒计时
-- 走表用 TimerManager。频道、到点通报和状态都在这里，界面只刷新数字。
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App

local TimerModule = App.newclz("TimerModule", App.AbstractModule)

function TimerModule:ctor()
	App.AbstractModule.ctor(self, "Timer")
end

function TimerModule:init()
	self.remain = 0
	self.running = false
	self.endAt = 0
	self._tick = nil
	self._ensured = false
end

function TimerModule:Ensure()
	if self._ensured then return end
	self._ensured = true
	self.remain = (App.Core.Store:GetKey("timerMinutes", 3)) * 60
	self.running = false
	self.endAt = 0
end

function TimerModule:Channel()
	if IsInRaid() then return "RAID" end
	if IsInGroup() then return "PARTY" end
	return "SAY"
end

function TimerModule:Announce(text)
	SendChatMessage("【墨战年华】" .. text, self:Channel())
end

function TimerModule:StatusText()
	if self.running then return "进行中" end
	if self.remain <= 0 then return "已结束" end
	return "已暂停 / 待开始"
end

function TimerModule:ParseMinutes(text)
	local v = tonumber(text)
	if not v or v <= 0 then v = 3 end
	v = math.min(120, v)
	App.Core.Store:Set("timerMinutes", v)
	return v
end

function TimerModule:_stopTick()
	if self._tick then
		self._tick:Cancel()
		self._tick = nil
	end
end

function TimerModule:_startTick()
	self:_stopTick()
	local timer = self
	self._tick = App.Core.Time:Every(0.2, function()
		if not timer.running then
			timer:_stopTick()
			return
		end
		timer.remain = timer.endAt - App.Core.Time:Now()
		if timer.remain <= 0 then
			timer.remain = 0
			timer.running = false
			timer:_stopTick()
			timer:Announce("倒计时结束，开怪！")
			App.eventManager:emit(App.Ev.TIMER_DONE)
			timer:emit("changed", "done")
			return
		end
		timer:emit("changed", "tick")
	end)
end

-- 返回本次解析出的分钟数；没解析时是 nil，输入框不必改写。
function TimerModule:Start(text)
	self:Ensure()
	local parsed
	if self.remain <= 0 then
		parsed = self:ParseMinutes(text)
		self.remain = parsed * 60
	end
	self.endAt = App.Core.Time:Now() + self.remain
	self.running = true
	self:_startTick()
	self:Announce("开怪倒计时 " .. App.Core.Time:Format(self.remain) .. " 开始，请就位。")
	App.eventManager:emit(App.Ev.TIMER_START, self.remain)
	self:emit("changed", "start")
	return parsed
end

function TimerModule:Pause()
	self:Ensure()
	if not self.running then return end
	self.remain = math.max(0, self.endAt - App.Core.Time:Now())
	self.running = false
	self:_stopTick()
	App.eventManager:emit(App.Ev.TIMER_PAUSE, self.remain)
	self:emit("changed", "pause")
end

function TimerModule:Reset(text)
	self:Ensure()
	self.running = false
	self:_stopTick()
	local parsed = self:ParseMinutes(text)
	self.remain = parsed * 60
	self:emit("changed", "reset")
	return parsed
end

function TimerModule:SetMinutes(text)
	self:Ensure()
	if self.running then return nil end
	local parsed = self:ParseMinutes(text)
	self.remain = parsed * 60
	self:emit("changed", "set")
	return parsed
end

function TimerModule:Say()
	self:Ensure()
	self:Announce("倒计时 " .. App.Core.Time:Format(self.remain) .. "，请准备。")
end

local inst = TimerModule:new()
App._modules.Timer = inst
inst:enterModule()
