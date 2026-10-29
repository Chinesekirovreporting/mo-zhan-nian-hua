-- ============================================================
-- View · 木桩考核
-- 左：平均 / 最高排行。右：选中成员，或过滤排除。
-- 记账在 AssessModule。这里只画和接点击。
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App
local S = App.Widget
local C = App.C

local RANK_LABEL = { max = "最高 ↓", avg = "平均 ↓", last = "最近 ↓" }
local ROW_H = 26
local TAG_H = 20

local AssessView = App.newclz("AssessView", App.AbstractView)

function AssessView:ctor()
	App.AbstractView.ctor(self, {
		id       = "assess",
		title    = "木桩考核",
		subtitle = "停手后记入平均与最高，可排除人名和技能",
		order    = 40,
		frame    = "MZPageAssess",
	})
	self.selected = nil
	self.query = ""
	self.mode = "detail"
	self.rows = {}
	self.tags = {}
	self._clearArmed = false
	self._postArmed = false
end

function AssessView:Mod()
	return App.GameModules.Assess
end

function AssessView:Tip(btn, line)
	App.Hook:Bind(btn, "OnEnter", function(self)
		if self.bg then self.bg:SetVertexColor(C.paperDark[1], C.paperDark[2], C.paperDark[3], 1) end
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine(line, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	App.Hook:Bind(btn, "OnLeave", function(self)
		if self.bg then self.bg:SetVertexColor(C.paperLight[1], C.paperLight[2], C.paperLight[3], 1) end
		GameTooltip:Hide()
	end)
end

function AssessView:SetIf(edit, text)
	if edit:HasFocus() then return end
	text = tostring(text)
	if edit:GetText() ~= text then edit:SetText(text) end
end

function AssessView:onBuild(page, body)
	local width = math.floor(body:GetWidth() or 0)
	if width < 320 then width = 461 end
	local sideW = 168
	local listW = width - sideW - 8
	self.listW = listW
	self.sideW = sideW

	self:BuildBar(body)
	self:BuildList(body, listW)
	self:BuildSide(body, sideW)

	local view = self
	self:Mod():on("sync", function()
		if view.page and view.page:IsShown() then view:Render() end
	end)
	self:Render()
end

function AssessView:BuildBar(body)
	self.sortBtn = S:Button(body, "最高 ↓", 64, 22)
	self.sortBtn:SetPoint("TOPRIGHT", body, "TOPRIGHT", -176, 2)

	self.search = S:EditBox(body, 88, 22)
	self.search:SetPoint("RIGHT", self.sortBtn, "LEFT", -6, 0)
	self.search:SetMaxLetters(14)
	self:Tip(self.search, "按名字筛选排行")

	self.statText = S:Text(body, 11, "inkFaint", "")
	self.statText:SetPoint("TOPLEFT", body, "TOPLEFT", 2, -4)
	self.statText:SetPoint("RIGHT", self.search, "LEFT", -8, 0)
	self.statText:SetWordWrap(false)

	local view = self
	App.Hook:Bind(self.sortBtn, "OnClick", function()
		view:Mod():CycleRank()
		view:Render()
	end)
	App.Hook:Bind(self.search, "OnTextChanged", function(edit)
		view.query = string.lower(strtrim(edit:GetText() or ""))
		view:Render()
	end)
end

function AssessView:BuildList(body, listW)
	local panel = CreateFrame("Frame", nil, body)
	panel:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -30)
	panel:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 0, 0)
	panel:SetWidth(listW)
	S:Paint(panel, "paperLight")
	S:Stroke(panel, "line", 0)
	self.listPanel = panel

	local head = S:Text(panel, 10, "inkFaint", "#  成员")
	head:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -6)
	local headMax = S:Text(panel, 10, "inkFaint", "最高")
	headMax:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -16, -6)
	local headAvg = S:Text(panel, 10, "inkFaint", "平均")
	headAvg:SetPoint("RIGHT", headMax, "LEFT", -16, 0)

	self.list = S:ScrollArea(panel)
	self.list.holder:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -24)
	self.list.holder:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -6, 6)

	self.empty = S:Text(self.list.holder, 11, "inkFaint", "")
	self.empty:SetPoint("TOPLEFT", self.list.holder, "TOPLEFT", 4, -8)
	self.empty:SetPoint("TOPRIGHT", self.list.holder, "TOPRIGHT", -4, -8)
	self.empty:SetJustifyH("LEFT")
	self.empty:SetWordWrap(true)
end

function AssessView:GetRow(i)
	local row = self.rows[i]
	if row then return row end

	row = CreateFrame("Button", nil, self.list.content)
	row:SetHeight(ROW_H)
	row:SetPoint("TOPLEFT", self.list.content, "TOPLEFT", 0, -(i - 1) * ROW_H)
	row:SetPoint("TOPRIGHT", self.list.content, "TOPRIGHT", 0, -(i - 1) * ROW_H)
	row:RegisterForClicks("LeftButtonUp")

	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints(row)
	S:Solid(row.bg, C.paper, 0)

	row.bar = row:CreateTexture(nil, "ARTWORK")
	row.bar:SetWidth(3)
	row.bar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -1)
	row.bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 1)
	S:Solid(row.bar, C.cinnabar)
	row.bar:Hide()

	row.rankFS = S:Text(row, 11, "inkFaint")
	row.rankFS:SetPoint("LEFT", row, "LEFT", 6, 0)
	row.rankFS:SetWidth(18)
	row.rankFS:SetJustifyH("LEFT")

	row.nameFS = S:Text(row, 12, "inkSoft")
	row.nameFS:SetPoint("LEFT", row, "LEFT", 26, 0)
	row.nameFS:SetWidth(math.max(40, (self.listW or 280) - 150))
	row.nameFS:SetWordWrap(false)
	row.nameFS:SetJustifyH("LEFT")

	row.maxFS = S:Text(row, 12, "ink")
	row.maxFS:SetPoint("RIGHT", row, "RIGHT", -8, 0)
	row.maxFS:SetWidth(52)
	row.maxFS:SetJustifyH("RIGHT")

	row.avgFS = S:Text(row, 12, "inkSoft")
	row.avgFS:SetPoint("RIGHT", row.maxFS, "LEFT", -4, 0)
	row.avgFS:SetWidth(52)
	row.avgFS:SetJustifyH("RIGHT")

	local view = self
	App.Hook:Bind(row, "OnClick", function(self)
		if self.memberName then view:Select(self.memberName) end
	end)
	App.Hook:Bind(row, "OnEnter", function(self)
		if self.memberName ~= view.selected then S:Solid(self.bg, C.paper, 0.5) end
		view:ShowRowTip(self)
	end)
	App.Hook:Bind(row, "OnLeave", function(self)
		if self.memberName ~= view.selected then S:Solid(self.bg, C.paper, 0) end
		GameTooltip:Hide()
	end)

	self.rows[i] = row
	return row
end

function AssessView:ShowRowTip(row)
	local rec = row.record
	if not rec then return end
	local mod = self:Mod()
	local last = rec:Last()
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:AddLine(rec.name)
	GameTooltip:AddDoubleLine("平均", mod:FormatDps(rec:Avg()), 0.6, 0.6, 0.6, 1, 1, 1)
	GameTooltip:AddDoubleLine("最高", mod:FormatDps(rec:Max()), 0.6, 0.6, 0.6, 0.9, 0.35, 0.3)
	GameTooltip:AddDoubleLine("样本", tostring(#rec.samples), 0.6, 0.6, 0.6, 1, 1, 1)
	if last then
		GameTooltip:AddLine(string.format("最近 %s · %.0f秒 · %s",
			mod:FormatDps(last.dps), last.seconds, date("%m-%d %H:%M", last.at)),
			0.6, 0.6, 0.6)
	end
	GameTooltip:Show()
end

function AssessView:BuildSide(body, sideW)
	local side = CreateFrame("Frame", nil, body)
	side:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, -30)
	side:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 0)
	side:SetWidth(sideW)
	S:Paint(side, "paperLight")
	S:Stroke(side, "line", 0)
	self.side = side

	local inner = sideW - 20
	self.inner = inner

	self.modeBtn = S:Button(side, "过滤条件", inner, 22)
	self.modeBtn:SetPoint("TOPLEFT", side, "TOPLEFT", 10, -8)
	local view = self
	App.Hook:Bind(self.modeBtn, "OnClick", function()
		view.mode = view.mode == "filter" and "detail" or "filter"
		view:Render()
	end)

	self:BuildDetail(side, inner)
	self:BuildFilter(side, inner)
end

function AssessView:BuildDetail(side, inner)
	local box = CreateFrame("Frame", nil, side)
	box:SetPoint("TOPLEFT", side, "TOPLEFT", 0, -36)
	box:SetPoint("BOTTOMRIGHT", side, "BOTTOMRIGHT", 0, 0)
	self.detail = box

	self.selName = S:Text(box, 13, "ink", "未选择")
	self.selName:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -4)
	self.selName:SetWidth(inner)
	self.selName:SetWordWrap(false)

	self.selPlace = S:Text(box, 10, "inkFaint", "在左侧点一位成员")
	self.selPlace:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -22)
	self.selPlace:SetWidth(inner)

	self.selAvg = S:Text(box, 18, "cinnabar", "—")
	self.selAvg:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -40)
	self.avgCaption = S:Text(box, 10, "inkFaint", "平均")
	self.avgCaption:SetPoint("LEFT", self.selAvg, "RIGHT", 6, -2)

	self.selMax = S:Text(box, 13, "ink", "")
	self.selMax:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -64)
	self.selMax:SetWidth(inner)

	self.selLast = S:Text(box, 10, "inkFaint", "")
	self.selLast:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -82)
	self.selLast:SetWidth(inner)
	self.selLast:SetWordWrap(true)

	self.selLive = S:Text(box, 10, "cinnabar", "")
	self.selLive:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -112)
	self.selLive:SetWidth(inner)

	local view = self
	self.undoBtn = S:Button(box, "撤销最近", inner, 20)
	self.undoBtn:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -132)
	App.Hook:Bind(self.undoBtn, "OnClick", function()
		view:UndoSelected()
	end)

	self.removeBtn = S:Button(box, "删除此人", inner, 20)
	self.removeBtn:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -156)
	App.Hook:Bind(self.removeBtn, "OnClick", function()
		view:RemoveSelected()
	end)

	self.clearBtn = S:Button(box, "清空记录", inner, 20)
	self.clearBtn:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -180)
	App.Hook:Bind(self.clearBtn, "OnClick", function()
		view:ClearAll()
	end)

	self.postBtn = S:Button(box, "张贴前五", inner, 22)
	self.postBtn:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -206)
	App.Hook:Bind(self.postBtn, "OnClick", function()
		view:PostRank()
	end)
	self:Tip(self.postBtn, "把当前排行前五发到公会频道")
end

function AssessView:BuildFilter(side, inner)
	local box = CreateFrame("Frame", nil, side)
	box:SetPoint("TOPLEFT", side, "TOPLEFT", 0, -36)
	box:SetPoint("BOTTOMRIGHT", side, "BOTTOMRIGHT", 0, 0)
	box:Hide()
	self.filterFrame = box

	local function numberRow(y, caption)
		local label = S:Text(box, 11, "inkSoft", caption)
		label:SetPoint("TOPLEFT", box, "TOPLEFT", 10, y)
		label:SetWidth(36)
		local edit = S:EditBox(box, 52, 20)
		edit:SetPoint("TOPLEFT", box, "TOPLEFT", 48, y + 2)
		edit:SetMaxLetters(3)
		App.Hook:Bind(edit, "OnTextChanged", function(self)
			local txt = self:GetText() or ""
			local clean = string.gsub(txt, "[^%d]", "")
			if clean ~= txt then self:SetText(clean) end
		end)
		return edit
	end

	self.minEdit = numberRow(-2, "最短")
	self.idleEdit = numberRow(-26, "停手")
	self:Tip(self.minEdit, "短于这个秒数的一次输出不记入。范围 5 到 600。")
	self:Tip(self.idleEdit, "停手超过这个秒数，就把这一次记下来。范围 2 到 60。")

	local view = self
	local function bindNumber(edit, key)
		App.Hook:Bind(edit, "OnEnterPressed", function(self)
			self:ClearFocus()
			view:Mod():SetNumber(key, self:GetText())
			view:SetIf(self, view:Mod():Filters()[key])
		end)
		App.Hook:Bind(edit, "OnEditFocusLost", function(self)
			view:Mod():SetNumber(key, self:GetText())
			view:SetIf(self, view:Mod():Filters()[key])
		end)
	end
	bindNumber(self.minEdit, "minSeconds")
	bindNumber(self.idleEdit, "idleSeconds")

	self.guildBtn = S:Button(box, "只记公会：开", inner, 20)
	self.guildBtn:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -52)
	self.petBtn = S:Button(box, "宠物伤害：开", inner, 20)
	self.petBtn:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -76)
	self.singleBtn = S:Button(box, "只记单桩：开", inner, 20)
	self.singleBtn:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -100)

	App.Hook:Bind(self.guildBtn, "OnClick", function()
		view:Mod():Toggle("guildOnly")
		view:Render()
	end)
	App.Hook:Bind(self.petBtn, "OnClick", function()
		view:Mod():Toggle("includePets")
		view:Render()
	end)
	App.Hook:Bind(self.singleBtn, "OnClick", function()
		view:Mod():Toggle("singleTarget")
		view:Render()
	end)
	self:Tip(self.guildBtn, "打开后只记录公会名册里的人。名册还没到时先照记，名册到了再丢掉外人。")
	self:Tip(self.petBtn, "打开后宠物、守护、图腾的伤害算在主人身上。")
	self:Tip(self.singleBtn, "打开后同一次只算第一只木桩，旁边的木桩不算，避免群伤灌水。")

	self.nameEdit = self:AddRow(box, inner, -128, "加人", "excludeNames", "排除这名玩家，排行里也不显示")
	self.spellEdit = self:AddRow(box, inner, -152, "加技", "excludeSpells", "排除技能名或法术 ID，只影响之后的伤害")
	self.dummyEdit = self:AddRow(box, inner, -176, "加桩", "dummyNames", "目标名字里带这几个字也当作木桩")

	self.tagScroll = S:ScrollArea(box)
	self.tagScroll.holder:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -202)
	self.tagScroll.holder:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -4, 6)
end

function AssessView:AddRow(box, inner, y, caption, key, tip)
	local edit = S:EditBox(box, inner - 40, 20)
	edit:SetPoint("TOPLEFT", box, "TOPLEFT", 10, y)
	edit:SetMaxLetters(16)
	local btn = S:Button(box, caption, 36, 20)
	btn:SetPoint("LEFT", edit, "RIGHT", 4, 0)
	self:Tip(edit, tip)
	local view = self
	local function add()
		local text = edit:GetText() or ""
		if view:Mod():AddList(key, text) then
			edit:SetText("")
			view:Render()
		end
		edit:ClearFocus()
	end
	App.Hook:Bind(btn, "OnClick", add)
	App.Hook:Bind(edit, "OnEnterPressed", function(self)
		self:ClearFocus()
		add()
	end)
	return edit
end

function AssessView:GetTag(i)
	local row = self.tags[i]
	if row then return row end
	row = CreateFrame("Button", nil, self.tagScroll.content)
	row:SetHeight(TAG_H)
	row:SetPoint("TOPLEFT", self.tagScroll.content, "TOPLEFT", 0, -(i - 1) * TAG_H)
	row:SetPoint("TOPRIGHT", self.tagScroll.content, "TOPRIGHT", 0, -(i - 1) * TAG_H)
	row:RegisterForClicks("LeftButtonUp")
	row.label = S:Text(row, 10, "inkSoft", "")
	row.label:SetPoint("LEFT", row, "LEFT", 2, 0)
	row.label:SetPoint("RIGHT", row, "RIGHT", -2, 0)
	row.label:SetWordWrap(false)
	row.label:SetJustifyH("LEFT")
	local view = self
	App.Hook:Bind(row, "OnClick", function(self)
		if self.listKey and self.listText then
			view:Mod():RemoveList(self.listKey, self.listText)
			view:Render()
		end
	end)
	App.Hook:Bind(row, "OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("点一下移除", 1, 1, 1)
		GameTooltip:Show()
	end)
	App.Hook:Bind(row, "OnLeave", function()
		GameTooltip:Hide()
	end)
	self.tags[i] = row
	return row
end

function AssessView:StatusLine(shown, live)
	local mod = self:Mod()
	local text = string.format("记录 %d 人", #shown)
	if #live > 0 then
		local bits = {}
		local n = math.min(#live, 2)
		for i = 1, n do
			bits[i] = string.format("%s %s", live[i].name, mod:FormatDps(live[i].dps))
		end
		text = text .. " · " .. table.concat(bits, " ")
	end
	return text
end

function AssessView:DrawRows(shown)
	local mod = self:Mod()
	local by = mod:Filters().rankBy or "max"
	for i = 1, #shown do
		local rec = shown[i]
		local row = self:GetRow(i)
		row.record = rec
		row.memberName = rec.name
		row.rankFS:SetText(tostring(i))
		if i <= 3 then
			row.rankFS:SetTextColor(C.cinnabar[1], C.cinnabar[2], C.cinnabar[3], 1)
		else
			row.rankFS:SetTextColor(C.inkFaint[1], C.inkFaint[2], C.inkFaint[3], 1)
		end
		row.nameFS:SetText(rec.name)
		local color = rec.classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[rec.classFile]
		if color then
			row.nameFS:SetTextColor(color.r, color.g, color.b, 1)
		else
			row.nameFS:SetTextColor(C.inkSoft[1], C.inkSoft[2], C.inkSoft[3], 1)
		end
		row.avgFS:SetText(mod:FormatDps(rec:Avg()))
		row.maxFS:SetText(mod:FormatDps(rec:Max()))
		local avgTone = by == "avg" and C.cinnabar or C.inkSoft
		local maxTone = by == "max" and C.cinnabar or C.ink
		row.avgFS:SetTextColor(avgTone[1], avgTone[2], avgTone[3], 1)
		row.maxFS:SetTextColor(maxTone[1], maxTone[2], maxTone[3], 1)
		local picked = rec.name == self.selected
		if picked then row.bar:Show() else row.bar:Hide() end
		S:Solid(row.bg, C.paper, picked and 1 or 0)
		row:Show()
	end
	for i = #shown + 1, #self.rows do
		self.rows[i].record = nil
		self.rows[i].memberName = nil
		self.rows[i]:Hide()
	end
	self.list.content:SetHeight(math.max(1, #shown * ROW_H))
	self.list.Update()
	if #shown == 0 then
		if self.query ~= "" then
			self.empty:SetText("没有匹配的成员")
		else
			self.empty:SetText("对着名字里带「木桩」或「假人」的目标输出，停手后记入。短于最短秒数的不算。首领名字可在过滤里追加。")
		end
		self.empty:Show()
	else
		self.empty:Hide()
	end
end

function AssessView:FindRecord(all)
	if not self.selected then return nil, nil end
	for i = 1, #all do
		if all[i].name == self.selected then return all[i], i end
	end
	return nil, nil
end

function AssessView:DrawDetail(all, live)
	local mod = self:Mod()
	local rec, place = self:FindRecord(all)
	if not rec then
		self.selName:SetText("未选择")
		self.selName:SetTextColor(C.inkFaint[1], C.inkFaint[2], C.inkFaint[3], 1)
		self.selPlace:SetText("在左侧点一位成员")
		self.selAvg:SetText("—")
		self.selMax:SetText("")
		self.selLast:SetText("")
		self.selLive:SetText("")
		return
	end
	self.selName:SetText(rec.name)
	local color = rec.classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[rec.classFile]
	if color then
		self.selName:SetTextColor(color.r, color.g, color.b, 1)
	else
		self.selName:SetTextColor(C.ink[1], C.ink[2], C.ink[3], 1)
	end
	self.selPlace:SetText(string.format("第 %d 名 · 样本 %d/%d", place or 0, #rec.samples, mod.MAX_SAMPLES))
	self.selAvg:SetText(mod:FormatDps(rec:Avg()))
	self.selMax:SetText("最高 " .. mod:FormatDps(rec:Max()))
	local last = rec:Last()
	if last then
		self.selLast:SetText(string.format("最近 %s · %.0f秒 · %s",
			mod:FormatDps(last.dps), last.seconds, date("%m-%d %H:%M", last.at)))
	else
		self.selLast:SetText("")
	end
	local liveLine = ""
	for i = 1, #live do
		if live[i].name == rec.name then
			liveLine = string.format("进行中 %s · %.0f秒", mod:FormatDps(live[i].dps), live[i].seconds)
			break
		end
	end
	self.selLive:SetText(liveLine)
end

function AssessView:DrawFilter(f)
	self:SetIf(self.minEdit, f.minSeconds)
	self:SetIf(self.idleEdit, f.idleSeconds)
	self.guildBtn:SetLabel(f.guildOnly and "只记公会：开" or "只记公会：关")
	self.petBtn:SetLabel(f.includePets and "宠物伤害：开" or "宠物伤害：关")
	self.singleBtn:SetLabel(f.singleTarget and "只记单桩：开" or "只记单桩：关")

	local items = {}
	for i = 1, #f.excludeNames do
		items[#items + 1] = { key = "excludeNames", text = f.excludeNames[i], label = "人 " .. f.excludeNames[i] }
	end
	for i = 1, #f.excludeSpells do
		items[#items + 1] = { key = "excludeSpells", text = f.excludeSpells[i], label = "技 " .. f.excludeSpells[i] }
	end
	for i = 1, #f.dummyNames do
		items[#items + 1] = { key = "dummyNames", text = f.dummyNames[i], label = "桩 " .. f.dummyNames[i] }
	end
	for i = 1, #items do
		local row = self:GetTag(i)
		row.listKey = items[i].key
		row.listText = items[i].text
		row.label:SetText(items[i].label)
		row:Show()
	end
	for i = #items + 1, #self.tags do
		self.tags[i].listKey = nil
		self.tags[i].listText = nil
		self.tags[i]:Hide()
	end
	self.tagScroll.content:SetHeight(math.max(1, #items * TAG_H))
	self.tagScroll.Update()
end

function AssessView:ModeLabel(f)
	if self.mode == "filter" then return "返回记录" end
	local n = #f.excludeNames + #f.excludeSpells + #f.dummyNames
	if n > 0 then return string.format("过滤 %d", n) end
	return "过滤条件"
end

function AssessView:Render()
	if not self.list then return end
	local mod = self:Mod()
	local f = mod:Filters()
	local all = mod:Arrange("")
	local shown = self.query ~= "" and mod:Arrange(self.query) or all
	local live = mod:LiveList()
	self.sortBtn:SetLabel(RANK_LABEL[f.rankBy] or "最高 ↓")
	self.statText:SetText(self:StatusLine(shown, live))
	self:DrawRows(shown)
	self.modeBtn:SetLabel(self:ModeLabel(f))
	if self.mode == "filter" then
		self.detail:Hide()
		self.filterFrame:Show()
		self:DrawFilter(f)
	else
		self.filterFrame:Hide()
		self.detail:Show()
		self:DrawDetail(all, live)
	end
	if not self._clearArmed then self.clearBtn:SetLabel("清空记录") end
	if not self._postArmed then self.postBtn:SetLabel("张贴前五") end
end

function AssessView:Select(name)
	self.selected = name
	self.mode = "detail"
	self:Render()
end

function AssessView:NeedSelection()
	if self.selected then return true end
	App:Print("请先在左侧选择一位成员。")
	return false
end

function AssessView:UndoSelected()
	if not self:NeedSelection() then return end
	local last = self:Mod():UndoLast(self.selected)
	if not last then
		App:Print("没有可撤销的记录。")
		return
	end
	App:Print(string.format("已撤销 %s 最近一次 %s", self.selected, self:Mod():FormatDps(last.dps)))
end

function AssessView:RemoveSelected()
	if not self:NeedSelection() then return end
	local name = self.selected
	self:Mod():Remove(name)
	self.selected = nil
	App:Print("已删除 " .. name .. " 的考核记录。")
end

function AssessView:ClearAll()
	if not self._clearArmed then
		self._clearArmed = true
		self.clearBtn:SetLabel("再点一次清空")
		local view = self
		App.Core.Time:After(3, function()
			if view._clearArmed then
				view._clearArmed = false
				view.clearBtn:SetLabel("清空记录")
			end
		end)
		return
	end
	self._clearArmed = false
	self.selected = nil
	self:Mod():Clear()
	App:Print("考核记录已清空。")
end

function AssessView:PostRank()
	if not self._postArmed then
		self._postArmed = true
		self.postBtn:SetLabel("再点一次张贴")
		local view = self
		App.Core.Time:After(3, function()
			if view._postArmed then
				view._postArmed = false
				view.postBtn:SetLabel("张贴前五")
			end
		end)
		return
	end
	self._postArmed = false
	self.postBtn:SetLabel("张贴前五")
	if not (IsInGuild and IsInGuild()) then
		App:Print("不在公会中，无法张贴。")
		return
	end
	local text = self:Mod():PostText()
	if not text then
		App:Print("还没有可张贴的记录。")
		return
	end
	local ok = pcall(SendChatMessage, text, "GUILD")
	if not ok then App:Print("张贴没有发出去。") end
end

function AssessView:onShow()
	local mod = self:Mod()
	mod:RefreshGuild()
	mod:RefreshPets()
	mod:RequestGuild()
	if self.statText then self:Render() end
end

AssessView:new():register()
