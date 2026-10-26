-- ============================================================
-- Core · 内核声明
-- 在 MZ.App 上挂载元信息 / 主题 / 字体 / _modules 暂存
-- 对外最终只保留 MZ.App（由 App\App 组装 Core）
-- ============================================================
local ADDON_NAME, MZ = ...

local App = {}
MZ.App = App

App.ADDON   = ADDON_NAME
App.VERSION = "0.4.2"

-- 各 Core\*.lua 注册到此；App\App 组装为 App.Core 后可作内部暂存
App._modules = {}

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
