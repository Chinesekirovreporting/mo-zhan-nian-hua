-- ============================================================
-- Skin · 滚动区（滚轮 + 右侧细墨条，不用暴雪原始滚动条）
-- ============================================================
local ADDON_NAME, MZ = ...
local S = MZ.Skin
local C = MZ.C

function S:ScrollArea(parent)
	local holder = CreateFrame("Frame", nil, parent)

	local sf = CreateFrame("ScrollFrame", nil, holder)
	sf:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
	sf:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -10, 0)

	local content = CreateFrame("Frame", nil, sf)
	content:SetSize(1, 1)
	sf:SetScrollChild(content)

	local track = S:VLine(holder, "line", 0.18)
	track:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -3, 0)
	track:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -3, 0)

	local thumb = holder:CreateTexture(nil, "OVERLAY")
	thumb:SetWidth(3)
	S:Solid(thumb, C.cinnabar, 0.75)
	thumb:Hide()

	local function UpdateThumb()
		local range = sf:GetVerticalScrollRange()
		local viewH = sf:GetHeight()
		if not range or range <= 0 or not viewH or viewH <= 0 then
			thumb:Hide()
			return
		end
		thumb:Show()
		local h = math.max(24, viewH * (viewH / (viewH + range)))
		thumb:SetHeight(h)
		local p = sf:GetVerticalScroll() / range
		thumb:ClearAllPoints()
		thumb:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -3, -(viewH - h) * p)
	end

	sf:SetScript("OnVerticalScroll", UpdateThumb)
	sf:SetScript("OnSizeChanged", function(self, w)
		content:SetWidth(w)
	end)

	holder:EnableMouseWheel(true)
	holder:SetScript("OnMouseWheel", function(_, delta)
		local range = sf:GetVerticalScrollRange() or 0
		local v = sf:GetVerticalScroll() - delta * 30
		if v < 0 then v = 0 end
		if v > range then v = range end
		sf:SetVerticalScroll(v)
		UpdateThumb()
	end)

	return {
		holder  = holder,
		scroll  = sf,
		content = content,
		Update  = UpdateThumb,
	}
end
