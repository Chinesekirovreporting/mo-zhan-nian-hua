-- ============================================================
-- View · 设置
-- 骨架：game/skin/SettingsView.xml。
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App

local SettingsView = App.newclz("SettingsView", App.AbstractView)

function SettingsView:ctor()
	App.AbstractView.ctor(self, {
		id       = "settings",
		title    = "设置",
		subtitle = "面板缩放与位置",
		order    = 90,
		frame    = "MZPageSettings",
	})
end

function SettingsView:onBuild()
	local W = App.Widget
	local pct = _G["MZSettingsPercentText"]
	W:TuneButton(_G["MZSettingsMinus"])
	W:TuneButton(_G["MZSettingsPlus"])
	W:TuneButton(_G["MZSettingsReset"])
	W:PaintText(_G["MZSettingsScaleLabelText"], 13, "inkSoft", "面板缩放")
	W:PaintText(pct, 13, "ink")
	W:PaintText(_G["MZSettingsAbout"], 11, "inkFaint")
	W:PaintText(_G["MZSettingsUsage"], 11, "inkFaint")

	local function ShowPct(v)
		pct:SetText(string.format("%d%%", math.floor(v * 100 + 0.5)))
	end

	local function Apply(delta)
		local v = App.UI:SetScale(App.Core.Store:GetKey("scale", 1) + delta)
		ShowPct(v)
	end

	App.Hook:Bind(_G["MZSettingsMinus"], "OnClick", function() Apply(-0.05) end)
	App.Hook:Bind(_G["MZSettingsPlus"], "OnClick", function() Apply(0.05) end)
	App.Hook:Bind(_G["MZSettingsReset"], "OnClick", function()
		App.UI:ResetPosition()
		ShowPct(1)
		App.Core.Log:Info("位置与缩放已重置。")
	end)

	_G["MZSettingsAbout"]:SetText("墨战年华 v" .. App.VERSION .. "　·　系统事件 / 代码事件")
	ShowPct(App.Core.Store:GetKey("scale", 1))
end

SettingsView:new():register()
