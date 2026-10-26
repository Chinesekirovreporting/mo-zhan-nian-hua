-- ============================================================
-- GameInit · 组合根（根目录仅本文件 + toc）
-- MZ.App ← Core + Skin + MainUI；ADDON_LOADED 后 Init → Ready
-- ============================================================
local ADDON_NAME, MZ = ...

local App = MZ.App
local started = false

local function Compose()
	App:Compose{
		Skin = App.Skin,
		UI   = App.UI,
	}
end

local function Start()
	if started then return end
	started = true

	Compose()
	App:Init()
	App:Ready()
	App.Core.Log:Debug("GameInit 完成 · 页面由 Views 已注册")
end

local function OnAddonLoaded(_, name)
	if name ~= ADDON_NAME then return end
	App.Core.Event:Off("ADDON_LOADED", OnAddonLoaded)
	Start()
end

App.Core.Event:On("ADDON_LOADED", OnAddonLoaded)

App.GameInit = {
	Compose = Compose,
	Start   = Start,
}
