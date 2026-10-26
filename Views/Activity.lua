-- ============================================================
-- View · 公会活动
-- ============================================================
local ADDON_NAME, MZ = ...
local S = MZ.Skin
local UI = MZ.UI

UI:AddPage{
	id       = "activity",
	title    = "公会活动",
	subtitle = "集合、报名、开怪，一条线走完",
	order    = 10,
	build    = function(page, body)
		local entries = {
			{
				name  = "活动报名",
				desc  = "发起一次集合，成员在这里点确认；名单自动汇总。",
				label = "待填入",
				action = function() MZ.Log:Info("「活动报名」功能位已预留，等接入。") end,
			},
			{
				name  = "参战名单",
				desc  = "读取当前团队 / 小队成员，按职业着色，标注等级。",
				label = "看名单",
				action = function() UI:ShowPage("roster") end,
			},
			{
				name  = "开怪计时",
				desc  = "统一节奏，倒计时可一键通报到团队频道。",
				label = "去计时",
				action = function() UI:ShowPage("timer") end,
			},
		}

		local y = 0
		for _, e in ipairs(entries) do
			local card = S:Card(body, 76)
			card:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -y)
			card:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, -y)

			card.title:SetText(e.name)
			card.desc:SetText(e.desc)

			local btn = S:Button(card, e.label, 84, 26)
			btn:SetPoint("RIGHT", card, "RIGHT", -14, 0)
			btn:SetScript("OnClick", e.action)

			y = y + 76 + 10
		end
	end,
}
