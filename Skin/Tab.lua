-- ============================================================
-- Skin · 侧栏页签
-- ============================================================
local ADDON_NAME, MZ = ...
local S = MZ.Skin
local C = MZ.C

function S:CreateSideTab(parent, height)
	local tab = CreateFrame("Button", nil, parent)
	tab:SetHeight(height or S.Layout.TAB_H)

	tab.bg = tab:CreateTexture(nil, "BACKGROUND")
	tab.bg:SetAllPoints(tab)
	S:Solid(tab.bg, C.paper, 0)

	tab.bar = tab:CreateTexture(nil, "ARTWORK")
	tab.bar:SetWidth(3)
	tab.bar:SetPoint("TOPLEFT", tab, "TOPLEFT", 0, 0)
	tab.bar:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 0, 0)
	S:Solid(tab.bar, C.cinnabar)

	tab.label = S:Text(tab, 13, "inkSoft")
	tab.label:SetPoint("LEFT", 14, 0)

	return tab
end

function S:SetSideTabActive(tab, active)
	if active then
		S:Solid(tab.bg, C.paperLight, 1)
		tab.bar:Show()
		tab.label:SetTextColor(C.ink[1], C.ink[2], C.ink[3], 1)
	else
		S:Solid(tab.bg, C.paper, 0)
		tab.bar:Hide()
		tab.label:SetTextColor(C.inkSoft[1], C.inkSoft[2], C.inkSoft[3], 1)
	end
end

function S:SetSideTabHover(tab, hovering, isActive)
	if isActive then return end
	if hovering then
		S:Solid(tab.bg, C.paper, 0.45)
	else
		S:Solid(tab.bg, C.paper, 0)
	end
end
