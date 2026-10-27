-- ============================================================
-- EventBus · 一条独立总线
-- 和对象自己的 EventEmitter 同一套 on / emit，不绑定任何具体事件名。
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App

local EventBus = App.Class("EventBus", App.EventEmitter)

function EventBus:ctor()
	App.EventEmitter.ctor(self)
end

App.EventBus = EventBus
