-- ============================================================
-- Skin · 入口
-- 绘制 API 由同目录模块挂到 App.Skin
-- ============================================================
local ADDON_NAME, MZ = ...

local S = {}
MZ.App.Skin = S

S.Layout = {
	WIDTH   = 660,
	HEIGHT  = 470,
	TITLE_H = 44,
	SIDE_W  = 156,
	TAB_H   = 34,
	TAB_GAP = 6,
}
