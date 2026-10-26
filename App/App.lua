-- ============================================================
-- App · 门面（私有模块）
-- 将 Core Modules 组装为统一 Core 外观，并挂到 MZ 快捷入口
-- ============================================================
local ADDON_NAME, MZ = ...

local M = MZ.Modules
assert(M and M.Log and M.Store and M.Event and M.Time, "App: Core Modules 未就绪")

-- -------------------- Core 门面 --------------------
local Core = {
	Log   = M.Log,
	Store = M.Store,
	Event = M.Event,
	Time  = M.Time,
}

--- 初始化 Core（存档等）；由 GameInit 在适当时机调用
function Core:Init()
	self.Store:Init()
	self.Log:Debug("Core 门面就绪 · v" .. tostring(MZ.VERSION))
	return self
end

MZ.Core = Core

-- -------------------- App 门面 --------------------
-- View 层（Skin / UI）由 GameInit 在界面脚本加载后 Compose 进来
local App = {
	Core = Core,
	Skin = nil,
	UI   = nil,
}

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

MZ.App = App

-- -------------------- 快捷入口（对外仍用 MZ.Log 等）--------------------
MZ.Log   = Core.Log
MZ.Store = Core.Store
MZ.Event = Core.Event
MZ.Time  = Core.Time

function MZ:Print(msg)
	Core.Log:Info(msg)
end

function MZ:GetDB()
	return Core.Store:Get()
end
