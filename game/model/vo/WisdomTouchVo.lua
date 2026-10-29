-- ============================================================
-- WisdomTouchVo · 一个成员的浇水或施肥记录
-- last 是上次动手的服务器时间，count 是累计次数。
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App

local WisdomTouchVo = App.newclz("WisdomTouchVo")

WisdomTouchVo.last = 0
WisdomTouchVo.count = 0

function WisdomTouchVo:ctor(last, count)
	self.last = last or 0
	self.count = count or 0
end

App.WisdomTouchVo = WisdomTouchVo
