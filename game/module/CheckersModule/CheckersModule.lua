-- ============================================================
-- CheckersModule · 六角跳棋
--   棋盘几何 / 走子规则 / 座位·准备·观战 / 房主权威同步
--   本文件不写一行绘制代码，UI 见 game/view/views/CheckersView.lua
--
-- 同步 · App.SyncScheme.HostSnapshot（房主权威 + 全量快照）
--   频道：一个队伍频道（有团队用 RAID，否则 PARTY，都没有才 INSTANCE_CHAT），
--         在公会时再追加 GUILD。前缀 MZCHK。广播，不是点对点。
--   封包：明文 H/B/C/Q/W/P/E/R，不改成 ~S。H 座位与阶段，B 棋盘。
--         房主约每 4 秒全量广播。走子 Q 由房主裁决后再广播，只有 Q| 去重。
--         座位声明 C 各端先落地，快照再纠偏。心跳 W/P 与补报入座 8 秒。
--         非房主约每 2 秒用 R 主动要快照。旧序号丢掉，状态包重复无害。
--   时机：点击（入座、准备、走子、开局）才发包。逻辑先攒到 1 秒。
--         帧回调只抽 NetManager 队列，不按帧同步。收包不进 EventManager。
--   本机：sync 把棋盘交给界面，不发插件消息，也不再发全局事件。
--   不用锁步，也不用对等式 CRDT。
-- ============================================================
local ADDON_NAME, MZ = ...

local App = MZ.App
local Net = App._modules.Net
local Log = App._modules.Log

local CheckersModule = App.newclz("CheckersModule", App.AbstractModule)
-- 几何在 CheckersBoard。这里挂到类上，界面仍从模块读。
local G = CheckersModule
local Board = App.CheckersBoard

G.ROWLEN = Board.ROWLEN
G.ARM = Board.ARM
G.CELL_COUNT = Board.CELL_COUNT
G.PER_ARM = Board.PER_ARM
G.SEAT_COUNT = Board.SEAT_COUNT
G.SEAT_NAMES = Board.SEAT_NAMES
G.ARM_LABEL = Board.ARM_LABEL
G.SEAT_COLORS = Board.SEAT_COLORS
G.cells = Board.cells
G.byKey = Board.byKey
G.ids = Board.ids
G.neighbors = Board.neighbors
G.jumps = Board.jumps

function CheckersModule:KeyOf(u, v)
	return Board.KeyOf(u, v)
end

function CheckersModule:IsNeighbor(a, b)
	return Board.IsNeighbor(a, b)
end

function CheckersModule:StepTargets(board, id)
	return Board.StepTargets(board, id)
end

function CheckersModule:JumpTargets(board, id)
	return Board.JumpTargets(board, id)
end

function CheckersModule:JumpMid(board, a, b)
	return Board.JumpMid(board, a, b)
end

function CheckersModule:ValidPath(board, path)
	return Board.ValidPath(board, path)
end

function CheckersModule:TargetArm(seat)
	return Board.TargetArm(seat)
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
		if G.cells[i].arm == arm and board[i] == seat then n = n + 1 end
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
-- 同步：本机状态。Changed 只刷新界面，不发插件消息。
-- ------------------------------------------------------------
G.WATCH_TTL  = 24   -- 观战者无心跳多久后清掉（秒）
G.PING_EVERY = 8    -- 心跳间隔
G.HOST_EVERY = 4    -- 房主状态广播间隔
G.SEAT_STALE = 50   -- 座位上的人多久没动静视为掉线（秒）
G.TURN_SKIP  = 120  -- 轮到的人多久没动静就自动跳过（秒）

function CheckersModule:EmptyBoard()
	return App.CheckersBoardVo:new()
end

function CheckersModule:Seat(name, ready, seen)
	return App.CheckersSeatVo:new(name, ready, seen)
end

function CheckersModule:init()
	self.seats    = {}
	self.watchers = {}
	self.board    = self:EmptyBoard()
	self.model    = self.board
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
	self._seen = {}
	self._lastSweep = 0
	self:BuildDriver()
end

function CheckersModule:BuildDriver()
	if self._ticking then return end
	self._ticking = true
	MZ.App:addManager(self)
end

-- 同步：本机。sync 交棋盘，不发插件消息，也不发全局事件。
function CheckersModule:Changed()
	self.model = self.board
	self:sync("changed")
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
		if now - seen <= G.WATCH_TTL and not self:SeatOf(name) then
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
-- 同步：明文 H/B/C/Q/W/P/E/R。收包来自 CHAT_MSG_ADDON，不进 EventManager。
-- ------------------------------------------------------------
-- 同步：明文进 NetManager 队列。正文不以 ~ 开头。mute 时不发。
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

-- 同步：B 包里的棋盘正文。121 格，空位是点，有子是座位号。
function CheckersModule:EncodeBoard()
	local t = {}
	for i = 1, 121 do
		t[i] = (self.board[i] == 0) and "." or tostring(self.board[i])
	end
	return table.concat(t)
end

-- 同步：解开 B 包，整盘替换本机棋盘。
function CheckersModule:DecodeBoard(str)
	local b = self:EmptyBoard()
	for i = 1, 121 do
		local ch = str:sub(i, i)
		local n = tonumber(ch)
		b[i] = n or 0
	end
	self.board = b
end

--- 房主把当前全量状态打出去（拆两包，避免顶到单包上限）
--- 同步：房主全量快照。H 座位与阶段，B 棋盘，同一序号。状态一变就发，心跳约每 4 秒再发。
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

-- 同步：房主广播 H+B。各端都做本机 Changed。
function CheckersModule:MarkDirty()
	if self:IsHost() then self:Broadcast() end
	self:Changed()
end

-- 同步：W 观战，P 在座心跳，C 声明，Q 请求，H/B 房主快照，E 拒绝，R 要快照。
-- Q| 在这里去重：请求不幂等。状态包重复无害，留给后面的序号丢掉。
function CheckersModule:OnMessage(text, sender)
	if self:DuplicateRequest(sender, text) then return end
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

function CheckersModule:DuplicateRequest(sender, text)
	if type(text) ~= "string" or text:sub(1, 2) ~= "Q|" then return false end
	local now = GetTime()
	local seen = self._seen
	if now - (self._lastSweep or 0) > 10 then
		self._lastSweep = now
		for k, t in pairs(seen) do
			if now - t > 1.5 then seen[k] = nil end
		end
	end
	local key = tostring(sender) .. "\0" .. text
	local t = seen[key]
	if t and now - t <= 1.5 then return true end
	seen[key] = now
	return false
end

-- 同步：带着本机见过的序号向房主要 H+B。没有序号时发 R。
function CheckersModule:RequestSnapshot()
	local seq = math.max(self.appliedH or 0, self.appliedB or 0)
	if seq > 0 then
		self:Send("R|" .. seq)
	else
		self:Send("R")
	end
end

function CheckersModule:TouchSeat(name)
	local seat = self:SeatOf(name)
	if seat then self.seats[seat].seen = GetTime() end
end

--- 座位 / 准备 / 离座：抢座式声明，各端就地应用，房主快照兜底纠偏
--- 同步：C。各端先落地。重复声明无害，快照再纠偏。
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
		self.seats[idx] = self:Seat(sender, p[4] == "1", GetTime())
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
--- 同步：Q。只在房主裁决。Q| 由通道去重。走子失败回 E。
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

-- 同步：H。序号比已应用的旧则丢掉。同序号时名字较小的那份算数。
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
			self.seats[i] = self:Seat(
				nm,
				mask:sub(i, i) == "1",
				(old and old.name == nm and old.seen) or GetTime()
			)
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

-- 同步：B。序号未越过则丢掉；对局中棋盘仍是空的时宁可收下。
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
-- 同步：点击时机。本机先改，再发 C 或 Q。房主自己的改动随 H+B 广播。
-- ------------------------------------------------------------
-- 同步：点击。本机先入座，再发 C|SIT。丢包由心跳补报。
function CheckersModule:Sit(index)
	if self.phase ~= "wait" then return false, "对局已开始，等下一局" end
	if self:MySeat() then return false, "你已经在座上了" end
	if index < 1 or index > 6 then return false, "座位号无效" end
	if self.seats[index] then return false, "该座位已被占" end
	self.seats[index] = self:Seat(self:Me(), false, GetTime())
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

-- 同步：点击。本机先离座，再发 C|UP。对局中不发。
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

-- 同步：点击。本机先改准备，再发 C|RDY。意图记在 myReady，避免被快照拉回。
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
--- 同步：房主本机开局后广播 H+B。人齐时由心跳调用，玩家点击不直接开局。
function CheckersModule:StartGame()
	if self.phase ~= "wait" then return false end
	local board = self:EmptyBoard()
	for seat = 1, 6 do
		if self.seats[seat] then
			for i = 1, 121 do
				if G.cells[i].arm == seat then board[i] = seat end
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
--- 同步：非房主发 Q|NEW，等房主裁决。房主本机重开后广播 H+B。
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
	self.board  = self:EmptyBoard()
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
--- 同步：点击。房主落子后广播。其他人发 Q|MV，不在本地改棋盘。
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
--- 同步：房主落子后 MarkDirty，由 H+B 带到各端。
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
-- 同步：面板开启发 W|1，关闭发 W|0。心跳每 8 秒补报 W|1。
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
-- 同步：先攒满 1 秒。补报入座、W/P 为 8 秒，房主 H+B 为 4 秒，非房主 R 约 2 秒。
-- 观战由界面在主窗口显示和隐藏时调用 SetWatching。
-- ------------------------------------------------------------
-- 同步：心跳时机。不在这一拍里按帧同步状态，只按上面的间隔补报、要快照、广播。
function CheckersModule:update(elapsed)
	self.acc = (self.acc or 0) + (elapsed or 0)
	if self.acc < 1 then return end
	self.acc = 0

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
		if now - (self.lastWatch or 0) >= G.PING_EVERY then
			self.lastWatch = now
			self:Send("W|1")
		end
	elseif mySeat then
		if now - (self.lastPing or 0) >= G.PING_EVERY then
			self.lastPing = now
			self:Send("P")
		end
	end

	-- 座位和准备都是「说一次就算」的：那一条包丢了，房主那边就永远看不到我
	-- 坐下了 / 已就绪，全桌卡在等人阶段。跟着心跳幂等补报一次。
	if mySeat and self.phase == "wait" and now - (self.lastClaim or 0) >= G.PING_EVERY then
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
			self:RequestSnapshot()
		end
	end

	-- 清理沉默的观战者
	local dirty = false
	for name, seen in pairs(self.watchers) do
		if name ~= self:Me() and now - seen > G.WATCH_TTL then
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
				if s and now - (s.seen or now) > G.SEAT_STALE then
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
			if now - (self.turnAt or now) > G.TURN_SKIP then
				self.turn   = self:NextTurn(self.turn)
				self.turnAt = now
				self:Broadcast()
			end
		end
		if now - (self.lastBroadcast or 0) >= G.HOST_EVERY then self:Broadcast() end
	end
end

-- ------------------------------------------------------------
-- 8 · 本机演练（没有队友时也能看棋盘；不外发任何包）
-- ------------------------------------------------------------
-- 同步：mute 期间 Send 直接丢掉。退出演练会发 R，向房主要一次快照。
function CheckersModule:Demo()
	if self.mute then
		-- 再点一次 = 退出演练。mute 必须清掉，否则之后一直发不出包、
		-- IsHost 还会恒为 true，两个人真同桌时这台机器就成了哑巴。
		self:init()
		local f = MZ.App.UI and MZ.App.UI.frame
		if f and f:IsShown() then self:SetWatching(true) end
		self:RequestSnapshot()
		self:Changed()
		return false
	end
	self.mute = true
	for i = 1, 6 do self.seats[i] = nil end
	for i = 1, 6 do
		self.seats[i] = self:Seat(
			(i == 1) and self:Me() or ("棋友" .. G.SEAT_NAMES[i]),
			true,
			GetTime()
		)
	end
	self.phase  = "wait"
	self.board  = self:EmptyBoard()
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
