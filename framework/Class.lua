-- ============================================================
-- newclz · 语法层的类工厂
-- 实例查子类，子类查父类。子类写了 ctor 时要自己调用父类 ctor。
-- App.Class 与 newclz 是同一个函数，旧文件不用改调用名。
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App

local function newclz(name, base)
	local cls = {}
	cls.className = name
	cls.super = base
	cls.__index = cls
	if base then
		setmetatable(cls, { __index = base })
	end

	function cls:new(...)
		local obj = setmetatable({}, cls)
		if obj.ctor then
			obj:ctor(...)
		end
		return obj
	end

	return cls
end

App.newclz = newclz
App.Class = newclz
