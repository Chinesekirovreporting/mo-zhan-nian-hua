-- ============================================================
-- CheckersSeatVo · 一个座位
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App

local CheckersSeatVo = App.newclz("CheckersSeatVo")

CheckersSeatVo.name = ""
CheckersSeatVo.ready = false
CheckersSeatVo.seen = 0

function CheckersSeatVo:ctor(name, ready, seen)
	self.name = name or ""
	self.ready = ready and true or false
	self.seen = seen or 0
end

App.CheckersSeatVo = CheckersSeatVo
