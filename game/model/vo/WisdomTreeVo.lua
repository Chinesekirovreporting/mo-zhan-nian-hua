-- ============================================================
-- WisdomTreeVo · 智慧树当前这一屏
-- 寸数、阶名和文案由模块算好，界面只读这些字段。
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App

local WisdomTreeVo = App.newclz("WisdomTreeVo")

WisdomTreeVo.stage = 1
WisdomTreeVo.stageName = "种子"
WisdomTreeVo.fruitReady = 0
WisdomTreeVo.waterReady = true
WisdomTreeVo.heightText = "树高 0 尺"
WisdomTreeVo.nutrientText = "挂机 0　照料 0"
WisdomTreeVo.idleText = "种下之后，每 10 分钟长一寸"
WisdomTreeVo.fruitText = "可采摘 0 枚　·　悟性 0"
WisdomTreeVo.quote = ""
WisdomTreeVo.cdText = "浇水 可浇　　施肥 可施"
WisdomTreeVo.banner = "全公会一起养"
WisdomTreeVo.rankText = "还没有人照料"
WisdomTreeVo.logText = "年轮上还是空白"

function WisdomTreeVo:ctor()
	self.stage = 1
	self.stageName = "种子"
	self.fruitReady = 0
	self.waterReady = true
	self.heightText = "树高 0 尺"
	self.nutrientText = "挂机 0　照料 0"
	self.idleText = "种下之后，每 10 分钟长一寸"
	self.fruitText = "可采摘 0 枚　·　悟性 0"
	self.quote = ""
	self.cdText = "浇水 可浇　　施肥 可施"
	self.banner = "全公会一起养"
	self.rankText = "还没有人照料"
	self.logText = "年轮上还是空白"
end

App.WisdomTreeVo = WisdomTreeVo
