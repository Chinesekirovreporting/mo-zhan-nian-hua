-- ============================================================
-- MainUI · 逻辑壳（私有模块）
-- 页面注册 / 切换 / 缩放 / 命令；绘制全部委托 Skin
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App
local S = App.Skin
local L = S.Layout
local Core = App.Core

local UI = {}
App.UI = UI

local frame
local pages = {}

function UI:AddPage(def)
	if type(def) ~= "table" or not def.id then return end
	for _, p in ipairs(pages) do
		if p.id == def.id then return end
	end
	table.insert(pages, def)
	if frame then
		self:BuildTabs()
		self:UpdateTabs()
	end
end

function UI:GetPage(id)
	for _, p in ipairs(pages) do
		if p.id == id then return p end
	end
end

function UI:GetSortedPages()
	local list = {}
	for _, p in ipairs(pages) do table.insert(list, p) end
	table.sort(list, function(a, b)
		return (a.order or 99) < (b.order or 99)
	end)
	return list
end

function UI:PageCount()
	return #pages
end

local function BuildPage(def)
	if def.frame then return def.frame end

	local page, body = S:BuildPageShell(frame.content, def)
	def.frame = page
	def.body = body

	if def.build then
		local ok, err = pcall(def.build, page, body, App)
		if not ok then
			Core.Log:Error("页面 " .. tostring(def.id) .. " 构建失败：" .. tostring(err))
		end
	end
	return page
end

function UI:BuildTabs()
	if not frame then return end

	if frame.tabPool then
		for _, t in ipairs(frame.tabPool) do t:Hide() end
	end
	frame.tabPool = frame.tabPool or {}
	frame.tabs = {}

	local list = self:GetSortedPages()
	local y = 0
	local index = 0

	for _, def in ipairs(list) do
		index = index + 1
		local tab = frame.tabPool[index]
		if not tab then
			tab = S:CreateSideTab(frame.tabArea, L.TAB_H)

			tab:SetScript("OnEnter", function(self)
				S:SetSideTabHover(self, true, UI.activePage == self.pageId)
			end)
			tab:SetScript("OnLeave", function(self)
				S:SetSideTabHover(self, false, UI.activePage == self.pageId)
			end)
			tab:SetScript("OnClick", function(self)
				if self.pageId then UI:ShowPage(self.pageId) end
			end)

			frame.tabPool[index] = tab
		end

		tab = frame.tabPool[index]
		tab.pageId = def.id
		tab.label:SetText(def.title or def.id)
		tab:ClearAllPoints()
		tab:SetPoint("TOPLEFT", frame.tabArea, "TOPLEFT", 0, -y)
		tab:SetPoint("TOPRIGHT", frame.tabArea, "TOPRIGHT", 0, -y)
		tab:Show()

		table.insert(frame.tabs, tab)
		y = y + L.TAB_H + L.TAB_GAP
	end
end

function UI:UpdateTabs()
	if not frame or not frame.tabs then return end
	for _, tab in ipairs(frame.tabs) do
		S:SetSideTabActive(tab, tab.pageId == self.activePage)
	end
end

function UI:ShowPage(id)
	if not frame then return end

	local def = self:GetPage(id)
	if not def then
		def = self:GetSortedPages()[1]
	end
	if not def then return end

	for _, p in ipairs(pages) do
		if p.frame and p ~= def then p.frame:Hide() end
	end

	BuildPage(def)
	def.frame:Show()

	self.activePage = def.id
	Core.Store:Set("lastPage", def.id)
	self:UpdateTabs()
	Core.Event:Send("MZ_PAGE_CHANGED", def.id)
end

function UI:SetScale(value)
	value = math.max(0.75, math.min(1.30, value))
	Core.Store:Set("scale", value)
	if frame then frame:SetScale(value) end
	return value
end

function UI:ResetPosition()
	Core.Store:Update({ point = nil, scale = 1.0 })
	if frame then
		frame:ClearAllPoints()
		frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
		frame:SetScale(1.0)
	end
end

function UI:Build()
	if frame then return frame end

	local db = Core.Store:Get()
	frame = S:BuildMainWindow{
		name   = "MoZhanNianHuaFrame",
		point  = db.point,
		scale  = db.scale or 1.0,
		onDragStop = function(point, relPoint, x, y)
			Core.Store:Set("point", { point = point, relPoint = relPoint, x = x, y = y })
		end,
	}

	table.insert(UISpecialFrames, "MoZhanNianHuaFrame")

	self.frame = frame
	self:BuildTabs()
	return frame
end

function UI:Toggle()
	if not self.frame then self:Build() end
	if frame:IsShown() then
		frame:Hide()
	else
		frame:Show()
		self:ShowPage(Core.Store:GetKey("lastPage", "activity"))
	end
end

function UI:Slash(msg)
	msg = string.lower(strtrim(msg or ""))
	if msg == "reset" then
		self:ResetPosition()
		Core.Log:Info("位置与缩放已重置。")
	elseif msg == "test" then
		Core.Log:Info("版本 " .. App.VERSION .. "，已注册页面 " .. self:PageCount() .. " 个。")
	else
		self:Toggle()
	end
end

SLASH_MOZHANNIANHUA1 = "/mz"
SLASH_MOZHANNIANHUA2 = "/mznh"
SLASH_MOZHANNIANHUA3 = "/mozhan"
SLASH_MOZHANNIANHUA4 = "/墨战"
SlashCmdList["MOZHANNIANHUA"] = function(msg) UI:Slash(msg) end
