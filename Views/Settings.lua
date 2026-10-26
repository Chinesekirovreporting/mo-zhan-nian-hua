-- ============================================================
-- View · 设置
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App
local S = App.Skin
local UI = App.UI

UI:AddPage{
	id       = "settings",
	title    = "设置",
	subtitle = "面板缩放与位置",
	order    = 90,
	build    = function(page, body)
		local label = S:Text(body, 13, "inkSoft", "面板缩放")
		label:SetPoint("TOPLEFT", body, "TOPLEFT", 2, -6)

		local minus = S:Button(body, "－", 30, 26)
		minus:SetPoint("LEFT", label, "RIGHT", 14, 0)

		local pct = S:Text(body, 13, "ink", "")
		pct:SetPoint("LEFT", minus, "RIGHT", 10, 0)

		local plus = S:Button(body, "＋", 30, 26)
		plus:SetPoint("LEFT", pct, "RIGHT", 10, 0)

		local function Apply(delta)
			local v = UI:SetScale((App.Core.Store:GetKey("scale", 1)) + delta)
			pct:SetText(string.format("%d%%", math.floor(v * 100 + 0.5)))
		end

		minus:SetScript("OnClick", function() Apply(-0.05) end)
		plus:SetScript("OnClick", function() Apply(0.05) end)

		local reset = S:Button(body, "重置位置与缩放", 132, 26)
		reset:SetPoint("TOPLEFT", body, "TOPLEFT", 2, -44)
		reset:SetScript("OnClick", function()
			UI:ResetPosition()
			pct:SetText("100%")
			App.Core.Log:Info("位置与缩放已重置。")
		end)

		local about = S:Text(body, 11, "inkFaint",
			"墨战年华 v" .. App.VERSION .. "　·　MV 架构")
		about:SetPoint("TOPLEFT", body, "TOPLEFT", 2, -88)

		local usage = S:Text(body, 11, "inkFaint",
			"命令：/mznh 或 /mz 打开面板　/mz reset 重置　/mz test 查看状态")
		usage:SetPoint("TOPLEFT", about, "BOTTOMLEFT", 0, -6)

		pct:SetText(string.format("%d%%", math.floor((App.Core.Store:GetKey("scale", 1)) * 100 + 0.5)))
	end,
}
