-- ============================================================
-- SystemEvent · 暴雪系统事件
-- 只提供 On / Once / Off。回调第一个参数是事件名。
-- 不提供 on / emit。代码事件走 CodeEvent。
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App

local SystemEvent = App.newclz("SystemEvent")

function SystemEvent:ctor()
	self._wow = {}
	self._driver = App.Hook:Own(CreateFrame("Frame", "MZSystemEventDriver"))
	local mgr = self
	App.Hook:Bind(self._driver, "OnEvent", function(_, event, ...)
		mgr:_dispatch(event, ...)
	end)
end

function SystemEvent:_report(event, err)
	local log = App._modules and App._modules.Log
	if not log and App.Core then log = App.Core.Log end
	if log then
		log:Error(string.format("[System] %s：%s", tostring(event), tostring(err)))
	end
end

function SystemEvent:_ensure(event)
	if not self._wow[event] then
		self._wow[event] = {}
		App.Hook:Listen(self._driver, event)
	end
end

function SystemEvent:_add(event, fn, thisArg, once)
	self:_ensure(event)
	local list = self._wow[event]
	local record = {
		fn = fn,
		thisArg = thisArg,
		once = once and true or false,
		active = true,
	}
	local mgr = self

	function record.remove()
		if not record.active then return end
		record.active = false
		local current = mgr._wow[event]
		if not current then return end
		for i = #current, 1, -1 do
			if current[i] == record then
				table.remove(current, i)
			end
		end
		if #current == 0 then
			mgr._wow[event] = nil
			App.Hook:Silence(mgr._driver, event)
		end
	end

	list[#list + 1] = record
	return record.remove
end

function SystemEvent:_dispatch(event, ...)
	local list = self._wow[event]
	if not list or #list == 0 then return end

	local snapshot = {}
	for i = 1, #list do snapshot[i] = list[i] end

	for i = 1, #snapshot do
		local entry = snapshot[i]
		if entry.active then
			if entry.once then entry.remove() end
			local ok, err
			if entry.thisArg ~= nil then
				ok, err = pcall(entry.fn, entry.thisArg, event, ...)
			else
				ok, err = pcall(entry.fn, event, ...)
			end
			if not ok then self:_report(event, err) end
		end
	end
end

function SystemEvent:On(event, fn, thisArg)
	if type(event) ~= "string" or type(fn) ~= "function" then return end
	self:_add(event, fn, thisArg, false)
	return fn
end

function SystemEvent:Once(event, fn, thisArg)
	if type(event) ~= "string" or type(fn) ~= "function" then return end
	self:_add(event, fn, thisArg, true)
	return fn
end

function SystemEvent:Off(event, fn)
	local list = self._wow[event]
	if not list then return end
	if type(fn) ~= "function" then
		for i = #list, 1, -1 do list[i].remove() end
		return
	end
	for i = #list, 1, -1 do
		if list[i].fn == fn then list[i].remove() end
	end
end

local system = SystemEvent:new()
App._modules.System = system
App.system = system
