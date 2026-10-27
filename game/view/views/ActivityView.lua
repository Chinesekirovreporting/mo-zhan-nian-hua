-- ============================================================
-- View · 公会活动
-- 骨架：game/skin/ActivityView.xml。这里只绑三张卡片的按钮。
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App

local ActivityView = App.newclz("ActivityView", App.AbstractView)

function ActivityView:ctor()
	App.AbstractView.ctor(self, {
		id       = "activity",
		title    = "公会活动",
		subtitle = "集合、报名、开怪，一条线走完",
		order    = 10,
		frame    = "MZPageActivity",
	})
end

function ActivityView:onBuild()
	local W = App.Widget
	W:TuneButton(_G["MZActivitySignupAction"])
	W:TuneButton(_G["MZActivityRosterAction"])
	W:TuneButton(_G["MZActivityTimerAction"])
	W:PaintText(_G["MZActivitySignupTitle"], 14, "ink")
	W:PaintText(_G["MZActivitySignupDesc"], 11, "inkFaint")
	W:PaintText(_G["MZActivityRosterTitle"], 14, "ink")
	W:PaintText(_G["MZActivityRosterDesc"], 11, "inkFaint")
	W:PaintText(_G["MZActivityTimerTitle"], 14, "ink")
	W:PaintText(_G["MZActivityTimerDesc"], 11, "inkFaint")

	App.Hook:Bind(_G["MZActivitySignupAction"], "OnClick", function()
		App.Core.Log:Info("「活动报名」功能位已预留，等接入。")
	end)
	App.Hook:Bind(_G["MZActivityRosterAction"], "OnClick", function()
		App.UI:ShowPage("roster")
	end)
	App.Hook:Bind(_G["MZActivityTimerAction"], "OnClick", function()
		App.UI:ShowPage("timer")
	end)
end

ActivityView:new():register()
