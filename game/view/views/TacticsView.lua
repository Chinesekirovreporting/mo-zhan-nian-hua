-- ============================================================
-- View · 战术绘画板
-- 骨架：game/skin/TacticsView.xml。笔画随 model.strokes 生成。
-- 点击只进 TacticsModule，这里不发插件消息。
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App

local TacticsView = App.newclz("TacticsView", App.AbstractView)

local TOOLS = {
	{ id = "P", name = "MZTacticsToolP" },
	{ id = "L", name = "MZTacticsToolL" },
	{ id = "A", name = "MZTacticsToolA" },
	{ id = "R", name = "MZTacticsToolR" },
	{ id = "E", name = "MZTacticsToolE" },
	{ id = "T", name = "MZTacticsToolT" },
}

function TacticsView:ctor()
	App.AbstractView.ctor(self, {
		id       = "tactics",
		title    = "战术绘画板",
		subtitle = "队长发笔，松手后小队和团队都能看见",
		order    = 12.5,
		frame    = "MZPageTactics",
	})
end

function TacticsView:Mod()
	return App.GameModules.Tactics
end

function TacticsView:onBuild()
	local W = App.Widget
	local view = self
	local mod = self:Mod()
	self.canvas = _G["MZTacticsCanvas"]
	self.tool = "P"
	self.color = 1
	self.textAt = nil
	self.dragging = false
	self.draft = nil
	self.texPool = {}
	self.fontPool = {}
	self.usedTex = 0
	self.usedFont = 0
	self.baseTex = 0
	self.baseFont = 0
	self.tools = {}

	local i = 1
	while i <= #TOOLS do
		local info = TOOLS[i]
		local btn = _G[info.name]
		self.tools[info.id] = btn
		W:TuneButton(btn, 12, info.id == "P")
		App.Hook:Bind(btn, "OnClick", function()
			view:SetTool(info.id)
		end)
		i = i + 1
	end

	i = 1
	while i <= #mod.COLORS do
		local btn = _G["MZTacticsColor" .. i]
		local index = i
		App.Hook:Bind(btn, "OnClick", function()
			view:SetColor(index)
		end)
		i = i + 1
	end
	self:PaintColors()

	local penBtn = _G["MZTacticsPenBtn"]
	local undoBtn = _G["MZTacticsUndo"]
	local clearBtn = _G["MZTacticsClear"]
	local textOk = _G["MZTacticsTextOk"]
	local box = _G["MZTacticsText"]
	W:TuneButton(penBtn, 12)
	W:TuneButton(undoBtn, 12)
	W:TuneButton(clearBtn, 12)
	W:TuneButton(textOk, 12)
	W:PaintText(_G["MZTacticsPen"], 12, "inkSoft")
	App:SetFont(box, 13)
	box:SetTextColor(App.C.ink[1], App.C.ink[2], App.C.ink[3], 1)
	box:SetAutoFocus(false)
	box:SetMaxLetters(72)

	App.Hook:Bind(penBtn, "OnClick", function()
		local board = view:Mod()
		if board.model.holder == board:Me() then
			board:DropPen()
		else
			board:TakePen()
		end
	end)
	App.Hook:Bind(undoBtn, "OnClick", function()
		view:Mod():Undo()
	end)
	App.Hook:Bind(clearBtn, "OnClick", function()
		view:Mod():ClearBoard()
	end)
	App.Hook:Bind(textOk, "OnClick", function()
		view:CommitText()
	end)
	App.Hook:Bind(box, "OnEnterPressed", function(self)
		view:CommitText()
		self:ClearFocus()
	end)
	App.Hook:Bind(box, "OnEscapePressed", function(self)
		self:ClearFocus()
	end)

	App.Hook:Bind(self.canvas, "OnMouseDown", function(_, button)
		if button == "LeftButton" then view:Begin() end
	end)
	App.Hook:Bind(self.canvas, "OnMouseUp", function(_, button)
		if button == "LeftButton" then view:Finish() end
	end)
	App.Hook:Bind(self.canvas, "OnUpdate", function()
		if not view.dragging then return end
		if not IsMouseButtonDown("LeftButton") then
			view:Finish()
			return
		end
		view:Extend()
	end)
	App.Hook:Bind(self.canvas, "OnSizeChanged", function()
		view:Redraw()
	end)

	mod:on("sync", function()
		view:Refresh()
	end)
	self:SetTool("P")
	self:Refresh()
end

function TacticsView:onShow()
	self:Refresh()
end

function TacticsView:SetTool(tool)
	self.tool = tool
	local W = App.Widget
	for id, btn in pairs(self.tools) do
		W:ApplyTone(btn, id == tool)
	end
	self:Redraw()
end

function TacticsView:SetColor(index)
	self.color = index
	self:PaintColors()
	self:Redraw()
end

function TacticsView:PaintColors()
	local colors = self:Mod().COLORS
	local i = 1
	while i <= #colors do
		local bg = _G["MZTacticsColor" .. i .. "Bg"]
		local mark = _G["MZTacticsColor" .. i .. "Mark"]
		local c = colors[i]
		if bg and c then bg:SetVertexColor(c[1], c[2], c[3], 1) end
		if mark then
			if i == self.color then mark:Show() else mark:Hide() end
		end
		i = i + 1
	end
end

function TacticsView:PenText(model)
	local mod = self:Mod()
	if not model.inGroup then return "单人，只在本机" end
	if model.holder == "" then return "笔闲着" end
	if model.holder == mod:Me() then return "你在持笔" end
	return "持笔：" .. model.holder
end

function TacticsView:Refresh()
	local mod = self:Mod()
	local model = mod.model
	local pen = _G["MZTacticsPen"]
	local btn = _G["MZTacticsPenBtn"]
	if pen then pen:SetText(self:PenText(model)) end
	if btn then
		if not model.inGroup then
			btn:SetText("单人")
			btn:Disable()
		else
			btn:Enable()
			if model.holder == mod:Me() then
				btn:SetText("放下")
			else
				btn:SetText("拿笔")
			end
		end
	end
	self:Redraw()
end

function TacticsView:Cursor()
	local canvas = self.canvas
	if not canvas then return nil end
	local scale = canvas:GetEffectiveScale()
	local left, top = canvas:GetLeft(), canvas:GetTop()
	local w, h = canvas:GetWidth(), canvas:GetHeight()
	if not scale or scale == 0 or not left or not top or not w or not h or w < 2 or h < 2 then
		return nil
	end
	local cx, cy = GetCursorPosition()
	local px = cx / scale - left
	local py = top - cy / scale
	if px < 0 then px = 0 elseif px > w then px = w end
	if py < 0 then py = 0 elseif py > h then py = h end
	local nx = math.floor(px / w * 999 + 0.5)
	local ny = math.floor(py / h * 999 + 0.5)
	if nx < 0 then nx = 0 elseif nx > 999 then nx = 999 end
	if ny < 0 then ny = 0 elseif ny > 999 then ny = 999 end
	return nx, ny
end

function TacticsView:Begin()
	local mod = self:Mod()
	if not mod:CanDraw() then return end
	local x, y = self:Cursor()
	if not x then return end
	if self.tool == "T" then
		self.textAt = { x = x, y = y }
		_G["MZTacticsText"]:SetFocus()
		self:Redraw()
		return
	end
	self.dragging = true
	self.draft = {
		tool = self.tool,
		color = self.color,
		points = { { x = x, y = y } },
		text = "",
	}
	self:RedrawDraft()
end

function TacticsView:Extend()
	if not self.dragging or not self.draft then return end
	local x, y = self:Cursor()
	if not x then return end
	local pts = self.draft.points
	local last = pts[#pts]
	if self.draft.tool == "P" then
		local dx, dy = x - last.x, y - last.y
		if dx * dx + dy * dy >= 36 and #pts < 80 then
			pts[#pts + 1] = { x = x, y = y }
		end
	else
		pts[2] = { x = x, y = y }
	end
	self:RedrawDraft()
end

function TacticsView:Finish()
	if not self.dragging or not self.draft then
		self.dragging = false
		return
	end
	local x, y = self:Cursor()
	local pts = self.draft.points
	if x then
		if self.draft.tool == "P" then
			local last = pts[#pts]
			if (not last or last.x ~= x or last.y ~= y) and #pts < 80 then
				pts[#pts + 1] = { x = x, y = y }
			end
		else
			pts[2] = { x = x, y = y }
		end
	end
	local draft = self.draft
	self.draft = nil
	self.dragging = false
	local ok = self:Mod():SubmitStroke(draft.tool, draft.color, draft.points, draft.text)
	if not ok then self:Redraw() end
end

function TacticsView:CommitText()
	local at = self.textAt
	if not at then return end
	local box = _G["MZTacticsText"]
	local ok = self:Mod():SubmitStroke("T", self.color, { { x = at.x, y = at.y } }, box:GetText())
	if not ok then return end
	box:SetText("")
	box:ClearFocus()
	self.textAt = nil
	self:Redraw()
end

function TacticsView:Px(nx, ny)
	return (nx / 999) * self.canvas:GetWidth(), (ny / 999) * self.canvas:GetHeight()
end

function TacticsView:ColorOf(index)
	local list = self:Mod().COLORS
	return list[index] or list[1]
end

function TacticsView:TakeTex()
	self.usedTex = self.usedTex + 1
	local tex = self.texPool[self.usedTex]
	if not tex then
		tex = self.canvas:CreateTexture(nil, "ARTWORK")
		tex:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
		self.texPool[self.usedTex] = tex
	end
	return tex
end

function TacticsView:TakeFont()
	self.usedFont = self.usedFont + 1
	local fs = self.fontPool[self.usedFont]
	if not fs then
		fs = self.canvas:CreateFontString(nil, "OVERLAY")
		fs:SetJustifyH("CENTER")
		fs:SetJustifyV("MIDDLE")
		self.fontPool[self.usedFont] = fs
	end
	return fs
end

function TacticsView:HideUnused()
	local i = self.usedTex + 1
	while i <= #self.texPool do
		self.texPool[i]:Hide()
		i = i + 1
	end
	i = self.usedFont + 1
	while i <= #self.fontPool do
		self.fontPool[i]:Hide()
		i = i + 1
	end
end

function TacticsView:Line(x1, y1, x2, y2, color, thick)
	local dx, dy = x2 - x1, y2 - y1
	local len = math.sqrt(dx * dx + dy * dy)
	if len < 0.4 then return end
	local tex = self:TakeTex()
	tex:SetVertexColor(color[1], color[2], color[3], 1)
	tex:SetSize(math.max(len, 1), thick or 2)
	tex:ClearAllPoints()
	tex:SetPoint("CENTER", self.canvas, "TOPLEFT", (x1 + x2) / 2, -((y1 + y2) / 2))
	if tex.SetRotation then
		tex:SetRotation(math.atan2(-dy, dx))
	end
	tex:Show()
end

function TacticsView:Dot(x, y, color)
	local tex = self:TakeTex()
	tex:SetVertexColor(color[1], color[2], color[3], 1)
	tex:SetSize(4, 4)
	tex:ClearAllPoints()
	tex:SetPoint("CENTER", self.canvas, "TOPLEFT", x, -y)
	if tex.SetRotation then tex:SetRotation(0) end
	tex:Show()
end

function TacticsView:Head(x1, y1, x2, y2, color)
	local dx, dy = x2 - x1, y2 - y1
	local len = math.sqrt(dx * dx + dy * dy)
	if len < 1 then return end
	local ux, uy = dx / len, dy / len
	local px, py = -uy, ux
	local bx, by = x2 - ux * 9, y2 - uy * 9
	self:Line(x2, y2, bx + px * 11, by + py * 11, color, 2)
	self:Line(x2, y2, bx - px * 11, by - py * 11, color, 2)
end

function TacticsView:Oval(x1, y1, x2, y2, color)
	local cx, cy = (x1 + x2) / 2, (y1 + y2) / 2
	local rx, ry = math.abs(x2 - x1) / 2, math.abs(y2 - y1) / 2
	if rx < 0.5 then rx = 0.5 end
	if ry < 0.5 then ry = 0.5 end
	local n, i = 20, 0
	local prevx, prevy
	while i <= n do
		local a = (i % n) / n * math.pi * 2
		local x = cx + rx * math.cos(a)
		local y = cy + ry * math.sin(a)
		if prevx then self:Line(prevx, prevy, x, y, color, 2) end
		prevx, prevy = x, y
		i = i + 1
	end
end

function TacticsView:DrawStroke(stroke)
	local color = self:ColorOf(stroke.color)
	local pts = stroke.points or {}
	if stroke.tool == "T" then
		if not pts[1] then return end
		local px, py = self:Px(pts[1].x, pts[1].y)
		local fs = self:TakeFont()
		fs:ClearAllPoints()
		fs:SetPoint("CENTER", self.canvas, "TOPLEFT", px, -py)
		App:SetFont(fs, 14)
		fs:SetTextColor(color[1], color[2], color[3], 1)
		fs:SetText(stroke.text or "")
		fs:Show()
		return
	end
	if stroke.tool == "P" then
		if #pts == 0 then return end
		if #pts == 1 then
			local x, y = self:Px(pts[1].x, pts[1].y)
			self:Dot(x, y, color)
			return
		end
		local i = 2
		while i <= #pts do
			local x1, y1 = self:Px(pts[i - 1].x, pts[i - 1].y)
			local x2, y2 = self:Px(pts[i].x, pts[i].y)
			self:Line(x1, y1, x2, y2, color, 2)
			i = i + 1
		end
		return
	end
	if #pts < 2 then return end
	local x1, y1 = self:Px(pts[1].x, pts[1].y)
	local x2, y2 = self:Px(pts[2].x, pts[2].y)
	if stroke.tool == "L" or stroke.tool == "A" then
		self:Line(x1, y1, x2, y2, color, 2)
		if stroke.tool == "A" then self:Head(x1, y1, x2, y2, color) end
	elseif stroke.tool == "R" then
		self:Line(x1, y1, x2, y1, color, 2)
		self:Line(x2, y1, x2, y2, color, 2)
		self:Line(x2, y2, x1, y2, color, 2)
		self:Line(x1, y2, x1, y1, color, 2)
	elseif stroke.tool == "E" then
		self:Oval(x1, y1, x2, y2, color)
	end
end

function TacticsView:Redraw()
	if not self.canvas then return end
	local w, h = self.canvas:GetWidth(), self.canvas:GetHeight()
	if not w or not h or w < 2 or h < 2 then return end
	self.usedTex = 0
	self.usedFont = 0
	local model = self:Mod().model
	local strokes = model.strokes or {}
	local i = 1
	while i <= #strokes do
		self:DrawStroke(strokes[i])
		i = i + 1
	end
	if model.pending then self:DrawStroke(model.pending) end
	if self.tool == "T" and self.textAt then
		local x, y = self:Px(self.textAt.x, self.textAt.y)
		self:Dot(x, y, self:ColorOf(self.color))
	end
	self.baseTex = self.usedTex
	self.baseFont = self.usedFont
	if self.draft then self:DrawStroke(self.draft) end
	self:HideUnused()
end

function TacticsView:RedrawDraft()
	if not self.canvas then return end
	self.usedTex = self.baseTex or 0
	self.usedFont = self.baseFont or 0
	if self.draft then self:DrawStroke(self.draft) end
	self:HideUnused()
end

TacticsView:new():register()
