-- ============================================================
-- View · 公会 DKP
--   左：成员积分榜（公会名册 + 本地积分，可搜索 / 三种排序）
--   右：选中成员记分（EP 加 / GP 扣）、快捷记分、张贴、撤销、流水
-- 计分：单一积分池，双记录 EP(获得) / GP(消耗)；净分 = EP - GP，PR = EP / GP
-- 数据：MoZhanNianHuaDB.dkp.members[name] = { ep, gp }；dkp.log 为流水
-- 名册只取名单 / 等级 / 职业色，分数完全离线保存在本地存档。
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App
local S = App.Skin
local C = App.C
local UI = App.UI

local MAX_LOG  = 200      -- 流水上限（超出丢最旧）
local SHOW_LOG = 4        -- 右侧显示的流水条数
local QUICK    = { 5, 10, 20, 50 } -- 快捷记分（左键加 EP / 右键扣 GP）

-- ------------------------------------------------------------
-- 数据层
-- ------------------------------------------------------------
local function DB()
	local db = App.Core.Store:Get()
	if type(db.dkp) ~= "table" then db.dkp = {} end
	local d = db.dkp
	if type(d.members) ~= "table" then d.members = {} end
	if type(d.log) ~= "table" then d.log = {} end
	return d
end

-- 归一化（兼容旧存档里直接存数字的写法）
local function Normalize(raw)
	if type(raw) == "table" then
		return tonumber(raw.ep) or 0, tonumber(raw.gp) or 0
	elseif type(raw) == "number" then
		return raw, 0
	end
	return 0, 0
end

-- 只读查询，不会在存档里造空记录
local function Peek(name)
	return Normalize(DB().members[name])
end

local function Net(name)
	local ep, gp = Peek(name)
	return ep - gp
end

local function PR(name)
	local ep, gp = Peek(name)
	return ep / math.max(1, gp)
end

-- delta > 0 记 EP；delta < 0 记 GP
local function AddEntry(name, delta, reason)
	local d = DB()
	local ep, gp = Normalize(d.members[name])
	if delta > 0 then
		ep = ep + delta
	else
		gp = gp + (-delta)
	end
	d.members[name] = { ep = ep, gp = gp }
	table.insert(d.log, {
		name   = name,
		delta  = delta,
		reason = reason or "",
		at     = time(),
	})
	while #d.log > MAX_LOG do table.remove(d.log, 1) end
end

local function UndoLast()
	local d = DB()
	local last = table.remove(d.log)
	if not last then return nil end

	local ep, gp = Normalize(d.members[last.name])
	if last.delta > 0 then
		ep = math.max(0, ep - last.delta)
	else
		gp = math.max(0, gp + last.delta)
	end
	d.members[last.name] = { ep = ep, gp = gp }
	return last
end

-- ------------------------------------------------------------
-- 职业色：名册第 5 项在经典客户端是本地化职业名，新版可能是职业 token
-- ------------------------------------------------------------
local localToToken = {}

local function BuildClassMap()
	if next(localToToken) then return end
	for token, loc in pairs(LOCALIZED_CLASS_NAMES_MALE or {}) do
		localToToken[loc] = token
	end
	for token, loc in pairs(LOCALIZED_CLASS_NAMES_FEMALE or {}) do
		if not localToToken[loc] then localToToken[loc] = token end
	end
end

local function ResolveClass(cls, idx)
	BuildClassMap()
	local colors = RAID_CLASS_COLORS
	if type(cls) == "string" then
		if colors and colors[cls] then return cls end
		if localToToken[cls] then return localToToken[cls] end
	end
	if type(idx) == "string" and colors and colors[idx] then return idx end
	return nil
end

-- ------------------------------------------------------------
-- 名册读取（只取名单 / 等级 / 职业，不取任何分数）
-- ------------------------------------------------------------
local function ScanGuild()
	local list = {}
	if not (IsInGuild and IsInGuild()) then return list end
	if not (GetNumGuildMembers and GetGuildRosterInfo) then return list end

	local n = GetNumGuildMembers() or 0
	for i = 1, n do
		local ok, name, _, _, level, class, _, _, _, online, _, classIdx =
			pcall(GetGuildRosterInfo, i)
		if ok and name then
			-- 跨服名册可能带 "-服务器"，去掉后缀以便与积分键对齐
			local short = string.match(name, "^([^-]+)") or name
			list[#list + 1] = {
				name      = short,
				level     = level or 0,
				classFile = ResolveClass(class, classIdx),
				online    = online and true or false,
				inGuild   = true,
			}
		end
	end
	return list
end

-- ------------------------------------------------------------
-- 页面
-- ------------------------------------------------------------
UI:AddPage{
	id       = "dkp",
	title    = "公会 DKP",
	subtitle = "EP / GP 双记录 · 净分排名 · 流水可撤销",
	order    = 15,
	build    = function(page, body)
		local W = math.floor(body:GetWidth() or 461)
		if W < 320 then W = 461 end

		local SIDE_W = 165
		local GAP    = 8
		local LIST_W = W - SIDE_W - GAP
		local INNER  = SIDE_W - 20

		local sortBy    = App.Core.Store:GetKey("dkpSort", "net")
		local members   = {}
		local selected  = nil
		local searching = ""

		-- 前向声明：行点击 / 快捷按钮在定义时会引用到
		local SelectMember, ApplyDelta, Render, UpdateSide

		-- ==================== 顶部工具条 ====================
		local statText = S:Text(body, 11, "inkFaint", "")
		statText:SetPoint("TOPLEFT", body, "TOPLEFT", 2, -4)
		statText:SetWidth(LIST_W - 2)
		statText:SetWordWrap(false)

		local syncBtn = S:Button(body, "同步", 46, 22)
		syncBtn:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, 2)

		local sortBtn = S:Button(body, "净分 ↓", 58, 22)
		sortBtn:SetPoint("RIGHT", syncBtn, "LEFT", -6, 0)

		local search = S:EditBox(body, 96, 22)
		search:SetPoint("RIGHT", sortBtn, "LEFT", -6, 0)
		search:SetMaxLetters(14)
		search:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
			GameTooltip:AddLine("按名字搜索成员")
			GameTooltip:Show()
		end)
		search:SetScript("OnLeave", function() GameTooltip:Hide() end)

		-- ==================== 左：积分榜 ====================
		local listPanel = CreateFrame("Frame", nil, body)
		listPanel:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -30)
		listPanel:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 0, 0)
		listPanel:SetWidth(LIST_W)
		S:Paint(listPanel, "paperLight")
		S:Stroke(listPanel, "line", 0)

		local list = S:ScrollArea(listPanel)
		list.holder:SetPoint("TOPLEFT", listPanel, "TOPLEFT", 8, -6)
		list.holder:SetPoint("BOTTOMRIGHT", listPanel, "BOTTOMRIGHT", -6, 6)

		local empty = S:Text(list.holder, 11, "inkFaint", "")
		empty:SetPoint("TOP", list.holder, "TOP", 0, -8)

		local rowH = 24
		local rows = {}

		local function GetRow(i)
			local row = rows[i]
			if row then return row end

			row = CreateFrame("Button", nil, list.content)
			row:SetHeight(rowH)
			row:SetPoint("TOPLEFT", list.content, "TOPLEFT", 0, -(i - 1) * rowH)
			row:SetPoint("TOPRIGHT", list.content, "TOPRIGHT", 0, -(i - 1) * rowH)
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

			row.nameFS = S:Text(row, 12, "inkSoft")
			row.nameFS:SetPoint("LEFT", row, "LEFT", 9, 0)
			row.nameFS:SetWidth(LIST_W - 132)
			row.nameFS:SetWordWrap(false)
			row.nameFS:SetJustifyH("LEFT")

			row.lvFS = S:Text(row, 10, "inkFaint")
			row.lvFS:SetPoint("RIGHT", row, "RIGHT", -58, 0)
			row.lvFS:SetWidth(44)
			row.lvFS:SetJustifyH("RIGHT")

			row.netFS = S:Text(row, 13, "ink")
			row.netFS:SetPoint("RIGHT", row, "RIGHT", -8, 0)
			row.netFS:SetWidth(50)
			row.netFS:SetJustifyH("RIGHT")

			row:SetScript("OnClick", function(self)
				if self.memberName then SelectMember(self.memberName) end
			end)
			row:SetScript("OnEnter", function(self)
				local name = self.memberName
				if not name then return end
				if name ~= selected then S:Solid(self.bg, C.paper, 0.5) end
				local ep, gp = Peek(name)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:AddLine(name)
				GameTooltip:AddDoubleLine("EP（获得）", tostring(ep), 0.6, 0.6, 0.6, 1, 1, 1)
				GameTooltip:AddDoubleLine("GP（消耗）", tostring(gp), 0.6, 0.6, 0.6, 1, 1, 1)
				GameTooltip:AddDoubleLine("净分", tostring(ep - gp), 0.6, 0.6, 0.6, 0.9, 0.35, 0.3)
				GameTooltip:AddDoubleLine("PR", string.format("%.2f", ep / math.max(1, gp)),
					0.6, 0.6, 0.6, 1, 1, 1)
				GameTooltip:Show()
			end)
			row:SetScript("OnLeave", function(self)
				if self.memberName ~= selected then S:Solid(self.bg, C.paper, 0) end
				GameTooltip:Hide()
			end)

			rows[i] = row
			return row
		end

		-- ==================== 右：记分面板 ====================
		local side = CreateFrame("Frame", nil, body)
		side:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, -30)
		side:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 0)
		side:SetWidth(SIDE_W)
		S:Paint(side, "paperLight")
		S:Stroke(side, "line", 0)

		local selName = S:Text(side, 13, "ink", "未选择成员")
		selName:SetPoint("TOPLEFT", side, "TOPLEFT", 10, -8)
		selName:SetWidth(86)
		selName:SetWordWrap(false)

		local selNet = S:Text(side, 22, "cinnabar", "—")
		selNet:SetPoint("TOPRIGHT", side, "TOPRIGHT", -10, -4)

		local selMeta = S:Text(side, 10, "inkFaint", "")
		selMeta:SetPoint("TOPLEFT", side, "TOPLEFT", 10, -26)

		local selEPGP = S:Text(side, 10, "inkFaint", "")
		selEPGP:SetPoint("TOPLEFT", side, "TOPLEFT", 10, -40)

		local rule1 = S:HLine(side, "line", 0.25)
		rule1:SetPoint("TOPLEFT", side, "TOPLEFT", 10, -56)
		rule1:SetPoint("TOPRIGHT", side, "TOPRIGHT", -10, -56)

		local reason = S:EditBox(side, INNER, 20)
		reason:SetPoint("TOPLEFT", side, "TOPLEFT", 10, -62)
		reason:SetMaxLetters(10)

		local delta = S:EditBox(side, 54, 20)
		delta:SetPoint("TOPLEFT", side, "TOPLEFT", 10, -86)
		delta:SetMaxLetters(5)
		delta:SetScript("OnTextChanged", function(self)
			local txt = self:GetText() or ""
			local clean = string.gsub(txt, "[^%d]", "")
			if clean ~= txt then self:SetText(clean) end
		end)

		local addBtn = S:Button(side, "加", 40, 20)
		addBtn:SetPoint("LEFT", delta, "RIGHT", 4, 0)

		local subBtn = S:Button(side, "减", 40, 20)
		subBtn:SetPoint("LEFT", addBtn, "RIGHT", 4, 0)

		-- 快捷记分
		local qGap = 3
		local qW = math.floor((INNER - qGap * (#QUICK - 1)) / #QUICK)
		for i = 1, #QUICK do
			local v = QUICK[i]
			local btn = S:Button(side, "+" .. v, qW, 20)
			btn:SetPoint("TOPLEFT", side, "TOPLEFT", 10 + (i - 1) * (qW + qGap), -112)
			btn:SetScript("OnClick", function(_, mouse)
				ApplyDelta(mouse == "RightButton" and -v or v)
			end)
			btn:SetScript("OnEnter", function(self)
				S:Solid(self.bg, C.paperDark)
				GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
				GameTooltip:AddLine(string.format("左键：+%d（EP 获得）", v))
				GameTooltip:AddLine(string.format("右键：-%d（GP 消耗）", v), 0.9, 0.35, 0.3)
				GameTooltip:Show()
			end)
			btn:SetScript("OnLeave", function(self)
				S:Solid(self.bg, C.paperLight)
				GameTooltip:Hide()
			end)
		end

		local postBtn = S:Button(side, "张贴到公会", INNER, 22)
		postBtn:SetPoint("TOPLEFT", side, "TOPLEFT", 10, -140)

		local undoBtn = S:Button(side, "撤销上一条", INNER, 20)
		undoBtn:SetPoint("TOPLEFT", side, "TOPLEFT", 10, -168)

		local rule2 = S:HLine(side, "line", 0.25)
		rule2:SetPoint("TOPLEFT", side, "TOPLEFT", 10, -194)
		rule2:SetPoint("TOPRIGHT", side, "TOPRIGHT", -10, -194)

		local logTitle = S:Text(side, 10, "inkFaint", "最近记录")
		logTitle:SetPoint("TOPLEFT", side, "TOPLEFT", 10, -200)

		local logRows = {}
		for i = 1, SHOW_LOG do
			local lr = CreateFrame("Frame", nil, side)
			lr:SetSize(INNER, 18)
			lr:SetPoint("TOPLEFT", side, "TOPLEFT", 10, -216 - (i - 1) * 18)

			lr.text = S:Text(lr, 10, "inkSoft", "")
			lr.text:SetPoint("LEFT", lr, "LEFT", 0, 0)
			lr.text:SetWidth(INNER - 46)
			lr.text:SetWordWrap(false)
			lr.text:SetJustifyH("LEFT")

			lr.time = S:Text(lr, 9, "inkFaint", "")
			lr.time:SetPoint("RIGHT", lr, "RIGHT", 0, 0)

			lr:SetScript("OnEnter", function(self)
				local e = self.entry
				if not e then return end
				GameTooltip:SetOwner(self, "ANCHOR_LEFT")
				GameTooltip:AddLine(string.format("%s  %+d", e.name, e.delta))
				GameTooltip:AddLine(e.reason ~= "" and e.reason or "未填写原因", 0.6, 0.6, 0.6)
				GameTooltip:AddLine(date("%Y-%m-%d %H:%M", e.at), 0.6, 0.6, 0.6)
				GameTooltip:Show()
			end)
			lr:SetScript("OnLeave", function() GameTooltip:Hide() end)

			logRows[i] = lr
		end

		-- ==================== 渲染 ====================
		local function RenderLog()
			local log = DB().log
			local n = #log
			for i = 1, SHOW_LOG do
				local lr = logRows[i]
				local entry = log[n - i + 1]
				if entry then
					lr.entry = entry
					lr.text:SetText(string.format("%s %+d", entry.name, entry.delta))
					local tone = entry.delta > 0 and C.cinnabar or C.inkSoft
					lr.text:SetTextColor(tone[1], tone[2], tone[3], 1)
					lr.time:SetText(date("%m-%d %H:%M", entry.at))
					lr:Show()
				else
					lr.entry = nil
					lr:Hide()
				end
			end
		end

		UpdateSide = function()
			local m
			for _, it in ipairs(members) do
				if it.name == selected then
					m = it
					break
				end
			end

			if not m then
				selName:SetText("未选择成员")
				selName:SetTextColor(C.inkFaint[1], C.inkFaint[2], C.inkFaint[3], 1)
				selNet:SetText("—")
				selNet:SetTextColor(C.inkFaint[1], C.inkFaint[2], C.inkFaint[3], 1)
				selMeta:SetText("在左侧点选一位成员")
				selEPGP:SetText("")
				return
			end

			local ep, gp = Peek(m.name)
			local net = ep - gp

			selName:SetText(m.name)
			local color = m.classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[m.classFile]
			if color then
				selName:SetTextColor(color.r, color.g, color.b, 1)
			else
				selName:SetTextColor(C.ink[1], C.ink[2], C.ink[3], 1)
			end

			selNet:SetText(tostring(net))
			if net > 0 then
				selNet:SetTextColor(C.cinnabar[1], C.cinnabar[2], C.cinnabar[3], 1)
			else
				selNet:SetTextColor(C.inkFaint[1], C.inkFaint[2], C.inkFaint[3], 1)
			end

			if not m.inGuild then
				selMeta:SetText("已离会 · 仅本地积分")
			elseif m.level and m.level > 0 then
				selMeta:SetText(string.format("Lv.%d · %s", m.level, m.online and "在线" or "离线"))
			else
				selMeta:SetText(m.online and "在线" or "离线")
			end

			selEPGP:SetText(string.format("EP %d · GP %d · PR %.2f", ep, gp, ep / math.max(1, gp)))
		end

		Render = function()
			-- 过滤 + 排序
			local shown = {}
			for _, m in ipairs(members) do
				if searching == "" or string.find(string.lower(m.name), searching, 1, true) then
					shown[#shown + 1] = m
				end
			end

			if sortBy == "name" then
				table.sort(shown, function(a, b) return a.name < b.name end)
			elseif sortBy == "pr" then
				table.sort(shown, function(a, b)
					local pa, pb = PR(a.name), PR(b.name)
					if pa == pb then return a.name < b.name end
					return pa > pb
				end)
			else
				table.sort(shown, function(a, b)
					local na, nb = Net(a.name), Net(b.name)
					if na == nb then return a.name < b.name end
					return na > nb
				end)
			end

			for i = 1, #shown do
				local m = shown[i]
				local row = GetRow(i)
				local net = Net(m.name)

				row.memberName = m.name
				row.nameFS:SetText(m.name)

				local color = m.inGuild and m.classFile and RAID_CLASS_COLORS
					and RAID_CLASS_COLORS[m.classFile]
				if not m.inGuild then
					row.nameFS:SetTextColor(C.inkFaint[1], C.inkFaint[2], C.inkFaint[3], 1)
				elseif color then
					row.nameFS:SetTextColor(color.r, color.g, color.b, 1)
				else
					row.nameFS:SetTextColor(C.inkSoft[1], C.inkSoft[2], C.inkSoft[3], 1)
				end

				if m.inGuild then
					row.lvFS:SetText(m.level > 0 and ("Lv." .. m.level) or "—")
				else
					row.lvFS:SetText("离会")
				end

				row.netFS:SetText(tostring(net))
				if net > 0 then
					row.netFS:SetTextColor(C.cinnabar[1], C.cinnabar[2], C.cinnabar[3], 1)
				elseif net < 0 then
					row.netFS:SetTextColor(C.inkSoft[1], C.inkSoft[2], C.inkSoft[3], 1)
				else
					row.netFS:SetTextColor(C.inkFaint[1], C.inkFaint[2], C.inkFaint[3], 1)
				end

				local isSel = (m.name == selected)
				if isSel then row.bar:Show() else row.bar:Hide() end
				S:Solid(row.bg, C.paper, isSel and 1 or 0)
				row:Show()
			end

			for i = #shown + 1, #rows do
				rows[i]:Hide()
			end

			list.content:SetHeight(math.max(1, #shown * rowH))
			list.Update()

			if #shown == 0 then
				if #members == 0 then
					empty:SetText((IsInGuild and IsInGuild())
						and "名册读取中 · 点右上「同步」"
						or "未加入公会 · 暂无本地记录")
				else
					empty:SetText("没有匹配的成员")
				end
				empty:Show()
			else
				empty:Hide()
			end

			-- 顶部统计
			local total = 0
			for _, m in ipairs(members) do total = total + Net(m.name) end
			local guildName = GetGuildInfo and (GetGuildInfo("player"))
			if type(guildName) == "string" and guildName ~= "" then
				statText:SetText(string.format("%s · %d 人 · 合计 %d 分", guildName, #shown, total))
			else
				statText:SetText(string.format("未加入公会 · 本地 %d 人 · 合计 %d 分", #shown, total))
			end

			UpdateSide()
			RenderLog()
		end

		-- ==================== 交互 ====================
		SelectMember = function(name)
			selected = name
			UpdateSide()
			-- 只动高亮，不重排（避免点一下顺序就跳）
			for _, row in ipairs(rows) do
				if row.memberName == name and row:IsShown() then
					row.bar:Show()
					S:Solid(row.bg, C.paper, 1)
				else
					row.bar:Hide()
					S:Solid(row.bg, C.paper, 0)
				end
			end
		end

		ApplyDelta = function(v)
			if not selected then
				App:Print("请先在左侧选择一位成员。")
				return
			end
			v = tonumber(v)
			if not v or v == 0 then
				App:Print("请先填写要记的分值。")
				return
			end

			local why = strtrim(reason:GetText() or "")
			AddEntry(selected, v, why)
			Render()

			App:Print(string.format("%s %s%d 分（%s）→ 现有 %d 分",
				selected, v > 0 and "+" or "", v,
				why ~= "" and why or "未填原因", Net(selected)))
		end

		-- ==================== 刷新 / 同步 ====================
		local lastRequest = 0

		local function RequestRoster()
			if not (IsInGuild and IsInGuild()) then return end
			local now = GetTime()
			if now - lastRequest < 2 then return end
			lastRequest = now
			pcall(GuildRoster)
		end

		local function Refresh(doRequest)
			members = ScanGuild()

			-- 本地有分但名册没有的（已离会 / 手动记过）也列出来
			local seen = {}
			for _, m in ipairs(members) do seen[m.name] = true end
			for name in pairs(DB().members) do
				if not seen[name] then
					members[#members + 1] = {
						name    = name,
						level   = 0,
						inGuild = false,
						online  = false,
					}
				end
			end

			Render()
			if doRequest then RequestRoster() end
		end

		local SORT_LABEL = { net = "净分 ↓", pr = "PR ↓", name = "姓名 ↑" }
		local SORT_NEXT  = { net = "pr", pr = "name", name = "net" }

		sortBtn:SetLabel(SORT_LABEL[sortBy] or "净分 ↓")
		sortBtn:SetScript("OnClick", function(self)
			sortBy = SORT_NEXT[sortBy] or "net"
			App.Core.Store:Set("dkpSort", sortBy)
			self:SetLabel(SORT_LABEL[sortBy])
			Render()
		end)

		syncBtn:SetScript("OnClick", function()
			if not (IsInGuild and IsInGuild()) then
				App:Print("当前不在公会中，只能查看本地记录。")
				return
			end
			lastRequest = 0
			Refresh(true)
			App:Print("已请求刷新公会名册。")
		end)

		search:SetScript("OnTextChanged", function(self)
			searching = string.lower(strtrim(self:GetText() or ""))
			Render()
		end)

		addBtn:SetScript("OnClick", function()
			ApplyDelta(tonumber(delta:GetText()) or 0)
		end)
		subBtn:SetScript("OnClick", function()
			local v = tonumber(delta:GetText()) or 0
			ApplyDelta(v > 0 and -v or v)
		end)

		reason:SetScript("OnEnterPressed", function(self)
			self:ClearFocus()
			ApplyDelta(tonumber(delta:GetText()) or 0)
		end)
		delta:SetScript("OnEnterPressed", function(self)
			self:ClearFocus()
			ApplyDelta(tonumber(self:GetText()) or 0)
		end)

		undoBtn:SetScript("OnClick", function()
			local last = UndoLast()
			if not last then
				App:Print("没有可撤销的记录。")
				return
			end
			Render()
			App:Print(string.format("已撤销：%s %+d 分", last.name, last.delta))
		end)

		-- 张贴到公会：第一次点击进入确认态，3 秒内再点才真正发出
		local postArmed = false
		postBtn:SetScript("OnClick", function(self)
			if not selected then
				App:Print("请先在左侧选择一位成员。")
				return
			end

			if not postArmed then
				postArmed = true
				self:SetLabel("再点一次确认")
				App.Core.Time:After(3, function()
					if postArmed then
						postArmed = false
						self:SetLabel("张贴到公会")
					end
				end)
				return
			end

			postArmed = false
			self:SetLabel("张贴到公会")

			if not (IsInGuild and IsInGuild()) then
				App:Print("不在公会中，无法张贴。")
				return
			end

			local ep, gp = Peek(selected)
			SendChatMessage(string.format("[DKP] %s 现有 %d 分（EP %d / GP %d）",
				selected, ep - gp, ep, gp), "GUILD")
		end)

		-- ==================== 事件 ====================
		App.Core.Event:On("GUILD_ROSTER_UPDATE", function()
			if page:IsShown() then Refresh(false) end
		end)
		App.Core.Event:On("PLAYER_ENTERING_WORLD", function()
			if page:IsShown() then Refresh(false) end
		end)
		App.Core.Event:OnMsg("MZ_PAGE_CHANGED", function(a, b)
			-- Event:Send 会把事件名当首个参数传进来，故也兼容只有一个参数的情况
			local id = b or a
			if id ~= "dkp" then return end
			Refresh(true)
		end)

		Refresh(true)
	end,
}
