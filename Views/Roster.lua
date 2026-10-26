-- ============================================================
-- View · 参战名单
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App
local S = App.Skin
local C = App.C
local UI = App.UI

UI:AddPage{
	id       = "roster",
	title    = "参战名单",
	subtitle = "按当前团队 / 小队实时读取",
	order    = 30,
	build    = function(page, body)
		local count = S:Text(body, 11, "inkFaint", "")
		count:SetPoint("TOPLEFT", body, "TOPLEFT", 2, 0)

		local refresh = S:Button(body, "刷新", 60, 24)
		refresh:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, 4)

		local list = S:ScrollArea(body)
		list.holder:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -26)
		list.holder:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 0)

		local rowH = 26
		local rows = {}

		local function GetRow(i)
			local row = rows[i]
			if row then return row end

			row = CreateFrame("Frame", nil, list.content)
			row:SetHeight(rowH)
			row:SetPoint("TOPLEFT", list.content, "TOPLEFT", 0, -(i - 1) * rowH)
			row:SetPoint("TOPRIGHT", list.content, "TOPRIGHT", 0, -(i - 1) * rowH)

			row.line = S:HLine(row, "line", 0.12)
			row.line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
			row.line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -10, 0)

			row.name = S:Text(row, 13, "inkSoft")
			row.name:SetPoint("LEFT", 2, 0)

			row.info = S:Text(row, 11, "inkFaint")
			row.info:SetPoint("RIGHT", row, "RIGHT", -12, 0)

			rows[i] = row
			return row
		end

		local function Refresh()
			local units = {}
			if IsInRaid() then
				for i = 1, GetNumGroupMembers() do
					units[#units + 1] = "raid" .. i
				end
			elseif IsInGroup() then
				units[#units + 1] = "player"
				for i = 1, GetNumSubgroupMembers() do
					units[#units + 1] = "party" .. i
				end
			else
				units[#units + 1] = "player"
			end

			for i = 1, #units do
				local unit = units[i]
				local row = GetRow(i)
				local name = UnitName(unit) or "未知"
				local _, classFile = UnitClass(unit)
				local level = UnitLevel(unit) or 0
				local color = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]

				row.name:SetText(name)
				if color then
					row.name:SetTextColor(color.r, color.g, color.b, 1)
				else
					row.name:SetTextColor(C.inkSoft[1], C.inkSoft[2], C.inkSoft[3], 1)
				end

				if level and level > 0 then
					row.info:SetText(string.format("等级 %d", level))
				else
					row.info:SetText("等级 ??")
				end
				row:Show()
			end

			for i = #units + 1, #rows do
				if rows[i] then rows[i]:Hide() end
			end

			list.content:SetHeight(math.max(1, #units * rowH))
			list.Update()

			count:SetText(string.format("当前 %d 人", #units))
		end

		refresh:SetScript("OnClick", Refresh)

		-- 团队变化时自动刷新（仅本页可见时）
		App.Core.Event:On("GROUP_ROSTER_UPDATE", function()
			if page:IsShown() then Refresh() end
		end)

		Refresh()
	end,
}
