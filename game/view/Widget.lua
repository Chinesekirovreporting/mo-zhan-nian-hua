-- ============================================================
-- Widget · 和 game/skin/Templates.xml 对应
-- 静态骨架在 XML 里。这里只给重复出现的行、按钮、输入框套模板，
-- 以及棋盘、名单这种 XML 写不出循环的动态节点。
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App
local C = App.C

local Widget = {}
App.Widget = Widget
Widget._seq = 0

function Widget:Solid(tex, color, alpha)
	if not tex or not color then return end
	local a = alpha or color[4] or 1
	if tex.SetColorTexture then
		tex:SetColorTexture(color[1], color[2], color[3], a)
	else
		tex:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
		tex:SetVertexColor(color[1], color[2], color[3], a)
	end
end

function Widget:Paint(frame, tone, alpha)
	local t = frame:CreateTexture(nil, "BACKGROUND")
	t:SetAllPoints(frame)
	self:Solid(t, C[tone or "paper"], alpha)
	frame.paper = t
	return t
end

function Widget:Stroke(frame, tone, inset, alpha)
	inset = inset or 0
	frame.__strokes = frame.__strokes or {}
	local s = frame.__strokes[inset]
	if not s then
		s = {}
		for i = 1, 4 do s[i] = frame:CreateTexture(nil, "BORDER") end
		frame.__strokes[inset] = s
	end

	local color = C[tone or "line"]

	s[1]:ClearAllPoints()
	s[1]:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
	s[1]:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -inset, -inset)
	s[1]:SetHeight(1)

	s[2]:ClearAllPoints()
	s[2]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", inset, inset)
	s[2]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
	s[2]:SetHeight(1)

	s[3]:ClearAllPoints()
	s[3]:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
	s[3]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", inset, inset)
	s[3]:SetWidth(1)

	s[4]:ClearAllPoints()
	s[4]:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -inset, -inset)
	s[4]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
	s[4]:SetWidth(1)

	for i = 1, 4 do self:Solid(s[i], color, alpha) end
	return frame
end

function Widget:HLine(parent, tone, alpha)
	local t = parent:CreateTexture(nil, "ARTWORK")
	t:SetHeight(1)
	self:Solid(t, C[tone or "line"], alpha)
	return t
end

function Widget:VLine(parent, tone, alpha)
	local t = parent:CreateTexture(nil, "ARTWORK")
	t:SetWidth(1)
	self:Solid(t, C[tone or "line"], alpha)
	return t
end

function Widget:Text(parent, size, tone, text, flags)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	return self:PaintText(fs, size, tone, text, flags)
end

function Widget:PaintText(fs, size, tone, text, flags)
	App:SetFont(fs, size or 13, flags)
	local color = C[tone or "ink"]
	fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
	if text then fs:SetText(text) end
	return fs
end

function Widget:_nextName(prefix)
	self._seq = self._seq + 1
	return (prefix or "MZDyn") .. self._seq
end

function Widget:ApplyTone(button, primary)
	button.tone = primary and "primary" or "normal"
	local name = button:GetName()
	local bg = name and _G[name .. "Bg"]
	local fs = button.GetFontString and button:GetFontString()
	button.bg = bg or button.bg
	button.label = fs or button.label
	if primary then
		if bg then bg:SetVertexColor(0.702, 0.196, 0.157, 1) end
		if fs then fs:SetTextColor(0.949, 0.925, 0.867, 1) end
	else
		if bg then bg:SetVertexColor(0.949, 0.925, 0.867, 1) end
		if fs then fs:SetTextColor(0.106, 0.098, 0.086, 1) end
	end
	return button
end

function Widget:TuneButton(button, size, primary)
	local fs = button.GetFontString and button:GetFontString()
	if fs then App:SetFont(fs, size or 13) end
	return self:ApplyTone(button, primary)
end

-- 外观在 MZButtonTemplate。primary 走朱砂。
function Widget:Button(parent, text, width, height, primary)
	local name = self:_nextName("MZDynBtn")
	local b = CreateFrame("Button", name, parent, "MZButtonTemplate")
	b:SetSize(width or 96, height or 26)
	b:SetText(text or "")
	self:TuneButton(b, 13, primary)
	function b:SetLabel(str)
		self:SetText(str or "")
	end
	return b
end

function Widget:EditBox(parent, width, height)
	local name = self:_nextName("MZDynEdit")
	local e = CreateFrame("EditBox", name, parent, "MZEditBoxTemplate")
	e:SetSize(width or 80, height or 26)
	e:SetAutoFocus(false)
	e:SetMaxLetters(12)
	App:SetFont(e, 13)
	e:SetTextColor(C.ink[1], C.ink[2], C.ink[3], 1)
	return e
end

function Widget:Card(parent, height)
	local name = self:_nextName("MZDynCard")
	local card = CreateFrame("Frame", name, parent, "MZCardTemplate")
	card:SetHeight(height or 76)
	card.title = _G[name .. "Title"]
	card.desc = _G[name .. "Desc"]
	return card
end

-- 滚动区。外观能放进 XML 的（已有具名滚动框）走 BindScroll。
function Widget:BindScroll(holder, scroll, content, thumb)
	if thumb then thumb:Hide() end

	local function UpdateThumb()
		local range = scroll:GetVerticalScrollRange()
		local viewH = scroll:GetHeight()
		if not thumb then return end
		if not range or range <= 0 or not viewH or viewH <= 0 then
			thumb:Hide()
			return
		end
		thumb:Show()
		local h = math.max(24, viewH * (viewH / (viewH + range)))
		thumb:SetHeight(h)
		local p = scroll:GetVerticalScroll() / range
		thumb:ClearAllPoints()
		thumb:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -3, -(viewH - h) * p)
	end

	local function ApplyWidth(w)
		w = w or scroll:GetWidth()
		if w and w > 1 then
			content:SetWidth(w)
		end
	end

	App.Hook:Bind(scroll, "OnVerticalScroll", UpdateThumb)
	App.Hook:Bind(scroll, "OnSizeChanged", function(_, w)
		ApplyWidth(w)
		UpdateThumb()
	end)

	holder:EnableMouseWheel(true)
	App.Hook:Bind(holder, "OnMouseWheel", function(_, delta)
		local range = scroll:GetVerticalScrollRange() or 0
		local v = scroll:GetVerticalScroll() - delta * 30
		if v < 0 then v = 0 end
		if v > range then v = range end
		scroll:SetVerticalScroll(v)
		UpdateThumb()
	end)

	ApplyWidth()
	App.Hook:Attach(holder, "OnShow", function()
		ApplyWidth()
		UpdateThumb()
	end)

	return {
		holder  = holder,
		scroll  = scroll,
		content = content,
		Update  = UpdateThumb,
	}
end

function Widget:ScrollArea(parent)
	local holder = CreateFrame("Frame", nil, parent)

	local sf = CreateFrame("ScrollFrame", nil, holder)
	sf:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
	sf:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -10, 0)

	local content = CreateFrame("Frame", nil, sf)
	content:SetSize(1, 1)
	sf:SetScrollChild(content)

	local track = self:VLine(holder, "line", 0.18)
	track:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -3, 0)
	track:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -3, 0)

	local thumb = holder:CreateTexture(nil, "OVERLAY")
	thumb:SetWidth(3)
	self:Solid(thumb, C.cinnabar, 0.75)
	thumb:Hide()

	return self:BindScroll(holder, sf, content, thumb)
end
