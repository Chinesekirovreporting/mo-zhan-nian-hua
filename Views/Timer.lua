-- ============================================================
-- View · 开怪计时
-- ============================================================
local ADDON_NAME, MZ = ...
local S = MZ.Skin
local C = MZ.C
local UI = MZ.UI

local function GroupChannel()
	if IsInRaid() then return "RAID" end
	if IsInGroup() then return "PARTY" end
	return "SAY"
end

UI:AddPage{
	id       = "timer",
	title    = "开怪计时",
	subtitle = "设定分钟数，到点自动通报",
	order    = 20,
	build    = function(page, body)
		local remain = (MZ.Store:GetKey("timerMinutes", 3)) * 60
		local running = false
		local endAt = 0
		local tick

		local display = S:Text(body, 46, "ink", MZ.Time:Format(remain))
		display:SetPoint("TOP", body, "TOP", 0, -10)

		local status = S:Text(body, 11, "inkFaint", "未开始")
		status:SetPoint("TOP", display, "BOTTOM", 0, -6)

		local label = S:Text(body, 12, "inkSoft", "分钟数")
		label:SetPoint("TOPLEFT", body, "TOPLEFT", 4, -104)

		local box = S:EditBox(body, 60, 26)
		box:SetPoint("LEFT", label, "RIGHT", 10, 0)
		box:SetText(tostring(MZ.Store:GetKey("timerMinutes", 3)))

		local setBtn = S:Button(body, "设定", 60, 26)
		setBtn:SetPoint("LEFT", box, "RIGHT", 8, 0)

		local startBtn = S:Button(body, "开始", 72, 28, true)
		startBtn:SetPoint("TOPLEFT", body, "TOPLEFT", 4, -146)

		local pauseBtn = S:Button(body, "暂停", 72, 28)
		pauseBtn:SetPoint("LEFT", startBtn, "RIGHT", 8, 0)

		local resetBtn = S:Button(body, "重置", 72, 28)
		resetBtn:SetPoint("LEFT", pauseBtn, "RIGHT", 8, 0)

		local sayBtn = S:Button(body, "通报剩余", 96, 28)
		sayBtn:SetPoint("LEFT", resetBtn, "RIGHT", 8, 0)

		local hint = S:Text(body, 11, "inkFaint", "提示：通报会发到团队 / 小队频道，单人时为说话。")
		hint:SetPoint("TOPLEFT", body, "TOPLEFT", 4, -186)

		local function Refresh()
			display:SetText(MZ.Time:Format(remain))
			if running then
				status:SetText("进行中")
			elseif remain <= 0 then
				status:SetText("已结束")
			else
				status:SetText("已暂停 / 待开始")
			end
		end

		local function ReadMinutes()
			local v = tonumber(box:GetText())
			if not v or v <= 0 then v = 3 end
			v = math.min(120, v)
			box:SetText(tostring(v))
			MZ.Store:Set("timerMinutes", v)
			return v
		end

		local function Announce(text)
			SendChatMessage("【墨战年华】" .. text, GroupChannel())
		end

		local function StopTick()
			if tick then
				tick:Cancel()
				tick = nil
			end
		end

		local function StartTick()
			StopTick()
			-- 用 Time 管理器驱动；切页不影响，到点照样通报
			tick = MZ.Time:Every(0.2, function()
				if not running then
					StopTick()
					return
				end
				remain = endAt - MZ.Time:Now()
				if remain <= 0 then
					remain = 0
					running = false
					StopTick()
					display:SetTextColor(C.cinnabar[1], C.cinnabar[2], C.cinnabar[3], 1)
					status:SetText("已结束")
					display:SetText(MZ.Time:Format(0))
					Announce("倒计时结束，开怪！")
					MZ.Event:Send("MZ_TIMER_DONE")
					return
				end
				display:SetText(MZ.Time:Format(remain))
			end)
		end

		startBtn:SetScript("OnClick", function()
			if remain <= 0 then remain = ReadMinutes() * 60 end
			endAt = MZ.Time:Now() + remain
			running = true
			display:SetTextColor(C.ink[1], C.ink[2], C.ink[3], 1)
			status:SetText("进行中")
			StartTick()
			Announce("开怪倒计时 " .. MZ.Time:Format(remain) .. " 开始，请就位。")
			MZ.Event:Send("MZ_TIMER_START", remain)
		end)

		pauseBtn:SetScript("OnClick", function()
			if running then
				remain = math.max(0, endAt - MZ.Time:Now())
				running = false
				StopTick()
				Refresh()
				MZ.Event:Send("MZ_TIMER_PAUSE", remain)
			end
		end)

		resetBtn:SetScript("OnClick", function()
			running = false
			StopTick()
			remain = ReadMinutes() * 60
			display:SetTextColor(C.ink[1], C.ink[2], C.ink[3], 1)
			Refresh()
		end)

		setBtn:SetScript("OnClick", function()
			if not running then
				remain = ReadMinutes() * 60
				Refresh()
			end
		end)

		sayBtn:SetScript("OnClick", function()
			Announce("倒计时 " .. MZ.Time:Format(remain) .. "，请准备。")
		end)

		Refresh()
	end,
}
