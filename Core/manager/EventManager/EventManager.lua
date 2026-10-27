-- ============================================================
-- EventManager · 对外的事件管理器
-- 暴雪事件和代码事件都是它的内部件。外面只拿这个类。
--   On / Once / Off     暴雪事件，回调第一个参数是事件名
--   on / emit           代码事件，回调只有载荷
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App

local EventManager = App.newclz("EventManager", App.Manager)

function EventManager:ctor()
	App.Manager.ctor(self)
	self.system = App._modules.System
	self.code = App._modules.Code
end

function EventManager:On(event, fn, thisArg)
	return self.system:On(event, fn, thisArg)
end

function EventManager:Once(event, fn, thisArg)
	return self.system:Once(event, fn, thisArg)
end

function EventManager:Off(event, fn)
	return self.system:Off(event, fn)
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

function EventManager:OnMsg(name, fn)
	return self.code:OnMsg(name, fn)
end

function EventManager:OffMsg(name, fn)
	return self.code:OffMsg(name, fn)
end

function EventManager:Send(name, ...)
	return self.code:Send(name, ...)
end

local inst = EventManager:new()
App._modules.Event = inst
App.eventManager = inst
App.system = inst.system
App.code = inst.code
App.events = inst.code
App:addManager(inst)
