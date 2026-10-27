-- ============================================================
-- Command · 斜杠命令
-- 只登记命令。面板开关、跳棋直达、诊断都从这里进。
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App

local function OpenMain(msg)
	App.UI:Slash(msg)
end

local function OpenCheckers()
	local ui = App.UI
	if not ui._ready then ui:Build() end
	if not ui.frame:IsShown() then ui.frame:Show() end
	ui:ShowPage("checkers")
end

local function Diag()
	local G = App.GameModules.Checkers
	local function LogLine(msg)
		local log = App.Core.Log or (App._modules and App._modules.Log)
		if log then log:Info(msg) end
	end

	local chans = "无"
	if App.Core.Net then
		local list = App.Core.Net:Channels()
		if #list > 0 then chans = table.concat(list, "+") end
	end

	local names = {}
	for i = 1, 6 do
		if G.seats[i] then names[#names + 1] = i .. "号" .. G.seats[i].name end
	end

	local parts = {
		"频道 " .. chans,
		"我 " .. G:Me() .. "（" .. tostring(G:MySeat()) .. " 号座）",
		"房主 " .. (G:IsHost() and "是我" or "不是我"),
		"阶段 " .. G.phase .. "，轮到 " .. tostring(G.turn),
		"在座 " .. G:SeatedCount() .. " 人：" .. (#names > 0 and table.concat(names, "、") or "无"),
	}
	if not G:IsHost() then
		parts[#parts + 1] = "收到房主快照：" .. (G.lastHostAt
			and string.format("%.0f 秒前", GetTime() - G.lastHostAt)
			or "从未收到")
	end
	LogLine("跳棋诊断 — " .. table.concat(parts, " ｜ "))
end

SLASH_MOZHANNIANHUA1 = "/mz"
SLASH_MOZHANNIANHUA2 = "/mznh"
SLASH_MOZHANNIANHUA3 = "/mozhan"
SLASH_MOZHANNIANHUA4 = "/墨战"
SlashCmdList["MOZHANNIANHUA"] = OpenMain

SLASH_MZCHECKERS1 = "/跳棋"
SLASH_MZCHECKERS2 = "/checkers"
SlashCmdList["MZCHECKERS"] = OpenCheckers

SLASH_MZCHKDIAG1 = "/跳棋诊断"
SlashCmdList["MZCHKDIAG"] = Diag
