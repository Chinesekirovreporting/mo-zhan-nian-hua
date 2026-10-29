-- ============================================================
-- View · 智慧树
-- 骨架：game/skin/WisdomView.xml。树形随阶数长出来，点击进模块。
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App

local SHAPE = {
	{ trunk = 0, cups = 0 },
	{ trunk = 16, cups = 0 },
	{ trunk = 28, cups = 1 },
	{ trunk = 40, cups = 1 },
	{ trunk = 52, cups = 2 },
	{ trunk = 62, cups = 2 },
	{ trunk = 70, cups = 3 },
	{ trunk = 76, cups = 3 },
	{ trunk = 82, cups = 4 },
	{ trunk = 88, cups = 4 },
}

local WisdomView = App.newclz("WisdomView", App.AbstractView)

function WisdomView:ctor()
	App.AbstractView.ctor(self, {
		id       = "wisdom",
		title    = "智慧树",
		subtitle = "全公会一起养，离开了也会长",
		order    = 13,
		frame    = "MZPageWisdom",
	})
end

function WisdomView:Grow(plot)
	local W = App.Widget
	local C = App.C
	W:Paint(plot, "paperLight")
	W:Stroke(plot, "line", 0, 0.4)

	local function block(w, h, tone, alpha)
		local f = CreateFrame("Frame", nil, plot)
		f:SetSize(w, h)
		local tex = f:CreateTexture(nil, "ARTWORK")
		tex:SetAllPoints()
		W:Solid(tex, C[tone], alpha)
		return f
	end

	self.ground = block(120, 2, "ink", 0.4)
	self.ground:SetPoint("BOTTOM", plot, "BOTTOM", 0, 16)
	self.seed = block(10, 10, "ink", 0.9)
	self.seed:SetPoint("BOTTOM", self.ground, "TOP", 0, 4)
	self.trunk = block(7, 40, "ink", 0.92)
	self.trunk:SetPoint("BOTTOM", self.ground, "TOP", 0, 0)

	local cups = {
		{ 36, 20, -6, "inkSoft", 0.55 },
		{ 58, 22, 10, "inkSoft", 0.7 },
		{ 78, 22, 28, "ink", 0.72 },
		{ 42, 16, 46, "ink", 0.88 },
	}
	self.cups = {}
	for i = 1, #cups do
		local spec = cups[i]
		local cup = block(spec[1], spec[2], spec[4], spec[5])
		cup:SetPoint("BOTTOM", self.trunk, "TOP", 0, spec[3])
		cup:Hide()
		self.cups[i] = cup
	end

	self.fruits = {}
	for i = 1, 3 do
		local dot = block(8, 8, "cinnabar", 1)
		dot:Hide()
		self.fruits[i] = dot
	end
end

function WisdomView:Draw(model)
	if not self.trunk then return end
	local shape = SHAPE[model.stage or 1] or SHAPE[#SHAPE]
	local cups = shape.cups
	if shape.trunk <= 0 then
		self.trunk:Hide()
		self.seed:Show()
	else
		self.seed:Hide()
		self.trunk:Show()
		self.trunk:SetHeight(shape.trunk)
	end
	for i = 1, #self.cups do
		if i <= cups then
			self.cups[i]:Show()
		else
			self.cups[i]:Hide()
		end
	end

	local spots = {}
	for i = cups, 1, -1 do
		spots[#spots + 1] = self.cups[i]
	end
	if #spots == 0 then
		spots[1] = self.trunk:IsShown() and self.trunk or self.seed
	end
	local n = math.min(3, model.fruitReady or 0)
	for i = 1, 3 do
		local spot = spots[i]
		local dot = self.fruits[i]
		if i <= n and spot then
			dot:ClearAllPoints()
			dot:SetPoint("CENTER", spot, "CENTER", (i - 2) * 12, 2)
			dot:Show()
		else
			dot:Hide()
		end
	end
end

function WisdomView:Paint(model)
	local W = App.Widget
	model = model or App.GameModules.Wisdom.model
	_G["MZWisdomStage"]:SetText(model.stageName or "")
	_G["MZWisdomHeight"]:SetText(model.heightText or "")
	_G["MZWisdomNutrient"]:SetText(model.nutrientText or "")
	_G["MZWisdomIdle"]:SetText(model.idleText or "")
	_G["MZWisdomFruit"]:SetText(model.fruitText or "")
	_G["MZWisdomQuote"]:SetText(model.quote or "")
	_G["MZWisdomCd"]:SetText(model.cdText or "")
	_G["MZWisdomBanner"]:SetText(model.banner or "")
	_G["MZWisdomRank"]:SetText(model.rankText or "")
	_G["MZWisdomLog"]:SetText(model.logText or "")
	self:Draw(model)
	if self._waterReady ~= model.waterReady then
		self._waterReady = model.waterReady
		W:ApplyTone(self.waterBtn, model.waterReady and true or false)
	end
	local pickReady = (model.fruitReady or 0) > 0
	if self._pickReady ~= pickReady then
		self._pickReady = pickReady
		W:ApplyTone(self.pickBtn, pickReady)
	end
end

function WisdomView:onBuild()
	local W = App.Widget
	local tree = App.GameModules.Wisdom
	self.waterBtn = _G["MZWisdomWater"]
	self.fertBtn = _G["MZWisdomFert"]
	self.pickBtn = _G["MZWisdomPick"]
	W:TuneButton(self.waterBtn, 13, true)
	W:TuneButton(self.fertBtn)
	W:TuneButton(self.pickBtn)
	W:PaintText(_G["MZWisdomStage"], 18, "ink")
	W:PaintText(_G["MZWisdomHeight"], 13, "ink")
	W:PaintText(_G["MZWisdomNutrient"], 12, "inkSoft")
	W:PaintText(_G["MZWisdomIdle"], 12, "inkFaint")
	W:PaintText(_G["MZWisdomFruit"], 12, "ink")
	W:PaintText(_G["MZWisdomQuote"], 12, "inkFaint")
	W:PaintText(_G["MZWisdomCd"], 12, "inkSoft")
	W:PaintText(_G["MZWisdomBanner"], 11, "inkFaint")
	W:PaintText(_G["MZWisdomRankTitle"], 13, "ink", "养护")
	W:PaintText(_G["MZWisdomRank"], 12, "inkSoft")
	W:PaintText(_G["MZWisdomLogTitle"], 13, "ink", "年轮")
	W:PaintText(_G["MZWisdomLog"], 12, "inkSoft")
	_G["MZWisdomQuote"]:SetWordWrap(true)
	_G["MZWisdomRank"]:SetWordWrap(true)
	_G["MZWisdomLog"]:SetWordWrap(true)
	_G["MZWisdomQuote"]:SetJustifyV("TOP")
	_G["MZWisdomRank"]:SetJustifyV("TOP")
	_G["MZWisdomLog"]:SetJustifyV("TOP")
	self:Grow(_G["MZWisdomPlot"])

	local view = self
	tree:on("sync", function(model)
		view:Paint(model)
	end)
	App.Hook:Bind(self.waterBtn, "OnClick", function()
		tree:Water()
	end)
	App.Hook:Bind(self.fertBtn, "OnClick", function()
		tree:Fertilize()
	end)
	App.Hook:Bind(self.pickBtn, "OnClick", function()
		tree:Pick()
	end)
	tree:Ensure()
	self:Paint(tree.model)
end

function WisdomView:onShow()
	App.GameModules.Wisdom:Watch(true)
end

function WisdomView:onHide()
	App.GameModules.Wisdom:Watch(false)
end

WisdomView:new():register()
