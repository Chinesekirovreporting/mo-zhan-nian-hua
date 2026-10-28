-- ============================================================
-- DkpMemberVo · 一名成员的 EP / GP
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App

local DkpMemberVo = App.newclz("DkpMemberVo")

DkpMemberVo.ep = 0
DkpMemberVo.gp = 0

function DkpMemberVo:ctor(ep, gp)
	self.ep = tonumber(ep) or 0
	self.gp = tonumber(gp) or 0
end

function DkpMemberVo:From(raw)
	if type(raw) == "table" then
		return DkpMemberVo:new(raw.ep, raw.gp)
	elseif type(raw) == "number" then
		return DkpMemberVo:new(raw, 0)
	end
	return DkpMemberVo:new(0, 0)
end

function DkpMemberVo:Net()
	return self.ep - self.gp
end

function DkpMemberVo:PR()
	return self.ep / math.max(1, self.gp)
end

App.DkpMemberVo = DkpMemberVo
