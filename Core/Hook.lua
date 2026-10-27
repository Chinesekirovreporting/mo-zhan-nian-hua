-- ============================================================
-- Hook · 钩子分层
--   Never  完全不会因保护机制被禁用：自己框体上的 SetScript / RegisterEvent
--   Maybe  有可能受限：HookScript、hooksecurefunc。只允许挂在本插件框体上，
--          且函数名不在 Always 里
--   Always 一定拒绝：战斗施法、移动、宏执行。这里不调用它们，只在有人
--          试图经 Hook 挂上时直接报错
-- 不提供绕过保护或规避检测的路径。
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App

local Hook = {}
App.Hook = Hook

-- 名字 → 入口。调用方走这些方法，不直接碰暴雪钩子。
Hook.Never = {
	SetScript = "Bind",
	RegisterEvent = "Listen",
	UnregisterEvent = "Silence",
}

Hook.Maybe = {
	HookScript = "Attach",
	hooksecurefunc = "After",
}

-- 受保护、会推动角色行动的接口。插件代码不应挂钩或转调。
Hook.Always = {
	CastSpellByName = true,
	CastSpell = true,
	CastSpellByID = true,
	UseAction = true,
	UseContainerItem = true,
	UseItemByName = true,
	RunMacro = true,
	RunMacroText = true,
	AttackTarget = true,
	PetAttack = true,
	CastPetAction = true,
	JumpOrAscendStart = true,
	AscendStop = true,
	MoveForwardStart = true,
	MoveBackwardStart = true,
	StrafeLeftStart = true,
	StrafeRightStart = true,
	TurnLeftStart = true,
	TurnRightStart = true,
	ToggleAutoRun = true,
	CameraOrSelectOrMoveStart = true,
	TargetNearestEnemy = true,
}

Hook._owned = {}
Hook._afterSeen = {}

function Hook:Own(frame)
	if frame then self._owned[frame] = true end
	return frame
end

function Hook:IsOurs(frame)
	if type(frame) ~= "table" then return false end
	if self._owned[frame] then return true end
	local current = frame
	for _ = 1, 40 do
		if not current then return false end
		local name = current.GetName and current:GetName()
		if name == "MoZhanNianHuaFrame" then return true end
		if not current.GetParent then return false end
		local parent = current:GetParent()
		if parent == current then return false end
		current = parent
	end
	return false
end

function Hook:_frameOk(frame)
	if type(frame) ~= "table" or type(frame.SetScript) ~= "function" then
		error("Hook 需要一个框体", 3)
	end
	if frame.IsProtected and frame:IsProtected() then
		error("Hook 拒绝受保护框体", 3)
	end
	if not self._owned[frame] and not self:IsOurs(frame) then
		error("Hook 拒绝非本插件框体", 3)
	end
end

function Hook:Blocked(name)
	error("Hook 拒绝一定会被禁用的函数：" .. tostring(name), 2)
end

-- Never · 替换自己框体上的脚本
function Hook:Bind(frame, script, fn)
	self:_frameOk(frame)
	if type(script) ~= "string" or type(fn) ~= "function" then
		error("Hook:Bind 需要脚本名和函数", 2)
	end
	frame:SetScript(script, fn)
	return fn
end

-- Never · 在自己的事件框上登记暴雪事件
function Hook:Listen(frame, event)
	self:_frameOk(frame)
	if type(event) ~= "string" then
		error("Hook:Listen 需要事件名", 2)
	end
	frame:RegisterEvent(event)
end

-- Never
function Hook:Silence(frame, event)
	self:_frameOk(frame)
	if type(event) ~= "string" then
		error("Hook:Silence 需要事件名", 2)
	end
	frame:UnregisterEvent(event)
end

-- Maybe · 在自己的框体上追加脚本，不替换已有处理
function Hook:Attach(frame, script, fn)
	self:_frameOk(frame)
	if type(script) ~= "string" or type(fn) ~= "function" then
		error("Hook:Attach 需要脚本名和函数", 2)
	end
	if type(frame.HookScript) ~= "function" then
		error("Hook:Attach 当前客户端没有 HookScript", 2)
	end
	frame:HookScript(script, fn)
	return fn
end

-- Maybe · 在非禁用函数之后追加调用
function Hook:After(name, fn)
	if type(name) ~= "string" or type(fn) ~= "function" then
		error("Hook:After 需要函数名和回调", 2)
	end
	if self.Always[name] then
		self:Blocked(name)
	end
	if type(hooksecurefunc) ~= "function" then
		error("Hook:After 当前客户端没有 hooksecurefunc", 2)
	end
	if type(_G[name]) ~= "function" then
		error("Hook:After 找不到函数 " .. name, 2)
	end
	if not self._afterSeen[name] then
		self._afterSeen[name] = true
		local log = App._modules and App._modules.Log
		if log then
			log:Debug("Hook:After " .. name .. "（可能受限，仅非禁用函数）")
		end
	end
	hooksecurefunc(name, fn)
	return fn
end

-- 每帧驱动。OnUpdate 只在框体显示时才会走，不要 Hide。
local driver = CreateFrame("Frame", "MZUpdateDriver")
Hook:Own(driver)
Hook:Bind(driver, "OnUpdate", function(_, elapsed)
	App:updateTick(elapsed or 0)
end)
driver:Show()
App._driver = driver
