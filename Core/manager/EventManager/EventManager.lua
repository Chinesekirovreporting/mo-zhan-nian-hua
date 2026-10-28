-- ============================================================
-- EventManager · 代码内的全局事件
-- 模块之间广播走这里。暴雪事件走 SystemEvent，插件频道走 NetManager。
--   on / once / off / emit    回调只有载荷，不带事件名
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App

local EventManager = App.newclz("EventManager", App.Manager)

function EventManager:ctor()
	App.Manager.ctor(self)
	self.code = App._modules.Code
end

function EventManager:on(event, fn, thisArg)
	return self.code:on(event, fn, thisArg)
end

function EventManager:once(event, fn, thisArg)
	return self.code:once(event, fn, thisArg)
end

function EventManager:off(event, fn, thisArg)
	return self.code:off(event, fn, thisArg)
end

function EventManager:emit(event, ...)
	return self.code:emit(event, ...)
end

function EventManager:targetOff(target)
	return self.code:targetOff(target)
end

local inst = EventManager:new()
App._modules.Event = inst
App.eventManager = inst
App:addManager(inst)
