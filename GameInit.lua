-- ============================================================
-- 墨战年华 · GameInit（组合根）
-- 门面组装：App ← Core + Skin + MainUI（根目录仅本文件 + toc）
-- 时机：本插件 ADDON_LOADED 后 Init → Ready
-- ============================================================
local ADDON_NAME, MZ = ...

local App = MZ.App
local started = false

local function Compose()
	App:Compose{
		Skin = MZ.Skin,
		UI   = MZ.UI,
	}
end

local function Start()
	if started then return end
	started = true

	Compose()
	App:Init()
	App:Ready()

	if App.Core and App.Core.Log then
		App.Core.Log:Debug("GameInit 完成 · 页面由 Views 已注册")
	end
end

local function OnAddonLoaded(_, name)
	if name ~= ADDON_NAME then return end
	MZ.Event:Off("ADDON_LOADED", OnAddonLoaded)
	Start()
end

-- Event 已由 App 门面挂到 MZ.Event
MZ.Event:On("ADDON_LOADED", OnAddonLoaded)

-- 导出，便于调试手动触发
MZ.GameInit = {
	Compose = Compose,
	Start   = Start,
}
