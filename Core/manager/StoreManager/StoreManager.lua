-- ============================================================
-- StoreManager · SavedVariables
-- init 放到 ADDON_LOADED 之后，避免存档还没灌进来就写默认值。
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App

local StoreManager = App.Class("StoreManager", App.Manager)

local DEFAULTS = {
	scale        = 1.0,
	lastPage     = "activity",
	point        = nil,
	timerMinutes = 3,
}

function StoreManager:ctor()
	App.Manager.ctor(self)
	self._ready = false
end

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

function StoreManager:Defaults()
	return DEFAULTS
end

function StoreManager:init()
	if type(MoZhanNianHuaDB) ~= "table" then
		MoZhanNianHuaDB = {}
	end
	FillDefaults(DEFAULTS, MoZhanNianHuaDB)
	self._ready = true
	return MoZhanNianHuaDB
end

-- 旧调用名
StoreManager.Init = StoreManager.init

function StoreManager:Get()
	if not self._ready then self:init() end
	return MoZhanNianHuaDB
end

function StoreManager:GetKey(key, fallback)
	local db = self:Get()
	local v = db[key]
	if v == nil then return fallback end
	return v
end

function StoreManager:Set(key, value)
	self:Get()[key] = value
	return value
end

function StoreManager:Update(patch)
	if type(patch) ~= "table" then return self:Get() end
	local db = self:Get()
	for k, v in pairs(patch) do
		db[k] = v
	end
	return db
end

local Store = StoreManager:new()
App._modules.Store = Store
App.storeManager = Store
App:addManager(Store)
