-- ============================================================
-- Skin · 按钮
-- primary = true 时为朱砂实心
-- ============================================================
local ADDON_NAME, MZ = ...
local S = MZ.Skin
local C = MZ.C

function S:Button(parent, text, width, height, primary)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(width or 96, height or 26)

	local base = primary and "cinnabar" or "paperLight"
	local hover = primary and "cinnabarHi" or "paperDark"
	local tone = primary and "paperLight" or "ink"

	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(b)
	S:Solid(bg, C[base])

	S:Stroke(b, "line", 0)

	local fs = S:Text(b, 13, tone, text)

	local function PlaceLabel(dy)
		fs:ClearAllPoints()
		fs:SetPoint("CENTER", b, "CENTER", 0, dy or 0)
	end
	PlaceLabel(0)

	b.label = fs
	b.bg = bg

	function b:SetLabel(str) fs:SetText(str) end

	b:SetScript("OnEnter", function() S:Solid(bg, C[hover]) end)
	b:SetScript("OnLeave", function()
		S:Solid(bg, C[base])
		PlaceLabel(0)
	end)
	b:SetScript("OnMouseDown", function() PlaceLabel(-1) end)
	b:SetScript("OnMouseUp", function() PlaceLabel(0) end)
	b:RegisterForClicks("AnyUp")
	return b
end
