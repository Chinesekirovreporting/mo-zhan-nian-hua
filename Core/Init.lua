-- ============================================================
-- Core · 内核声明
-- 主题 / 字体 / 模块登记表，以及每帧 updateTick。
-- dt 是秒（暴雪 OnUpdate），不是参考工程里的毫秒。
-- ============================================================
local ADDON_NAME, MZ = ...

local App = {}
MZ.App = App

App.ADDON   = ADDON_NAME
App.VERSION = "0.5.1"

-- 各模块加载时把自己的单例放进来，App.lua 再挂到门面上
App._modules = {}
App._tickers = {}

function App:addManager(manager)
	if not manager then return end
	local list = self._tickers
	for i = 1, #list do
		if list[i] == manager then return end
	end
	list[#list + 1] = manager
end

function App:removeManager(manager)
	local list = self._tickers
	for i = #list, 1, -1 do
		if list[i] == manager then
			table.remove(list, i)
		end
	end
end

function App:updateTick(dt)
	local list = self._tickers
	for i = 1, #list do
		local manager = list[i]
		if manager.update then
			manager:update(dt)
		end
	end
end

-- 与 game/skin/MainUI.xml 的窗口尺寸保持一致
App.Layout = {
	WIDTH   = 660,
	HEIGHT  = 470,
	TITLE_H = 44,
	SIDE_W  = 156,
	TAB_H   = 34,
	TAB_GAP = 6,
}

-- 水墨配色：宣纸底 + 墨线 + 朱砂点缀
App.C = {
	paper      = { 0.902, 0.871, 0.792 },
	paperLight = { 0.949, 0.925, 0.867 },
	paperDark  = { 0.831, 0.796, 0.706 },
	paperDeep  = { 0.749, 0.714, 0.624 },
	ink        = { 0.106, 0.098, 0.086 },
	inkSoft    = { 0.278, 0.259, 0.227 },
	inkFaint   = { 0.435, 0.408, 0.361 },
	cinnabar   = { 0.702, 0.196, 0.157 },
	cinnabarHi = { 0.839, 0.325, 0.243 },
	line       = { 0.106, 0.098, 0.086, 0.55 },
}

local fontPath

function App:GetFontPath()
	if fontPath then return fontPath end
	local ok, path = pcall(function() return GameFontNormal:GetFont() end)
	fontPath = (ok and path) or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
	return fontPath
end

function App:SetFont(fontString, size, flags)
	local path = self:GetFontPath()
	fontString:SetFont(path, size, flags or "")
	if not fontString:GetFont() then
		fontString:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, flags or "")
	end
	return fontString
end

-- 每帧驱动在 core/Hook.lua：那是自己的框体，走 Never 层的 Bind。
