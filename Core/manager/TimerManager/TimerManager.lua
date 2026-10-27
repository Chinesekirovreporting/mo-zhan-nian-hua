-- ============================================================
-- TimerManager · After / Every / Cancel / Format / Now
-- 到点与否看 GetTime，由 App:updateTick 每帧扫一次。
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App

local TimerManager = App.Class("TimerManager", App.Manager)

function TimerManager:ctor()
	App.Manager.ctor(self)
	self._nextId = 0
	self._jobs = {}
end

local Time

local function ModLog()
	if App.Core and App.Core.Log then return App.Core.Log end
	return App._modules and App._modules.Log
end

local function NewHandle(id)
	return {
		id = id,
		Cancel = function(handle)
			Time:Cancel(handle)
		end,
	}
end

function TimerManager:After(delay, fn)
	if type(fn) ~= "function" then return end
	delay = math.max(0, tonumber(delay) or 0)
	self._nextId = self._nextId + 1
	local id = self._nextId
	self._jobs[id] = {
		kind   = "after",
		fireAt = GetTime() + delay,
		fn     = fn,
	}
	return NewHandle(id)
end

function TimerManager:Every(interval, fn, iterations)
	if type(fn) ~= "function" then return end
	interval = math.max(0.05, tonumber(interval) or 1)
	self._nextId = self._nextId + 1
	local id = self._nextId
	local jobs = self._jobs
	local job = {
		kind      = "every",
		interval  = interval,
		fireAt    = GetTime() + interval,
		fn        = fn,
		remaining = iterations,
		cancelled = false,
	}
	jobs[id] = job

	local handle = NewHandle(id)
	function handle:Cancel()
		job.cancelled = true
		Time._jobs[id] = nil
	end
	return handle
end

function TimerManager:Cancel(handle)
	if not handle then return end
	local id = handle.id
	local job = id and self._jobs[id]
	if job then
		job.cancelled = true
		self._jobs[id] = nil
	end
end

function TimerManager:Now()
	return GetTime()
end

function TimerManager:Format(sec)
	sec = math.max(0, math.floor((sec or 0) + 0.5))
	return string.format("%02d:%02d", math.floor(sec / 60), sec % 60)
end

function TimerManager:update()
	local jobs = self._jobs
	if not next(jobs) then return end

	local now = GetTime()
	local due = {}
	for id, job in pairs(jobs) do
		if not job.cancelled and now >= job.fireAt then
			due[#due + 1] = id
		end
	end

	for i = 1, #due do
		local id = due[i]
		local job = jobs[id]
		if job and not job.cancelled then
			if job.kind == "after" then
				jobs[id] = nil
				local ok, err = pcall(job.fn)
				if not ok then
					local log = ModLog()
					if log then log:Error(tostring(err)) end
				end
			elseif job.kind == "every" then
				job.fireAt = now + job.interval
				local ok, err = pcall(job.fn, job)
				if not ok then
					local log = ModLog()
					if log then log:Error(tostring(err)) end
				end
				if job.cancelled then
					jobs[id] = nil
				elseif job.remaining then
					job.remaining = job.remaining - 1
					if job.remaining <= 0 then
						jobs[id] = nil
					end
				end
			end
		end
	end
end

function TimerManager:destroy()
	self._jobs = {}
	App.Manager.destroy(self)
end

Time = TimerManager:new()
App._modules.Time = Time
App.timerManager = Time
App:addManager(Time)
