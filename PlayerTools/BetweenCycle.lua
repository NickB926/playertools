--[[
	Watches PlayerTools/_between_cycle_cmd.json (written by the Between cycle window).
	Travel → The Between → create party → set difficulty → start.
	On a special wave: reset, then Return to Lobby, then repeat.
]]
return function()
	local BUILD = 'swing-v4'
	local gen = (tonumber(getgenv().SB2BetweenCycleGen) or 0) + 1
	getgenv().SB2BetweenCycleGen = gen
	getgenv().SB2BetweenCycleBuild = BUILD
	local Players = game:GetService('Players')
	local ReplicatedStorage = game:GetService('ReplicatedStorage')
	local LocalPlayer = Players.LocalPlayer

	local CMD_PATH = 'PlayerTools/_between_cycle_v2_cmd.json'
	local STATUS_PATH = 'PlayerTools/_between_cycle_v2_status.json'
	local BETWEEN_PLACE_ID = 78945654064532
	local RUN_PLACES = {
		[540240728] = true,
		[78945654064532] = true,
		[580239979] = true,
	}
	local MODE_ORDER = { 'Normal', 'Hard', 'Elite' }
	local STATUS_ORDER = { 'Public', 'Friends', 'Game Party', 'Private' }

	local phase = 'idle'
	local detail = 'waiting for the window'
	local busy = false
	local runToken = 0
	local specialHandled = false
	local runSeenAt = 0
	local specialWasClear = true

	local function writeStatus(extra)
		if type(writefile) ~= 'function' then
			return
		end
		local function esc(s)
			return (tostring(s or ''):gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', ' '))
		end
		local body = string.format(
			'{"phase":"%s","detail":"%s","busy":%s,"place":%d}',
			esc(phase),
			esc(detail),
			busy and 'true' or 'false',
			tonumber(game.PlaceId) or 0
		)
		if extra then
			body = body:sub(1, -2) .. ',"note":"' .. esc(extra) .. '"}'
		end
		pcall(writefile, STATUS_PATH, body)
	end

	local function setPhase(nextPhase, nextDetail)
		phase = nextPhase
		detail = nextDetail or ''
		writeStatus()
	end

	local function readCmd()
		if type(isfile) ~= 'function' or type(readfile) ~= 'function' or not isfile(CMD_PATH) then
			return { run = false, mode = 'Hard', status = 'Private' }
		end
		local ok, raw = pcall(readfile, CMD_PATH)
		if not ok or type(raw) ~= 'string' then
			return { run = false, mode = 'Hard', status = 'Private' }
		end
		local mode = raw:match('"mode"%s*:%s*"([^"]+)"') or 'Hard'
		local status = raw:match('"status"%s*:%s*"([^"]+)"') or 'Private'
		if mode ~= 'Normal' and mode ~= 'Hard' and mode ~= 'Elite' then
			mode = 'Hard'
		end
		local known = false
		for _, name in ipairs(STATUS_ORDER) do
			if name == status then
				known = true
				break
			end
		end
		if not known then
			status = 'Private'
		end
		return {
			run = raw:find('"run"%s*:%s*true') ~= nil,
			mode = mode,
			status = status,
		}
	end

	local function stillRunning()
		return readCmd().run == true
	end

	local function fireGuiButton(btn)
		if not (btn and btn:IsA('GuiButton')) then
			return false
		end
		local ran = false
		if type(getconnections) == 'function' then
			pcall(function()
				for _, sigName in ipairs({ 'Activated', 'MouseButton1Click' }) do
					local ok, cons = pcall(getconnections, btn[sigName])
					if not (ok and type(cons) == 'table') then
						continue
					end
					for _, c in ipairs(cons) do
						pcall(function()
							if type(c.Function) == 'function' then
								c.Function()
								ran = true
							end
						end)
					end
				end
			end)
		end
		if type(firesignal) == 'function' then
			pcall(function()
				firesignal(btn.Activated)
				ran = true
			end)
		end
		pcall(function()
			btn:Activate()
			ran = true
		end)
		return ran
	end

	local function fireParties(action, extra)
		local payload = { 'Parties', action }
		if extra ~= nil then
			payload[#payload + 1] = extra
		end
		local ev = ReplicatedStorage:FindFirstChild('Event')
		if not ev then
			return false
		end
		pcall(function()
			ev:FireServer('UniqueFloorTypes', payload)
		end)
		return true
	end

	local function invokeParties(action, extra)
		local fn = ReplicatedStorage:FindFirstChild('Function')
		if not fn then
			return nil
		end
		local payload = { 'Parties', action }
		if extra ~= nil then
			payload[#payload + 1] = extra
		end
		local ok, result = pcall(function()
			return fn:InvokeServer('UniqueFloorTypes', payload)
		end)
		if not ok then
			return nil
		end
		return result
	end

	local function partyFolder()
		local pid = LocalPlayer:GetAttribute('PartyID')
		if pid == nil then
			return nil
		end
		local parties = ReplicatedStorage:FindFirstChild('LobbyParties')
		if not parties then
			return nil
		end
		return parties:FindFirstChild(tostring(pid))
	end

	local cycleSwinging = false

	local function combatActions()
		local svc = getgenv().SB2RequiredServices
		local actions = svc and svc.Actions
		if type(actions) == 'table' then
			return actions
		end
		return nil
	end

	local function holdSwing()
		local actions = combatActions()
		if not (actions and type(actions.StartSwing) == 'function') then
			return
		end
		cycleSwinging = true
		task.spawn(actions.StartSwing)
	end

	local function releaseSwing()
		if not cycleSwinging then
			return
		end
		cycleSwinging = false
		if getgenv().SB2AutoSwingConn ~= nil then
			return
		end
		local actions = combatActions()
		if actions and type(actions.StopSwing) == 'function' then
			pcall(actions.StopSwing)
		end
	end

	local function inActiveRun()
		if not workspace:FindFirstChild('WaveDefenseStuff') then
			return false
		end
		return RUN_PLACES[tonumber(game.PlaceId)] == true
	end

	local function inBetweenLobby()
		return tonumber(game.PlaceId) == BETWEEN_PLACE_ID and not workspace:FindFirstChild('WaveDefenseStuff')
	end

	local function textShown(inst)
		local cur = inst
		while cur and cur ~= game do
			if cur:IsA('LayerCollector') then
				if cur.Enabled == false then
					return false
				end
			elseif cur:IsA('GuiObject') and cur.Visible == false then
				return false
			end
			cur = cur.Parent
		end
		return true
	end

	local function textIsSpecialWave(raw)
		local t = string.lower(tostring(raw or ''):gsub('%s+', ' '))
		if t == '' or #t > 80 then
			return false
		end
		if string.find(t, 'wave key', 1, true) or string.find(t, 'preview special', 1, true) then
			return false
		end
		if string.find(t, 'special wave', 1, true) or string.find(t, 'rift wave', 1, true) then
			return true, t
		end
		return false
	end

	local function specialWaveVisible()
		local pg = LocalPlayer:FindFirstChild('PlayerGui')
		if not pg then
			return false, ''
		end
		local center = pg:FindFirstChild('CenterLabel')
		local label = center and center:FindFirstChild('Frame', true)
		label = label and label:FindFirstChild('TextLabel')
		if label and label:IsA('TextLabel') and textShown(label) then
			local hit, t = textIsSpecialWave(label.Text)
			if hit then
				return true, t
			end
		end
		local scanned = 0
		for _, d in ipairs(pg:GetDescendants()) do
			scanned += 1
			if scanned > 8000 then
				break
			end
			if not (d:IsA('TextLabel') or d:IsA('TextButton')) or not textShown(d) then
				continue
			end
			local hit, t = textIsSpecialWave(d.Text)
			if hit then
				return true, t
			end
		end
		return false, ''
	end

	local function mainFrame()
		local pg = LocalPlayer:FindFirstChild('PlayerGui')
		local cardinal = pg and pg:FindFirstChild('CardinalUI')
		local playerUi = cardinal and cardinal:FindFirstChild('PlayerUI')
		return playerUi and playerUi:FindFirstChild('MainFrame')
	end

	local function openTravelTab()
		local mf = mainFrame()
		if not mf then
			return false, 'menu missing'
		end
		mf.Visible = true
		local tabs = mf:FindFirstChild('Tabs')
		local button = nil
		if tabs then
			button = tabs:FindFirstChild('Locations') or tabs:FindFirstChild('Travel')
			if not button then
				for _, child in ipairs(tabs:GetDescendants()) do
					if child:IsA('GuiButton') then
						local blob = string.lower(child.Name .. ' ' .. tostring(child.Text or ''))
						if string.find(blob, 'travel', 1, true) or string.find(blob, 'location', 1, true) then
							button = child
							break
						end
					end
				end
			end
		end
		if button then
			fireGuiButton(button)
		end
		local frames = mf:FindFirstChild('TabFrames')
		local locations = frames and frames:FindFirstChild('Locations')
		if locations and locations:IsA('GuiObject') then
			locations.Visible = true
		end
		return locations ~= nil, locations
	end

	local function findBetweenButton(locations)
		local map = locations and locations:FindFirstChild('MapList')
		if not map then
			return nil, nil
		end
		local label = nil
		for _, d in ipairs(map:GetDescendants()) do
			if (d:IsA('TextLabel') or d:IsA('TextButton')) and d.Text then
				if string.find(string.lower(tostring(d.Text)), 'the between', 1, true) then
					label = d
					break
				end
			end
		end
		if not label then
			return nil, map
		end
		local btn = label
		while btn and btn ~= map do
			if btn:IsA('TextButton') and btn.Name == 'FloorTemplate' then
				return btn, map
			end
			btn = btn.Parent
		end
		btn = label
		while btn and not btn:IsA('GuiButton') do
			btn = btn.Parent
		end
		return btn or label, map
	end

	local function scrollIntoView(map, gui)
		if not (map and map:IsA('ScrollingFrame') and gui) then
			return
		end
		local rel = gui.AbsolutePosition.Y - map.AbsolutePosition.Y + map.CanvasPosition.Y
		map.CanvasPosition = Vector2.new(map.CanvasPosition.X, math.max(0, rel - 36))
	end

	local function openBetweenFromTravel()
		setPhase('travel', 'opening Travel')
		local ok, locations = openTravelTab()
		if not ok then
			return false, 'Travel menu did not open'
		end
		task.wait(0.35)
		if not stillRunning() then
			return false, 'stopped'
		end
		local btn, map = findBetweenButton(locations)
		if not btn then
			if type(getgenv().SB2BetweenOpenPartyUi) == 'function' then
				local opened = getgenv().SB2BetweenOpenPartyUi()
				if opened then
					return true
				end
			end
			return false, 'The Between is not on the travel list'
		end
		setPhase('travel', 'scrolling to The Between')
		scrollIntoView(map, btn)
		task.wait(0.25)
		fireGuiButton(btn)
		task.wait(0.4)
		local opened = false
		local openErr = nil
		if type(getgenv().SB2BetweenOpenPartyUi) == 'function' then
			local ok, result, err = pcall(getgenv().SB2BetweenOpenPartyUi)
			opened = ok and result == true
			if not opened then
				openErr = (ok and err) or result
			end
		end
		local parties = locations:FindFirstChild('Parties')
		if parties and parties:IsA('GuiObject') and parties.Visible then
			opened = true
		end
		if not opened then
			return false, tostring(openErr or 'The Between card did not open')
		end
		return true
	end

	local function waitForParty(timeout)
		local t0 = os.clock()
		while os.clock() - t0 < timeout do
			if not stillRunning() then
				return nil
			end
			local folder = partyFolder()
			if folder then
				return folder
			end
			task.wait(0.1)
		end
		return partyFolder()
	end

	local function cycleAttribute(attr, action, target, steps)
		local folder = partyFolder()
		if not folder then
			return false, 'no party'
		end
		if folder:GetAttribute('Host') ~= LocalPlayer.UserId then
			return false, 'not the party leader'
		end
		for _ = 1, steps do
			folder = partyFolder()
			if not folder then
				return false, 'party closed'
			end
			if folder:GetAttribute(attr) == target then
				return true
			end
			local prev = folder:GetAttribute(attr)
			fireParties(action)
			local deadline = os.clock() + 1.3
			while os.clock() < deadline do
				task.wait(0.06)
				folder = partyFolder()
				if not folder then
					break
				end
				local now = folder:GetAttribute(attr)
				if now == target or now ~= prev then
					break
				end
			end
		end
		folder = partyFolder()
		return folder and folder:GetAttribute(attr) == target, folder and folder:GetAttribute(attr)
	end

	local function startRun(mode, status)
		local opened, err = openBetweenFromTravel()
		if not opened then
			return false, err
		end
		if not stillRunning() then
			return false, 'stopped'
		end
		setPhase('party', 'creating party')
		local existing = partyFolder()
		if existing and tonumber(existing:GetAttribute('PlaceId')) ~= BETWEEN_PLACE_ID then
			if existing:GetAttribute('Host') == LocalPlayer.UserId then
				fireParties('LeaveParty')
				task.wait(0.45)
			else
				return false, 'leave your current party first'
			end
		end
		if not partyFolder() then
			fireParties('CreateParty', tonumber(getgenv().SB2BetweenLocIndex) or 25)
			if not waitForParty(8) then
				return false, 'create party timed out'
			end
		end
		task.wait(0.25)
		setPhase('party', 'setting ' .. mode)
		local okMode, modeNow = cycleAttribute('Mode', 'ToggleMode', mode, 8)
		if not okMode then
			return false, 'difficulty stayed on ' .. tostring(modeNow)
		end
		setPhase('party', 'setting ' .. status)
		local okStatus, statusNow = cycleAttribute('Status', 'ToggleStatus', status, 6)
		if not okStatus then
			return false, 'party status stayed on ' .. tostring(statusNow)
		end
		if not stillRunning() then
			return false, 'stopped'
		end
		setPhase('start', 'starting')
		local result = invokeParties('Start')
		if result ~= true then
			invokeParties('Start', tonumber(getgenv().SB2BetweenLocIndex) or 25)
		end
		return true
	end

	local function reviveFrame()
		local pg = LocalPlayer:FindFirstChild('PlayerGui')
		local ok, frame = pcall(function()
			return pg.CardinalUI.PlayerUI.Popups.WaveDefense.ReviveFrame
		end)
		if ok then
			return frame
		end
		return nil
	end

	local function resetAndReturn()
		setPhase('reset', 'resetting')
		local char = LocalPlayer.Character
		local hum = char and char:FindFirstChildOfClass('Humanoid')
		if hum then
			pcall(function()
				hum.Health = 0
			end)
		end
		if char then
			pcall(function()
				char:BreakJoints()
			end)
		end
		local t0 = os.clock()
		local clicked = false
		while os.clock() - t0 < 10 do
			if not stillRunning() then
				return false, 'stopped'
			end
			local frame = reviveFrame()
			local ret = frame and frame:FindFirstChild('Return')
			if frame and frame.Visible and ret and ret:IsA('GuiButton') then
				setPhase('lobby', 'Return to Lobby')
				fireGuiButton(ret)
				clicked = true
				break
			end
			task.wait(0.15)
		end
		if not clicked then
			return false, 'revive screen did not open'
		end
		local leaveAt = os.clock()
		while os.clock() - leaveAt < 25 do
			if not inActiveRun() then
				return true
			end
			task.wait(0.25)
		end
		return false, 'still in the run after Return to Lobby'
	end

	local function loopOnce()
		local cmd = readCmd()
		if not cmd.run then
			releaseSwing()
			if phase ~= 'idle' then
				setPhase('idle', 'stopped')
			end
			specialHandled = false
			return
		end
		if inActiveRun() then
			if runSeenAt == 0 then
				runSeenAt = os.clock()
				specialWasClear = not specialWaveVisible()
			end
			local found, text = specialWaveVisible()
			if not found then
				specialWasClear = true
			end
			if found and not specialHandled and (specialWasClear or os.clock() - runSeenAt > 6) then
				specialWasClear = false
				specialHandled = true
				releaseSwing()
				setPhase('special', text)
				local ok, err = resetAndReturn()
				if not ok then
					setPhase('error', err or 'reset failed')
					specialHandled = false
					task.wait(3)
				end
			elseif not specialHandled then
				holdSwing()
				setPhase('run', 'swinging, watching for a special wave')
			end
			return
		end
		runSeenAt = 0
		specialHandled = false
		specialWasClear = true
		releaseSwing()
		if busy then
			return
		end
		busy = true
		runToken += 1
		local token = runToken
		task.spawn(function()
			local ok, err = startRun(cmd.mode, cmd.status)
			if token ~= runToken then
				busy = false
				return
			end
			if not ok then
				setPhase('error', err or 'start failed')
				task.wait(4)
			else
				setPhase('start', 'waiting for the run to load')
				local t0 = os.clock()
				while os.clock() - t0 < 50 and stillRunning() and not inActiveRun() do
					task.wait(0.4)
				end
			end
			busy = false
		end)
	end

	task.spawn(function()
		setPhase('idle', 'ready')
		while getgenv().SB2BetweenCycleGen == gen do
			task.wait(0.45)
			local ok, err = pcall(loopOnce)
			if not ok then
				busy = false
				setPhase('error', tostring(err))
			end
		end
	end)

	getgenv().SB2BetweenCycleLoaded = true
end
