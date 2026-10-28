-- ============================================================
-- DkpLogVo · 一条积分流水
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App

local DkpLogVo = App.newclz("DkpLogVo")

DkpLogVo.name = ""
DkpLogVo.delta = 0
DkpLogVo.reason = ""
DkpLogVo.at = 0

function DkpLogVo:ctor(name, delta, reason, at)
	self.name = name or ""
	self.delta = delta or 0
	self.reason = reason or ""
	self.at = at or 0
end

App.DkpLogVo = DkpLogVo
