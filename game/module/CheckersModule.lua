-- ============================================================
-- CheckersModule · 六角跳棋
--   棋盘几何 / 走子规则 / 座位·准备·观战 / 房主权威同步
--   本文件不写一行绘制代码，UI 见 game/view/views/CheckersView.lua
-- ============================================================
local ADDON_NAME, MZ = ...

local App = MZ.App
local Net = App._modules.Net
local Log = App._modules.Log

local CheckersModule = App.newclz("CheckersModule", App.AbstractModule)
-- 几何常量挂在类上。G 是类表别名；座位和棋盘在实例上。
local G = CheckersModule

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
function CheckersModule:IsNeighbor(a, b)
	for _, n in ipairs(self.neighbors[a] or {}) do
		if n == b then return true end
	end
	return false
end

--- 单步落点（相邻且为空）
function CheckersModule:StepTargets(board, id)
	local out = {}
	for _, n in ipairs(self.neighbors[id] or {}) do
		if board[n] == 0 then out[#out + 1] = n end
	end
	return out
end

--- 跳一步的落点（中间隔一子，落点为空）
function CheckersModule:JumpTargets(board, id)
	local out = {}
	for _, j in ipairs(self.jumps[id] or {}) do
		if board[j.mid] ~= 0 and board[j.dest] == 0 then out[#out + 1] = j.dest end
	end
	return out
end

--- a 跳到 b 的中间格；不成立返回 nil
function CheckersModule:JumpMid(board, a, b)
	for _, j in ipairs(self.jumps[a] or {}) do
		if j.dest == b and board[j.mid] ~= 0 and board[b] == 0 then return j.mid end
	end
	return nil
end

--- 整条路径是否合法：单步（相邻空位）或若干次连跳
function CheckersModule:ValidPath(board, path)
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

function CheckersModule:TargetArm(seat)
	return (seat + 2) % 6 + 1
end

--- 两人局时，两人是否坐成了对面的营（互为终点）
--- 只有两人在座才有意义：true 正面对抗 / false 各跑空营 / nil 不是两人局
function CheckersModule:TwoSomeFacing()
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

function CheckersModule:PiecesInArm(seat, arm)
	local board, n = self.board, 0
	for i = 1, 121 do
		if cells[i].arm == arm and board[i] == seat then n = n + 1 end
	end
	return n
end

function CheckersModule:CheckWinner()
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

function CheckersModule:init()
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
	self.hostSilent  = false
	self.raceLost, self.raceLostAt = nil, nil
	self.lastError, self.lastErrorAt = nil, nil
	-- 补报 / 重同步的计时器
	self.wantSeat, self.reclaimN, self.reclaimAt = nil, 0, nil
	self.lastClaim, self.lastSync = 0, 0
	self.myReady = false
	self:BuildDriver()
end

function CheckersModule:BuildDriver()
	if self._ticking then return end
	self._ticking = true
	MZ.App:addManager(self)
end

function CheckersModule:Changed()
	local app = MZ.App
	local bus = app.eventManager or app.code or app.events
	local name = (app.Ev and app.Ev.CHECKERS_CHANGED) or "MZ_CHECKERS_CHANGED"
	if bus then bus:emit(name) end
end

function CheckersModule:Me()
	return (Net and Net:Me()) or (UnitName("player") or "player")
end

function CheckersModule:SeatOf(name)
	if not name then return nil end
	for i = 1, 6 do
		local s = self.seats[i]
		if s and s.name == name then return i end
	end
end

function CheckersModule:MySeat()
	return self:SeatOf(self:Me())
end

function CheckersModule:SeatedCount()
	local n = 0
	for i = 1, 6 do
		if self.seats[i] then n = n + 1 end
	end
	return n
end

function CheckersModule:ReadyCount()
	local n = 0
	for i = 1, 6 do
		if self.seats[i] and self.seats[i].ready then n = n + 1 end
	end
	return n
end

--- 房主 = 座位号最小的在座玩家；无人落座时人人可当房主
function CheckersModule:IsHost()
	if self.mute then return true end
	local first
	for i = 1, 6 do
		if self.seats[i] and self.seats[i].name then first = i; break end
	end
	if not first then return true end
	return self.seats[first].name == self:Me()
end

function CheckersModule:FirstTurn()
	for i = 1, 6 do
		if self.seats[i] then return i end
	end
	return nil
end

--- 下一个有人的座位（严格逐个座位往后找，不能跳号）
function CheckersModule:NextTurn(from)
	for k = 1, 6 do
		local seat = (from + k - 1) % 6 + 1
		if self.seats[seat] then return seat end
	end
	return from
end

--- 观战名单：还活着、且没有座位的人
function CheckersModule:Spectators()
	local now, list = GetTime(), {}
	for name, seen in pairs(self.watchers) do
		if now - seen <= WATCH_TTL and not self:SeatOf(name) then
			list[#list + 1] = name
		end
	end
	table.sort(list)
	return list
end

function CheckersModule:SpectatorCount()
	return #self:Spectators()
end

-- ------------------------------------------------------------
-- 4 · 发/收
-- ------------------------------------------------------------
function CheckersModule:Send(text)
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
function CheckersModule:LinkSuspect()
	if self.mute then return false end
	if (self.recvCount or 0) > 0 then return false end
	if (self.sentCount or 0) < 1 then return false end
	return GetTime() - (self.firstSendAt or GetTime()) > 12
end

function CheckersModule:EncodeBoard()
	local t = {}
	for i = 1, 121 do
		t[i] = (self.board[i] == 0) and "." or tostring(self.board[i])
	end
	return table.concat(t)
end

function CheckersModule:DecodeBoard(str)
	local b = EmptyBoard()
	for i = 1, 121 do
		local ch = str:sub(i, i)
		local n = tonumber(ch)
		b[i] = n or 0
	end
	self.board = b
end

--- 房主把当前全量状态打出去（拆两包，避免顶到单包上限）
function CheckersModule:Broadcast()
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

function CheckersModule:MarkDirty()
	if self:IsHost() then self:Broadcast() end
	self:Changed()
end

function CheckersModule:OnMessage(text, sender)
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
		if self:IsHost() then
			-- 请求方带着它手里的序号（R|<appliedB>）。它可能卡在比我们更大的号上
			-- （它自己当房主时广播过），把号拖过来，下一包的 seq 才越得过去。
			local want = tonumber(p[2]) or 0
			if want > (self.appliedH or 0) then self.appliedH = want end
			if want > (self.appliedB or 0) then self.appliedB = want end
			self:Broadcast()
		end
	end
end

function CheckersModule:TouchSeat(name)
	local seat = self:SeatOf(name)
	if seat then self.seats[seat].seen = GetTime() end
end

--- 座位 / 准备 / 离座：抢座式声明，各端就地应用，房主快照兜底纠偏
function CheckersModule:OnClaim(p, sender)
	local what = p[2]
	if what == "SIT" then
		local idx = tonumber(p[3])
		if not idx or idx < 1 or idx > 6 then return end
		if self.phase ~= "wait" then return end
		local mine = self:SeatOf(sender)
		if mine then
			-- 同一个人重复报同一个座位：这是定时补报（那条声明丢过一次），
			-- 顺手把准备态一起同步过来，别让房主那边永远停在「未准备」。
			if mine == idx and self.seats[idx] then
				self.seats[idx].seen  = GetTime()
				self.seats[idx].ready = (p[4] == "1")
				self:Changed()
			end
			return
		end
		if self.seats[idx] then return end
		self.seats[idx] = { name = sender, ready = (p[4] == "1"), seen = GetTime() }
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
function CheckersModule:OnRequest(p, sender)
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

function CheckersModule:OnHostState(p, sender)
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
	local wasPlaying = (self.phase == "play" or self.phase == "over")

	local phase  = p[3]
	local turn   = tonumber(p[4]) or 0
	local winner = tonumber(p[5]) or 0
	local mask   = p[6] or ""
	local names  = { strsplit(",", p[7] or "") }

	self.phase  = (phase == "play" or phase == "over") and phase or "wait"
	-- 房主把桌子收回大厅（新一局）：我自己那份「已准备」也要撤掉，
	-- 否则下一次心跳补报会把我立刻又抬成已准备，刚重开就自动开局
	if wasPlaying and self.phase == "wait" then self.myReady = false end
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

	-- 自己的座位没了：被别人坐走才提示换座；
	-- 只是自己那条声明丢了（快照里该座是空的），交给 Tick 自动补报，不惊动玩家
	if mineBefore and not self:MySeat() and self.seats[mineBefore] then
		self.raceLost, self.raceLostAt = mineBefore, GetTime()
	end
	self:Changed()
end

--- 棋盘上一个子都没有（刚开局还没收到棋盘的典型状态）
function CheckersModule:BoardEmpty()
	for i = 1, 121 do
		if (self.board[i] or 0) > 0 then return false end
	end
	return true
end

function CheckersModule:OnHostBoard(p)
	local seq = tonumber(p[2]) or 0
	self.lastHostAt = GetTime()
	if seq <= (self.appliedB or 0) then
		-- 序号没越过我们手里的，正常是该丢的旧包。
		-- 但「对局中却一个子都没有」只可能是棋盘从来没收到过（对方曾经自己广播过，
		-- 序号比我们大，于是它的新包一直被挡）。这时宁可按旧的也收下，先把棋盘点亮。
		if not (self.phase == "play" and self:BoardEmpty()) then return end
	end
	self.appliedB = seq
	self:DecodeBoard(p[3] or "")
	self:Changed()
end

-- ------------------------------------------------------------
-- 5 · 动作（本地立即生效，再广播 / 请求）
-- ------------------------------------------------------------
function CheckersModule:Sit(index)
	if self.phase ~= "wait" then return false, "对局已开始，等下一局" end
	if self:MySeat() then return false, "你已经在座上了" end
	if index < 1 or index > 6 then return false, "座位号无效" end
	if self.seats[index] then return false, "该座位已被占" end
	self.seats[index] = { name = self:Me(), ready = false, seen = GetTime() }
	self.wantSeat, self.reclaimN = index, 0   -- 声明丢了要能自己补回来
	self.myReady = false
	self:Send("C|SIT|" .. index)
	self:MarkDirty()
	return true
end

function CheckersModule:SitFirstFree()
	for i = 1, 6 do
		if not self.seats[i] then return self:Sit(i) end
	end
	return false, "六个座位都满了"
end

function CheckersModule:Leave()
	local seat = self:MySeat()
	if not seat then return false, "你还没入座" end
	if self.phase == "play" then return false, "对局中不能离座" end
	self.seats[seat] = nil
	self.wantSeat, self.reclaimN = nil, 0
	self.myReady = false
	self:Send("C|UP")
	self:MarkDirty()
	return true
end

function CheckersModule:ToggleReady()
	local seat = self:MySeat()
	if not seat then return false, "先占一个座位" end
	if self.phase ~= "wait" then return false, "对局已开始" end
	local v = not self.seats[seat].ready
	self.seats[seat].ready = v
	self.myReady = v            -- 记住自己的意图：快照会把本地 ready 覆盖掉
	self:Send("C|RDY|" .. (v and "1" or "0"))
	self:MarkDirty()
	return true
end

function CheckersModule:CanStart()
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
function CheckersModule:StartGame()
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
function CheckersModule:Restart()
	if not self:IsHost() then
		if not self:Send("Q|NEW") then
			return false, "发不出去：和房主不在同一队伍或公会"
		end
		return true
	end
	for i = 1, 6 do
		if self.seats[i] then self.seats[i].ready = false end
	end
	self.myReady = false          -- 回到大厅就撤销我自己的「已准备」，否则会被自动开局
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
function CheckersModule:SubmitMove(path)
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
function CheckersModule:ApplyMove(name, path)
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
function CheckersModule:SetWatching(on)
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

local function HookPanel(game)
	if hooked then return end
	local f = MZ.App.UI and MZ.App.UI.frame
	if not f then return end
	hooked = true
	MZ.App.Hook:Attach(f, "OnShow", function() game:SetWatching(true) end)
	MZ.App.Hook:Attach(f, "OnHide", function() game:SetWatching(false) end)
	if f:IsShown() then game:SetWatching(true) end
end

function CheckersModule:update(elapsed)
	self.acc = (self.acc or 0) + (elapsed or 0)
	if self.acc < 1 then return end
	self.acc = 0

	if not hooked then HookPanel(self) end

	local now = GetTime()

	-- 自己那条「我坐 N 号」的声明可能丢包，房主快照一盖座位就没了。
	-- 悄悄补报几次，别让人只看到一句「座位已归他人」还得自己再点一次。
	if self.wantSeat and not self:MySeat() and self.phase == "wait"
		and (self.reclaimN or 0) < 3
		and now - (self.reclaimAt or 0) >= 3 then
		self.reclaimAt = now
		self.reclaimN = (self.reclaimN or 0) + 1
		local ok, err = self:Sit(self.wantSeat)
		if not ok and err == "该座位已被占" then
			self.wantSeat = nil        -- 真被别人坐走了，别再试
		end
	end

	-- 自己的座位永远算「活着」（自己的包不会回到自己这里）
	local mySeat = self:MySeat()
	if mySeat then self.reclaimN = 0 end
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

	-- 座位和准备都是「说一次就算」的：那一条包丢了，房主那边就永远看不到我
	-- 坐下了 / 已就绪，全桌卡在等人阶段。跟着心跳幂等补报一次。
	if mySeat and self.phase == "wait" and now - (self.lastClaim or 0) >= PING_EVERY then
		self.lastClaim = now
		-- 报的是自己的「意图」而不是快照里那个值：房主没见过我准备就会一直发
		-- 「未准备」，我照着它回话就变成了互相把对方拉回未准备，全桌永远开不了局。
		local s = self.seats[mySeat]
		if s then s.ready = self.myReady end
		self:Send("C|SIT|" .. mySeat .. "|" .. (self.myReady and "1" or "0"))
	end

	-- 「我这边已经该开局了，但什么都没收到」或者「对局中却一个子都没有」：
	-- 主动要一次全量快照，并把手里的大序号报过去，让房主下一包能越过我们
	-- （否则它发多少我们丢多少，棋盘永远不亮）。
	if not self:IsHost() and now - (self.lastSync or 0) >= 2 then
		local needSync = (self.phase == "play" and self:BoardEmpty())
			or (self.phase == "wait" and self:CanStart())
		if needSync then
			self.lastSync = now
			self:Send("R|" .. math.max(self.appliedH or 0, self.appliedB or 0))
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

	-- 对局中房主长时间没有快照：局面已经不会再动了，让页面说一句，
	-- 别让人对着不动的棋盘干等（房主掉线时只有重启插件才能恢复）
	local silent = (not self:IsHost()) and self.phase == "play"
		and self.lastHostAt ~= nil and (now - self.lastHostAt > 20)
	if silent ~= self.hostSilent then
		self.hostSilent = silent
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
function CheckersModule:Demo()
	if self.mute then
		-- 再点一次 = 退出演练。mute 必须清掉，否则之后一直发不出包、
		-- IsHost 还会恒为 true，两个人真同桌时这台机器就成了哑巴。
		self:init()
		local f = MZ.App.UI and MZ.App.UI.frame
		if f and f:IsShown() then self:SetWatching(true) end
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

local inst = CheckersModule:new("Checkers")
App._modules.Checkers = inst
inst:enterModule()

-- 收到别人的包，交给这一局。
if Net then
	Net:On(function(text, sender) inst:OnMessage(text, sender) end)
end
