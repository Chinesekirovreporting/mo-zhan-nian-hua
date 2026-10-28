-- ============================================================
-- NetCodec · 结构化包的序列化、压缩和可打印编码
-- 跳棋短明文不走这里。NetManager 的 Pack / Unpack 转到这张表。
-- ============================================================
local ADDON_NAME, MZ = ...
local App = MZ.App

local Codec = {}
App.NetCodec = Codec

function Codec.WriteValue(net, value)
	local kind = type(value)
	if kind == "nil" then return "z" end
	if kind == "boolean" then
		if value then return "t" else return "f" end
	end
	if kind == "number" then return "n" .. tostring(value) .. ";" end
	if kind == "string" then return "s" .. #value .. ":" .. value end
	if kind == "table" then
		local n = #value
		local body = ""
		local i = 1
		while i <= n do
			body = body .. Codec.WriteValue(net, value[i])
			i = i + 1
		end
		local extra = 0
		local map = ""
		for k, v in pairs(value) do
			local inArray = type(k) == "number" and k >= 1 and k <= n and k == math.floor(k)
			if not inArray then
				extra = extra + 1
				map = map .. Codec.WriteValue(net, tostring(k)) .. Codec.WriteValue(net, v)
			end
		end
		return "m" .. n .. ":" .. extra .. ":" .. body .. map
	end
	return "z"
end

function Codec.ReadValue(net, str, i)
	if type(str) ~= "string" or i > #str then return nil, i end
	local tag = str:sub(i, i)
	if tag == "z" then return nil, i + 1 end
	if tag == "t" then return true, i + 1 end
	if tag == "f" then return false, i + 1 end
	if tag == "n" then
		local semi = str:find(";", i + 1, true)
		if not semi then return nil, #str + 1 end
		return tonumber(str:sub(i + 1, semi - 1)), semi + 1
	end
	if tag == "s" then
		local colon = str:find(":", i + 1, true)
		if not colon then return nil, #str + 1 end
		local len = tonumber(str:sub(i + 1, colon - 1))
		if not len or len < 0 then return nil, #str + 1 end
		local a = colon + 1
		if a + len - 1 > #str then return nil, #str + 1 end
		return str:sub(a, a + len - 1), a + len
	end
	if tag == "m" then
		local c1 = str:find(":", i + 1, true)
		if not c1 then return nil, #str + 1 end
		local n = tonumber(str:sub(i + 1, c1 - 1))
		local c2 = str:find(":", c1 + 1, true)
		if not n or n < 0 or not c2 then return nil, #str + 1 end
		local extra = tonumber(str:sub(c1 + 1, c2 - 1))
		if not extra or extra < 0 then return nil, #str + 1 end
		local p = c2 + 1
		local arr = {}
		local idx = 1
		while idx <= n do
			local v
			v, p = Codec.ReadValue(net, str, p)
			arr[idx] = v
			idx = idx + 1
		end
		idx = 1
		while idx <= extra do
			local k, v
			k, p = Codec.ReadValue(net, str, p)
			v, p = Codec.ReadValue(net, str, p)
			arr[k] = v
			idx = idx + 1
		end
		return arr, p
	end
	return nil, #str + 1
end

function Codec.Sum(net, text)
	local s = 0
	local i = 1
	while i <= #text do
		s = (s + text:byte(i) * i) % 65536
		i = i + 1
	end
	return string.format("%04x", s)
end

function Codec.Compress(net, src)
	if type(src) ~= "string" or #src < 8 then return nil end
	local acc = ""
	local i = 1
	local n = #src
	local window = net.WINDOW
	while i <= n do
		local bestLen, bestDist = 0, 0
		local j = math.max(1, i - window)
		while j < i do
			local len = 0
			local cap = i - j
			if cap > 255 then cap = 255 end
			while len < cap and (i + len) <= n and src:byte(j + len) == src:byte(i + len) do
				len = len + 1
			end
			if len >= 3 and len > bestLen then
				bestLen = len
				bestDist = i - j
			end
			j = j + 1
		end
		if bestLen >= 3 then
			acc = acc .. string.char(1, bestDist, bestLen)
			i = i + bestLen
		else
			local b = src:byte(i)
			if b == 1 then
				acc = acc .. string.char(1, 0, 1)
			else
				acc = acc .. string.char(0, b)
			end
			i = i + 1
		end
	end
	return acc
end

function Codec.Decompress(net, src)
	if type(src) ~= "string" then return nil end
	local acc = ""
	local i = 1
	local n = #src
	while i <= n do
		local mark = src:byte(i)
		if mark == 0 then
			if i + 1 > n then return nil end
			acc = acc .. src:sub(i + 1, i + 1)
			i = i + 2
		elseif mark == 1 then
			if i + 2 > n then return nil end
			local dist = src:byte(i + 1)
			local len = src:byte(i + 2)
			if dist == 0 then
				if len ~= 1 then return nil end
				acc = acc .. string.char(1)
			else
				if dist > #acc or len < 1 then return nil end
				local start = #acc - dist + 1
				local k = 0
				while k < len do
					acc = acc .. acc:sub(start + (k % dist), start + (k % dist))
					k = k + 1
				end
			end
			i = i + 3
		else
			return nil
		end
	end
	return acc
end

function Codec.Encode64(net, data)
	local out = {}
	local n = #data
	local i = 1
	local alph = net.ALPH
	while i <= n do
		local a = data:byte(i)
		local b = 0
		local c = 0
		if i + 1 <= n then b = data:byte(i + 1) end
		if i + 2 <= n then c = data:byte(i + 2) end
		local triple = a * 65536 + b * 256 + c
		local c1 = math.floor(triple / 262144) % 64
		local c2 = math.floor(triple / 4096) % 64
		local c3 = math.floor(triple / 64) % 64
		local c4 = triple % 64
		out[#out + 1] = alph:sub(c1 + 1, c1 + 1)
		out[#out + 1] = alph:sub(c2 + 1, c2 + 1)
		if i + 1 <= n then
			out[#out + 1] = alph:sub(c3 + 1, c3 + 1)
		else
			out[#out + 1] = "="
		end
		if i + 2 <= n then
			out[#out + 1] = alph:sub(c4 + 1, c4 + 1)
		else
			out[#out + 1] = "="
		end
		i = i + 3
	end
	return table.concat(out)
end

function Codec.Decode64(net, data)
	if type(data) ~= "string" or data == "" then return nil end
	if not net._b64map then
		local map = {}
		local i = 1
		while i <= #net.ALPH do
			map[net.ALPH:sub(i, i)] = i - 1
			i = i + 1
		end
		net._b64map = map
	end
	local map = net._b64map
	local out = {}
	local i = 1
	while i <= #data do
		local ch1 = data:sub(i, i)
		local ch2 = data:sub(i + 1, i + 1)
		local ch3 = data:sub(i + 2, i + 2)
		local ch4 = data:sub(i + 3, i + 3)
		if ch1 == "" or ch2 == "" or not map[ch1] or not map[ch2] then return nil end
		local c1 = map[ch1]
		local c2 = map[ch2]
		local c3 = map[ch3]
		local c4 = map[ch4]
		local n = c1 * 262144 + c2 * 4096 + (c3 or 0) * 64 + (c4 or 0)
		out[#out + 1] = string.char(math.floor(n / 65536) % 256)
		if ch3 ~= "" and ch3 ~= "=" then
			out[#out + 1] = string.char(math.floor(n / 256) % 256)
		end
		if ch4 ~= "" and ch4 ~= "=" then
			out[#out + 1] = string.char(n % 256)
		end
		i = i + 4
	end
	return table.concat(out)
end

function Codec.Pack(net, value)
	local raw = Codec.WriteValue(net, value)
	if type(raw) ~= "string" then return nil end
	local sum = Codec.Sum(net, raw)
	local smaller = Codec.Compress(net, raw)
	local flag = "U"
	local data = raw
	if smaller and #smaller < #raw then
		flag = "C"
		data = smaller
	end
	return flag .. "|" .. sum .. "|" .. Codec.Encode64(net, data)
end

function Codec.Unpack(net, text)
	if type(text) ~= "string" then return nil, false end
	local flag, sum, b64 = text:match("^([UC])|(%x%x%x%x)|(.+)$")
	if not flag or not b64 then return nil, false end
	local data = Codec.Decode64(net, b64)
	if not data then return nil, false end
	if flag == "C" then
		data = Codec.Decompress(net, data)
		if not data then return nil, false end
	end
	if Codec.Sum(net, data) ~= sum then return nil, false end
	local value, nxt = Codec.ReadValue(net, data, 1)
	if nxt ~= #data + 1 then return nil, false end
	return value, true
end
