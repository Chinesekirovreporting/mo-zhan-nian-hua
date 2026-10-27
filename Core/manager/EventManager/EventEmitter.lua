-- ============================================================
-- EventEmitter · 对象自己的事件
-- on / once / off / emit / targetOff / removeAll
-- on 返回取消函数。派发用快照，单个监听出错不影响后面的。
-- 带 thisArg 时，回调第一个参数是它（Lua 没有隐藏的 this）。
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App

local EventEmitter = App.Class("EventEmitter")

local function noop() end

function EventEmitter:ctor()
	self._listeners = {}
	self._disposed = false
end

function EventEmitter:isDisposed()
	return self._disposed and true or false
end

function EventEmitter:_report(event, err)
	local log = App._modules and App._modules.Log
	if not log and App.Core then log = App.Core.Log end
	if log then
		log:Error(string.format("[Event] %s：%s", tostring(event), tostring(err)))
	end
end

function EventEmitter:_subscribe(event, handler, thisArg, once)
	if self._disposed or type(event) ~= "string" or type(handler) ~= "function" then
		return noop
	end

	local bucket = self._listeners[event]
	if not bucket then
		bucket = {}
		self._listeners[event] = bucket
	end

	local record = {
		handler = handler,
		thisArg = thisArg,
		once = once and true or false,
		active = true,
	}

	function record.remove()
		if not record.active then return end
		record.active = false
		local current = self._listeners[event]
		if not current then return end
		for i = #current, 1, -1 do
			if current[i] == record then
				table.remove(current, i)
			end
		end
		if #current == 0 then
			self._listeners[event] = nil
		end
	end

	bucket[#bucket + 1] = record
	return record.remove
end

function EventEmitter:on(event, handler, thisArg)
	return self:_subscribe(event, handler, thisArg, false)
end

function EventEmitter:once(event, handler, thisArg)
	return self:_subscribe(event, handler, thisArg, true)
end

function EventEmitter:off(event, handler, thisArg)
	local bucket = self._listeners[event]
	if not bucket then return end
	if type(handler) ~= "function" then
		for i = #bucket, 1, -1 do
			bucket[i].remove()
		end
		return
	end
	local checkThis = thisArg ~= nil
	for i = #bucket, 1, -1 do
		local entry = bucket[i]
		if entry.handler == handler and (not checkThis or entry.thisArg == thisArg) then
			entry.remove()
		end
	end
end

function EventEmitter:emit(event, ...)
	if self._disposed then return end
	local bucket = self._listeners[event]
	if not bucket or #bucket == 0 then return end

	local snapshot = {}
	for i = 1, #bucket do snapshot[i] = bucket[i] end

	for i = 1, #snapshot do
		local entry = snapshot[i]
		if entry.active then
			if entry.once then entry.remove() end
			local ok, err
			if entry.thisArg ~= nil then
				ok, err = pcall(entry.handler, entry.thisArg, ...)
			else
				ok, err = pcall(entry.handler, ...)
			end
			if not ok then self:_report(event, err) end
		end
	end
end

function EventEmitter:targetOff(target)
	if target == nil then return end
	local names = {}
	for event in pairs(self._listeners) do
		names[#names + 1] = event
	end
	for i = 1, #names do
		local bucket = self._listeners[names[i]]
		if bucket then
			for j = #bucket, 1, -1 do
				if bucket[j].thisArg == target then
					bucket[j].remove()
				end
			end
		end
	end
end

function EventEmitter:removeAll(event)
	if event ~= nil then
		self:off(event)
		return
	end
	local names = {}
	for ev in pairs(self._listeners) do
		names[#names + 1] = ev
	end
	for i = 1, #names do
		self:off(names[i])
	end
end

function EventEmitter:clear(event)
	self:removeAll(event)
end

function EventEmitter:listenerCount(event)
	local bucket = self._listeners[event]
	return bucket and #bucket or 0
end

function EventEmitter:hasEventListener(event, handler, thisArg)
	local bucket = self._listeners[event]
	if not bucket then return false end
	if type(handler) ~= "function" then return #bucket > 0 end
	for i = 1, #bucket do
		local entry = bucket[i]
		if entry.active and entry.handler == handler and (thisArg == nil or entry.thisArg == thisArg) then
			return true
		end
	end
	return false
end

function EventEmitter:dispose()
	if self._disposed then return end
	self._disposed = true
	self:removeAll()
end

App.EventEmitter = EventEmitter
