-- ============================================================
-- MainUI · 逻辑壳（私有模块）
-- 页面注册 / 切换 / 缩放 / 命令；绘制全部委托 Skin
-- ============================================================
local ADDON_NAME, MZ = ...
local S = MZ.Skin
local L = S.Layout

local UI = {}
MZ.UI = UI

local frame
local pages = {}

-- ------------------------------------------------------------
-- 页面注册
-- ------------------------------------------------------------
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

function MZ:AddPage(def) return UI:AddPage(def) end
function MZ:GetPage(id) return UI:GetPage(id) end
function MZ:GetSortedPages() return UI:GetSortedPages() end

-- ------------------------------------------------------------
-- 页面骨架（绘制在 Skin.Page）
-- ------------------------------------------------------------
local function BuildPage(def)
	if def.frame then return def.frame end

	local page, body = S:BuildPageShell(frame.content, def)
	def.frame = page
	def.body = body

	if def.build then
		local ok, err = pcall(def.build, page, body, MZ)
		if not ok then
			MZ.Log:Error("页面 " .. tostring(def.id) .. " 构建失败：" .. tostring(err))
		end
	end
	return page
end

-- ------------------------------------------------------------
-- 侧栏页签
-- ------------------------------------------------------------
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

-- ------------------------------------------------------------
-- 页面切换
-- ------------------------------------------------------------
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
	MZ.activePage = def.id
	MZ.Store:Set("lastPage", def.id)
	self:UpdateTabs()
	MZ.Event:Send("MZ_PAGE_CHANGED", def.id)
end

-- ------------------------------------------------------------
-- 缩放 / 位置
-- ------------------------------------------------------------
function UI:SetScale(value)
	value = math.max(0.75, math.min(1.30, value))
	MZ.Store:Set("scale", value)
	if frame then frame:SetScale(value) end
	return value
end

function UI:ResetPosition()
	MZ.Store:Update({ point = nil, scale = 1.0 })
	if frame then
		frame:ClearAllPoints()
		frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
		frame:SetScale(1.0)
	end
end

function MZ:SetScale(value) return UI:SetScale(value) end
function MZ:ResetPosition() return UI:ResetPosition() end
function MZ:ShowPage(id) return UI:ShowPage(id) end

-- ------------------------------------------------------------
-- 主窗口（绘制在 Skin.Window）
-- ------------------------------------------------------------
function UI:Build()
	if frame then return frame end

	local db = MZ.Store:Get()
	frame = S:BuildMainWindow{
		name   = "MoZhanNianHuaFrame",
		point  = db.point,
		scale  = db.scale or 1.0,
		onDragStop = function(point, relPoint, x, y)
			MZ.Store:Set("point", { point = point, relPoint = relPoint, x = x, y = y })
		end,
	}

	table.insert(UISpecialFrames, "MoZhanNianHuaFrame")

	self.frame = frame
	MZ.frame = frame
	self:BuildTabs()
	return frame
end

function MZ:Build() return UI:Build() end

-- ------------------------------------------------------------
-- 开关 / 斜杠命令
-- ------------------------------------------------------------
function UI:Toggle()
	if not self.frame then self:Build() end
	if frame:IsShown() then
		frame:Hide()
	else
		frame:Show()
		self:ShowPage(MZ.Store:GetKey("lastPage", "activity"))
	end
end

function UI:Slash(msg)
	msg = string.lower(strtrim(msg or ""))
	if msg == "reset" then
		self:ResetPosition()
		MZ.Log:Info("位置与缩放已重置。")
	elseif msg == "test" then
		MZ.Log:Info("版本 " .. MZ.VERSION .. "，已注册页面 " .. self:PageCount() .. " 个。")
	else
		self:Toggle()
	end
end

function MZ:Toggle() return UI:Toggle() end
function MZ:Slash(msg) return UI:Slash(msg) end

SLASH_MOZHANNIANHUA1 = "/mz"
SLASH_MOZHANNIANHUA2 = "/mznh"
SLASH_MOZHANNIANHUA3 = "/mozhan"
SLASH_MOZHANNIANHUA4 = "/墨战"
SlashCmdList["MOZHANNIANHUA"] = function(msg) UI:Slash(msg) end
