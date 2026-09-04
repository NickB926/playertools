--[[
	HiveMind.lua — multi-client commander for Swordburst 2 (Potassium)

	File IPC (shared workspace):
	  PlayerTools/hive/order.json
	  PlayerTools/hive/peers/<userId>.json
	  PlayerTools/hive/roster.json
	  PlayerTools/hive/commander.json

	Pick a commanding client; other hive clients TP / follow / stack on them.

	Roles:
	  commander — issues orders
	  worker    — executes orders
	  idle      — heartbeat only

	Orders: stop | follow | stack | rally | combat_on | combat_off | solo_resume | solo_resume_off | boss_route_on | boss_route_off | hide_menu | deposit_crystals | dump_items

	Usage from PlayerTools (or alone):
	  local Hive = loadstring(readfile('PlayerTools/HiveMind.lua'))()
	  Hive.start()
	  Hive.claimCommander()
	  Hive.issue('follow')
]]

local Players = game:GetService('Players')
local RunService = game:GetService('RunService')
local TeleportService = game:GetService('TeleportService')
local HttpService = game:GetService('HttpService')
local ReplicatedStorage = game:GetService('ReplicatedStorage')

-- Kill zombie HiveMind trade listeners + heartbeats from prior loads (reconnect storms).
pcall(function()
	local n = 0
	local function purgeSignal(sig)
		if typeof(sig) ~= 'RBXScriptSignal' or type(getconnections) ~= 'function' then
			return
		end
		for _, c in ipairs(getconnections(sig)) do
			local fn = c.Function
			if type(fn) == 'function' then
				local ok, src = pcall(debug.info, fn, 's')
				if ok and type(src) == 'string' and src:find('HiveMind', 1, true) then
					pcall(function()
						c:Disconnect()
					end)
					n += 1
				end
			end
		end
	end
	local ev = ReplicatedStorage:FindFirstChild('Event')
	if ev then
		purgeSignal(ev.OnClientEvent)
	end
	purgeSignal(RunService.Heartbeat)
	purgeSignal(RunService.Stepped)
	purgeSignal(RunService.RenderStepped)
	getgenv().SB2HiveTradeConn = nil
	getgenv().SB2HiveTradeBound = false
	-- Kill any in-flight dump/deposit loops from prior loads (they cancel+request-storm).
	getgenv().SB2HiveDumpGen = (getgenv().SB2HiveDumpGen or 0) + 1
	getgenv().SB2HiveDumpBusy = false
	getgenv().SB2HiveTradeOpenLock = false
	getgenv().SB2HiveTradeReqLock = nil
	if n > 0 then
		warn(('[Hive] purged %s zombie HiveMind connections'):format(tostring(n)))
	end
end)

local LocalPlayer = Players.LocalPlayer
local USER_ID = LocalPlayer and LocalPlayer.UserId

local HIVE_DIR = 'PlayerTools/hive'
local PEERS_DIR = HIVE_DIR .. '/peers'
local ORDER_PATH = HIVE_DIR .. '/order.json'
local ROSTER_PATH = HIVE_DIR .. '/roster.json'
local COMMANDER_PATH = HIVE_DIR .. '/commander.json'
local TRIBUTE_WEBHOOK_PATH = HIVE_DIR .. '/tribute_webhook.json' -- legacy shared
local function tributeWebhookPath()
	return HIVE_DIR .. '/tribute_webhook_' .. tostring(USER_ID or '0') .. '.json'
end

local HEARTBEAT_INTERVAL = 0.45
local ORDER_POLL_INTERVAL = 0.35
local PEER_STALE_SEC = 12

local Hive = getgenv().SB2Hive
if type(Hive) == 'table' then
	pcall(function()
		if Hive._followConn then
			Hive._followConn:Disconnect()
		end
	end)
	pcall(function()
		Hive._abortTrade = true
		Hive._depositBusy = false
	end)
	pcall(function()
		if type(Hive.stop) == 'function' then
			-- Soft stop on module reload — do not bury peer / leave roster mid-reload.
			Hive.stop({ leave = false })
		end
	end)
	pcall(function()
		for _, c in ipairs(Hive._conns or {}) do
			c:Disconnect()
		end
	end)
end
pcall(function()
	getgenv().SB2HiveDumpGen = (getgenv().SB2HiveDumpGen or 0) + 1
	getgenv().SB2HiveDumpBusy = false
	-- Force a clean trade listener bind after this reload (kills reconnect-storm leftovers).
	getgenv().SB2HiveTradeBound = false
end)

Hive = {
	_alive = false,
	role = 'idle', -- idle | commander | worker
	status = 'off',
	lastOrderSeq = 0,
	selectedCommanderId = nil,
	_conns = {},
	_followConn = nil,
	_followGen = 0,
	_tradeConn = nil,
	_acceptHiveTrades = false,
	_depositBusy = false,
	_abortTrade = false,
	_addingItems = false,
	_tradeState = nil,
	_lastTradeAction = nil,
	_tradeGen = 0,
	notify = nil, -- optional function(msg)
	_tributeWatchConn = nil,
	_tributeKnown = nil, -- set of inventory instance ids already seen
	_tributeWebhookUrl = '',
	_tributeWebhookOn = false,
	_tributePing = '', -- each user sets their own Discord snowflake; never hardcode
	_orderRev = 8, -- bump when order handlers / webhook payload change so soft reload re-loadstrings HiveMind
}
getgenv().SB2Hive = Hive

local function notify(msg)
	if type(Hive.notify) == 'function' then
		pcall(Hive.notify, tostring(msg))
	end
	warn('[Hive] ' .. tostring(msg))
end

local function ensureDirs()
	if type(makefolder) ~= 'function' then
		return
	end
	pcall(makefolder, 'PlayerTools')
	pcall(makefolder, HIVE_DIR)
	pcall(makefolder, PEERS_DIR)
end

local function encode(tbl)
	local ok, out = pcall(function()
		return HttpService:JSONEncode(tbl)
	end)
	return ok and out or nil
end

local function decode(str)
	if type(str) ~= 'string' or str == '' then
		return nil
	end
	local ok, out = pcall(function()
		return HttpService:JSONDecode(str)
	end)
	return ok and out or nil
end

local function writeJson(path, tbl)
	if type(writefile) ~= 'function' then
		return false
	end
	local body = encode(tbl)
	if not body then
		return false
	end
	ensureDirs()
	local ok = pcall(writefile, path, body)
	return ok and true or false
end

local function readJson(path)
	if type(readfile) ~= 'function' then
		return nil
	end
	if type(isfile) == 'function' then
		local ok, exists = pcall(isfile, path)
		if ok and not exists then
			return nil
		end
	end
	local ok, body = pcall(readfile, path)
	if not ok or type(body) ~= 'string' then
		return nil
	end
	return decode(body)
end

local function peerPath(userId)
	return ('%s/%s.json'):format(PEERS_DIR, tostring(userId))
end

local function getRoot(player)
	player = player or LocalPlayer
	if not player then
		return nil
	end
	local chars = workspace:FindFirstChild('Characters')
	local char = chars and chars:FindFirstChild(player.Name)
	if not (char and char.Parent) then
		char = player.Character
	end
	if not char then
		return nil
	end
	return char:FindFirstChild('HumanoidRootPart') or char:FindFirstChild('UpperTorso')
end

local function getHp()
	local char = LocalPlayer.Character
	if not char then
		return 0, 0, false
	end
	local ent = char:FindFirstChild('Entity')
	local health = ent and ent:FindFirstChild('Health')
	local maxHealth = ent and ent:FindFirstChild('MaxHealth')
	if health and maxHealth then
		return tonumber(health.Value) or 0, tonumber(maxHealth.Value) or 0, (tonumber(health.Value) or 0) > 0
	end
	local hum = char:FindFirstChildOfClass('Humanoid')
	if hum then
		return hum.Health, hum.MaxHealth, hum.Health > 0
	end
	return 0, 0, false
end

local function crystalCounts()
	local out = {}
	local profiles = ReplicatedStorage:FindFirstChild('Profiles')
	local profile = profiles and profiles:FindFirstChild(LocalPlayer.Name)
	local inv = profile and profile:FindFirstChild('Inventory')
	if not inv then
		return out
	end
	for _, name in ipairs({
		'Common Upgrade Crystal',
		'Uncommon Upgrade Crystal',
		'Rare Upgrade Crystal',
		'Legendary Upgrade Crystal',
		'Tribute Upgrade Crystal',
		'Burst Upgrade Crystal',
		'Upgrade Protection Scroll',
	}) do
		local item = inv:FindFirstChild(name)
		if item then
			local n = item:FindFirstChild('Count') and item.Count.Value or 1
			out[name] = n
		end
	end
	return out
end

local function resolveToggles()
	-- Starlight keeps toggles on Library.Toggles only — global `Toggles` is often nil
	-- in separately loadstring'd modules like this one.
	local t = rawget(_G, 'Toggles')
	if type(t) == 'table' and (t.BossWaypointRoute or t.SoloCombatResume or t.AutoAttack or next(t) ~= nil) then
		return t
	end
	local L = rawget(_G, 'Library')
	if type(L) ~= 'table' then
		L = getgenv().SB2Library or getgenv().Library
	end
	if type(L) == 'table' and type(L.Toggles) == 'table' then
		return L.Toggles
	end
	return type(t) == 'table' and t or nil
end

local function setCombatToggles(attack, skill)
	local toggles = resolveToggles()
	pcall(function()
		if toggles and toggles.AutoAttack and type(attack) == 'boolean' then
			toggles.AutoAttack:SetValue(attack)
		end
		if toggles and toggles.AutoSkill and type(skill) == 'boolean' then
			toggles.AutoSkill:SetValue(skill)
		end
	end)
end

local function listPeers()
	local peers = {}
	local now = tick()
	local seen = {}

	local function consider(data)
		if type(data) ~= 'table' or not data.userId or not data.ts then
			return
		end
		if (now - data.ts) > PEER_STALE_SEC then
			return
		end
		if seen[data.userId] then
			return
		end
		seen[data.userId] = true
		peers[#peers + 1] = data
	end

	if type(listfiles) == 'function' then
		local ok, files = pcall(listfiles, PEERS_DIR)
		if ok and type(files) == 'table' then
			for _, path in ipairs(files) do
				consider(readJson(path))
			end
		end
	end

	local roster = readJson(ROSTER_PATH)
	local ids = {}
	if type(roster) == 'table' and type(roster.ids) == 'table' then
		for _, id in ipairs(roster.ids) do
			ids[#ids + 1] = tonumber(id) or id
		end
	end
	ids[#ids + 1] = USER_ID
	for _, plr in ipairs(Players:GetPlayers()) do
		ids[#ids + 1] = plr.UserId
	end
	local remembered = getgenv().SB2HivePeerIds
	if type(remembered) == 'table' then
		for _, id in ipairs(remembered) do
			ids[#ids + 1] = id
		end
	end

	for _, id in ipairs(ids) do
		if id and not seen[id] then
			consider(readJson(peerPath(id)))
		end
	end

	table.sort(peers, function(a, b)
		return tostring(a.name) < tostring(b.name)
	end)

	local rem = {}
	for _, p in ipairs(peers) do
		rem[#rem + 1] = p.userId
	end
	getgenv().SB2HivePeerIds = rem
	return peers
end

local function readCommanderFile()
	return readJson(COMMANDER_PATH)
end

local function leaveRoster()
	local roster = readJson(ROSTER_PATH)
	if type(roster) ~= 'table' or type(roster.ids) ~= 'table' then
		return
	end
	local nextIds = {}
	for _, id in ipairs(roster.ids) do
		if tonumber(id) ~= USER_ID and id ~= USER_ID then
			nextIds[#nextIds + 1] = id
		end
	end
	roster.ids = nextIds
	roster.ts = tick()
	writeJson(ROSTER_PATH, roster)
end

local function buryPeerFile()
	local dead = {
		userId = USER_ID,
		name = LocalPlayer.Name,
		role = 'idle',
		status = 'off',
		ts = 0,
	}
	writeJson(peerPath(USER_ID), dead)
	if type(delfile) == 'function' then
		pcall(delfile, peerPath(USER_ID))
	end
end

local function clearCommanderIfSelf()
	local data = readCommanderFile()
	if not (data and tonumber(data.userId) == USER_ID) then
		return
	end
	Hive.selectedCommanderId = nil
	if type(delfile) == 'function' then
		pcall(delfile, COMMANDER_PATH)
	else
		writeJson(COMMANDER_PATH, { userId = 0, name = '', ts = 0 })
	end
end

local function touchRoster()
	local roster = readJson(ROSTER_PATH) or { ids = {} }
	if type(roster.ids) ~= 'table' then
		roster.ids = {}
	end
	local have = false
	for _, id in ipairs(roster.ids) do
		if tonumber(id) == USER_ID or id == USER_ID then
			have = true
			break
		end
	end
	if not have then
		roster.ids[#roster.ids + 1] = USER_ID
		roster.ts = tick()
		writeJson(ROSTER_PATH, roster)
	end
end

local function readOrder()
	return readJson(ORDER_PATH)
end

local function writeOrder(orderType, payload, commanderId)
	local prev = readOrder()
	local seq = (prev and tonumber(prev.seq) or 0) + 1
	local cmdId = tonumber(commanderId) or tonumber(Hive.selectedCommanderId) or USER_ID
	local order = {
		seq = seq,
		commanderId = cmdId,
		type = orderType,
		payload = payload or {},
		ts = tick(),
	}
	if writeJson(ORDER_PATH, order) then
		Hive.lastOrderSeq = seq
		return order
	end
	return nil
end

local function writeHeartbeat()
	local root = getRoot(LocalPlayer)
	local hp, maxHp, alive = getHp()
	local combatOn = false
	local skillOn = false
	pcall(function()
		combatOn = Toggles and Toggles.AutoAttack and Toggles.AutoAttack.Value == true
		skillOn = Toggles and Toggles.AutoSkill and Toggles.AutoSkill.Value == true
	end)
	local peer = {
		userId = USER_ID,
		name = LocalPlayer.Name,
		displayName = LocalPlayer.DisplayName,
		role = Hive.role,
		status = Hive.status,
		placeId = game.PlaceId,
		jobId = game.JobId,
		pos = root and { x = root.Position.X, y = root.Position.Y, z = root.Position.Z } or nil,
		hp = hp,
		maxHp = maxHp,
		alive = alive,
		lastOrderSeq = Hive.lastOrderSeq,
		combat = { autoAttack = combatOn, autoSkill = skillOn },
		crystals = crystalCounts(),
		vel = (function()
			local n = 0
			pcall(function()
				local p = ReplicatedStorage.Profiles:FindFirstChild(LocalPlayer.Name)
				-- Floor — peer JSON must not carry float noise into tax math.
				n = math.floor(tonumber(p.Stats.Vel.Value) or 0)
			end)
			return n
		end)(),
		ts = tick(),
	}
	writeJson(peerPath(USER_ID), peer)
	return peer
end

local function stopFollow()
	Hive._followGen = (tonumber(Hive._followGen) or 0) + 1
	if Hive._followConn then
		pcall(function()
			Hive._followConn:Disconnect()
		end)
		Hive._followConn = nil
	end
	if Hive.status == 'follow' or Hive.status == 'stack' or Hive.status == 'waiting_commander' then
		Hive.status = 'idle'
	end
end

local function commanderPlayer(order)
	local id = order and tonumber(order.commanderId)
	if not id then
		return nil
	end
	return Players:GetPlayerByUserId(id)
end

local function workerSlotIndex(order)
	local peers = listPeers()
	local workers = {}
	for _, p in ipairs(peers) do
		if p.userId ~= (order and order.commanderId) and p.role ~= 'commander' then
			workers[#workers + 1] = p
		end
	end
	table.sort(workers, function(a, b)
		return (tonumber(a.userId) or 0) < (tonumber(b.userId) or 0)
	end)
	for i, w in ipairs(workers) do
		if w.userId == USER_ID then
			return i, #workers
		end
	end
	return 1, math.max(1, #workers)
end

local function followOffset(mode, order)
	local slot, total = workerSlotIndex(order)
	if mode == 'stack' then
		return Vector3.new(0, 2 + (slot - 1) * 0.15, 0)
	end
	-- ring around commander
	local angle = ((slot - 1) / math.max(total, 1)) * math.pi * 2
	local radius = (order and order.payload and tonumber(order.payload.radius)) or 5
	return Vector3.new(math.cos(angle) * radius, 3, math.sin(angle) * radius)
end

local function startFollow(mode, order)
	stopFollow()
	if not Hive._alive then
		return
	end
	Hive.status = mode
	if type(getgenv().SB2HoldCombatAnchor) == 'function' then
		pcall(getgenv().SB2HoldCombatAnchor, 3)
	end
	local lastHold = 0
	local gen = Hive._followGen
	Hive._followConn = RunService.Heartbeat:Connect(function()
		if gen ~= Hive._followGen or not Hive._alive or Hive.role == 'idle' then
			return
		end
		if Hive.status ~= 'follow' and Hive.status ~= 'stack' then
			return
		end
		local now = os.clock()
		if now - lastHold > 2 and type(getgenv().SB2HoldCombatAnchor) == 'function' then
			lastHold = now
			pcall(getgenv().SB2HoldCombatAnchor, 2.5)
		end
		local cmd = commanderPlayer(order)
		if not cmd then
			Hive.status = 'waiting_commander'
			return
		end
		local myRoot = getRoot(LocalPlayer)
		local theirRoot = getRoot(cmd)
		if not (myRoot and theirRoot) then
			return
		end
		local offset = followOffset(mode, order)
		pcall(function()
			myRoot.Anchored = false
			myRoot.CFrame = theirRoot.CFrame * CFrame.new(offset)
			myRoot.AssemblyLinearVelocity = Vector3.zero
			myRoot.AssemblyAngularVelocity = Vector3.zero
		end)
	end)
end

local function snapOnceToCommander(order)
	stopFollow()
	if type(getgenv().SB2HoldCombatAnchor) == 'function' then
		pcall(getgenv().SB2HoldCombatAnchor, 0.9)
	end
	local cmdId = order and tonumber(order.commanderId)
	local cmd = commanderPlayer(order)
	local myRoot = getRoot(LocalPlayer)
	local dest
	local theirRoot = cmd and getRoot(cmd)
	if theirRoot then
		dest = theirRoot.CFrame * CFrame.new(followOffset('follow', order))
	else
		local cmdPeer
		for _, p in ipairs(listPeers()) do
			if p.userId == cmdId and p.pos then
				cmdPeer = p
				break
			end
		end
		if cmdPeer and cmdPeer.pos then
			local offset = followOffset('follow', order)
			dest = CFrame.new(cmdPeer.pos.x, cmdPeer.pos.y, cmdPeer.pos.z) + offset
		end
	end
	if myRoot and dest then
		pcall(function()
			myRoot.Anchored = false
			myRoot.CFrame = dest
			myRoot.AssemblyLinearVelocity = Vector3.zero
			myRoot.AssemblyAngularVelocity = Vector3.zero
		end)
	end
	Hive.status = 'idle'
	notify('Warped once — free roam')
end

local function pendingSnapPath()
	return HIVE_DIR .. '/snap_' .. tostring(USER_ID) .. '.json'
end

local function rallyToCommander(order)
	local cmdId = order and tonumber(order.commanderId)
	local peers = listPeers()
	local cmdPeer
	for _, p in ipairs(peers) do
		if p.userId == cmdId then
			cmdPeer = p
			break
		end
	end
	if not cmdPeer then
		notify('Rally failed — commander peer stale')
		Hive.status = 'rally_failed'
		return
	end

	-- Same server: one warp to them, then let the client walk.
	if cmdPeer.jobId == game.JobId and cmdPeer.placeId == game.PlaceId then
		snapOnceToCommander(order)
		return
	end

	Hive.status = 'hopping'
	writeJson(pendingSnapPath(), {
		commanderId = cmdId,
		seq = order and order.seq,
		ts = tick(),
	})
	if type(getgenv().SB2HoldCombatAnchor) == 'function' then
		pcall(getgenv().SB2HoldCombatAnchor, 1.1)
	end
	if type(getgenv().SB2CloseAllPillPanels) == 'function' then
		pcall(getgenv().SB2CloseAllPillPanels)
	end
	notify(('Rally hop → %s'):format(tostring(cmdPeer.name)))
	local ok, err = pcall(function()
		TeleportService:TeleportToPlaceInstance(cmdPeer.placeId, cmdPeer.jobId, LocalPlayer)
	end)
	if not ok then
		notify('Rally teleport failed: ' .. tostring(err))
		Hive.status = 'rally_failed'
		if type(delfile) == 'function' then
			pcall(delfile, pendingSnapPath())
		end
	end
end

local function getEvent()
	local ev = ReplicatedStorage:FindFirstChild('Event')
	if typeof(ev) == 'Instance' and ev:IsA('RemoteEvent') then
		return ev
	end
	for _, inst in ipairs(ReplicatedStorage:GetDescendants()) do
		if inst:IsA('RemoteEvent') and inst.Name == 'Event' then
			return inst
		end
	end
	return nil
end

local function getFunction()
	return ReplicatedStorage:FindFirstChild('Function')
end

local function invokeTrade(...)
	local fn = getFunction()
	if not fn then
		return nil
	end
	local ok, result = pcall(fn.InvokeServer, fn, ...)
	if ok then
		return result
	end
	return nil
end

local function fireTrade(...)
	local ev = getEvent()
	if not ev then
		return
	end
	pcall(ev.FireServer, ev, ...)
end

local function getTradeUI()
	if type(Hive._tradeUI) == 'table' then
		return Hive._tradeUI
	end
	local g = getgenv()
	if type(g.SB2RequiredServices) == 'table' and type(g.SB2RequiredServices.TradeUI) == 'table' then
		Hive._tradeUI = g.SB2RequiredServices.TradeUI
		return Hive._tradeUI
	end
	local req = require or getrenv().require
	if type(req) ~= 'function' then
		return nil
	end
	local mainModule
	for _, func in next, { getloadedmodules, getnilinstances } do
		if type(func) ~= 'function' then
			continue
		end
		local ok, list = pcall(func)
		if ok and type(list) == 'table' then
			for _, instance in next, list do
				if typeof(instance) == 'Instance' and instance.Name == 'MainModule' and instance:FindFirstChild('Services') then
					mainModule = instance
					break
				end
			end
		end
		if mainModule then
			break
		end
	end
	if not mainModule then
		return nil
	end
	local ok, tu = pcall(function()
		local ui = mainModule.Services.UI
		return req(ui.Trade)
	end)
	if ok and type(tu) == 'table' then
		Hive._tradeUI = tu
		return tu
	end
	return nil
end

local function playerFromTradeId(id)
	id = tonumber(id)
	if not id then
		return nil
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p.UserId == id then
			return p
		end
	end
	return nil
end

-- Game TradeUI uses Requester/Partner Player refs; server often sends only UserIds (null refs break AddItem).
local function enrichTradeState(state)
	if type(state) ~= 'table' then
		return state
	end
	if typeof(state.Requester) ~= 'Instance' or not state.Requester:IsA('Player') then
		local p = playerFromTradeId(state.RequesterUserId or state.RequesterId)
		if p then
			state.Requester = p
		end
	end
	if typeof(state.Partner) ~= 'Instance' or not state.Partner:IsA('Player') then
		local p = playerFromTradeId(state.PartnerUserId or state.PartnerId)
		if p then
			state.Partner = p
		end
	end
	return state
end

local function hideRobloxChatOnly()
	pcall(function()
		game:GetService('StarterGui'):SetCoreGuiEnabled(Enum.CoreGuiType.Chat, false)
	end)
	pcall(function()
		local ec = game:GetService('CoreGui'):FindFirstChild('ExperienceChat')
		if ec and ec:IsA('ScreenGui') then
			ec.Enabled = false
		end
	end)
end

local function ensureGameChatVisible()
	pcall(function()
		local ui = getgenv().SB2RequiredServices and getgenv().SB2RequiredServices.UI
		if ui and ui.Pui and ui.Pui.Chat then
			ui.Pui.Chat.Visible = true
		end
	end)
end

local function parseTradeEvent(kind, payload, arg3, arg4)
	if kind == 'UI' and type(payload) == 'table' and payload[1] == 'Trade' then
		return payload[2], payload[3]
	end
	if kind == 'UI' and payload == 'Trade' and type(arg3) == 'string' then
		return arg3, arg4
	end
	if type(kind) == 'table' and kind[1] == 'Trade' then
		return kind[2], kind[3]
	end
	return nil, nil
end

local function disconnectHiveTradeListeners()
	if type(getconnections) ~= 'function' then
		return 0
	end
	local ev = getEvent()
	if not ev then
		return 0
	end
	local removed = 0
	for _, conn in ipairs(getconnections(ev.OnClientEvent)) do
		local fn = conn.Function
		if type(fn) == 'function' then
			local ok, src = pcall(debug.info, fn, 's')
			if ok and type(src) == 'string' and src:find('HiveMind', 1, true) then
				pcall(function()
					conn:Disconnect()
				end)
				removed += 1
			end
		end
	end
	return removed
end

local function forwardTradeUI(action, state)
	local tu = getTradeUI()
	if not tu or type(state) ~= 'table' then
		return
	end
	state = enrichTradeState(state)
	if action == 'RequestAccepted' and type(tu.OnRequestAccepted) == 'function' then
		pcall(tu.OnRequestAccepted, state)
		hideRobloxChatOnly()
	elseif action == 'TradeChanged' and type(tu.OnTradeChanged) == 'function' then
		pcall(tu.OnTradeChanged, state)
	end
end

local function hivePeerIds()
	local set = {}
	for _, p in ipairs(listPeers()) do
		set[p.userId] = true
	end
	return set
end

-- Accept even if peer heartbeat is briefly stale (listPeers drops them after PEER_STALE_SEC).
local function isHiveTradePartner(plrOrId)
	local id = plrOrId
	local plr = nil
	if typeof(plrOrId) == 'Instance' and plrOrId:IsA('Player') then
		plr = plrOrId
		id = plrOrId.UserId
	end
	id = tonumber(id)
	if not id then
		return false
	end
	if id == USER_ID then
		return false
	end
	if type(isOwnAlt) == 'function' and plr and isOwnAlt(plr) then
		return true
	end
	if type(getgenv().SB2IsOwnAlt) == 'function' and plr and getgenv().SB2IsOwnAlt(plr) then
		return true
	end
	for _, p in ipairs(listPeers()) do
		if tonumber(p.userId) == id then
			return true
		end
	end
	local roster = readJson(ROSTER_PATH)
	if type(roster) == 'table' and type(roster.ids) == 'table' then
		for _, rid in ipairs(roster.ids) do
			if tonumber(rid) == id then
				return true
			end
		end
	end
	local remembered = getgenv().SB2HivePeerIds
	if type(remembered) == 'table' then
		for _, rid in ipairs(remembered) do
			if tonumber(rid) == id then
				return true
			end
		end
	end
	-- Stale peer file still counts as hive for trade accept.
	local stale = readJson(peerPath(id))
	if type(stale) == 'table' and tonumber(stale.userId) == id and type(stale.name) == 'string' then
		return true
	end
	return false
end

local function shouldAutoAcceptHiveTrade(fromPlr)
	if not fromPlr then
		return false
	end
	if not isHiveTradePartner(fromPlr) then
		return false
	end
	if Hive._acceptHiveTrades then
		return true
	end
	if Hive.role == 'commander' then
		return true
	end
	local cmd = readCommanderFile()
	if cmd and tonumber(cmd.userId) == USER_ID then
		return true
	end
	return false
end

local function resolveTradePlayer(from)
	if typeof(from) == 'Instance' and from:IsA('Player') then
		return from
	end
	local id = tonumber(from)
	if id then
		local ok, plr = pcall(Players.GetPlayerByUserId, Players, id)
		if ok and plr then
			return plr
		end
	end
	if type(from) == 'string' and from ~= '' then
		return Players:FindFirstChild(from)
	end
	return nil
end

local TRADE_MAX = 400
local VEL_CAP = 1000000000
local VEL_TAX = 1.10
-- Game Trade UI debounces AddItem at ~0.3s; stay at/above that for uniques.
local TRADE_ADD_DELAY = 0.48
local TRADE_ADD_PAUSE_EVERY = 8
local TRADE_ADD_PAUSE = 0.55
local TRADE_SETTLE = 1.15
local TRADE_SETTLE_FAST = 0.25
local TRADE_BETWEEN = 1.6
local TRADE_ACCEPT_TIMEOUT = 20
local TRADE_COMPLETE_TIMEOUT = 22
local TRADE_UI_SETTLE = 0.75
-- Set false for the rest of a dump if TradeChangeCurrency cannot be verified.
local velDumpEnabled = true

local function tradeListenerLive()
	-- Some executors report RBXScriptConnection.Connected as false even while live
	-- (commander was Bound=true + Connected=false). Trust session Bound + conn object.
	-- Module-load purge clears Bound/Conn so a fresh load always rebinds once.
	if getgenv().SB2HiveTradeBound ~= true then
		return false
	end
	local c = Hive._tradeConn or getgenv().SB2HiveTradeConn
	if not c then
		getgenv().SB2HiveTradeBound = false
		return false
	end
	Hive._tradeConn = c
	getgenv().SB2HiveTradeConn = c
	return true
end

local function setupTradeListener()
	if tradeListenerLive() then
		return
	end
	-- One bind per session. Never mass-disconnect via getconnections (that caused reconnect storms).
	pcall(function()
		local old = getgenv().SB2HiveTradeConn
		if old then
			old:Disconnect()
		end
	end)
	Hive._tradeConn = nil
	getgenv().SB2HiveTradeConn = nil
	getgenv().SB2HiveTradeBound = false
	local ev = getEvent()
	if not ev or typeof(ev.OnClientEvent) ~= 'RBXScriptSignal' then
		return
	end
	local okConn, conn = pcall(function()
		return ev.OnClientEvent:Connect(function(kind, payload, arg3, arg4)
		local action, data = parseTradeEvent(kind, payload, arg3, arg4)
		if not action then
			return
		end

		if action == 'Request' then
			local fromPlr = resolveTradePlayer(data)
			local fromId = fromPlr and fromPlr.UserId
			if shouldAutoAcceptHiveTrade(fromPlr) then
				local g = getgenv()
				local tnow = tick()
				if g.SB2HiveTradeAcceptFrom == fromId and g.SB2HiveTradeAcceptAt and (tnow - g.SB2HiveTradeAcceptAt) < 0.5 then
					return
				end
				g.SB2HiveTradeAcceptFrom = fromId
				g.SB2HiveTradeAcceptAt = tnow
				fireTrade('Trade', 'RequestAccept', {})
				Hive.status = 'trading_accept'
				notify(('Accepted trade from %s'):format(tostring(fromPlr and fromPlr.Name or fromId)))
			elseif Hive._acceptHiveTrades and fromId and not isHiveTradePartner(fromPlr or fromId) then
				fireTrade('Trade', 'RequestDecline', {})
			end
		elseif action == 'RequestAccepted' or action == 'RequestAccept' then
			-- Server/client event name is RequestAccept (state table). RequestAccepted was never sent.
			local state = data
			if type(state) == 'table' then
				enrichTradeState(state)
				Hive._tradeState = state
			end
			Hive._lastTradeAction = 'accepted'
			Hive._tradeGen = (Hive._tradeGen or 0) + 1
			-- Cardinal MainModule already drives TradeUI.OnRequestAccepted — do not double-call.
		elseif action == 'TradeChanged' then
			local state = data
			if type(state) == 'table' then
				enrichTradeState(state)
				Hive._tradeState = state
			end
			forwardTradeUI('TradeChanged', state)
			Hive._lastTradeAction = 'changed'
			Hive._tradeGen = (Hive._tradeGen or 0) + 1
			if type(state) ~= 'table' then
				return
			end
			local weReq = tradeUserId(state, 'Requester') == USER_ID
				or (typeof(state.Requester) == 'Instance' and state.Requester == LocalPlayer)
			local targetRole = weReq and 'Partner' or 'Requester'
			local ourRole = weReq and 'Requester' or 'Partner'
			local theyConfirmed = state[targetRole .. 'Confirmed'] == true
			local weAccepted = state[ourRole .. 'Accepted'] == true
			-- If the other side already confirmed, finish even while still adding (full 400 trap).
			if theyConfirmed and not weAccepted then
				if Hive._addingItems then
					Hive._addingItems = false
				end
				if Hive._acceptHiveTrades or Hive._depositBusy or Hive.role == 'commander' or Hive._depositBusy then
					fireTrade('Trade', 'TradeConfirm', {})
					fireTrade('Trade', 'TradeAccept', {})
					local tu = getTradeUI()
					if tu then
						pcall(function()
							if type(tu.Confirm) == 'function' then
								tu.Confirm()
							end
							if type(tu.Accept) == 'function' then
								tu.Accept()
							end
						end)
					end
				end
				return
			end
			if Hive._addingItems then
				return
			end
			if not (Hive._acceptHiveTrades or Hive._depositBusy or Hive.role == 'commander') then
				return
			end
			if theyConfirmed and not weAccepted then
				fireTrade('Trade', 'TradeConfirm', {})
				fireTrade('Trade', 'TradeAccept', {})
			end
		elseif action == 'TradeCompleted' or action == 'TradeComplete' or action == 'Completed' then
			Hive._lastTradeAction = 'completed'
			Hive._addingItems = false
			Hive._tradeState = nil
			getgenv().SB2HiveTradeOpenLock = false
			if Hive.status == 'trading' or Hive.status == 'trading_accept' then
				if not Hive._depositBusy then
					Hive.status = Hive.role == 'commander' and 'commanding' or 'idle'
				end
			end
		elseif action == 'TradeCancel' or action == 'TradeCancelled' or action == 'Cancelled' then
			if Hive._ignoreCancelUntil and tick() < Hive._ignoreCancelUntil then
				-- #region agent log
				warn('[TRADE-DBG] ignore stale TradeCancel')
				-- #endregion
				return
			end
			Hive._lastTradeAction = 'cancel'
			Hive._tradeState = nil
			Hive._addingItems = false
			getgenv().SB2HiveTradeOpenLock = false
			if not Hive._depositBusy then
				if Hive.status == 'trading' or Hive.status == 'trading_accept' then
					Hive.status = Hive.role == 'commander' and 'commanding' or 'idle'
				end
			end
		end
		end)
	end)
	if okConn and conn then
		getgenv().SB2HiveTradeConn = conn
		getgenv().SB2HiveTradeBound = true
		Hive._tradeConn = conn
	end
	-- TradeUI callbacks are the authoritative completion path when Event names differ.
	pcall(function()
		local tu = getTradeUI()
		if type(tu) ~= 'table' or tu._SB2HiveCompleteHook then
			return
		end
		tu._SB2HiveCompleteHook = true
		local prevDone = tu.OnTradeCompleted
		tu.OnTradeCompleted = function(...)
			Hive._lastTradeAction = 'completed'
			Hive._addingItems = false
			Hive._tradeState = nil
			getgenv().SB2HiveTradeOpenLock = false
			-- #region agent log
			warn('[TRADE-DBG] OnTradeCompleted')
			-- #endregion
			if type(prevDone) == 'function' then
				return prevDone(...)
			end
		end
		local prevCancel = tu.OnTradeCancelled
		tu.OnTradeCancelled = function(...)
			if Hive._ignoreCancelUntil and tick() < Hive._ignoreCancelUntil then
				-- #region agent log
				warn('[TRADE-DBG] ignore stale OnTradeCancelled')
				-- #endregion
				return
			end
			Hive._lastTradeAction = 'cancel'
			Hive._addingItems = false
			Hive._tradeState = nil
			getgenv().SB2HiveTradeOpenLock = false
			-- #region agent log
			warn('[TRADE-DBG] OnTradeCancelled')
			-- #endregion
			if type(prevCancel) == 'function' then
				return prevCancel(...)
			end
		end
	end)
end

local function waitFor(timeout, pred)
	local deadline = os.clock() + timeout
	while os.clock() < deadline do
		if Hive._abortTrade or not Hive._alive then
			return false, 'abort'
		end
		-- Stale dump coroutine must not keep cancel/request-storming after a newer dump/reload.
		if Hive._dumpGen ~= nil and getgenv().SB2HiveDumpGen ~= Hive._dumpGen then
			return false, 'abort'
		end
		if pred() then
			return true
		end
		task.wait(0.05)
	end
	return false, 'timeout'
end

local function getProfile()
	local profiles = ReplicatedStorage:FindFirstChild('Profiles')
	return profiles and profiles:FindFirstChild(LocalPlayer.Name)
end

local function getInventory()
	local profile = getProfile()
	return profile and profile:FindFirstChild('Inventory')
end

local function equippedIdSet()
	local set = {}
	local profile = getProfile()
	local equip = profile and profile:FindFirstChild('Equip')
	if not equip then
		return set
	end
	for _, slot in ipairs(equip:GetChildren()) do
		if slot:IsA('ValueBase') then
			local id = tonumber(slot.Value)
			if id and id ~= 0 then
				set[id] = true
			end
		end
	end
	return set
end

local function itemCount(item)
	local c = item and item:FindFirstChild('Count')
	if c and typeof(c.Value) == 'number' then
		return math.max(0, math.floor(c.Value))
	end
	return 1
end

local function itemIsUntradeable(item)
	if not item then
		return true
	end
	-- Inventory IntValues rarely carry flags; game checks Database itemref.Untradeable.
	local flag = item:FindFirstChild('Untradeable')
	if flag then
		if flag:IsA('BoolValue') then
			if flag.Value then
				return true
			end
		else
			return true
		end
	end
	local tradeable = item:FindFirstChild('Tradeable')
	if tradeable and tradeable:IsA('BoolValue') and tradeable.Value == false then
		return true
	end
	local db = ReplicatedStorage:FindFirstChild('Database')
	local items = db and db:FindFirstChild('Items')
	local ref = items and items:FindFirstChild(item.Name)
	if ref and ref:FindFirstChild('Untradeable') then
		return true
	end
	return false
end

local function canTradeItem(item, equipped)
	if not item or not item.Parent then
		return false
	end
	local lower = string.lower(tostring(item.Name))
	if lower == 'vel' or lower == 'gold' or lower == 'money' then
		return false
	end
	if itemIsUntradeable(item) then
		return false
	end
	-- Game trade UI also hides Favorited, but FireServer still accepts them.
	-- Only hard-skip Locked (and equipped). Dump-all should move favorited gear.
	if item:GetAttribute('Locked') then
		return false
	end
	if item:GetAttribute('Favorited') then
		return false
	end
	local locked = item:FindFirstChild('Locked')
	if locked and (not locked:IsA('BoolValue') or locked.Value) then
		return false
	end
	if item:IsA('ValueBase') then
		local id = tonumber(item.Value)
		if id and equipped[id] then
			return false
		end
	end
	return true
end

local function getVelOf(player)
	player = player or LocalPlayer
	if not player then
		return nil
	end
	local function asInt(v)
		local n = tonumber(v)
		if type(n) ~= 'number' then
			return nil
		end
		-- Hidden float noise in Value/peer JSON breaks 10% tax afford checks.
		return math.floor(n)
	end
	local n
	pcall(function()
		local profiles = ReplicatedStorage:FindFirstChild('Profiles')
		local profile = profiles and profiles:FindFirstChild(player.Name)
		local vel = profile and profile:FindFirstChild('Stats') and profile.Stats:FindFirstChild('Vel')
		n = vel and asInt(vel.Value)
	end)
	if type(n) == 'number' then
		return n
	end
	-- Match by UserId if name lookup failed.
	pcall(function()
		local profiles = ReplicatedStorage:FindFirstChild('Profiles')
		if not profiles then
			return
		end
		for _, profile in ipairs(profiles:GetChildren()) do
			local plr = Players:FindFirstChild(profile.Name)
			if plr and plr.UserId == player.UserId then
				local vel = profile:FindFirstChild('Stats') and profile.Stats:FindFirstChild('Vel')
				n = asInt(vel and vel.Value)
				break
			end
		end
	end)
	if type(n) == 'number' then
		return n
	end
	if player ~= LocalPlayer then
		for _, p in ipairs(listPeers()) do
			if tonumber(p.userId) == player.UserId and p.vel ~= nil then
				return asInt(p.vel)
			end
		end
		-- Stale peer file still has last known vel.
		local stale = readJson(peerPath(player.UserId))
		if type(stale) == 'table' and stale.vel ~= nil then
			return asInt(stale.vel)
		end
	end
	return nil
end

local function tableSize(t)
	if type(t) ~= 'table' then
		return 0
	end
	local n = #t
	if n > 0 then
		return n
	end
	for _ in pairs(t) do
		n += 1
	end
	return n
end

local function tradeUserId(state, role)
	if type(state) ~= 'table' then
		return nil
	end
	if role == 'Requester' then
		local req = state.Requester
		if typeof(req) == 'Instance' and req:IsA('Player') then
			return req.UserId
		end
		return tonumber(state.RequesterUserId) or tonumber(state.RequesterId)
	end
	local par = state.Partner
	if typeof(par) == 'Instance' and par:IsA('Player') then
		return par.UserId
	end
	return tonumber(state.PartnerUserId) or tonumber(state.PartnerId)
end

local function ourTradeRole()
	local state = Hive._tradeState
	if type(state) ~= 'table' then
		return 'Requester'
	end
	local reqId = tradeUserId(state, 'Requester')
	local parId = tradeUserId(state, 'Partner')
	if reqId == USER_ID then
		return 'Requester'
	end
	if parId == USER_ID then
		return 'Partner'
	end
	local req = state.Requester
	if typeof(req) == 'Instance' and req:IsA('Player') then
		if req == LocalPlayer or req.UserId == USER_ID then
			return 'Requester'
		end
		return 'Partner'
	end
	if type(req) == 'string' and string.lower(req) == string.lower(LocalPlayer.Name) then
		return 'Requester'
	end
	return 'Requester'
end

local function weAreTradeRequester()
	return ourTradeRole() == 'Requester'
end

-- Game trade state uses RequesterCurrency / PartnerCurrency (not *Vel).
local function readOurOfferedVel()
	local state = Hive._tradeState
	if type(state) ~= 'table' then
		return 0
	end
	local role = ourTradeRole()
	local n = tonumber(state[role .. 'Currency'])
	if type(n) == 'number' then
		return n
	end
	-- Some payloads nest currency under a table.
	local nested = state[role .. 'Currency']
	if type(nested) == 'table' then
		return tonumber(nested.Value or nested.amount or nested[1]) or 0
	end
	return 0
end

local function readOurOfferedItemCount()
	local state = Hive._tradeState
	if type(state) == 'table' then
		local n = tableSize(state[ourTradeRole() .. 'Items'])
		if n > 0 then
			return n
		end
	end
	-- Fallback when listener missed TradeChanged but trade UI is open.
	local n = 0
	pcall(function()
		local tf = findTradeRoot()
		local yf = tf and (tf:FindFirstChild('YourFrame') or tf:FindFirstChild('YourFrame', true))
		local list = yf and yf:FindFirstChild('List')
		if not list then
			return
		end
		for _, c in ipairs(list:GetChildren()) do
			if c:IsA('Frame') or c:IsA('TextButton') then
				n += 1
			end
		end
	end)
	if type(state) == 'table' then
		return math.max(n, tableSize(state[ourTradeRole() .. 'Items']))
	end
	return n
end

-- Sender pays offer + 10% fee; receiver gets `offer`. Cap 1B on receiver.
-- Use ceil(fee) + integer-only afford so float/1.1 noise never over-offers (refunds to alt).
local function velFee(offer)
	offer = math.floor(tonumber(offer) or 0)
	if offer <= 0 then
		return 0
	end
	return math.ceil(offer * 0.1)
end

local function computeVelOffer(cmd)
	if not cmd or cmd == LocalPlayer then
		return 0, 'self'
	end
	-- Do not gate on Hive.role — sticky "commander" role was skipping worker vel.
	if tonumber(Hive.selectedCommanderId) == USER_ID and cmd.UserId == USER_ID then
		return 0, 'self'
	end
	local mine = getVelOf(LocalPlayer)
	local theirs = getVelOf(cmd)
	if type(mine) ~= 'number' then
		return 0, 'no_sender_vel'
	end
	if mine < 2 then
		return 0, 'broke'
	end
	if type(theirs) ~= 'number' then
		-- Prefer sending rather than skipping forever; assume empty room only if unknown.
		theirs = 0
	end
	local room = math.floor(VEL_CAP - theirs)
	if room <= 0 then
		return 0, 'receiver_full'
	end
	-- Integer afford: max offer where offer + ceil(offer*0.1) <= mine.
	-- floor(mine * 10 / 11) is exact for 10% without float division by 1.1.
	local offer = math.min(math.floor(mine * 10 / 11), room)
	while offer > 0 and (offer + velFee(offer)) > mine do
		offer -= 1
	end
	if theirs + offer > VEL_CAP then
		offer = math.max(0, VEL_CAP - theirs)
	end
	return math.max(0, math.floor(offer)), nil, mine, theirs
end

local function fireChangeCurrency(amount)
	amount = math.floor(tonumber(amount) or 0)
	if amount <= 0 then
		return
	end
	-- Match Cardinal Trade UI: Event FireServer("Trade", "TradeChangeCurrency", { offer })
	fireTrade('Trade', 'TradeChangeCurrency', { amount })
end

local function addVelOffer(amount)
	amount = math.floor(tonumber(amount) or 0)
	if amount <= 0 or not velDumpEnabled then
		return false, 'disabled'
	end
	if type(Hive._tradeState) ~= 'table' then
		return false, 'no_trade'
	end
	local before = readOurOfferedVel()
	fireChangeCurrency(amount)
	waitFor(1.25, function()
		local now = readOurOfferedVel()
		return now ~= before or Hive._lastTradeAction == 'cancel'
	end)
	if Hive._lastTradeAction == 'cancel' then
		return false, 'cancel'
	end
	local now = readOurOfferedVel()
	if now >= amount or (now > before and now > 0) then
		task.wait(0.1)
		return true, now
	end
	-- Retry once — state parse sometimes lags behind a successful fire.
	fireChangeCurrency(amount)
	waitFor(1.0, function()
		return readOurOfferedVel() >= amount or Hive._lastTradeAction == 'cancel'
	end)
	now = readOurOfferedVel()
	if now >= amount or (now > before and now > 0) then
		task.wait(0.1)
		return true, now
	end
	-- Optimistic: remote matches UI; do not hard-disable vel for the whole dump.
	notify(('Vel fire %s (state shows %s — continuing)'):format(tostring(amount), tostring(now)))
	return true, now
end

local function offerVelToCommander(cmd)
	if not velDumpEnabled then
		return 0
	end
	if not cmd or cmd == LocalPlayer then
		return 0
	end
	if type(Hive._tradeState) ~= 'table' then
		return 0
	end
	if Hive._velOffered then
		return 0
	end
	local offer, why, mine, theirs = computeVelOffer(cmd)
	if offer <= 0 then
		if why == 'receiver_full' then
			notify('Commander at 1B vel — not sending (would void)')
		elseif why == 'broke' or why == 'no_sender_vel' then
			-- Quiet for broke alts.
		elseif why == 'self' then
			-- Quiet.
		else
			notify('Vel skipped: ' .. tostring(why or 'none'))
		end
		return 0
	end
	local fee = velFee(offer)
	local taxCost = offer + fee
	notify(('Vel → cmd offer %s (fee %s, pay %s, mine %s, cmd %s)'):format(
		tostring(offer),
		tostring(fee),
		tostring(taxCost),
		tostring(mine or getVelOf(LocalPlayer)),
		tostring(theirs or getVelOf(cmd))
	))
	local ok = addVelOffer(offer)
	if ok then
		Hive._velOffered = true
		return offer
	end
	notify('Vel offer failed this trade — will retry next batch')
	return 0
end

local function cancelOpenTrade()
	fireTrade('Trade', 'TradeCancel', {})
	local ok = waitFor(4, function()
		return Hive._lastTradeAction == 'cancel'
	end)
	Hive._tradeState = nil
	return ok
end

local function tradeAborted()
	if not Hive._alive then
		return true
	end
	if Hive._abortTrade then
		return true
	end
	-- Stale dump/deposit coroutine after reload or newer dump started.
	if Hive._dumpGen ~= nil and getgenv().SB2HiveDumpGen ~= Hive._dumpGen then
		return true
	end
	return false
end

local function isCrystalStack(item)
	local n = tostring(item and item.Name or '')
	if n:find('Upgrade Crystal', 1, true) then
		return true
	end
	if n == 'Upgrade Protection Scroll' then
		return true
	end
	return false
end

local function tradePartnerIs(state, cmd)
	if type(state) ~= 'table' or not cmd then
		return false
	end
	local cmdId = cmd.UserId
	if tradeUserId(state, 'Requester') == cmdId or tradeUserId(state, 'Partner') == cmdId then
		return true
	end
	local req = state.Requester
	local par = state.Partner
	if req == cmd or par == cmd then
		return true
	end
	if typeof(req) == 'Instance' and req:IsA('Player') and req.UserId == cmdId then
		return true
	end
	if typeof(par) == 'Instance' and par:IsA('Player') and par.UserId == cmdId then
		return true
	end
	return false
end

local function findTradeRoot()
	local pg = LocalPlayer and LocalPlayer:FindFirstChildOfClass('PlayerGui')
	if not pg then
		return nil
	end
	local card = pg:FindFirstChild('CardinalUI')
	if card then
		local tf = card:FindFirstChild('TradeFrame', true)
		if tf then
			return tf
		end
	end
	return pg:FindFirstChild('TradeFrame', true)
end

local function tradeUiLooksOpen(cmd)
	local tf = findTradeRoot()
	if not tf then
		return false
	end
	local vis = false
	pcall(function()
		vis = tf.Visible == true or (tf.Parent and tf.Parent.Visible == true)
	end)
	if not vis then
		return false
	end
	if not cmd then
		return true
	end
	local partnerLabel = nil
	pcall(function()
		partnerLabel = tf:FindFirstChild('PartnerFrame', true)
		partnerLabel = partnerLabel and partnerLabel:FindFirstChild('PartnerName')
	end)
	if partnerLabel and partnerLabel:IsA('TextLabel') then
		local t = tostring(partnerLabel.Text or '')
		if t:find(cmd.Name, 1, true) then
			return true
		end
	end
	return false
end

local function tradeStateReady(state, cmd)
	if type(state) ~= 'table' then
		return false
	end
	if state.State and state.State ~= 'Trading' then
		return false
	end
	if not tradeUserId(state, 'Requester') or not tradeUserId(state, 'Partner') then
		return false
	end
	if cmd and not tradePartnerIs(state, cmd) then
		return false
	end
	return true
end

local function waitForTradeReady(cmd, timeout)
	timeout = timeout or TRADE_ACCEPT_TIMEOUT
	local ok = waitFor(timeout, function()
		return tradeStateReady(Hive._tradeState, cmd) and Hive._lastTradeAction ~= 'cancel'
	end)
	if ok and type(Hive._tradeState) == 'table' then
		enrichTradeState(Hive._tradeState)
		forwardTradeUI('RequestAccepted', Hive._tradeState)
		-- Accept lag: OnRequestAccepted rebuilds trade inventory. Wait for settle
		-- before AddItem or the first adds are silently dropped (manual click "kickstarts").
		local genAtReady = Hive._tradeGen or 0
		waitFor(2.5, function()
			return Hive._lastTradeAction == 'cancel'
				or ((Hive._tradeGen or 0) > genAtReady and tradeStateReady(Hive._tradeState, cmd))
		end)
		-- Extra settle for accept lag — cold start needs ~2s before first AddItem.
		task.wait(TRADE_UI_SETTLE)
	end
	return ok
end

local function requestTrade(cmd)
	if not cmd then
		return false
	end
	-- Prefer raw InvokeServer — TradeUI.Request no-ops when an internal session flag is set.
	local result = invokeTrade('Trade', 'Request', { cmd })
	if result == true then
		return true
	end
	local tu = getTradeUI()
	if tu and type(tu.Request) == 'function' then
		local ok, success = pcall(tu.Request, cmd.Name)
		if ok and success == true then
			return true
		end
		if ok and success == nil then
			return 'pending'
		end
	end
	return false
end

local function fireAddItem(item)
	-- Prefer raw FireServer for dumps. TradeUI.AddItem has a 0.3s lock (u63) that
	-- silently no-ops if called again too soon — that matched "too fast after accept".
	fireTrade('Trade', 'TradeAddItem', { item })
	return 'raw'
end

local function waitOfferGrew(before, timeout)
	timeout = timeout or 1.0
	return waitFor(timeout, function()
		return readOurOfferedItemCount() > before or Hive._lastTradeAction == 'cancel'
	end)
end

local function addItemFast(item, addedSoFar)
	if tradeAborted() then
		return false, 'abort'
	end
	if Hive._lastTradeAction == 'cancel' then
		return false, 'cancel'
	end
	local before = readOurOfferedItemCount()
	local via = fireAddItem(item)
	-- Always honor game AddItem debounce (~0.3s). Faster waits drop/reject under lag.
	task.wait(TRADE_ADD_DELAY)
	waitOfferGrew(before, addedSoFar <= 1 and 1.5 or 0.6)
	if Hive._lastTradeAction == 'cancel' then
		return false, 'cancel'
	end
	if readOurOfferedItemCount() <= before then
		return false, 'reject'
	end
	return true
end

local function addItemSlow(item, addedSoFar)
	if tradeAborted() then
		return false, 'abort'
	end
	if Hive._lastTradeAction == 'cancel' then
		return false, 'cancel'
	end
	local before = readOurOfferedItemCount()
	local via = fireAddItem(item)
	task.wait(TRADE_ADD_DELAY)
	waitOfferGrew(before, addedSoFar <= 1 and 2.0 or 1.0)
	if addedSoFar > 0 and addedSoFar % TRADE_ADD_PAUSE_EVERY == 0 then
		task.wait(TRADE_ADD_PAUSE)
	end
	if Hive._lastTradeAction == 'cancel' then
		return false, 'cancel'
	end
	if readOurOfferedItemCount() <= before then
		return false, 'reject'
	end
	return true
end

local function openTradeWith(cmd)
	-- Serialize open attempts — parallel dump waiters were TradeCancel-storming each other.
	local g = getgenv()
	local lockAt = tonumber(g.SB2HiveTradeOpenAt) or 0
	if g.SB2HiveTradeOpenLock and (tick() - lockAt) < 30 then
		return false
	end
	g.SB2HiveTradeOpenLock = true
	g.SB2HiveTradeOpenAt = tick()
	local function release()
		if g.SB2HiveTradeOpenAt == g.SB2HiveTradeOpenAt then
			g.SB2HiveTradeOpenLock = false
		end
	end

	-- Only reuse a real server trade state — UI-visible alone used to skip Request entirely.
	local existing = Hive._tradeState
	if type(existing) == 'table' and tradePartnerIs(existing, cmd) and tradeStateReady(existing, cmd) and Hive._lastTradeAction ~= 'cancel' then
		forwardTradeUI('RequestAccepted', existing)
		task.wait(TRADE_UI_SETTLE)
		release()
		return true
	end

	-- Clear stale session so Request is not blocked.
	-- IMPORTANT: do not FireServer TradeCancel just because lastAction=='cancel' —
	-- a delayed cancel from cleanup was landing after RequestAccept and killing the new trade
	-- (last stuck on cancel → confirm never succeeds → dump never continues).
	if type(Hive._tradeState) == 'table' or tradeUiLooksOpen(cmd) then
		cancelOpenTrade()
		task.wait(0.35)
		Hive._lastTradeAction = nil
		Hive._tradeState = nil
	elseif Hive._lastTradeAction == 'cancel' then
		Hive._lastTradeAction = nil
	end

	local reqGen = (Hive._tradeReqGen or 0) + 1
	Hive._tradeReqGen = reqGen
	-- Ignore stale TradeCancel from the cancel above for a short window.
	Hive._ignoreCancelUntil = tick() + 2.5

	local req = requestTrade(cmd)
	if req == true or req == 'pending' then
		if Hive._lastTradeAction == 'cancel' then
			Hive._lastTradeAction = nil
		end
	elseif req == false then
		local quick = waitFor(2.5, function()
			return tradeStateReady(Hive._tradeState, cmd)
		end)
		if not quick then
			cancelOpenTrade()
			task.wait(0.35)
			Hive._lastTradeAction = nil
			requestTrade(cmd)
		end
	end

	local ok = waitForTradeReady(cmd, TRADE_ACCEPT_TIMEOUT)
	local opened = ok and Hive._lastTradeAction ~= 'cancel'
	if opened then
		task.wait(TRADE_UI_SETTLE)
	end
	release()
	return opened
end

local function confirmTrade()
	Hive._addingItems = false
	local settle = Hive._addedSlow and TRADE_SETTLE or TRADE_SETTLE_FAST
	task.wait(settle)
	if tradeAborted() or Hive._lastTradeAction == 'cancel' then
		return false
	end
	local genBefore = Hive._tradeGen or 0
	fireTrade('Trade', 'TradeConfirm', {})
	task.wait(0.2)
	fireTrade('Trade', 'TradeAccept', {})
	local tu = getTradeUI()
	if tu then
		pcall(function()
			if type(tu.Confirm) == 'function' then
				tu.Confirm()
			end
		end)
		task.wait(0.15)
		pcall(function()
			if type(tu.Accept) == 'function' then
				tu.Accept()
			end
		end)
	end
	-- #region agent log
	pcall(function()
		warn('[TRADE-DBG] confirmTrade fired last=' .. tostring(Hive._lastTradeAction))
	end)
	-- #endregion
	local ok = waitFor(TRADE_COMPLETE_TIMEOUT, function()
		if Hive._lastTradeAction == 'completed' or Hive._lastTradeAction == 'cancel' then
			return true
		end
		-- Completion event name can differ; UI closed + no state == done.
		if type(Hive._tradeState) ~= 'table' and not tradeUiLooksOpen() then
			Hive._lastTradeAction = 'completed'
			return true
		end
		return false
	end)
	local success = ok and Hive._lastTradeAction == 'completed'
	-- #region agent log
	pcall(function()
		warn('[TRADE-DBG] confirmTrade result ok='
			.. tostring(success)
			.. ' last='
			.. tostring(Hive._lastTradeAction)
			.. ' gen='
			.. tostring(genBefore)
			.. '→'
			.. tostring(Hive._tradeGen))
	end)
	-- #endregion
	if success then
		Hive._tradeState = nil
		getgenv().SB2HiveTradeOpenLock = false
	end
	return success
end

-- addFn(addOne) should call addOne(item) up to TRADE_MAX times. Returns added count.
local function runTradeBatch(cmd, addFn)
	local opened = false
	for attempt = 1, 40 do
		if tradeAborted() then
			return 0, 'abort'
		end
		if openTradeWith(cmd) then
			opened = true
			break
		end
		if attempt == 1 or attempt % 5 == 0 then
			notify(('Waiting for commander trade (%s)'):format(tostring(attempt)))
		end
		task.wait(3)
	end
	if not opened then
		return 0, 'request'
	end

	Hive._addingItems = true
	Hive.status = 'trading'
	Hive._velOffered = false
	Hive._addedSlow = false
	local added = 0
	local function addOne(item, pace)
		if added >= TRADE_MAX then
			return false, 'full'
		end
		if readOurOfferedItemCount() >= TRADE_MAX then
			return false, 'full'
		end
		local useFast = pace == 'fast' or (pace ~= 'slow' and isCrystalStack(item))
		-- Until the first item lands, force slow path + retries (accept lag).
		if added == 0 then
			useFast = false
		end
		if not useFast then
			Hive._addedSlow = true
		end
		local fn = useFast and addItemFast or addItemSlow
		local ok, why = fn(item, added + 1)
		if not ok and why == 'reject' and added == 0 then
			for retry = 1, 4 do
				if tradeAborted() or Hive._lastTradeAction == 'cancel' then
					break
				end
				task.wait(0.4)
				ok, why = addItemSlow(item, 1)
				if ok then
					break
				end
			end
		end
		if not ok then
			-- Full offer rejects forever if we keep trying more items — treat as full.
			if why == 'reject' and readOurOfferedItemCount() >= TRADE_MAX then
				return false, 'full'
			end
			return false, why
		end
		added += 1
		return true
	end

	local _, why = addFn(addOne)
	Hive._addingItems = false
	if why == 'full' then
		why = nil
	end
	if why == 'abort' or tradeAborted() then
		cancelOpenTrade()
		return added, 'abort'
	end
	if why == 'cancel' or Hive._lastTradeAction == 'cancel' then
		notify('Trade bounced — waiting, then retry')
		task.wait(1.4)
		return added, 'bounce'
	end
	-- Trust server-side offer count — local add counter could lie if FireServer was ignored.
	local offered = readOurOfferedItemCount()
	added = math.max(added, offered)
	if added <= 0 and offered <= 0 and not Hive._velOffered then
		cancelOpenTrade()
		return 0, 'empty'
	end
	if not confirmTrade() then
		if Hive._lastTradeAction == 'cancel' then
			notify('Trade bounced on confirm — retry')
			task.wait(1.4)
			return added, 'bounce'
		end
		cancelOpenTrade()
		return added, 'confirm'
	end
	task.wait(TRADE_BETWEEN)
	return added, 'ok'
end

local function depositCrystals(order)
	if Hive._depositBusy then
		return
	end
	local payload = order and order.payload or {}
	local rarity = tostring(payload.rarity or 'Legendary')
	local amount = math.max(1, math.floor(tonumber(payload.amount) or 64))
	local crystalName = rarity .. ' Upgrade Crystal'
	if rarity == 'Scroll' or rarity == 'Protection' then
		crystalName = 'Upgrade Protection Scroll'
	end

	local cmd = commanderPlayer(order)
	if not cmd then
		notify('Deposit failed — commander not in this server (Rally first)')
		Hive.status = 'deposit_failed'
		return
	end

	local inv = getInventory()
	local item = inv and inv:FindFirstChild(crystalName)
	if not item then
		notify('No ' .. crystalName)
		Hive.status = 'deposit_failed'
		return
	end

	Hive._abortTrade = false
	Hive._depositBusy = true
	Hive.status = 'trading'
	setupTradeListener()

	task.spawn(function()
		local remaining = amount
		local totalSent = 0
		while remaining > 0 and not tradeAborted() do
			item = getInventory() and getInventory():FindFirstChild(crystalName)
			if not item then
				break
			end
			local owned = itemCount(item)
			if owned <= 0 then
				break
			end
			local want = math.min(remaining, owned, TRADE_MAX)
			local added, status = runTradeBatch(cmd, function(addOne)
				local n = 0
				while n < want do
					item = getInventory() and getInventory():FindFirstChild(crystalName)
					if not item or itemCount(item) <= 0 then
						break
					end
					local ok, why = addOne(item, 'fast')
					if not ok then
						return false, why
					end
					n += 1
				end
				return true
			end)
			if status == 'abort' or status == 'request' or status == 'confirm' then
				if status ~= 'abort' then
					notify('Crystal deposit failed: ' .. tostring(status))
				end
				break
			end
			if status == 'empty' then
				break
			end
			if status == 'ok' then
				totalSent += added
				remaining -= added
			end
			if added <= 0 and status ~= 'bounce' then
				break
			end
		end
		Hive._depositBusy = false
		Hive._addingItems = false
		if Hive.status == 'trading' then
			Hive.status = 'idle'
		end
		if totalSent > 0 then
			notify(('Deposited %dx %s'):format(totalSent, crystalName))
		elseif not tradeAborted() then
			notify('No crystals deposited')
		end
	end)
end

local function dumpAllItems(order)
	-- Atomic across reloads/stacked heartbeats (plain _depositBusy races).
	if Hive._depositBusy or getgenv().SB2HiveDumpBusy then
		return
	end
	-- Bump gen first so any stale waitFor/cancel loops die before we take the lock.
	getgenv().SB2HiveDumpGen = (getgenv().SB2HiveDumpGen or 0) + 1
	local dumpGen = getgenv().SB2HiveDumpGen
	Hive._dumpGen = dumpGen
	getgenv().SB2HiveDumpBusy = true
	Hive._depositBusy = true
	local cmd = commanderPlayer(order)
	if not cmd then
		getgenv().SB2HiveDumpBusy = false
		Hive._depositBusy = false
		notify('Dump failed — commander not in this server (Rally first)')
		Hive.status = 'deposit_failed'
		return
	end
	if cmd == LocalPlayer then
		getgenv().SB2HiveDumpBusy = false
		Hive._depositBusy = false
		notify('Dump skipped — this client is the commander')
		return
	end

	Hive._abortTrade = false
	Hive.status = 'trading'
	velDumpEnabled = true
	setupTradeListener()
	ensureGameChatVisible()
	hideRobloxChatOnly()

	task.spawn(function()
		local function dumpDone()
			if getgenv().SB2HiveDumpGen == dumpGen then
				getgenv().SB2HiveDumpBusy = false
			end
			Hive._depositBusy = false
			Hive._addingItems = false
			if Hive.status == 'trading' then
				Hive.status = 'idle'
			end
		end
		-- Same-server only — do not TP/snap to commander for trading.
		if not commanderPlayer(order) then
			dumpDone()
			notify('Dump aborted — commander left this server')
			return
		end
		ensureGameChatVisible()
		notify(('Dump start — same server as %s (no TP)'):format(cmd.Name))

		local equipped = equippedIdSet()
		local inv = getInventory()
		local tradeable = 0
		if inv then
			for _, item in ipairs(inv:GetChildren()) do
				if canTradeItem(item, equipped) then
					tradeable += 1
				end
			end
		end
		notify(('Dump start — %s tradeable (locked/equipped skipped)'):format(tostring(tradeable)))

		local totalSent = 0
		local batches = 0
		local emptyStreak = 0
		local loopIter = 0
		while not tradeAborted() and getgenv().SB2HiveDumpGen == dumpGen do
			loopIter += 1
			hideRobloxChatOnly()
			equipped = equippedIdSet()
			inv = getInventory()
			if not inv then
				break
			end
			local hasAny = false
			for _, item in ipairs(inv:GetChildren()) do
				if canTradeItem(item, equipped) then
					hasAny = true
					break
				end
			end
			local wantVel = velDumpEnabled and (select(1, computeVelOffer(cmd)) or 0) > 0
			if not hasAny and not wantVel then
				break
			end

			local addedUniques = {}
			local itemsFired = 0
			local added, status = runTradeBatch(cmd, function(addOne)
				equipped = equippedIdSet()
				inv = getInventory()
				local fired = 0
				if inv then
					local function addFromInv(crystalsOnly)
						for _, item in ipairs(inv:GetChildren()) do
							if tradeAborted() then
								return false, 'abort'
							end
							if not canTradeItem(item, equipped) then
								continue
							end
							if crystalsOnly ~= isCrystalStack(item) then
								continue
							end
							local pace = crystalsOnly and 'fast' or 'slow'
							if item:FindFirstChild('Count') then
								local guard = 0
								while item.Parent and itemCount(item) > 0 and guard < TRADE_MAX do
									local ok, why = addOne(item, pace)
									if not ok then
										if why == 'reject' then
											if readOurOfferedItemCount() >= TRADE_MAX then
												return false, 'full'
											end
											break
										end
										return false, why
									end
									fired += 1
									itemsFired += 1
									guard += 1
								end
							else
								local id = item:IsA('ValueBase') and tonumber(item.Value) or item
								if not addedUniques[id] then
									addedUniques[id] = true
									local ok, why = addOne(item, pace)
									if not ok then
										if why == 'reject' then
											if readOurOfferedItemCount() >= TRADE_MAX then
												return false, 'full'
											end
											continue
										end
										return false, why
									end
									fired += 1
									itemsFired += 1
								end
							end
						end
						return true
					end
					-- Gear/uniques first — crystal stacks used to fill all 400 slots before items.
					local lastWhy = nil
					local ok, why = addFromInv(false)
					lastWhy = why
					if ok or why == 'full' then
						ok, why = addFromInv(true)
						if why then
							lastWhy = why
						end
					end
					-- Always try vel before closing the add phase (even when item slots are full).
					if lastWhy ~= 'abort' and lastWhy ~= 'cancel' and Hive._lastTradeAction ~= 'cancel' then
						offerVelToCommander(cmd)
					end
					if lastWhy == 'abort' or lastWhy == 'cancel' then
						return false, lastWhy
					end
					if lastWhy == 'full' then
						return false, 'full'
					end
					if ok == false and lastWhy then
						return false, lastWhy
					end
				end
				return true
			end)

			if status == 'abort' then
				break
			end
			-- Confirm timeout / miss: bounce and open a fresh trade instead of ending the dump.
			if status == 'confirm' then
				notify('Dump confirm missed — retrying next trade')
				cancelOpenTrade()
				Hive._tradeState = nil
				Hive._lastTradeAction = nil
				getgenv().SB2HiveTradeOpenLock = false
				task.wait(TRADE_BETWEEN)
				status = 'bounce'
			end
			if status == 'bounce' then
				Hive._tradeState = nil
				getgenv().SB2HiveTradeOpenLock = false
				task.wait(0.75)
			end
			if status == 'request' then
				notify('Dump trade failed: ' .. tostring(status))
				-- Still retry a few request failures instead of killing the whole dump.
				emptyStreak += 1
				if emptyStreak >= 5 then
					break
				end
				getgenv().SB2HiveTradeOpenLock = false
				Hive._tradeState = nil
				task.wait(TRADE_BETWEEN)
				status = 'bounce'
			end
			if status == 'empty' then
				emptyStreak += 1
				if emptyStreak >= 2 then
					notify('Dump empty — no items stuck in trade (check locked / distance)')
					break
				end
			elseif status == 'ok' and (added > 0 or Hive._velOffered) then
				emptyStreak = 0
				totalSent += added
				batches += 1
				notify(('Dump batch %s: ~%s adds'):format(tostring(batches), tostring(added)))
				-- Clear session so the next Request is not blocked by stale open UI/state.
				Hive._tradeState = nil
				Hive._lastTradeAction = nil
				getgenv().SB2HiveTradeOpenLock = false
				task.wait(0.5)
			elseif status ~= 'bounce' then
				break
			end
		end
		dumpDone()
		if tradeAborted() then
			notify('Dump stopped')
		else
			notify(('Dump done — ~%s item adds%s'):format(
				tostring(totalSent),
				Hive._velOffered and ' + vel' or ''
			))
		end
	end)
end

local function handleOrder(order)
	if type(order) ~= 'table' or not order.seq then
		return
	end
	local seq = tonumber(order.seq) or 0
	if seq <= Hive.lastOrderSeq then
		return
	end
	Hive.lastOrderSeq = seq

	-- Left the hive: consume seq so we do not burst-execute on rejoin.
	if not Hive._alive or Hive.role == 'idle' or not Hive.fileOptedIn() then
		stopFollow()
		return
	end

	local t = order.type
	-- The selected commander is the TP target — they do not run most worker orders.
	-- These apply to every hive client including the commander.
	local allClients = t == 'solo_resume'
		or t == 'solo_resume_off'
		or t == 'boss_route_on'
		or t == 'boss_route_off'
		or t == 'hide_menu'
	if tonumber(order.commanderId) == USER_ID and not allClients then
		-- Still arm trade accept when workers are dumping to us.
		if t == 'dump_items' or t == 'deposit_crystals' then
			Hive._acceptHiveTrades = true
			setupTradeListener()
			Hive.status = 'commanding'
			notify('Workers dumping — accepting hive trades')
		end
		return
	end

	local function setBossRouteToggle(on)
		local okSet = false
		pcall(function()
			if on ~= true and type(getgenv().SB2StopBossWaypointRoute) == 'function' then
				-- Hard stop (bumps gen) even when the toggle is already false.
				pcall(getgenv().SB2StopBossWaypointRoute, 'hive-off')
			end
			if type(getgenv().SB2SetBossWaypointRoute) == 'function' then
				okSet = getgenv().SB2SetBossWaypointRoute(on == true) == true
			end
		end)
		if okSet then
			return true
		end
		pcall(function()
			local toggles = resolveToggles()
			local toggle = toggles and toggles.BossWaypointRoute
			if type(toggle) == 'table' and type(toggle.SetValue) == 'function' then
				if on ~= true then
					if type(getgenv().SB2StopBossWaypointRoute) == 'function' then
						pcall(getgenv().SB2StopBossWaypointRoute, 'hive-off')
					end
				end
				if toggle.Value == on then
					-- Force OnChanged so a stuck-on/off still restarts or clears.
					toggle:SetValue(not on)
					task.wait()
				end
				toggle:SetValue(on == true)
				okSet = true
			end
		end)
		return okSet
	end

	if t == 'stop' then
		Hive._abortTrade = true
		stopFollow()
		setCombatToggles(false, false)
		Hive.status = 'idle'
		notify('Order: stop')
	elseif t == 'follow' then
		startFollow('follow', order)
		notify('Order: follow')
	elseif t == 'stack' then
		startFollow('stack', order)
		notify('Order: stack')
	elseif t == 'rally' then
		stopFollow()
		rallyToCommander(order)
	elseif t == 'combat_on' then
		setCombatToggles(true, true)
		Hive.status = 'combat'
		notify('Order: combat on')
	elseif t == 'combat_off' then
		setCombatToggles(false, false)
		if Hive.status == 'combat' then
			Hive.status = 'idle'
		end
		notify('Order: combat off')
	elseif t == 'solo_resume' or t == 'solo_resume_off' then
		local payload = type(order.payload) == 'table' and order.payload or {}
		local on = true
		if t == 'solo_resume_off' then
			on = false
		elseif payload.on ~= nil then
			on = payload.on == true
		elseif payload.enabled ~= nil then
			on = payload.enabled == true
		end
		local okSet = false
		pcall(function()
			if type(getgenv().SB2SetSoloResume) == 'function' then
				okSet = getgenv().SB2SetSoloResume(on) == true
			end
			if not okSet then
				local toggles = resolveToggles()
				local resume = toggles and toggles.SoloCombatResume
				if type(resume) == 'table' and type(resume.SetValue) == 'function' then
					if resume.Value == on then
						resume:SetValue(not on)
						task.wait()
					end
					resume:SetValue(on)
					okSet = true
				end
			end
		end)
		notify(okSet and (on and 'Order: resume on' or 'Order: resume off') or 'Order: resume missing toggle')
	elseif t == 'boss_route_on' then
		local okSet = setBossRouteToggle(true)
		notify(okSet and 'Order: boss route on' or 'Order: boss route missing toggle')
	elseif t == 'boss_route_off' then
		local okSet = setBossRouteToggle(false)
		notify(okSet and 'Order: boss route off' or 'Order: boss route missing toggle')
	elseif t == 'hide_menu' then
		pcall(function()
			if type(getgenv().SB2HidePlayerToolsMenu) == 'function' then
				getgenv().SB2HidePlayerToolsMenu()
			end
		end)
		notify('Order: hide menu')
	elseif t == 'deposit_crystals' then
		depositCrystals(order)
	elseif t == 'dump_items' then
		dumpAllItems(order)
	else
		notify('Unknown order: ' .. tostring(t))
	end
end

function Hive.listPeers()
	return listPeers()
end

function Hive.readOrder()
	return readOrder()
end

function Hive.issue(orderType, payload)
	if not Hive._alive then
		notify('Join hive first')
		return nil
	end
	local order = writeOrder(orderType, payload, Hive.selectedCommanderId)
	if order then
		notify(('Issued %s → commander %s (#%s)'):format(
			tostring(orderType),
			tostring(order.commanderId),
			tostring(order.seq)
		))
	else
		notify('Failed to write order (writefile?)')
	end
	return order
end

function Hive.peerNames()
	local names = {}
	for _, p in ipairs(listPeers()) do
		names[#names + 1] = tostring(p.name)
	end
	table.sort(names)
	return names
end

function Hive.commanderName()
	local data = readCommanderFile()
	local id = tonumber(Hive.selectedCommanderId) or (data and tonumber(data.userId))
	if id then
		for _, p in ipairs(listPeers()) do
			if p.userId == id then
				return tostring(p.name), id
			end
		end
	end
	if data and type(data.name) == 'string' and data.name ~= '' then
		return data.name, id
	end
	return nil, id
end

function Hive.peerByName(name)
	name = string.lower(tostring(name or ''))
	for _, p in ipairs(listPeers()) do
		if string.lower(tostring(p.name)) == name or string.lower(tostring(p.displayName or '')) == name then
			return p
		end
	end
	return nil
end

function Hive.syncRoleFromCommanderFile()
	local data = readCommanderFile()
	local id = data and tonumber(data.userId)
	if not id or id == 0 then
		return
	end
	Hive.selectedCommanderId = id
	if id == USER_ID then
		Hive.role = 'commander'
		if Hive.status == 'off' or Hive.status == 'idle' then
			Hive.status = 'commanding'
		end
		Hive._acceptHiveTrades = true
		-- Listener is session-bound; do not reconnect from sync (caused storms).
	elseif Hive.role == 'commander' then
		Hive.role = 'worker'
		Hive.status = Hive.status == 'commanding' and 'idle' or Hive.status
		-- Do not clear _acceptHiveTrades — UI toggle owns it for receivers.
	end
end

function Hive.setSelectedCommander(userId, name)
	userId = tonumber(userId)
	if not userId then
		notify('No commander selected')
		return false
	end
	local already = Hive.selectedCommanderId == userId
	Hive.selectedCommanderId = userId
	writeJson(COMMANDER_PATH, {
		userId = userId,
		name = name or '',
		ts = tick(),
	})
	Hive.syncRoleFromCommanderFile()
	if userId == USER_ID then
		stopFollow()
	end
	writeHeartbeat()
	if not already then
		notify(('Commanding client → %s'):format(tostring(name ~= '' and name or userId)))
	end
	return true
end

function Hive.claimCommander()
	return Hive.setSelectedCommander(USER_ID, LocalPlayer.Name)
end

function Hive.stopMovement()
	stopFollow()
	if Hive.status == 'follow' or Hive.status == 'stack' or Hive.status == 'waiting_commander' then
		Hive.status = 'idle'
	end
end

function Hive.becomeWorker()
	stopFollow()
	Hive.role = 'worker'
	Hive.status = 'idle'
	Hive._acceptHiveTrades = false
	writeHeartbeat()
	notify('You are hive worker')
end

function Hive.setAcceptHiveTrades(on)
	Hive._acceptHiveTrades = on == true
	if on then
		setupTradeListener()
	end
end

function Hive.peerSummary()
	local peers = listPeers()
	local _, cmdId = Hive.commanderName()
	cmdId = tonumber(cmdId) or tonumber(Hive.selectedCommanderId)
	local lines = {}
	for _, p in ipairs(peers) do
		local age = math.floor(tick() - (p.ts or tick()))
		local same = (p.jobId == game.JobId) and 'HERE' or 'away'
		local role = tostring(p.role)
		if cmdId and p.userId == cmdId then
			role = 'commander'
		elseif role == 'commander' then
			role = 'worker'
		end
		lines[#lines + 1] = ('%s [%s] %s %s %ds'):format(
			tostring(p.name),
			role,
			tostring(p.status),
			same,
			age
		)
	end
	if #lines == 0 then
		return 'No peers (start Hive on other clients)'
	end
	return table.concat(lines, '\n')
end

function Hive.start()
	if not Hive.fileOptedIn() then
		if Hive._alive then
			Hive.stop({ leave = false })
		end
		notify('Join hive is off on this client')
		return Hive
	end
	if Hive._alive then
		return Hive
	end
	if type(writefile) ~= 'function' or type(readfile) ~= 'function' then
		notify('Hive needs writefile/readfile')
		return Hive
	end
	ensureDirs()
	touchRoster()
	Hive._alive = true
	Hive.syncRoleFromCommanderFile()
	if Hive.role == 'idle' then
		Hive.role = 'worker'
	end
	Hive.status = Hive.status == 'off' and 'idle' or Hive.status
	-- Do not re-run the order that caused a teleport (that was locking follow on join).
	do
		local existing = readOrder()
		if existing and tonumber(existing.seq) then
			Hive.lastOrderSeq = math.max(Hive.lastOrderSeq or 0, tonumber(existing.seq) or 0)
		end
	end
	setupTradeListener()
	if Hive.role == 'commander' then
		Hive._acceptHiveTrades = true
	end
	ensureGameChatVisible()
	hideRobloxChatOnly()
	writeHeartbeat()

	local pending = readJson(pendingSnapPath())
	if type(pending) == 'table' then
		if type(delfile) == 'function' then
			pcall(delfile, pendingSnapPath())
		end
		task.spawn(function()
			for _ = 1, 40 do
				if getRoot(LocalPlayer) then
					break
				end
				task.wait(0.15)
			end
			if Hive._alive then
				snapOnceToCommander({
					commanderId = pending.commanderId,
					payload = { radius = 5 },
				})
			end
		end)
	end

	local acc = 0
	local orderAcc = 0
	-- One Heartbeat per session � PlayerTools reloads were stacking 4�6 and re-arming dumps.
	pcall(function()
		local old = getgenv().SB2HiveHbConn
		if old then
			old:Disconnect()
		end
	end)
	local okHb, conn = pcall(function()
		return RunService.Heartbeat:Connect(function(dt)
		if not Hive._alive then
			return
		end
		if not Hive.fileOptedIn() then
			Hive.stop({ leave = false })
			return
		end
		acc += dt
		orderAcc += dt
		if acc >= HEARTBEAT_INTERVAL then
			acc = 0
			Hive.syncRoleFromCommanderFile()
			writeHeartbeat()
		end
		if orderAcc >= ORDER_POLL_INTERVAL then
			orderAcc = 0
			local order = readOrder()
			if order then
				handleOrder(order)
			end
		end
		end)
	end)
	if okHb then
		getgenv().SB2HiveHbConn = conn
		Hive._conns[#Hive._conns + 1] = conn
	end
	local lastOnline = tonumber(getgenv().SB2HiveLastOnlineNotifyAt) or 0
	if (os.clock() - lastOnline) > 3 then
		getgenv().SB2HiveLastOnlineNotifyAt = os.clock()
		notify('Hive online as ' .. Hive.role)
	end
	return Hive
end

function Hive.stop(opts)
	opts = type(opts) == 'table' and opts or {}
	Hive._abortTrade = true
	getgenv().SB2HiveDumpGen = (getgenv().SB2HiveDumpGen or 0) + 1
	getgenv().SB2HiveDumpBusy = false
	getgenv().SB2HiveTradeOpenLock = false
	Hive._alive = false
	Hive.role = 'idle'
	stopFollow()
	local order = readOrder()
	if order and tonumber(order.seq) then
		Hive.lastOrderSeq = math.max(Hive.lastOrderSeq or 0, tonumber(order.seq) or 0)
	end
	for _, c in ipairs(Hive._conns) do
		pcall(function()
			c:Disconnect()
		end)
	end
	Hive._conns = {}
	getgenv().SB2HiveHbConn = nil
	-- Soft reload (leave=false): keep session trade listener — reconnect storms killed mid-trade accepts.
	if opts.leave ~= false then
		pcall(function()
			local tc = Hive._tradeConn or getgenv().SB2HiveTradeConn
			if tc then
				tc:Disconnect()
			end
		end)
		Hive._tradeConn = nil
		getgenv().SB2HiveTradeConn = nil
		getgenv().SB2HiveTradeBound = false
		clearCommanderIfSelf()
		leaveRoster()
		buryPeerFile()
	else
		Hive._tradeConn = getgenv().SB2HiveTradeConn
	end
	Hive.status = 'off'
	Hive._acceptHiveTrades = false
	Hive._addingItems = false
	-- Soft reload (leave=false) stays quiet — PT UI rebuilds were spamming offline/online.
	if opts.leave ~= false then
		notify('Hive offline')
	end
end

function Hive.isAlive()
	return Hive._alive == true
end

local function optInPath()
	return HIVE_DIR .. '/optin_' .. tostring(USER_ID) .. '.txt'
end

function Hive.fileOptedIn()
	if type(isfile) ~= 'function' or type(readfile) ~= 'function' then
		return false
	end
	local ok, exists = pcall(isfile, optInPath())
	if not (ok and exists) then
		return false
	end
	local okRead, body = pcall(readfile, optInPath())
	if not okRead then
		return false
	end
	local s = tostring(body or ''):gsub('%s+', ''):lower()
	if s == 'false' or s == '0' or s == 'off' or s == 'no' then
		return false
	end
	return s == 'true' or s == '1' or s == 'yes' or s == 'on'
end

function Hive.writeOptedIn(on)
	ensureDirs()
	if type(writefile) ~= 'function' then
		return
	end
	pcall(writefile, optInPath(), on and 'true' or 'false')
end

-- ── Tribute drop → Discord webhook ───────────────────────────────

local function normalizeDiscordWebhookUrl(raw)
	local url = tostring(raw or '')
	-- People paste <url>, quotes, newlines, or trailing junk.
	url = url:gsub('^%s+', ''):gsub('%s+$', '')
	url = url:gsub('^<', ''):gsub('>$', '')
	url = url:gsub('^["\']', ''):gsub('["\']$', '')
	url = url:gsub('%s+', '')
	-- discordapp.com / canary / ptb all work; normalize host for our checks + POST.
	url = url:gsub('^https://discordapp%.com/', 'https://discord.com/')
	url = url:gsub('^https://canary%.discord%.com/', 'https://discord.com/')
	url = url:gsub('^https://ptb%.discord%.com/', 'https://discord.com/')
	url = url:gsub('^http://discord%.com/', 'https://discord.com/')
	url = url:gsub('^http://discordapp%.com/', 'https://discord.com/')
	return url
end

local function isDiscordWebhookUrl(url)
	if type(url) ~= 'string' or url == '' then
		return false
	end
	-- Accept discord.com and legacy discordapp.com (pre-normalize or raw).
	if url:find('discord.com/api/webhooks/', 1, true) then
		return true
	end
	if url:find('discordapp.com/api/webhooks/', 1, true) then
		return true
	end
	return false
end

local function httpRequest(opts)
	local req = (syn and syn.request)
		or http_request
		or (http and http.request)
		or request
	if type(req) ~= 'function' then
		return false, 'no request'
	end
	local ok, res = pcall(req, opts)
	return ok, res
end

local function itemDbRarity(itemName)
	local db = ReplicatedStorage:FindFirstChild('Database')
	local items = db and db:FindFirstChild('Items')
	local ref = items and items:FindFirstChild(itemName)
	local rar = ref and ref:FindFirstChild('Rarity')
	if rar and rar:IsA('ValueBase') then
		local s = tostring(rar.Value or '')
		if s == 'Uncomon' then
			s = 'Uncommon'
		end
		return s
	end
	return ''
end

local function inventoryInstanceId(item)
	if not item then
		return nil
	end
	if item:IsA('ValueBase') then
		local id = tonumber(item.Value)
		if id and id ~= 0 then
			return tostring(id)
		end
	end
	return item:GetFullName()
end

local function readLocalTestPing()
	-- Machine-local only (PlayerTools/hive/LOCAL_TEST_PING). Never shipped in version.json.
	-- Lets your Potassium testing copy default <@you> without baking an ID into published HiveMind.
	local path = HIVE_DIR .. '/LOCAL_TEST_PING'
	if type(isfile) ~= 'function' or not isfile(path) then
		return ''
	end
	local ok, body = pcall(readfile, path)
	if not ok or type(body) ~= 'string' then
		return ''
	end
	return tostring(body):gsub('%D', '')
end

local function writeTributeWebhookConfig(url, enabled, ping)
	ensureDirs()
	writeJson(tributeWebhookPath(), {
		url = tostring(url or ''),
		enabled = enabled == true,
		ping = tostring(ping or ''):gsub('%D', ''),
		userId = tonumber(USER_ID) or 0,
		username = LocalPlayer and LocalPlayer.Name or '',
		t = os.time(),
	})
end

local function readTributeWebhookConfig()
	-- Prefer per-account file so Nick/friend don't share URL/ping on the same PC.
	local data = readJson(tributeWebhookPath())
	if type(data) == 'table' then
		local url = normalizeDiscordWebhookUrl(type(data.url) == 'string' and data.url or '')
		local on = data.enabled == true
		local ping = type(data.ping) == 'string' and data.ping:gsub('%D', '') or ''
		if ping == '' then
			ping = readLocalTestPing()
		end
		return url, on, ping
	end
	-- Legacy shared hive/tribute_webhook.json — migrate once.
	-- Never reuse another account's Discord ping (friend must not get Nick's <@id>).
	local legacy = readJson(TRIBUTE_WEBHOOK_PATH)
	if type(legacy) ~= 'table' then
		local localPing = readLocalTestPing()
		return '', false, localPing
	end
	local url = normalizeDiscordWebhookUrl(type(legacy.url) == 'string' and legacy.url or '')
	local on = legacy.enabled == true
	local ping = ''
	local legacyOwner = tonumber(legacy.userId)
	if legacyOwner and legacyOwner == tonumber(USER_ID) and type(legacy.ping) == 'string' then
		ping = legacy.ping:gsub('%D', '')
	end
	if ping == '' then
		ping = readLocalTestPing()
	end
	-- Persist per-account immediately so later logins don't keep reading the shared file.
	if url ~= '' or on then
		writeTributeWebhookConfig(url, on, ping)
	end
	return url, on, ping
end

local function stopTributeWatch()
	local c = Hive._tributeWatchConn
	if c then
		pcall(function()
			c:Disconnect()
		end)
	end
	Hive._tributeWatchConn = nil
	getgenv().SB2HiveTributeWatchConn = nil
end

local function snapshotTributeInventory()
	local known = {}
	local inv = getInventory()
	if not inv then
		return known
	end
	for _, item in ipairs(inv:GetChildren()) do
		local id = inventoryInstanceId(item)
		if id then
			known[id] = true
		end
	end
	return known
end

local function postTributeWebhook(payload)
	local url = normalizeDiscordWebhookUrl(Hive._tributeWebhookUrl)
	Hive._tributeWebhookUrl = url
	if not isDiscordWebhookUrl(url) then
		return false, 'bad url'
	end
	local user = LocalPlayer and LocalPlayer.Name or '?'
	local title = payload.name or 'Tribute'
	if payload.upgrade then
		title = ('%s (+%s)'):format(tostring(title), tostring(payload.upgrade))
	end
	local timeStr = os.date('%Y-%m-%d %H:%M:%S')
	local pingId = tostring(Hive._tributePing or ''):gsub('%D', '')
	-- Message body is ping-only (no extra text). Details live in the embed fields.
	local content = ''
	local allowed = { parse = {} }
	if pingId ~= '' then
		content = ('<@%s>'):format(pingId)
		allowed = { parse = {}, users = { pingId } }
	end
	local body = HttpService:JSONEncode({
		content = content,
		allowed_mentions = allowed,
		embeds = {
			{
				title = '🏆 Tribute drop',
				color = 0xF1C40F,
				fields = {
					{ name = 'ITEM', value = tostring(title), inline = false },
					{ name = 'ACCOUNT', value = tostring(user), inline = false },
					{ name = 'TIME', value = tostring(timeStr), inline = false },
				},
			},
		},
	})
	local done, result
	local finished = false
	task.spawn(function()
		local ok, res = httpRequest({
			Url = url,
			Method = 'POST',
			Headers = { ['Content-Type'] = 'application/json' },
			Body = body,
		})
		done, result = ok, res
		finished = true
	end)
	-- Non-blocking for drops; test path can wait briefly via returned waiter.
	return true, function(timeout)
		local deadline = os.clock() + (tonumber(timeout) or 4)
		while not finished and os.clock() < deadline do
			task.wait(0.05)
		end
		return done, result
	end
end

local function onTributeInventoryItem(item)
	if not Hive._tributeWebhookOn or not item or not item.Parent then
		return
	end
	local rar = itemDbRarity(item.Name)
	if rar ~= 'Tribute' then
		return
	end
	local id = inventoryInstanceId(item)
	if not id then
		return
	end
	Hive._tributeKnown = Hive._tributeKnown or {}
	if Hive._tributeKnown[id] then
		return
	end
	Hive._tributeKnown[id] = true
	local upgrade = item:FindFirstChild('Upgrade')
	local upVal = upgrade and upgrade:IsA('ValueBase') and tonumber(upgrade.Value) or nil
	notify(('Tribute drop: %s'):format(tostring(item.Name)))
	postTributeWebhook({
		name = item.Name,
		upgrade = upVal,
		instanceId = id,
	})
end

local function startTributeWatch()
	stopTributeWatch()
	if not Hive._tributeWebhookOn then
		return
	end
	local url = normalizeDiscordWebhookUrl(Hive._tributeWebhookUrl)
	Hive._tributeWebhookUrl = url
	if not isDiscordWebhookUrl(url) then
		return
	end
	Hive._tributeKnown = snapshotTributeInventory()
	local inv = getInventory()
	if not inv then
		task.delay(2, function()
			if Hive._tributeWebhookOn then
				startTributeWatch()
			end
		end)
		return
	end
	local conn = inv.ChildAdded:Connect(function(child)
		task.defer(function()
			-- Wait a frame so Upgrade/Count replicate.
			task.wait(0.15)
			onTributeInventoryItem(child)
		end)
	end)
	Hive._tributeWatchConn = conn
	getgenv().SB2HiveTributeWatchConn = conn
end

function Hive.getTributeWebhook()
	local url, on, ping = readTributeWebhookConfig()
	Hive._tributeWebhookUrl = url
	Hive._tributeWebhookOn = on
	Hive._tributePing = type(ping) == 'string' and ping or ''
	return url, on, Hive._tributePing
end

function Hive.setTributeWebhook(url, enabled, ping, opts)
	opts = type(opts) == 'table' and opts or {}
	local quiet = opts.quiet == true
	url = normalizeDiscordWebhookUrl(url)
	Hive._tributeWebhookUrl = url
	if enabled ~= nil then
		Hive._tributeWebhookOn = enabled == true
	end
	-- Always accept ping (including empty = no ping). Never keep a previous account's ID.
	if type(ping) == 'string' then
		Hive._tributePing = ping:gsub('%D', '')
	end
	writeTributeWebhookConfig(Hive._tributeWebhookUrl, Hive._tributeWebhookOn, Hive._tributePing)
	if Hive._tributeWebhookOn and isDiscordWebhookUrl(Hive._tributeWebhookUrl) then
		startTributeWatch()
		if not quiet then
			notify('Tribute webhook armed')
		end
	else
		stopTributeWatch()
		if Hive._tributeWebhookOn and Hive._tributeWebhookUrl ~= '' and not isDiscordWebhookUrl(Hive._tributeWebhookUrl) then
			if not quiet then
				notify('Webhook URL looks invalid (need discord.com/api/webhooks/...)')
			end
			Hive._tributeWebhookOn = false
			writeTributeWebhookConfig(Hive._tributeWebhookUrl, false, Hive._tributePing)
		elseif not quiet then
			notify('Tribute webhook off')
		end
	end
end

function Hive.setTributeWebhookEnabled(on)
	Hive._tributeWebhookOn = on == true
	writeTributeWebhookConfig(Hive._tributeWebhookUrl, Hive._tributeWebhookOn, Hive._tributePing)
	if Hive._tributeWebhookOn and Hive._tributeWebhookUrl ~= '' then
		startTributeWatch()
	else
		stopTributeWatch()
	end
end

-- Sends a sample Discord post using the current (or override) URL/ping. Does not require the toggle.
function Hive.testTributeWebhook(urlOverride, pingOverride)
	local fromUi = normalizeDiscordWebhookUrl(urlOverride)
	if fromUi ~= '' then
		Hive._tributeWebhookUrl = fromUi
	else
		-- Fall back to saved config if UI Value was empty (pre-commit paste).
		local saved = select(1, readTributeWebhookConfig())
		saved = normalizeDiscordWebhookUrl(saved)
		if saved ~= '' then
			Hive._tributeWebhookUrl = saved
		end
	end
	if type(pingOverride) == 'string' then
		Hive._tributePing = pingOverride:gsub('%D', '')
	end
	local url = normalizeDiscordWebhookUrl(Hive._tributeWebhookUrl)
	Hive._tributeWebhookUrl = url
	if not isDiscordWebhookUrl(url) then
		local preview = url ~= '' and url:sub(1, 40) or '(empty)'
		notify('Need a Discord webhook URL (got: ' .. preview .. ')')
		return false
	end
	-- Persist what we're testing so reinject keeps it.
	writeTributeWebhookConfig(url, Hive._tributeWebhookOn == true, Hive._tributePing)
	local okStart, waiter = postTributeWebhook({
		name = 'Webhook test',
		upgrade = nil,
		instanceId = 'test',
	})
	if not okStart then
		notify('Webhook POST could not start')
		return false
	end
	if type(waiter) == 'function' then
		local okHttp, res = waiter(5)
		local code = 0
		if type(res) == 'table' then
			code = tonumber(res.StatusCode or res.Status or res.statusCode) or 0
		end
		if okHttp == false then
			notify('Webhook request failed (executor HTTP?)')
			return false
		end
		if code ~= 0 and (code < 200 or code >= 300) then
			notify(('Webhook HTTP %s — check URL / channel'):format(tostring(code)))
			return false
		end
	end
	notify('Test webhook sent')
	return true
end

-- Restore webhook watch across reloads (does not require Join hive).
task.defer(function()
	local url, on, ping = readTributeWebhookConfig()
	Hive._tributeWebhookUrl = url
	Hive._tributeWebhookOn = on
	Hive._tributePing = type(ping) == 'string' and ping or ''
	if on and url ~= '' then
		startTributeWatch()
	end
end)

return Hive
