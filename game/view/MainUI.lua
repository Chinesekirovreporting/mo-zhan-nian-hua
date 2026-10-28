-- ============================================================
-- MainUI · 主窗口
-- 骨架在 game/skin/MainUI.xml。这里只绑拖拽、页签和缩放。
-- 子窗口是 View 里的各个页面，XML 页框已经挂在内容区里。
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App
local Core = App.Core
local W = App.Widget
local C = App.C

local TABS = {
	{ name = "MZTabActivity", id = "activity" },
	{ name = "MZTabCheckers", id = "checkers" },
	{ name = "MZTabDkp",      id = "dkp" },
	{ name = "MZTabTimer",    id = "timer" },
	{ name = "MZTabRoster",   id = "roster" },
	{ name = "MZTabSettings", id = "settings" },
}

local MainUI = App.newclz("MainUI")

function MainUI:ctor()
	self._pages = {}
	self._tabById = {}
	self.frame = _G["MoZhanNianHuaFrame"]
	self.activePage = nil
	self._ready = false
	if not self.frame then
		error("MainUI: 缺少 XML 主窗口 MoZhanNianHuaFrame")
	end
	self.frame.titleBar = _G["MZMainTitle"]
	self.frame.side = _G["MZMainSide"]
	self.frame.tabArea = _G["MZMainTabArea"]
	self.frame.content = _G["MZMainContent"]
	self.frame.closeBtn = _G["MZMainClose"]
end

function MainUI:AddPage(def)
	if type(def) ~= "table" or not def.id then return end
	for _, p in ipairs(self._pages) do
		if p.id == def.id then return end
	end
	self._pages[#self._pages + 1] = def
	local tab = self._tabById[def.id]
	if tab and def.title then tab:SetText(def.title) end
end

function MainUI:GetPage(id)
	for _, p in ipairs(self._pages) do
		if p.id == id then return p end
	end
end

function MainUI:GetSortedPages()
	local list = {}
	for _, p in ipairs(self._pages) do list[#list + 1] = p end
	table.sort(list, function(a, b)
		return (a.order or 99) < (b.order or 99)
	end)
	return list
end

function MainUI:PageCount()
	return #self._pages
end

function MainUI:_setTab(tab, active)
	if active then
		W:Solid(tab.bg, C.paperLight, 1)
		tab.bar:Show()
		local fs = tab:GetFontString()
		if fs then fs:SetTextColor(C.ink[1], C.ink[2], C.ink[3], 1) end
	else
		W:Solid(tab.bg, C.paper, 0)
		tab.bar:Hide()
		local fs = tab:GetFontString()
		if fs then fs:SetTextColor(C.inkSoft[1], C.inkSoft[2], C.inkSoft[3], 1) end
	end
end

function MainUI:UpdateTabs()
	for _, tab in pairs(self._tabById) do
		self:_setTab(tab, tab.pageId == self.activePage)
	end
end

function MainUI:_bindTabs()
	local window = self
	for _, info in ipairs(TABS) do
		local tab = _G[info.name]
		if tab then
			tab.pageId = info.id
			tab.bg = _G[info.name .. "Bg"]
			tab.bar = _G[info.name .. "Bar"]
			self._tabById[info.id] = tab
			local fs = tab:GetFontString()
			if fs then App:SetFont(fs, 13) end
			App.Hook:Bind(tab, "OnEnter", function(self)
				if window.activePage == self.pageId then return end
				W:Solid(self.bg, C.paper, 0.45)
			end)
			App.Hook:Bind(tab, "OnLeave", function(self)
				window:_setTab(self, window.activePage == self.pageId)
			end)
			App.Hook:Bind(tab, "OnClick", function(self)
				if self.pageId then window:ShowPage(self.pageId) end
			end)
		end
	end
	self:UpdateTabs()
end

function MainUI:_paintChrome()
	W:PaintText(_G["MZMainSealText"], 14, "paperLight", "墨")
	W:PaintText(_G["MZMainHeading"], 18, "ink", "墨战年华")
	W:PaintText(_G["MZMainCaption"], 11, "inkFaint", "公会活动面板")
	W:PaintText(_G["MZMainCloseMark"], 20, "inkSoft", "×")
end

function MainUI:ShowPage(id)
	if not self._ready then self:Build() end
	if not self.frame then return end

	local def = self:GetPage(id)
	if not def then
		def = self:GetSortedPages()[1]
	end
	if not def then return end

	for _, p in ipairs(self._pages) do
		if p.frame and p ~= def then p.frame:Hide() end
	end

	if not def._built and def.build then
		local ok, err = pcall(def.build)
		if ok then
			def._built = true
		else
			Core.Log:Error("页面 " .. tostring(def.id) .. " 构建失败：" .. tostring(err))
		end
	end

	if def.frame then def.frame:Show() end
	self.activePage = def.id
	Core.Store:Set("lastPage", def.id)
	self:UpdateTabs()
	App.eventManager:emit(App.GlobalEvents.PAGE_CHANGED, def.id)
end

function MainUI:SetScale(value)
	value = math.max(0.75, math.min(1.30, value))
	Core.Store:Set("scale", value)
	if self.frame then self.frame:SetScale(value) end
	return value
end

function MainUI:ResetPosition()
	Core.Store:Update({ point = nil, scale = 1.0 })
	if self.frame then
		self.frame:ClearAllPoints()
		self.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
		self.frame:SetScale(1.0)
	end
end

function MainUI:Build()
	if self._ready then return self.frame end
	local frame = self.frame
	local db = Core.Store:Get()
	local point = db.point
	if point and point.point then
		frame:ClearAllPoints()
		frame:SetPoint(point.point, UIParent, point.relPoint or point.point, point.x or 0, point.y or 0)
	end
	frame:SetScale(db.scale or 1)

	frame:RegisterForDrag("LeftButton")
	App.Hook:Bind(frame, "OnDragStart", function(self) self:StartMoving() end)
	App.Hook:Bind(frame, "OnDragStop", function(self)
		self:StopMovingOrSizing()
		local p, _, rel, x, y = self:GetPoint(1)
		Core.Store:Set("point", { point = p, relPoint = rel, x = x, y = y })
	end)
	App.Hook:Bind(frame.closeBtn, "OnClick", function() frame:Hide() end)

	self:_paintChrome()
	self:_bindTabs()

	local listed = false
	for _, n in ipairs(UISpecialFrames) do
		if n == "MoZhanNianHuaFrame" then listed = true break end
	end
	if not listed then
		table.insert(UISpecialFrames, "MoZhanNianHuaFrame")
	end

	self._ready = true
	return frame
end

function MainUI:Toggle()
	if not self._ready then self:Build() end
	if self.frame:IsShown() then
		self.frame:Hide()
	else
		self.frame:Show()
		self:ShowPage(Core.Store:GetKey("lastPage", "activity"))
	end
end

function MainUI:Slash(msg)
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

local UI = MainUI:new()
App.UI = UI
