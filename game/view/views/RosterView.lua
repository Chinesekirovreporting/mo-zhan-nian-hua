-- ============================================================
-- View · 参战名单
-- 骨架：game/skin/RosterView.xml。名单来自 RosterModule，每一行随人数生成。
-- 团队变化走系统事件 GROUP_ROSTER_UPDATE。
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App
local S = App.Widget
local C = App.C

local RosterView = App.newclz("RosterView", App.AbstractView)

function RosterView:ctor()
	App.AbstractView.ctor(self, {
		id       = "roster",
		title    = "参战名单",
		subtitle = "按当前团队 / 小队实时读取",
		order    = 30,
		frame    = "MZPageRoster",
	})
end

function RosterView:onBuild(page)
	local count = _G["MZRosterCount"]
	local refresh = _G["MZRosterRefresh"]
	S:PaintText(count, 11, "inkFaint")
	S:TuneButton(refresh)

	local list = S:BindScroll(
		_G["MZRosterScroll"],
		_G["MZRosterScrollFrame"],
		_G["MZRosterScrollChild"],
		_G["MZRosterScrollThumb"]
	)

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
		local units = App.GameModules.Roster:List()

		for i = 1, #units do
			local info = units[i]
			local row = GetRow(i)
			local color = info.classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[info.classFile]

			row.name:SetText(info.name)
			if color then
				row.name:SetTextColor(color.r, color.g, color.b, 1)
			else
				row.name:SetTextColor(C.inkSoft[1], C.inkSoft[2], C.inkSoft[3], 1)
			end

			if info.level and info.level > 0 then
				row.info:SetText(string.format("等级 %d", info.level))
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

	App.Hook:Bind(refresh, "OnClick", Refresh)

	App.system:On(App.NetEvents.GROUP_ROSTER_UPDATE, function()
		if page:IsShown() then Refresh() end
	end)

	Refresh()
end

function RosterView:onShow()
	local scroll = _G["MZRosterScrollFrame"]
	local content = _G["MZRosterScrollChild"]
	if not scroll or not content then return end
	local w = scroll:GetWidth()
	if w and w > 1 then content:SetWidth(w) end
end

RosterView:new():register()
