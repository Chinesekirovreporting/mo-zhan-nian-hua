-- ============================================================
-- Core Module · 存储管理器（SavedVariables 封装）
-- ============================================================
local ADDON_NAME, MZ = ...

local Store = {}
MZ.Modules.Store = Store

local DEFAULTS = {
	scale        = 1.0,
	lastPage     = "activity",
	point        = nil,
	timerMinutes = 3,
}

local ready = false

local function FillDefaults(src, dst)
	for k, v in pairs(src) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then dst[k] = {} end
			FillDefaults(v, dst[k])
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
end

function Store:Defaults()
	return DEFAULTS
end

function Store:Init()
	if type(MoZhanNianHuaDB) ~= "table" then
		MoZhanNianHuaDB = {}
	end
	FillDefaults(DEFAULTS, MoZhanNianHuaDB)
	ready = true
	return MoZhanNianHuaDB
end

function Store:Get()
	if not ready then self:Init() end
	return MoZhanNianHuaDB
end

function Store:GetKey(key, fallback)
	local db = self:Get()
	local v = db[key]
	if v == nil then return fallback end
	return v
end

function Store:Set(key, value)
	self:Get()[key] = value
	return value
end

function Store:Update(patch)
	if type(patch) ~= "table" then return self:Get() end
	local db = self:Get()
	for k, v in pairs(patch) do
		db[k] = v
	end
	return db
end
