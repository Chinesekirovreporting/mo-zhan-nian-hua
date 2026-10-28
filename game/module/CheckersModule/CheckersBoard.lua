-- ============================================================
-- CheckersBoard · 六角跳棋的几何和走子规则
-- 本机数据。不发插件消息，也不走 sync。
-- 对外仍由 CheckersModule 转发，界面不直接拿这张表。
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App

local Board = {}
App.CheckersBoard = Board

-- 17 行星形，共 121 格。u = 半格横坐标（u/2 = 一格间距），v = 行号（自上而下）
-- ARM：0 = 中央区，1..6 = 六个营（1 南 · 2 东南 · 3 东北 · 4 北 · 5 西北 · 6 西南）
-- 对面营：1<->4、2<->5、3<->6，即 (arm + 2) % 6 + 1
Board.ROWLEN = { 1, 2, 3, 4, 13, 12, 11, 10, 9, 10, 11, 12, 13, 4, 3, 2, 1 }

Board.ARM = {
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

Board.CELL_COUNT = 121
Board.PER_ARM    = 10
Board.SEAT_COUNT = 6

Board.SEAT_NAMES = { "一", "二", "三", "四", "五", "六" }
Board.ARM_LABEL  = { "南", "东南", "东北", "北", "西北", "西南" }

Board.SEAT_COLORS = {
	{ 0.760, 0.235, 0.196 },
	{ 0.851, 0.647, 0.216 },
	{ 0.353, 0.573, 0.310 },
	{ 0.204, 0.502, 0.588 },
	{ 0.271, 0.365, 0.702 },
	{ 0.514, 0.298, 0.573 },
}

Board.NB = {
	App.CheckersOffsetVo:new(2, 0),
	App.CheckersOffsetVo:new(-2, 0),
	App.CheckersOffsetVo:new(1, 1),
	App.CheckersOffsetVo:new(-1, 1),
	App.CheckersOffsetVo:new(1, -1),
	App.CheckersOffsetVo:new(-1, -1),
}

function Board.KeyOf(u, v)
	return u * 64 + v
end

Board.cells = {}
Board.byKey = {}
Board.ids = {}
do
	local id = 0
	for v, len in ipairs(Board.ROWLEN) do
		local odd = (v % 2 == 1)
		local i0 = odd and -math.floor((len - 1) / 2) or -math.floor(len / 2)
		for k = 0, len - 1 do
			local u = odd and (2 * (i0 + k)) or (2 * (i0 + k) + 1)
			id = id + 1
			Board.cells[id] = App.CheckersCellVo:new(id, u, v, u / 2, 9 - v, Board.ARM[id] or 0)
			Board.byKey[Board.KeyOf(u, v)] = id
			Board.ids[#Board.ids + 1] = id
		end
	end
end

Board.neighbors = {}
Board.jumps = {}
for _, c in ipairs(Board.cells) do
	local nbs, jps = {}, {}
	for _, d in ipairs(Board.NB) do
		local n = Board.byKey[Board.KeyOf(c.u + d.du, c.v + d.dv)]
		if n then
			nbs[#nbs + 1] = n
			local land = Board.byKey[Board.KeyOf(c.u + d.du * 2, c.v + d.dv * 2)]
			if land then jps[#jps + 1] = App.CheckersJumpVo:new(n, land) end
		end
	end
	Board.neighbors[c.id] = nbs
	Board.jumps[c.id] = jps
end

function Board.IsNeighbor(a, b)
	for _, n in ipairs(Board.neighbors[a] or {}) do
		if n == b then return true end
	end
	return false
end

function Board.StepTargets(board, id)
	local out = {}
	for _, n in ipairs(Board.neighbors[id] or {}) do
		if board[n] == 0 then out[#out + 1] = n end
	end
	return out
end

function Board.JumpTargets(board, id)
	local out = {}
	for _, j in ipairs(Board.jumps[id] or {}) do
		if board[j.mid] ~= 0 and board[j.dest] == 0 then out[#out + 1] = j.dest end
	end
	return out
end

function Board.JumpMid(board, a, b)
	for _, j in ipairs(Board.jumps[a] or {}) do
		if j.dest == b and board[j.mid] ~= 0 and board[b] == 0 then return j.mid end
	end
	return nil
end

function Board.ValidPath(board, path)
	if #path < 2 then return false end
	local from, first = path[1], path[2]
	if board[from] == 0 then return false end
	if #path == 2 and Board.IsNeighbor(from, first) and board[first] == 0 then
		return true
	end
	local visited = { [from] = true }
	local cur = from
	for i = 2, #path do
		local to = path[i]
		if visited[to] then return false end
		if not Board.JumpMid(board, cur, to) then return false end
		visited[to] = true
		cur = to
	end
	return true
end

function Board.TargetArm(seat)
	return (seat + 2) % 6 + 1
end
