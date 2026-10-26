-- ============================================================
-- Skin · 卡片（纸面 + 墨线 + 标题 / 说明）
-- ============================================================
local ADDON_NAME, MZ = ...
local S = MZ.Skin

function S:Card(parent, height)
	local card = CreateFrame("Frame", nil, parent)
	card:SetHeight(height or 76)
	S:Paint(card, "paperLight")
	S:Stroke(card, "line", 0)

	card.title = S:Text(card, 14, "ink")
	card.title:SetPoint("TOPLEFT", 14, -12)

	card.desc = S:Text(card, 11, "inkFaint")
	card.desc:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -6)

	return card
end
