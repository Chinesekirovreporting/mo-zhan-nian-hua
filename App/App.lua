-- ============================================================
-- App · 门面（MZ 对外唯一入口）
-- 组装 Core（底层能力）+ 预留 Skin / UI（由 GameInit Compose）
-- ============================================================
local ADDON_NAME, MZ = ...

local App = MZ.App
assert(App and App._modules, "App: Core/Init 未就绪")

local M = App._modules
assert(M.Log and M.Store and M.Event and M.Time, "App: 核心 Modules 未就绪")

-- -------------------- Core 门面（底层函数）--------------------
local Core = {
	Log      = M.Log,
	Store    = M.Store,
	Event    = M.Event,
	Time     = M.Time,
	Net      = M.Net,
	Checkers = M.Checkers,
}

function Core:Init()
	self.Store:Init()
	self.Log:Debug("Core 就绪 · v" .. tostring(App.VERSION))
	return self
end

App.Core = Core

-- View 层由 GameInit Compose
App.Skin = App.Skin or nil
App.UI   = App.UI or nil

function App:Compose(parts)
	parts = parts or {}
	if parts.Skin then self.Skin = parts.Skin end
	if parts.UI then self.UI = parts.UI end
	return self
end

function App:Init()
	self.Core:Init()
	return self
end

function App:Ready()
	self.Core.Event:Send("MZ_READY")
	self.Core.Log:Debug("App 就绪")
	return self
end

function App:Print(msg)
	self.Core.Log:Info(msg)
end

function App:GetDB()
	return self.Core.Store:Get()
end

-- 确保 MZ 上只挂 App（清掉加载期可能残留的旁路键）
do
	local keep = App
	local keys = {}
	for k in pairs(MZ) do keys[#keys + 1] = k end
	for i = 1, #keys do MZ[keys[i]] = nil end
	MZ.App = keep
end
