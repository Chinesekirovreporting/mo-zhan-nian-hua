-- ============================================================
-- 墨战年华 · Core 内核声明
-- 只提供命名空间、主题、字体；管理器由 Modules 注册，App 组装
-- ============================================================
local ADDON_NAME, MZ = ...

MZ.ADDON   = ADDON_NAME
MZ.VERSION = "0.4.2"

-- 模块挂载点（各 Core\*.lua 往这里注册，App\App 再门面组装）
MZ.Modules = MZ.Modules or {}

-- 水墨配色：宣纸底 + 墨线 + 朱砂点缀
MZ.C = {
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

-- ------------------------------------------------------------
-- 字体：沿用客户端当前语言字体，保证中文不出方框
-- ------------------------------------------------------------
local fontPath

function MZ:GetFontPath()
	if fontPath then return fontPath end
	local ok, path = pcall(function() return GameFontNormal:GetFont() end)
	fontPath = (ok and path) or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
	return fontPath
end

function MZ:SetFont(fontString, size, flags)
	local path = self:GetFontPath()
	fontString:SetFont(path, size, flags or "")
	if not fontString:GetFont() then
		fontString:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, flags or "")
	end
	return fontString
end
