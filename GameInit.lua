-- ============================================================
-- GameInit · 组合根
-- ADDON_LOADED 走系统事件。startApp → Ready。每帧更新在 Hook 的驱动帧上。
-- ============================================================
local ADDON_NAME, MZ = ...

local App = MZ.App
local started = false

local function Compose()
	App:Compose({
		UI = App.UI,
	})
end

local function Start()
	if started then return end
	started = true

	Compose()
	App:startApp()
	App:Ready()
	App.logManager:Debug("GameInit 完成 · 子窗口由 View 注册")
end

local function OnAddonLoaded(_, name)
	if name ~= ADDON_NAME then return end
	App.system:Off(App.NetEvents.ADDON_LOADED, OnAddonLoaded)
	Start()
end

App.system:On(App.NetEvents.ADDON_LOADED, OnAddonLoaded)

App.GameInit = {
	Compose = Compose,
	Start   = Start,
}
