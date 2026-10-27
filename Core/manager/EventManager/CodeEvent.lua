-- ============================================================
-- CodeEvent · 插件自己的代码事件
-- 小写 on / once / off / emit。回调只收载荷，不塞事件名。
-- OnMsg / OffMsg 仍把事件名放在第一个参数，留给旧调用。
-- 暴雪事件不走这里，走 SystemEvent。
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App

local bus = App.EventBus:new()
bus._msgWrap = {}

function bus:OnMsg(name, fn)
	if type(name) ~= "string" or type(fn) ~= "function" then return end
	local wrapped = function(...)
		return fn(name, ...)
	end
	self._msgWrap[fn] = wrapped
	return self:on(name, wrapped)
end

function bus:OffMsg(name, fn)
	if type(name) ~= "string" then return end
	if type(fn) ~= "function" then
		return self:off(name)
	end
	local wrapped = self._msgWrap[fn]
	self._msgWrap[fn] = nil
	return self:off(name, wrapped or fn)
end

function bus:Send(name, ...)
	return self:emit(name, ...)
end

App._modules.Code = bus
