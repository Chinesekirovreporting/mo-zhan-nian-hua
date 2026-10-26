-- ============================================================
-- Skin · 内容页骨架（标题 / 副标题 / 分隔线 / body）
-- ============================================================
local ADDON_NAME, MZ = ...
local S = MZ.App.Skin

function S:BuildPageShell(parent, def)
	local page = CreateFrame("Frame", nil, parent)
	page:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, -18)
	page:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -20, 18)
	page:Hide()

	local title = S:Text(page, 15, "ink", def.title or def.id)
	title:SetPoint("TOPLEFT", 0, 0)

	local subtitle = S:Text(page, 11, "inkFaint", def.subtitle or "")
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)

	local rule = S:HLine(page, "line", 0.35)
	rule:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -48)
	rule:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -48)

	local body = CreateFrame("Frame", nil, page)
	body:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -62)
	body:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)

	page.titleFS = title
	page.subtitleFS = subtitle
	page.body = body
	return page, body
end
