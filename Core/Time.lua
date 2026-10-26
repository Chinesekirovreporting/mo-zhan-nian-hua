-- ============================================================
-- Core Module · 时间管理器
--   After / Every / Cancel / Format / Now
-- ============================================================
local ADDON_NAME, MZ = ...

local Time = {}
MZ.App._modules.Time = Time

local driver = CreateFrame("Frame")
driver:Hide()

local nextId = 0
local jobs = {}

local function ModLog()
	local App = MZ.App
	if App.Core and App.Core.Log then return App.Core.Log end
	return App._modules and App._modules.Log
end

local function Arm()
	driver:Show()
end

local function NewHandle(id)
	return {
		id = id,
		Cancel = function(self)
			Time:Cancel(self)
		end,
	}
end

driver:SetScript("OnUpdate", function()
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

	if not next(jobs) then
		driver:Hide()
	end
end)

function Time:After(delay, fn)
	if type(fn) ~= "function" then return end
	delay = math.max(0, tonumber(delay) or 0)
	nextId = nextId + 1
	local id = nextId
	jobs[id] = {
		kind   = "after",
		fireAt = GetTime() + delay,
		fn     = fn,
	}
	Arm()
	return NewHandle(id)
end

function Time:Every(interval, fn, iterations)
	if type(fn) ~= "function" then return end
	interval = math.max(0.05, tonumber(interval) or 1)
	nextId = nextId + 1
	local id = nextId
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
		jobs[id] = nil
	end
	Arm()
	return handle
end

function Time:Cancel(handle)
	if not handle then return end
	local id = handle.id
	local job = id and jobs[id]
	if job then
		job.cancelled = true
		jobs[id] = nil
	end
end

function Time:Now()
	return GetTime()
end

function Time:Format(sec)
	sec = math.max(0, math.floor((sec or 0) + 0.5))
	return string.format("%02d:%02d", math.floor(sec / 60), sec % 60)
end
