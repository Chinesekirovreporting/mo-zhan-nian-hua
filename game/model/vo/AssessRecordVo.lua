-- ============================================================
-- AssessRecordVo · 一名成员的木桩记录
-- 平均是各次秒伤的算术平均，最高是其中最好的一次。
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App

local AssessRecordVo = App.newclz("AssessRecordVo")

AssessRecordVo.name = ""
AssessRecordVo.classFile = nil
AssessRecordVo.samples = nil

function AssessRecordVo:ctor(name, classFile)
	self.name = name or ""
	self.classFile = classFile
	self.samples = {}
end

function AssessRecordVo:From(name, raw)
	local classFile = type(raw) == "table" and raw.classFile or nil
	local vo = AssessRecordVo:new(name, classFile)
	if type(raw) == "table" and type(raw.samples) == "table" then
		for i = 1, #raw.samples do
			local s = raw.samples[i]
			if type(s) == "table" then
				vo.samples[#vo.samples + 1] = App.AssessSampleVo:new(s.dps, s.damage, s.seconds, s.at)
			end
		end
	end
	return vo
end

function AssessRecordVo:Avg()
	local n = #self.samples
	if n == 0 then return 0 end
	local sum = 0
	for i = 1, n do
		sum = sum + (self.samples[i].dps or 0)
	end
	return sum / n
end

function AssessRecordVo:Max()
	local best = 0
	for i = 1, #self.samples do
		local dps = self.samples[i].dps or 0
		if dps > best then best = dps end
	end
	return best
end

function AssessRecordVo:Last()
	return self.samples[#self.samples]
end

App.AssessRecordVo = AssessRecordVo
