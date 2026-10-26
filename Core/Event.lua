-- ============================================================
-- Core Module · 事件管理器
--   On / Off / Once：暴雪事件
--   OnMsg / OffMsg / Send：内部消息总线
-- ============================================================
local ADDON_NAME, MZ = ...

local Event = {}
MZ.App._modules.Event = Event

local driver = CreateFrame("Frame")
local wowListeners = {}
local msgListeners = {}

local function ModLog()
	local App = MZ.App
	if App.Core and App.Core.Log then return App.Core.Log end
	return App._modules and App._modules.Log
end

local function SafeCall(fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		local log = ModLog()
		if log then log:Error(tostring(err)) end
	end
end

driver:SetScript("OnEvent", function(_, event, ...)
	local list = wowListeners[event]
	if not list or #list == 0 then return end

	local snapshot = {}
	for i = 1, #list do snapshot[i] = list[i] end

	for i = 1, #snapshot do
		local entry = snapshot[i]
		SafeCall(entry.fn, event, ...)
		if entry.once then
			Event:Off(event, entry.fn)
		end
	end
end)

local function EnsureRegistered(event)
	if not wowListeners[event] then
		wowListeners[event] = {}
		driver:RegisterEvent(event)
	end
end

local function RemoveListener(list, fn)
	if not list then return end
	for i = #list, 1, -1 do
		if list[i].fn == fn or list[i] == fn then
			table.remove(list, i)
		end
	end
end

function Event:On(event, fn)
	if type(event) ~= "string" or type(fn) ~= "function" then return end
	EnsureRegistered(event)
	table.insert(wowListeners[event], { fn = fn, once = false })
	return fn
end

function Event:Once(event, fn)
	if type(event) ~= "string" or type(fn) ~= "function" then return end
	EnsureRegistered(event)
	table.insert(wowListeners[event], { fn = fn, once = true })
	return fn
end

function Event:Off(event, fn)
	local list = wowListeners[event]
	if not list then return end
	if fn then
		RemoveListener(list, fn)
	else
		for i = #list, 1, -1 do table.remove(list, i) end
	end
	if #list == 0 then
		driver:UnregisterEvent(event)
		wowListeners[event] = nil
	end
end

function Event:OnMsg(name, fn)
	if type(name) ~= "string" or type(fn) ~= "function" then return end
	msgListeners[name] = msgListeners[name] or {}
	table.insert(msgListeners[name], fn)
	return fn
end

function Event:OffMsg(name, fn)
	local list = msgListeners[name]
	if not list then return end
	if not fn then
		msgListeners[name] = nil
		return
	end
	for i = #list, 1, -1 do
		if list[i] == fn then table.remove(list, i) end
	end
end

function Event:Send(name, ...)
	local list = msgListeners[name]
	if not list then return end
	local snapshot = {}
	for i = 1, #list do snapshot[i] = list[i] end
	for i = 1, #snapshot do
		SafeCall(snapshot[i], name, ...)
	end
end
