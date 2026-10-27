-- ============================================================
-- LogManager · 聊天栏日志
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App

local LogManager = App.Class("LogManager", App.Manager)

local PREFIX = "|cffB33228墨战年华|r "
local LEVEL = { DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4 }

function LogManager:ctor()
	App.Manager.ctor(self)
	self._level = LEVEL.INFO
end

local function Push(cf, msg)
	if cf and cf.AddMessage then
		cf:AddMessage(msg)
		return true
	end
	return false
end

-- 综合窗口 + 当前选中的聊天窗口各写一份。
-- 不走 SendChatMessage：这是本机提示，不该刷公共频道。
local function Chat(msg)
	if not Push(DEFAULT_CHAT_FRAME, msg) then return end
	local sel = SELECTED_CHAT_FRAME
	if sel and sel ~= DEFAULT_CHAT_FRAME then Push(sel, msg) end
end

function LogManager:SetLevel(name)
	self._level = LEVEL[string.upper(tostring(name or "INFO"))] or LEVEL.INFO
end

function LogManager:Debug(msg)
	if self._level <= LEVEL.DEBUG then
		Chat(PREFIX .. "|cff888888[DBG]|r " .. tostring(msg))
	end
end

function LogManager:Info(msg)
	if self._level <= LEVEL.INFO then
		Chat(PREFIX .. tostring(msg))
	end
end

function LogManager:Warn(msg)
	if self._level <= LEVEL.WARN then
		Chat(PREFIX .. "|cffC9A227[警告]|r " .. tostring(msg))
	end
end

function LogManager:Error(msg)
	if self._level <= LEVEL.ERROR then
		Chat(PREFIX .. "|cffB33228[错误]|r " .. tostring(msg))
	end
end

local Log = LogManager:new()
App._modules.Log = Log
App.logManager = Log
App:addManager(Log)
