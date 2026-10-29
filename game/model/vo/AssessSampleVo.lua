-- ============================================================
-- AssessSampleVo · 一次木桩考核
-- dps 是这次的秒伤，seconds 是从第一下到最后一下的时长。
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App

local AssessSampleVo = App.newclz("AssessSampleVo")

AssessSampleVo.dps = 0
AssessSampleVo.damage = 0
AssessSampleVo.seconds = 0
AssessSampleVo.at = 0

function AssessSampleVo:ctor(dps, damage, seconds, at)
	self.dps = tonumber(dps) or 0
	self.damage = tonumber(damage) or 0
	self.seconds = tonumber(seconds) or 0
	self.at = tonumber(at) or 0
end

App.AssessSampleVo = AssessSampleVo
