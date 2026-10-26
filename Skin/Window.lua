-- ============================================================
-- Skin · 主窗口外壳绘制
-- 标题栏 / 侧栏 / 内容区；业务回调由 opts 传入
-- ============================================================
local ADDON_NAME, MZ = ...
local S = MZ.Skin
local C = MZ.C
local L = S.Layout

--- opts = {
---   name, point, scale,
---   onDragStop = function(point, relPoint, x, y),
---   onClose = function(frame),
--- }
function S:BuildMainWindow(opts)
	opts = opts or {}

	local frame = CreateFrame("Frame", opts.name or "MoZhanNianHuaFrame", UIParent)
	frame:SetSize(L.WIDTH, L.HEIGHT)
	frame:SetFrameStrata("DIALOG")
	frame:SetToplevel(true)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)

	local point = opts.point
	if point and point.point then
		frame:SetPoint(point.point, UIParent, point.relPoint or point.point,
			point.x or 0, point.y or 0)
	else
		frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	end
	frame:SetScale(opts.scale or 1.0)

	S:Paint(frame, "paper", 1)
	S:Stroke(frame, "ink", 0)
	S:Stroke(frame, "line", 4, 0.35)

	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		if opts.onDragStop then
			local p, _, rel, x, y = self:GetPoint(1)
			opts.onDragStop(p, rel, x, y)
		end
	end)

	-- 标题栏
	local title = CreateFrame("Frame", nil, frame)
	title:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
	title:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
	title:SetHeight(L.TITLE_H)
	frame.titleBar = title

	local bottom = S:HLine(title, "line", 0.85)
	bottom:SetPoint("BOTTOMLEFT", title, "BOTTOMLEFT", 0, 0)
	bottom:SetPoint("BOTTOMRIGHT", title, "BOTTOMRIGHT", 0, 0)

	local seal = title:CreateTexture(nil, "ARTWORK")
	seal:SetSize(22, 22)
	seal:SetPoint("LEFT", title, "LEFT", 16, 0)
	S:Solid(seal, C.cinnabar)

	local sealText = S:Text(title, 14, "paperLight", "墨")
	sealText:SetPoint("CENTER", seal, "CENTER", 0, 0)

	local heading = S:Text(title, 18, "ink", "墨战年华")
	heading:SetPoint("LEFT", seal, "RIGHT", 12, 0)

	local caption = S:Text(title, 11, "inkFaint", "公会活动面板")
	caption:SetPoint("LEFT", heading, "RIGHT", 12, -1)

	local close = CreateFrame("Button", nil, title)
	close:SetSize(28, 28)
	close:SetPoint("RIGHT", title, "RIGHT", -10, 0)

	local closeBg = close:CreateTexture(nil, "BACKGROUND")
	closeBg:SetAllPoints(close)
	S:Solid(closeBg, C.cinnabar, 0)

	local closeMark = S:Text(close, 20, "inkSoft", "×")
	closeMark:SetPoint("CENTER", close, "CENTER", 0, 1)

	close:SetScript("OnEnter", function()
		S:Solid(closeBg, C.cinnabar, 0.85)
		closeMark:SetTextColor(C.paperLight[1], C.paperLight[2], C.paperLight[3], 1)
	end)
	close:SetScript("OnLeave", function()
		S:Solid(closeBg, C.cinnabar, 0)
		closeMark:SetTextColor(C.inkSoft[1], C.inkSoft[2], C.inkSoft[3], 1)
	end)
	close:SetScript("OnClick", function()
		if opts.onClose then
			opts.onClose(frame)
		else
			frame:Hide()
		end
	end)
	frame.closeBtn = close

	-- 侧栏
	local side = CreateFrame("Frame", nil, frame)
	side:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -(L.TITLE_H + 1))
	side:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, 1)
	side:SetWidth(L.SIDE_W)
	frame.side = side

	local sideBg = side:CreateTexture(nil, "BACKGROUND")
	sideBg:SetAllPoints(side)
	S:Solid(sideBg, C.paperDeep, 0.35)

	local sideLine = S:VLine(side, "line", 0.55)
	sideLine:SetPoint("TOPRIGHT", side, "TOPRIGHT", 0, 0)
	sideLine:SetPoint("BOTTOMRIGHT", side, "BOTTOMRIGHT", 0, 0)

	local tabArea = CreateFrame("Frame", nil, side)
	tabArea:SetPoint("TOPLEFT", side, "TOPLEFT", 10, -16)
	tabArea:SetPoint("TOPRIGHT", side, "TOPRIGHT", -10, -16)
	tabArea:SetHeight(1)
	frame.tabArea = tabArea

	-- 内容区
	local content = CreateFrame("Frame", nil, frame)
	content:SetPoint("TOPLEFT", side, "TOPRIGHT", 1, 0)
	content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
	frame.content = content

	return frame
end
