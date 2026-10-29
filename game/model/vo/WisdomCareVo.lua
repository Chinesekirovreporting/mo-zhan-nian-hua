-- ============================================================
-- WisdomCareVo · 年轮上的一次照料
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App

local WisdomCareVo = App.newclz("WisdomCareVo")

WisdomCareVo.name = ""
WisdomCareVo.act = ""
WisdomCareVo.at = 0

function WisdomCareVo:ctor(name, act, at)
	self.name = name or ""
	self.act = act or ""
	self.at = at or 0
end

App.WisdomCareVo = WisdomCareVo
