-- ============================================================
-- Skin · 基础绘制
-- ============================================================
local ADDON_NAME, MZ = ...
local S = MZ.Skin
local C = MZ.C

function S:Solid(tex, color, alpha)
	local a = alpha or color[4] or 1
	if tex.SetColorTexture then
		tex:SetColorTexture(color[1], color[2], color[3], a)
	else
		tex:SetTexture(1, 1, 1, a)
		tex:SetVertexColor(color[1], color[2], color[3])
	end
end

function S:Paint(frame, tone, alpha)
	local t = frame:CreateTexture(nil, "BACKGROUND")
	t:SetAllPoints(frame)
	S:Solid(t, C[tone or "paper"], alpha)
	frame.paper = t
	return t
end

-- 一圈 1px 墨线。inset 不同则各自独立，可叠多层。
function S:Stroke(frame, tone, inset, alpha)
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

	for i = 1, 4 do S:Solid(s[i], color, alpha) end
	return frame
end

function S:HLine(parent, tone, alpha)
	local t = parent:CreateTexture(nil, "ARTWORK")
	t:SetHeight(1)
	S:Solid(t, C[tone or "line"], alpha)
	return t
end

function S:VLine(parent, tone, alpha)
	local t = parent:CreateTexture(nil, "ARTWORK")
	t:SetWidth(1)
	S:Solid(t, C[tone or "line"], alpha)
	return t
end

function S:Text(parent, size, tone, text, flags)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	MZ:SetFont(fs, size or 13, flags)
	local color = C[tone or "ink"]
	fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
	if text then fs:SetText(text) end
	return fs
end
