-- ============================================================
-- Core Module · 六角跳棋
--   棋盘几何 / 走子规则 / 座位·准备·观战 / 房主权威同步
--   本文件不写一行绘制代码，UI 见 Views/Checkers.lua
-- ============================================================
local ADDON_NAME, MZ = ...

local Net = MZ.Net
local Log = MZ.Modules.Log

local G = {}
MZ.Checkers = G

-- ------------------------------------------------------------
-- 1 · 棋盘几何
--   17 行星形，共 121 格。u = 半格横坐标（u/2 = 一格间距），v = 行号（自上而下）
--   ARM：0 = 中央区，1..6 = 六个营（1 南 · 2 东南 · 3 东北 · 4 北 · 5 西北 · 6 西南）
--   对面营：1<->4、2<->5、3<->6，即 (arm + 2) % 6 + 1
-- ------------------------------------------------------------
local ROWLEN = { 1, 2, 3, 4, 13, 12, 11, 10, 9, 10, 11, 12, 13, 4, 3, 2, 1 }

local ARM = {
	4,4,4,4,4,4,4,4,4,4,5,5,5,5,0,
	0,0,0,0,3,3,3,3,5,5,5,0,0,0,0,
	0,0,3,3,3,5,5,0,0,0,0,0,0,0,3,
	3,5,0,0,0,0,0,0,0,0,3,0,0,0,0,
	0,0,0,0,0,6,0,0,0,0,0,0,0,0,2,
	6,6,0,0,0,0,0,0,0,2,2,6,6,6,0,
	0,0,0,0,0,2,2,2,6,6,6,6,0,0,0,
	0,0,2,2,2,2,1,1,1,1,1,1,1,1,1,
	1,
}

G.CELL_COUNT = 121
G.PER_ARM    = 10
G.SEAT_COUNT = 6

G.SEAT_NAMES = { "一", "二", "三", "四", "五", "六" }
G.ARM_LABEL  = { "南", "东南", "东北", "北", "西北", "西南" }

-- 六色棋子：朱砂 / 藤黄 / 苔绿 / 石青 / 靛蓝 / 紫檀
G.SEAT_COLORS = {
	{ 0.760, 0.235, 0.196 },
	{ 0.851, 0.647, 0.216 },
	{ 0.353, 0.573, 0.310 },
	{ 0.204, 0.502, 0.588 },
	{ 0.271, 0.365, 0.702 },
	{ 0.514, 0.298, 0.573 },
}

-- 邻接偏移（u, v）：横一格 = u±2；斜一格 = u±1, v±1
local NB = { { 2, 0 }, { -2, 0 }, { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } }

local function KeyOf(u, v) return u * 64 + v end

local cells, byKey, ids = {}, {}, {}
do
	local id = 0
	for v, len in ipairs(ROWLEN) do
		local odd = (v % 2 == 1)
		local i0 = odd and -math.floor((len - 1) / 2) or -math.floor(len / 2)
		for k = 0, len - 1 do
			local u = odd and (2 * (i0 + k)) or (2 * (i0 + k) + 1)
			id = id + 1
			cells[id] = {
				id   = id,
				u    = u,
				v    = v,
				x    = u / 2,        -- 横向（单位 = 一格间距）
				y    = 9 - v,        -- 纵向（单位 = 行高，向上为正）
				arm  = ARM[id] or 0,
			}
			byKey[KeyOf(u, v)] = id
			ids[#ids + 1] = id
		end
	end
end

G.cells = cells
G.neighbors, G.jumps = {}, {}
for _, c in ipairs(cells) do
	local nbs, jps = {}, {}
	for _, d in ipairs(NB) do
		local n = byKey[KeyOf(c.u + d[1], c.v + d[2])]
		if n then
			nbs[#nbs + 1] = n
			local land = byKey[KeyOf(c.u + d[1] * 2, c.v + d[2] * 2)]
			if land then jps[#jps + 1] = { mid = n, dest = land } end
		end
	end
	G.neighbors[c.id] = nbs
	G.jumps[c.id]     = jps
end

-- ------------------------------------------------------------
-- 2 · 规则
-- ------------------------------------------------------------
function G:IsNeighbor(a, b)
	for _, n in ipairs(self.neighbors[a] or {}) do
		if n == b then return true end
	end
	return false
end

--- 单步落点（相邻且为空）
function G:StepTargets(board, id)
	local out = {}
	for _, n in ipairs(self.neighbors[id] or {}) do
		if board[n] == 0 then out[#out + 1] = n end
	end
	return out
end

--- 跳一步的落点（中间隔一子，落点为空）
function G:JumpTargets(board, id)
	local out = {}
	for _, j in ipairs(self.jumps[id] or {}) do
		if board[j.mid] ~= 0 and board[j.dest] == 0 then out[#out + 1] = j.dest end
	end
	return out
end

--- a 跳到 b 的中间格；不成立返回 nil
function G:JumpMid(board, a, b)
	for _, j in ipairs(self.jumps[a] or {}) do
		if j.dest == b and board[j.mid] ~= 0 and board[b] == 0 then return j.mid end
	end
	return nil
end

--- 整条路径是否合法：单步（相邻空位）或若干次连跳
function G:ValidPath(board, path)
	if #path < 2 then return false end
	local from, first = path[1], path[2]
	if board[from] == 0 then return false end
	if #path == 2 and self:IsNeighbor(from, first) and board[first] == 0 then
		return true
	end
	local visited = { [from] = true }
	local cur = from
	for i = 2, #path do
		local to = path[i]
		if visited[to] then return false end
		if not self:JumpMid(board, cur, to) then return false end
		visited[to] = true
		cur = to
	end
	return true
end

function G:TargetArm(seat)
	return (seat + 2) % 6 + 1
end

--- 两人局时，两人是否坐成了对面的营（互为终点）
--- 只有两人在座才有意义：true 正面对抗 / false 各跑空营 / nil 不是两人局
function G:TwoSomeFacing()
	local a, b
	for i = 1, 6 do
		if self.seats[i] then
			if not a then a = i
			elseif not b then b = i
			else return nil end
		end
	end
	if not a or not b then return nil end
	return self:TargetArm(a) == b
end

function G:PiecesInArm(seat, arm)
	local board, n = self.board, 0
	for i = 1, 121 do
		if cells[i].arm == arm and board[i] == seat then n = n + 1 end
	end
	return n
end

function G:CheckWinner()
	for seat = 1, 6 do
		if self.seats[seat] and self:PiecesInArm(seat, self:TargetArm(seat)) >= self.PER_ARM then
			return seat
		end
	end
end

-- ------------------------------------------------------------
-- 3 · 状态
-- ------------------------------------------------------------
local WATCH_TTL   = 24   -- 观战者无心跳多久后清掉（秒）
local PING_EVERY  = 8    -- 心跳间隔
local HOST_EVERY  = 4    -- 房主状态广播间隔
local SEAT_STALE  = 50   -- 座位上的人多久没动静视为掉线（秒）
local TURN_SKIP   = 120  -- 轮到的人多久没动静就自动跳过（秒）

local function EmptyBoard()
	local b = {}
	for i = 1, 121 do b[i] = 0 end
	return b
end

function G:Init()
	self.seats    = {}
	self.watchers = {}
	self.board    = EmptyBoard()
	self.phase    = "wait"       -- wait / play / over
	self.turn     = nil
	self.turnAt   = nil          -- 本回合开始的时间（判超时用，不再看座位心跳）
	self.winner   = nil
	self.seq      = 0
	self.appliedH = 0
	self.appliedB = 0
	self.watching = false
	self.mute     = false
	self.acc      = 0
	self.sentCount   = 0
	self.recvCount   = 0
	self.firstSendAt = nil
	self.lastHostAt  = nil
	self.linkSuspect = false
	self.raceLost, self.raceLostAt = nil, nil
	self.lastError, self.lastErrorAt = nil, nil
	self:BuildDriver()
end

function G:BuildDriver()
	if self.driver then return end
	local f = CreateFrame("Frame")
	f:SetScript("OnUpdate", function(_, elapsed) self:Tick(elapsed) end)
	self.driver = f
end

function G:Changed()
	local ev = MZ.Event or MZ.Modules.Event
	if ev then ev:Send("MZ_CHECKERS_CHANGED") end
end

function G:Me()
	return (Net and Net:Me()) or (UnitName("player") or "player")
end

function G:SeatOf(name)
	if not name then return nil end
	for i = 1, 6 do
		local s = self.seats[i]
		if s and s.name == name then return i end
	end
end

function G:MySeat()
	return self:SeatOf(self:Me())
end

function G:SeatedCount()
	local n = 0
	for i = 1, 6 do
		if self.seats[i] then n = n + 1 end
	end
	return n
end

function G:ReadyCount()
	local n = 0
	for i = 1, 6 do
		if self.seats[i] and self.seats[i].ready then n = n + 1 end
	end
	return n
end

--- 房主 = 座位号最小的在座玩家；无人落座时人人可当房主
function G:IsHost()
	if self.mute then return true end
	local first
	for i = 1, 6 do
		if self.seats[i] and self.seats[i].name then first = i; break end
	end
	if not first then return true end
	return self.seats[first].name == self:Me()
end

function G:FirstTurn()
	for i = 1, 6 do
		if self.seats[i] then return i end
	end
	return nil
end

--- 下一个有人的座位（严格逐个座位往后找，不能跳号）
function G:NextTurn(from)
	for k = 1, 6 do
		local seat = (from + k - 1) % 6 + 1
		if self.seats[seat] then return seat end
	end
	return from
end

--- 观战名单：还活着、且没有座位的人
function G:Spectators()
	local now, list = GetTime(), {}
	for name, seen in pairs(self.watchers) do
		if now - seen <= WATCH_TTL and not self:SeatOf(name) then
			list[#list + 1] = name
		end
	end
	table.sort(list)
	return list
end

function G:SpectatorCount()
	return #self:Spectators()
end

-- ------------------------------------------------------------
-- 4 · 发/收
-- ------------------------------------------------------------
function G:Send(text)
	if self.mute then return false end
	if not Net then return false end
	local ok = Net:Send(text)
	if ok then
		self.sentCount  = (self.sentCount or 0) + 1
		self.firstSendAt = self.firstSendAt or GetTime()
	end
	return ok
end

--- 包发出去了却一条回音都没收到：八成是两台机器落在不同频道
function G:LinkSuspect()
	if self.mute then return false end
	if (self.recvCount or 0) > 0 then return false end
	if (self.sentCount or 0) < 1 then return false end
	return GetTime() - (self.firstSendAt or GetTime()) > 12
end

function G:EncodeBoard()
	local t = {}
	for i = 1, 121 do
		t[i] = (self.board[i] == 0) and "." or tostring(self.board[i])
	end
	return table.concat(t)
end

function G:DecodeBoard(str)
	local b = EmptyBoard()
	for i = 1, 121 do
		local ch = str:sub(i, i)
		local n = tonumber(ch)
		b[i] = n or 0
	end
	self.board = b
end

--- 房主把当前全量状态打出去（拆两包，避免顶到单包上限）
function G:Broadcast()
	-- 序号必须越过自己见过的最大号：H / B 分开计数，漏收过一包时
	-- 只比 appliedH 会导致新序号不比别人手里的 appliedB 大，棋盘被当成旧包丢掉
	self.seq = math.max(self.seq or 0, self.appliedH or 0, self.appliedB or 0) + 1

	local names, mask = {}, {}
	for i = 1, 6 do
		local s = self.seats[i]
		names[i] = (s and s.name) or ""
		mask[i]  = (s and s.ready) and "1" or "0"
	end

	self:Send(string.format("H|%d|%s|%d|%d|%s|%s",
		self.seq, self.phase, self.turn or 0, self.winner or 0,
		table.concat(mask), table.concat(names, ",")))
	self:Send(string.format("B|%d|%s", self.seq, self:EncodeBoard()))

	self.appliedH, self.appliedB = self.seq, self.seq
	self.lastBroadcast = GetTime()
end

function G:MarkDirty()
	if self:IsHost() then self:Broadcast() end
	self:Changed()
end

function G:OnMessage(text, sender)
	self.recvCount  = (self.recvCount or 0) + 1
	self.lastRecvAt = GetTime()
	local p = { strsplit("|", text) }
	local tag = p[1]
	if tag == "W" then
		if p[2] == "0" then
			self.watchers[sender] = nil
		else
			self.watchers[sender] = GetTime()
		end
		self:TouchSeat(sender)
		self:Changed()
	elseif tag == "P" then
		self:TouchSeat(sender)
		if self.watchers[sender] then self.watchers[sender] = GetTime() end
	elseif tag == "C" then
		self:OnClaim(p, sender)
	elseif tag == "Q" then
		if self:IsHost() then self:OnRequest(p, sender) end
	elseif tag == "H" then
		self:OnHostState(p, sender)
	elseif tag == "B" then
		self:OnHostBoard(p)
	elseif tag == "E" then
		-- 房主拒绝了我的走子：把原因带回提示行
		if p[2] == self:Me() then
			self.lastError, self.lastErrorAt = p[3] or "这一手没走成", GetTime()
			self:Changed()
		end
	elseif tag == "R" then
		if self:IsHost() then self:Broadcast() end
	end
end

function G:TouchSeat(name)
	local seat = self:SeatOf(name)
	if seat then self.seats[seat].seen = GetTime() end
end

--- 座位 / 准备 / 离座：抢座式声明，各端就地应用，房主快照兜底纠偏
function G:OnClaim(p, sender)
	local what = p[2]
	if what == "SIT" then
		local idx = tonumber(p[3])
		if not idx or idx < 1 or idx > 6 then return end
		if self.phase ~= "wait" then return end
		if self.seats[idx] then return end
		if self:SeatOf(sender) then return end
		self.seats[idx] = { name = sender, ready = false, seen = GetTime() }
		self:Changed()
	elseif what == "UP" then
		if self.phase ~= "wait" then return end
		local seat = self:SeatOf(sender)
		if seat then
			self.seats[seat] = nil
			self:Changed()
		end
	elseif what == "RDY" then
		local seat = self:SeatOf(sender)
		if seat then
			self.seats[seat].ready = (p[3] == "1")
			self.seats[seat].seen  = GetTime()
			self:Changed()
		end
	end
end

--- 房主收到的请求：走子 / 重开
function G:OnRequest(p, sender)
	local what = p[2]
	if what == "MV" then
		local path = {}
		for _, s in ipairs({ strsplit(";", p[3] or "") }) do
			local n = tonumber(s)
			if n then path[#path + 1] = n end
		end
		local ok, err = self:ApplyMove(sender, path)
		if not ok and err then
			Log:Debug("拒绝 " .. sender .. " 走子：" .. err)
			-- 请求方本地的棋盘不会变，没有这句话就是「点了没反应」的黑盒
			self:Send("E|" .. sender .. "|" .. err)
		end
	elseif what == "NEW" then
		self:Restart()
	end
end

function G:OnHostState(p, sender)
	local seq = tonumber(p[2]) or 0
	self.lastHostAt = GetTime()   -- 只要还收得到房主的快照，就说明链路是通的
	if seq < (self.appliedH or 0) then return end
	if seq == (self.appliedH or 0) then
		-- 同序号却来自另一个人：两人几乎同时抢同一座位时，双方都以为自己是房主，
		-- 各自广播的序号会一直追平，谁都不肯收对方的包 —— 桌面永久分裂。
		-- 这里用「名字小的那份算数」做唯一裁决，两端算出同一结果，必然收敛。
		if not sender or sender >= self:Me() then return end
	end
	self.appliedH = seq

	local mineBefore = self:MySeat()

	local phase  = p[3]
	local turn   = tonumber(p[4]) or 0
	local winner = tonumber(p[5]) or 0
	local mask   = p[6] or ""
	local names  = { strsplit(",", p[7] or "") }

	self.phase  = (phase == "play" or phase == "over") and phase or "wait"
	local oldTurn = self.turn
	self.turn   = (turn > 0) and turn or nil
	self.winner = (winner > 0) and winner or nil
	-- 轮次变了就重置超时计时（自己万一被选成新房主，计时才有意义）
	if self.turn ~= oldTurn then self.turnAt = GetTime() end

	for i = 1, 6 do
		local nm = names[i]
		if nm and nm ~= "" then
			local old = self.seats[i]
			self.seats[i] = {
				name  = nm,
				ready = (mask:sub(i, i) == "1"),
				seen  = (old and old.name == nm and old.seen) or GetTime(),
			}
		else
			self.seats[i] = nil
		end
	end

	-- 自己的座位没了（抢座输给别人 / 被房主判掉线）：让提示行说一句
	if mineBefore and not self:MySeat() then
		self.raceLost, self.raceLostAt = mineBefore, GetTime()
	end
	self:Changed()
end

function G:OnHostBoard(p)
	local seq = tonumber(p[2]) or 0
	self.lastHostAt = GetTime()
	if seq <= (self.appliedB or 0) then return end
	self.appliedB = seq
	self:DecodeBoard(p[3] or "")
	self:Changed()
end

-- ------------------------------------------------------------
-- 5 · 动作（本地立即生效，再广播 / 请求）
-- ------------------------------------------------------------
function G:Sit(index)
	if self.phase ~= "wait" then return false, "对局已开始，等下一局" end
	if self:MySeat() then return false, "你已经在座上了" end
	if index < 1 or index > 6 then return false, "座位号无效" end
	if self.seats[index] then return false, "该座位已被占" end
	self.seats[index] = { name = self:Me(), ready = false, seen = GetTime() }
	self:Send("C|SIT|" .. index)
	self:MarkDirty()
	return true
end

function G:SitFirstFree()
	for i = 1, 6 do
		if not self.seats[i] then return self:Sit(i) end
	end
	return false, "六个座位都满了"
end

function G:Leave()
	local seat = self:MySeat()
	if not seat then return false, "你还没入座" end
	if self.phase == "play" then return false, "对局中不能离座" end
	self.seats[seat] = nil
	self:Send("C|UP")
	self:MarkDirty()
	return true
end

function G:ToggleReady()
	local seat = self:MySeat()
	if not seat then return false, "先占一个座位" end
	if self.phase ~= "wait" then return false, "对局已开始" end
	local v = not self.seats[seat].ready
	self.seats[seat].ready = v
	self:Send("C|RDY|" .. (v and "1" or "0"))
	self:MarkDirty()
	return true
end

function G:CanStart()
	if self.phase ~= "wait" then return false end
	local n = 0
	for i = 1, 6 do
		local s = self.seats[i]
		if s then
			if not s.ready then return false end
			n = n + 1
		end
	end
	return n >= 2
end

--- 开局：座位 i 的棋子摆在营 i，目标是对面营
function G:StartGame()
	if self.phase ~= "wait" then return false end
	local board = EmptyBoard()
	for seat = 1, 6 do
		if self.seats[seat] then
			for i = 1, 121 do
				if cells[i].arm == seat then board[i] = seat end
			end
		end
	end
	self.board  = board
	self.phase  = "play"
	self.winner = nil
	self.turn   = self:FirstTurn()
	self.turnAt = GetTime()
	self:MarkDirty()
	return true
end

--- 重开：留着座位，回到「等人就绪」；演练模式下直接再来一局
function G:Restart()
	if not self:IsHost() then
		if not self:Send("Q|NEW") then
			return false, "发不出去：和房主不在同一队伍或公会"
		end
		return true
	end
	for i = 1, 6 do
		if self.seats[i] then self.seats[i].ready = false end
	end
	self.board  = EmptyBoard()
	self.phase  = "wait"
	self.turn   = nil
	self.turnAt = nil
	self.winner = nil

	if self.mute then
		for i = 1, 6 do
			if self.seats[i] then self.seats[i].ready = true end
		end
		self:StartGame()
	else
		self:Broadcast()
		self:Changed()
	end
	return true
end

--- 走子：房主自己下就地判，别人下就发请求
function G:SubmitMove(path)
	if not path or #path < 2 then return false, "路径无效" end
	if self:IsHost() then
		local ok, err = self:ApplyMove(self:Me(), path)
		if not ok and err then Log:Warn(err) end
		return ok, err
	end
	if not self:Send("Q|MV|" .. table.concat(path, ";")) then
		return false, "发不出去：和主机不在同一队伍或公会"
	end
	return true
end

--- 房主端校验并落子
function G:ApplyMove(name, path)
	if self.phase ~= "play" then return false, "还没开局" end
	local seat = self:SeatOf(name)
	if not seat then return false, "未入座" end
	if seat ~= self.turn then return false, "还没轮到你" end
	if #path < 2 then return false, "路径无效" end

	local from, dest = path[1], path[#path]
	if self.board[from] ~= seat then return false, "这不是你的棋子" end
	if not self:ValidPath(self.board, path) then return false, "不符合走子规则" end

	self.board[from] = 0
	self.board[dest] = seat

	local win = self:CheckWinner()
	if win then
		self.phase  = "over"
		self.winner = win
	else
		self.turn   = self:NextTurn(seat)
	end
	self.turnAt = GetTime()
	self:MarkDirty()
	return true
end

-- ------------------------------------------------------------
-- 6 · 观战登记（插件面板开 = 观战，关 = 撤销）
-- ------------------------------------------------------------
function G:SetWatching(on)
	on = on and true or false
	if self.watching == on then return end
	self.watching = on
	if on then
		self.watchers[self:Me()] = GetTime()
		self:Send("W|1")
	else
		self.watchers[self:Me()] = nil
		self:Send("W|0")
	end
	self:Changed()
end

-- ------------------------------------------------------------
-- 7 · 心跳 / 房主轮询
-- ------------------------------------------------------------
local hooked = false

local function HookPanel()
	if hooked then return end
	local f = MZ.frame
	if not f then return end
	hooked = true
	f:HookScript("OnShow", function() G:SetWatching(true) end)
	f:HookScript("OnHide", function() G:SetWatching(false) end)
	if f:IsShown() then G:SetWatching(true) end
end

function G:Tick(elapsed)
	self.acc = (self.acc or 0) + (elapsed or 0)
	if self.acc < 1 then return end
	self.acc = 0

	if not hooked then HookPanel() end

	local now = GetTime()

	-- 自己的座位永远算「活着」（自己的包不会回到自己这里）
	local mySeat = self:MySeat()
	if mySeat and self.seats[mySeat] then self.seats[mySeat].seen = now end

	-- 面板开着就持续登记；坐着的人即使关面板也报活，免得被当成掉线
	if self.watching then
		self.watchers[self:Me()] = now
		if now - (self.lastWatch or 0) >= PING_EVERY then
			self.lastWatch = now
			self:Send("W|1")
		end
	elseif mySeat then
		if now - (self.lastPing or 0) >= PING_EVERY then
			self.lastPing = now
			self:Send("P")
		end
	end

	-- 清理沉默的观战者
	local dirty = false
	for name, seen in pairs(self.watchers) do
		if name ~= self:Me() and now - seen > WATCH_TTL then
			self.watchers[name] = nil
			dirty = true
		end
	end
	if dirty then self:Changed() end

	-- 发出去却没回音，让页面能把「连不上」显示出来
	local suspect = self:LinkSuspect()
	if suspect ~= self.linkSuspect then
		self.linkSuspect = suspect
		self:Changed()
	end

	if self:IsHost() then
		-- 掉线的人腾出座位（只在等人阶段）
		if self.phase == "wait" then
			for i = 1, 6 do
				local s = self.seats[i]
				if s and now - (s.seen or now) > SEAT_STALE then
					self.seats[i] = nil
					self:Changed()
				end
			end
			-- 人齐且全就绪 → 房主自动开局
			if self:CanStart() then self:StartGame() end
		elseif self.phase == "play" and self.turn then
			-- 这一回合卡太久（掉线 / 挂机）就跳过，免得全桌干等。
			-- 用 turnAt 而不是座位心跳：房主自己的座位每帧都被刷新，
			-- 用心跳判的话房主挂机永远不会被跳过，全桌反而卡死。
			if now - (self.turnAt or now) > TURN_SKIP then
				self.turn   = self:NextTurn(self.turn)
				self.turnAt = now
				self:Broadcast()
			end
		end
		if now - (self.lastBroadcast or 0) >= HOST_EVERY then self:Broadcast() end
	end
end

-- ------------------------------------------------------------
-- 8 · 本机演练（没有队友时也能看棋盘；不外发任何包）
-- ------------------------------------------------------------
function G:Demo()
	if self.mute then
		-- 再点一次 = 退出演练。mute 必须清掉，否则之后一直发不出包、
		-- IsHost 还会恒为 true，两个人真同桌时这台机器就成了哑巴。
		self:Init()
		if MZ.frame and MZ.frame:IsShown() then self:SetWatching(true) end
		self:Send("R")
		self:Changed()
		return false
	end
	self.mute = true
	for i = 1, 6 do self.seats[i] = nil end
	for i = 1, 6 do
		self.seats[i] = {
			name  = (i == 1) and self:Me() or ("棋友" .. G.SEAT_NAMES[i]),
			ready = true,
			seen  = GetTime(),
		}
	end
	self.phase  = "wait"
	self.board  = EmptyBoard()
	self:StartGame()
	self:Changed()
end

G:Init()

-- 收到别人的包 → 交给状态机
if Net then
	Net:On(function(text, sender) G:OnMessage(text, sender) end)
end
