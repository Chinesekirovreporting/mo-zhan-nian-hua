-- ============================================================
-- AbstractModule · 功能模块基类
-- enterModule 第一次进入时 init，然后 show。exitModule 走 remove。
-- 本插件没有场景切换，因此不移植 scene / changeScene。
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App

local AbstractModule = App.Class("AbstractModule", App.EventEmitter)

function AbstractModule:ctor(moduleName)
	App.EventEmitter.ctor(self)
	self.moduleName = moduleName or ""
	self.inited = false
end

function AbstractModule:enterModule()
	if not self.inited then
		self:init()
		self.inited = true
	end
	self:show()
end

function AbstractModule:exitModule()
	self:remove()
end

function AbstractModule:reset()
end

function AbstractModule:init()
end

function AbstractModule:show()
end

function AbstractModule:remove()
	self:removeAll()
end

App.AbstractModule = AbstractModule
