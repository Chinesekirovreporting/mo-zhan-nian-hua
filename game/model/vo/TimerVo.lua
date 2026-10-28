-- ============================================================
-- TimerVo · 倒计时的当前状态
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App

local TimerVo = App.newclz("TimerVo")

TimerVo.remain = 0
TimerVo.running = false
TimerVo.endAt = 0
TimerVo.ensured = false

function TimerVo:ctor()
	self.remain = 0
	self.running = false
	self.endAt = 0
	self.ensured = false
end

App.TimerVo = TimerVo
