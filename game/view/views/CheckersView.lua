-- ============================================================
-- View · 六角跳棋
-- 骨架：game/skin/CheckersView.xml。格子和座位在本文件生成。
--   左：星形棋盘  右：六个彩色座位 + 观战人数 + 准备 / 重开
--   只做绘制与点击，规则、状态、联机全在 CheckersModule
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App
local S = App.Widget
local G = App.GameModules.Checkers
local C = App.C

local CELL   = 21                 -- 横向一格像素
local VSTEP  = CELL * 0.86603     -- 行距
local PIECE  = 17
local DOT    = "Interface\\AddOns\\" .. ADDON_NAME .. "\\game\\media\\dot.tga"
local RING   = "Interface\\AddOns\\" .. ADDON_NAME .. "\\game\\media\\ring.tga"

local boardFrame
local cellBtn  = {}               -- [id] = Button
local seatRow  = {}               -- [1..6] = Frame
local fsState, fsHint, fsWatch, fsNames
local btnMain, btnNew, btnDemo
local sel = nil                   -- { path = {id...}, cur = id, visited = {}, legal = {} }

-- ------------------------------------------------------------
-- 小工具
-- ------------------------------------------------------------
local function Tex(parent, layer, path, size)
	local t = parent:CreateTexture(nil, layer)
	t:SetTexture(path)
	t:SetSize(size, size)
	t:SetPoint("CENTER")
	return t
end

local function Tint(t, color, alpha)
	t:SetVertexColor(color[1], color[2], color[3])
	t:SetAlpha(alpha or 1)
end

local function ShortName(name)
	name = tostring(name or "")
	if #name > 8 then return name:sub(1, 7) .. "…" end
	return name
end

local FACE_HINT = "不在对面：各跑空营，互不阻挡"
local LINK_HINT = "没收到回应：确认对方同队或同会"

local function Hint(text)
	if fsHint then fsHint:SetText(text or "") end
end

-- 状态自动写上去的提示（链路异常 / 座位被抢 / 房主拒绝…）：
-- 条件消失后必须能自己撤掉，否则会一直黏在提示行上，
-- 把「点高亮处落子」这类走子提示挤没。
local autoHint = nil
local function SetAutoHint(text)
	if text then
		autoHint = text
		Hint(text)
	else
		if autoHint and fsHint and fsHint:GetText() == autoHint then Hint("") end
		autoHint = nil
	end
end

-- ------------------------------------------------------------
-- 棋盘
-- ------------------------------------------------------------
local function RefreshBoard()
	if not boardFrame then return end
	for id = 1, G.CELL_COUNT do
		local b = cellBtn[id]
		local v = G.board[id] or 0
		if v > 0 then
			Tint(b.piece, G.SEAT_COLORS[v] or C.ink, 1)
			b.piece:Show()
			b.dot:Hide()
		else
			b.piece:Hide()
			b.dot:Show()
		end
		b.selRing:Hide()
		b.hiRing:Hide()
	end
end

local function ApplySel()
	if not sel then return end
	cellBtn[sel.cur].selRing:Show()
	for id in pairs(sel.legal or {}) do
		cellBtn[id].hiRing:Show()
	end
end

local function ClearSel()
	sel = nil
	RefreshBoard()
end

local function RecalcSel()
	if not sel then return end
	local legal = {}
	if #sel.path == 1 then
		for _, t in ipairs(G:StepTargets(G.board, sel.cur)) do legal[t] = true end
	end
	for _, t in ipairs(G:JumpTargets(G.board, sel.cur)) do
		if not sel.visited[t] then legal[t] = true end
	end
	sel.legal = legal
end

local function SubmitSel()
	if not sel then return end
	local path = sel.path
	sel = nil
	local ok, err = G:SubmitMove(path)
	Hint(ok and "" or (err or "这一手没走成"))
	RefreshBoard()
end

local function OnCellClick(id, button)
	-- 右键：连跳途中落定，否则取消选择
	if button == "RightButton" then
		if sel and #sel.path >= 2 then
			SubmitSel()
		else
			ClearSel()
			Hint("")
		end
		return
	end

	if G.phase ~= "play" then
		Hint(G.phase == "wait" and "全员就绪后自动开局（两人即可）。" or "本局已结束，房主可点「重开」。")
		return
	end

	local my = G:MySeat()
	if not my then
		Hint("先占一个座位：点右侧空座。")
		return
	end
	if G.turn ~= my then
		Hint("还没轮到你。")
		return
	end

	if sel and sel.legal and sel.legal[id] then
		local isStep = (#sel.path == 1) and G:IsNeighbor(sel.cur, id)
		sel.path[#sel.path + 1] = id
		sel.visited[id] = true
		sel.cur = id
		if isStep then
			SubmitSel()
			return
		end
		RecalcSel()
		if next(sel.legal) == nil then
			SubmitSel()
		else
			RefreshBoard()
			ApplySel()
			Hint("还能接着跳；右键落定。")
		end
		return
	end

	if sel and id == sel.cur then
		ClearSel()
		Hint("")
		return
	end

	if G.board[id] == my then
		ClearSel()
		sel = { path = { id }, cur = id, visited = { [id] = true } }
		RecalcSel()
		RefreshBoard()
		ApplySel()
		Hint("点高亮处落子；右键取消。")
	else
		Hint("这枚不是你的棋子。")
	end
end

local function BuildBoard(parent)
	boardFrame = CreateFrame("Frame", nil, parent)
	boardFrame:SetSize(272, 310)
	boardFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
	S:Paint(boardFrame, "paperLight", 0.5)
	S:Stroke(boardFrame, "line", 0, 0.3)

	for id = 1, G.CELL_COUNT do
		local c = G.cells[id]
		local b = CreateFrame("Button", nil, boardFrame)
		b:SetSize(20, 20)
		b:SetPoint("CENTER", boardFrame, "CENTER", c.x * CELL, c.y * VSTEP)
		b.id = id

		b.arm = Tex(b, "BACKGROUND", DOT, 22)
		b.dot = Tex(b, "ARTWORK", DOT, 5)
		b.piece = Tex(b, "OVERLAY", DOT, PIECE)
		b.hiRing = Tex(b, "HIGHLIGHT", RING, 22)
		b.selRing = Tex(b, "HIGHLIGHT", RING, 26)

		if c.arm > 0 then
			Tint(b.arm, G.SEAT_COLORS[c.arm], 0.13)
		else
			b.arm:Hide()
		end
		Tint(b.dot, C.inkFaint, 0.55)
		Tint(b.hiRing, { 0.851, 0.647, 0.216 }, 0.9)
		Tint(b.selRing, C.cinnabar, 1)
		b.piece:Hide()
		b.hiRing:Hide()
		b.selRing:Hide()

		b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		App.Hook:Bind(b, "OnClick", function(self, button) OnCellClick(self.id, button) end)
		App.Hook:Bind(b, "OnEnter", function(self)
			if sel and sel.legal and sel.legal[self.id] then
				self.dot:SetAlpha(1)
			end
		end)
		App.Hook:Bind(b, "OnLeave", function(self)
			self.dot:SetAlpha(0.55)
		end)

		cellBtn[id] = b
	end

	-- 星形相对中心上下左右对称，格心直接按坐标居中即可
	return boardFrame
end

-- ------------------------------------------------------------
-- 右侧座位栏
-- ------------------------------------------------------------
local function RefreshSeats()
	if not seatRow[1] then return end

	for i = 1, 6 do
		local row, s = seatRow[i], G.seats[i]
		local col = G.SEAT_COLORS[i]

		if s then
			S:Solid(row.bg, C.paperLight, 0.95)
			Tint(row.chip, col, 1)
			row.chip:Show()
			row.name:SetText(ShortName(s.name))
			if s.name == G:Me() then
				row.name:SetTextColor(C.ink[1], C.ink[2], C.ink[3], 1)
			else
				row.name:SetTextColor(C.inkSoft[1], C.inkSoft[2], C.inkSoft[3], 1)
			end
			row.ready:SetText(s.ready and "已备" or "待备")
			if s.ready then
				row.ready:SetTextColor(C.cinnabar[1], C.cinnabar[2], C.cinnabar[3], 1)
			else
				row.ready:SetTextColor(C.inkFaint[1], C.inkFaint[2], C.inkFaint[3], 1)
			end
		else
			S:Solid(row.bg, C.paper, 0.25)
			row.chip:Hide()
			row.name:SetText("空座")
			row.name:SetTextColor(C.inkFaint[1], C.inkFaint[2], C.inkFaint[3], 0.9)
			row.ready:SetText("")
		end

		if G.phase == "play" and G.turn == i then
			row.bar:Show()
		else
			row.bar:Hide()
		end
	end

	-- 状态行
	if G.phase == "play" then
		local seat = G.turn
		local nm = seat and G.seats[seat] and ShortName(G.seats[seat].name) or "?"
		fsState:SetText("轮到 " .. (G.SEAT_NAMES[seat or 1] or "?") .. "号 " .. nm)
	elseif G.phase == "over" then
		local w = G.winner
		local nm = w and G.seats[w] and ShortName(G.seats[w].name) or "?"
		fsState:SetText((G.SEAT_NAMES[w or 1] or "?") .. "号 " .. nm .. " 胜")
	else
		fsState:SetText(string.format("等待中 · 就绪 %d/%d", G:ReadyCount(), G:SeatedCount()))
	end

	-- 观战
	local list = G:Spectators()
	fsWatch:SetText("观战 " .. #list .. " 人")
	if #list == 0 then
		fsNames:SetText("面板开着的人会记在这里。")
	else
		local text = table.concat(list, "、")
		if #text > 34 then text = text:sub(1, 33) .. "…" end
		fsNames:SetText(text)
	end

	-- 主按钮
	local mySeat = G:MySeat()
	if G.phase ~= "wait" then
		btnMain:SetLabel("对局中")
		btnMain:Disable()
	elseif not mySeat then
		btnMain:SetLabel("入座")
		btnMain:Enable()
	else
		btnMain:SetLabel(G.seats[mySeat].ready and "取消准备" or "准备")
		btnMain:Enable()
	end

	if G.phase == "wait" then
		btnNew:Hide()
	else
		btnNew:Show()
	end

	-- 演练中要留一个出口：否则 mute 一直挂着，之后再也连不上真桌子
	if G.mute then
		btnDemo:SetLabel("退出演练")
		btnDemo:Show()
	elseif G.phase == "wait" and G:SeatedCount() == 0 then
		btnDemo:SetLabel("本机演练")
		btnDemo:Show()
	else
		btnDemo:Hide()
	end

	-- 提示优先级：房主拒绝的原因 > 座位被抢先 > 连不上对方 > 两人没坐成对面
	local auto
	local now = GetTime()
	if G.lastError and now - (G.lastErrorAt or 0) <= 5 then
		auto = G.lastError
	elseif G.phase == "wait" and G.raceLost and now - (G.raceLostAt or 0) <= 6 then
		auto = (G.SEAT_NAMES[G.raceLost] or "该") .. "号座已归他人，请重新选座"
	elseif G.hostSilent then
		auto = "等不到房主：牌局可能已卡住"
	elseif G.phase == "wait" and G.linkSuspect then
		auto = LINK_HINT
	elseif G.phase == "wait" and G:TwoSomeFacing() == false then
		auto = FACE_HINT
	end
	SetAutoHint(auto)
end

local function Refresh()
	if not boardFrame then return end
	RefreshBoard()
	ApplySel()
	RefreshSeats()
end

local function BuildPanel(parent)
	local panel = CreateFrame("Frame", nil, parent)
	panel:SetSize(182, 310)
	panel:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)

	fsState = S:Text(panel, 12, "ink")
	fsState:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
	fsState:SetWidth(182)

	fsHint = S:Text(panel, 11, "cinnabar")
	fsHint:SetPoint("TOPLEFT", fsState, "BOTTOMLEFT", 0, -5)
	fsHint:SetWidth(182)

	fsWatch = S:Text(panel, 12, "inkSoft")
	fsWatch:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -40)

	fsNames = S:Text(panel, 11, "inkFaint")
	fsNames:SetPoint("TOPLEFT", fsWatch, "BOTTOMLEFT", 0, -5)
	fsNames:SetWidth(182)
	fsNames:SetJustifyH("LEFT")

	local rule = S:HLine(panel, "line", 0.3)
	rule:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -92)
	rule:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -92)

	for i = 1, 6 do
		local row = CreateFrame("Button", nil, panel)
		row:SetSize(182, 27)
		row:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -96 - (i - 1) * 30)

		row.bg = row:CreateTexture(nil, "BACKGROUND")
		row.bg:SetAllPoints(row)

		row.bar = row:CreateTexture(nil, "ARTWORK")
		row.bar:SetWidth(3)
		row.bar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -3)
		row.bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 3)
		S:Solid(row.bar, C.cinnabar)

		row.chip = Tex(row, "ARTWORK", DOT, 11)
		row.chip:SetPoint("CENTER")
		row.chip:ClearAllPoints()
		row.chip:SetPoint("LEFT", row, "LEFT", 10, 0)

		row.num = S:Text(row, 11, "inkFaint", G.SEAT_NAMES[i] .. "号")
		row.num:SetPoint("LEFT", row, "LEFT", 22, 0)

		row.name = S:Text(row, 12, "inkSoft")
		row.name:SetPoint("LEFT", row, "LEFT", 56, 0)
		row.name:SetWidth(84)
		row.name:SetWordWrap(false)

		row.ready = S:Text(row, 11, "inkFaint")
		row.ready:SetPoint("RIGHT", row, "RIGHT", -8, 0)

		App.Hook:Bind(row, "OnClick", function()
			if G.phase ~= "wait" then
				Hint("对局已开始，等下一局。")
				return
			end
			local mine = G:MySeat()
			if mine == i then
				local ok, err = G:Leave()
				if not ok then Hint(err) end
			elseif G.seats[i] then
				Hint(G.seats[i].name .. " 已占这一座。")
			else
				local ok, err = G:Sit(i)
				if not ok then Hint(err) end
			end
		end)
		App.Hook:Bind(row, "OnEnter", function() S:Solid(row.bg, C.paperDark, 0.35) end)
		App.Hook:Bind(row, "OnLeave", function() RefreshSeats() end)

		seatRow[i] = row
	end

	btnMain = S:Button(panel, "入座", 86, 26, true)
	btnMain:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -280)
	App.Hook:Bind(btnMain, "OnClick", function()
		local my = G:MySeat()
		if not my then
			local ok, err = G:SitFirstFree()
			if not ok then Hint(err) end
		else
			local ok, err = G:ToggleReady()
			if not ok then Hint(err) end
		end
	end)

	btnNew = S:Button(panel, "重开", 86, 26)
	btnNew:SetPoint("TOPLEFT", panel, "TOPLEFT", 96, -280)
	App.Hook:Bind(btnNew, "OnClick", function()
		local ok, err = G:Restart()
		if not ok and err then Hint(err) end
	end)
	btnNew:Hide()

	btnDemo = S:Button(panel, "本机演练", 86, 16)
	btnDemo:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -310)
	App.Hook:Bind(btnDemo, "OnClick", function() G:Demo() end)
	btnDemo:Hide()

	return panel
end

-- ------------------------------------------------------------
-- 页签注册
-- ------------------------------------------------------------
local CheckersView = App.newclz("CheckersView", App.AbstractView)

function CheckersView:ctor()
	App.AbstractView.ctor(self, {
		id       = "checkers",
		title    = "六角跳棋",
		subtitle = "两人起坐 · 全员就绪即开局",
		order    = 12,
		frame    = "MZPageCheckers",
	})
end

function CheckersView:onBuild(p, b)
		BuildBoard(b)
		BuildPanel(b)

		local function OnPanelShow()
			G:Send("R")
			Refresh()
			if App.Core.Net and not App.Core.Net:Available() then
				Hint("未组队 / 未入公会：这一桌只有你自己看得见。")
			end
		end

		-- 页签每次被切出来；主面板每次被打开，都重新要一次房主快照
		App.Hook:Attach(p, "OnShow", OnPanelShow)
		if App.UI.frame then
			App.Hook:Attach(App.UI.frame, "OnShow", function() G:Send("R") end)
		end
		OnPanelShow()
	end

CheckersView:new():register()


App.eventManager:on(App.Ev.CHECKERS_CHANGED, function()
	Refresh()
end)
