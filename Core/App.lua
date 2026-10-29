-- ============================================================
-- App · 门面
-- 单例在各文件加载时创建。这里挂到门面上，startApp 再初始化存档。
--   App.eventManager   代码内全局事件（on·emit）
--   App.GlobalEvents   模块事件名字符串集
--   App.system         暴雪事件（On·Once·Off）
--   App.NetEvents      收集到的暴雪事件字符串集
--   App.Core           日志、存档、计时、网络、事件
--   App.GameModules    跳棋、智慧树、DKP、倒计时、名单、考核
-- ============================================================
local ADDON_NAME, MZ = ...

local App = MZ.App
assert(App and App._modules, "App: core/Init 未就绪")

local M = App._modules
assert(M.Log and M.Store and M.Event and M.System and M.Time and M.Net, "App: 核心模块未就绪")
assert(App.GameModules and App.GameModules.Checkers and App.GameModules.Wisdom
	and App.GameModules.Dkp and App.GameModules.Timer and App.GameModules.Roster
	and App.GameModules.Assess, "App: GameModules 未就绪")

App.logManager   = M.Log
App.storeManager = M.Store
App.eventManager = M.Event
App.system       = M.System

App.Core = {
	Log      = M.Log,
	Store    = M.Store,
	Time     = M.Time,
	Net      = M.Net,
	Event    = M.Event,
	System   = M.System,
}

App.UI = App.UI or nil

function App:Compose(parts)
	parts = parts or {}
	if parts.UI then self.UI = parts.UI end
	return self
end

function App:startApp()
	self.storeManager:init()
	self.logManager:Debug("Core 就绪 · v" .. tostring(self.VERSION))
	return self
end

function App:Init()
	return self:startApp()
end

function App:Ready()
	self.eventManager:emit(self.GlobalEvents.READY)
	self.logManager:Debug("App 就绪")
	return self
end

function App:Print(msg)
	self.logManager:Info(msg)
end

function App:GetDB()
	return self.storeManager:Get()
end

do
	local keep = App
	local keys = {}
	for k in pairs(MZ) do keys[#keys + 1] = k end
	for i = 1, #keys do MZ[keys[i]] = nil end
	MZ.App = keep
end
