-- ============================================================
-- View · 开怪计时
-- 骨架：game/skin/TimerView.xml。倒计时在 TimerModule，这里只刷数字和按钮。
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App
local C = App.C

local TimerView = App.newclz("TimerView", App.AbstractView)

function TimerView:ctor()
	App.AbstractView.ctor(self, {
		id       = "timer",
		title    = "开怪计时",
		subtitle = "设定分钟数，到点自动通报",
		order    = 20,
		frame    = "MZPageTimer",
	})
end

function TimerView:onBuild()
	local W = App.Widget
	local timer = App.GameModules.Timer
	local display = _G["MZTimerDisplay"]
	local status = _G["MZTimerStatus"]
	local box = _G["MZTimerMinutes"]
	local startBtn = _G["MZTimerStart"]
	local pauseBtn = _G["MZTimerPause"]
	local resetBtn = _G["MZTimerReset"]
	local setBtn = _G["MZTimerSet"]
	local sayBtn = _G["MZTimerSay"]

	W:PaintText(display, 46, "ink")
	W:PaintText(status, 11, "inkFaint", "未开始")
	W:PaintText(_G["MZTimerMinuteLabelText"], 12, "inkSoft", "分钟数")
	W:PaintText(_G["MZTimerHint"], 11, "inkFaint")
	App:SetFont(box, 13)
	box:SetTextColor(C.ink[1], C.ink[2], C.ink[3], 1)
	box:SetAutoFocus(false)
	W:TuneButton(setBtn)
	W:TuneButton(startBtn, 13, true)
	W:TuneButton(pauseBtn)
	W:TuneButton(resetBtn)
	W:TuneButton(sayBtn)

	timer:Ensure()
	box:SetText(tostring(App.Core.Store:GetKey("timerMinutes", 3)))

	local function Refresh()
		display:SetText(App.Core.Time:Format(timer.remain))
		status:SetText(timer:StatusText())
	end

	local function Ink()
		display:SetTextColor(C.ink[1], C.ink[2], C.ink[3], 1)
	end

	timer:on("changed", function(why)
		if why == "done" then
			display:SetTextColor(C.cinnabar[1], C.cinnabar[2], C.cinnabar[3], 1)
		elseif why == "start" or why == "reset" then
			Ink()
		end
		Refresh()
	end)

	App.Hook:Bind(startBtn, "OnClick", function()
		local parsed = timer:Start(box:GetText())
		if parsed then box:SetText(tostring(parsed)) end
	end)

	App.Hook:Bind(pauseBtn, "OnClick", function()
		timer:Pause()
	end)

	App.Hook:Bind(resetBtn, "OnClick", function()
		local parsed = timer:Reset(box:GetText())
		if parsed then box:SetText(tostring(parsed)) end
	end)

	App.Hook:Bind(setBtn, "OnClick", function()
		local parsed = timer:SetMinutes(box:GetText())
		if parsed then box:SetText(tostring(parsed)) end
	end)

	App.Hook:Bind(sayBtn, "OnClick", function()
		timer:Say()
	end)

	Refresh()
end

TimerView:new():register()
