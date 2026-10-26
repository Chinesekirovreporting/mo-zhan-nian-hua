-- ============================================================
-- Skin · 输入框
-- ============================================================
local ADDON_NAME, MZ = ...
local S = MZ.App.Skin
local C = MZ.App.C

function S:EditBox(parent, width, height)
	local e = CreateFrame("EditBox", nil, parent)
	e:SetSize(width or 80, height or 26)
	e:SetAutoFocus(false)
	e:SetMaxLetters(12)

	local bg = e:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(e)
	S:Solid(bg, C.paperLight)

	S:Stroke(e, "line", 0)
	MZ.App:SetFont(e, 13)
	e:SetTextColor(C.ink[1], C.ink[2], C.ink[3])
	e:SetTextInsets(8, 8, 0, 0)
	e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	return e
end
