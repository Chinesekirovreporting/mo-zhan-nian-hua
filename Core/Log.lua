-- ============================================================
-- Core Module · 日志管理器
-- ============================================================
local ADDON_NAME, MZ = ...

local Log = {}
MZ.App._modules.Log = Log

local PREFIX = "|cffB33228墨战年华|r "
local LEVEL = { DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4 }
local current = LEVEL.INFO

local function Push(cf, msg)
	if cf and cf.AddMessage then
		cf:AddMessage(msg)
		return true
	end
	return false
end

-- 综合窗口 + 当前选中的聊天窗口各写一份。
-- 不走 SendChatMessage：这是本机提示，不该刷公共频道；
-- 也不带 messageType：带上反而会被窗口的类型过滤挡住。
local function Chat(msg)
	if not Push(DEFAULT_CHAT_FRAME, msg) then return end
	local sel = SELECTED_CHAT_FRAME
	if sel and sel ~= DEFAULT_CHAT_FRAME then Push(sel, msg) end
end

function Log:SetLevel(name)
	current = LEVEL[string.upper(tostring(name or "INFO"))] or LEVEL.INFO
end

function Log:Debug(msg)
	if current <= LEVEL.DEBUG then
		Chat(PREFIX .. "|cff888888[DBG]|r " .. tostring(msg))
	end
end

function Log:Info(msg)
	if current <= LEVEL.INFO then
		Chat(PREFIX .. tostring(msg))
	end
end

function Log:Warn(msg)
	if current <= LEVEL.WARN then
		Chat(PREFIX .. "|cffC9A227[警告]|r " .. tostring(msg))
	end
end

function Log:Error(msg)
	if current <= LEVEL.ERROR then
		Chat(PREFIX .. "|cffB33228[错误]|r " .. tostring(msg))
	end
end
