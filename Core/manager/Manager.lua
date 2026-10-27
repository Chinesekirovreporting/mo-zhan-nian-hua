-- ============================================================
-- Manager · 管理器基类
-- 带事件，并有 init / update / destroy。
-- update 由 App:updateTick 每帧调用，dt 是秒。
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App

local Manager = App.Class("Manager", App.EventEmitter)

function Manager:ctor()
	App.EventEmitter.ctor(self)
end

function Manager:init()
end

function Manager:update(_dt)
end

function Manager:destroy()
	self:dispose()
end

App.Manager = Manager
