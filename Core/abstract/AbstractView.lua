-- ============================================================
-- AbstractView · 子窗口基类
-- def.frame 是 Skin 里同名 XML 页。主窗口是 MainUI，这里的都是它的子页。
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App

local AbstractView = App.newclz("AbstractView", App.AbstractModule)

function AbstractView:ctor(def)
	def = def or {}
	App.AbstractModule.ctor(self, def.id or "view")
	self.def = def
	self.page = nil
	self.body = nil
	self._built = false
end

function AbstractView:register()
	local ui = App.UI
	if not ui then
		error(self.className .. ":register 需要 MainUI 先加载")
	end

	local def = self.def
	local page = def.frame and _G[def.frame]
	if not page then
		error(self.className .. " 缺少 XML 页面 " .. tostring(def.frame))
	end
	local body = _G[def.frame .. "Body"]
	page.body = body
	page.titleFS = _G[def.frame .. "Title"]
	page.subtitleFS = _G[def.frame .. "Subtitle"]
	if page.titleFS and def.title then page.titleFS:SetText(def.title) end
	if page.subtitleFS then page.subtitleFS:SetText(def.subtitle or "") end

	local view = self
	ui:AddPage({
		id       = def.id,
		title    = def.title,
		subtitle = def.subtitle,
		order    = def.order,
		frame    = page,
		body     = body,
		build    = function()
			if view._built then return end
			view._built = true
			view.page = page
			view.body = body
			App.Hook:Attach(page, "OnShow", function() view:onShow() end)
			App.Hook:Attach(page, "OnHide", function() view:onHide() end)
			view:onBuild(page, body, App)
		end,
	})
	return self
end

function AbstractView:onBuild(_page, _body, _app)
end

function AbstractView:onShow()
end

function AbstractView:onHide()
end

function AbstractView:dispose()
	App.eventManager:targetOff(self)
	self:exitModule()
	self.page = nil
	self.body = nil
end

App.AbstractView = AbstractView
