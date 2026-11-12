--[[
	The Between (Wave Defense party lobby) — create party, set mode/status, start run.
	Split from PlayerTools_Obsidian.lua (register / size).
]]
getgenv().SB2BetweenPartyBuild = 'follow-friend-v24-panel-sync'

-- Keep the in-game party panel in sync with the real party (Status/Mode).
-- One loop per client: newest loader wins via a token.
do
	local G = getgenv()
	local token = {}
	G.SB2PartyPanelSync = token
	task.spawn(function()
		local ok, Parties = pcall(function()
			return require(game:GetService('ReplicatedStorage').CardinalClient.MainModule.Services.UI.Locations.Parties)
		end)
		if not ok or type(Parties) ~= 'table' or type(Parties.UpdateLocalParty) ~= 'function' then return end
		local lastSig
		while G.SB2PartyPanelSync == token do
			pcall(function()
				local party = Parties.GetLocalParty()
				if party then
					local sig = tostring(party:GetAttribute('Status')) .. '|' .. tostring(party:GetAttribute('Mode')) .. '|' .. party.Name
					if sig ~= lastSig or math.random() < 0.34 then
						lastSig = sig
						Parties.UpdateLocalParty(party)
					end
				else
					lastSig = nil
				end
			end)
			task.wait(1.5)
		end
	end)
end

return function(env)
	local function acctPath(p)
		-- Standalone AutoBetween runs on several accounts on one PC: give each its own files.
		local tag = getgenv().SB2AcctFileTag
		if type(tag) ~= 'string' or tag == '' then
			return p
		end
		local base, ext = string.match(p, '^(.-)(%.%w+)$')
		if base then
			return base .. '_' .. tag .. ext
		end
		return p .. '_' .. tag
	end
	local WdBox = env.WdBox
	local Library = env.Library
	local ReplicatedStorage = env.ReplicatedStorage or game:GetService('ReplicatedStorage')
	local Players = env.Players or game:GetService('Players')
	local LocalPlayer = env.LocalPlayer or Players.LocalPlayer
	local Options = env.Options
	assert(WdBox, 'BetweenParty: WdBox required')

	local BETWEEN_PLACE_ID = 78945654064532
	local BETWEEN_RUN_PLACE_IDS = {
		[540240728] = true,
		[78945654064532] = true,
		[580239979] = true,
	}
	local BETWEEN_AUTO_WAVE_MIN = 100
	local BETWEEN_AUTO_START_COOLDOWN = 38
	local BETWEEN_AUTO_RETRY_COOLDOWN = 4
	-- Database.Locations index for CreateParty / Parties.Open (verified in-game).
	local BETWEEN_LOC_INDEX = 25
	local BETWEEN_FALLBACK_ENTRY = {
		Name = 'The Between',
		PlaceId = BETWEEN_PLACE_ID,
		Modes = {
			Normal = { LayoutOrder = 1 },
			Hard = { LayoutOrder = 2 },
			Elite = { LayoutOrder = 3 },
		},
	}
	local STATUS_ORDER = { 'Public', 'Friends', 'Game Party', 'Private' }

	local function flattenOptionValue(value)
		if type(value) == 'table' then
			if type(value.Value) == 'string' or type(value.Value) == 'number' then
				return value.Value
			end
			if type(value[1]) == 'string' or type(value[1]) == 'number' then
				return value[1]
			end
			if type(value.Text) == 'string' then
				return value.Text
			end
		end
		return value
	end

	local function fireGuiButton(btn)
		if not (btn and btn:IsA('GuiButton')) then
			return false
		end
		pcall(function()
			btn.Visible = true
			btn.Active = true
		end)
		local ran = false
		if type(getconnections) == 'function' then
			pcall(function()
				for _, sigName in ipairs({ 'Activated', 'MouseButton1Click', 'MouseButton1Down' }) do
					local ok, cons = pcall(getconnections, btn[sigName])
					if not (ok and type(cons) == 'table') then
						continue
					end
					for _, c in ipairs(cons) do
						pcall(function()
							if c.Enabled == false and type(c.Enable) == 'function' then
								c:Enable()
							end
						end)
						pcall(function()
							if type(c.Function) == 'function' then
								c.Function()
								ran = true
							end
						end)
						pcall(function()
							if type(c.fn) == 'function' then
								c.fn()
								ran = true
							end
						end)
						pcall(function()
							if type(c.Fire) == 'function' then
								c:Fire()
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

	local function requireLocationsData()
		local db = ReplicatedStorage:FindFirstChild('Database')
		local locMod = db and db:FindFirstChild('Locations')
		if not locMod then
			return nil
		end
		if not locMod:IsA('ModuleScript') then
			return locMod
		end
		local requirers = {}
		pcall(function()
			if getrenv and type(getrenv().require) == 'function' then
				requirers[#requirers + 1] = getrenv().require
			end
		end)
		if type(require) == 'function' then
			requirers[#requirers + 1] = require
		end
		for _, req in ipairs(requirers) do
			local ok, mod = pcall(req, locMod)
			if ok and type(mod) == 'table' then
				return mod
			end
		end
		if type(decompile) == 'function' then
			local okd, src = pcall(decompile, locMod)
			if okd and type(src) == 'string' and src ~= '' then
				local compile = loadstring or load
				local fn, err = compile(src, 'Database.Locations')
				if fn then
					local okr, mod = pcall(fn)
					if okr and type(mod) == 'table' then
						return mod
					end
				end
			end
		end
		return nil
	end

	local function getLocationsFloors()
		local mod = requireLocationsData()
		if type(mod) ~= 'table' then
			return nil
		end
		return mod.floors or mod.Floors
	end

	local function entryLooksBetween(entry)
		if type(entry) ~= 'table' then
			return false
		end
		local pid = tonumber(entry.PlaceId or entry.placeId or entry.PlaceID)
		if pid == BETWEEN_PLACE_ID then
			return true
		end
		local name = entry.Name or entry.name or entry.DisplayName or entry.displayName
		if type(name) == 'string' then
			local key = string.gsub(string.lower(name), '[%p%s]+', '')
			if key == 'thebetween' or name == 'The Between' then
				return true
			end
		end
		return false
	end

	local function getBetweenLocation()
		local cachedIdx = tonumber(getgenv().SB2BetweenLocIndex)
		local cachedEntry = getgenv().SB2BetweenLocEntry
		if cachedIdx and type(cachedEntry) == 'table' then
			return cachedIdx, cachedEntry
		end

		local floors = getLocationsFloors()
		if type(floors) == 'table' then
			local maxIdx = 0
			for k in pairs(floors) do
				if type(k) == 'number' and k > maxIdx then
					maxIdx = k
				end
			end
			for i = 1, maxIdx do
				local entry = floors[i]
				if entryLooksBetween(entry) then
					getgenv().SB2BetweenLocIndex = i
					getgenv().SB2BetweenLocEntry = entry
					return i, entry
				end
			end
			for idx, entry in pairs(floors) do
				if entryLooksBetween(entry) then
					getgenv().SB2BetweenLocIndex = idx
					getgenv().SB2BetweenLocEntry = entry
					return idx, entry
				end
			end
		end

		getgenv().SB2BetweenLocIndex = BETWEEN_LOC_INDEX
		getgenv().SB2BetweenLocEntry = BETWEEN_FALLBACK_ENTRY
		return BETWEEN_LOC_INDEX, BETWEEN_FALLBACK_ENTRY
	end

	local function modeOrder(entry)
		local modes = entry and entry.Modes
		if type(modes) ~= 'table' then
			return { 'Normal', 'Hard', 'Elite' }
		end
		local list = {}
		for name, info in pairs(modes) do
			local order = 999
			if type(info) == 'table' then
				order = tonumber(info.LayoutOrder) or order
			end
			list[#list + 1] = { name = tostring(name), order = order }
		end
		table.sort(list, function(a, b)
			return a.order < b.order
		end)
		local names = {}
		for _, row in ipairs(list) do
			names[#names + 1] = row.name
		end
		return names
	end

	local function lobbyParties()
		return ReplicatedStorage:FindFirstChild('LobbyParties')
	end

	local function getLocalPartyFolder()
		local pid = LocalPlayer:GetAttribute('PartyID')
		if pid == nil then
			return nil
		end
		local root = lobbyParties()
		if not root then
			return nil
		end
		return root:FindFirstChild(tostring(pid))
	end

	local function firePartiesEvent(action, extra)
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

	local function invokeParties(...)
		local fn = ReplicatedStorage:FindFirstChild('Function')
		if not fn then
			return nil, 'no Function remote'
		end
		local args = { ... }
		local payload = { 'Parties', table.unpack(args) }
		local ok, result = pcall(function()
			return fn:InvokeServer('UniqueFloorTypes', payload)
		end)
		if not ok then
			return nil, tostring(result)
		end
		return result
	end

	local function waitForLocalParty(timeout)
		timeout = tonumber(timeout) or 8
		local t0 = os.clock()
		while os.clock() - t0 < timeout do
			local folder = getLocalPartyFolder()
			if folder then
				return folder
			end
			task.wait(0.08)
		end
		return getLocalPartyFolder()
	end

	local function isPartyLeader(party)
		party = party or getLocalPartyFolder()
		if not party then
			return false
		end
		return party:GetAttribute('Host') == LocalPlayer.UserId
	end

	local function partyUi()
		local pg = LocalPlayer:FindFirstChild('PlayerGui')
		if not pg then
			return nil
		end
		local ok, frame = pcall(function()
			return pg.CardinalUI.PlayerUI.MainFrame.TabFrames.Locations.Parties
		end)
		if ok then
			return frame
		end
		return nil
	end

	local function findStartButton()
		local ui = partyUi()
		if not ui then
			return nil
		end
		local ok, btn = pcall(function()
			return ui.InParty.Options.Buttons.Start
		end)
		if ok and btn and btn:IsA('GuiButton') then
			return btn
		end
		return nil
	end

	local function findModesButton()
		local ui = partyUi()
		if not ui then
			return nil
		end
		local ok, btn = pcall(function()
			return ui.InParty.Buttons.Modes
		end)
		if ok and btn and btn:IsA('GuiButton') then
			return btn
		end
		return nil
	end

	local function openBetweenPartyScreen()
		local locIdx, entry = getBetweenLocation()
		if not locIdx or not entry then
			return false, 'The Between not in Locations'
		end
		pcall(function()
			local pg = LocalPlayer:FindFirstChild('PlayerGui')
			local mf = pg and pg:FindFirstChild('CardinalUI') and pg.CardinalUI:FindFirstChild('PlayerUI')
			mf = mf and mf:FindFirstChild('MainFrame')
			if mf then
				mf.Visible = true
				local locTab = mf:FindFirstChild('Tabs') and mf.Tabs:FindFirstChild('Locations')
				if locTab and locTab:IsA('GuiButton') then
					fireGuiButton(locTab)
				end
			end
		end)
		local ok, err = pcall(function()
			local mod = ReplicatedStorage.CardinalClient.MainModule.Services.UI.Locations.Parties
			local req = (getrenv and getrenv().require) or require
			local parties = req(mod)
			if type(parties.Open) == 'function' then
				parties.Open(locIdx, entry)
			end
		end)
		if not ok then
			return false, tostring(err)
		end
		return true, locIdx
	end

	local function toggleUntilAttribute(attr, toggleAction, target, maxSteps)
		target = tostring(target)
		maxSteps = tonumber(maxSteps) or 5
		local party = getLocalPartyFolder()
		if not party then
			return false, 'not in a party'
		end
		if not isPartyLeader(party) then
			return false, 'party leader only'
		end
		if party:GetAttribute(attr) == target then
			return true
		end
		for _ = 1, maxSteps do
			local prev = party:GetAttribute(attr)
			-- One remote fire = one cycle step, same as the game's button. fireGuiButton runs the
			-- handler several ways per call, which skipped over the middle mode (Hard).
			firePartiesEvent(toggleAction)
			local deadline = os.clock() + 1.2
			while os.clock() < deadline do
				task.wait(0.06)
				party = getLocalPartyFolder()
				if not party then
					break
				end
				local now = party:GetAttribute(attr)
				if now == target then
					return true
				end
				if now ~= prev then
					break
				end
			end
			party = getLocalPartyFolder()
			if party and party:GetAttribute(attr) == target then
				return true
			end
		end
		party = getLocalPartyFolder()
		local cur = party and party:GetAttribute(attr)
		return cur == target, cur or 'no change'
	end

	local function getExistingBetweenParty()
		local party = getLocalPartyFolder()
		if not party then
			return nil
		end
		if tonumber(party:GetAttribute('PlaceId')) ~= BETWEEN_PLACE_ID then
			return nil
		end
		return party
	end

	local function ensureBetweenParty()
		local locIdx, entry = getBetweenLocation()
		if not locIdx then
			return nil, nil, 'The Between not in Locations'
		end
		local party = getExistingBetweenParty()
		if party then
			return party, entry, nil
		end
		party = getLocalPartyFolder()
		if party then
			if isPartyLeader(party) then
				firePartiesEvent('LeaveParty')
				task.wait(0.45)
			else
				return nil, entry, 'leave your current party first'
			end
		end
		openBetweenPartyScreen()
		task.wait(0.15)
		firePartiesEvent('CreateParty', locIdx)
		party = waitForLocalParty(10)
		if not party then
			local ui = partyUi()
			local createBtn = ui and ui:FindFirstChild('Options') and ui.Options:FindFirstChild('Buttons')
			createBtn = createBtn and createBtn:FindFirstChild('CreateParty')
			if createBtn and createBtn:IsA('GuiButton') then
				fireGuiButton(createBtn)
				party = waitForLocalParty(8)
			end
		end
		if not party then
			return nil, entry, 'CreateParty timed out — open Travel → The Between, then retry'
		end
		if not isPartyLeader(party) then
			return party, entry, 'joined existing party (not leader)'
		end
		return party, entry, nil
	end

	local function currentPartyMode()
		local party = getLocalPartyFolder()
		return party and party:GetAttribute('Mode')
	end

	local function readModesButtonLabel()
		local btn = findModesButton()
		local label = btn and btn:FindFirstChild('Label')
		if not (label and label:IsA('TextLabel')) then
			return nil
		end
		local t = tostring(label.Text or '')
		if t == 'Normal' or t == 'Hard' or t == 'Elite' then
			return t
		end
		return nil
	end

	local function readLobbyMode()
		local attr = currentPartyMode()
		local label = readModesButtonLabel()
		local wd = workspace:GetAttribute('WaveDefenseMode')
		-- Never "keep" Easy/Normal when Travel or last run already shows Hard/Elite.
		if label == 'Hard' or label == 'Elite' then
			return label
		end
		if attr == 'Hard' or attr == 'Elite' then
			return attr
		end
		if wd == 'Hard' or wd == 'Elite' then
			return wd
		end
		if type(attr) == 'string' and attr ~= '' then
			return attr
		end
		if type(label) == 'string' and label ~= '' then
			return label
		end
		if type(wd) == 'string' and wd ~= '' then
			return wd
		end
		return nil
	end

	local function startLooksPending()
		local btn = findStartButton()
		if btn then
			local label = btn:FindFirstChild('Label')
			if label and label:IsA('TextLabel') and label.Text ~= 'Start' then
				return true
			end
		end
		if LocalPlayer:GetAttribute('PartyID') == nil then
			return true
		end
		local wd = workspace:GetAttribute('WaveDefenseMode')
		if type(wd) == 'string' and wd ~= '' then
			return true
		end
		return false
	end

	local function tryStartBetweenParty(locIdx, requiredMode)
		if requiredMode and requiredMode ~= '' and currentPartyMode() ~= requiredMode then
			return false, ('refusing start — mode is %s, wanted %s'):format(tostring(currentPartyMode()), requiredMode)
		end
		-- Remote Start first. Opening the Travel UI here used to snap the
		-- displayed mode back to Normal/Auto and start that instead of Hard.
		local tries = {
			function()
				return invokeParties('Start')
			end,
			function()
				return invokeParties('Start', locIdx)
			end,
		}
		for _, fn in ipairs(tries) do
			if requiredMode and requiredMode ~= '' and currentPartyMode() ~= requiredMode then
				return false, ('mode lost before start (%s)'):format(tostring(currentPartyMode()))
			end
			local r = fn()
			if r == true or startLooksPending() then
				return true
			end
			task.wait(0.15)
			if startLooksPending() then
				return true
			end
		end
		openBetweenPartyScreen()
		task.wait(0.12)
		if requiredMode and requiredMode ~= '' and currentPartyMode() ~= requiredMode then
			return false, ('mode lost after opening UI (%s)'):format(tostring(currentPartyMode()))
		end
		local btn = findStartButton()
		if btn then
			local label = btn:FindFirstChild('Label')
			if label and label:IsA('TextLabel') and label.Text ~= 'Start' then
				return true
			end
			fireGuiButton(btn)
			for _ = 1, 12 do
				task.wait(0.1)
				if startLooksPending() then
					return true
				end
			end
		end
		return false, 'Start failed — use Travel → The Between → Start (must be party leader)'
	end

	local function readBetweenPartyState()
		local party = getExistingBetweenParty()
		if not party then
			return nil
		end
		return {
			mode = party:GetAttribute('Mode'),
			status = party:GetAttribute('Status'),
			leader = isPartyLeader(party),
		}
	end

	local function applyBetweenMode(mode)
		mode = tostring(mode or '')
		if mode == '' then
			return false, 'no mode selected'
		end
		local party, entry, err = ensureBetweenParty()
		if not party then
			return false, err or 'no party'
		end
		if err and err:find('not leader') then
			return false, err
		end
		if not isPartyLeader(party) then
			return false, 'party leader only'
		end
		-- CreateParty always lands on Normal (the default / "auto" mode). Wait for
		-- that attribute before cycling so ToggleMode is not eating the first step.
		local t0 = os.clock()
		while os.clock() - t0 < 2.5 do
			party = getLocalPartyFolder()
			if party and party:GetAttribute('Mode') ~= nil then
				break
			end
			task.wait(0.08)
		end
		local ok, modeErr = toggleUntilAttribute('Mode', 'ToggleMode', mode, 8)
		if not ok then
			return false, ('mode stuck at %s (wanted %s)'):format(tostring(modeErr), mode)
		end
		task.wait(0.2)
		local now = currentPartyMode()
		if now ~= mode then
			return false, ('mode drifted to %s (wanted %s)'):format(tostring(now), mode)
		end
		return true
	end

	local function startBetweenRun(opts)
		opts = type(opts) == 'table' and opts or {}
		local locIdx = select(1, getBetweenLocation())
		local keepLobby = opts.keepLobbySettings == true
		local mode = tostring(
			opts.mode or flattenOptionValue(Options.BetweenDifficulty and Options.BetweenDifficulty.Value) or ''
		)
		local wantPrivate = opts.private
		if wantPrivate == nil then
			local t = env.Toggles and env.Toggles.BetweenPrivate
			wantPrivate = type(t) == 'table' and t.Value == true
		end

		openBetweenPartyScreen()
		task.wait(0.12)
		local savedLobby = readLobbyMode() or readModesButtonLabel()

		local party, entry, err
		if keepLobby then
			party = getExistingBetweenParty()
			if not party then
				-- CreateParty always resets to Normal. Snapshot Travel's mode first, then restore.
				party, entry, err = ensureBetweenParty()
			end
		else
			party, entry, err = ensureBetweenParty()
		end
		if not party then
			return false, err or 'no party'
		end
		if err and err:find('not leader') then
			return false, err
		end
		if not isPartyLeader(party) then
			return false, 'party leader only'
		end

		if keepLobby then
			local restore = savedLobby
			local claimed = tostring(opts.mode or '')
			if claimed == 'Hard' or claimed == 'Elite' then
				if restore ~= 'Elite' then
					restore = claimed
				end
			elseif (not restore or restore == '' or restore == 'Normal') then
				local wd = workspace:GetAttribute('WaveDefenseMode')
				if wd == 'Hard' or wd == 'Elite' then
					restore = wd
				elseif claimed ~= '' then
					restore = claimed
				elseif readModesButtonLabel() then
					restore = readModesButtonLabel()
				end
			end
			if restore and restore ~= '' and currentPartyMode() ~= restore then
				local okMode, modeErr = applyBetweenMode(restore)
				if not okMode then
					return false, modeErr
				end
			end
			if restore and restore ~= '' and currentPartyMode() ~= restore then
				return false, ('keep lobby would start %s, Travel was %s'):format(tostring(currentPartyMode()), restore)
			end
		elseif mode ~= '' then
			local lastErr
			for _ = 1, 3 do
				local okMode, modeErr = applyBetweenMode(mode)
				if currentPartyMode() == mode then
					lastErr = nil
					break
				end
				lastErr = modeErr or ('mode is %s'):format(tostring(currentPartyMode()))
				task.wait(0.25)
			end
			if currentPartyMode() ~= mode then
				return false, lastErr or ('would start on %s, wanted %s'):format(tostring(currentPartyMode()), mode)
			end
		end

		if wantPrivate then
			local okStat, statErr = toggleUntilAttribute('Status', 'ToggleStatus', 'Private', 5)
			if not okStat then
				return false, ('status: %s'):format(tostring(statErr))
			end
		end

		if opts.start == false then
			return true
		end

		local lockMode
		if keepLobby then
			lockMode = savedLobby or currentPartyMode()
			local claimed = tostring(opts.mode or '')
			if claimed == 'Hard' or claimed == 'Elite' then
				lockMode = claimed
			elseif (lockMode == nil or lockMode == '' or lockMode == 'Normal') and (claimed ~= '') then
				lockMode = claimed
			end
		elseif mode ~= '' then
			lockMode = mode
		end
		if lockMode and currentPartyMode() ~= lockMode then
			return false, ('refusing start — mode is %s, wanted %s'):format(tostring(currentPartyMode()), lockMode)
		end

		return tryStartBetweenParty(locIdx, lockMode)
	end

	getgenv().SB2BetweenPartyState = readBetweenPartyState
	getgenv().SB2BetweenApplyMode = applyBetweenMode
	getgenv().SB2BetweenStartRun = startBetweenRun
	getgenv().SB2BetweenOpenPartyUi = openBetweenPartyScreen

	local function autoChainEnabled()
		-- Follow friend's party is the hands-off mode: it implies chaining your own runs
		-- (its own gate still stops chain while you're with friends).
		-- Only when Auto difficulty is on; otherwise Follow just waits for a friend party.
		if getgenv().SB2BetweenFollowActive == true and getgenv().SB2BetweenFollowOwnRuns == true then
			return true
		end
		local t = env.Toggles and env.Toggles.BetweenAutoChain
		return type(t) == 'table' and t.Value == true
	end

	local function readWaveDefenseWave()
		local names = { 'Wave', 'WaveNumber', 'CurrentWave', 'WaveIndex', 'Round' }
		for _, name in ipairs(names) do
			local v = workspace:GetAttribute(name)
			if typeof(v) == 'number' and v >= 1 then
				return math.floor(v)
			end
		end
		local wd = workspace:FindFirstChild('WaveDefenseStuff')
		if wd then
			for _, name in ipairs(names) do
				local v = wd:GetAttribute(name)
				if typeof(v) == 'number' and v >= 1 then
					return math.floor(v)
				end
			end
		end
		local pg = LocalPlayer:FindFirstChild('PlayerGui')
		if not pg then
			return nil
		end
		local scanned = 0
		for _, d in ipairs(pg:GetDescendants()) do
			scanned += 1
			if scanned > 4000 then
				break
			end
			if not d:IsA('TextLabel') or not d.Visible then
				continue
			end
			local raw = tostring(d.Text or '')
			if raw == '' then
				continue
			end
			local n = tonumber(raw:match('[Ww]ave%s*[:#%-]?%s*(%d+)'))
				or tonumber(raw:match('^(%d+)%s*$'))
			if n and n >= 1 and n <= 250 then
				return math.floor(n)
			end
		end
		return nil
	end

	local function normalizeUiText(raw)
		return string.lower(tostring(raw or ''):gsub('%s+', ' '):match('^%s*(.-)%s*$') or '')
	end

	local function uiTextBlob(root, maxNodes)
		if not root then
			return ''
		end
		maxNodes = tonumber(maxNodes) or 800
		local parts = {}
		local scanned = 0
		for _, d in ipairs(root:GetDescendants()) do
			scanned += 1
			if scanned > maxNodes then
				break
			end
			if not d:IsA('TextLabel') or not d.Visible then
				continue
			end
			local t = normalizeUiText(d.Text)
			if t ~= '' and #t < 80 then
				parts[#parts + 1] = t
			end
		end
		return table.concat(parts, ' ')
	end

	local function blobLooksLikeLobbyReturn(blob)
		if blob == '' then
			return false
		end
		if string.find(blob, 'teleporting back', 1, true) then
			return true
		end
		if string.find(blob, 'return to lobby', 1, true) then
			return true
		end
		if string.find(blob, 'returning to lobby', 1, true) then
			return true
		end
		if string.find(blob, 'back to lobby', 1, true) then
			return true
		end
		if string.find(blob, 'returned to lobby', 1, true) then
			return true
		end
		return false
	end

	local function scanLobbyReturnCountdown()
		for _, name in ipairs({
			'LobbyCountdown',
			'ReturnCountdown',
			'EndCountdown',
			'WaveDefenseEndCountdown',
			'TeleportBackCountdown',
		}) do
			local v = workspace:GetAttribute(name)
			if typeof(v) == 'number' and v > 0 then
				return true
			end
		end
		local pg = LocalPlayer:FindFirstChild('PlayerGui')
		if not pg then
			return false
		end
		local cardinal = pg:FindFirstChild('CardinalUI')
		local popups = cardinal
			and cardinal:FindFirstChild('PlayerUI')
			and cardinal.PlayerUI:FindFirstChild('Popups')
		if popups then
			for _, popup in ipairs(popups:GetChildren()) do
				if popup:IsA('GuiObject') and popup.Visible ~= false then
					local blob = uiTextBlob(popup, 500)
					if string.find(blob, 'teleporting back', 1, true) and string.find(blob, 'in%s+%d+', 1, false) then
						return true
					end
					if blobLooksLikeLobbyReturn(blob) and string.find(blob, 'in%s+%d+', 1, false) then
						return true
					end
				end
			end
		end
		local lines = {}
		local scanned = 0
		for _, d in ipairs(pg:GetDescendants()) do
			scanned += 1
			if scanned > 5000 then
				break
			end
			if not (d:IsA('TextLabel') or d:IsA('TextButton')) or not d.Visible then
				continue
			end
			local t = normalizeUiText(d.Text)
			if t == '' or #t > 96 then
				continue
			end
			lines[#lines + 1] = t
		end
		local blob = table.concat(lines, ' ')
		if string.find(blob, 'teleporting back', 1, true) and string.find(blob, 'in%s+%d+', 1, false) then
			return true
		end
		return false
	end

	local function isBetweenRunActive()
		if not workspace:FindFirstChild('WaveDefenseStuff') then
			return false
		end
		return BETWEEN_RUN_PLACE_IDS[tonumber(game.PlaceId)] == true
	end

	local function isBetweenLobbyIdle()
		local pid = tonumber(game.PlaceId)
		if pid == BETWEEN_PLACE_ID then
			return workspace:FindFirstChild('WaveDefenseStuff') == nil
		end
		-- Wipe "Return to Lobby" and the end-of-run timer land in the Between overworld, not
		-- the WD instance. Counts as the lobby while a run finished in the last 10 minutes.
		if pid == 540240728 then
			if getgenv().SB2BetweenWipeRestart == true then
				return true
			end
			if type(readfile) == 'function' then
				local ok, raw = pcall(readfile, acctPath('PlayerTools/_between_chain_pending.txt'))
				local at = ok and tonumber(raw) or 0
				if at > 0 and os.time() - at <= 600 then
					return true
				end
			end
		end
		return false
	end

	local function findLivingRewardChest()
		local mobs = workspace:FindFirstChild('Mobs')
		if not mobs then
			return nil
		end
		for _, mob in ipairs(mobs:GetChildren()) do
			if mob:GetAttribute('Died') == true then
				continue
			end
			local lower = string.lower(tostring(mob.Name or ''))
			local isChest = (string.find(lower, 'reward', 1, true) and string.find(lower, 'chest', 1, true))
				or string.find(lower, 'rewardchest', 1, true)
				or mob:GetAttribute('RewardChest') == true
				or mob:GetAttribute('Reward') == true
			if not isChest then
				continue
			end
			local entity = mob:FindFirstChild('Entity')
			if not entity then
				return mob
			end
			if entity:GetAttribute('Died') == true then
				continue
			end
			local health = entity:FindFirstChild('Health')
			if not health then
				return mob
			end
			local ok, hp = pcall(function()
				return health.Value
			end)
			if ok and type(hp) == 'number' and hp > 0 then
				return mob
			end
		end
		return nil
	end

	local function findLivingRubricatus()
		local mobs = workspace:FindFirstChild('Mobs')
		if not mobs then
			return nil
		end
		for _, mob in ipairs(mobs:GetChildren()) do
			if mob:GetAttribute('Died') == true then
				continue
			end
			if not string.find(string.lower(tostring(mob.Name or '')), 'rubricatus', 1, true) then
				continue
			end
			local entity = mob:FindFirstChild('Entity')
			local health = entity and entity:FindFirstChild('Health')
			if entity and entity:GetAttribute('Died') == true then
				continue
			end
			local ok, hp = pcall(function()
				return health and health.Value
			end)
			if not health or (ok and type(hp) == 'number' and hp > 0) then
				return mob
			end
		end
		return nil
	end

	-- Wave 100 → Rubricatus seen → Rubricatus gone while the reward chest is up → 15s → hop.
	-- Rubricatus reappearing (stream flicker) restarts the countdown.
	local function chainLog(...)
		local parts = {}
		for i = 1, select('#', ...) do
			parts[#parts + 1] = tostring((select(i, ...)))
		end
		local line = ('%s place=%s wave=%s  %s\n'):format(os.date('%Y-%m-%d %H:%M:%S'), tostring(game.PlaceId),
			tostring(workspace:GetAttribute('Wave')), table.concat(parts, ' '))
		pcall(function()
			if type(appendfile) == 'function' and isfile and isfile(acctPath('PlayerTools/_chain_log.txt')) then
				appendfile(acctPath('PlayerTools/_chain_log.txt'), line)
			else
				writefile(acctPath('PlayerTools/_chain_log.txt'), line)
			end
		end)
	end
	getgenv().SB2BetweenChainLog = chainLog
	local BETWEEN_CHAIN_DELAY = 15
	local chainWave100 = false
	-- Kept in getgenv so a PlayerTools reload after Rubricatus dies doesn't forget he was seen.
	local chainSawRubricatus = getgenv().SB2BetweenChainSawRub == true
	local chainReadyAt = 0

	local function resetChestWatch()
		chainWave100 = false
		chainSawRubricatus = false
		getgenv().SB2BetweenChainSawRub = false
		chainReadyAt = 0
	end

	local function betweenRunReadyToChain()
		if not isBetweenRunActive() then
			resetChestWatch()
			return false
		end
		if not chainWave100 then
			local wave = readWaveDefenseWave()
			if not wave or wave < BETWEEN_AUTO_WAVE_MIN then
				return false
			end
			chainWave100 = true
		end
		if findLivingRubricatus() then
			if not chainSawRubricatus then
				chainLog('rubricatus seen')
			end
			chainSawRubricatus = true
			getgenv().SB2BetweenChainSawRub = true
			chainReadyAt = 0
			return false
		end
		if not chainSawRubricatus then
			return false
		end
		if chainReadyAt == 0 then
			if not findLivingRewardChest() then
				local now = os.clock()
				if now - (tonumber(getgenv().SB2ChainNoChestLogAt) or 0) > 10 then
					getgenv().SB2ChainNoChestLogAt = now
					chainLog('rubricatus gone, waiting for reward chest')
				end
				return false
			end
			chainReadyAt = os.clock()
			chainLog('reward chest seen, starting in', BETWEEN_CHAIN_DELAY, 's')
		end
		-- Wait for the chest to actually break (the dodge walks you over to it), so the next
		-- run never starts with the reward unclaimed. 45s cap in case it can't be reached.
		local age = os.clock() - chainReadyAt
		if age < BETWEEN_CHAIN_DELAY then
			return false
		end
		if findLivingRewardChest() and age < (tonumber(getgenv().SB2BetweenChestWaitCap) or 45) then
			return false
		end
		return true
	end

	-- The finished-run marker lives on disk too: the lobby return can land in a fresh
	-- server where getgenv() is empty. Stale markers expire so a later join never auto-starts.
	local CHAIN_MARKER_PATH = acctPath('PlayerTools/_between_chain_pending.txt')
	local WIPE_MARKER_PATH = acctPath('PlayerTools/_between_wipe_mode.txt')
	local CHAIN_MARKER_MAX_AGE = 600

	local function markRunFinished()
		getgenv().SB2BetweenAutoChainPending = true
		if type(writefile) == 'function' then
			pcall(writefile, CHAIN_MARKER_PATH, tostring(os.time()))
		end
	end

	local function clearRunFinished()
		getgenv().SB2BetweenAutoChainPending = false
		getgenv().SB2BetweenWipeRestart = false
		getgenv().SB2BetweenWipeMode = nil
		if type(writefile) == 'function' then
			pcall(writefile, CHAIN_MARKER_PATH, '0')
			pcall(writefile, WIPE_MARKER_PATH, '')
		end
	end

	local function persistWipeMode(mode)
		getgenv().SB2BetweenWipeRestart = true
		if type(mode) == 'string' and mode ~= '' then
			getgenv().SB2BetweenWipeMode = mode
		end
		if type(writefile) == 'function' then
			pcall(writefile, WIPE_MARKER_PATH, ('%s\n%d'):format(tostring(mode or ''), os.time()))
		end
	end

	local function restoreWipeFromDisk()
		if getgenv().SB2BetweenWipeRestart == true then
			return true
		end
		if type(readfile) ~= 'function' then
			return false
		end
		local ok, raw = pcall(readfile, WIPE_MARKER_PATH)
		if not ok or type(raw) ~= 'string' or raw == '' then
			return false
		end
		local mode, at = string.match(raw, '^(%a+)\n(%d+)')
		at = tonumber(at)
		if (mode == 'Hard' or mode == 'Elite' or mode == 'Normal')
			and at
			and os.time() - at <= CHAIN_MARKER_MAX_AGE
		then
			getgenv().SB2BetweenWipeRestart = true
			getgenv().SB2BetweenWipeMode = mode
			return true
		end
		return false
	end
	restoreWipeFromDisk()

	local function runFinishedPending()
		if getgenv().SB2BetweenAutoChainPending == true then
			return true
		end
		if type(readfile) ~= 'function' then
			return false
		end
		local ok, raw = pcall(readfile, CHAIN_MARKER_PATH)
		local at = ok and tonumber(raw) or 0
		if at > 0 and os.time() - at <= CHAIN_MARKER_MAX_AGE then
			getgenv().SB2BetweenAutoChainPending = true
			return true
		end
		return false
	end

	local autoChainBusy = false
	local autoChainLastAt = 0

	local function payToReviveVisible()
		local frame
		pcall(function()
			frame = LocalPlayer.PlayerGui.CardinalUI.PlayerUI.Popups.WaveDefense.ReviveFrame
		end)
		if not (frame and frame.Visible) then
			return false
		end
		local btn = frame:FindFirstChild('Options') and frame.Options:FindFirstChild('Revive')
		if not (btn and btn:IsA('TextButton') and btn.Visible) then
			return false
		end
		return tostring(btn.Text or '') == 'Pay to revive?'
	end

	local followBlocksChain -- set below (follow-friend mode)

	local function tryAutoChainStart()
		-- Chain off = never start a run. Wipe / Pay-to-revive used to ignore the toggle and eat keys.
		if not autoChainEnabled() then
			return
		end
		-- Follow-friend mode: never start from inside someone else's party, and let the
		-- follow logic own lobby starts (it checks for a friend's party first).
		if followBlocksChain and followBlocksChain() then
			local now = os.clock()
			if now - (tonumber(getgenv().SB2ChainBlockLogAt) or 0) > 10 then
				getgenv().SB2ChainBlockLogAt = now
				chainLog('blocked by follow')
			end
			return
		end
		local pay = payToReviveVisible()
		local wipe = getgenv().SB2BetweenWipeRestart == true or pay
		if autoChainBusy then
			return
		end
		if pay or wipe then
			-- Start from the death screen. Do not Return to Lobby.
		elseif not isBetweenLobbyIdle() and not betweenRunReadyToChain() then
			return
		end
		local now = os.clock()
		local cooldown = BETWEEN_AUTO_START_COOLDOWN
		if pay or wipe then
			cooldown = 1.2
		elseif getgenv().SB2BetweenAutoChainPending == true then
			cooldown = BETWEEN_AUTO_RETRY_COOLDOWN
		end
		if now - autoChainLastAt < cooldown then
			return
		end
		autoChainBusy = true
		task.spawn(function()
			task.wait(0.25)
			local startFn = getgenv().SB2BetweenStartRun or startBetweenRun
			-- Always the difficulty you selected (Follow's own-run difficulty when Follow is on,
			-- else Between difficulty) — never whatever the last run / lobby happened to be.
			local modeFn = getgenv().SB2BetweenChainMode
			local mode = type(modeFn) == 'function' and modeFn() or nil
			if type(mode) ~= 'string' or mode == '' then
				mode = tostring(flattenOptionValue(Options.BetweenDifficulty and Options.BetweenDifficulty.Value) or 'Normal')
			end
			chainLog('start attempt', mode, wipe and 'wipe' or 'chain')
			local ok, err = startFn({
				keepLobbySettings = false,
				mode = mode,
			})
			chainLog('start result', tostring(ok), tostring(err))
			autoChainLastAt = os.clock()
			autoChainBusy = false
			if ok then
				getgenv().SB2BetweenWipeRestart = false
				getgenv().SB2BetweenWipeMode = nil
				clearRunFinished()
				resetChestWatch()
				Library:Notify(
					('Between %s — %s starting…'):format(
						wipe and 'wipe restart' or 'auto-chain',
						tostring(currentPartyMode() or 'run')
					),
					4
				)
			elseif err then
				warn('[BetweenParty] auto-chain: ', err)
			end
		end)
	end

	-- ── Follow friend's party ───────────────────────────────────────────────
	-- Between lobby: if a followed player hosts a joinable Between party, join it; never
	-- start a run from the lobby (no friend party = just wait). In a run inside someone
	-- else's party, auto-chain stays quiet (no wave-100 hop, no wipe restart).
	-- Any other floor (e.g. floor 6): start a Between run on the selected difficulty.
	local FOLLOW_FILE = acctPath('PlayerTools/between_follow.json')
	local FOLLOW_FLOOR_SETTLE = 8 -- seconds on a floor before it starts (time to switch it off)
	local FOLLOW_START_COOLDOWN = 30
	local FOLLOW_JOIN_RETRY = 10 -- seconds between party checks / join attempts, no limit
	local followCfg = { on = false, names = '', fallback = 'Normal', autoDiff = true, shardTarget = 235, eliteFirst = true }
	pcall(function()
		if type(isfile) == 'function' and isfile(FOLLOW_FILE) then
			local d = game:GetService('HttpService'):JSONDecode(readfile(FOLLOW_FILE))
			if type(d) == 'table' then
				followCfg.on = d.on == true
				followCfg.names = type(d.names) == 'string' and d.names or ''
				followCfg.fallback = type(d.fallback) == 'string' and d.fallback or 'Normal'
				if d.autoDiff ~= nil then
					followCfg.autoDiff = d.autoDiff == true
				end
				followCfg.shardTarget = tonumber(d.shardTarget) or 235
				if d.eliteFirst ~= nil then
					followCfg.eliteFirst = d.eliteFirst == true
				end
			end
		end
	end)
	local function saveFollowCfg()
		pcall(function()
			writefile(FOLLOW_FILE, game:GetService('HttpService'):JSONEncode(followCfg))
		end)
	end

	local function followEnabled()
		local t = env.Toggles and env.Toggles.BetweenFollowFriend
		if type(t) == 'table' then
			return t.Value == true
		end
		return followCfg.on == true
	end
	-- Auto difficulty: Normal until you hold N Normal Shards, then Hard (Hard needs no keys).
	-- Drops back to Normal by itself if you spend the shards below N.
	local function autoDiffOn()
		local t = env.Toggles and env.Toggles.BetweenAutoDifficulty
		if type(t) == 'table' then
			return t.Value == true
		end
		return followCfg.autoDiff == true
	end
	local function shardTarget()
		local o = Options and Options.BetweenShardTarget
		local n = o and tonumber(o.Value)
		return n or tonumber(followCfg.shardTarget) or 235
	end
	local function normalShardCount()
		local total = 0
		pcall(function()
			local inv = ReplicatedStorage.Profiles[LocalPlayer.Name].Inventory
			for _, it in ipairs(inv:GetChildren()) do
				if it.Name == 'Normal Shard' then
					local c = it:FindFirstChild('Count')
					total += (c and tonumber(c.Value)) or 1
				end
			end
		end)
		return total
	end
	local function eliteKeyCount()
		local n = 0
		pcall(function()
			n = tonumber(ReplicatedStorage.Profiles[LocalPlayer.Name]:GetAttribute('Elite_Wave_Keys')) or 0
		end)
		return n
	end
	local function eliteFirstOn()
		local t = env.Toggles and env.Toggles.BetweenEliteFirst
		if type(t) == 'table' then
			return t.Value == true
		end
		return followCfg.eliteFirst == true
	end
	-- Elite while you have Elite Wave Keys, then Normal until N Normal Shards, then Hard.
	local function autoDiffMode()
		if eliteFirstOn() and eliteKeyCount() > 0 then
			return 'Elite'
		end
		-- Normal dropped from the cycle (all Normal Shards collected): Elite while keys last, then Hard.
		return 'Hard'
	end
	getgenv().SB2BetweenEliteKeys = eliteKeyCount
	getgenv().SB2BetweenNormalShards = normalShardCount

	local function followFallbackMode()
		if autoDiffOn() then
			return autoDiffMode()
		end
		-- No Auto difficulty: the Between difficulty dropdown (same as chain uses).
		local v = flattenOptionValue(Options and Options.BetweenDifficulty and Options.BetweenDifficulty.Value)
		if type(v) ~= 'string' or v == '' then
			v = followCfg.fallback
		end
		return (v == 'Hard' or v == 'Elite') and v or 'Normal'
	end
	getgenv().SB2BetweenChainMode = function()
		if autoDiffOn() then
			return autoDiffMode()
		end
		if followEnabled() then
			return followFallbackMode()
		end
		return tostring(flattenOptionValue(Options and Options.BetweenDifficulty and Options.BetweenDifficulty.Value) or 'Normal')
	end

	local function followNameSet()
		local o = Options and Options.BetweenFollowNames
		local raw = o and o.Value
		if type(raw) ~= 'string' then
			raw = followCfg.names
		end
		local set, any = {}, false
		for part in string.gmatch(string.lower(raw or ''), '[^,%s]+') do
			set[part] = true
			any = true
		end
		return set, any
	end

	local friendCache = {}
	local function isFollowed(userId)
		userId = tonumber(userId)
		if not userId or userId == LocalPlayer.UserId then
			return false
		end
		-- Anyone on your PlayerTools whitelist counts as a friend for following.
		local wl = getgenv().SB2IsOwnAltId
		if type(wl) == 'function' then
			local ok, res = pcall(wl, userId)
			if ok and res then
				return true
			end
		end
		local set, any = followNameSet()
		local plr = Players:GetPlayerByUserId(userId)
		if any then
			if not plr then
				return false
			end
			return set[string.lower(plr.Name)] == true or set[string.lower(plr.DisplayName)] == true
		end
		-- Whitelist only now (plus the names list if you fill it): Roblox friends no longer count.
		return false
	end

	local function partyMemberCount(party)
		local n = 0
		for k, v in pairs(party:GetAttributes()) do
			if v == true and tonumber(k) then
				n += 1
			end
		end
		return n
	end

	-- In a party someone else hosts (friend or not): never start anything ourselves.
	local function inOthersParty()
		local party = getLocalPartyFolder()
		if not party then
			return false, nil
		end
		local host = tonumber(party:GetAttribute('Host'))
		return host ~= nil and host ~= LocalPlayer.UserId, party
	end

	-- In a party with anyone else in it (you host or they do): hands off entirely.
	local function inGroupParty()
		local party = getLocalPartyFolder()
		if not party then
			return false, nil
		end
		return partyMemberCount(party) >= 2, party
	end

	-- Party with at least one followed player in it (host or member).
	local function partyHasFriend(party)
		if not party then
			return false
		end
		for k, v in pairs(party:GetAttributes()) do
			if v == true and tonumber(k) and isFollowed(tonumber(k)) then
				return true
			end
		end
		return isFollowed(party:GetAttribute('Host'))
	end
	local function withFriends()
		local party = getLocalPartyFolder()
		return party ~= nil and partyHasFriend(party), party
	end
	local function anyFollowedInServer()
		for _, plr in ipairs(Players:GetPlayers()) do
			if isFollowed(plr.UserId) then
				return true
			end
		end
		return false
	end

	local function findFriendParty()
		local root = lobbyParties()
		if not root then
			return nil
		end
		local best, bestN = nil, -1
		for _, party in ipairs(root:GetChildren()) do
			if tonumber(party:GetAttribute('PlaceId')) == BETWEEN_PLACE_ID
				and isFollowed(party:GetAttribute('Host'))
			then
				local status = tostring(party:GetAttribute('Status') or '')
				local limit = tonumber(party:GetAttribute('PartyLimit')) or 8
				local n = partyMemberCount(party)
				if status ~= 'Private' and n < limit and n > bestN then
					best, bestN = party, n
				end
			end
		end
		return best
	end

	local function inBetweenLobby()
		return tonumber(game.PlaceId) == BETWEEN_PLACE_ID and workspace:FindFirstChild('WaveDefenseStuff') == nil
	end

	-- Seconds a friend's party has to be gone before auto-chain may start a run of yours.
	local FOLLOW_CHAIN_GRACE = 20
	local FOLLOW_LOBBY_WAIT = 60 -- lobby: wait this long for a friend party before going solo
	local friendPartySeenAt = -math.huge

	followBlocksChain = function()
		if not followEnabled() then
			return false
		end
		-- In a party with your friends: never start anything (they / the host do).
		if (withFriends()) then
			return true
		end
		-- Someone else's party without friends: follow leaves it first; don't start meanwhile.
		if (inOthersParty()) then
			return true
		end
		-- A friend's party is up (or was, moments ago): join it instead of starting your own.
		if os.clock() - friendPartySeenAt < FOLLOW_CHAIN_GRACE then
			return true
		end
		-- Lobby starts are done by the follow logic (it applies the selected difficulty).
		if inBetweenLobby() then
			return true
		end
		-- F1 / any floor outside a run: Follow's 60s friend-party window decides, not chain.
		if not isBetweenRunActive() then
			return true
		end
		return false
	end
	getgenv().SB2BetweenFollowBlocksChain = followBlocksChain

	local follow = { noFriendSince = nil, lastJoinAt = 0, joinParty = nil, joinTries = 0, lastStartAt = 0, busy = false, status = 'off' }
	getgenv().SB2BetweenFollowState = follow
	local followLabel

	local function setFollowStatus(text)
		if follow.status == text then
			return
		end
		follow.status = text
		if followLabel and type(followLabel.SetText) == 'function' then
			pcall(followLabel.SetText, followLabel, 'Follow: ' .. text)
		end
	end

	local function startSelectedRun(label)
		local now = os.clock()
		if follow.busy or now - follow.lastStartAt < FOLLOW_START_COOLDOWN then
			return
		end
		follow.busy = true
		follow.lastStartAt = now
		local mode = followFallbackMode()
		setFollowStatus('starting ' .. mode .. ' run…')
		task.spawn(function()
			-- Last look right before starting: a friend's party made just now still wins.
			if findFriendParty() or (withFriends()) then
				follow.busy = false
				return
			end
			local startFn = getgenv().SB2BetweenStartRun or startBetweenRun
			local ok, err = startFn({ keepLobbySettings = false, mode = mode })
			follow.busy = false
			if ok then
				clearRunFinished()
				resetChestWatch()
				Library:Notify(('Follow: %s — starting %s run…'):format(label, mode), 4)
			else
				setFollowStatus('start failed: ' .. tostring(err))
				warn('[BetweenParty] follow start: ', err)
			end
		end)
	end

	local function followTick()
		getgenv().SB2BetweenFollowActive = followEnabled()
		-- Follow only starts / chains runs of its own when Auto difficulty is on.
		getgenv().SB2BetweenFollowOwnRuns = true
		if not followEnabled() then
			follow.noFriendSince = nil
			setFollowStatus('off')
			return
		end
		local now = os.clock()
		local pid = tonumber(game.PlaceId)
		-- The Between overworld (where the end-of-run timer drops you) has no WaveDefenseStuff:
		-- treat it like any other floor / lobby, not like being inside a run.
		local inBetweenPlace = pid == BETWEEN_PLACE_ID
			or (BETWEEN_RUN_PLACE_IDS[pid] == true and workspace:FindFirstChild('WaveDefenseStuff') ~= nil)

		-- 1. In a party with your friends: hands off until the next run is started.
		local friendsHere, myParty = withFriends()
		if friendsHere then
			follow.noFriendSince = nil
			follow.joinParty, follow.joinTries = nil, 0
			local host = myParty and Players:GetPlayerByUserId(tonumber(myParty:GetAttribute('Host')) or 0)
			setFollowStatus(('with friends in %s party — waiting for the next run'):format(host and (host.Name .. "'s") or 'a'))
			return
		end
		-- In someone else's party: their host starts, just wait.
		if (inOthersParty()) then
			follow.noFriendSince = nil
			setFollowStatus("in someone's party — waiting for the next run")
			return
		end

		-- 2. A friend's party exists in this server (lobby OR mid-run): join it.
		local fp = findFriendParty()
		if fp then
			friendPartySeenAt = now
			follow.noFriendSince = nil
			if follow.joinParty ~= fp.Name then
				follow.joinParty, follow.joinTries = fp.Name, 0
				follow.lastJoinAt = -math.huge -- new party: try right away
			end
			if now - follow.lastJoinAt < FOLLOW_JOIN_RETRY then
				return
			end
			follow.lastJoinAt = now
			follow.joinTries += 1
			local host = Players:GetPlayerByUserId(tonumber(fp:GetAttribute('Host')) or 0)
			setFollowStatus(("joining %s's party… (try %d, every %ds)"):format(host and host.Name or '?', follow.joinTries, FOLLOW_JOIN_RETRY))
			task.spawn(function()
				if getLocalPartyFolder() then
					firePartiesEvent('LeaveParty') -- only ever a party of just you here
					task.wait(0.5)
				end
				firePartiesEvent('JoinParty', fp.Name)
			end)
			return
		end
		follow.joinParty, follow.joinTries = nil, 0

		-- 3. No friend party to join.
		-- Without Auto difficulty, Follow never starts a run itself: it waits (on whatever
		-- floor you're on, or the Between lobby) and joins as soon as a friend makes a party.
		if not inBetweenPlace then
			-- Another floor (e.g. floor 6): start a Between run on the selected difficulty.
			follow.noFriendSince = follow.noFriendSince or now
			-- Same 60s window as the Between lobby: a friend's party made in that time wins.
			local left = FOLLOW_LOBBY_WAIT - (now - follow.noFriendSince)
			if left > 0 then
				setFollowStatus(('lobby — no friend party, starting %s run in %ds'):format(followFallbackMode(), math.ceil(left)))
				return
			end
			startSelectedRun('from another floor')
			return
		end
		if not inBetweenLobby() then
			follow.noFriendSince = nil
			if now - friendPartySeenAt >= FOLLOW_CHAIN_GRACE then
				setFollowStatus('own run — chaining (joins a friend party if one shows up)')
			else
				setFollowStatus('in run — watching for a friend party')
			end
			return
		end
		-- Between lobby, no friend party for a full minute: start your own run.
		follow.noFriendSince = follow.noFriendSince or now
		local grace = FOLLOW_LOBBY_WAIT
		local left = grace - (now - follow.noFriendSince)
		if left > 0 then
			setFollowStatus(('no friend party — starting %s run in %ds'):format(followFallbackMode(), math.ceil(left)))
			return
		end
		startSelectedRun('no friend party')
	end

	local RunService = game:GetService('RunService')
	if getgenv().SB2BetweenAutoChainConn then
		pcall(function()
			getgenv().SB2BetweenAutoChainConn:Disconnect()
		end)
		getgenv().SB2BetweenAutoChainConn = nil
	end
	local autoChainAccum = 0
	local lastRunMarkerTouch = 0
	local lobbyReadySince = nil
	-- Grace period in the lobby so the chain can be switched off before it fires.
	local BETWEEN_LOBBY_SETTLE = 6
	getgenv().SB2BetweenAutoChainConn = RunService.Heartbeat:Connect(function(dt)
		autoChainAccum += dt
		if autoChainAccum < 0.45 then
			return
		end
		autoChainAccum = 0

		-- End of run: only the reward chest is left (Rubricatus dead, nothing else spawns).
		-- Killaura only wakes up on a mob spawn, so it can sit there unhit: restart killaura and
		-- hit the chest directly until it breaks.
		pcall(function()
			if not isBetweenRunActive() then
				return
			end
			local chest = findLivingRewardChest()
			if not chest then
				return
			end
			local mobs = workspace:FindFirstChild('Mobs')
			for _, m in ipairs(mobs and mobs:GetChildren() or {}) do
				if m ~= chest and m:GetAttribute('Died') ~= true then
					local lower = string.lower(m.Name)
					if not string.find(lower, 'chest', 1, true) then
						local ent = m:FindFirstChild('Entity')
						local hp = ent and ent:FindFirstChild('Health')
						if ent and ent:GetAttribute('Died') ~= true and (not hp or (tonumber(hp.Value) or 0) > 0) then
							return -- a real mob is still alive; killaura is busy anyway
						end
					end
				end
			end
			local g = getgenv()
			local now = os.clock()
			if now - (tonumber(g.SB2ChestHitAt) or 0) < 0.4 then
				return
			end
			g.SB2ChestHitAt = now
			if type(g.SB2KillauraNeedsStart) == 'function' and g.SB2KillauraNeedsStart()
				and type(g.SB2StartKillauraLoop) == 'function'
			then
				pcall(g.SB2StartKillauraLoop)
			end
			local rs = g.SB2RequiredServices
			local deal = rs and rs.Combat and rs.Combat.DealDamage
			local okHit = false
			if type(deal) == 'function' then
				okHit = pcall(deal, chest, nil)
			end
			if now - (tonumber(g.SB2ChestHitLogAt) or 0) > 3 then
				g.SB2ChestHitLogAt = now
				local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild('HumanoidRootPart')
				local okP, piv = pcall(function() return chest:GetPivot().Position end)
				local ent = chest:FindFirstChild('Entity')
				local hp = ent and ent:FindFirstChild('Health')
				chainLog('chest hit', tostring(okHit), 'hp', hp and tostring(hp.Value) or '?',
					'dist', (hrp and okP) and ('%.0f'):format((piv - hrp.Position).Magnitude) or '?')
			end
		end)

		local okF, errF = pcall(followTick)
		if not okF then
			warn('[BetweenParty] follow: ', errF)
		end

		-- Follow friend's party: when the run is won, don't start the next run in here; let the
		-- game's own end-of-run timer send you back to the lobby. In the lobby the follow logic
		-- joins a friend's party if one shows up within 60s, otherwise (Auto difficulty) starts yours.
		-- Was a friend (whitelisted, not one of your own accounts) in this run at any point?
		-- Only then is the lobby trip worth it; a solo run chains straight into the next one.
		if followEnabled() and isBetweenRunActive() then
			local OWN = { [105008790] = true, [58534583] = true, [5629930206] = true, [2948744565] = true,
				[2567665744] = true }
			for _, plr in ipairs(Players:GetPlayers()) do
				if not OWN[plr.UserId] and isFollowed(plr.UserId) then
					if getgenv().SB2BetweenFriendInRun ~= true then
						chainLog('friend in this run:', plr.Name)
					end
					getgenv().SB2BetweenFriendInRun = true
					break
				end
			end
		elseif not isBetweenRunActive() then
			getgenv().SB2BetweenFriendInRun = nil
		end
		if followEnabled() and isBetweenRunActive() and betweenRunReadyToChain()
			and getgenv().SB2BetweenFriendInRun == true
		then
			if not getgenv().SB2BetweenWaitReturnNoted then
				getgenv().SB2BetweenWaitReturnNoted = true
				Library:Notify('Follow: run done — waiting for the lobby timer…', 4)
			end
			return
		end

		local chain = autoChainEnabled()
		if not chain then
			if getgenv().SB2BetweenWipeRestart == true
				or getgenv().SB2BetweenAutoChainPending == true
				or getgenv().SB2BetweenWipeMode ~= nil
			then
				clearRunFinished()
			end
			return
		end
		local wipe = getgenv().SB2BetweenWipeRestart == true
		if isBetweenRunActive() then
			local lives = LocalPlayer:GetAttribute('Lives')
			if typeof(lives) == 'number' and lives > 0 and wipe then
				clearRunFinished()
				wipe = false
			elseif payToReviveVisible() then
				local mode = workspace:GetAttribute('WaveDefenseMode') or currentPartyMode()
				if type(mode) == 'string' and mode ~= '' then
					persistWipeMode(mode)
				else
					persistWipeMode(getgenv().SB2BetweenWipeMode or 'Hard')
				end
				if getgenv().SB2BetweenAutoChainPending ~= true then
					markRunFinished()
				end
				wipe = true
				tryAutoChainStart()
			end
		end

		-- Wipe: Pay to revive? → same startBetweenRun as auto-chain (no lobby).
		-- Success chain: wave-100 chest, or lobby marker if that start misses.
		if isBetweenRunActive() then
			lobbyReadySince = nil
			if os.time() - lastRunMarkerTouch >= 15 and type(writefile) == 'function' then
				lastRunMarkerTouch = os.time()
				pcall(writefile, CHAIN_MARKER_PATH, tostring(os.time()))
			end
			if chain and betweenRunReadyToChain() then
				if getgenv().SB2BetweenAutoChainPending ~= true then
					markRunFinished()
				end
				tryAutoChainStart()
			end
		elseif isBetweenLobbyIdle() and (wipe or runFinishedPending()) then
			lobbyReadySince = lobbyReadySince or os.clock()
			local settle = wipe and 3 or BETWEEN_LOBBY_SETTLE
			if os.clock() - lobbyReadySince >= settle then
				tryAutoChainStart()
			end
		else
			lobbyReadySince = nil
		end
	end)

	local _, betweenEntry = getBetweenLocation()
	local modeValues = modeOrder(betweenEntry)
	local skipUi = env.reloadLogicOnly == true

	if skipUi then
		return
	end

	WdBox:AddDropdown('BetweenDifficulty', {
		Text = 'Between difficulty',
		Values = modeValues,
		Default = table.find(modeValues, 'Hard') and 'Hard' or modeValues[1],
		AllowNull = false,
		Tooltip = 'Normal / Hard / Elite. Steps the party mode one ToggleMode at a time until it matches.',
	})

	WdBox:AddToggle('BetweenPrivate', {
		Text = 'Private party',
		Default = false,
		Tooltip = 'Before start, cycle party status to Private (leader only). Off = keep your current Public/Private setting.',
	})

	WdBox:AddToggle('BetweenAutoChain', {
		Text = 'Auto chain Between runs',
		Default = false,
		Tooltip = 'On: after wave 100 (and on wipe / Pay to revive) start the next run. Off: never auto-start — including death — so keys are not spent.',
	})

	WdBox:AddToggle('BetweenFollowFriend', {
		Text = "Follow friend's party",
		Default = followCfg.on == true,
		Tooltip = "AFK mode. Joins a friend's Between party whenever there is one (lobby or mid-run, every 10s) and waits while you're with them. No friend party in the lobby for 1 minute, or on another floor → starts / chains your own run on the difficulty below. Works without Auto chain. Saved in PlayerTools/between_follow.json.",
	}):OnChanged(function(v)
		followCfg.on = v == true
		follow.noFriendSince = nil
		saveFollowCfg()
	end)

	WdBox:AddInput('BetweenFollowNames', {
		Text = 'Follow these players',
		Default = followCfg.names,
		Placeholder = 'extra usernames, comma separated (whitelist always counts)',
		Finished = true,
		ClearTextOnFocus = false,
		AllowEmpty = true,
		Callback = function(v)
			followCfg.names = tostring(v or '')
			saveFollowCfg()
		end,
	})

	WdBox:AddDropdown('BetweenFollowFallback', {
		Text = 'Follow: own-run difficulty',
		Values = modeValues,
		Default = table.find(modeValues, followCfg.fallback) and followCfg.fallback or (table.find(modeValues, 'Normal') and 'Normal' or modeValues[1]),
		AllowNull = false,
		Tooltip = 'Difficulty used when follow starts a run of yours (no friend party, or from another floor).',
	}):OnChanged(function(v)
		followCfg.fallback = tostring(flattenOptionValue(v) or 'Normal')
		saveFollowCfg()
	end)

	WdBox:AddToggle('BetweenAutoDifficulty', {
		Text = 'Auto difficulty (Elite → Hard)',
		Default = followCfg.autoDiff == true,
		Tooltip = 'Chained / auto-started runs: Elite while you have Elite Wave Keys (if Use Elite keys first is on), then Hard. Overrides the difficulty dropdowns for auto starts.',
	}):OnChanged(function(v)
		followCfg.autoDiff = v == true
		saveFollowCfg()
	end)

	WdBox:AddToggle('BetweenEliteFirst', {
		Text = 'Use Elite keys first',
		Default = followCfg.eliteFirst == true,
		Tooltip = 'With Auto difficulty: start Elite while you have Elite Wave Keys, then Hard.',
	}):OnChanged(function(v)
		followCfg.eliteFirst = v == true
		saveFollowCfg()
	end)

	followLabel = WdBox:AddLabel('Follow: ' .. follow.status)

	WdBox:AddButton('Start Between run', function()
		task.spawn(function()
			Library:Notify('The Between — applying difficulty then start…', 3)
			local startFn = getgenv().SB2BetweenStartRun or startBetweenRun
			local ok, err = startFn({ keepLobbySettings = false })
			if ok then
				Library:Notify(('Between %s starting…'):format(tostring(currentPartyMode() or 'run')), 4)
			else
				Library:Notify(tostring(err or 'failed'), 7, true)
			end
		end)
	end)

	WdBox:AddButton('Start (keep lobby difficulty)', function()
		task.spawn(function()
			local startFn = getgenv().SB2BetweenStartRun or startBetweenRun
			local ok, err = startFn({ keepLobbySettings = true })
			if ok then
				Library:Notify(('Starting %s (lobby)…'):format(tostring(currentPartyMode() or 'run')), 4)
			else
				Library:Notify(tostring(err or 'failed'), 7, true)
			end
		end)
	end)

	WdBox:AddButton('Apply difficulty only', function()
		task.spawn(function()
			local mode = flattenOptionValue(Options.BetweenDifficulty and Options.BetweenDifficulty.Value)
			local applyFn = getgenv().SB2BetweenApplyMode or applyBetweenMode
			local ok, err = applyFn(mode)
			if ok then
				Library:Notify('Mode → ' .. tostring(currentPartyMode() or mode), 3)
			else
				Library:Notify(tostring(err or 'failed'), 7, true)
			end
		end)
	end)

	WdBox:AddButton('Open Between party (Travel)', function()
		task.spawn(function()
			local ok, err = openBetweenPartyScreen()
			if ok then
				Library:Notify('Opened The Between party screen', 3)
			else
				Library:Notify(tostring(err or 'failed'), 6, true)
			end
		end)
	end)
end
