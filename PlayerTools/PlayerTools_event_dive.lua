--[[
    SAVED SNAPSHOT 2026-08-17 — Event dive / under-mob farm
    (Neuublue-style fly, save/restore CFrame, farm skills, hit-lives rush, heals).
    Live PlayerTools.lua was reverted to the pre-event-dive Combat tab.
	Restore: copy this file over PlayerTools.lua in workspace, workspace/PlayerTools, and scripts/PlayerTools.
]]
if true then
	return -- snapshot only; live UI is PlayerTools.lua (this file was stacking extra Tool windows)
end
--[[
    PlayerTools.lua — Swordburst 2
    Spectate + view other players' inventories.
    Remote upgrade / remote dismantle (no NPC / no dismantle GUI).
    Items tab: snapshot Database.Items, wiki dumps (stats/buffs/icon/flags), aura chests.
    HiveMind — pick a commanding client; others TP / follow / stack via Hive tab.
    Combat tab: auto skill + auto attack (same stack as AutoFarm).
    Also launches Infinite Yield on start.

    Farm / vacuum / skills live in AutoFarm/AutoFarm.lua now
    (combat toggles are also on PlayerTools → Combat).

    Potassium: open the PlayerTools folder and run this file (or init.lua).
    With AutoFarm: from scripts/ root run combo.lua (loads both).
    Toggle UI: Home (AutoFarm uses End).

    Force re-run after a failed attempt:
        getgenv().SB2PlayerTools = false
        loadstring(readfile('PlayerTools.lua'))()
]]

-- Infinite Yield — load before PlayerTools UI (skip if already running).
pcall(function()
	if getgenv().IY_LOADED or getgenv().IYLoaded or getgenv().loadedIY or IY_LOADED then
		return
	end
	local src = game:HttpGet('https://raw.githubusercontent.com/EdgeIY/infiniteyield/master/source')
	assert(type(src) == 'string' and src ~= '', 'Infinite Yield HttpGet returned nil')
	assert(loadstring(src))()
end)

local function fileExists(path)
	if type(isfile) == 'function' then
		local ok, exists = pcall(isfile, path)
		if ok then
			return exists and true or false
		end
	end
	if type(readfile) ~= 'function' then
		return false
	end
	local ok, src = pcall(readfile, path)
	return ok and type(src) == 'string'
end

local scriptPath = fileExists('PlayerTools/PlayerTools.lua') and 'PlayerTools/PlayerTools.lua'
	or fileExists('PlayerTools.lua') and 'PlayerTools.lua'
	or 'PlayerTools/PlayerTools.lua'

local configFolder = fileExists('PlayerTools/autoexec') and 'PlayerTools'
	or fileExists('autoexec') and '.'
	or 'PlayerTools'

local CONFIG = {
	GenvKey = 'SB2PlayerTools',
	Title = 'Tool',
	Footer = 'Viewer',
	WindowSize = UDim2.fromOffset(300, 260),
	WindowMinSize = Vector2.new(240, 180), -- Obsidian defaults to 480×360 min otherwise
	WindowPaddingX = 12,
	WindowPaddingY = 60,
	ScriptPath = scriptPath,
	ConfigFolder = configFolder,
	Icon = 90459974458598,
	UIRepo = 'https://raw.githubusercontent.com/deividcomsono/Obsidian/main/',
}

local joinPath = function(folder, name)
	if not folder or folder == '' or folder == '.' then
		return name
	end
	return folder .. '/' .. name
end

local AUTOEXEC_PATH = joinPath(CONFIG.ConfigFolder, 'autoexec')
local ANTIAFK_PATH = joinPath(CONFIG.ConfigFolder, 'antiafk')
local ANTIAFK_LOG_PATH = joinPath(CONFIG.ConfigFolder, 'antiafk_log.txt')
local AUTOBLOCK_PATH = joinPath(CONFIG.ConfigFolder, 'autoblock')
local AUTOBLOCK_HOP_PATH = joinPath(CONFIG.ConfigFolder, 'autoblock_hop.json')
local SOLO_RESUME_PATH = joinPath(CONFIG.ConfigFolder, 'solo_resume')
local COMBAT_SKILLS_PATH = joinPath(CONFIG.ConfigFolder, 'combat_skills.json')
local MANUAL_UNLOAD_PATH = joinPath(CONFIG.ConfigFolder, 'manual_unload')
local ITEMS_KNOWN_PATH = joinPath(CONFIG.ConfigFolder, 'items_known.json')
local WIKI_DUMP_PATH = joinPath(CONFIG.ConfigFolder, 'wiki_dump.txt')
local LIBRARY_KEY = 'SB2PlayerToolsLibrary'
local SCRIPT_PATHS = {
	'PlayerTools/PlayerTools.lua',
	'PlayerTools.lua',
	CONFIG.ScriptPath,
}
local AUTOEXEC_PATHS = {
	'PlayerTools/autoexec',
	'autoexec',
	AUTOEXEC_PATH,
}

-- Solo resume / auto-block treat these as you (combat stays on, no block hop).
local OWN_ALT_NAMES = {
	nickb928 = true,
	nickb925 = true,
	nickb926 = true,
	nickb910 = true,
	nickb929 = true,
	dyildolover = true,
	['62qx'] = true,
}
local function isOwnAlt(plr)
	if not plr then
		return false
	end
	local name = string.lower(tostring(plr.Name or ''))
	local display = string.lower(tostring(plr.DisplayName or ''))
	return OWN_ALT_NAMES[name] == true or OWN_ALT_NAMES[display] == true
end
getgenv().SB2IsOwnAlt = isOwnAlt

local notify = function(title, text)
	pcall(function()
		game:GetService('StarterGui'):SetCore('SendNotification', {
			Title = title,
			Text = text,
			Duration = 8,
		})
	end)
	warn(('[PlayerTools] %s: %s'):format(title, text))
end

local unloadExisting = function()
	pcall(function()
		-- Only unload OUR Obsidian instance — never fall back to getgenv().Library
		-- (that may be AutoFarm's window when both run together).
		local library = getgenv()[LIBRARY_KEY]
		if library then
			if library.ScreenGui then
				pcall(function()
					library.ScreenGui:Destroy()
				end)
			end
			-- Don't call Unload if somehow sharing a table with AutoFarm.
			if library.Unload and getgenv().SB2AutoFarmLibrary ~= library then
				library:Unload()
			end
		end
	end)

	local function destroyObsidianUnder(parent)
		if not parent then
			return
		end
		for _, gui in ipairs(parent:GetChildren()) do
			if gui:IsA('ScreenGui') and gui:GetAttribute('SB2PlayerTools') == true then
				pcall(function()
					gui:Destroy()
				end)
			end
		end
	end

	pcall(function()
		local lp = game:GetService('Players').LocalPlayer
		if lp then
			destroyObsidianUnder(lp:FindFirstChild('PlayerGui'))
		end
	end)
	pcall(function()
		destroyObsidianUnder(game:GetService('CoreGui'))
	end)
	pcall(function()
		if type(gethui) == 'function' then
			destroyObsidianUnder(gethui())
		end
	end)

	if getgenv().SB2PlayerToolsGui then
		pcall(function()
			getgenv().SB2PlayerToolsGui:Destroy()
		end)
		getgenv().SB2PlayerToolsGui = nil
	end

	pcall(function()
		if type(getgenv().SB2SetAnchorPlayerNoclip) == 'function' then
			getgenv().SB2SetAnchorPlayerNoclip(false)
		end
	end)

	getgenv()[LIBRARY_KEY] = nil
end

-- Re-execute from Potassium must always proceed; a stuck prior load used to
-- leave this true and make later injects silently no-op.
getgenv().SB2PlayerToolsLoading = true

-- Intentional launch (Potassium execute) clears a prior Unload Script block.
do
	getgenv().SB2PlayerToolsManualUnload = nil
	if type(writefile) == 'function' then
		if type(makefolder) == 'function' and type(isfolder) == 'function' then
			if CONFIG.ConfigFolder ~= '' and CONFIG.ConfigFolder ~= '.' and not isfolder(CONFIG.ConfigFolder) then
				pcall(makefolder, CONFIG.ConfigFolder)
			end
		end
		pcall(writefile, MANUAL_UNLOAD_PATH, 'false')
		pcall(writefile, 'PlayerTools/manual_unload', 'false')
	end
end

if getgenv()[CONFIG.GenvKey] then
	pcall(unloadExisting)
	getgenv()[CONFIG.GenvKey] = false
	getgenv()[LIBRARY_KEY] = nil
	getgenv().SB2PlayerToolsArmedNotify = nil
	getgenv().SB2PlayerToolsLoadedNotify = nil
end

getgenv()[CONFIG.GenvKey] = true
unloadExisting()

local ok, err = pcall(function()
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end

	if game.GameId ~= 212154879 then
		getgenv()[CONFIG.GenvKey] = false
		notify('Player Tools', 'Wrong game — need Swordburst 2')
		return
	end

	local WORKSPACE_SCRIPT = 'PlayerTools/PlayerTools.lua'
	local function cacheAndMirrorSource()
		local src
		if type(readfile) == 'function' then
			for _, path in ipairs(SCRIPT_PATHS) do
				local okRead, body = pcall(readfile, path)
				if okRead and type(body) == 'string' and body ~= '' and body:find('SB2PlayerTools', 1, true) then
					src = body
					break
				end
			end
		end
		if not src then
			src = getgenv().SB2PlayerToolsCode
		end
		if type(src) == 'string' and src ~= '' then
			getgenv().SB2PlayerToolsCode = src
			if type(writefile) == 'function' then
				if type(makefolder) == 'function' and type(isfolder) == 'function' then
					if not isfolder('PlayerTools') then
						pcall(makefolder, 'PlayerTools')
					end
				end
				pcall(writefile, WORKSPACE_SCRIPT, src)
				pcall(writefile, 'PlayerTools.lua', src)
			end
		end
		return src
	end
	cacheAndMirrorSource()

	local Players = game:GetService('Players')
	local LocalPlayer = Players.LocalPlayer
	if not LocalPlayer then
		Players:GetPropertyChangedSignal('LocalPlayer'):Wait()
		LocalPlayer = Players.LocalPlayer
	end

	local queueTeleport = (type(queueteleport) == 'function' and queueteleport)
		or (type(queue_on_teleport) == 'function' and queue_on_teleport)
		or (type(queueonteleport) == 'function' and queueonteleport)
		or (getgenv() and type(getgenv().queueteleport) == 'function' and getgenv().queueteleport)

	local TELEPORT_STUB =
		"if isfile and isfile('PlayerTools/manual_unload') then local ok,b=pcall(readfile,'PlayerTools/manual_unload'); if ok and tostring(b)=='true' then return end end;"
		.. "if getgenv().SB2PlayerToolsManualUnload then return end;"
		.. "getgenv().SB2PlayerTools=false;"
		.. "getgenv().SB2PlayerToolsLibrary=nil;"
		.. "local ok,err=pcall(function()"
		.. "local p=(isfile and isfile('PlayerTools/PlayerTools.lua') and 'PlayerTools/PlayerTools.lua')"
		.. "or(isfile and isfile('PlayerTools.lua') and 'PlayerTools.lua');"
		.. "assert(p,'PlayerTools.lua missing from workspace');"
		.. "assert(loadstring(readfile(p)))()"
		.. "end);if not ok then warn('[PlayerTools] rejoin failed: '..tostring(err)) end"

	local function isUnloadBlocked()
		if getgenv().SB2PlayerToolsManualUnload then
			return true
		end
		if type(isfile) == 'function' and type(readfile) == 'function' then
			local ok, exists = pcall(isfile, 'PlayerTools/manual_unload')
			if ok and exists then
				local okRead, body = pcall(readfile, 'PlayerTools/manual_unload')
				if okRead and tostring(body) == 'true' then
					return true
				end
			end
		end
		return false
	end

	local function armKeepPlayerTools(...)
		local first = ...
		if typeof(first) == 'Instance' and first:IsA('Player') and first ~= LocalPlayer then
			return
		end
		if not queueTeleport then
			return
		end
		if isUnloadBlocked() then
			return
		end

		local now = os.clock()
		if getgenv().SB2PlayerToolsArmAt and (now - getgenv().SB2PlayerToolsArmAt) < 0.75 then
			return
		end
		getgenv().SB2PlayerToolsArmAt = now

		local autoOff = false
		for _, path in ipairs(AUTOEXEC_PATHS) do
			local okExists, exists = pcall(function()
				return isfile and isfile(path)
			end)
			if okExists and exists then
				local okRead, body = pcall(readfile, path)
				if okRead and tostring(body) == 'false' then
					autoOff = true
				end
				break
			end
		end
		if autoOff then
			return
		end

		pcall(cacheAndMirrorSource)
		local okArm, armErr = pcall(queueTeleport, TELEPORT_STUB)
		if not okArm then
			warn('[PlayerTools] queueteleport failed: ' .. tostring(armErr))
		end
	end

	local function disconnectArmConns()
		local conns = getgenv().SB2PlayerToolsArmConns
		if type(conns) == 'table' then
			for _, c in ipairs(conns) do
				pcall(function()
					c:Disconnect()
				end)
			end
		end
		getgenv().SB2PlayerToolsArmConns = nil
		getgenv().SB2PlayerToolsArmTeleport = nil
	end

	if queueTeleport then
		armKeepPlayerTools()
		local conns = {}
		pcall(function()
			conns[#conns + 1] = LocalPlayer.OnTeleport:Connect(armKeepPlayerTools)
		end)
		pcall(function()
			conns[#conns + 1] = LocalPlayer.OnTeleportInternal:Connect(armKeepPlayerTools)
		end)
		getgenv().SB2PlayerToolsArmConns = conns
		getgenv().SB2PlayerToolsArmTeleport = armKeepPlayerTools
		if not getgenv().SB2PlayerToolsArmedNotify then
			getgenv().SB2PlayerToolsArmedNotify = true
			notify('Player Tools', 'Rejoin autoexec armed')
		end
	else
		warn('[PlayerTools] queueteleport missing — will not reload after rejoin')
	end

	local function antiafkFileOn()
		if type(isfile) == 'function' and type(readfile) == 'function' then
			local ok, exists = pcall(isfile, ANTIAFK_PATH)
			if ok and exists then
				local okRead, body = pcall(readfile, ANTIAFK_PATH)
				if okRead and tostring(body) == 'false' then
					return false
				end
			end
		end
		return true
	end

	local function writeAntiafkFile(on)
		if type(writefile) ~= 'function' then
			return
		end
		pcall(function()
			if type(makefolder) == 'function' and type(isfolder) == 'function' then
				local folder = CONFIG.ConfigFolder
				if folder ~= '' and folder ~= '.' and not isfolder(folder) then
					makefolder(folder)
				end
			end
		end)
		pcall(writefile, ANTIAFK_PATH, on and 'true' or 'false')
	end

	local function logAntiafk(msg)
		if type(appendfile) ~= 'function' and type(writefile) ~= 'function' then
			return
		end
		local line = ('[%s] place=%s %s\n'):format(os.date('%Y-%m-%d %H:%M:%S'), tostring(game.PlaceId), tostring(msg))
		if type(appendfile) == 'function' then
			pcall(appendfile, ANTIAFK_LOG_PATH, line)
			return
		end
		local prev = ''
		if type(readfile) == 'function' and type(isfile) == 'function' then
			local ok, exists = pcall(isfile, ANTIAFK_LOG_PATH)
			if ok and exists then
				local rok, body = pcall(readfile, ANTIAFK_LOG_PATH)
				if rok and type(body) == 'string' then
					prev = body
				end
			end
		end
		pcall(writefile, ANTIAFK_LOG_PATH, prev .. line)
	end

	-- Same as Infinite Yield `antiafk`: mute Roblox's Idled kick. No jump / key / camera.
	local function muteIdledKick()
		if type(getconnections) ~= 'function' then
			return
		end
		pcall(function()
			for _, conn in ipairs(getconnections(LocalPlayer.Idled)) do
				pcall(function()
					if conn.Disable then
						conn:Disable()
					end
				end)
				pcall(function()
					if conn.Disconnect then
						conn:Disconnect()
					end
				end)
			end
		end)
	end

	local function onRobloxIdled()
		if getgenv().SB2AntiAfkOn ~= true then
			return
		end
		pcall(function()
			local vu = game:GetService('VirtualUser')
			vu:CaptureController()
			vu:ClickButton2(Vector2.zero)
		end)
		getgenv().SB2AntiAfkLastPulse = os.time()
		getgenv().SB2AntiAfkLastReason = 'idled'
		logAntiafk('idled')
		if type(getgenv().SB2AntiAfkPaint) == 'function' then
			pcall(getgenv().SB2AntiAfkPaint)
		end
	end

	local function stopAntiAfk()
		getgenv().SB2AntiAfkOn = false
		local prev = getgenv().SB2AntiAfkConn
		if prev then
			pcall(function()
				prev:Disconnect()
			end)
		end
		getgenv().SB2AntiAfkConn = nil
		if getgenv().SB2AntiAfkPulseToken then
			getgenv().SB2AntiAfkPulseToken += 1
		end
	end

	local function startAntiAfk()
		stopAntiAfk()
		getgenv().SB2AntiAfkOn = true
		getgenv().SB2AntiAfkStartedAt = os.time()
		muteIdledKick()
		getgenv().SB2AntiAfkConn = LocalPlayer.Idled:Connect(onRobloxIdled)
		logAntiafk('armed')
		if type(getgenv().SB2AntiAfkPaint) == 'function' then
			pcall(getgenv().SB2AntiAfkPaint)
		end
	end

	getgenv().SB2AntiAfkStart = startAntiAfk
	getgenv().SB2AntiAfkStop = stopAntiAfk

	if antiafkFileOn() then
		startAntiAfk()
	end

	getgenv().SB2PlayerToolsMarkUnloaded = function()
		getgenv().SB2PlayerToolsManualUnload = true
		disconnectArmConns()
		if type(writefile) == 'function' then
			pcall(writefile, MANUAL_UNLOAD_PATH, 'true')
			pcall(writefile, 'PlayerTools/manual_unload', 'true')
		end
		-- Overwrite teleport queue so a prior stub cannot revive this script.
		if queueTeleport then
			pcall(queueTeleport, "if true then return end")
		end
	end

	if game.PlaceId == 659222129 then
		game:GetService('ReplicatedStorage'):WaitForChild('Function'):InvokeServer('Login')
		getgenv()[CONFIG.GenvKey] = false
		notify('Player Tools', 'On main menu — join a floor first')
		return
	end

	-- Auto-block F1 stop: hop to F11 as soon as this script is running.
	-- Do not wait for character, map, or the rest of the UI.
	-- If auto-block was turned off, drop a leftover hop so a normal session is not hijacked.
	do
		local F1_PLACE = 542351431
		local F11_PLACE = 5287433115
		local hop
		local abOn = false
		if type(readfile) == 'function' and type(isfile) == 'function' then
			local okAb, existsAb = pcall(isfile, AUTOBLOCK_PATH)
			if okAb and existsAb then
				local okReadAb, bodyAb = pcall(readfile, AUTOBLOCK_PATH)
				if okReadAb then
					abOn = tostring(bodyAb) == 'true'
				end
			end
			local okExists, exists = pcall(isfile, AUTOBLOCK_HOP_PATH)
			if okExists and exists then
				local okRead, body = pcall(readfile, AUTOBLOCK_HOP_PATH)
				if okRead and type(body) == 'string' and body ~= '' then
					local okJson, data = pcall(function()
						return game:GetService('HttpService'):JSONDecode(body)
					end)
					if okJson and type(data) == 'table' then
						hop = data
					end
				end
			end
		end
		if type(hop) ~= 'table' then
			hop = getgenv().SB2AutoBlockHop
		end
		local hopping = type(hop) == 'table'
			and hop.active == true
			and (hop.phase == 'f1' or hop.phase == 'f11')
		if hopping and (not abOn or (game.PlaceId ~= F1_PLACE and game.PlaceId ~= F11_PLACE)) then
			-- Leftover hop must not yank you off F2–F10/F12 back to F11.
			getgenv().SB2AutoBlockHopping = nil
			getgenv().SB2AutoBlockHop = { active = false, phase = 'off', t = os.time() }
			pcall(function()
				if type(writefile) == 'function' then
					writefile(AUTOBLOCK_HOP_PATH, game:GetService('HttpService'):JSONEncode({
						active = false,
						phase = 'off',
						t = os.time(),
					}))
				end
			end)
		elseif hopping and abOn and game.PlaceId == F1_PLACE then
			local payload = {
				active = true,
				phase = 'f11',
				auto = true,
				t = os.time(),
			}
			getgenv().SB2AutoBlockHop = payload
			getgenv().SB2AutoBlockHopping = true
			getgenv().SB2AutoBlockWanted = true
			pcall(function()
				if type(makefolder) == 'function' and type(isfolder) == 'function' and not isfolder('PlayerTools') then
					makefolder('PlayerTools')
				end
			end)
			pcall(function()
				if type(writefile) == 'function' then
					writefile(AUTOBLOCK_HOP_PATH, game:GetService('HttpService'):JSONEncode(payload))
					writefile(AUTOBLOCK_PATH, 'true')
				end
			end)
			if type(getgenv().SB2PlayerToolsArmTeleport) == 'function' then
				pcall(getgenv().SB2PlayerToolsArmTeleport)
			end
			notify('Player Tools', 'Auto block — scripts loaded, joining F11…')
			pcall(function()
				game:GetService('TeleportService'):Teleport(F11_PLACE, LocalPlayer)
			end)
			return
		end
	end

	-- Session loader (PlayerGui.Gui) can hang. Do not hide/force HUD (that was a
	-- fake session). Rejoin this client until the overlay actually goes away.
	local LoadSkip = (function()
		local PATH = joinPath(CONFIG.ConfigFolder, 'autoskip_load')
		local STUCK_SECS = 15

		local function fileOn()
			if type(isfile) == 'function' and type(readfile) == 'function' then
				local ok, exists = pcall(isfile, PATH)
				if ok and exists then
					local okRead, body = pcall(readfile, PATH)
					if okRead and tostring(body) == 'false' then
						return false
					end
				end
			end
			return true
		end

		local function writeFile(on)
			if type(writefile) ~= 'function' then
				return
			end
			pcall(function()
				if type(makefolder) == 'function' and type(isfolder) == 'function' then
					local folder = CONFIG.ConfigFolder
					if folder ~= '' and folder ~= '.' and not isfolder(folder) then
						makefolder(folder)
					end
				end
			end)
			pcall(writefile, PATH, on and 'true' or 'false')
		end

		local function skipGuiName(name)
			local n = string.lower(tostring(name or ''))
			return string.find(n, 'playertools', 1, true)
				or string.find(n, 'obsidian', 1, true)
				or string.find(n, 'linoria', 1, true)
		end

		local LOAD_PHRASES = {
			'session is loading',
			'your session is',
			'loading session',
			'joining server',
			'joining game',
			'joining the',
			'joining floor',
			'please wait',
			'teleporting',
			'connecting',
			'waiting for server',
			'waiting for players',
			'getting your',
			'preparing',
			'loading map',
			'loading world',
			'loading...',
		}

		local function textLooksLoading(raw)
			local t = string.lower((tostring(raw or ''):gsub('%s+', ' ')))
			if t == '' or #t > 140 then
				return false
			end
			for i = 1, #LOAD_PHRASES do
				if string.find(t, LOAD_PHRASES[i], 1, true) then
					return true
				end
			end
			return false
		end

		local function isShown(inst)
			local cur = inst
			for _ = 1, 14 do
				if not cur or cur == game then
					return false
				end
				local vis = true
				pcall(function()
					if cur:IsA('LayerCollector') then
						vis = cur.Enabled ~= false
					elseif cur:IsA('GuiObject') then
						vis = cur.Visible ~= false
					end
				end)
				if not vis then
					return false
				end
				if cur:IsA('PlayerGui') or cur:IsA('CoreGui') then
					return true
				end
				cur = cur.Parent
			end
			return false
		end

		local function nameLooksLoader(name)
			local n = string.lower(tostring(name or ''))
			return string.find(n, 'loadingcircle', 1, true)
				or string.find(n, 'loadingspinner', 1, true)
				or string.find(n, 'loadcircle', 1, true)
				or n == 'spinner'
				or n == 'throbber'
				or n == 'loadingring'
		end

		local function instLooksLoader(inst)
			if not inst or skipGuiName(inst.Name) then
				return false
			end
			if nameLooksLoader(inst.Name) and isShown(inst) then
				return true
			end
			if (inst:IsA('TextLabel') or inst:IsA('TextButton') or inst:IsA('TextBox')) and isShown(inst) then
				local raw = inst.Text
				pcall(function()
					if inst.ContentText and inst.ContentText ~= '' then
						raw = inst.ContentText
					end
				end)
				if textLooksLoading(raw) then
					return true
				end
			end
			return false
		end

		local function treeLooksLoading(root, budget)
			if not root then
				return false
			end
			if instLooksLoader(root) then
				return true
			end
			local left = budget or 600
			local ok, desc = pcall(function()
				return root:GetDescendants()
			end)
			if not ok or type(desc) ~= 'table' then
				return false
			end
			for i = 1, #desc do
				if i > left then
					break
				end
				if instLooksLoader(desc[i]) then
					return true
				end
			end
			return false
		end

		local function overlayUp()
			local loaded = true
			pcall(function()
				loaded = game:IsLoaded()
			end)
			if not loaded then
				return true
			end
			local pg = LocalPlayer:FindFirstChild('PlayerGui')
			if not pg then
				return true
			end
			local gui = pg:FindFirstChild('Gui')
			local cui = pg:FindFirstChild('CardinalUI')
			local hudOn = cui and cui:IsA('LayerCollector') and cui.Enabled == true

			-- SB2 session spinner (PlayerGui.Gui). HUD never parenting is the hang.
			if gui and gui:IsA('LayerCollector') then
				if treeLooksLoading(gui) then
					return true
				end
				if gui.Enabled and not hudOn then
					return true
				end
			end

			for _, g in ipairs(pg:GetChildren()) do
				if g ~= gui and g ~= cui and g:IsA('LayerCollector') and g.Enabled and not skipGuiName(g.Name) then
					local n = string.lower(g.Name)
					if string.find(n, 'load', 1, true)
						or string.find(n, 'join', 1, true)
						or string.find(n, 'teleport', 1, true)
						or string.find(n, 'fade', 1, true)
						or string.find(n, 'splash', 1, true)
					then
						return true
					end
					if treeLooksLoading(g, 250) then
						return true
					end
				end
			end

			local coreHit = false
			pcall(function()
				local cg = game:GetService('CoreGui')
				for _, g in ipairs(cg:GetChildren()) do
					if g:IsA('LayerCollector') and g.Enabled and not skipGuiName(g.Name) then
						local n = string.lower(g.Name)
						if string.find(n, 'load', 1, true)
							or string.find(n, 'teleport', 1, true)
						then
							coreHit = true
							return
						end
					end
				end
			end)
			return coreHit
		end

		local function rejoin(reason)
			if getgenv().SB2LoadRejoining then
				return false
			end
			getgenv().SB2LoadRejoining = true
			if type(getgenv().SB2CloseAllPillPanels) == 'function' then
				pcall(getgenv().SB2CloseAllPillPanels)
			end
			notify(
				'Player Tools',
				('Stuck loading >%ds — rejoining'):format(STUCK_SECS)
			)
			warn(('[PlayerTools] stuck-load rejoin (%s)'):format(tostring(reason or '?')))
			local placeId = game.PlaceId
			local jobId = tostring(game.JobId or '')
			local ts = game:GetService('TeleportService')
			-- TeleportToPlaceInstance(current job) is a no-op once Roblox already
			-- counts this client as in the server — one window hops, the other sits.
			-- Leave this place, then come back to the same job.
			local hopPlace = 659222129
			if placeId == hopPlace then
				hopPlace = 1818
			end
			local returnScript = string.format(
				'task.defer(function()\n'
					.. 'local ts=game:GetService("TeleportService")\n'
					.. 'local lp=game:GetService("Players").LocalPlayer\n'
					.. 'local q=(type(queueteleport)=="function" and queueteleport) or (type(queue_on_teleport)=="function" and queue_on_teleport) or (type(queueonteleport)=="function" and queueonteleport)\n'
					.. 'if q then pcall(q,%s) end\n'
					.. 'pcall(function() ts:TeleportToPlaceInstance(%d,%s,lp) end)\n'
					.. 'end)\n',
				string.format('%q', TELEPORT_STUB),
				placeId,
				string.format('%q', jobId)
			)
			task.spawn(function()
				task.wait(((tonumber(LocalPlayer.UserId) or 0) % 9) * 0.45)
				if queueTeleport then
					pcall(queueTeleport, returnScript)
				end
				local ok = pcall(function()
					ts:Teleport(hopPlace, LocalPlayer)
				end)
				if not ok then
					ok = pcall(function()
						if jobId ~= '' then
							ts:TeleportToPlaceInstance(placeId, jobId, LocalPlayer)
						else
							ts:Teleport(placeId, LocalPlayer)
						end
					end)
				end
				if not ok then
					getgenv().SB2LoadRejoining = false
				end
			end)
			task.delay(15, function()
				getgenv().SB2LoadRejoining = false
			end)
			return true
		end

		getgenv().SB2AutoSkipLoad = fileOn()
		getgenv().SB2LoadRejoining = false

		task.spawn(function()
			local overlaySince = nil
			local clearSince = nil
			while getgenv()[CONFIG.GenvKey] do
				if getgenv().SB2AutoSkipLoad == false or getgenv().SB2LoadRejoining then
					overlaySince = nil
					clearSince = nil
					task.wait(1)
				elseif overlayUp() then
					clearSince = nil
					if not overlaySince then
						overlaySince = os.clock()
					elseif (os.clock() - overlaySince) >= STUCK_SECS then
						rejoin('auto')
						overlaySince = nil
					end
					task.wait(0.35)
				else
					-- One missed check used to reset the timer; require a real clear.
					if overlaySince then
						if not clearSince then
							clearSince = os.clock()
						elseif (os.clock() - clearSince) >= 2.5 then
							overlaySince = nil
							clearSince = nil
						end
					end
					task.wait(0.5)
				end
			end
		end)

		return {
			rejoin = rejoin,
			overlayUp = overlayUp,
			fileOn = fileOn,
			writeFile = writeFile,
		}
	end)()
	getgenv().SB2ForceFinishLoad = LoadSkip.rejoin

	local Character = LocalPlayer.Character
	if not Character then
		local deadline = os.clock() + 12
		while not Character and os.clock() < deadline do
			Character = LocalPlayer.Character
			if Character then
				break
			end
			task.wait(0.15)
		end
		Character = Character or LocalPlayer.Character
	end
	local Camera = workspace.CurrentCamera
	if not Camera then
		local deadline = os.clock() + 8
		while not workspace.CurrentCamera and os.clock() < deadline do
			task.wait(0.1)
		end
		Camera = workspace.CurrentCamera
	end

	-- Kill client streaming so the map stops unreplicating (void Workspace).
	-- Needs executor setscriptable / sethiddenproperty; re-applies if it flips back on.
	local function disableWorkspaceStreaming()
		pcall(function()
			if type(setscriptable) == 'function' then
				pcall(setscriptable, workspace, 'StreamingEnabled', true)
				pcall(setscriptable, workspace, 'StreamingMinRadius', true)
				pcall(setscriptable, workspace, 'StreamingTargetRadius', true)
				pcall(setscriptable, workspace, 'StreamOutBehavior', true)
			end
		end)
		pcall(function()
			workspace.StreamingEnabled = false
		end)
		pcall(function()
			if type(sethiddenproperty) == 'function' then
				sethiddenproperty(workspace, 'StreamingEnabled', false)
				sethiddenproperty(workspace, 'StreamingMinRadius', 8192)
				sethiddenproperty(workspace, 'StreamingTargetRadius', 16384)
			end
		end)
		pcall(function()
			workspace.StreamingMinRadius = 8192
			workspace.StreamingTargetRadius = 16384
		end)
		return workspace.StreamingEnabled == false
	end
	disableWorkspaceStreaming()
	task.spawn(function()
		local RunService = game:GetService('RunService')
		if getgenv().SB2NoStreamConn then
			pcall(function()
				getgenv().SB2NoStreamConn:Disconnect()
			end)
			getgenv().SB2NoStreamConn = nil
		end
		local accum = 0
		getgenv().SB2NoStreamConn = RunService.Heartbeat:Connect(function(dt)
			if not getgenv()[CONFIG.GenvKey] then
				return
			end
			accum += dt
			if accum < 5 then
				return
			end
			accum = 0
			if workspace.StreamingEnabled then
				disableWorkspaceStreaming()
			end
		end)
	end)

	local function getLiveCamera()
		local cam = workspace.CurrentCamera
		if cam then
			Camera = cam
		end
		return Camera
	end

	-- Must be Humanoid (not the Model) or SB2 camera goes void / underwater.
	local cachedMyChar, cachedMyCharAt = nil, 0
	local function getMyCharacterModel()
		local now = os.clock()
		if cachedMyChar and cachedMyChar.Parent and (now - cachedMyCharAt) < 0.12 then
			return cachedMyChar
		end
		local chars = workspace:FindFirstChild('Characters')
		local model = chars and chars:FindFirstChild(LocalPlayer.Name)
		if model and model.Parent then
			cachedMyChar, cachedMyCharAt = model, now
			return model
		end
		local lpChar = LocalPlayer.Character
		if lpChar and lpChar.Parent then
			cachedMyChar, cachedMyCharAt = lpChar, now
			return lpChar
		end
		if Character and Character.Parent then
			cachedMyChar, cachedMyCharAt = Character, now
			return Character
		end
		cachedMyChar, cachedMyCharAt = nil, now
		return nil
	end

	local PhysicsService = game:GetService('PhysicsService')
	local ANCHOR_NOCLIP_ATTR = 'SB2AnchorCol'
	local function setAnchorPlayerNoclip(enabled)
		-- Player↔player only. World / mob collision stays. Restore on disable / unload.
		pcall(function()
			PhysicsService:CollisionGroupSetCollidable('Players', 'Players', not enabled)
		end)
		pcall(function()
			PhysicsService:CollisionGroupSetCollidable('MobsNoCollision', 'Players', not enabled)
		end)
		local charsFolder = workspace:FindFirstChild('Characters')
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr ~= LocalPlayer then
				local model = plr.Character
				if not (model and model.Parent) then
					model = charsFolder and charsFolder:FindFirstChild(plr.Name)
				end
				if model then
					for _, part in ipairs(model:GetDescendants()) do
						if part:IsA('BasePart') then
							if enabled then
								if part:GetAttribute(ANCHOR_NOCLIP_ATTR) == nil then
									part:SetAttribute(ANCHOR_NOCLIP_ATTR, part.CanCollide)
								end
								part.CanCollide = false
							else
								local was = part:GetAttribute(ANCHOR_NOCLIP_ATTR)
								if was ~= nil then
									part.CanCollide = was == true
									part:SetAttribute(ANCHOR_NOCLIP_ATTR, nil)
								end
							end
						end
					end
				end
			end
		end
	end
	getgenv().SB2SetAnchorPlayerNoclip = setAnchorPlayerNoclip

	local function cameraSubjectFrom(model)
		if not model or not model.Parent then
			return nil
		end
		local hum = model:FindFirstChildOfClass('Humanoid')
		if hum then
			return hum
		end
		return model:FindFirstChild('HumanoidRootPart') or model:FindFirstChild('Head')
	end

	local function lockReplicationFocus(char)
		local model = char or getMyCharacterModel() or LocalPlayer.Character
		if not model or not model.Parent then
			return
		end
		local hrp = model:FindFirstChild('HumanoidRootPart')
		local focus = hrp or model
		-- StreamingEnabled: wrong/nil ReplicationFocus unloads the map while mobs linger.
		pcall(function()
			if LocalPlayer.ReplicationFocus ~= focus then
				LocalPlayer.ReplicationFocus = focus
			end
		end)
	end

	-- Anchoring HRP before the server has our CFrame freezes us at spawn:
	-- mobs never stream, other clients never see us. Hold unanchored after spawn/TP.
	local function combatAnchorHolding()
		return os.clock() < (tonumber(getgenv().SB2AnchorHoldUntil) or 0)
	end
	local function holdCombatAnchor(seconds)
		seconds = tonumber(seconds) or 3.5
		if seconds < 0 then
			seconds = 0
		end
		local untilT = os.clock() + seconds
		local prev = tonumber(getgenv().SB2AnchorHoldUntil) or 0
		if untilT > prev then
			getgenv().SB2AnchorHoldUntil = untilT
		end
		local model = getMyCharacterModel() or LocalPlayer.Character
		if not model then
			return
		end
		pcall(function()
			for _, name in ipairs({ 'HumanoidRootPart', 'UpperTorso', 'LowerTorso', 'Torso' }) do
				local part = model:FindFirstChild(name)
				if part and part:IsA('BasePart') then
					part.Anchored = false
					part.AssemblyLinearVelocity = Vector3.zero
					part.AssemblyAngularVelocity = Vector3.zero
				end
			end
			local hum = model:FindFirstChildOfClass('Humanoid')
			if hum then
				hum.Sit = false
				hum.PlatformStand = false
			end
		end)
		lockReplicationFocus(model)
		local hrp = model:FindFirstChild('HumanoidRootPart') or model:FindFirstChild('UpperTorso')
		if hrp then
			pcall(function()
				LocalPlayer:RequestStreamAroundAsync(hrp.Position, 40)
			end)
		end
	end
	getgenv().SB2HoldCombatAnchor = holdCombatAnchor
	getgenv().SB2CombatAnchorHolding = combatAnchorHolding
	task.defer(function()
		if LocalPlayer.Character then
			holdCombatAnchor(4)
		end
	end)

	local lastStreamRequestAt = 0
	local lastMapGoneNotifyAt = 0
	local mapGoneSince = nil
	local mapGoneReloadTried = false
	local ESSENTIAL_WORKSPACE = {
		Camera = true,
		Terrain = true,
		Characters = true,
		['Baseplate'] = true,
		['AntiFall-Maze'] = true,
	}
	-- Game death FX — not map. Ignore in delete logs / hollow checks.
	local IGNORE_WORKSPACE_NAMES = {
		ResetEffect = true,
		HighlightModel = true,
		Camera = true,
		Terrain = true,
		Characters = true,
		['AntiFall-Maze'] = true,
	}

	local function countPartsNear(pos, radius)
		if not pos then
			return -1
		end
		local n = 0
		local ok, parts = pcall(function()
			return workspace:GetPartBoundsInRadius(pos, radius)
		end)
		if not ok or type(parts) ~= 'table' then
			return -1
		end
		for _ = 1, #parts do
			n += 1
		end
		return n
	end

	-- Explorer shows only Camera + Terrain + Characters = entire map streamed out.
	local function mapLooksGone()
		local extra = 0
		for _, child in ipairs(workspace:GetChildren()) do
			if not ESSENTIAL_WORKSPACE[child.Name] and not IGNORE_WORKSPACE_NAMES[child.Name] then
				extra += 1
				if extra >= 2 then
					return false
				end
			end
		end
		return true
	end

	-- Log Workspace root removals so we can tell Destroy vs stream-out next time.
	task.spawn(function()
		if getgenv().SB2WsDeleteLogConn then
			pcall(function()
				getgenv().SB2WsDeleteLogConn:Disconnect()
			end)
		end
		local path = 'PlayerTools/_ws_delete_log.txt'
		local function append(line)
			pcall(function()
				local prev = ''
				pcall(function()
					prev = readfile(path)
				end)
				if #prev > 12000 then
					prev = prev:sub(-8000)
				end
				writefile(path, prev .. '\n' .. line)
			end)
		end
		local removeStormTimes = {}
		local lastStormRecoverAt = 0
		local lastDeleteLogAt = 0
		getgenv().SB2WsDeleteLogConn = workspace.ChildRemoved:Connect(function(child)
			local name = child and child.Name or '?'
			if IGNORE_WORKSPACE_NAMES[name] then
				return
			end
			-- Throttle disk writes — stream storms used to hitch from writefile spam.
			local nowLog = os.clock()
			if (nowLog - lastDeleteLogAt) >= 0.35 then
				lastDeleteLogAt = nowLog
				local line = string.format(
					'[%s] REMOVED %s %s (stream=%s)',
					os.date('%H:%M:%S'),
					tostring(child and child.ClassName),
					name,
					tostring(workspace.StreamingEnabled)
				)
				task.defer(append, line)
			end

			if name == 'Mobs' or name == 'CharacterItems' then
				getgenv().SB2SkillActiveUntil = 0
				getgenv().SB2SkillActiveName = nil
				getgenv().SB2SkillCastLock = false
			end

			-- Stream wipe storm: many roots leave at once. Only re-pull YOUR position
			-- (multi-point RequestStreamAroundAsync was shifting interest and making it worse).
			local now = os.clock()
			removeStormTimes[#removeStormTimes + 1] = now
			local kept = {}
			for _, t in ipairs(removeStormTimes) do
				if (now - t) < 1.5 then
					kept[#kept + 1] = t
				end
			end
			removeStormTimes = kept
			if #removeStormTimes >= 8 and (now - lastStormRecoverAt) > 2.5 then
				lastStormRecoverAt = now
				append(string.format('[%s] STORM_RECOVER n=%d', os.date('%H:%M:%S'), #removeStormTimes))
				local model = getMyCharacterModel() or LocalPlayer.Character
				local hrp = model and model:FindFirstChild('HumanoidRootPart')
				lockReplicationFocus(model)
				if hrp then
					task.spawn(function()
						pcall(function()
							LocalPlayer:RequestStreamAroundAsync(hrp.Position, 40)
						end)
					end)
				end
			end
		end)
	end)

	-- Pull map chunks back when StreamingEnabled drops everything around you
	-- (visual void: sky + a few mobs, cam/char still "fine").
	local function requestStreamAround(char, force)
		local now = os.clock()
		if not force and (now - lastStreamRequestAt) < 1.25 then
			return false
		end
		local model = char or getMyCharacterModel() or LocalPlayer.Character
		local hrp = model and model:FindFirstChild('HumanoidRootPart')
		if not hrp then
			return false
		end
		lastStreamRequestAt = now
		lockReplicationFocus(model)
		local ok = pcall(function()
			LocalPlayer:RequestStreamAroundAsync(hrp.Position, mapLooksGone() and 30 or 12)
		end)
		return ok
	end

	-- Hard recovery when Workspace is hollow (Camera/Terrain/Characters only).
	-- IMPORTANT: only stream around the player. Requesting far points (spawn while at
	-- farm, ±120 offsets, etc.) shifts Replication interest and can wipe the current area.
	local function reloadStreamedMap(notify)
		local model = getMyCharacterModel() or LocalPlayer.Character
		local hrp = model and model:FindFirstChild('HumanoidRootPart')
		local hum = model and model:FindFirstChildOfClass('Humanoid')
		local cam = getLiveCamera()
		if not hrp then
			if notify then
				pcall(function()
					Library:Notify('No character — rejoin to reload map')
				end)
			end
			return false
		end
		lockReplicationFocus(model)
		if cam and hum then
			pcall(function()
				cam.CameraType = Enum.CameraType.Custom
				cam.CameraSubject = hum
				if (cam.CFrame.Position - hrp.Position).Magnitude > 80 then
					cam.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 10, 16), hrp.Position)
					cam.Focus = CFrame.new(hrp.Position)
				end
			end)
		end
		task.spawn(function()
			if not getgenv()[CONFIG.GenvKey] then
				return
			end
			pcall(function()
				LocalPlayer.ReplicationFocus = hrp
				LocalPlayer:RequestStreamAroundAsync(hrp.Position, 40)
			end)
			task.wait(0.5)
			pcall(function()
				if hrp.Parent then
					LocalPlayer:RequestStreamAroundAsync(hrp.Position, 40)
				end
			end)
			if notify then
				task.wait(0.8)
				local gone = mapLooksGone()
				pcall(function()
					if gone then
						Library:Notify('Map still empty — use Reload map / Unstuck (to spawn)')
					else
						Library:Notify('Map stream reload requested')
					end
				end)
			end
		end)
		return true
	end
	getgenv().SB2ReloadStreamedMap = reloadStreamedMap
	getgenv().SB2MapLooksGone = mapLooksGone

	-- High-air farms (saurus Y≈2343) are naturally sparse — absolute part counts lie.
	-- Track a rolling peak and only treat sudden collapse near ground/spawn as unload.
	local streamDensityPeak = 0
	local streamDensityPeakAt = 0
	local function worldLooksUnloaded(char)
		if mapLooksGone() then
			return true
		end
		local model = char or getMyCharacterModel() or LocalPlayer.Character
		local hrp = model and model:FindFirstChild('HumanoidRootPart')
		if not hrp then
			return false
		end
		local pos = hrp.Position
		local n = countPartsNear(pos, 120)
		if n < 0 then
			return false
		end
		local now = os.clock()
		if n >= streamDensityPeak or (now - streamDensityPeakAt) > 20 then
			streamDensityPeak = n
			streamDensityPeakAt = now
		elseif n > streamDensityPeak * 0.6 then
			streamDensityPeak = math.max(streamDensityPeak * 0.92, n)
			streamDensityPeakAt = now
		end
		-- High sky farms: ignore absolute sparsity (platform + mobs only).
		if pos.Y > 800 then
			return streamDensityPeak >= 12 and n <= 2
		end
		-- Ground/spawn: empty bubble or sudden collapse from a loaded peak.
		if n < 18 then
			return true
		end
		return streamDensityPeak >= 60 and n < (streamDensityPeak * 0.22)
	end

	local function fixCamera(preferredChar)
		local cam = getLiveCamera()
		if not cam then
			return false
		end
		-- Always leave Fixed/Scriptable void mode even before a subject exists.
		pcall(function()
			if cam.CameraType ~= Enum.CameraType.Custom then
				cam.CameraType = Enum.CameraType.Custom
			end
		end)
		local char = preferredChar
		if not char or not char.Parent then
			char = getMyCharacterModel()
		end
		if not char or not char.Parent then
			return false
		end
		lockReplicationFocus(char)
		requestStreamAround(char, true)
		local hum = char:FindFirstChildOfClass('Humanoid')
		if not hum then
			hum = char:FindFirstChild('Humanoid')
		end
		local hrp = char:FindFirstChild('HumanoidRootPart')
		local subject = hum or cameraSubjectFrom(char)
		if not subject then
			return false
		end
		local ok = pcall(function()
			cam.CameraType = Enum.CameraType.Custom
			-- Nudge subject even if already set — rebinding snaps a stuck void CFrame.
			if cam.CameraSubject == subject then
				cam.CameraSubject = nil
			end
			cam.CameraSubject = subject
			-- Fixed void often leaves Camera at origin (0,8,5) → Streaming unloads world.
			if hrp and (cam.CFrame.Position - hrp.Position).Magnitude > 60 then
				local look = hrp.CFrame.LookVector
				local flat = Vector3.new(look.X, 0, look.Z)
				if flat.Magnitude < 0.05 then
					flat = Vector3.new(0, 0, -1)
				else
					flat = flat.Unit
				end
				cam.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 8, 0) - flat * 14, hrp.Position + Vector3.new(0, 2, 0))
				cam.Focus = CFrame.new(hrp.Position)
			end
		end)
		return ok
	end
	getgenv().SB2FixCamera = fixCamera
	getgenv().SB2LockReplicationFocus = lockReplicationFocus
	getgenv().SB2RequestStreamAround = requestStreamAround

	local function cameraLooksBroken(cam, char)
		if not cam then
			return true
		end
		if cam.CameraType == Enum.CameraType.Fixed or cam.CameraType == Enum.CameraType.Scriptable then
			return true
		end
		-- Default void cam parked near origin with no subject.
		local cp = cam.CFrame.Position
		if cam.CameraSubject == nil and cp.Magnitude < 40 then
			return true
		end
		if not char or not char.Parent then
			return false
		end
		local hum = char:FindFirstChildOfClass('Humanoid')
		local subject = cam.CameraSubject
		if subject == nil or subject == char then
			return true -- nil / Model subject = classic SB2 void cam
		end
		-- Always prefer your Humanoid while alive and farming.
		if hum and subject ~= hum then
			return true
		end
		local hrp = char:FindFirstChild('HumanoidRootPart')
		if hrp then
			local dist = (cam.CFrame.Position - hrp.Position).Magnitude
			-- Cam at origin / far away = Streaming unloads map (mobs may still show).
			if dist > 60 then
				return true
			end
		end
		return false
	end

	local Profiles = game:GetService('ReplicatedStorage'):WaitForChild('Profiles', 25)
	local Profile = Profiles
		and (Profiles:FindFirstChild(LocalPlayer.Name) or Profiles:WaitForChild(LocalPlayer.Name, 8))

	local function getLiveProfile()
		if Profile and Profile.Parent then
			return Profile
		end
		local folder = game:GetService('ReplicatedStorage'):FindFirstChild('Profiles')
		if not folder then
			return nil
		end
		Profile = folder:FindFirstChild(LocalPlayer.Name) or folder:FindFirstChild(tostring(LocalPlayer.UserId))
		return Profile
	end

	local getExecutorName = function()
		local fn = type(identifyexecutor) == 'function' and identifyexecutor
			or type(getexecutorname) == 'function' and getexecutorname
		if fn then
			local success, name = pcall(fn)
			if success then
				return name
			end
		end
		return 'Unknown'
	end

	local RequiredServices = (function()
		if getExecutorName() == 'Xeno' then
			notify('Player Tools', 'Xeno is not supported')
			return nil
		end

		local methods = {
			function()
				local services
				for _, func in next, { getgc, getreg } do
					if type(func) == 'function' then
						for _, object in next, select(2, pcall(func, true)) do
							if type(object) == 'table' then
								local svc = rawget(object, 'Services')
								if svc and rawget(svc, 'Combat') then
									services = svc
									break
								end
							end
						end
					end
					if services then
						break
					end
				end
				if not services then
					return nil
				end

				local uiSafeInit = services.UI.SafeInit
				services.InventoryUI = debug.getupvalue(uiSafeInit, 18)
				services.StatsUI = debug.getupvalue(uiSafeInit, 40)
				services.TradeUI = debug.getupvalue(uiSafeInit, 31)
				return services
			end,
			function()
				local mainModule
				for _, func in next, { getloadedmodules, getnilinstances } do
					if type(func) == 'function' then
						for _, instance in next, select(2, pcall(func)) do
							if instance.Name == 'MainModule' and instance:FindFirstChild('Services') then
					ces') then
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

				local req = require or getrenv().require
				local services = req(mainModule).Services
				local ui = mainModule.Services.UI
				services.InventoryUI = req(ui.Inventory)
				services.StatsUI = req(ui.Stats)
				services.TradeUI = req(ui.Trade)
				return services
			end,
		}

		for _, method in methods do
			local success, services = pcall(method)
			if success and type(services) == 'table' then
				return services
			end
		end

		return nil
	end)()
	getgenv().SB2RequiredServices = RequiredServices
	if not RequiredServices then
		task.spawn(function()
			for _ = 1, 25 do
				task.wait(1)
				local loaded = getgenv().SB2CardinalServices
				if type(loaded) == 'table' and loaded.UI then
					RequiredServices = loaded
					getgenv().SB2RequiredServices = loaded
					break
				end
			end
		end)
	end

	local isDead = function(entity)
		if not (entity and entity.Parent) then
			return true
		end
		if not entity:FindFirstChild('HumanoidRootPart') then
			return true
		end
		local ent = entity:FindFirstChild('Entity')
		if not ent then
			local hum = entity:FindFirstChildOfClass('Humanoid')
			return not hum or hum.Health <= 0
		end
		local health = ent:FindFirstChild('Health')
		if not health then
			return false
		end
		local okHealth, healthValue = pcall(function()
			return health.Value
		end)
		if not okHealth or type(healthValue) ~= 'number' or healthValue <= 0 then
			return true
		end
		return false
	end

	local httpGet = function(url)
		local request = (syn and syn.request)
			or (http and http.request)
			or http_request
			or request
		if type(request) == 'function' then
			return request({ Url = url, Method = 'GET' }).Body
		end
		return game:HttpGet(url)
	end

	local compile = loadstring or load
	local librarySource = httpGet(CONFIG.UIRepo .. 'Library.lua')

	local deadLucide =
		'https://raw.githubusercontent.com/deividcomsono/lucide-roblox-direct/refs/heads/main/source.lua'
	local liveLucide = 'https://gitlab.com/upio/lucide-roblox-direct/-/raw/main/source.lua'
	if librarySource:find(deadLucide, 1, true) then
		librarySource = librarySource:gsub(deadLucide:gsub('(%W)', '%%%1'), liveLucide)
	end
	librarySource = librarySource:gsub(
		'pcall%(Icons%.GetAsset, IconName%)',
		'pcall(type(Icons) == "table" and Icons.GetAsset or function() end, IconName)'
	)

	local libraryFunc = compile(librarySource)
	assert(libraryFunc, 'Obsidian Library.lua failed to compile')

	-- Force a fresh Obsidian instance so AutoFarm can run beside us.
	getgenv().Library = nil
	local Library = libraryFunc()
	assert(Library and Library.CreateWindow, 'Obsidian library failed to initialize')
	getgenv()[LIBRARY_KEY] = Library
	if Library.ScreenGui then
		pcall(function()
			Library.ScreenGui:SetAttribute('SB2PlayerTools', true)
			Library.ScreenGui.Name = 'SB2PlayerTools'
		end)
		getgenv().SB2PlayerToolsGui = Library.ScreenGui
	end

	local Options = Library.Options
	local Toggles = Library.Toggles

	local isToggleOn = function(name)
		local toggle = Toggles[name]
		if type(toggle) ~= 'table' then
			return false
		end
		local okVal, value = pcall(function()
			return toggle.Value
		end)
		return okVal and value == true
	end

	local resolveWindowIcon = function(icon)
		if icon == nil then
			return nil
		end
		if type(icon) == 'string' and not icon:match('^%d+$') and not icon:match('^rbx') then
			return icon
		end
		local assetId = tonumber(icon) or tonumber(tostring(icon):match('%d+'))
		if not assetId then
			return icon
		end
		local okTex, texture = pcall(function()
			local model = game:GetService('InsertService'):LoadAsset(assetId)
			local decal = model:FindFirstChildWhichIsA('Decal', true)
			local uri = decal and decal.Texture ~= '' and decal.Texture or nil
			model:Destroy()
			return uri
		end)
		if okTex and type(texture) == 'string' and texture ~= '' then
			return texture
		end
		return ('rbxthumb://type=Asset&id=%d&w=150&h=150'):format(assetId)
	end

	local applyTitleIcon = function(iconUri)
		if not iconUri then
			return
		end
		local image = iconUri
		if Library.GetCustomIcon then
			local parsed = Library:GetCustomIcon(iconUri)
			if parsed then
				image = parsed.Url
			end
		elseif tonumber(image) then
			image = ('rbxassetid://%s'):format(image)
		end
		for _, gui in Library.ScreenGui:GetDescendants() do
			if gui:IsA('ImageLabel') and gui.Size == UDim2.fromOffset(30, 30) then
				gui.BackgroundTransparency = 1
				gui.ScaleType = Enum.ScaleType.Fit
				gui.ImageRectOffset = Vector2.zero
				gui.ImageRectSize = Vector2.zero
				gui.Image = image
				return true
			end
		end
	end

	local windowIcon = resolveWindowIcon(CONFIG.Icon)
	local windowWidth, windowHeight = 300, 260
	if CONFIG.WindowSize then
		windowWidth = CONFIG.WindowSize.X.Offset
		windowHeight = CONFIG.WindowSize.Y.Offset
	end
	-- Obsidian clamps CreateWindow Size to Library.MinSize (default 480×360).
	local minSize = CONFIG.WindowMinSize or Vector2.new(240, 180)
	pcall(function()
		Library.OriginalMinSize = minSize
		Library.MinSize = minSize
	end)
	local paddingX = CONFIG.WindowPaddingX or 12
	local paddingY = CONFIG.WindowPaddingY or 60
	local windowSize = UDim2.fromOffset(windowWidth, windowHeight)
	local defaultWindowPosition = UDim2.new(0, paddingX, 1, -(windowHeight + paddingY))
	local windowPosition = defaultWindowPosition

	local POSITION_PATH = joinPath(CONFIG.ConfigFolder, 'window_position')
	local encodeUDim2 = function(u)
		return ('%s,%s,%s,%s'):format(u.X.Scale, u.X.Offset, u.Y.Scale, u.Y.Offset)
	end
	local decodeUDim2 = function(raw)
		if type(raw) ~= 'string' then
			return nil
		end
		local xs, xo, ys, yo = raw:match('^%s*([^,]+),([^,]+),([^,]+),([^,%s]+)%s*$')
		xs, xo, ys, yo = tonumber(xs), tonumber(xo), tonumber(ys), tonumber(yo)
		if not (xs and xo and ys and yo) then
			return nil
		end
		return UDim2.new(xs, xo, ys, yo)
	end

	-- Reject positions that would place the window fully off-screen.
	local isPositionOnScreen = function(pos)
		if typeof(pos) ~= 'UDim2' then
			return false
		end
		local cam = workspace.CurrentCamera
		local vp = cam and cam.ViewportSize
		if not vp then
			return true
		end
		local absX = pos.X.Scale * vp.X + pos.X.Offset
		local absY = pos.Y.Scale * vp.Y + pos.Y.Offset
		-- Need at least ~80px of the window visible.
		if absX + windowWidth < 80 or absX > vp.X - 40 then
			return false
		end
		if absY + windowHeight < 80 or absY > vp.Y - 40 then
			return false
		end
		return true
	end

	local loadSavedWindowPosition = function()
		if type(isfile) ~= 'function' or type(readfile) ~= 'function' then
			return nil
		end
		local okExists, exists = pcall(isfile, POSITION_PATH)
		if not (okExists and exists) then
			return nil
		end
		local okRead, body = pcall(readfile, POSITION_PATH)
		if not okRead then
			return nil
		end
		local pos = decodeUDim2(body)
		if pos and not isPositionOnScreen(pos) then
			warn('[PlayerTools] saved window was off-screen — resetting')
			return nil
		end
		return pos
	end
	local saveWindowPosition = function(pos)
		if type(writefile) ~= 'function' then
			return
		end
		if not isPositionOnScreen(pos) then
			return
		end
		local folder = CONFIG.ConfigFolder
		if folder ~= '' and folder ~= '.' and type(isfolder) == 'function' and type(makefolder) == 'function' then
			if not isfolder(folder) then
				pcall(makefolder, folder)
			end
		end
		pcall(writefile, POSITION_PATH, encodeUDim2(pos))
	end

	local savedPos = loadSavedWindowPosition()
	if savedPos then
		windowPosition = savedPos
	end

	local windowInfo = {
		Title = CONFIG.Title,
		Footer = CONFIG.Footer,
		Icon = windowIcon,
		Size = windowSize,
		Position = windowPosition,
		ShowCustomCursor = false, -- Obsidian + crosshair on top of OS mouse
		Resizable = true,
	}
	local Window = Library:CreateWindow(windowInfo)
	assert(Window, 'CreateWindow returned nil')
	pcall(function()
		Library.ShowCustomCursor = false
		Library.OriginalMinSize = minSize
		Library.MinSize = minSize * (Library.DPIScale or 1)
	end)
	-- Re-apply size in case CreateWindow snapped up to the old 480×360 floor.
	pcall(function()
		local main = Library.ScreenGui and Library.ScreenGui:FindFirstChild('Main')
		if main then
			main.Size = windowSize
		end
	end)
	-- Kill any cursor frames already created before the flag applied.
	pcall(function()
		local gui = Library.ScreenGui
		if not gui then
			return
		end
		for _, child in ipairs(gui:GetChildren()) do
			if child:IsA('Frame') and child.Name == 'Frame' and not child:FindFirstChild('Main', true) then
				-- Obsidian cursor is a tiny Frame tree under ScreenGui (not Main).
				local size = child.AbsoluteSize
				if size.X <= 20 and size.Y <= 20 then
					child:Destroy()
				end
			end
		end
	end)

	local forceShowWindow = function(resetPos)
		pcall(function()
			if Library.Unloaded then
				return
			end
			if Library.Toggle then
				-- Ensure UI is open (some forks use Toggled / Open).
				if Library.Toggled == false and type(Library.Toggle) == 'function' then
					Library:Toggle()
				elseif Library.Open == false and type(Library.Toggle) == 'function' then
					Library:Toggle()
				end
			end
			if Library.ScreenGui then
				Library.ScreenGui.Enabled = true
			end
			local main = Library.ScreenGui and Library.ScreenGui:FindFirstChild('Main')
			if main then
				main.Visible = true
				if resetPos or not isPositionOnScreen(main.Position) then
					main.Position = defaultWindowPosition
					saveWindowPosition(defaultWindowPosition)
				end
			end
		end)
	end

	pcall(function()
		local main = Library.ScreenGui:FindFirstChild('Main')
		if not main then
			return
		end
		if not isPositionOnScreen(windowPosition) then
			windowPosition = defaultWindowPosition
		end
		main.Position = windowPosition
		local saveToken = 0
		main:GetPropertyChangedSignal('Position'):Connect(function()
			saveToken += 1
			local token = saveToken
			task.delay(0.2, function()
				if token == saveToken and main and main.Parent then
					saveWindowPosition(main.Position)
				end
			end)
		end)
	end)

	task.defer(function()
		forceShowWindow(false)
		notify('Player Tools', 'UI ready — press End if hidden. Bottom-left if you lose it.')
	end)

	task.spawn(function()
		for _ = 1, 10 do
			if applyTitleIcon(windowIcon) then
				break
			end
			task.wait(0.1)
		end
	end)

	local PlayersBox = Window:AddTab('Players', 'users'):AddLeftGroupbox('Players')
	assert(PlayersBox, 'AddLeftGroupbox returned nil')

	local selectedPlayer

	local getLevelFromExp = function(exp)
		if type(exp) ~= 'number' or exp < 0 then
			return 0
		end
		return math.floor(exp ^ (1 / 3))
	end

	local formatNumber = function(n)
		if type(n) ~= 'number' then
			return tostring(n)
		end
		local neg = n < 0
		n = math.floor(math.abs(n) + 0.5)
		local s = tostring(n)
		while true do
			local ns, k = s:gsub('^(-?%d+)(%d%d%d)', '%1,%2')
			s = ns
			if k == 0 then
				break
			end
		end
		return neg and ('-' .. s) or s
	end

	local getInventoryItemNameById = function(profile, id)
		if not profile or not id or id == 0 then
			return 'none'
		end
		local inv = profile:FindFirstChild('Inventory')
		if not inv then
			return 'none'
		end
		for _, item in ipairs(inv:GetChildren()) do
			if item:IsA('ValueBase') and item.Value == id then
				return item.Name
			end
		end
		return 'unknown'
	end

	local readPlayerStats = function(player)
		if not player then
			return nil
		end
		local profile = Profiles:FindFirstChild(player.Name)
		if not profile then
			return nil
		end
		local stats = profile:FindFirstChild('Stats')
		local expVal = stats and stats:FindFirstChild('Exp')
		local velVal = stats and stats:FindFirstChild('Vel')
		local exp = (expVal and typeof(expVal.Value) == 'number') and expVal.Value or 0
		local vel = (velVal and typeof(velVal.Value) == 'number') and velVal.Value or 0
		local equip = profile:FindFirstChild('Equip')
		local rightId = equip and equip:FindFirstChild('Right') and equip.Right.Value
		local leftId = equip and equip:FindFirstChild('Left') and equip.Left.Value
		local armorId = equip and equip:FindFirstChild('Clothing') and equip.Clothing.Value
		local companionId = equip and equip:FindFirstChild('Companion') and equip.Companion.Value
		local accessory1Id = equip and equip:FindFirstChild('Accessory1') and equip.Accessory1.Value
		local accessory2Id = equip and equip:FindFirstChild('Accessory2') and equip.Accessory2.Value

		local char = player.Character
			or (workspace:FindFirstChild('Characters') and workspace.Characters:FindFirstChild(player.Name))
		local entity = char and char:FindFirstChild('Entity')
		local buffs = entity and entity:FindFirstChild('Buffs')
		local hum = char and char:FindFirstChildOfClass('Humanoid')

		local readBuff = function(name)
			local v = buffs and buffs:FindFirstChild(name)
			if v and typeof(v.Value) == 'number' then
				return v.Value
			end
			return nil
		end

		local walkSpeed = hum and hum.WalkSpeed or nil
		if (not walkSpeed or walkSpeed == 0) and char then
			local attr = char:GetAttribute('Walkspeed') or char:GetAttribute('WalkSpeed')
			if type(attr) == 'number' then
				walkSpeed = attr
			end
		end

		return {
			profile = profile,
			level = getLevelFromExp(exp),
			vel = vel,
			right = getInventoryItemNameById(profile, rightId),
			left = getInventoryItemNameById(profile, leftId),
			armor = getInventoryItemNameById(profile, armorId),
			companion = getInventoryItemNameById(profile, companionId),
			accessory1 = getInventoryItemNameById(profile, accessory1Id),
			accessory2 = getInventoryItemNameById(profile, accessory2Id),
			staminaRegen = readBuff('StaminaRegeneration'),
			healthRegen = readBuff('HealthRegeneration'),
			speedBuff = readBuff('Speed'),
			walkSpeed = walkSpeed,
			jumpPower = hum and hum.JumpPower or nil,
			jumpHeight = hum and hum.JumpHeight or nil,
			loaded = char ~= nil,
		}
	end

	local showPlayerStatsNotify = function()
		local player = selectedPlayer or (Options.PlayerList and Options.PlayerList.Value)
		if not player then
			Library:Notify('Select a player first')
			return
		end
		local info = readPlayerStats(player)
		if not info then
			Library:Notify(player.Name .. ' — profile unavailable')
			return
		end

		local fmt = function(v, suffix)
			if v == nil then
				return '—'
			end
			if type(v) == 'number' then
				local rounded = math.floor(v * 100 + 0.5) / 100
				return tostring(rounded) .. (suffix or '')
			end
			return tostring(v)
		end

		local gearLines = {
			player.Name .. ' — gear',
			'Right: ' .. info.right,
			'Left: ' .. info.left,
			'Armor: ' .. info.armor,
			'Accessory 1: ' .. info.accessory1,
			'Accessory 2: ' .. info.accessory2,
			'Companion: ' .. info.companion,
		}
		local statLines = {
			player.Name .. ' — stats',
			'Level ' .. tostring(info.level),
			'Vel ' .. formatNumber(info.vel),
			'Stamina regen: ' .. fmt(info.staminaRegen),
			'Health regen: ' .. fmt(info.healthRegen),
			'Speed buff: ' .. fmt(info.speedBuff),
			'Walk speed: ' .. fmt(info.walkSpeed),
			'Jump power: ' .. fmt(info.jumpPower),
		}
		if not info.loaded then
			statLines[#statLines + 1] = '(character not loaded — regen/speed may be blank)'
		end
		-- Two notifies so accessories aren't clipped by Obsidian's notify height.
		Library:Notify(table.concat(gearLines, '\n'), 12)
		task.defer(function()
			Library:Notify(table.concat(statLines, '\n'), 10)
		end)
	end

	PlayersBox:AddDropdown('PlayerList', {
		Text = 'Player list',
		Values = {},
		SpecialType = 'Player',
	}):OnChanged(function(player)
		selectedPlayer = player

		if RequiredServices
			and isToggleOn('ViewPlayersInventory')
			and RequiredServices.InventoryUI
			and RequiredServices.InventoryUI.GetInventoryData
		then
			debug.setupvalue(RequiredServices.InventoryUI.GetInventoryData, 2, Profiles[player.Name])
		end
	end)

	PlayersBox:AddButton('View stats', function()
		showPlayerStatsNotify()
	end)

	if RequiredServices
		and RequiredServices.InventoryUI
		and RequiredServices.InventoryUI.GetInventoryData
	then
		PlayersBox:AddToggle('ViewPlayersInventory', { Text = 'Inventory' }):OnChanged(function(value)
			if not value then
				debug.setupvalue(RequiredServices.InventoryUI.GetInventoryData, 2, Profile)
				return
			end

			local player = Options.PlayerList and Options.PlayerList.Value
			if not player then
				Library:Notify('Select a player first')
				if Toggles.ViewPlayersInventory then
					Toggles.ViewPlayersInventory:SetValue(false)
				end
				return
			end

			debug.setupvalue(RequiredServices.InventoryUI.GetInventoryData, 2, Profiles[player.Name])
			Library:Notify('Open your inventory in-game to view ' .. player.Name .. "'s items")
		end)
	else
		PlayersBox:AddLabel('Inventory viewing unavailable')
		PlayersBox:AddLabel('(executor missing getgc/debug.setupvalue?)')
	end

	PlayersBox:AddToggle('ViewPlayer', { Text = 'Spectate' }):OnChanged(function(value)
		if not value then
			fixCamera(Character)
			return
		end

		if not selectedPlayer then
			Library:Notify('Select a player first')
			Toggles.ViewPlayer:SetValue(false)
			return
		end

		while isToggleOn('ViewPlayer') do
			local cam = getLiveCamera()
			if selectedPlayer and not isDead(selectedPlayer.Character) then
				local subject = cameraSubjectFrom(selectedPlayer.Character)
				if cam and subject then
					cam.CameraSubject = subject
				end
			else
				-- Target died / left — snap back so we don't stare into the void.
				fixCamera(LocalPlayer.Character or Character)
			end
			task.wait(0.1)
		end

		fixCamera(LocalPlayer.Character or Character)
	end)

	PlayersBox:AddButton('Fix camera', function()
		if isToggleOn('ViewPlayer') then
			Toggles.ViewPlayer:SetValue(false)
		end
		task.spawn(function()
			for _ = 1, 20 do
				if fixCamera(getMyCharacterModel()) then
					Library:Notify('Camera reset to your character')
					return
				end
				task.wait(0.15)
			end
			Library:Notify('Still no humanoid — try Unstuck (to spawn) or Fix camera')
		end)
	end)

	-- OS mouse + hide Obsidian's custom + cursor (and SB2 MouseIcon disable).
	local UserInputService = game:GetService('UserInputService')
	local function stripObsidianCursor()
		pcall(function()
			Library.ShowCustomCursor = false
		end)
		local function stripGui(gui)
			if not gui then
				return
			end
			for _, child in ipairs(gui:GetChildren()) do
				if child.Name == 'Main' or child.Name == 'Window' then
					continue
				end
				if child:IsA('Frame') then
					local size = child.AbsoluteSize
					-- Cursor widget is a few-pixel Frame crosshair under ScreenGui.
					if size.X <= 24 and size.Y <= 24 then
						pcall(function()
							child:Destroy()
						end)
					end
				end
			end
		end
		stripGui(Library.ScreenGui)
		stripGui(getgenv().SB2PlayerToolsGui)
	end
	local function restoreDefaultCursor()
		getgenv().SB2DefaultCursorLock = true
		pcall(function()
			UserInputService.MouseIconEnabled = true
		end)
		pcall(function()
			local mouse = LocalPlayer:GetMouse()
			if mouse then
				mouse.Icon = ''
			end
		end)
		stripObsidianCursor()
	end
	restoreDefaultCursor()
	if getgenv().SB2DefaultCursorLockConn then
		pcall(function()
			getgenv().SB2DefaultCursorLockConn:Disconnect()
		end)
		getgenv().SB2DefaultCursorLockConn = nil
	end
	-- Heartbeat ~4Hz — RenderStepped GetMouse on 5 clients was a lot of CPU.
	do
		local cursorAccum = 0
		getgenv().SB2DefaultCursorLockConn = game:GetService('RunService').Heartbeat:Connect(function(dt)
			if getgenv().SB2DefaultCursorLock == false then
				return
			end
			cursorAccum += dt
			if cursorAccum < 0.25 then
				return
			end
			cursorAccum = 0
			if not UserInputService.MouseIconEnabled then
				pcall(function()
					UserInputService.MouseIconEnabled = true
				end)
			end
			pcall(function()
				local mouse = LocalPlayer:GetMouse()
				if mouse and mouse.Icon ~= '' then
					mouse.Icon = ''
				end
			end)
			if Library.ShowCustomCursor then
				Library.ShowCustomCursor = false
			end
		end)
	end
	-- Periodic strip (cheaper than every render for Destroy scans).
	task.spawn(function()
		while getgenv()[CONFIG.GenvKey] do
			if getgenv().SB2DefaultCursorLock ~= false then
				stripObsidianCursor()
			end
			task.wait(0.5)
		end
	end)
	PlayersBox:AddButton('Fix cursor', function()
		restoreDefaultCursor()
		Library:Notify('Default cursor — Obsidian + removed')
	end)

	-- Esc→Reset needs a living Humanoid. SB2 void-stuck leaves Parent=nil husk → Reset does nothing.
	local TeleportService = game:GetService('TeleportService')
	local lastCharacterAddedAt = os.clock()
	local voidHuskSince = nil

	local function tryClickNoRevive()
		local pg = LocalPlayer:FindFirstChild('PlayerGui')
		local pop = pg and pg:FindFirstChild('CardinalUI')
		pop = pop and pop:FindFirstChild('PlayerUI')
		pop = pop and pop:FindFirstChild('Popups')
		local rf = pop and pop:FindFirstChild('ReviveFrame')
		if not rf or not rf.Visible then
			return false
		end
		local btn = rf:FindFirstChild('NoRevive') or rf:FindFirstChild('Revive')
		if not btn or not btn:IsA('GuiButton') then
			return false
		end
		local clicked = false
		pcall(function()
			if type(firesignal) == 'function' then
				firesignal(btn.MouseButton1Click)
				clicked = true
			end
		end)
		pcall(function()
			btn:Activate()
			clicked = true
		end)
		return clicked
	end

	local function getCombatChar()
		local ws = workspace:FindFirstChild('Characters')
		local wsChar = ws and ws:FindFirstChild(LocalPlayer.Name)
		return wsChar or LocalPlayer.Character
	end

	local function isUsableChar(model)
		if not model or not model.Parent then
			return false
		end
		local hum = model:FindFirstChildOfClass('Humanoid')
		local hrp = model:FindFirstChild('HumanoidRootPart')
		if not hum or not hrp then
			return false
		end
		if hum.Health <= 0 then
			return false
		end
		local entity = model:FindFirstChild('Entity')
		local health = entity and entity:FindFirstChild('Health')
		if health and typeof(health.Value) == 'number' and health.Value <= 0 then
			return false
		end
		return true
	end

	-- Dead / missing body (Reset usually useless).
	local function isVoidHusk()
		local ws = workspace:FindFirstChild('Characters')
		local wsChar = ws and ws:FindFirstChild(LocalPlayer.Name)
		local lpChar = LocalPlayer.Character
		if isUsableChar(wsChar) or isUsableChar(lpChar) then
			return false
		end
		return true
	end

	-- Truly under the map only. High Air farms (e.g. saurus Y≈2343) are valid.
	local function isUnderMap()
		local model = getCombatChar()
		if not isUsableChar(model) then
			return false
		end
		local hrp = model:FindFirstChild('HumanoidRootPart')
		return hrp and hrp.Position.Y < -100
	end

	-- Camera Fixed/nil while body is fine — do NOT teleport (that yanked high farms to Y≈35).
	local function isCameraVoidOnly()
		local model = getCombatChar()
		if not isUsableChar(model) then
			return false
		end
		local cam = workspace.CurrentCamera
		if not cam then
			return true
		end
		return cam.CameraType == Enum.CameraType.Fixed
			or cam.CameraType == Enum.CameraType.Scriptable
			or cam.CameraSubject == nil
			or cam.CameraSubject == model
	end

	local function isVoidStuck()
		if getgenv().SB2DiveFarmOn or isToggleOn('DiveFarm') then
			return isVoidHusk()
		end
		return isVoidHusk() or isUnderMap()
	end

	local function stopCombatForVoid()
		pcall(function()
			if Toggles.AutoAttack and Toggles.AutoAttack.Value then
				Toggles.AutoAttack:SetValue(false)
			end
		end)
		pcall(function()
			if Toggles.AutoSkill and Toggles.AutoSkill.Value then
				Toggles.AutoSkill:SetValue(false)
			end
		end)
		pcall(function()
			if Toggles.DiveFarm and Toggles.DiveFarm.Value then
				Toggles.DiveFarm:SetValue(false)
			end
		end)
		local conn = getgenv().SB2AutoAttackConn
		if conn then
			pcall(function()
				conn:Disconnect()
			end)
			getgenv().SB2AutoAttackConn = nil
		end
	end

	-- Camera-only recovery — never moves your character (high farms stay put).
	local function tryFixCameraOnly()
		local model = getCombatChar()
		if not model then
			return false
		end
		return fixCamera(model) == true
	end

	-- NEVER auto-teleports. Old versions clamped high farms (saurus Y≈2343) down to Y≈35.
	local function trySoftUnstuck()
		return tryFixCameraOnly()
	end

	getgenv().SB2ForceRejoinUnstuck = nil
	getgenv().SB2VoidRejoining = nil
	getgenv().SB2IsVoidHusk = isVoidHusk
	getgenv().SB2IsVoidStuck = isVoidStuck
	getgenv().SB2TrySoftUnstuck = trySoftUnstuck

	PlayersBox:AddButton('Unstuck (to spawn)', function()
		stopCombatForVoid()
		local model = getCombatChar()
		local hrp = model and model:FindFirstChild('HumanoidRootPart')
		if hrp then
			pcall(function()
				if Toggles.CombatAnchor and Toggles.CombatAnchor.Value then
					Toggles.CombatAnchor:SetValue(false)
				end
				hrp.Anchored = false
				local spawn = workspace:FindFirstChildWhichIsA('SpawnLocation', true)
				if spawn then
					hrp.CFrame = spawn.CFrame + Vector3.new(0, 6, 0)
				else
					hrp.CFrame = CFrame.new(4367, 340, 222)
				end
			end)
		end
		pcall(tryFixCameraOnly)
		pcall(reloadStreamedMap, false)
		Library:Notify('Moved to spawn + camera fixed')
	end)

	PlayersBox:AddButton('Reload map (stream)', function()
		pcall(tryFixCameraOnly)
		reloadStreamedMap(true)
	end)

	PlayersBox:AddButton('Rejoin if stuck loading', function()
		if LoadSkip.overlayUp() then
			LoadSkip.rejoin('manual')
			Library:Notify('Rejoining — keep Autoexecute on so PlayerTools comes back.', 6)
		else
			Library:Notify('Loading overlay is not up on this client.', 4)
		end
	end)

	LocalPlayer.CharacterAdded:Connect(function(newCharacter)
		Character = newCharacter
		cachedMyChar, cachedMyCharAt = nil, 0
		lastCharacterAddedAt = os.clock()
		voidHuskSince = nil
		task.spawn(function()
			local hum = newCharacter:WaitForChild('Humanoid', 15)
			if not hum then
				return
			end
			local hrp = newCharacter:WaitForChild('HumanoidRootPart', 10)
			if hrp then
				lockReplicationFocus(newCharacter)
				requestStreamAround(newCharacter, true)
				holdCombatAnchor(4)
			end
			for _ = 1, 30 do
				if isToggleOn('ViewPlayer') then
					return
				end
				if fixCamera(newCharacter) then
					requestStreamAround(newCharacter, true)
					return
				end
				task.wait(0.2)
			end
		end)
	end)

	-- Camera / map recovery only — no auto-rejoin.
	task.spawn(function()
		local RunService = game:GetService('RunService')
		local accum = 0
		RunService.Heartbeat:Connect(function(dt)
			if not getgenv()[CONFIG.GenvKey] then
				return
			end
			accum += dt
			if accum < 0.5 then
				return
			end
			accum = 0
			if (os.clock() - lastCharacterAddedAt) < 3 then
				voidHuskSince = nil
				return
			end
			if isCameraVoidOnly() then
				pcall(tryFixCameraOnly)
			end

			if isVoidHusk() then
				stopCombatForVoid()
				if not voidHuskSince then
					voidHuskSince = os.clock()
				end
			else
				voidHuskSince = nil
			end

			if mapLooksGone() then
				if not mapGoneSince then
					mapGoneSince = os.clock()
					mapGoneReloadTried = false
				end
				local goneFor = os.clock() - mapGoneSince
				if goneFor >= 4 and not mapGoneReloadTried then
					mapGoneReloadTried = true
					pcall(reloadStreamedMap, false)
				elseif goneFor >= 20 and (os.clock() - lastMapGoneNotifyAt) > 30 then
					lastMapGoneNotifyAt = os.clock()
					pcall(function()
						Library:Notify('Map still empty — use Reload map / Unstuck (to spawn)')
					end)
				end
			else
				mapGoneSince = nil
				mapGoneReloadTried = false
			end
		end)
	end)

	-- Camera-only void is common while AA still farms: Fixed/nil subject or cam CFrame
	-- stuck in the sky while your body keeps hitting mobs.
	-- SB2 often re-applies Fixed after Camera priority — bind at Last + PropertyChanged.
	task.spawn(function()
		local RunService = game:GetService('RunService')
		if getgenv().SB2CameraLockConn then
			pcall(function()
				getgenv().SB2CameraLockConn:Disconnect()
			end)
			getgenv().SB2CameraLockConn = nil
		end
		pcall(function()
			RunService:UnbindFromRenderStep('SB2CamLock')
		end)
		pcall(function()
			RunService:UnbindFromRenderStep('SB2CamLockLast')
		end)

		local camPropConns = {}
		local lastHeavyCamCheckAt = 0
		local cachedMapGone = false
		local cachedWorldUnloaded = false

		-- Combat Anchor only — never snap CFrame on freefall (that rubberbanded falls).
		local function pinHighAir(char)
			if not isToggleOn('CombatAnchor') then
				return
			end
			if combatAnchorHolding() then
				local hrpHold = char and char:FindFirstChild('HumanoidRootPart')
				if hrpHold then
					pcall(function()
						hrpHold.Anchored = false
					end)
				end
				return
			end
			local hrp = char and char:FindFirstChild('HumanoidRootPart')
			if not hrp then
				return
			end
			pcall(function()
				hrp.AssemblyLinearVelocity = Vector3.zero
				hrp.AssemblyAngularVelocity = Vector3.zero
				hrp.Anchored = true
			end)
		end

		local function hardenCamera()
			if not getgenv()[CONFIG.GenvKey] then
				return
			end
			if isToggleOn('ViewPlayer') then
				return
			end
			local cam = getLiveCamera()
			local char = getMyCharacterModel() or LocalPlayer.Character
			-- Cheap every-frame work only.
			lockReplicationFocus(char)
			pinHighAir(char)
			if cameraLooksBroken(cam, char) then
				fixCamera(char)
				pinHighAir(char)
			end

			-- mapLooksGone / GetPartBoundsInRadius / RequestStreamAround are expensive —
			-- running them on RenderStep was hitching. Throttle to ~1.5s.
			local now = os.clock()
			if (now - lastHeavyCamCheckAt) < 1.5 then
				return
			end
			lastHeavyCamCheckAt = now
			cachedMapGone = mapLooksGone()
			if cachedMapGone then
				if (now - lastMapGoneNotifyAt) > 8 then
					lastMapGoneNotifyAt = now
					pcall(function()
						Library:Notify('Map unloaded — requesting stream…')
					end)
					task.defer(function()
						reloadStreamedMap(false)
					end)
				else
					task.defer(function()
						requestStreamAround(char, false)
					end)
				end
				return
			end
			cachedWorldUnloaded = worldLooksUnloaded(char)
			if cachedWorldUnloaded then
				task.defer(function()
					requestStreamAround(char, false)
				end)
			end
		end

		local function bindCamProps(cam)
			for _, c in ipairs(camPropConns) do
				pcall(function()
					c:Disconnect()
				end)
			end
			table.clear(camPropConns)
			if not cam then
				return
			end
			local function onCamProp()
				if cameraLooksBroken(cam, getMyCharacterModel() or LocalPlayer.Character) then
					hardenCamera()
				end
			end
			table.insert(camPropConns, cam:GetPropertyChangedSignal('CameraType'):Connect(onCamProp))
			table.insert(camPropConns, cam:GetPropertyChangedSignal('CameraSubject'):Connect(onCamProp))
		end

		bindCamProps(getLiveCamera())
		local camChanged = workspace:GetPropertyChangedSignal('CurrentCamera'):Connect(function()
			bindCamProps(getLiveCamera())
			hardenCamera()
		end)

		-- Last wins against SB2 scripts that set Fixed after default Camera priority.
		-- 20Hz is enough; property-changed still calls hardenCamera immediately.
		local lastHardenAt = 0
		local function hardenCameraStepped()
			local now = os.clock()
			if (now - lastHardenAt) < 0.05 then
				return
			end
			lastHardenAt = now
			hardenCamera()
		end
		RunService:BindToRenderStep('SB2CamLockLast', Enum.RenderPriority.Last.Value, hardenCameraStepped)
		getgenv().SB2CameraLockConn = {
			Disconnect = function()
				pcall(function()
					RunService:UnbindFromRenderStep('SB2CamLock')
				end)
				pcall(function()
					RunService:UnbindFromRenderStep('SB2CamLockLast')
				end)
				for _, c in ipairs(camPropConns) do
					pcall(function()
						c:Disconnect()
					end)
				end
				pcall(function()
					camChanged:Disconnect()
				end)
			end,
		}
	end)

	-- ── Combat (auto skill + auto attack) — same stack as AutoFarm ──
	-- Own function: the outer pcall already holds ~100 locals, and Luau's
	-- 200-register limit was aborting compile at getMobAttackCFrame.
	;(function()
		local RunService = game:GetService('RunService')
		local ReplicatedStorage = game:GetService('ReplicatedStorage')
		local CombatEvent = ReplicatedStorage:FindFirstChild('Event')
		local CombatFunction = ReplicatedStorage:FindFirstChild('Function')
		local AUTO_ATTACK_RANGE = 200
		-- Wide skill tagging range, but we still cap how many mobs we hit per tick.
		local SKILL_HIT_RANGE = 10000
		local AUTO_ATTACK_INTERVAL = 0.12
		local AUTO_ATTACK_DELAY = 0.08
		local HIT_LIVES_ATTACK_INTERVAL = 0.05
		local HIT_LIVES_ATTACK_DELAY = 0.05
		local HIT_LIVES_MIN_DELAY = 0.05
		local MAX_ATTACKS_PER_TICK = 14
		-- Gap between any UseSkill casts (weapon + support).
		local SKILL_CAST_GAP = 0.5
		local lastAnySkillCastAt = 0

		local getOptionNumber = function(name, fallback)
			local opt = Options[name]
			if type(opt) ~= 'table' then
				return fallback
			end
			local ok, value = pcall(function()
				return opt.Value
			end)
			if ok and type(value) == 'number' then
				return value
			end
			if ok and type(value) == 'string' then
				return tonumber(value) or fallback
			end
			return fallback
		end

		local copyKeyTable = function(source)
			if type(source) ~= 'table' then
				return nil
			end
			local copy = {}
			for index, value in pairs(source) do
				copy[index] = value
			end
			return copy
		end

		local combatState = getgenv().SB2CombatState
		if type(combatState) ~= 'table' then
			combatState = {
				-- Match Neuublue: one RPCKey + Attack key '2'. Never brute RefillKeys.
				rpcKey = { '\xCC', '\xD6', '\xB1', '\xFB' },
				keys = { '2' },
				sniffed = false,
				rpcReady = false,
			}
			getgenv().SB2CombatState = combatState
		end
		combatState.keysValidated = nil -- drop kicky flag from prior builds

		local refreshRpcKey = function()
			if combatState.rpcReady and type(combatState.rpcKey) == 'table' then
				return true
			end
			if not CombatFunction then
				CombatFunction = ReplicatedStorage:FindFirstChild('Function')
			end
			if not CombatFunction then
				return false
			end
			local ok, key = pcall(function()
				return CombatFunction:InvokeServer('RPCKey', {})
			end)
			if ok and type(key) == 'table' then
				local copied = copyKeyTable(key)
				if copied then
					combatState.rpcKey = copied
					combatState.rpcReady = true
					combatState.sniffed = true
					return true
				end
			end
			return false
		end

		-- Passive-only: steal the game's real rpcKey when YOU swing. No Invoke spam.
		getgenv().SB2CombatSnifferOnCombat = function(rpcKey, payload)
			local copied = copyKeyTable(rpcKey)
			if copied then
				combatState.rpcKey = copied
				combatState.rpcReady = true
				combatState.sniffed = true
			end
			if type(payload) == 'table' and payload[1] == 'Attack' and payload[4] ~= nil then
				-- Prefer keeping a single working seed key ('2' is fine for Neuublue).
				if #combatState.keys < 8 then
					combatState.keys[#combatState.keys + 1] = payload[4]
				end
			end
		end

		local installCombatSniffer = function()
			if type(hookmetamethod) ~= 'function' or type(getnamecallmethod) ~= 'function' then
				return
			end
			if getgenv().SB2CombatSnifferDispatch then
				return
			end
			local old
			local dispatch
			dispatch = function(self, ...)
				local method = getnamecallmethod()
				if (method == 'FireServer' or method == 'fireServer')
					and typeof(self) == 'Instance'
					and self.Name == 'Event'
				then
					local args = { ... }
					if args[1] == 'Combat' and type(args[2]) == 'table' then
						local cb = getgenv().SB2CombatSnifferOnCombat
						if type(cb) == 'function' then
							pcall(cb, args[2], args[3])
						end
					end
				end
				return old(self, ...)
			end
			if type(newcclosure) == 'function' then
				dispatch = newcclosure(dispatch)
			end
			old = hookmetamethod(game, '__namecall', dispatch)
			if type(old) == 'function' then
				getgenv().SB2CombatSnifferOld = old
				getgenv().SB2CombatSnifferDispatch = true
				getgenv().SB2CombatSnifferInstalled = true
			end
		end
		pcall(installCombatSniffer)

		-- Neuublue path uses a fixed attack key '2' — do NOT InvokeServer RefillKeys /
		-- guess rpc keys from getgc (that was Secure API Violation 1).
		local takeCombatKey = function()
			if #combatState.keys == 0 then
				return '2'
			end
			-- Reuse last key; don't deplete / refill.
			return combatState.keys[#combatState.keys] or '2'
		end

		task.spawn(function()
			task.wait(0.35)
			-- One RPCKey fetch only. Never loop / never RefillKeys probe.
			pcall(refreshRpcKey)
		end)

		local getMyBringPart = function()
			local model = getMyCharacterModel()
			if not model or not model.Parent then
				return nil
			end
			return model:FindFirstChild('HumanoidRootPart')
				or model:FindFirstChild('UpperTorso')
				or model:FindFirstChild('Torso')
		end

		local isLocalAlive = function()
			local model = getMyCharacterModel()
			if not model or not model.Parent then
				return false
			end
			local hum = model:FindFirstChildOfClass('Humanoid')
			if hum and hum.Health <= 0 then
				return false
			end
			local entity = model:FindFirstChild('Entity')
			local health = entity and entity:FindFirstChild('Health')
			if health and typeof(health.Value) == 'number' and health.Value <= 0 then
				return false
			end
			-- No humanoid yet (loading / dead) — treat as not ready to fight.
			if not hum and not (entity and health) then
				return false
			end
			return getMyBringPart() ~= nil
		end

		local getMobRoot = function(mob)
			if not mob or not mob.Parent then
				return nil
			end
			local root = mob:FindFirstChild('HumanoidRootPart')
				or mob:FindFirstChild('Torso')
				or mob:FindFirstChild('UpperTorso')
			if root and root:IsA('BasePart') then
				return root
			end
			return nil
		end

		local isDeadMob = function(mob)
			local entity = mob and mob:FindFirstChild('Entity')
			local health = entity and entity:FindFirstChild('Health')
			if health and typeof(health.Value) == 'number' then
				if health.Value <= 0 then
					return true
				end
			end
			local hitLives = entity and entity:FindFirstChild('HitLives')
			if hitLives and typeof(hitLives.Value) == 'number' and hitLives.Value <= 0 then
				return true
			end
			return false
		end

		local MOB_ATTACK_BLACKLIST = {
			['gorilla berserker'] = true,
		}
		local shouldSkipMob = function(mob)
			if not mob then
				return true
			end
			local name = string.lower(tostring(mob.Name))
			if MOB_ATTACK_BLACKLIST[name] then
				return true
			end
			if string.find(name, 'gorilla berserker', 1, true) then
				return true
			end
			return false
		end

		local setCharacterNoclip = function(enabled)
			-- PlayerTools combat is stand-still killaura — never flip collision.
			-- (Noclip restore mid-fight was dropping people through floors / void-killing.)
			return
		end

		local getSkillDatabase = function()
			local database = ReplicatedStorage:FindFirstChild('Database')
			return database and database:FindFirstChild('Skills')
		end

		local getItemsDatabase = function()
			local database = ReplicatedStorage:FindFirstChild('Database')
			return database and database:FindFirstChild('Items')
		end

		local normalizeWeaponClass = function(className)
			if not className or className == '' then
				return nil
			end
			className = tostring(className)
			if className == 'SingleSword' then
				return '1HSword'
			end
			return className
		end

		local getInventoryItemById = function(id)
			if not id or id == 0 then
				return nil
			end
			local profile = getLiveProfile()
			local inv = profile and profile:FindFirstChild('Inventory')
			if not inv then
				return nil
			end
			for _, item in ipairs(inv:GetChildren()) do
				if item:IsA('ValueBase') and item.Value == id then
					return item
				end
			end
			return nil
		end

		local getEquippedWeaponClasses = function()
			local classes = {}
			local profile = getLiveProfile()
			local equip = profile and profile:FindFirstChild('Equip')
			local itemsDb = getItemsDatabase()
			if not equip or not itemsDb then
				return classes
			end
			for _, hand in ipairs({ 'Right', 'Left' }) do
				local slot = equip:FindFirstChild(hand)
				local id = slot and slot.Value
				local item = getInventoryItemById(id)
				if item then
					local entry = itemsDb:FindFirstChild(item.Name)
					local cls = entry and entry:FindFirstChild('Class')
					local typ = entry and entry:FindFirstChild('Type')
					if typ and tostring(typ.Value) == 'Weapon' and cls then
						local norm = normalizeWeaponClass(cls.Value)
						if norm then
							classes[norm] = true
						end
					end
				end
			end
			return classes
		end

		local getSkillInfo = function(skillName)
			local skillsDb = getSkillDatabase()
			local entry = skillsDb and skillsDb:FindFirstChild(skillName)
			if not entry then
				return { name = skillName, cooldown = 2, cost = 0, class = nil, anytime = false, duration = 1.5 }
			end
			local cooldown = entry:FindFirstChild('Cooldown')
			local cost = entry:FindFirstChild('Cost')
			local classVal = entry:FindFirstChild('Class')
			local anytime = entry:FindFirstChild('Anytime') ~= nil
			local duration = entry:FindFirstChild('Duration')
				or entry:FindFirstChild('Length')
				or entry:FindFirstChild('ActiveTime')
			local durationSec = (duration and typeof(duration.Value) == 'number' and duration.Value > 0)
				and duration.Value
				or 1.5
			return {
				name = skillName,
				cooldown = (cooldown and typeof(cooldown.Value) == 'number') and cooldown.Value or 2,
				cost = (cost and typeof(cost.Value) == 'number') and cost.Value or 0,
				class = classVal and normalizeWeaponClass(classVal.Value) or nil,
				anytime = anytime,
				duration = durationSec,
			}
		end

		-- Anim mute was connecting AnimationPlayed every cast and hitching — leave no-op.
		local muteSkillAnimations = function(_durationSec) end

		local heldClassCache, heldClassCacheAt = nil, 0
		local getEquippedWeaponClassesCached = function()
			local now = os.clock()
			if heldClassCache and (now - heldClassCacheAt) < 0.75 then
				return heldClassCache
			end
			heldClassCache = getEquippedWeaponClasses()
			heldClassCacheAt = now
			return heldClassCache
		end

		local SKIP_UTILITY_SKILLS = {
			Block = true,
			Roll = true,
			Sprint = true,
			['Realm Judgement'] = true,
			['Realm Banishment'] = true,
			['Meteor Shot'] = true,
		}

		local FORCE_ATTACK_SKILLS = {
			['Summon Pistol'] = true,
			['Pistol Summon'] = true,
		}

		local getPlayerLevel = function()
			local level = 1
			pcall(function()
				local profile = getLiveProfile()
				local exp = profile and profile:FindFirstChild('Stats') and profile.Stats:FindFirstChild('Exp')
				if exp and typeof(exp.Value) == 'number' then
					level = math.floor(exp.Value ^ (1 / 3))
				end
			end)
			return level
		end

		local skillPassesUnlock = function(skillName, entry, mySkills, level)
			if not entry then
				return mySkills == nil or mySkills:FindFirstChild(skillName) ~= nil
			end
			local needLevel = entry:FindFirstChild('Level')
			if needLevel and typeof(needLevel.Value) == 'number' and level < needLevel.Value then
				return false
			end
			local unlock = entry:FindFirstChild('Unlock')
			if unlock and mySkills and not mySkills:FindFirstChild(skillName) then
				return false
			end
			return true
		end

		-- Weapon-class combat skills only (CTF, smash, etc.). Support buffs go in the other list.
		local getAvailableSkills = function()
			local names = {}
			local seen = {}
			local held = getEquippedWeaponClasses()
			local hasHeld = next(held) ~= nil
			local level = getPlayerLevel()
			local mySkills = getLiveProfile() and getLiveProfile():FindFirstChild('Skills')
			local skillsDb = getSkillDatabase()

			local tryAdd = function(skillName)
				if seen[skillName] or SKIP_UTILITY_SKILLS[skillName] then
					return
				end
				local entry = skillsDb and skillsDb:FindFirstChild(skillName)
				if FORCE_ATTACK_SKILLS[skillName] then
					if mySkills and not mySkills:FindFirstChild(skillName) then
						return
					end
					if not skillPassesUnlock(skillName, entry, mySkills, level) then
						return
					end
					seen[skillName] = true
					names[#names + 1] = skillName
					return
				end
				local info = getSkillInfo(skillName)
				if info.anytime or not info.class then
					return
				end
				if not skillPassesUnlock(skillName, entry, mySkills, level) then
					return
				end
				if not hasHeld or not held[info.class] then
					return
				end
				seen[skillName] = true
				names[#names + 1] = skillName
			end

			if skillsDb then
				for _, entry in ipairs(skillsDb:GetChildren()) do
					tryAdd(entry.Name)
				end
			end

			local pg = LocalPlayer:FindFirstChild('PlayerGui')
			local list = pg
				and pg:FindFirstChild('CardinalUI')
				and pg.CardinalUI:FindFirstChild('PlayerUI')
				and pg.CardinalUI.PlayerUI:FindFirstChild('MainFrame')
				and pg.CardinalUI.PlayerUI.MainFrame:FindFirstChild('TabFrames')
				and pg.CardinalUI.PlayerUI.MainFrame.TabFrames:FindFirstChild('Skills')
				and pg.CardinalUI.PlayerUI.MainFrame.TabFrames.Skills:FindFirstChild('List')
			if list then
				for _, btn in ipairs(list:GetChildren()) do
					if btn:IsA('GuiButton') or btn:IsA('Frame') then
						if btn.Name == 'UIGridLayout' or btn.Name == 'UIListLayout' then
							continue
						end
						local frame = btn:FindFirstChild('Frame')
						local label = (frame and frame:FindFirstChild('Label')) or btn:FindFirstChild('Label', true)
						local locked = label
							and label:IsA('TextLabel')
							and type(label.Text) == 'string'
							and label.Text ~= ''
							and string.find(label.Text, 'Level', 1, true) ~= nil
						if not locked then
							tryAdd(btn.Name)
						end
					end
				end
			end

			for forceName in pairs(FORCE_ATTACK_SKILLS) do
				tryAdd(forceName)
			end

			table.sort(names)
			table.insert(names, 1, '(none)')
			return names
		end

		-- Anytime / support buffs (Cursed Enhancement, etc.).
		local getAvailableSupportSkills = function()
			local names = { '(none)' }
			local seen = { ['(none)'] = true }
			local level = getPlayerLevel()
			local mySkills = getLiveProfile() and getLiveProfile():FindFirstChild('Skills')
			local skillsDb = getSkillDatabase()

			local tryAdd = function(skillName)
				if seen[skillName] or SKIP_UTILITY_SKILLS[skillName] or FORCE_ATTACK_SKILLS[skillName] then
					return
				end
				local info = getSkillInfo(skillName)
				if not info.anytime then
					return
				end
				local entry = skillsDb and skillsDb:FindFirstChild(skillName)
				if mySkills and not mySkills:FindFirstChild(skillName) then
					return
				end
				if not skillPassesUnlock(skillName, entry, mySkills, level) then
					return
				end
				seen[skillName] = true
				names[#names + 1] = skillName
			end

			if mySkills then
				for _, owned in ipairs(mySkills:GetChildren()) do
					tryAdd(owned.Name)
				end
			end
			if skillsDb then
				for _, entry in ipairs(skillsDb:GetChildren()) do
					if entry:FindFirstChild('Anytime') then
						tryAdd(entry.Name)
					end
				end
			end

			table.sort(names, function(a, b)
				if a == '(none)' then
					return true
				end
				if b == '(none)' then
					return false
				end
				return a < b
			end)
			return names
		end

		local flattenOptionValue = function(value)
			if value == nil then
				return nil
			end
			if type(value) == 'table' then
				if value[1] ~= nil then
					return flattenOptionValue(value[1])
				end
				for k, on in pairs(value) do
					if on == true then
						return tostring(k)
					end
				end
				if value.value ~= nil then
					return flattenOptionValue(value.value)
				end
				return nil
			end
			local s = tostring(value)
			if s == '' or string.sub(s, 1, 6) == 'table:' then
				return nil
			end
			return s
		end
		getgenv().SB2FlattenOptionValue = flattenOptionValue

		local refreshDropdownValues = function(option, values, invalidPlaceholder)
			if not option or not option.SetValues then
				return
			end
			local cur = flattenOptionValue(option.Value)
			local keep = cur
			if (not keep or keep == '(none)') and type(getgenv().SB2LastCombatOptions) == 'table' then
				if option == Options.SkillName then
					keep = getgenv().SB2LastCombatOptions.SkillName
				elseif option == Options.SupportSkillName then
					keep = getgenv().SB2LastCombatOptions.SupportSkillName
				end
			end
			local nextValues = {}
			local seen = {}
			for _, v in ipairs(values or {}) do
				if v and not seen[v] then
					seen[v] = true
					nextValues[#nextValues + 1] = v
				end
			end
			-- Never drop a real selected/saved skill just because the weapon list rebuilt.
			if keep and keep ~= '' and keep ~= '(none)' and not seen[keep] then
				nextValues[#nextValues + 1] = keep
				seen[keep] = true
			end
			pcall(function()
				option:SetValues(nextValues)
			end)
			if keep and keep ~= '' then
				pcall(function()
					option:SetValue(keep)
				end)
				return
			end
			if invalidPlaceholder and table.find(nextValues, invalidPlaceholder) then
				pcall(function()
					option:SetValue(invalidPlaceholder)
				end)
			elseif nextValues[1] then
				pcall(function()
					option:SetValue(nextValues[1])
				end)
			end
		end

		-- Forward decls: preferWeaponCombatSkill runs after SaveManager and calls these.
		local getSelectedSkillName
		local preferWeaponCombatSkill

		-- Pistol is a one-shot projectile. Prefer a held-weapon skill (Downward Smash etc.)
		-- so AutoSkill opens a real DealDamage/Attack window instead of only the bullet.
		preferWeaponCombatSkill = function(force)
			-- Never stomp a profile-restored skill while SaveManager is applying.
			if getgenv().SB2ConfigLoading then
				return getSelectedSkillName()
			end
			-- User/profile pick wins — do not replace pistol / (none) / CTF after that.
			if getgenv().SB2HonorSavedCombatSkill or getgenv().SB2UserPickedCombatSkill then
				return getSelectedSkillName()
			end
			local values = getAvailableSkills()
			local opt = Options.SkillName
			if type(opt) ~= 'table' then
				return nil
			end
			local cur = getSelectedSkillName()
			-- Keep any valid held-weapon skill (never stomp user's CTF/smash pick on load).
			if cur and not FORCE_ATTACK_SKILLS[cur] then
				local info = getSkillInfo(cur)
				if info.class and not info.anytime then
					local held = getEquippedWeaponClassesCached()
					if held[info.class] then
						return cur
					end
				end
			end
			-- nil / pistol / wrong-class → pick Downward Smash or first weapon skill.
			local pick = nil
			for _, name in ipairs(values) do
				if name ~= '(none)' and not FORCE_ATTACK_SKILLS[name] then
					if name == 'Downward Smash' then
						pick = name
						break
					end
					if not pick then
						pick = name
					end
				end
			end
			if pick and pick ~= cur then
				pcall(function()
					opt:SetValue(pick)
				end)
			end
			return pick or cur
		end
		getgenv().SB2PreferWeaponCombatSkill = preferWeaponCombatSkill

		local refreshSkillDropdown = function(notify)
			local values = getAvailableSkills()
			local supportValues = getAvailableSupportSkills()
			refreshDropdownValues(Options.SkillName, values, '(none)')
			refreshDropdownValues(Options.SupportSkillName, supportValues, '(none)')
			if not getgenv().SB2HonorSavedCombatSkill and not getgenv().SB2UserPickedCombatSkill then
				preferWeaponCombatSkill(false)
			end
			if notify then
				local held = getEquippedWeaponClasses()
				local heldList = {}
				for c in pairs(held) do
					heldList[#heldList + 1] = c
				end
				table.sort(heldList)
				local heldStr = #heldList > 0 and table.concat(heldList, ', ') or 'none'
				Library:Notify(('Combat %d | Support %d (%s)'):format(#values, math.max(0, #supportValues - 1), heldStr))
			end
			return values
		end

		local isSkillReady = function(skillName)
			local untilT = getgenv().SB2SkillCdUntil
			if type(untilT) == 'table' and type(untilT[skillName]) == 'number' then
				return time() >= untilT[skillName]
			end
			return true
		end

		local markSkillUsed = function(skillName, cooldownSec)
			if type(getgenv().SB2SkillCdUntil) ~= 'table' then
				getgenv().SB2SkillCdUntil = {}
			end
			local cd = cooldownSec or 2
			if cd < 0.5 then
				cd = 0.5
			end
			getgenv().SB2SkillCdUntil[skillName] = time() + cd
		end

		local getPlayerStamina = function()
			local char = LocalPlayer.Character
				or (workspace:FindFirstChild('Characters') and workspace.Characters:FindFirstChild(LocalPlayer.Name))
			local entity = char and char:FindFirstChild('Entity')
			local stamina = entity and entity:FindFirstChild('Stamina')
			if stamina and typeof(stamina.Value) == 'number' then
				return stamina.Value
			end
			return 0
		end

		getSelectedSkillName = function()
			local opt = Options.SkillName
			if type(opt) ~= 'table' then
				return nil
			end
			local ok, raw = pcall(function()
				return opt.Value
			end)
			if not ok then
				return nil
			end
			local value = flattenOptionValue(raw)
			if value == nil or value == '' or value == '(none)' or value == '(none for held weapon)' then
				return nil
			end
			return value
		end

		local getSelectedSupportSkillName = function()
			local opt = Options.SupportSkillName
			if type(opt) ~= 'table' then
				return nil
			end
			local ok, raw = pcall(function()
				return opt.Value
			end)
			if not ok then
				return nil
			end
			local value = flattenOptionValue(raw)
			if value == nil or value == '' or value == '(none)' then
				return nil
			end
			return value
		end

		local function readOptionSkill(optName)
			local opt = Options[optName]
			if type(opt) ~= 'table' then
				return nil
			end
			local ok, raw = pcall(function()
				return opt.Value
			end)
			if not ok then
				return nil
			end
			local value = flattenOptionValue(raw)
			if value == nil or value == '' or value == '(none)' or value == '(none for held weapon)' then
				return nil
			end
			return value
		end

		local function usingEventFarmSkills()
			return isToggleOn('DiveFarm')
		end

		local function getSelectedFarmSkillName()
			return readOptionSkill('FarmSkillName')
		end

		local function getSelectedFarmSupportSkillName()
			return readOptionSkill('FarmSupportSkillName')
		end

		local function getSelectedFarmHealSkillName()
			return readOptionSkill('FarmHealSkillName')
		end

		local function getSelectedFarmMendSkillName()
			return readOptionSkill('FarmMendSkillName')
		end

		local function getActiveWeaponSkillName()
			if usingEventFarmSkills() then
				return getSelectedFarmSkillName()
			end
			return getSelectedSkillName()
		end

		local function getActiveSupportSkillName()
			if usingEventFarmSkills() then
				return getSelectedFarmSupportSkillName()
			end
			return getSelectedSupportSkillName()
		end

		local HEAL_SKILL_PRIORITY = {
			'Heal',
			'Mending Spirit',
		}
		local BURST_HEAL_NAME = 'Heal'
		local MEND_HEAL_NAME = 'Mending Spirit'
		local MEND_HOLD_FALLBACK = 8
		local MEND_AOE_STAY = 10

		local function getAvailableHealSkills()
			local names = { '(none)' }
			local seen = { ['(none)'] = true }
			local mySkills = getLiveProfile() and getLiveProfile():FindFirstChild('Skills')
			local function tryAdd(skillName)
				if seen[skillName] then
					return
				end
				if mySkills and not mySkills:FindFirstChild(skillName) then
					return
				end
				seen[skillName] = true
				names[#names + 1] = skillName
			end
			for _, skillName in ipairs(HEAL_SKILL_PRIORITY) do
				tryAdd(skillName)
			end
			local skillsDb = getSkillDatabase()
			if skillsDb then
				for _, entry in ipairs(skillsDb:GetChildren()) do
					local lower = string.lower(entry.Name)
					if string.find(lower, 'heal', 1, true)
						or string.find(lower, 'mending', 1, true)
						or string.find(lower, 'spirit', 1, true)
					then
						tryAdd(entry.Name)
					end
				end
			end
			table.sort(names, function(a, b)
				if a == '(none)' then
					return true
				end
				if b == '(none)' then
					return false
				end
				return a < b
			end)
			return names
		end

		-- Never burn CE/CTF while map is hollow or Mobs folder is empty/missing.
		local workspaceHasMobs = function()
			local mobs = workspace:FindFirstChild('Mobs')
			if not mobs or mobs.Parent ~= workspace then
				return false
			end
			return #mobs:GetChildren() > 0
		end

		-- https://swordburst2.fandom.com/wiki/Category:Boss (+ aliases for matching only)
		local BOSS_NAME_LIST = {
			'Aeganatos, The Sunken Sovereign',
			'Alpha Killer Bunny',
			'Atheon',
			'Azeis, Spirit of the Blossom',
			'Basileus YanSafe',
			'Borik the BeeKeeper',
			'Corrupted Atheon',
			'Da, the Demeanor',
			'Duality Reaper',
			'Formaug the Jungle Giant',
			'Grim the Overseer',
			'Headless Horseman',
			'Irath the Lion',
			'Jolrock the Snow Protecter',
			'Ka, the Mischief',
			'Limor the Devourer',
			'Mortis the Flaming Sear',
			'Orc King',
			"Ra'thae the Ice King",
			'Ra, the Enlightener',
			'Radioactive Experiment',
			'Rahjin the Thief King',
			'Ramseis, Chef of Souls',
			'Rekindled Unborn',
			"Sa'jun (Catacombs)",
			"Sa'jun the Centurian Chieftain",
			'Saurus, the All-Seeing',
			'Saurus the All-Seeing',
			'Smashroom the Mushroom Behemoth',
			'Suspended Unborn',
			'Terror Incarnate',
			'Terror Incarnātus, The Eldritch Unbound',
			'Terror Incarnatus, The Eldritch Unbound',
			'Vyroth, The Frostflame',
			'Wa, the Curious',
			'Warlord',
			'Wintula the Punisher',
			'Za, the Eldest',
		}
		local function normBossKey(s)
			s = string.lower(tostring(s or ''))
			s = string.gsub(s, '[%p%s]+', '')
			return s
		end
		local BOSS_KEYS = {}
		for _, name in ipairs(BOSS_NAME_LIST) do
			local key = normBossKey(name)
			if #key >= 5 then
				BOSS_KEYS[key] = true
			end
		end

		local entityFlagOn = function(entity, flagName)
			if not entity then
				return false
			end
			if entity:GetAttribute(flagName) == true then
				return true
			end
			local flag = entity:FindFirstChild(flagName)
			if not flag then
				return false
			end
			if flag:IsA('BoolValue') then
				return flag.Value == true
			end
			if flag:IsA('NumberValue') or flag:IsA('IntValue') then
				return flag.Value > 0
			end
			-- Presence of a Folder/Configuration named Boss counts.
			return true
		end

		local isBossMob = function(mob)
			if not mob or not mob.Parent then
				return false
			end
			-- Never treat chests / drops as bosses.
			local name = tostring(mob.Name)
			local lower = string.lower(name)
			if string.find(lower, 'chest', 1, true) or string.find(lower, 'drop', 1, true) then
				return false
			end
			if string.find(lower, 'boss', 1, true) then
				return true
			end
			local key = normBossKey(name)
			if BOSS_KEYS[key] then
				return true
			end
			-- Only: full wiki boss name appears inside the mob name (not the reverse —
			-- reverse matched random mobs like "Giant"/"King" inside boss titles).
			for bossKey in pairs(BOSS_KEYS) do
				if #bossKey >= 8 and string.find(key, bossKey, 1, true) then
					return true
				end
			end
			local entity = mob:FindFirstChild('Entity')
			if entityFlagOn(entity, 'Boss') or entityFlagOn(entity, 'Miniboss') then
				return true
			end
			local hitLives = entity and entity:FindFirstChild('HitLives')
			if hitLives and typeof(hitLives.Value) == 'number' and hitLives.Value > 1 then
				return true
			end
			return false
		end

		local function mobHitLives(mob)
			local entity = mob and mob:FindFirstChild('Entity')
			local hitLives = entity and entity:FindFirstChild('HitLives')
			if hitLives and typeof(hitLives.Value) == 'number' then
				return hitLives.Value
			end
			return nil
		end

		local function mobUsesHitLives(mob)
			local lives = mobHitLives(mob)
			return lives ~= nil and lives > 0
		end

		local function mobHasSpecialAttribute(mob)
			local entity = mob and mob:FindFirstChild('Entity')
			if not entity then
				return false
			end
			local okAttr, attrs = pcall(function()
				return entity:GetAttributes()
			end)
			if okAttr and type(attrs) == 'table' then
				for name in pairs(attrs) do
					local n = string.lower(tostring(name))
					if string.find(n, 'elite', 1, true)
						or string.find(n, 'hard', 1, true)
						or string.find(n, 'element', 1, true)
						or string.find(n, 'spawn', 1, true)
						or string.find(n, 'poison', 1, true)
						or string.find(n, 'fire', 1, true)
						or string.find(n, 'dark', 1, true)
					then
						return true
					end
				end
			end
			for _, child in ipairs(entity:GetChildren()) do
				local n = string.lower(child.Name)
				if string.find(n, 'poison', 1, true)
					or string.find(n, 'fire', 1, true)
					or string.find(n, 'elite', 1, true)
					or string.find(n, 'dark', 1, true)
					or string.find(n, 'buff', 1, true)
					or string.find(n, 'attribute', 1, true)
				then
					return true
				end
			end
			return false
		end

		-- Combo dropdown only: unique names for this PlaceId. Aliases stay in BOSS_NAME_LIST for matching.
		local FLOOR_COMBO_BOSSES = {
			[542351431] = { -- F1 Virhst Woodlands
				'Rahjin the Thief King',
				'Dire Wolf',
				'Ruined Kobold Lord',
			},
			[548231754] = { -- F2 Redveil Grove
				'Borik the BeeKeeper',
				'Pearl Guardian',
			},
			[555980327] = { -- F3 Avalanche Expanse
				"Ra'thae the Ice King",
				'Jolrock the Snow Protecter',
			},
			[572487908] = { -- F4 Hidden Wilds
				'Irath the Lion',
				'Rotling',
			},
			[580239979] = { -- F5 Desolate Dunes
				"Sa'jun the Centurian Chieftain",
				'Fire Scorpion',
			},
			[566212942] = {}, -- F6 Helmfirth (town)
			[582198062] = { -- F7 Entoloma Gloomlands
				'Smashroom the Mushroom Behemoth',
				'Frogazoid',
			},
			[548878321] = { -- F8 Blooming Plateau
				'Formaug the Jungle Giant',
				'Hippogriff',
			},
			[573267292] = { -- F9 Va' Rok
				'Mortis the Flaming Sear',
				'Polyserpant',
				'Gargoyle Reaper',
			},
			[2659143505] = { -- F10 Transylvania
				'Grim the Overseer',
				'Baal, The Tormentor',
			},
			[5287433115] = { -- F11 Hypersiddia
				'Saurus, the All-Seeing',
				'Duality Reaper',
				'Za, the Eldest',
				'Wa, the Curious',
				'Ra, the Enlightener',
				'Da, the Demeanor',
				'Ka, the Mischief',
			},
			[6144637080] = { -- F12 Sector-235
				'Suspended Unborn',
				'Limor the Devourer',
				'Radioactive Experiment',
				'Rekindled Unborn',
				'Warlord',
			},
			[13965775911] = { -- Atheon realm
				'Atheon',
				'Corrupted Atheon',
			},
			[16810524216] = { -- Eternal Garden
				'Azeis, Spirit of the Blossom',
			},
			[18729767954] = { -- Glutton's Lair
				'Ramseis, Chef of Souls',
			},
			[134019705603409] = { -- Atlantis
				'Aeganatos, The Sunken Sovereign',
			},
			[11331145451] = { -- Spooky Hollow
				'Headless Horseman',
				'Terror Incarnate',
			},
			[15716179871] = { -- Frosty Fields
				'Vyroth, The Frostflame',
			},
			[13051622258] = { -- Egg Realm
				'Alpha Killer Bunny',
			},
		}

		local function uniqueBossNames(names)
			local out, seen = {}, {}
			for _, name in ipairs(names or {}) do
				local key = normBossKey(name)
				if key ~= '' and not seen[key] then
					seen[key] = true
					out[#out + 1] = name
				end
			end
			table.sort(out)
			return out
		end

		local function listFloorComboBosses()
			local pid = game.PlaceId
			if FLOOR_COMBO_BOSSES[pid] ~= nil then
				local names = uniqueBossNames(FLOOR_COMBO_BOSSES[pid])
				if #names > 0 then
					return names
				end
				return { '(none)' }
			end
			local live = {}
			local mobs = workspace:FindFirstChild('Mobs')
			if mobs then
				for _, mob in ipairs(mobs:GetChildren()) do
					if isBossMob(mob) then
						live[#live + 1] = mob.Name
					end
				end
			end
			local names = uniqueBossNames(live)
			if #names == 0 then
				return { '(none)' }
			end
			return names
		end

		local function pickDefaultComboBoss(values)
			for _, name in ipairs({ 'Saurus, the All-Seeing', 'Saurus the All-Seeing' }) do
				if table.find(values, name) then
					return name
				end
			end
			return values[1]
		end

		local function refreshFloorBossDropdown(notify)
			local names = listFloorComboBosses()
			local opt = Options.BossComboTarget
			if not opt or not opt.SetValues then
				return names
			end
			pcall(function()
				opt:SetValues(names)
			end)
			local cur
			pcall(function()
				cur = opt.Value
			end)
			if not cur or not table.find(names, cur) then
				pcall(function()
					opt:SetValue(pickDefaultComboBoss(names))
				end)
			end
			if notify then
				Library:Notify(('Floor bosses: %d'):format(#names))
			end
			return names
		end

		local anyBossPresent = function()
			local mobs = workspace:FindFirstChild('Mobs')
			if not mobs then
				return false
			end
			for _, mob in ipairs(mobs:GetChildren()) do
				if not isDeadMob(mob) and isBossMob(mob) then
					return true
				end
			end
			return false
		end

		local function anyHitLivesPresent()
			local mobs = workspace:FindFirstChild('Mobs')
			if not mobs then
				return false
			end
			for _, mob in ipairs(mobs:GetChildren()) do
				if not isDeadMob(mob) and mobUsesHitLives(mob) then
					return true
				end
			end
			return false
		end

		local function wantHitLivesRush()
			if not anyHitLivesPresent() then
				return false
			end
			if isToggleOn('DiveFarm') then
				return true
			end
			local toggle = Toggles.HitLivesRush
			if type(toggle) ~= 'table' then
				return true
			end
			return isToggleOn('HitLivesRush')
		end

		-- Default ON if toggle missing (old session) — do not burn CE on trash mobs.
		local wantSupportBossOnly = function()
			local toggle = Toggles.SupportBossOnly
			if type(toggle) ~= 'table' then
				return true
			end
			local ok, value = pcall(function()
				return toggle.Value
			end)
			if not ok then
				return true
			end
			return value == true
		end

		local wantSupportSkill = function()
			local toggle = Toggles.SupportSkill
			if type(toggle) ~= 'table' then
				-- No toggle yet: allow if a support skill is selected.
				return getSelectedSupportSkillName() ~= nil
			end
			return isToggleOn('SupportSkill')
		end

		local fireUseSkill = function(skillName, info, opts)
			opts = opts or {}
			if not opts.ignoreMobsGate and not workspaceHasMobs() then
				return false
			end
			-- Pistol only from the auto-attack loop after a real-CFrame 3-stud check.
			if FORCE_ATTACK_SKILLS[skillName] and not opts.allowPistol then
				return false
			end
			if not CombatEvent then
				CombatEvent = ReplicatedStorage:FindFirstChild('Event')
			end
			if not CombatEvent then
				return false
			end
			local nowCast = os.clock()
			if not opts.ignoreGap and (nowCast - lastAnySkillCastAt) < SKILL_CAST_GAP then
				return false
			end
			local stamBefore = getPlayerStamina()
			if stamBefore < (info.cost or 0) then
				return false
			end
			if not isSkillReady(skillName) then
				return false
			end

			local hrp = getMyBringPart()
				or (LocalPlayer.Character and LocalPlayer.Character:FindFirstChild('HumanoidRootPart'))
			local look = (hrp and hrp.CFrame.LookVector) or Vector3.new(0, 0, -1)
			local flat = Vector3.new(look.X, 0, look.Z)
			local dir = flat.Magnitude > 0.05 and flat.Unit or Vector3.new(0, 0, -1)

			lastAnySkillCastAt = nowCast
			local cd = info.cooldown or 2
			if FORCE_ATTACK_SKILLS[skillName] then
				cd = math.max(cd, 4)
			end
			markSkillUsed(skillName, cd)
			getgenv().SB2CombatProbe = getgenv().SB2CombatProbe or {}
			getgenv().SB2CombatProbe.lastSkill = skillName
			getgenv().SB2CombatProbe.lastSkillAt = os.clock()
			getgenv().SB2CombatProbe.lastSkillDir = { dir.X, dir.Y, dir.Z }

			local fireOk = pcall(function()
				CombatEvent:FireServer('Skills', {
					'UseSkill',
					skillName,
					{ Direction = dir },
				})
			end)
			if not fireOk then
				if type(getgenv().SB2SkillCdUntil) == 'table' then
					getgenv().SB2SkillCdUntil[skillName] = nil
				end
				return false
			end
			return true
		end

		-- Support dropdown (CE etc.) — always outranks weapon UseSkill when ready.
		local getSupportCastTarget = function()
			if not wantSupportSkill() then
				return nil, nil
			end
			if not workspaceHasMobs() then
				return nil, nil
			end
			if wantHitLivesRush() then
				local mySkills = getLiveProfile() and getLiveProfile():FindFirstChild('Skills')
				local ceName = getActiveSupportSkillName() or 'Cursed Enhancement'
				if ceName == 'Cursed Enhancement' or (mySkills and mySkills:FindFirstChild('Cursed Enhancement')) then
					ceName = 'Cursed Enhancement'
					local ceInfo = getSkillInfo(ceName)
					if ceInfo.anytime
						and isSkillReady(ceName)
						and getPlayerStamina() >= (ceInfo.cost or 0)
					then
						return ceName, ceInfo
					end
				end
			end
			if wantSupportBossOnly() and not anyBossPresent() and not wantHitLivesRush() and not usingEventFarmSkills() then
				return nil, nil
			end
			local skillName = getActiveSupportSkillName()
			if not skillName or SKIP_UTILITY_SKILLS[skillName] then
				return nil, nil
			end
			local info = getSkillInfo(skillName)
			if not info.anytime then
				return nil, nil
			end
			local mySkills = getLiveProfile() and getLiveProfile():FindFirstChild('Skills')
			if mySkills and not mySkills:FindFirstChild(skillName) then
				return nil, nil
			end
			if not isSkillReady(skillName) then
				return nil, nil
			end
			local stam = getPlayerStamina()
			if stam < (info.cost or 0) then
				return nil, nil
			end
			return skillName, info
		end

		local castSelectedSupportSkill = function()
			local skillName, info = getSupportCastTarget()
			if not skillName then
				return false
			end
			return fireUseSkill(skillName, info, { muteFor = 2.0, silentFail = true }) == true
		end

		local ensureSkillWindow = function()
			if getgenv().SB2BossComboLock then
				local name = getgenv().SB2SkillActiveName
				local untilT = getgenv().SB2SkillActiveUntil
				if type(name) == 'string'
					and type(untilT) == 'number'
					and untilT > time()
				then
					return name
				end
				return nil
			end
			if not isToggleOn('AutoSkill') then
				return nil
			end
			if not workspaceHasMobs() then
				getgenv().SB2SkillActiveUntil = 0
				getgenv().SB2SkillActiveName = nil
				return nil
			end

			local skillName = getActiveWeaponSkillName()
			local function activeWeaponTag()
				if not skillName
					or skillName == 'Block'
					or skillName == 'Roll'
					or skillName == 'Sprint'
					or skillName == 'Realm Judgement'
					or skillName == 'Realm Banishment'
					or skillName == 'Meteor Shot'
				then
					return nil
				end
				local now = time()
				if getgenv().SB2SkillActiveName == skillName
					and type(getgenv().SB2SkillActiveUntil) == 'number'
					and getgenv().SB2SkillActiveUntil > now
				then
					return skillName
				end
				return nil
			end

			-- Support first: if CE/buff is ready, cast it and skip weapon UseSkill this tick.
			local supportName = getSupportCastTarget()
			if supportName then
				pcall(castSelectedSupportSkill)
				return activeWeaponTag()
			end

			if not skillName
				or skillName == 'Block'
				or skillName == 'Roll'
				or skillName == 'Sprint'
				or skillName == 'Realm Judgement'
				or skillName == 'Realm Banishment'
				or skillName == 'Meteor Shot'
			then
				return nil
			end

			local info = getSkillInfo(skillName)
			local forced = FORCE_ATTACK_SKILLS[skillName] == true
			-- Combat dropdown is weapon-class only, except forced shots (Summon Pistol).
			-- Pistol is Anytime / no class — still UseSkill + tag DealDamage like CTF.
			if not forced then
				if info.anytime or not info.class then
					return nil
				end
				local held = getEquippedWeaponClassesCached()
				if not held[info.class] then
					return nil
				end
			end

			-- Summon Pistol is projectile-only — never open a CTF-style tag window for it.
			if forced then
				return nil
			end

			local tagged = activeWeaponTag()
			if tagged then
				return tagged
			end

			if not isSkillReady(skillName) then
				return nil
			end
			if getgenv().SB2SkillCastLock then
				return nil
			end

			getgenv().SB2SkillCastLock = true
			local now = time()
			getgenv().SB2SkillActiveName = skillName
			getgenv().SB2SkillActiveUntil = now + 1.0

			local ok = fireUseSkill(skillName, info, { muteFor = 1.35 })
			task.defer(function()
				task.wait(0.15)
				getgenv().SB2SkillCastLock = false
			end)
			if not ok then
				getgenv().SB2SkillActiveUntil = 0
				getgenv().SB2SkillActiveName = nil
				return nil
			end
			return skillName
		end

		local fireMobAttack = function(mob, attackName)
			if not mob or not mob.Parent or shouldSkipMob(mob) then
				return false
			end

			local hit = false
			-- Neuublue / AutoFarm: tag the skill name, then also send a basic hit.
			-- Pistol (Anytime) can reject a skill-only tag and do 0 damage.
			if RequiredServices
				and RequiredServices.Combat
				and type(RequiredServices.Combat.DealDamage) == 'function'
			then
				if attackName then
					local okSkill = pcall(RequiredServices.Combat.DealDamage, mob, attackName)
					if okSkill then
						hit = true
					end
				end
				local okBasic = pcall(RequiredServices.Combat.DealDamage, mob, nil)
				if okBasic then
					hit = true
				end
			end

			if not CombatEvent then
				CombatEvent = ReplicatedStorage:FindFirstChild('Event')
			end
			-- Neuublue remote: Event Combat + RPCKey + Attack key '2'.
			if CombatEvent then
				if not combatState.rpcReady then
					-- Don't InvokeServer from the attack hot path — one-shot boot fetch only.
				elseif type(combatState.rpcKey) == 'table' then
					if attackName then
						local ok = pcall(function()
							CombatEvent:FireServer('Combat', combatState.rpcKey, {
								'Attack',
								mob,
								attackName,
								takeCombatKey(),
							})
						end)
						if ok then
							hit = true
						end
					end
					local ok2 = pcall(function()
						CombatEvent:FireServer('Combat', combatState.rpcKey, {
							'Attack',
							mob,
							nil,
							takeCombatKey(),
						})
					end)
					if ok2 then
						hit = true
					end
				end
			end

			if hit then
				local probe = getgenv().SB2CombatProbe or {}
				probe.lastHitMob = mob.Name
				probe.lastHitAt = os.clock()
				probe.lastHitName = attackName
				probe.hits = (probe.hits or 0) + 1
				getgenv().SB2CombatProbe = probe
			end

			return hit
		end

		local mobRealCF = getgenv().SB2MobRealCF
		if type(mobRealCF) ~= 'table' then
			mobRealCF = {}
			getgenv().SB2MobRealCF = mobRealCF
		end

		local countNearMobs = function(origin, radius)
			local mobsRoot = workspace:FindFirstChild('Mobs')
			if not mobsRoot then
				return 0, 0
			end
			local near, alive = 0, 0
			local rSq = radius * radius
			for _, mob in mobsRoot:GetChildren() do
				if isDeadMob(mob) then
					continue
				end
				local root = getMobRoot(mob)
				if not root then
					continue
				end
				alive += 1
				local delta = root.Position - origin
				if delta:Dot(delta) <= rSq then
					near += 1
				end
			end
			return near, alive
		end

		local looksClientStacked = function(origin)
			local near, alive = countNearMobs(origin, 30)
			return alive >= 6 and near >= math.max(5, math.floor(alive * 0.45))
		end

		local cacheMobRealPositions = function(origin)
			local mobsRoot = workspace:FindFirstChild('Mobs')
			if not mobsRoot or not origin then
				return
			end
			local stacked = looksClientStacked(origin)
			for _, mob in mobsRoot:GetChildren() do
				if isDeadMob(mob) then
					mobRealCF[mob] = nil
					continue
				end
				local root = getMobRoot(mob)
				if not root then
					continue
				end
				local dist = (root.Position - origin).Magnitude
				if dist > 45 or (not stacked and dist > 12) then
					mobRealCF[mob] = root.CFrame
				elseif not mobRealCF[mob] and not stacked then
					mobRealCF[mob] = root.CFrame
				end
			end
		end

		local getMobAttackCFrame = function(mob, root, origin)
			local cached = mobRealCF[mob]
			if cached and looksClientStacked(origin) then
				return cached
			end
			if cached then
				local clientDist = (root.Position - origin).Magnitude
				local cachedDist = (cached.Position - origin).Magnitude
				if clientDist < 30 and cachedDist > 45 then
					return cached
				end
			end
			return root.CFrame
		end

		-- Pistol cast when a mob is close (not full 200-stud killaura).
		local PISTOL_CAST_RANGE = 30
		local pistolInCastRange = function(origin)
			local mobsRoot = workspace:FindFirstChild('Mobs')
			if not mobsRoot or not origin then
				return false
			end
			local rangeSq = PISTOL_CAST_RANGE * PISTOL_CAST_RANGE
			for _, mob in mobsRoot:GetChildren() do
				if isDeadMob(mob) or shouldSkipMob(mob) then
					continue
				end
				local root = getMobRoot(mob)
				if not root then
					continue
				end
				local atkCF = getMobAttackCFrame(mob, root, origin)
				local dx = atkCF.Position.X - origin.X
				local dz = atkCF.Position.Z - origin.Z
				if (dx * dx + dz * dz) <= rangeSq then
					return true
				end
			end
			return false
		end

		(function()
		local CombatTab = Window:AddTab('Combat', 'swords')
		local CombatBox = CombatTab:AddLeftGroupbox('Combat')
		assert(CombatBox, 'Combat groupbox nil')

		CombatBox:AddToggle('AutoSkill', {
			Text = 'Auto skill damage',
			Default = false,
			Tooltip = 'UseSkill once, then tag DealDamage/Attack with that skill (all streamed mobs) for ~1s.',
		})

		local applyCombatAnchor = function(enabled)
			if enabled and isToggleOn('DiveFarm') then
				enabled = false
			end
			local model = getMyCharacterModel()
			local hrp = model and (model:FindFirstChild('HumanoidRootPart') or model:FindFirstChild('UpperTorso'))
			if not hrp or not hrp:IsA('BasePart') then
				pcall(setAnchorPlayerNoclip, enabled == true)
				return false
			end
			pcall(function()
				if enabled and combatAnchorHolding() then
					hrp.Anchored = false
					return
				end
				if enabled then
					hrp.AssemblyLinearVelocity = Vector3.zero
					hrp.AssemblyAngularVelocity = Vector3.zero
					if not hrp.Anchored then
						hrp.CFrame = hrp.CFrame
						lockReplicationFocus(model)
						pcall(function()
							LocalPlayer:RequestStreamAroundAsync(hrp.Position, 40)
						end)
					end
				end
				hrp.Anchored = enabled == true
			end)
			pcall(setAnchorPlayerNoclip, enabled == true)
			return true
		end

		CombatBox:AddToggle('AutoAttack', { Text = 'Auto attack nearby mobs' }):OnChanged(function(value)
			local prev = getgenv().SB2AutoAttackConn
			if prev then
				pcall(function()
					prev:Disconnect()
				end)
				getgenv().SB2AutoAttackConn = nil
			end

			if not value then
				return
			end

			-- One safe RPCKey fetch if we don't have it yet — never RefillKeys / gc brute.
			task.spawn(function()
				pcall(refreshRpcKey)
			end)
			-- Clear stuck skill lock/CD from old laggy sessions.
			getgenv().SB2SkillCastLock = false
			getgenv().SB2SkillCdUntil = {}
			getgenv().SB2SkillActiveUntil = 0
			getgenv().SB2SkillActiveName = nil
			-- Kill live namecall UseSkill hooks (they blocked skills / added hitch).
			pcall(function()
				if getgenv()._SB2SupportBossOld and getrawmetatable then
					local mt = getrawmetatable(game)
					setreadonly(mt, false)
					mt.__namecall = getgenv()._SB2SupportBossOld
					setreadonly(mt, true)
					getgenv()._SB2SupportBossHook = nil
					getgenv().SB2SupportBossOnlyLive = false
				end
			end)

			local onCooldown = {}
			local lastTick = 0
			getgenv().SB2AutoAttackConn = RunService.Heartbeat:Connect(function()
				if not isToggleOn('AutoAttack') then
					local conn = getgenv().SB2AutoAttackConn
					if conn then
						conn:Disconnect()
						getgenv().SB2AutoAttackConn = nil
					end
					return
				end

				local now = os.clock()
				local hitLivesRush = wantHitLivesRush()
				local tickGap = hitLivesRush and HIT_LIVES_ATTACK_INTERVAL or AUTO_ATTACK_INTERVAL
				if now - lastTick < tickGap then
					return
				end
				lastTick = now

				if not isLocalAlive() then
					return
				end
				local myPart = getMyBringPart()
				local mobsRoot = workspace:FindFirstChild('Mobs')
				if not myPart or not mobsRoot then
					return
				end

				local aaRange = AUTO_ATTACK_RANGE
				local skillRange = SKILL_HIT_RANGE
				local delay = hitLivesRush
						and math.max(
							HIT_LIVES_MIN_DELAY,
							getOptionNumber('HitLivesAttackDelay', HIT_LIVES_ATTACK_DELAY)
						)
					or getOptionNumber('AutoAttackDelay', AUTO_ATTACK_DELAY)
				if hitLivesRush then
					delay = math.max(HIT_LIVES_MIN_DELAY, delay)
				end
				local origin = myPart.Position
				local selectedSkill = getActiveWeaponSkillName()
				local pistolMode = not hitLivesRush and FORCE_ATTACK_SKILLS[selectedSkill] == true
				-- After pistol UseSkill, tag like CTF (wide reach). Before that, stay on killaura.
				local skillWindowOpen = not hitLivesRush
					and isToggleOn('AutoSkill')
					and type(getgenv().SB2SkillActiveUntil) == 'number'
					and getgenv().SB2SkillActiveUntil > time()
				local wantSkillReach = not hitLivesRush
					and isToggleOn('AutoSkill')
					and (skillWindowOpen or (not pistolMode and skillRange >= aaRange))
				local range = wantSkillReach and math.max(aaRange, skillRange) or aaRange
				local rangeSq = range * range
				local attackAllStreamed = range >= 10000

				-- Pistol needs real CFrames even when AutoSkill is tagging all streamed mobs.
				if pistolMode or not attackAllStreamed then
					cacheMobRealPositions(origin)
				end

				-- Hit-lives mobs die by hit count — CE buff + basic swings, no weapon UseSkill.
				local attackName = nil
				if hitLivesRush then
					if isToggleOn('AutoSkill') then
						pcall(castSelectedSupportSkill)
					end
				elseif isToggleOn('AutoSkill') then
					attackName = ensureSkillWindow()
				end

				-- Pistol: UseSkill shot only. Tagging DealDamage with "Summon Pistol" does not
				-- multi-hit like Downward Smash / CTF — that was the "one damage instance" bug.
				if isToggleOn('AutoSkill') and pistolMode and not attackName then
					if pistolInCastRange(origin) then
						local info = getSkillInfo(selectedSkill)
						fireUseSkill(selectedSkill, info, { muteFor = 1.35, allowPistol = true })
					end
				end

				local mobList = {}
				for _, mob in mobsRoot:GetChildren() do
					if isDeadMob(mob) or shouldSkipMob(mob) then
						continue
					end
					local root = getMobRoot(mob)
					if not root then
						continue
					end
					if not attackAllStreamed then
						local atkCF = getMobAttackCFrame(mob, root, origin)
						local dx = atkCF.Position.X - origin.X
						local dz = atkCF.Position.Z - origin.Z
						if (dx * dx + dz * dz) > rangeSq then
							continue
						end
					end
					mobList[#mobList + 1] = {
						mob = mob,
						hitLives = mobUsesHitLives(mob),
						boss = isBossMob(mob),
						special = mobHasSpecialAttribute(mob),
					}
				end
				table.sort(mobList, function(a, b)
					if a.hitLives ~= b.hitLives then
						return a.hitLives
					end
					if a.boss ~= b.boss then
						return a.boss
					end
					if a.special ~= b.special then
						return a.special
					end
					return false
				end)

				local attacked = 0
				for _, entry in ipairs(mobList) do
					local mob = entry.mob
					if attacked >= MAX_ATTACKS_PER_TICK then
						break
					end
					if onCooldown[mob] then
						continue
					end
					if fireMobAttack(mob, attackName) then
						attacked += 1
						onCooldown[mob] = true
						task.delay(delay, function()
							onCooldown[mob] = nil
						end)
					end
				end
			end)
		end)

		CombatBox:AddSlider('AutoAttackDelay', {
			Text = 'Per-mob attack delay',
			Default = AUTO_ATTACK_DELAY,
			Min = 0.05,
			Max = 0.5,
			Rounding = 2,
			Suffix = 's',
			Tooltip = 'Cooldown between hits on the same mob. Normal farming only — hit-lives rush uses its own faster delay.',
		})

		CombatBox:AddSlider('HitLivesAttackDelay', {
			Text = 'Hit-lives attack delay',
			Default = HIT_LIVES_ATTACK_DELAY,
			Min = 0.05,
			Max = 0.2,
			Rounding = 2,
			Suffix = 's',
			Tooltip = '0.05s is about the game attack-speed floor. Lower values usually get ignored server-side.',
		})

		CombatBox:AddToggle('HitLivesRush', {
			Text = 'Hit-lives rush (CE + fast hits)',
			Default = true,
			Tooltip = 'When Entity.HitLives is present, skip weapon UseSkill and spam basic attacks with Cursed Enhancement at max speed. Best for bosses that die by hit count, not raw damage. Auto-on with Event dive.',
		})

		CombatBox:AddToggle('CombatAnchor', {
			Text = 'Anchor',
			Default = false,
			Tooltip = 'Anchors your HumanoidRootPart so dash skills (CTF etc.) cannot yeet you into the void. Brief unanchor after spawn/TP so the server gets your position, then locks. Also turns off collision with other players until Anchor is off.',
		}):OnChanged(function(value)
			local prev = getgenv().SB2CombatAnchorConn
			if prev then
				pcall(function()
					prev:Disconnect()
				end)
				getgenv().SB2CombatAnchorConn = nil
			end
			if not value then
				getgenv().SB2AnchorHoldUntil = 0
				applyCombatAnchor(false)
				return
			end
			holdCombatAnchor(0.5)
			applyCombatAnchor(true)
			-- Re-apply — UseSkill / physics can clear Anchored.
			getgenv().SB2CombatAnchorConn = RunService.Heartbeat:Connect(function()
				if not isToggleOn('CombatAnchor') then
					local conn = getgenv().SB2CombatAnchorConn
					if conn then
						pcall(function()
							conn:Disconnect()
						end)
						getgenv().SB2CombatAnchorConn = nil
					end
					applyCombatAnchor(false)
					return
				end
				local nowA = os.clock()
				if nowA - (getgenv().SB2CombatAnchorTick or 0) < 0.1 then
					return
				end
				getgenv().SB2CombatAnchorTick = nowA
				applyCombatAnchor(true)
			end)
		end)

		-- Event dive: Neuublue-style fly under the mob (noclip + LinearVelocity).
		local DIVE_VERTICAL = -60
		local DIVE_FLY_SPEED = 300
		local DIVE_AURA_RANGE = math.max(40, AUTO_ATTACK_RANGE - 18)
		local DIVE_FLEE_RANGE = math.min(320, AUTO_ATTACK_RANGE + 80)
		local DIVE_MAX_KEEP = 360
		local DIVE_HP_FLEE = 0.30
		local DIVE_HP_RETURN = 0.42
		local DIVE_HP_PANIC = 0.20
		local DIVE_CENTER_RANGE = 14
		local DIVE_POISON_HEAL = 0.82
		local DIVE_FIRE_HEAL = 0.65
		local ELEMENT_STICK_SEC = 18
		local DIVE_IGNORE_WS = {
			Camera = true,
			Terrain = true,
			Characters = true,
			Mobs = true,
			Baseplate = true,
			['AntiFall-Maze'] = true,
		}
		local diveNoclipOrig = {}
		local DIVE_MOB_COLLISION_GROUPS = { 'Mobs', 'MobsNoCollision', 'Mob', 'Enemies' }
		local diveMobCollideOn = false
		local function setDiveMobIntangible(on)
			if on == diveMobCollideOn then
				return
			end
			diveMobCollideOn = on
			for _, mobGroup in ipairs(DIVE_MOB_COLLISION_GROUPS) do
				pcall(function()
					PhysicsService:CollisionGroupSetCollidable(mobGroup, 'Players', not on)
				end)
			end
		end
		local diveDashed = setmetatable({}, { __mode = 'k' })
		local diveSeenAt = setmetatable({}, { __mode = 'k' })
		local diveFleeing = false
		local diveYaw = (((tonumber(LocalPlayer.UserId) or 1) % 12) / 12) * math.pi * 2
		local lastDiveStreamAt = 0
		local lastDiveMoveAt = 0
		local lastDiveHealAt = 0
		local lastDiveMendAt = 0
		local diveMendingUntil = 0
		local diveMendingPos = nil
		local diveHpSamples = {}
		local diveElementCache = { id = nil, at = 0 }
		local diveStickMob = nil
		local diveMobsFolderConns = {}
		local diveReturnCF = nil
		local diveRestoreGen = 0
		pcall(function()
			local oldVel = getgenv().SB2DiveLinVel
			if oldVel then
				oldVel:Destroy()
			end
		end)
		local diveLinVel = Instance.new('LinearVelocity')
		diveLinVel.Name = 'SB2DiveLinVel'
		diveLinVel.MaxForce = math.huge
		diveLinVel.VectorVelocity = Vector3.zero
		diveLinVel.RelativeTo = Enum.ActuatorRelativeTo.World
		getgenv().SB2DiveLinVel = diveLinVel
		local diveNoclipStepped = nil
		local diveAnchorHook = nil

		local ELEMENT_HINTS = {
			{ id = 'darkness', words = { 'darkness', 'dark zone', 'dark element', 'stay in the middle', 'stay in the middle', 'reach the center', 'light fades' } },
			{ id = 'poison', words = { 'poison', 'toxic', 'venom', 'poison element' } },
			{ id = 'fire', words = { 'fire element', 'flame element', 'burning ground', 'inferno', 'scorched' } },
			{ id = 'ice', words = { 'ice element', 'frost element', 'frozen floor' } },
		}

		local function textHasElementHint(text)
			local t = string.lower(tostring(text or ''))
			if t == '' then
				return nil
			end
			for _, rule in ipairs(ELEMENT_HINTS) do
				for _, word in ipairs(rule.words) do
					if string.find(t, word, 1, true) then
						return rule.id
					end
				end
			end
			return nil
		end

		local function detectEventElement()
			local now = os.clock()
			if diveElementCache.id and (now - diveElementCache.at) < 1.2 then
				return diveElementCache.id
			end
			local found = nil
			for _, child in ipairs(workspace:GetChildren()) do
				found = textHasElementHint(child.Name)
				if found then
					break
				end
				if child:IsA('Folder') or child:IsA('Model') then
					local n = 0
					for _, d in ipairs(child:GetDescendants()) do
						n += 1
						if n > 80 then
							break
						end
						if d:IsA('BasePart') or d:IsA('ParticleEmitter') then
							found = textHasElementHint(d.Name)
							if found then
								break
							end
						end
					end
				end
				if found then
					break
				end
			end
			if not found then
				local pg = LocalPlayer:FindFirstChild('PlayerGui')
				if pg then
					local n = 0
					for _, d in ipairs(pg:GetDescendants()) do
						n += 1
						if n > 220 then
							break
						end
						if d:IsA('TextLabel') or d:IsA('TextButton') then
							local vis = true
							pcall(function()
								if d:IsA('GuiObject') then
									vis = d.Visible ~= false
								end
							end)
							if vis then
								found = textHasElementHint(d.Text)
								if not found and d.ContentText then
									found = textHasElementHint(d.ContentText)
								end
								if found then
									break
								end
							end
						end
					end
				end
			end
			if found then
				diveElementCache.id = found
				diveElementCache.at = now
				getgenv().SB2LastEventElement = found
				getgenv().SB2LastEventElementAt = now
				return found
			end
			local sticky = getgenv().SB2LastEventElement
			local stickyAt = tonumber(getgenv().SB2LastEventElementAt) or 0
			if sticky and (now - stickyAt) <= ELEMENT_STICK_SEC then
				diveElementCache.id = sticky
				diveElementCache.at = now
				return sticky
			end
			diveElementCache.id = nil
			diveElementCache.at = now
			return nil
		end

		local function diveHpTrendingDown()
			local hp = diveHealthFrac()
			diveHpSamples[#diveHpSamples + 1] = { t = os.clock(), hp = hp }
			while #diveHpSamples > 0 and (os.clock() - diveHpSamples[1].t) > 5 do
				table.remove(diveHpSamples, 1)
			end
			if #diveHpSamples < 3 then
				return false
			end
			return diveHpSamples[#diveHpSamples].hp <= diveHpSamples[1].hp - 0.07
		end

		local function ownedSkill(skillName)
			if not skillName then
				return false
			end
			local mySkills = getLiveProfile() and getLiveProfile():FindFirstChild('Skills')
			return mySkills ~= nil and mySkills:FindFirstChild(skillName) ~= nil
		end

		local function pickBurstHealName()
			local picked = getSelectedFarmHealSkillName()
			if picked and ownedSkill(picked) then
				return picked
			end
			if ownedSkill(BURST_HEAL_NAME) then
				return BURST_HEAL_NAME
			end
			return nil
		end

		local function pickMendHealName()
			local picked = getSelectedFarmMendSkillName()
			if picked and ownedSkill(picked) then
				return picked
			end
			if ownedSkill(MEND_HEAL_NAME) then
				return MEND_HEAL_NAME
			end
			return nil
		end

		local function tryCastNamedHeal(skillName, reason, opts)
			opts = opts or {}
			if not skillName or not isToggleOn('DiveFarm') or not isToggleOn('AutoSkill') then
				return false
			end
			local now = os.clock()
			local gap = opts.gap or 0.85
			local lastAt = opts.mend and lastDiveMendAt or lastDiveHealAt
			if now - lastAt < gap then
				return false
			end
			if not isSkillReady(skillName) then
				return false
			end
			local info = getSkillInfo(skillName)
			if getPlayerStamina() < (info.cost or 0) then
				return false
			end
			local ok = fireUseSkill(skillName, info, { muteFor = 1.2, silentFail = true, ignoreGap = false })
			if not ok then
				return false
			end
			if opts.mend then
				lastDiveMendAt = now
				local hold = tonumber(info.duration) or MEND_HOLD_FALLBACK
				if hold < 4 then
					hold = MEND_HOLD_FALLBACK
				end
				if hold > 20 then
					hold = 20
				end
				local hrp = getMyBringPart()
				diveMendingUntil = now + hold
				diveMendingPos = hrp and hrp.Position or diveMendingPos
			else
				lastDiveHealAt = now
			end
			getgenv().SB2LastEventHeal = { skill = skillName, reason = reason, at = now, mend = opts.mend == true }
			return true
		end

		local function tryCastEventHeal(reason, hp)
			hp = tonumber(hp) or diveHealthFrac()
			-- Burst Heal for emergency / poison ticks. Mending Spirit for overtime
			-- (poison/fire) — stay in its AOE after cast.
			local wantBurst = hp <= DIVE_HP_PANIC
				or hp <= DIVE_HP_FLEE
				or reason == 'low-hp'
				or reason == 'panic'
				or hp <= 0.45
			local wantMend = reason ~= 'panic'
				and (reason == 'poison' or reason == 'fire' or hp <= DIVE_POISON_HEAL)
			if wantBurst then
				tryCastNamedHeal(pickBurstHealName(), reason, { gap = 0.6 })
			end
			if wantMend then
				tryCastNamedHeal(pickMendHealName(), reason, { mend = true, gap = 1.2 })
			end
			return true
		end

		local function diveHealthFrac()
			local model = getMyCharacterModel()
			if not model then
				return 1
			end
			local entity = model:FindFirstChild('Entity')
			local h = entity and entity:FindFirstChild('Health')
			local m = entity and entity:FindFirstChild('MaxHealth')
			if h and m and typeof(h.Value) == 'number' and typeof(m.Value) == 'number' and m.Value > 0 then
				return h.Value / m.Value
			end
			local hum = model:FindFirstChildOfClass('Humanoid')
			if hum and hum.MaxHealth > 0 then
				return hum.Health / hum.MaxHealth
			end
			return 1
		end

		local function setDiveNoclip(on)
			if on then
				setDiveMobIntangible(true)
				if not diveNoclipStepped then
					diveNoclipStepped = RunService.Stepped:Connect(function()
						local model = getMyCharacterModel()
						if not model then
							return
						end
						for _, child in ipairs(model:GetDescendants()) do
							if child:IsA('BasePart') then
								if diveNoclipOrig[child] == nil then
									diveNoclipOrig[child] = child.CanCollide
								end
								child.CanCollide = false
								child.CanTouch = false
								child.Massless = true
							end
						end
						local hrp = getMyBringPart()
						if hrp then
							hrp.AssemblyLinearVelocity = Vector3.zero
							hrp.AssemblyAngularVelocity = Vector3.zero
						end
					end)
				end
				local hrp = getMyBringPart()
				if hrp then
					pcall(function()
						local att = hrp:FindFirstChild('RootAttachment')
						if not att then
							att = hrp:FindFirstChildWhichIsA('Attachment')
						end
						if not att then
							att = Instance.new('Attachment')
							att.Name = 'SB2DiveAttachment'
							att.Parent = hrp
						end
						diveLinVel.Attachment0 = att
						diveLinVel.VectorVelocity = Vector3.zero
						diveLinVel.Parent = workspace
						hrp.Anchored = false
					end)
					if diveAnchorHook then
						pcall(function()
							diveAnchorHook:Disconnect()
						end)
					end
					diveAnchorHook = hrp:GetPropertyChangedSignal('Anchored'):Connect(function()
						if getgenv().SB2DiveFarmOn and hrp.Parent and hrp.Anchored then
							hrp.Anchored = false
						end
					end)
				end
				pcall(function()
					local model = getMyCharacterModel()
					local hum = model and model:FindFirstChildOfClass('Humanoid')
					if hum then
						hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
						hum.Sit = false
					end
				end)
			else
				setDiveMobIntangible(false)
				if diveNoclipStepped then
					pcall(function()
						diveNoclipStepped:Disconnect()
					end)
					diveNoclipStepped = nil
				end
				if diveAnchorHook then
					pcall(function()
						diveAnchorHook:Disconnect()
					end)
					diveAnchorHook = nil
				end
				pcall(function()
					diveLinVel.Parent = nil
					diveLinVel.Attachment0 = nil
				end)
				for part, orig in pairs(diveNoclipOrig) do
					if part.Parent then
						pcall(function()
							part.CanCollide = orig
							part.CanTouch = true
							part.Massless = false
						end)
					end
				end
				table.clear(diveNoclipOrig)
				pcall(function()
					local model = getMyCharacterModel()
					local hum = model and model:FindFirstChildOfClass('Humanoid')
					if hum then
						hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true)
					end
				end)
			end
		end

		-- Neuublue autofarm: snap Y under the target, then fly XZ (CFrame +=).
		local function diveFlyStep(hrp, targetPos, dt)
			if not hrp or not targetPos then
				return
			end
			dt = tonumber(dt) or 0.016
			if dt <= 0 then
				dt = 1 / 60
			end
			pcall(function()
				hrp.Anchored = false
				local toTarget = targetPos - hrp.Position
				local totalDist = toTarget.Magnitude
				if totalDist < 0.05 then
					return
				end
				hrp.CFrame += Vector3.new(0, toTarget.Y, 0)
				local horiz = Vector3.new(toTarget.X, 0, toTarget.Z)
				local horizDist = horiz.Magnitude
				if horizDist < 0.05 then
					return
				end
				local alpha = math.clamp(dt * DIVE_FLY_SPEED / horizDist, 0, 1)
				hrp.CFrame += horiz.Unit * totalDist * alpha
			end)
		end

		local function diveMoveTo(hrp, pos, _look)
			diveFlyStep(hrp, pos, 1)
		end

		local function diveUnderY(clusterPos)
			return clusterPos.Y + DIVE_VERTICAL
		end

		local function captureDiveReturnCF()
			local hrp = getMyBringPart()
			if not hrp then
				return
			end
			diveReturnCF = hrp.CFrame
			getgenv().SB2DiveReturnCF = diveReturnCF
		end

		local function restoreDiveReturnCF()
			local cf = diveReturnCF or getgenv().SB2DiveReturnCF
			diveReturnCF = nil
			getgenv().SB2DiveReturnCF = nil
			if typeof(cf) ~= 'CFrame' then
				return
			end
			diveRestoreGen += 1
			local gen = diveRestoreGen
			task.spawn(function()
				setDiveNoclip(true)
				for _ = 1, 14 do
					if gen ~= diveRestoreGen or getgenv().SB2DiveFarmOn then
						return
					end
					local hrp = getMyBringPart()
					if not hrp then
						break
					end
					pcall(function()
						local model = getMyCharacterModel()
						if model and model.PivotTo then
							model:PivotTo(cf)
						end
						hrp.Anchored = false
						hrp.CFrame = cf
						hrp.AssemblyLinearVelocity = Vector3.zero
						hrp.AssemblyAngularVelocity = Vector3.zero
					end)
					if (hrp.Position - cf.Position).Magnitude <= 8 then
						break
					end
					RunService.Heartbeat:Wait()
				end
				if gen ~= diveRestoreGen or getgenv().SB2DiveFarmOn then
					return
				end
				setDiveNoclip(false)
				pcall(function()
					LocalPlayer:RequestStreamAroundAsync(cf.Position, 40)
				end)
			end)
		end

		local function diveStayUnder(hrp, xzPos, dt)
			if not hrp or not xzPos then
				return
			end
			setDiveNoclip(true)
			local surfaceY = xzPos.Y
			local saved = diveReturnCF or getgenv().SB2DiveReturnCF
			if typeof(saved) == 'CFrame' then
				surfaceY = saved.Position.Y
			end
			diveFlyStep(hrp, Vector3.new(xzPos.X, surfaceY + DIVE_VERTICAL, xzPos.Z), dt or 1)
		end

		local function clampNearCluster(pos, cluster, maxDist)
			local flat = Vector3.new(pos.X - cluster.X, 0, pos.Z - cluster.Z)
			if flat.Magnitude <= maxDist then
				return Vector3.new(pos.X, pos.Y, pos.Z)
			end
			local u = flat.Unit * maxDist
			return Vector3.new(cluster.X + u.X, pos.Y, cluster.Z + u.Z)
		end

		local function diveLiveMobs()
			local mobsRoot = workspace:FindFirstChild('Mobs')
			if not mobsRoot then
				return {}
			end
			local out = {}
			for _, mob in ipairs(mobsRoot:GetChildren()) do
				if isDeadMob(mob) or shouldSkipMob(mob) then
					continue
				end
				local root = getMobRoot(mob)
				if not root then
					continue
				end
				out[#out + 1] = { mob = mob, pos = root.Position }
			end
			return out
		end

		-- Any live mob in workspace.Mobs. Stick to one pack (nearest, then all
		-- within killaura XZ), sit under that pack so every member stays in range.
		local function diveFocus(origin)
			local entries = diveLiveMobs()
			if #entries == 0 then
				diveStickMob = nil
				return nil, 0, 0
			end
			local stick = nil
			if diveStickMob then
				for i = 1, #entries do
					if entries[i].mob == diveStickMob then
						stick = entries[i]
						break
					end
				end
			end
			if not stick then
				local best, bestD = nil, math.huge
				for i = 1, #entries do
					local e = entries[i]
					local d = 0
					if origin then
						local dx = e.pos.X - origin.X
						local dz = e.pos.Z - origin.Z
						d = math.sqrt(dx * dx + dz * dz)
					end
					if d < bestD then
						best, bestD = e, d
					end
				end
				stick = best
				diveStickMob = stick and stick.mob or nil
			end
			if not stick then
				return nil, 0, 0
			end
			local aura = AUTO_ATTACK_RANGE
			local sx, sy, sz, n = 0, 0, 0, 0
			for i = 1, #entries do
				local e = entries[i]
				local dx = e.pos.X - stick.pos.X
				local dz = e.pos.Z - stick.pos.Z
				if (dx * dx + dz * dz) <= (aura * aura) then
					sx += e.pos.X
					sy += e.pos.Y
					sz += e.pos.Z
					n += 1
				end
			end
			if n <= 0 then
				return stick.pos, 1, 0
			end
			local center = Vector3.new(sx / n, sy / n, sz / n)
			local packR = 0
			for i = 1, #entries do
				local e = entries[i]
				local dx = e.pos.X - center.X
				local dz = e.pos.Z - center.Z
				local d = math.sqrt(dx * dx + dz * dz)
				if d <= aura and d > packR then
					packR = d
				end
			end
			return center, n, packR
		end

		local function nameLooksTelegraph(name)
			local n = string.lower(tostring(name or ''))
			if n == '' or n == 'humanoidrootpart' or n == 'torso' or n == 'head' then
				return false
			end
			return string.find(n, 'hitbox', 1, true)
				or string.find(n, 'warn', 1, true)
				or string.find(n, 'indicat', 1, true)
				or string.find(n, 'aoe', 1, true)
				or string.find(n, 'circle', 1, true)
				or string.find(n, 'ring', 1, true)
				or string.find(n, 'nuke', 1, true)
				or string.find(n, 'gyzer', 1, true)
				or string.find(n, 'geyser', 1, true)
				or string.find(n, 'smash', 1, true)
				or string.find(n, 'stomp', 1, true)
				or string.find(n, 'slam', 1, true)
				or string.find(n, 'blast', 1, true)
				or string.find(n, 'nova', 1, true)
				or string.find(n, 'storm', 1, true)
				or string.find(n, 'laser', 1, true)
				or string.find(n, 'lazer', 1, true)
				or string.find(n, 'beam', 1, true)
				or string.find(n, 'ray', 1, true)
				or string.find(n, 'wave', 1, true)
				or string.find(n, 'charge', 1, true)
				or string.find(n, 'fillin', 1, true)
				or string.find(n, 'telegraph', 1, true)
				or string.find(n, 'omega', 1, true)
				or string.find(n, 'zone', 1, true)
				or string.find(n, 'pool', 1, true)
				or string.find(n, 'fireball', 1, true)
				or string.find(n, 'projectile', 1, true)
				or string.find(n, 'meteor', 1, true)
				or string.find(n, 'orb', 1, true)
				or string.find(n, 'bolt', 1, true)
				or string.find(n, 'shard', 1, true)
				or string.find(n, 'darkness', 1, true)
				or string.find(n, 'poison', 1, true)
				or string.find(n, 'toxic', 1, true)
				or string.find(n, 'venom', 1, true)
				or string.find(n, 'flame', 1, true)
				or string.find(n, 'inferno', 1, true)
		end

		local function partLooksProjectile(part, name)
			local n = string.lower(tostring(name or part.Name))
			if string.find(n, 'fireball', 1, true)
				or string.find(n, 'projectile', 1, true)
				or string.find(n, 'meteor', 1, true)
				or string.find(n, 'orb', 1, true)
				or string.find(n, 'bolt', 1, true)
			then
				return true
			end
			local s = part.Size
			local maxS = math.max(s.X, s.Y, s.Z)
			local minS = math.min(s.X, s.Y, s.Z)
			if maxS <= 10 and minS >= 0.8 then
				local vel = part.AssemblyLinearVelocity.Magnitude
				if vel > 18 then
					return true
				end
			end
			return false
		end

		local function partIsBeamish(part, name)
			local n = string.lower(tostring(name or part.Name))
			if string.find(n, 'laser', 1, true)
				or string.find(n, 'lazer', 1, true)
				or string.find(n, 'beam', 1, true)
				or string.find(n, 'ray', 1, true)
				or string.find(n, 'wave', 1, true)
				or string.find(n, 'omega', 1, true)
				or string.find(n, 'dash', 1, true)
			then
				return true
			end
			local s = part.Size
			local axes = { s.X, s.Y, s.Z }
			table.sort(axes)
			return axes[3] >= 18 and axes[3] >= axes[2] * 3.2
		end

		local function considerTelegraph(part, into, myChar)
			if not part or not part:IsA('BasePart') or not part.Parent then
				return
			end
			if myChar and part:IsDescendantOf(myChar) then
				return
			end
			if part.Transparency >= 0.98 then
				return
			end
			local s = part.Size
			if math.max(s.X, s.Y, s.Z) < 6 then
				return
			end
			local named = nameLooksTelegraph(part.Name) or nameLooksTelegraph(part.Parent and part.Parent.Name)
			if not named and not partIsBeamish(part, part.Name) and not partLooksProjectile(part, part.Name) then
				return
			end
			if not diveSeenAt[part] then
				diveSeenAt[part] = os.clock()
			end
			local beam = partIsBeamish(part, part.Name) or partIsBeamish(part, part.Parent and part.Parent.Name)
			local projectile = partLooksProjectile(part, part.Name) or partLooksProjectile(part, part.Parent and part.Parent.Name)
			if projectile then
				beam = true
			end
			into[#into + 1] = {
				part = part,
				beam = beam,
				seenAt = diveSeenAt[part],
			}
		end

		local function collectTelegraphs()
			local hits = {}
			local myChar = getMyCharacterModel()
			for _, child in ipairs(workspace:GetChildren()) do
				if DIVE_IGNORE_WS[child.Name] then
					continue
				end
				if child:IsA('BasePart') then
					considerTelegraph(child, hits, myChar)
				elseif child:IsA('Model') or child:IsA('Folder') or child:IsA('Accoutrement') then
					local n = 0
					for _, d in ipairs(child:GetDescendants()) do
						n += 1
						if n > 220 then
							break
						end
						if d:IsA('BasePart') then
							considerTelegraph(d, hits, myChar)
						end
					end
				end
			end
			local mobs = workspace:FindFirstChild('Mobs')
			if mobs then
				for _, mob in ipairs(mobs:GetChildren()) do
					local n = 0
					for _, d in ipairs(mob:GetDescendants()) do
						n += 1
						if n > 160 then
							break
						end
						if d:IsA('BasePart') and (nameLooksTelegraph(d.Name) or nameLooksTelegraph(d.Parent and d.Parent.Name)) then
							considerTelegraph(d, hits, myChar)
						end
					end
				end
			end
			return hits
		end

		local function telegraphEscape(hrpPos, cluster)
			local hits = collectTelegraphs()
			if #hits == 0 then
				return nil, false, nil
			end
			local pos = Vector3.new(hrpPos.X, hrpPos.Y, hrpPos.Z)
			local needDash = false
			local dashDir = nil
			local moved = false
			local now = os.clock()
			for _, hit in ipairs(hits) do
				local part = hit.part
				local p = part.Position
				if hit.beam then
					local look = part.CFrame.LookVector
					local s = part.Size
					local long = math.max(s.X, s.Y, s.Z)
					if s.X >= s.Y and s.X >= s.Z then
						look = part.CFrame.RightVector
					elseif s.Y >= s.X and s.Y >= s.Z then
						look = part.CFrame.UpVector
					end
					look = Vector3.new(look.X, 0, look.Z)
					if look.Magnitude < 0.05 then
						look = Vector3.new(0, 0, -1)
					else
						look = look.Unit
					end
					local halfW = math.max(4, math.min(s.X, s.Y, s.Z) * 0.5 + 6)
					local rel = Vector3.new(pos.X - p.X, 0, pos.Z - p.Z)
					local along = rel:Dot(look)
					if math.abs(along) > long * 0.65 + 20 then
						continue
					end
					local perp = rel - look * along
					local dist = perp.Magnitude
					local side = perp.Magnitude > 0.2 and perp.Unit or Vector3.new(-look.Z, 0, look.X)
					dashDir = side
					if dist < halfW + 8 then
						pos = Vector3.new(pos.X + side.X * (halfW + 14 - dist), pos.Y, pos.Z + side.Z * (halfW + 14 - dist))
						moved = true
					end
					local age = now - (hit.seenAt or now)
					local firing = part.Transparency < 0.35 or age >= 0.9
					if firing and not diveDashed[part] then
						needDash = true
						moved = true
						if dist >= halfW + 8 then
							pos = Vector3.new(pos.X + side.X * 18, pos.Y, pos.Z + side.Z * 18)
						end
					end
				else
					local radius = math.max(part.Size.X, part.Size.Z) * 0.5 + 8
					local flat = Vector3.new(pos.X - p.X, 0, pos.Z - p.Z)
					if flat.Magnitude < radius then
						if flat.Magnitude < 0.2 then
							flat = Vector3.new(math.cos(diveYaw), 0, math.sin(diveYaw))
						end
						local u = flat.Unit
						pos = Vector3.new(p.X + u.X * (radius + 6), pos.Y, p.Z + u.Z * (radius + 6))
						moved = true
					end
				end
			end
			if not moved then
				return nil, false, nil
			end
			if cluster then
				pos = clampNearCluster(pos, cluster, DIVE_MAX_KEEP)
			end
			return pos, needDash, dashDir
		end

		local function diveTryDash(hrp, dir)
			if not hrp or not dir then
				return
			end
			local flat = Vector3.new(dir.X, 0, dir.Z)
			if flat.Magnitude < 0.05 then
				return
			end
			flat = flat.Unit
			local dest = hrp.Position + flat * 28
			diveMoveTo(hrp, dest, flat)
			pcall(function()
				local info = getSkillInfo('Roll')
				fireUseSkill('Roll', info, { ignoreMobsGate = true, ignoreGap = true })
			end)
		end

		local function stopDiveFarm(restore)
			getgenv().SB2DiveFarmOn = false
			diveFleeing = false
			diveStickMob = nil
			diveMendingUntil = 0
			diveMendingPos = nil
			local prev = getgenv().SB2DiveFarmConn
			if prev then
				pcall(function()
					prev:Disconnect()
				end)
				getgenv().SB2DiveFarmConn = nil
			end
			for _, c in ipairs(diveMobsFolderConns) do
				pcall(function()
					c:Disconnect()
				end)
			end
			diveMobsFolderConns = {}
			if restore then
				restoreDiveReturnCF()
			else
				setDiveNoclip(false)
			end
		end

		local function startDiveFarm()
			stopDiveFarm(false)
			diveRestoreGen += 1
			captureDiveReturnCF()
			getgenv().SB2DiveFarmOn = true
			diveFleeing = false
			pcall(function()
				if Toggles.CombatAnchor and Toggles.CombatAnchor.Value then
					Toggles.CombatAnchor:SetValue(false)
				end
			end)
			pcall(function()
				if Toggles.AutoAttack and Toggles.AutoAttack.SetValue and not Toggles.AutoAttack.Value then
					Toggles.AutoAttack:SetValue(true)
				end
			end)
			pcall(function()
				if Toggles.AutoSkill and Toggles.AutoSkill.SetValue and not Toggles.AutoSkill.Value then
					Toggles.AutoSkill:SetValue(true)
				end
			end)
			pcall(function()
				if Toggles.SupportSkill and Toggles.SupportSkill.SetValue and not Toggles.SupportSkill.Value then
					Toggles.SupportSkill:SetValue(true)
				end
			end)
			applyCombatAnchor(false)
			setDiveNoclip(true)
			pcall(function()
				local mobsRoot = workspace:FindFirstChild('Mobs')
				if not mobsRoot then
					return
				end
				diveMobsFolderConns[#diveMobsFolderConns + 1] = mobsRoot.ChildAdded:Connect(function()
					if not diveStickMob or isDeadMob(diveStickMob) then
						diveStickMob = nil
					end
				end)
				diveMobsFolderConns[#diveMobsFolderConns + 1] = mobsRoot.ChildRemoved:Connect(function(child)
					if child == diveStickMob then
						diveStickMob = nil
					end
				end)
			end)
			getgenv().SB2DiveFarmConn = RunService.Heartbeat:Connect(function(dt)
				if not isToggleOn('DiveFarm') then
					stopDiveFarm(true)
					return
				end
				if isToggleOn('CombatAnchor') then
					pcall(function()
						Toggles.CombatAnchor:SetValue(false)
					end)
					applyCombatAnchor(false)
				end
				if not isLocalAlive() then
					return
				end
				local hrp = getMyBringPart()
				if not hrp then
					return
				end
				setDiveNoclip(true)
				if #diveMobsFolderConns == 0 then
					pcall(function()
						local mobsRoot = workspace:FindFirstChild('Mobs')
						if not mobsRoot then
							return
						end
						diveMobsFolderConns[#diveMobsFolderConns + 1] = mobsRoot.ChildAdded:Connect(function()
							if not diveStickMob or isDeadMob(diveStickMob) then
								diveStickMob = nil
							end
						end)
						diveMobsFolderConns[#diveMobsFolderConns + 1] = mobsRoot.ChildRemoved:Connect(function(child)
							if child == diveStickMob then
								diveStickMob = nil
							end
						end)
					end)
				end
				local cluster, nMobs, packR = diveFocus(hrp.Position)
				if not cluster or nMobs <= 0 then
					diveStayUnder(hrp, hrp.Position, dt)
					return
				end
				packR = tonumber(packR) or 0
				local hp = diveHealthFrac()
				local element = detectEventElement()
				local panic = hp <= DIVE_HP_PANIC
				if panic then
					diveFleeing = true
					diveMendingUntil = 0
					diveMendingPos = nil
					tryCastEventHeal('panic', hp)
				elseif hp <= DIVE_HP_FLEE then
					diveFleeing = true
				elseif hp >= DIVE_HP_RETURN then
					diveFleeing = false
				end
				local poisonEvent = not panic and (element == 'poison' or diveHpTrendingDown())
				local fireEvent = not panic and element == 'fire'
				if not panic then
					if poisonEvent and (hp <= DIVE_POISON_HEAL or diveFleeing or diveHpTrendingDown()) then
						tryCastEventHeal('poison', hp)
					elseif fireEvent and hp <= DIVE_FIRE_HEAL then
						tryCastEventHeal('fire', hp)
					elseif diveFleeing then
						tryCastEventHeal('low-hp', hp)
					end
				end
				local keepHit = math.max(12, AUTO_ATTACK_RANGE - packR - 12)
				-- Neuublue default: sit directly under the mob (horizontal 0, Y-60).
				local range = 0
				if panic then
					range = math.min(DIVE_FLEE_RANGE, math.max(keepHit + 40, AUTO_ATTACK_RANGE * 0.9))
				elseif element == 'darkness' then
					range = DIVE_CENTER_RANGE
				elseif diveFleeing or poisonEvent or fireEvent then
					range = math.min(DIVE_FLEE_RANGE, math.max(keepHit, DIVE_AURA_RANGE))
				end
				local underY = cluster.Y + DIVE_VERTICAL
				local ring = Vector3.new(cluster.X + math.cos(diveYaw) * range, underY, cluster.Z + math.sin(diveYaw) * range)
				if element == 'darkness' and not panic then
					ring = Vector3.new(cluster.X, underY, cluster.Z)
				end
				-- Mending Spirit is a ground AOE HoT — stay inside it until it expires.
				-- Instant-kill telegraphs still dodge; then return to the circle.
				-- Panic (<20%) cancels the hold and TPs away.
				local holdingMend = not panic
					and os.clock() < diveMendingUntil
					and diveMendingPos ~= nil
				if holdingMend then
					ring = Vector3.new(diveMendingPos.X, underY, diveMendingPos.Z)
				end
				local dodgePos, needDash, dashDir = telegraphEscape(hrp.Position, cluster)
				local now = os.clock()
				if now - lastDiveStreamAt > 1.4 then
					lastDiveStreamAt = now
					pcall(function()
						LocalPlayer:RequestStreamAroundAsync(cluster, 70)
					end)
					pcall(lockReplicationFocus, getMyCharacterModel())
				end
				if panic then
					diveFlyStep(hrp, ring, dt)
					return
				end
				if dodgePos then
					local dest = Vector3.new(dodgePos.X, underY, dodgePos.Z)
					if holdingMend then
						local dx = dest.X - diveMendingPos.X
						local dz = dest.Z - diveMendingPos.Z
						if (dx * dx + dz * dz) > (MEND_AOE_STAY * MEND_AOE_STAY) and not needDash then
							dest = Vector3.new(diveMendingPos.X, underY, diveMendingPos.Z)
						end
					end
					diveFlyStep(hrp, dest, dt)
					if needDash then
						diveTryDash(hrp, dashDir or (dest - hrp.Position))
						for _, hit in ipairs(collectTelegraphs()) do
							if hit.beam then
								diveDashed[hit.part] = true
							end
						end
					end
					return
				end
				if holdingMend then
					diveFlyStep(hrp, Vector3.new(diveMendingPos.X, underY, diveMendingPos.Z), dt)
					return
				end
				diveFlyStep(hrp, ring, dt)
			end)
		end

		CombatBox:AddToggle('DiveFarm', {
			Text = 'Event dive (under map)',
			Default = false,
			Tooltip = 'Saves your spot, noclips, and flies under the mob (Neuublue-style). Intangible to mobs while on (no push). Off teleports you back.',
		}):OnChanged(function(value)
			if not value then
				stopDiveFarm(true)
				return
			end
			startDiveFarm()
			pcall(function()
				Library:Notify('Event dive on — flying under mobs. Off teleports you back.', 6)
			end)
		end)

		do
			local farmSkills = getAvailableSkills()
			local farmSupport = getAvailableSupportSkills()
			local farmHeal = getAvailableHealSkills()
			local defaultFarmSkill = '(none)'
			for _, pick in ipairs({ 'Water Blast', 'Downward Smash', 'Everfrost Strike' }) do
				if table.find(farmSkills, pick) then
					defaultFarmSkill = pick
					break
				end
			end
			if defaultFarmSkill == '(none)' and farmSkills[2] then
				defaultFarmSkill = farmSkills[2]
			end
			local defaultFarmSupport = table.find(farmSupport, 'Cursed Enhancement') and 'Cursed Enhancement' or farmSupport[2]
			local defaultFarmHeal = table.find(farmHeal, 'Heal') and 'Heal' or farmHeal[2]
			CombatBox:AddDropdown('FarmSkillName', {
				Text = 'Farm weapon skill',
				Values = farmSkills,
				Default = defaultFarmSkill,
				AllowNull = false,
				Searchable = true,
				Tooltip = 'Used while Event dive is on instead of the killaura Skill dropdown.',
			})
			CombatBox:AddDropdown('FarmSupportSkillName', {
				Text = 'Farm support skill',
				Values = farmSupport,
				Default = defaultFarmSupport or '(none)',
				AllowNull = false,
				Searchable = true,
				Tooltip = 'Usually Cursed Enhancement. Event dive casts this, not killaura Support.',
			})
			CombatBox:AddDropdown('FarmHealSkillName', {
				Text = 'Farm heal (burst)',
				Values = farmHeal,
				Default = defaultFarmHeal or '(none)',
				AllowNull = false,
				Searchable = true,
				Tooltip = 'Heal — one-shot HP dump. Used on poison ticks, fire, or below 30%.',
			})
			local defaultFarmMend = table.find(farmHeal, 'Mending Spirit') and 'Mending Spirit' or '(none)'
			CombatBox:AddDropdown('FarmMendSkillName', {
				Text = 'Farm heal (AoE)',
				Values = farmHeal,
				Default = defaultFarmMend,
				AllowNull = false,
				Searchable = true,
				Tooltip = 'Mending Spirit — HoT. After cast, stay in the circle until it ends. Instant-kill dodges still work. Accounts that do not own it skip this.',
			})
		end

		-- Anyone else joining → kill combat so you don't look blatant / get Secure API'd.
		local disableCombatForPlayerJoin = function(joiner)
			if not joiner or joiner == LocalPlayer or isOwnAlt(joiner) then
				return
			end
			local changed = false
			for _, name in ipairs({ 'AutoAttack', 'AutoSkill', 'CombatAnchor', 'DiveFarm', 'HitLivesRush' }) do
				local toggle = Toggles[name]
				if type(toggle) == 'table' and toggle.Value == true and type(toggle.SetValue) == 'function' then
					pcall(function()
						toggle:SetValue(false)
					end)
					changed = true
				end
			end
			if changed then
				pcall(function()
					Library:Notify(('Combat off — %s joined'):format(joiner.Name), 4)
				end)
			end
		end
		do
			local prev = getgenv().SB2CombatJoinDisableConn
			if prev then
				pcall(function()
					prev:Disconnect()
				end)
			end
			getgenv().SB2CombatJoinDisableConn = Players.PlayerAdded:Connect(disableCombatForPlayerJoin)
		end

		do
			local skillValues = getAvailableSkills()
			local supportValues = getAvailableSupportSkills()
			-- Fresh UI / no profile: none. SaveManager still restores a saved skill after load.
			local defaultSkill = '(none)'
			local defaultSupport = '(none)'
			CombatBox:AddDropdown('SkillName', {
				Text = 'Skill (held weapon)',
				Values = skillValues,
				Default = defaultSkill,
				AllowNull = false,
				Searchable = true,
			})
			CombatBox:AddDropdown('SupportSkillName', {
				Text = 'Support skill (buff)',
				Values = supportValues,
				Default = defaultSupport,
				AllowNull = false,
				Searchable = true,
				Tooltip = 'Anytime buffs like Cursed Enhancement — casts on its own CD alongside your weapon skill.',
			})
			local function rememberPickedSkills(skill, support)
				local last = getgenv().SB2LastCombatOptions
				if type(last) ~= 'table' then
					last = {}
					getgenv().SB2LastCombatOptions = last
				end
				if skill ~= nil then
					last.SkillName = skill
				end
				if support ~= nil then
					last.SupportSkillName = support
				end
				if getgenv().SB2ConfigLoading then
					return
				end
				if type(writefile) ~= 'function' then
					return
				end
				pcall(function()
					local HttpService = game:GetService('HttpService')
					writefile(
						COMBAT_SKILLS_PATH,
						HttpService:JSONEncode({
							SkillName = last.SkillName,
							SupportSkillName = last.SupportSkillName,
						})
					)
				end)
			end
			getgenv().SB2RememberPickedSkills = rememberPickedSkills
			pcall(function()
				Options.SkillName:OnChanged(function(value)
					if getgenv().SB2ConfigLoading then
						return
					end
					local skill = flattenOptionValue(value) or flattenOptionValue(Options.SkillName.Value)
					if skill and skill ~= '' then
						getgenv().SB2UserPickedCombatSkill = true
						getgenv().SB2HonorSavedCombatSkill = true
						rememberPickedSkills(skill, nil)
					end
				end)
			end)
			pcall(function()
				Options.SupportSkillName:OnChanged(function(value)
					if getgenv().SB2ConfigLoading then
						return
					end
					local support = flattenOptionValue(value) or flattenOptionValue(Options.SupportSkillName.Value)
					if support and support ~= '' then
						rememberPickedSkills(nil, support)
					end
				end)
			end)
			CombatBox:AddToggle('SupportSkill', {
				Text = 'Auto support skill',
				Default = true,
				Tooltip = 'Cast the support buff (CE etc.) on its cooldown while Auto skill is on.',
			})
			CombatBox:AddToggle('SupportBossOnly', {
				Text = 'Support only on bosses',
				Default = true,
				Tooltip = 'Only cast support when a boss is in workspace.Mobs (wiki Boss list + Entity.Boss / HitLives). Ignored during hit-lives rush.',
			})
			CombatBox:AddButton('Refresh skills', function()
				refreshSkillDropdown(true)
			end)
			-- After UI build: soft prefer only. Profile load owns SkillName afterward.
			task.defer(function()
				if not getgenv().SB2HonorSavedCombatSkill then
					preferWeaponCombatSkill(false)
				end
			end)
			task.delay(0.4, function()
				if not getgenv().SB2HonorSavedCombatSkill then
					preferWeaponCombatSkill(false)
				end
			end)
			task.delay(1.2, function()
				if not getgenv().SB2HonorSavedCombatSkill then
					preferWeaponCombatSkill(false)
				end
			end)
			pcall(function()
				local equip = getLiveProfile() and getLiveProfile():FindFirstChild('Equip')
				if not equip then
					return
				end
				for _, hand in ipairs({ 'Right', 'Left' }) do
					local slot = equip:FindFirstChild(hand)
					if slot and slot:IsA('ValueBase') then
						slot:GetPropertyChangedSignal('Value'):Connect(function()
							task.defer(function()
								refreshSkillDropdown(false)
							end)
						end)
					end
				end
			end)
		end

		local COMBAT_TRIO = { 'AutoAttack', 'AutoSkill', 'CombatAnchor' }
		local WP_NONE = '(none)'

		local function otherPlayersPresent()
			for _, plr in ipairs(Players:GetPlayers()) do
				if plr ~= LocalPlayer and not isOwnAlt(plr) then
					return true
				end
			end
			return false
		end

		local function setCombatTrio(enabled)
			for _, name in ipairs(COMBAT_TRIO) do
				local toggle = Toggles[name]
				if type(toggle) == 'table' and type(toggle.SetValue) == 'function' then
					pcall(function()
						toggle:SetValue(enabled == true)
					end)
				end
			end
		end

		local function listSoloWaypoints()
			local names = { WP_NONE }
			local fn = getgenv().SB2WaypointsListForPlace
			if type(fn) == 'function' then
				local ok, listed = pcall(fn)
				if ok and type(listed) == 'table' then
					for _, name in ipairs(listed) do
						if type(name) == 'string' and name ~= '' then
							names[#names + 1] = name
						end
					end
					return names
				end
			end
			local store = getgenv().SB2Waypoints and getgenv().SB2Waypoints.store
			local pid = game.PlaceId
			if store and type(store.waypoints) == 'table' then
				for _, wp in ipairs(store.waypoints) do
					if type(wp) == 'table' and type(wp.name) == 'string' then
						if wp.placeId == nil or tonumber(wp.placeId) == pid then
							names[#names + 1] = wp.name
						end
					end
				end
			end
			return names
		end

		local function currentSoloWaypoint()
			local opt = Options.SoloResumeWaypoint and Options.SoloResumeWaypoint.Value
			if type(opt) == 'string' and opt ~= '' and opt ~= WP_NONE then
				return opt
			end
			local getter = getgenv().SB2WaypointsGetSelected
			if type(getter) == 'function' then
				local ok, name = pcall(getter)
				if ok and type(name) == 'string' and name ~= '' then
					return name
				end
			end
			return nil
		end

		local function findSoloWaypointRec(name)
			if type(name) ~= 'string' or name == '' then
				return nil
			end
			local store = getgenv().SB2Waypoints and getgenv().SB2Waypoints.store
			if not (store and type(store.waypoints) == 'table') then
				return nil
			end
			local lname = string.lower(name)
			for _, rec in ipairs(store.waypoints) do
				if type(rec) == 'table' and type(rec.name) == 'string' and string.lower(rec.name) == lname then
					return rec
				end
			end
			return nil
		end

		local function applyCharacterCFrame(cf)
			holdCombatAnchor(0.5)
			local model = getMyCharacterModel() or LocalPlayer.Character
			if not model then
				return false, 'no character'
			end
			local hrp = model:FindFirstChild('HumanoidRootPart') or model:FindFirstChild('UpperTorso')
			if not hrp or not hrp:IsA('BasePart') then
				return false, 'no root'
			end
			pcall(function()
				hrp.Anchored = false
			end)
			for _ = 1, 5 do
				RunService.Heartbeat:Wait()
				pcall(function()
					hrp.Anchored = false
				end)
			end
			pcall(function()
				if model.PivotTo then
					model:PivotTo(cf)
				end
				hrp.Anchored = false
				hrp.CFrame = cf
				hrp.AssemblyLinearVelocity = Vector3.zero
				hrp.AssemblyAngularVelocity = Vector3.zero
			end)
			for _ = 1, 10 do
				RunService.Heartbeat:Wait()
				pcall(function()
					hrp.Anchored = false
					if (hrp.Position - cf.Position).Magnitude > 8 then
						hrp.CFrame = cf
					end
				end)
				if (hrp.Position - cf.Position).Magnitude <= 8 then
					break
				end
			end
			holdCombatAnchor(0.5)
			lockReplicationFocus(model)
			pcall(function()
				LocalPlayer:RequestStreamAroundAsync(cf.Position, 40)
			end)
			if type(getgenv().SB2FixCamera) == 'function' then
				pcall(getgenv().SB2FixCamera, model)
			end
			local dist = (hrp.Position - cf.Position).Magnitude
			if dist > 25 then
				return false, 'still not at waypoint'
			end
			return true
		end

		local function teleportSoloWaypoint()
			local setter = getgenv().SB2WaypointsSetSelected
			local name = currentSoloWaypoint()
			if name and type(setter) == 'function' then
				pcall(setter, name, true)
			end
			if not name then
				return false, 'no waypoint selected'
			end
			local wp = findSoloWaypointRec(name)
			if not wp then
				local named = getgenv().SB2WaypointsTeleportNamed
				if type(named) == 'function' then
					holdCombatAnchor(0.5)
					for _ = 1, 5 do
						RunService.Heartbeat:Wait()
					end
					return named(name)
				end
				return false, 'waypoint not found'
			end
			local cf = CFrame.new(tonumber(wp.x) or 0, tonumber(wp.y) or 0, tonumber(wp.z) or 0)
			return applyCharacterCFrame(cf)
		end

		local lastSoloResumeAt = 0
		local function resumeSoloCombat(reason, force)
			if getgenv().SB2AutoBlockHopping then
				return
			end
			if not force and not isToggleOn('SoloCombatResume') then
				return
			end
			if not force and otherPlayersPresent() then
				return
			end
			local now = os.clock()
			if not force and now - lastSoloResumeAt < 1.5 then
				return
			end
			lastSoloResumeAt = now
			pcall(function()
				local hive = getgenv().SB2Hive
				if hive and type(hive.stopMovement) == 'function' then
					hive.stopMovement()
				end
			end)
			-- 0.5s hold after TP — Anchor stays off until this expires.
			holdCombatAnchor(0.5)
			task.wait(0.05)
			local okTp, errTp = teleportSoloWaypoint()
			holdCombatAnchor(0.5)
			setCombatTrio(true)
			pcall(function()
				if okTp then
					Library:Notify('Solo — teleported, then combat/anchor', 4)
				else
					Library:Notify(
						('Solo — combat on (%s)'):format(tostring(errTp or reason or 'no waypoint')),
						4
					)
				end
			end)
		end

		local AutoBlock = (function()
		local F1_PLACE = 542351431
		local F11_PLACE = 5287433115
		local AUTO_BLOCK_WAIT = 60
		local AUTO_BLOCK_TEST_WAIT = 5
		local ACTION_DELAY = 0.5
		local autoTimers = {}
		local autoBusy = false
		local autoStatusText = 'off'
		local paintAutoBlock
		local justLandedUntil = 0

		local function autoblockFileOn()
			if type(isfile) == 'function' and type(readfile) == 'function' then
				local ok, exists = pcall(isfile, AUTOBLOCK_PATH)
				if ok and exists then
					local okRead, body = pcall(readfile, AUTOBLOCK_PATH)
					if okRead then
						return tostring(body) == 'true'
					end
				end
			end
			return getgenv().SB2AutoBlockWanted == true
		end

		local function writeAutoblockFile(on)
			if type(writefile) ~= 'function' then
				return
			end
			pcall(function()
				if type(makefolder) == 'function' and type(isfolder) == 'function' and not isfolder('PlayerTools') then
					makefolder('PlayerTools')
				end
			end)
			pcall(writefile, AUTOBLOCK_PATH, on and 'true' or 'false')
		end

		local function setAutoStatus(text)
			autoStatusText = tostring(text or 'off')
			if type(paintAutoBlock) == 'function' then
				pcall(paintAutoBlock)
			end
		end

		local Http = game:GetService('HttpService')
		local function readHop()
			if type(readfile) == 'function' and type(isfile) == 'function' then
				local okExists, exists = pcall(isfile, AUTOBLOCK_HOP_PATH)
				if okExists and exists then
					local okRead, body = pcall(readfile, AUTOBLOCK_HOP_PATH)
					if okRead and type(body) == 'string' and body ~= '' then
						local okJson, data = pcall(function()
							return Http:JSONDecode(body)
						end)
						if okJson and type(data) == 'table' then
							return data
						end
					end
				end
			end
			return getgenv().SB2AutoBlockHop
		end

		local function writeHop(data)
			getgenv().SB2AutoBlockHop = data
			if type(writefile) ~= 'function' then
				return
			end
			pcall(function()
				if type(makefolder) == 'function' and type(isfolder) == 'function' and not isfolder('PlayerTools') then
					makefolder('PlayerTools')
				end
			end)
			local okJson, body = pcall(function()
				return Http:JSONEncode(data)
			end)
			if okJson and type(body) == 'string' then
				pcall(writefile, AUTOBLOCK_HOP_PATH, body)
			end
		end

		local function hopInProgress()
			local hop = readHop()
			return type(hop) == 'table' and hop.active == true
		end

		local function coreGui()
			local cg = game:GetService('CoreGui')
			if cloneref then
				pcall(function()
					cg = cloneref(cg)
				end)
			end
			return cg
		end

		local function coreGuiRoots()
			local roots = {}
			local seen = {}
			local function add(r)
				if r and not seen[r] then
					seen[r] = true
					roots[#roots + 1] = r
				end
			end
			-- Raw CoreGui first — cloneref sometimes hides Foundation overlay kids.
			pcall(function()
				add(game:GetService('CoreGui'))
			end)
			pcall(function()
				add(coreGui())
			end)
			pcall(function()
				if type(gethui) == 'function' then
					add(gethui())
				end
			end)
			return roots
		end

		local function buttonPlainText(obj)
			local text = ''
			pcall(function()
				text = tostring(obj.Text or '')
			end)
			if text == '' then
				pcall(function()
					text = tostring(obj.ContentText or '')
				end)
			end
			text = text:gsub('%b<>', '')
			return (string.lower(text):gsub('^%s+', ''):gsub('%s+$', ''))
		end

		local function findBlockingModal()
			-- FindFirstChild on FoundationOverlay often returns nil even when the modal is open.
			-- Scan descendants instead; skip the Settings ModuleScript copy.
			for _, root in ipairs(coreGuiRoots()) do
				local ok, descendants = pcall(function()
					return root:GetDescendants()
				end)
				if ok and type(descendants) == 'table' then
					for _, d in ipairs(descendants) do
						if d.Name == 'BlockingModalScreen' and not d:IsA('LuaSourceContainer') then
							local path = ''
							pcall(function()
								path = string.lower(d:GetFullName())
							end)
							if path:find('foundationoverlay', 1, true) or path:find('safeareaframe', 1, true) then
								return d
							end
							if not path:find('modules.settings', 1, true) and (d:IsA('GuiObject') or d:IsA('Folder')) then
								return d
							end
						end
					end
				end
			end
			return nil
		end

		-- Live Block row = FoundationOverlay ... Footer.Buttons.N (ImageButton).
		-- Prefer the small Footer row — a large dialog container also has a
		-- descendant "Block" label and its center lands on the notify text.
		local function findModalBlockButton()
			local cam = workspace.CurrentCamera
			local vp = cam and cam.ViewportSize or Vector2.new(1920, 1080)
			local best
			local bestScore = -math.huge

			local function scoreCandidate(pick, path)
				if not pick or not pick:IsA('GuiObject') then
					return
				end
				local ps = pick.AbsoluteSize
				if ps.X < 40 or ps.Y < 16 then
					return
				end
				-- Reject dialog chrome / whole-card hit targets (center = notify text).
				if ps.Y > 96 or ps.X > vp.X * 0.85 then
					return
				end
				if ps.X > vp.X * 0.7 and ps.Y > vp.Y * 0.2 then
					return
				end
				local cy = pick.AbsolutePosition.Y + ps.Y * 0.5
				-- Block row sits in the lower half of the modal / screen.
				if cy < vp.Y * 0.35 then
					return
				end
				local score = 0
				if path:find('footer', 1, true) then
					score += 80
				end
				if path:find('buttons', 1, true) then
					score += 40
				end
				if pick.Name:match('^%d+$') then
					score += 25
				end
				if pick:IsA('GuiButton') then
					score += 20
				end
				-- Prefer real button-row height (Roblox Foundation ~36–56).
				if ps.Y >= 28 and ps.Y <= 64 then
					score += 30
				elseif ps.Y <= 80 then
					score += 10
				end
				-- Prefer higher Block row over Cancel (Cancel is lower, no "block" text).
				-- Among exact-Block candidates, slightly prefer the topmost footer button.
				score += math.min(40, (cy / vp.Y) * 40)
				if path:find('footer', 1, true) then
					score -= (cy / vp.Y) * 8
				end
				-- Smaller height wins over fat wrappers.
				score -= ps.Y * 0.15
				if score > bestScore then
					bestScore = score
					best = pick
				end
			end

			local function buttonHasExactBlock(btn)
				local hasBlock = false
				local hasReport = false
				local function check(obj)
					local t = buttonPlainText(obj)
					if t == 'block' then
						hasBlock = true
					elseif t:find('report', 1, true) then
						hasReport = true
					end
				end
				check(btn)
				for _, c in ipairs(btn:GetDescendants()) do
					if c:IsA('TextLabel') or c:IsA('TextButton') then
						check(c)
					end
				end
				return hasBlock and not hasReport
			end

			for _, root in ipairs(coreGuiRoots()) do
				pcall(function()
					for _, d in ipairs(root:GetDescendants()) do
						if d:IsA('ImageButton') or d:IsA('TextButton') then
							local path = string.lower(d:GetFullName())
							if path:find('joinlogs', 1, true) or path:find('playertools', 1, true) then
								continue
							end
							if not (path:find('foundationoverlay', 1, true) or path:find('blockingmodal', 1, true)) then
								continue
							end
							if path:find('report', 1, true) then
								continue
							end
							if buttonHasExactBlock(d) then
								scoreCandidate(d, path)
							end
						end
					end
				end)
			end

			if best then
				return best
			end

			-- Fallback: exact "Block" labels → nearest GuiButton ancestor.
			for _, root in ipairs(coreGuiRoots()) do
				pcall(function()
					for _, label in ipairs(root:GetDescendants()) do
						if label:IsA('TextLabel') or label:IsA('TextButton') then
							if buttonPlainText(label) ~= 'block' then
								continue
							end
							local path = string.lower(label:GetFullName())
							if path:find('joinlogs', 1, true) or path:find('playertools', 1, true) then
								continue
							end
							if path:find('report', 1, true) then
								continue
							end
							if not (path:find('foundationoverlay', 1, true) or path:find('blockingmodal', 1, true)) then
								continue
							end
							local pick = label
							local p = label.Parent
							for _ = 1, 6 do
								if not p then
									break
								end
								if p:IsA('GuiButton') then
									pick = p
									break
								end
								p = p.Parent
							end
							scoreCandidate(pick, path)
						end
					end
				end)
			end
			return best
		end

		-- Calibrated 2026-08-16 on dyildolover (1600×877, insetY=58):
		-- mouse on Block=(809,478) vs AbsolutePosition center=(800,425.5)
		-- delta ≈ +53 Y → mousemoveabs needs AbsolutePosition + GuiInset.
		local function blockAimPoints(btn)
			if not btn or not btn:IsA('GuiObject') then
				return {}
			end
			local pos = btn.AbsolutePosition
			local size = btn.AbsoluteSize
			if size.X < 2 or size.Y < 2 then
				return {}
			end
			local GuiService = game:GetService('GuiService')
			local inset = Vector2.zero
			pcall(function()
				inset = GuiService:GetGuiInset()
			end)
			local cx = pos.X + size.X * 0.5
			local cy = pos.Y + size.Y * 0.55
			-- Primary: abs + inset (matches UserInputService:GetMouseLocation).
			local points = {
				{ x = cx + inset.X, y = cy + inset.Y, tag = 'abs+inset' },
				{ x = cx + inset.X, y = pos.Y + size.Y * 0.72 + inset.Y, tag = 'low+inset' },
				{ x = cx + inset.X, y = pos.Y + size.Y - 4 + inset.Y, tag = 'bot+inset' },
			}
			-- Raw abs only as last resorts (wrong on this client, kept for other DPI).
			points[#points + 1] = { x = cx, y = cy, tag = 'abs' }
			points[#points + 1] = { x = cx, y = cy + 53, tag = 'abs+53' }
			return points
		end

		local function blockClickCoords(btn)
			local cam = workspace.CurrentCamera
			local vs = cam and cam.ViewportSize or Vector2.new(1600, 877)
			local points = blockAimPoints(btn)
			if points[1] then
				return points[1].x, points[1].y, points[1].tag
			end
			-- Calibrated fallback when button geometry missing (norm from probe).
			return vs.X * 0.5056, vs.Y * 0.5450, 'norm'
		end

		local function fireGuiClick(btn)
			if not btn then
				return
			end
			local target = btn
			if not target:IsA('GuiButton') and target.Parent and target.Parent:IsA('GuiButton') then
				target = target.Parent
			end
			-- Walk up to Buttons.N ImageButton if we landed on a child label.
			pcall(function()
				local p = target
				for _ = 1, 6 do
					if not p then
						break
					end
					if p:IsA('ImageButton') or p:IsA('TextButton') then
						target = p
						break
					end
					p = p.Parent
				end
			end)
			if not target:IsA('GuiButton') then
				return
			end
			pcall(function()
				if typeof(target.Activate) == 'function' then
					target:Activate()
				end
			end)
			pcall(function()
				if type(firesignal) == 'function' then
					pcall(firesignal, target.Activated)
					pcall(firesignal, target.MouseButton1Click)
					pcall(firesignal, target.MouseButton1Down)
					pcall(firesignal, target.MouseButton1Up)
				end
			end)
			pcall(function()
				if type(getconnections) ~= 'function' then
					return
				end
				for _, sig in ipairs({ 'Activated', 'MouseButton1Click', 'MouseButton1Down', 'MouseButton1Up' }) do
					local ok, cons = pcall(getconnections, target[sig])
					if ok and type(cons) == 'table' then
						for _, c in ipairs(cons) do
							pcall(function()
								if c.Fire then
									c:Fire()
								elseif c.fire then
									c:fire()
								end
							end)
						end
					end
				end
			end)
		end

		local function moveAndClickAt(gx, gy)
			pcall(function()
				if type(mousemoveabs) == 'function' then
					mousemoveabs(gx, gy)
				end
			end)
			pcall(function()
				game:GetService('VirtualInputManager'):SendMouseMoveEvent(gx, gy, game)
			end)
			task.wait(0.12)
			pcall(function()
				if type(mouse1press) == 'function' and type(mouse1release) == 'function' then
					mouse1press()
					task.wait(0.07)
					mouse1release()
				elseif type(mouse1click) == 'function' then
					mouse1click()
				end
			end)
			pcall(function()
				local vim = game:GetService('VirtualInputManager')
				vim:SendMouseMoveEvent(gx, gy, game)
				vim:SendMouseButtonEvent(gx, gy, 0, true, game, 1)
				task.wait(0.07)
				vim:SendMouseButtonEvent(gx, gy, 0, false, game, 1)
			end)
		end

		local function clickBlockWithMouse(btn)
			btn = findModalBlockButton() or btn
			local points = blockAimPoints(btn)
			if #points == 0 then
				local x, y, how = blockClickCoords(btn)
				points = { { x = x, y = y, tag = how } }
			end
			Library:Notify(
				('Auto block — aim %s (%.0f, %.0f) +%d'):format(
					tostring(points[1].tag),
					points[1].x,
					points[1].y,
					math.max(0, #points - 1)
				),
				2
			)
			for i, pt in ipairs(points) do
				moveAndClickAt(pt.x, pt.y)
				fireGuiClick(btn)
				task.wait(0.18)
				-- Stop early if the modal closed.
				if not findModalBlockButton() and not findBlockingModal() then
					return true
				end
				-- Re-resolve button between tries (layout can shift).
				btn = findModalBlockButton() or btn
				if i == 1 then
					-- Keep trying remaining inset variants.
				end
			end
			local again = findModalBlockButton()
			if again then
				fireGuiClick(again)
				local pts = blockAimPoints(again)
				if pts[1] then
					moveAndClickAt(pts[1].x, pts[1].y)
				end
			end
			return true
		end

		local function confirmBlockButton(btn)
			if not btn then
				btn = findModalBlockButton()
			end
			return clickBlockWithMouse(btn)
		end

		local function armTeleport()
			getgenv().SB2AutoBlockHopping = true
			if type(getgenv().SB2CloseAllPillPanels) == 'function' then
				pcall(getgenv().SB2CloseAllPillPanels)
			end
			if type(getgenv().SB2PlayerToolsArmTeleport) == 'function' then
				pcall(getgenv().SB2PlayerToolsArmTeleport)
			end
		end

		local function startF1ThenF11Hop()
			writeAutoblockFile(true)
			getgenv().SB2AutoBlockWanted = true
			local resumeOn = false
			pcall(function()
				local t = Toggles.SoloCombatResume
				resumeOn = type(t) == 'table' and t.Value == true
			end)
			if game.PlaceId == F1_PLACE then
				writeHop({
					active = true,
					phase = 'f11',
					auto = true,
					resume = resumeOn,
					t = os.time(),
				})
				armTeleport()
				Library:Notify('Auto block — joining F11…', 4)
				pcall(function()
					TeleportService:Teleport(F11_PLACE, LocalPlayer)
				end)
				return
			end
			writeHop({
				active = true,
				phase = 'f1',
				auto = true,
				resume = resumeOn,
				t = os.time(),
			})
			armTeleport()
			Library:Notify('Auto block — joining F1, then F11…', 4)
			pcall(function()
				TeleportService:Teleport(F1_PLACE, LocalPlayer)
			end)
		end

		local function cancelAutoTimer(userId)
			userId = tonumber(userId)
			if not userId then
				return
			end
			local rec = autoTimers[userId]
			if rec then
				rec.cancelled = true
				autoTimers[userId] = nil
			end
		end

		local function cancelAllAutoTimers()
			for userId, rec in pairs(autoTimers) do
				if rec then
					rec.cancelled = true
				end
				autoTimers[userId] = nil
			end
		end

		local function soonestTimer()
			local best
			for _, rec in pairs(autoTimers) do
				if rec and not rec.cancelled then
					if not best or rec.deadline < best.deadline then
						best = rec
					end
				end
			end
			return best
		end

		local function runAutoBlockSequence(plr)
			if autoBusy or not plr or plr == LocalPlayer or isOwnAlt(plr) then
				return
			end
			if not Players:GetPlayerByUserId(plr.UserId) then
				return
			end
			autoBusy = true
			setAutoStatus('blocking ' .. tostring(plr.DisplayName or plr.Name))
			Library:Notify(('Auto block — blocking %s'):format(tostring(plr.DisplayName or plr.Name)), 5)
			local okRun, errRun = pcall(function()
				task.wait(ACTION_DELAY)
				if not Players:GetPlayerByUserId(plr.UserId) then
					return
				end
				local StarterGui = game:GetService('StarterGui')
				local opened = pcall(function()
					StarterGui:SetCore('PromptBlockPlayer', plr)
				end)
				if not opened then
					opened = pcall(function()
						StarterGui:SetCore('PromptBlockPlayer', { Player = plr })
					end)
				end
				if not opened then
					Library:Notify('Block prompt failed', 4)
					return
				end
				task.wait(0.35)
				local clicked = false
				local untilT = os.clock() + 12
				while os.clock() < untilT do
					local btn = findModalBlockButton()
					local modalUp = findBlockingModal() ~= nil or btn ~= nil
					-- Also detect via Foundation "Block" text / Prompt still open.
					if not modalUp then
						pcall(function()
							for _, d in ipairs(game:GetService('CoreGui'):GetDescendants()) do
								if (d:IsA('TextLabel') or d:IsA('TextButton')) then
									local t = buttonPlainText(d)
									if t == 'block' then
										local path = string.lower(d:GetFullName())
										if path:find('foundationoverlay', 1, true) and not path:find('report', 1, true) then
											modalUp = true
											btn = btn or (d.Parent and d.Parent:IsA('GuiButton') and d.Parent) or d
											break
										end
									end
								end
							end
						end)
					end
					if modalUp then
						clicked = clickBlockWithMouse(btn) == true
						task.wait(0.4)
						-- If modal gone, treat as success.
						if not findModalBlockButton() and not findBlockingModal() then
							clicked = true
							break
						end
						if clicked then
							break
						end
					end
					task.wait(0.12)
				end
				if not clicked then
					Library:Notify('Auto block — could not click Block (modal missing?)', 5)
					setAutoStatus('block click failed')
					return
				end
				task.wait(ACTION_DELAY)
				if not autoblockFileOn() then
					return
				end
				cancelAllAutoTimers()
				startF1ThenF11Hop()
			end)
			autoBusy = false
			if not okRun then
				setAutoStatus('error')
				Library:Notify('Auto block error: ' .. tostring(errRun), 5)
			elseif autoblockFileOn() and not hopInProgress() then
				setAutoStatus('watching')
			end
		end

		local function startAutoTimer(plr, waitSec)
			if not autoblockFileOn() or not plr or plr == LocalPlayer or isOwnAlt(plr) then
				return
			end
			if hopInProgress() then
				return
			end
			local userId = plr.UserId
			waitSec = tonumber(waitSec)
			if waitSec == nil then
				waitSec = AUTO_BLOCK_WAIT
			end
			local immediate = waitSec <= 0.05
			if autoTimers[userId] then
				if not immediate then
					return
				end
				cancelAutoTimer(userId)
			end
			local rec = {
				userId = userId,
				name = tostring(plr.DisplayName or plr.Name),
				deadline = os.clock() + math.max(0, waitSec),
				cancelled = false,
			}
			autoTimers[userId] = rec
			local function finishTimer()
				if rec.cancelled or autoTimers[userId] ~= rec then
					return
				end
				autoTimers[userId] = nil
				local still = Players:GetPlayerByUserId(userId)
				if not still then
					setAutoStatus(autoblockFileOn() and 'watching' or 'off')
					return
				end
				runAutoBlockSequence(still)
			end
			if immediate then
				setAutoStatus('blocking now · ' .. rec.name)
				Library:Notify(('Auto block now — %s (already here)'):format(rec.name), 4)
				task.spawn(function()
					local spin = os.clock() + 20
					while autoBusy and os.clock() < spin do
						if rec.cancelled or autoTimers[userId] ~= rec then
							return
						end
						task.wait(0.15)
					end
					finishTimer()
				end)
				return
			end
			Library:Notify(('Auto block in %ds — %s'):format(waitSec, rec.name), 4)
			task.spawn(function()
				while autoTimers[userId] == rec and not rec.cancelled do
					local left = rec.deadline - os.clock()
					if left <= 0 then
						break
					end
					setAutoStatus(('%ds · %s'):format(math.ceil(left), rec.name))
					task.wait(0.5)
				end
				finishTimer()
			end)
		end

		local function armAutoTimersForPresent(waitSec)
			if not autoblockFileOn() then
				return
			end
			if hopInProgress() and game.PlaceId == F1_PLACE then
				setAutoStatus('hopping F1→F11')
				return
			end
			if waitSec == nil then
				waitSec = 0
			end
			for _, plr in ipairs(Players:GetPlayers()) do
				startAutoTimer(plr, waitSec)
			end
			if not soonestTimer() then
				setAutoStatus('watching')
			end
		end

		getgenv().SB2ArmAutoBlockTimers = armAutoTimersForPresent

		local function clearHopState()
			getgenv().SB2AutoBlockHopping = nil
			writeHop({
				active = false,
				phase = 'off',
				t = os.time(),
			})
		end

		local function setAutoBlockEnabled(on, waitSec)
			on = on == true
			getgenv().SB2AutoBlockWanted = on
			writeAutoblockFile(on)
			if type(getgenv().SB2SetAutoBlock) == 'function' then
				-- JoinLogs copy; ignore errors if it is ourselves.
				pcall(function()
					if getgenv().SB2SetAutoBlock ~= setAutoBlockEnabled then
						getgenv().SB2SetAutoBlock(on)
					end
				end)
			end
			if on then
				setAutoStatus('watching')
				armAutoTimersForPresent(0)
			else
				cancelAllAutoTimers()
				clearHopState()
				setAutoStatus('off')
			end
			local t = Toggles.AutoBlockJoin
			if type(t) == 'table' and type(t.SetValue) == 'function' and t.Value ~= on then
				pcall(function()
					t:SetValue(on)
				end)
			end
			return on
		end
		getgenv().SB2SetAutoBlock = setAutoBlockEnabled

		do
			local prevAdd = getgenv().SB2AutoBlockJoinConn
			if prevAdd then
				pcall(function()
					prevAdd:Disconnect()
				end)
			end
			local prevRem = getgenv().SB2AutoBlockLeaveConn
			if prevRem then
				pcall(function()
					prevRem:Disconnect()
				end)
			end
			getgenv().SB2AutoBlockJoinConn = Players.PlayerAdded:Connect(function(plr)
				if plr == LocalPlayer then
					return
				end
				task.defer(function()
					local waitSec = AUTO_BLOCK_WAIT
					if os.clock() < justLandedUntil then
						waitSec = 0
					end
					startAutoTimer(plr, waitSec)
				end)
			end)
			getgenv().SB2AutoBlockLeaveConn = Players.PlayerRemoving:Connect(function(plr)
				if not plr or plr == LocalPlayer then
					return
				end
				cancelAutoTimer(plr.UserId)
				if autoblockFileOn() and not autoBusy and not soonestTimer() then
					setAutoStatus('watching')
				end
			end)
		end

		local function continueAfterConfig()
			-- SaveManager loads every control via task.defer — never trust toggle
			-- values until SB2SoloBlockProfileReady (set after profile re-apply).
			if not getgenv().SB2SoloBlockProfileReady then
				return
			end
			local toggleOn = false
			pcall(function()
				local t = Toggles.AutoBlockJoin
				toggleOn = type(t) == 'table' and t.Value == true
			end)
			local fileOn = false
			pcall(function()
				fileOn = autoblockFileOn() == true
			end)
			-- File/profile said ON but UI still Default=false — restore, never wipe the file.
			if not toggleOn and fileOn then
				pcall(function()
					local t = Toggles.AutoBlockJoin
					if type(t) == 'table' and type(t.SetValue) == 'function' then
						t:SetValue(true)
					end
				end)
				toggleOn = true
				getgenv().SB2AutoBlockWanted = true
			end
			if not toggleOn then
				local hop = readHop()
				if type(hop) == 'table' and hop.active == true then
					-- Mid F1→F11 hop: keep file on even if UI briefly lagged.
					writeAutoblockFile(true)
					getgenv().SB2AutoBlockWanted = true
				else
					getgenv().SB2AutoBlockWanted = false
					-- Only clear the sidecar after a real apply — never on first Default=false race.
					if getgenv().SB2SoloBlockAppliedOnce then
						writeAutoblockFile(false)
					end
					clearHopState()
					cancelAllAutoTimers()
					setAutoStatus('off')
				end
				return
			end
			task.spawn(function()
				local hop = readHop()
				if type(hop) ~= 'table' or hop.active ~= true then
					getgenv().SB2AutoBlockHopping = nil
					setAutoStatus('watching')
					armAutoTimersForPresent(0)
					Library:Notify(('Auto block armed on place %s'):format(tostring(game.PlaceId)), 5)
					return
				end
				local pid = game.PlaceId
				-- Only F1→F11 continuation. Any other floor = user is playing; drop the hop.
				if pid ~= F1_PLACE and pid ~= F11_PLACE then
					clearHopState()
					getgenv().SB2AutoBlockHopping = nil
					setAutoStatus('watching')
					armAutoTimersForPresent(0)
					return
				end
				local token = tostring(hop.phase) .. ':' .. tostring(hop.t or '')
				if getgenv().SB2AutoBlockHopHandled == token then
					return
				end
				getgenv().SB2AutoBlockHopHandled = token
				getgenv().SB2AutoBlockHopping = true
				writeAutoblockFile(true)
				getgenv().SB2AutoBlockWanted = true
				setAutoStatus('hopping F1→F11')
				local resumeOn = hop.resume == true
				if pid == F1_PLACE then
					writeHop({
						active = true,
						phase = 'f11',
						auto = true,
						resume = resumeOn,
						t = os.time(),
					})
					armTeleport()
					Library:Notify('Auto block still on — joining F11…', 5)
					pcall(function()
						TeleportService:Teleport(F11_PLACE, LocalPlayer)
					end)
					return
				end
				-- Already on F11 — finish hop, do not teleport away.
				task.wait(3)
				writeHop({
					active = false,
					phase = 'done',
					auto = true,
					resume = resumeOn,
					t = os.time(),
				})
				getgenv().SB2AutoBlockHopping = nil
				writeAutoblockFile(true)
				justLandedUntil = os.clock() + 8
				if otherPlayersPresent() then
					Library:Notify('Auto block — people already here, blocking now', 5)
					cancelAllAutoTimers()
					armAutoTimersForPresent(0)
					return
				end
				setAutoStatus('watching')
				if resumeOn then
					local okSet = false
					for _ = 1, 40 do
						okSet = getgenv().SB2SetSoloResume(true)
						if okSet then
							break
						end
						task.wait(0.25)
					end
					Library:Notify(okSet and 'Auto block still on · Resume on' or 'Auto block still on · Resume missing', 5)
				else
					Library:Notify('Auto block still on', 5)
				end
			end)
		end
		getgenv().SB2AutoBlockAfterConfig = continueAfterConfig

		return {
			fileOn = autoblockFileOn,
			writeFile = writeAutoblockFile,
			setStatus = setAutoStatus,
			armPresent = armAutoTimersForPresent,
			startTimer = startAutoTimer,
			cancelTimer = cancelAutoTimer,
			cancelAll = cancelAllAutoTimers,
			clearHop = clearHopState,
			afterConfig = continueAfterConfig,
			status = function()
				return autoStatusText
			end,
			setPaint = function(fn)
				paintAutoBlock = fn
			end,
			wait = AUTO_BLOCK_WAIT,
			testWait = AUTO_BLOCK_TEST_WAIT,
		}
		end)()

		local SoloBox = CombatTab:AddRightGroupbox('Solo resume')
		assert(SoloBox, 'Solo resume groupbox nil')
		SoloBox:AddToggle('SoloCombatResume', {
			Text = 'Resume when solo',
			Default = false,
			Tooltip = 'Turns Auto skill / Auto attack / Combat Anchor on. They still turn off if anyone joins. When you are alone again they turn back on and you TP to the selected WP. Saved with your PlayerTools profile (Save / Autoload).',
		}):OnChanged(function(value)
			-- Sidecar so autoload races can't leave Default=false after Save.
			if type(writefile) == 'function' then
				pcall(writefile, SOLO_RESUME_PATH, value and 'true' or 'false')
			end
			-- SaveManager loads via task.defer — don't TP/combat until profile apply finishes.
			if getgenv().SB2ConfigLoading then
				return
			end
			if not value then
				return
			end
			if otherPlayersPresent() then
				Library:Notify('Solo resume armed — waiting until the server is empty', 4)
				return
			end
			task.spawn(function()
				resumeSoloCombat('toggle', true)
			end)
		end)
		SoloBox:AddButton('Resume now (TP then anchor)', function()
			task.spawn(function()
				resumeSoloCombat('button', true)
			end)
		end)
		SoloBox:AddToggle('AutoBlockJoin', {
			Text = 'Auto block after 1 min',
			Default = false,
			Tooltip = '1m only if someone joins while you were already solo. Focuses this client, jumps the mouse onto Block, clicks once, then hops F1→F11. Saved with your PlayerTools profile (Save / Autoload).',
		}):OnChanged(function(value)
			getgenv().SB2AutoBlockWanted = value == true
			getgenv().SB2SoloBlockAppliedOnce = true
			AutoBlock.writeFile(value == true)
			if value then
				AutoBlock.setStatus('watching')
				AutoBlock.armPresent(0)
				Library:Notify('Auto block armed — 1m if someone joins while you are solo', 4)
			else
				AutoBlock.cancelAll()
				if type(AutoBlock.clearHop) == 'function' then
					AutoBlock.clearHop()
				end
				AutoBlock.setStatus('off')
			end
		end)
		local autoBlockLabel = SoloBox:AddLabel(AutoBlock.status())
		AutoBlock.setPaint(function()
			pcall(function()
				if autoBlockLabel and type(autoBlockLabel.SetText) == 'function' then
					autoBlockLabel:SetText(AutoBlock.status())
				elseif autoBlockLabel then
					autoBlockLabel.Text = AutoBlock.status()
				end
			end)
		end)
		SoloBox:AddButton('Test auto-block (5s)', function()
			if not AutoBlock.fileOn() then
				Library:Notify('Turn Auto block after 1 min on first', 4)
				return
			end
			local target
			for _, plr in ipairs(Players:GetPlayers()) do
				if plr ~= LocalPlayer then
					target = plr
					break
				end
			end
			if not target then
				Library:Notify('No one else here — the 5s test needs another player in this server', 5)
				return
			end
			AutoBlock.cancelTimer(target.UserId)
			AutoBlock.startTimer(target, AutoBlock.testWait)
			Library:Notify(('TEST: will block %s in 5s, then hop F1→F11'):format(target.DisplayName or target.Name), 6)
		end)

		local wpValues = listSoloWaypoints()
		local wpDefault = WP_NONE
		do
			local selected = currentSoloWaypoint()
			if selected then
				for _, name in ipairs(wpValues) do
					if name == selected then
						wpDefault = selected
						break
					end
				end
				if wpDefault == WP_NONE then
					wpValues[#wpValues + 1] = selected
					wpDefault = selected
				end
			end
		end
		SoloBox:AddDropdown('SoloResumeWaypoint', {
			Text = 'Waypoint (WP pill)',
			Values = wpValues,
			Default = wpDefault,
			AllowNull = false,
			Searchable = true,
			Tooltip = 'Click a name in the WP pill to select it, or pick it here. Used when the server is empty again.',
		})
		pcall(function()
			Options.SoloResumeWaypoint:OnChanged(function(value)
				if value == WP_NONE then
					value = nil
				end
				local setter = getgenv().SB2WaypointsSetSelected
				if type(setter) == 'function' then
					pcall(setter, value, true)
				end
			end)
		end)
		SoloBox:AddButton('Refresh waypoints', function()
			local names = listSoloWaypoints()
			if Options.SoloResumeWaypoint then
				Options.SoloResumeWaypoint:SetValues(names)
				local cur = currentSoloWaypoint()
				if cur then
					Options.SoloResumeWaypoint:SetValue(cur)
				end
			end
			Library:Notify(('Waypoints: %d'):format(math.max(0, #names - 1)))
		end)

		getgenv().SB2OnWaypointSelected = function(name)
			if not Options.SoloResumeWaypoint then
				return
			end
			local values = Options.SoloResumeWaypoint.Values or listSoloWaypoints()
			if type(name) == 'string' and name ~= '' then
				local found = false
				for _, v in ipairs(values) do
					if v == name then
						found = true
						break
					end
				end
				if not found then
					values = listSoloWaypoints()
					if not table.find(values, name) then
						values[#values + 1] = name
					end
					Options.SoloResumeWaypoint:SetValues(values)
				end
				Options.SoloResumeWaypoint:SetValue(name)
			end
		end

		do
			local prev = getgenv().SB2CombatSoloResumeConn
			if prev then
				pcall(function()
					prev:Disconnect()
				end)
			end
			getgenv().SB2CombatSoloResumeConn = Players.PlayerRemoving:Connect(function(leaver)
				if not leaver or leaver == LocalPlayer then
					return
				end
				task.defer(function()
					task.wait(0.35)
					resumeSoloCombat('empty')
				end)
			end)
		end

		getgenv().SB2SetSoloResume = function(enabled)
			local toggle = Toggles.SoloCombatResume
			if type(toggle) == 'table' and type(toggle.SetValue) == 'function' then
				pcall(function()
					toggle:SetValue(enabled == true)
				end)
				return true
			end
			return false
		end
		getgenv().SB2ResumeSoloCombat = resumeSoloCombat

		local function listComboSkills()
			local names = {}
			local seen = {}
			local add = function(skillName)
				if type(skillName) ~= 'string' or skillName == '' or seen[skillName] then
					return
				end
				if skillName == '(none)' or skillName == '(none for held weapon)' then
					return
				end
				if SKIP_UTILITY_SKILLS[skillName] then
					return
				end
				seen[skillName] = true
				names[#names + 1] = skillName
			end
			local mySkills = getLiveProfile() and getLiveProfile():FindFirstChild('Skills')
			if mySkills then
				for _, owned in ipairs(mySkills:GetChildren()) do
					add(owned.Name)
				end
			end
			for _, name in ipairs(getAvailableSkills()) do
				add(name)
			end
			for _, name in ipairs(getAvailableSupportSkills()) do
				add(name)
			end
			table.sort(names)
			return names
		end

		local function pickDefaultSkill(values, preferred)
			if table.find(values, preferred) then
				return preferred
			end
			return values[1]
		end

		local function selectedBossName()
			local opt = Options.BossComboTarget
			if type(opt) ~= 'table' then
				return nil
			end
			local ok, value = pcall(function()
				return opt.Value
			end)
			if not ok or value == nil then
				return nil
			end
			value = tostring(value)
			if value == '' or value == '(none)' then
				return nil
			end
			return value
		end

		local function mobMatchesComboBoss(mob, bossName)
			if not mob or not bossName then
				return false
			end
			if isDeadMob(mob) then
				return false
			end
			local key = normBossKey(mob.Name)
			local want = normBossKey(bossName)
			if want == '' or key == '' then
				return false
			end
			if key == want then
				return true
			end
			if #want >= 5 and string.find(key, want, 1, true) then
				return true
			end
			if #key >= 5 and string.find(want, key, 1, true) then
				return true
			end
			return false
		end

		local function fireComboSkill(skillName)
			if type(skillName) ~= 'string' or skillName == '' then
				return false
			end
			local info = getSkillInfo(skillName)
			local dur = (info.duration and info.duration > 0) and info.duration or 1.5
			getgenv().SB2SkillActiveName = skillName
			getgenv().SB2SkillActiveUntil = time() + math.max(0.8, dur)
			local ok = fireUseSkill(skillName, info, {
				muteFor = dur + 0.2,
				silentFail = true,
				ignoreGap = true,
			})
			if not ok then
				getgenv().SB2SkillActiveUntil = 0
				getgenv().SB2SkillActiveName = nil
			end
			return ok == true, dur
		end

		local comboBusy = false
		local comboSeen = {}
		local comboToken = 0

		local function runBossCombo(mob)
			if comboBusy or not mob then
				return
			end
			if not isToggleOn('BossComboEnable') then
				return
			end
			local skill1 = Options.BossComboSkill1 and Options.BossComboSkill1.Value
			local skill2 = Options.BossComboSkill2 and Options.BossComboSkill2.Value
			local skill3 = Options.BossComboSkill3 and Options.BossComboSkill3.Value
			comboBusy = true
			getgenv().SB2BossComboLock = true
			comboToken += 1
			local token = comboToken
			Library:Notify(('Boss combo — %s'):format(tostring(mob.Name)), 3)
			task.spawn(function()
				local okRun, errRun = pcall(function()
					local overlap = 0.5
					local deadline = os.clock() + 2.5
					local ok1, dur1 = false, 1.5
					while os.clock() < deadline and token == comboToken do
						ok1, dur1 = fireComboSkill(skill1)
						if ok1 then
							break
						end
						task.wait(0.08)
					end
					if not ok1 then
						Library:Notify('Boss combo: ' .. tostring(skill1) .. ' failed', 4)
						return
					end
					local wait1 = math.max(0.05, (tonumber(dur1) or 1.5) - overlap)
					task.wait(wait1)
					if token ~= comboToken or not isToggleOn('BossComboEnable') then
						return
					end
					local ok2 = fireComboSkill(skill2)
					if not ok2 then
						task.wait(0.15)
						ok2 = fireComboSkill(skill2)
					end
					task.wait(0.35)
					if token ~= comboToken or not isToggleOn('BossComboEnable') then
						return
					end
					local ok3 = fireComboSkill(skill3)
					if not ok3 then
						task.wait(0.2)
						fireComboSkill(skill3)
					end
				end)
				comboBusy = false
				getgenv().SB2BossComboLock = false
				if not okRun then
					Library:Notify('Boss combo error: ' .. tostring(errRun), 4)
				end
			end)
		end

		local function scanBossCombo()
			if not isToggleOn('BossComboEnable') then
				return
			end
			local bossName = selectedBossName()
			if not bossName then
				return
			end
			local mobs = workspace:FindFirstChild('Mobs')
			if not mobs then
				return
			end
			for inst in pairs(comboSeen) do
				if not inst or not inst.Parent then
					comboSeen[inst] = nil
				end
			end
			for _, mob in ipairs(mobs:GetChildren()) do
				if mobMatchesComboBoss(mob, bossName) and not comboSeen[mob] then
					comboSeen[mob] = true
					runBossCombo(mob)
					return
				end
			end
		end

		local ComboBox = CombatTab:AddRightGroupbox('Boss combo')
		assert(ComboBox, 'Boss combo groupbox nil')
		local bossValues = listFloorComboBosses()
		local defaultBoss = pickDefaultComboBoss(bossValues)
		ComboBox:AddDropdown('BossComboTarget', {
			Text = 'Boss',
			Values = bossValues,
			Default = defaultBoss,
			AllowNull = false,
			Searchable = true,
			Tooltip = 'Bosses on this floor only. Combo fires once when that name appears in workspace.Mobs.',
		})
		local comboSkills = listComboSkills()
		ComboBox:AddDropdown('BossComboSkill1', {
			Text = 'First (on spawn)',
			Values = comboSkills,
			Default = pickDefaultSkill(comboSkills, 'Water Blast'),
			AllowNull = false,
			Searchable = true,
		})
		ComboBox:AddDropdown('BossComboSkill2', {
			Text = 'Second (0.5s before first ends)',
			Values = comboSkills,
			Default = pickDefaultSkill(comboSkills, 'Everfrost Strike'),
			AllowNull = false,
			Searchable = true,
		})
		ComboBox:AddDropdown('BossComboSkill3', {
			Text = 'Third',
			Values = comboSkills,
			Default = pickDefaultSkill(comboSkills, 'Cursed Enhancement'),
			AllowNull = false,
			Searchable = true,
		})
		ComboBox:AddToggle('BossComboEnable', {
			Text = 'Combo on boss spawn',
			Default = false,
			Tooltip = 'Cast skill 1 the instant the selected boss is in Mobs, skill 2 ~0.5s before that ends, then skill 3.',
		}):OnChanged(function(value)
			if not value then
				comboToken += 1
				comboBusy = false
				getgenv().SB2BossComboLock = false
				local prev = getgenv().SB2BossComboScanConn
				if prev then
					pcall(function()
						prev:Disconnect()
					end)
					getgenv().SB2BossComboScanConn = nil
				end
				return
			end
			if not getgenv().SB2BossComboScanConn then
				getgenv().SB2BossComboScanConn = RunService.Heartbeat:Connect(function()
					if not isToggleOn('BossComboEnable') then
						return
					end
					local now = os.clock()
					if now - (getgenv().SB2BossComboLastScan or 0) < 0.15 then
						return
					end
					getgenv().SB2BossComboLastScan = now
					scanBossCombo()
				end)
			end
			task.defer(scanBossCombo)
		end)
		ComboBox:AddButton('Refresh bosses', function()
			refreshFloorBossDropdown(true)
		end)
		ComboBox:AddButton('Refresh skills', function()
			local names = listComboSkills()
			for _, key in ipairs({ 'BossComboSkill1', 'BossComboSkill2', 'BossComboSkill3' }) do
				if Options[key] then
					local cur = Options[key].Value
					Options[key]:SetValues(names)
					if cur and table.find(names, cur) then
						Options[key]:SetValue(cur)
					end
				end
			end
			Library:Notify(('Combo skills: %d'):format(#names))
		end)
		task.defer(function()
			refreshFloorBossDropdown(false)
		end)

		do
			local prev = getgenv().SB2BossComboScanConn
			if prev then
				pcall(function()
					prev:Disconnect()
				end)
				getgenv().SB2BossComboScanConn = nil
			end
			local prevAdd = getgenv().SB2BossComboAddConn
			if prevAdd then
				pcall(function()
					prevAdd:Disconnect()
				end)
			end
			local mobs = workspace:FindFirstChild('Mobs')
			if mobs then
				getgenv().SB2BossComboAddConn = mobs.ChildAdded:Connect(function(mob)
					task.defer(function()
						if not isToggleOn('BossComboEnable') then
							return
						end
						local bossName = selectedBossName()
						if mobMatchesComboBoss(mob, bossName) and not comboSeen[mob] then
							comboSeen[mob] = true
							runBossCombo(mob)
						end
					end)
				end)
			end
		end
		end)()

	-- Inventory tab (stations / remote upgrade).
	do
		if type(getgenv().SB2InvFilterCleanup) == 'function' then
			pcall(getgenv().SB2InvFilterCleanup)
		end
		do
			local inventoryUI = RequiredServices and RequiredServices.InventoryUI
			local original = getgenv().SB2OrigGetInventoryData
			if inventoryUI and type(original) == 'function' then
				pcall(function()
					inventoryUI.GetInventoryData = original
				end)
			end
			getgenv().SB2InvFilterCleanup = nil
			getgenv().SB2ApplyInvLevelFilter = nil
			getgenv().SB2ApplySavedInvFilter = nil
		end

		local InvTab = Window:AddTab('Inventory', 'package')

		-- Stations + remote upgrade (CardinalUI Upgrade remote / openUpgrade).
		local StationsBox = InvTab:AddRightGroupbox('Stations')
		assert(StationsBox, 'Stations groupbox nil')

		local function openUiStation(methodName, label)
			local ui = RequiredServices and RequiredServices.UI
			local fn = ui and ui[methodName]
			if type(fn) ~= 'function' then
				Library:Notify(label .. ' unavailable (UI services missing)')
				return
			end
			local ok, err = pcall(fn)
			if not ok then
				Library:Notify(('Failed to open %s: %s'):format(label, tostring(err)))
			end
		end

		StationsBox:AddLabel('Opens the in-game UIs from anywhere (no blacksmith NPC).')
		StationsBox:AddButton('Open upgrade', function()
			openUiStation('openUpgrade', 'Upgrade')
		end)
		StationsBox:AddButton('Open dismantle', function()
			openUiStation('openDismantle', 'Dismantle')
		end)
		StationsBox:AddButton('Open crystal forge', function()
			openUiStation('openCrystalForge', 'Crystal forge')
		end)

		local UpgradeBox = InvTab:AddRightGroupbox('Remote upgrade')
		assert(UpgradeBox, 'Remote upgrade groupbox nil')

		local UPGRADE_MAX = {
			Common = 10,
			Uncommon = 10,
			Rare = 15,
			Legendary = 20,
			Tribute = 20,
			Burst = 25,
		}
		local UPGRADE_CRYSTAL = {
			Common = 'Common Upgrade Crystal',
			Uncommon = 'Uncommon Upgrade Crystal',
			Rare = 'Rare Upgrade Crystal',
			Legendary = 'Legendary Upgrade Crystal',
			Tribute = 'Tribute Upgrade Crystal',
			Burst = 'Burst Upgrade Crystal',
		}

		local upgradeItemMap = {}
		local upgradeItemLabels = {}

		local function getInventoryFolder()
			return getLiveProfile() and getLiveProfile():FindFirstChild('Inventory')
		end

		local function getItemsDatabase()
			local database = game:GetService('ReplicatedStorage'):FindFirstChild('Database')
			return database and database:FindFirstChild('Items')
		end

		local function getItemRarityAndType(item)
			local itemsDb = getItemsDatabase()
			local db = itemsDb and itemsDb:FindFirstChild(item.Name)
			if not db then
				return nil, nil
			end
			local rarity = db:FindFirstChild('Rarity') and db.Rarity.Value or nil
			local typ = db:FindFirstChild('Type') and db.Type.Value or nil
			return rarity, typ
		end

		local function getDbItem(item)
			local itemsDb = getItemsDatabase()
			return itemsDb and item and itemsDb:FindFirstChild(item.Name)
		end

		local function isStarredOrUnupgradable(item)
			local stats = (item and item:FindFirstChild('Stats')) or nil
			local db = getDbItem(item)
			local dbStats = db and db:FindFirstChild('Stats')
			local function upgradeStat(folder, name)
				local v = folder and folder:FindFirstChild(name)
				if v and v:IsA('ValueBase') and type(v.Value) == 'number' then
					return v.Value
				end
				return nil
			end
			-- Starred / unupgradable equipment uses DamageUpgrade (or DefenseUpgrade) <= 0
			-- on Database.Items. Stats on the inventory copy is often missing (IntValues).
			local dmg = upgradeStat(stats, 'DamageUpgrade')
			if dmg == nil then
				dmg = upgradeStat(dbStats, 'DamageUpgrade')
			end
			local def = upgradeStat(stats, 'DefenseUpgrade')
			if def == nil then
				def = upgradeStat(dbStats, 'DefenseUpgrade')
			end
			if dmg ~= nil and dmg <= 0 then
				return true
			end
			if def ~= nil and def <= 0 then
				return true
			end
			if db and (db:FindFirstChild('Unupgradable') or db:FindFirstChild('Unupgradeable') or db:FindFirstChild('Starred')) then
				return true
			end
			if item and (item:FindFirstChild('Unupgradable') or item:FindFirstChild('Unupgradeable') or item:FindFirstChild('Starred')) then
				return true
			end
			return false
		end

		local function canUpgradeItem(item)
			if not (item and item.Parent) then
				return false, nil, 0, nil
			end
			local rarity, typ = getItemRarityAndType(item)
			if not rarity or (typ ~= 'Weapon' and typ ~= 'Clothing') then
				return false, rarity, 0, nil
			end
			if isStarredOrUnupgradable(item) then
				return false, rarity, 0, nil
			end
			local maxUp = UPGRADE_MAX[rarity]
			if not maxUp then
				return false, rarity, 0, nil
			end
			local upgrade = item:FindFirstChild('Upgrade') and item.Upgrade.Value or 0
			return upgrade < maxUp, rarity, upgrade, maxUp
		end

		local function refreshUpgradeItemList(silent)
			table.clear(upgradeItemMap)
			table.clear(upgradeItemLabels)
			local inv = getInventoryFolder()
			if inv then
				local idx = 0
				for _, item in ipairs(inv:GetChildren()) do
					local okUp, rarity, upgrade, maxUp = canUpgradeItem(item)
					if okUp then
						idx += 1
						local label = ('%s +%d/%d (%s) #%d'):format(
							item.Name,
							upgrade,
							maxUp,
							rarity,
							idx
						)
						upgradeItemMap[label] = item
						upgradeItemLabels[#upgradeItemLabels + 1] = label
					end
				end
				table.sort(upgradeItemLabels)
			end
			if Options.RemoteUpgradeItem then
				Options.RemoteUpgradeItem:SetValues(upgradeItemLabels)
				local cur = Options.RemoteUpgradeItem.Value
				if cur and not upgradeItemMap[cur] then
					Options.RemoteUpgradeItem:SetValue(nil)
				end
			end
			if not silent then
				Library:Notify(('Upgrade list: %d items'):format(#upgradeItemLabels))
			end
		end

		UpgradeBox:AddDropdown('RemoteUpgradeItem', {
			Text = 'Equipment',
			Values = upgradeItemLabels,
			AllowNull = true,
			Searchable = true,
		})

		UpgradeBox:AddSlider('RemoteUpgradeCrystals', {
			Text = 'Crystals per batch',
			Default = 25,
			Min = 1,
			Max = 25,
			Rounding = 0,
			Tooltip = 'Max uses this many per FireServer (capped by remaining / owned) until the item is maxed.',
		})

		UpgradeBox:AddSlider('RemoteUpgradeScrolls', {
			Text = 'Protection scrolls / batch',
			Default = 0,
			Min = 0,
			Max = 25,
			Rounding = 0,
			Tooltip = '0 = risky. Match crystals if you want fails not to downgrade.',
		})

		UpgradeBox:AddButton('Refresh equipment list', function()
			refreshUpgradeItemList(false)
		end)

		local remoteUpgradeBusy = false
		local upgradeModuleRef -- game UI.Upgrade table (Open/Close/OnUpgradeCompleted)

		local function getPlayerUI()
			local pg = LocalPlayer:FindFirstChild('PlayerGui')
			local cardinal = pg and pg:FindFirstChild('CardinalUI')
			return cardinal and cardinal:FindFirstChild('PlayerUI')
		end

		local function getUpgradeGui()
			local playerUI = getPlayerUI()
			return playerUI and playerUI:FindFirstChild('Upgrade')
		end

		local function findUpgradeModule()
			if upgradeModuleRef and type(upgradeModuleRef.Close) == 'function' then
				return upgradeModuleRef
			end
			pcall(function()
				for _, obj in ipairs(getgc(true)) do
					if type(obj) == 'table'
						and type(rawget(obj, 'Open')) == 'function'
						and type(rawget(obj, 'Close')) == 'function'
						and type(rawget(obj, 'Confirm')) == 'function'
						and type(rawget(obj, 'OnUpgradeCompleted')) == 'function'
					then
						upgradeModuleRef = obj
						break
					end
				end
			end)
			return upgradeModuleRef
		end

		local function dismissUpgradeNotifications()
			local playerUI = getPlayerUI()
			if not playerUI then
				return
			end
			-- Live result modals are cloned as PlayerUI.Notification (multiple allowed).
			for _, child in ipairs(playerUI:GetChildren()) do
				if child.Name ~= 'Notification' or child == playerUI:FindFirstChild('Templates') then
					-- continue
				else
					local isUpgradeModal = false
					pcall(function()
						local title = child:FindFirstChild('Title', true)
						local msg = child:FindFirstChild('Message', true)
						local text = (title and title:IsA('TextLabel') and title.Text) or ''
						local message = (msg and msg:IsA('TextLabel') and msg.Text) or ''
						if text:find('Upgrade', 1, true)
							or message:find('→', 1, true)
							or text:find('Not A Failure', 1, true)
						then
							isUpgradeModal = true
						end
						-- Empty / broken black frames left over from suppress also go.
						if child:IsA('GuiObject') and child.Visible then
							local frame = child:FindFirstChild('Frame') or child
							if frame:IsA('GuiObject') and frame.BackgroundTransparency < 0.3 then
								local bg = frame.BackgroundColor3
								if bg.R < 0.12 and bg.G < 0.12 and bg.B < 0.12 then
									isUpgradeModal = true
								end
							end
						end
					end)
					if isUpgradeModal or child.Name == 'Notification' then
						-- Prefer clicking Okay so game cleanup runs; else destroy.
						local clicked = false
						pcall(function()
							local confirm = child:FindFirstChild('Confirm', true)
							if confirm and confirm:IsA('GuiButton') then
								firesignal(confirm.MouseButton1Click)
								clicked = true
							end
						end)
						pcall(function()
							child.Visible = false
							for _, sub in ipairs(child:GetChildren()) do
								sub:Destroy()
							end
							-- Don't destroy the persistent Notification host if game reuses it;
							-- clearing children is enough. Extra hosts can be destroyed.
							if child.Parent and #child:GetChildren() == 0 and child.Visible == false then
								-- leave empty host; hide only
							end
						end)
					end
				end
			end
		end

		local function closeUpgradeUiHard()
			local mod = findUpgradeModule()
			if mod then
				pcall(mod.Close, true)
			end
			local upgradeGui = getUpgradeGui()
			if upgradeGui then
				pcall(function()
					upgradeGui.Visible = false
				end)
			end
			local ui = RequiredServices and RequiredServices.UI
			if ui then
				pcall(function()
					if ui.InventoryMenu and type(ui.InventoryMenu.Close) == 'function' then
						ui.InventoryMenu.Close()
					end
				end)
			end
			dismissUpgradeNotifications()
			pcall(function()
				for _, b in ipairs(game:GetService('Lighting'):GetChildren()) do
					if b:IsA('BlurEffect') and b.Name == 'MenuBlur' then
						b.Size = 0
						b.Enabled = false
					end
				end
			end)
		end

		local function withUpgradeUiSuppressed(fn)
			local ui = RequiredServices and RequiredServices.UI
			local savedOpen = ui and ui.openUpgrade
			local mod = findUpgradeModule()
			local savedModOpen = mod and mod.Open
			local savedOnDone = mod and mod.OnUpgradeCompleted
			local upgradeGui = getUpgradeGui()
			local hideConn
			local notifConn

			if ui and type(savedOpen) == 'function' then
				ui.openUpgrade = function()
					closeUpgradeUiHard()
				end
			end

			-- Don't reopen the station after each batch, and skip the Okay modal.
			if mod then
				if type(savedModOpen) == 'function' then
					mod.Open = function()
						closeUpgradeUiHard()
					end
				end
				if type(savedOnDone) == 'function' then
					mod.OnUpgradeCompleted = function(...)
						-- Swallow success/fail modal; still allow sounds if cheap.
						task.defer(dismissUpgradeNotifications)
						task.defer(closeUpgradeUiHard)
					end
				end
			end

			if upgradeGui then
				pcall(function()
					upgradeGui.Visible = false
				end)
				hideConn = upgradeGui:GetPropertyChangedSignal('Visible'):Connect(function()
					if upgradeGui.Visible then
						closeUpgradeUiHard()
					end
				end)
			end

			local playerUI = getPlayerUI()
			if playerUI then
				notifConn = playerUI.ChildAdded:Connect(function(child)
					if child.Name == 'Notification' then
						task.defer(dismissUpgradeNotifications)
					end
				end)
			end

			local ok, err = pcall(fn)

			if hideConn then
				pcall(function()
					hideConn:Disconnect()
				end)
			end
			if notifConn then
				pcall(function()
					notifConn:Disconnect()
				end)
			end
			if ui and savedOpen then
				ui.openUpgrade = savedOpen
			end
			if mod then
				if savedModOpen then
					mod.Open = savedModOpen
				end
				if savedOnDone then
					mod.OnUpgradeCompleted = savedOnDone
				end
			end
			closeUpgradeUiHard()

			if not ok then
				return false, err
			end
			return true
		end

		local function waitForUpgradeSettle(item, beforeLevel, timeout)
			timeout = timeout or 2.5
			local deadline = os.clock() + timeout
			local signaled = false
			local conns = {}

			local function mark()
				signaled = true
			end

			local upgradeVal = item:FindFirstChild('Upgrade')
			if upgradeVal and upgradeVal:IsA('ValueBase') then
				conns[#conns + 1] = upgradeVal.Changed:Connect(mark)
			end
			conns[#conns + 1] = item.ChildAdded:Connect(function(child)
				if child.Name == 'Upgrade' then
					mark()
					conns[#conns + 1] = child.Changed:Connect(mark)
				end
			end)
			conns[#conns + 1] = item.ChildRemoved:Connect(function(child)
				if child.Name == 'Upgrade' then
					mark()
				end
			end)

			while os.clock() < deadline do
				dismissUpgradeNotifications()
				if signaled then
					task.wait(0.08)
					break
				end
				local now = item:FindFirstChild('Upgrade') and item.Upgrade.Value or 0
				if now ~= beforeLevel then
					break
				end
				task.wait(0.05)
			end

			for _, c in ipairs(conns) do
				pcall(function()
					c:Disconnect()
				end)
			end

			local after = item:FindFirstChild('Upgrade') and item.Upgrade.Value or 0
			return after ~= beforeLevel, after
		end

		StationsBox:AddButton('Close stuck upgrade UI', function()
			closeUpgradeUiHard()
			Library:Notify('Closed upgrade / result overlays')
		end)

		UpgradeBox:AddButton('Max upgrade', function()
			if remoteUpgradeBusy then
				Library:Notify('Already maxing an item')
				return
			end

			local label = Options.RemoteUpgradeItem and Options.RemoteUpgradeItem.Value
			local item = label and upgradeItemMap[label]
			if not item or not item.Parent then
				Library:Notify('Select equipment first (refresh if stale)')
				refreshUpgradeItemList(true)
				return
			end

			local okUp, rarity, upgrade, maxUp = canUpgradeItem(item)
			if not okUp then
				Library:Notify('That item cannot be upgraded further')
				refreshUpgradeItemList(true)
				return
			end

			local Event = game:GetService('ReplicatedStorage'):FindFirstChild('Event')
			if not Event then
				Library:Notify('ReplicatedStorage.Event missing')
				return
			end

			local crystalName = UPGRADE_CRYSTAL[rarity]
			local batchCrystals = Options.RemoteUpgradeCrystals and Options.RemoteUpgradeCrystals.Value or 25
			batchCrystals = math.clamp(math.floor(tonumber(batchCrystals) or 25), 1, 25)
			local batchScrolls = Options.RemoteUpgradeScrolls and Options.RemoteUpgradeScrolls.Value or 0
			batchScrolls = math.max(0, math.floor(tonumber(batchScrolls) or 0))

			remoteUpgradeBusy = true
			Library:Notify(('Maxing %s (+%d → +%d)…'):format(item.Name, upgrade, maxUp))

			task.spawn(function()
				local okRun, errRun = withUpgradeUiSuppressed(function()
					local rounds = 0
					local stagnant = 0
					while item.Parent and rounds < 80 do
						rounds += 1
						dismissUpgradeNotifications()

						local still, curRarity, curUp, curMax = canUpgradeItem(item)
						if not still then
							break
						end

						local inv = getInventoryFolder()
						local crystal = inv and inv:FindFirstChild(crystalName)
						if not crystal then
							Library:Notify('Out of ' .. tostring(crystalName))
							break
						end
						local ownedCrystals = crystal:FindFirstChild('Count') and crystal.Count.Value or 1
						local wantCrystals = math.min(batchCrystals, ownedCrystals, curMax - curUp)
						if wantCrystals < 1 then
							Library:Notify('Not enough crystals to continue')
							break
						end

						local wantScrolls = 0
						if batchScrolls > 0 then
							local scroll = inv:FindFirstChild('Upgrade Protection Scroll')
							local ownedScrolls = scroll
									and (scroll:FindFirstChild('Count') and scroll.Count.Value or 1)
								or 0
							if ownedScrolls < 1 then
								Library:Notify('Out of protection scrolls — stopping')
								break
							end
							wantScrolls = math.min(batchScrolls, ownedScrolls, wantCrystals, 25)
						end

						local before = curUp
						local okFire, errFire = pcall(function()
							Event:FireServer('Equipment', {
								'Upgrade',
								item,
								wantCrystals,
								wantScrolls,
							})
						end)
						if not okFire then
							Library:Notify('Upgrade fire failed: ' .. tostring(errFire))
							break
						end

						local changed = waitForUpgradeSettle(item, before, 2.8)
						dismissUpgradeNotifications()
						local mod = findUpgradeModule()
						if mod then
							pcall(mod.Close, true)
						end

						if not changed then
							stagnant += 1
							if stagnant >= 3 then
								Library:Notify('Upgrade stalled (no level change) — stopped')
								break
							end
							task.wait(0.35)
						else
							stagnant = 0
						end

						task.wait(0.12)
					end
				end)

				remoteUpgradeBusy = false
				closeUpgradeUiHard()
				refreshUpgradeItemList(true)

				if not okRun then
					Library:Notify('Max upgrade error: ' .. tostring(errRun))
					return
				end

				local finalUp = item and item.Parent and item:FindFirstChild('Upgrade') and item.Upgrade.Value or upgrade
				local _, _, _, finalMax = canUpgradeItem(item)
				if item and item.Parent and finalMax and finalUp >= finalMax then
					Library:Notify(('Maxed %s at +%d'):format(item.Name, finalUp))
				elseif item and item.Parent then
					Library:Notify(('Stopped %s at +%d (not max)'):format(item.Name, finalUp))
				else
					Library:Notify('Upgrade finished (item gone from inventory?)')
				end

				task.spawn(function()
					for _ = 1, 25 do
						closeUpgradeUiHard()
						task.wait(0.04)
					end
				end)
			end)
		end)

		task.defer(function()
			refreshUpgradeItemList(true)
		end)

		local DismantleBox = InvTab:AddRightGroupbox('Remote dismantle')
		assert(DismantleBox, 'Remote dismantle groupbox nil')

		local DISMANTLE_TYPES = {
			Weapon = true,
			Clothing = true,
			Accessory = true,
		}
		local dismantleLabelMap = {} -- label -> item Name
		local dismantleLabels = {}
		local remoteDismantleBusy = false
		local dismantleSearchToken = 0

		local function equippedIdSet()
			local set = {}
			local equip = getLiveProfile() and getLiveProfile():FindFirstChild('Equip')
			if not equip then
				return set
			end
			for _, slot in ipairs(equip:GetChildren()) do
				if slot:IsA('ValueBase') then
					local v = slot.Value
					if type(v) == 'number' and v ~= 0 then
						set[v] = true
					elseif type(v) == 'string' and v ~= '' and v ~= '0' then
						set[v] = true
						set[tonumber(v) or v] = true
					end
				end
			end
			return set
		end

		local function itemNumericId(item)
			if item:IsA('ValueBase') then
				return item.Value
			end
			local id = item:FindFirstChild('ID') or item:FindFirstChild('Id')
			if id and id:IsA('ValueBase') then
				return id.Value
			end
			return nil
		end

		local function canDismantleItem(item, equipped)
			if not (item and item.Parent) then
				return false
			end
			if item:FindFirstChild('Undismantleable') then
				return false
			end
			local rarity, typ = getItemRarityAndType(item)
			if not DISMANTLE_TYPES[typ] then
				return false
			end
			local itemsDb = getItemsDatabase()
			local db = itemsDb and itemsDb:FindFirstChild(item.Name)
			if db and db:FindFirstChild('Undismantleable') then
				return false
			end
			local id = itemNumericId(item)
			if id ~= nil and equipped[id] then
				return false
			end
			return true, rarity, typ
		end

		local function countInventoryName(name)
			local n = 0
			local inv = getInventoryFolder()
			if not inv or type(name) ~= 'string' then
				return 0
			end
			for _, item in ipairs(inv:GetChildren()) do
				if item.Name == name then
					n += 1
				end
			end
			return n
		end

		local function collectDismantleableByName(name)
			local out = {}
			local inv = getInventoryFolder()
			if not inv or type(name) ~= 'string' or name == '' then
				return out
			end
			local equipped = equippedIdSet()
			for _, item in ipairs(inv:GetChildren()) do
				if item.Name == name then
					if canDismantleItem(item, equipped) then
						out[#out + 1] = item
					end
				end
			end
			return out
		end

		local function refreshDismantleNameList(query, silent)
			table.clear(dismantleLabelMap)
			table.clear(dismantleLabels)
			query = string.lower(tostring(query or ''):gsub('^%s+', ''):gsub('%s+$', ''))
			local inv = getInventoryFolder()
			local equipped = equippedIdSet()
			local counts = {}
			if inv then
				for _, item in ipairs(inv:GetChildren()) do
					local ok, rarity, typ = canDismantleItem(item, equipped)
					if ok then
						if query == '' or string.find(string.lower(item.Name), query, 1, true) then
							local rec = counts[item.Name]
							if not rec then
								rec = { count = 0, rarity = rarity, typ = typ }
								counts[item.Name] = rec
							end
							rec.count += 1
						end
					end
				end
			end
			local names = {}
			for name in pairs(counts) do
				names[#names + 1] = name
			end
			table.sort(names, function(a, b)
				if counts[a].count ~= counts[b].count then
					return counts[a].count > counts[b].count
				end
				return a < b
			end)
			local cap = query == '' and 80 or 120
			for i, name in ipairs(names) do
				if i > cap then
					break
				end
				local rec = counts[name]
				local label = ('%s  x%d  %s %s'):format(
					name,
					rec.count,
					tostring(rec.rarity or ''),
					tostring(rec.typ or '')
				)
				dismantleLabelMap[label] = name
				dismantleLabels[#dismantleLabels + 1] = label
			end
			if Options.RemoteDismantleItem then
				Options.RemoteDismantleItem:SetValues(dismantleLabels)
				local cur = Options.RemoteDismantleItem.Value
				if cur and not dismantleLabelMap[cur] then
					if #dismantleLabels == 1 then
						Options.RemoteDismantleItem:SetValue(dismantleLabels[1])
					else
						Options.RemoteDismantleItem:SetValue(nil)
					end
				elseif not cur and #dismantleLabels == 1 then
					Options.RemoteDismantleItem:SetValue(dismantleLabels[1])
				end
			end
			if not silent then
				Library:Notify(('Dismantle matches: %d names'):format(#dismantleLabels))
			end
		end

		DismantleBox:AddLabel('Sends 25 single-item dismantles per burst (same payload as the game UI). Stops when the keep count remains.')

		DismantleBox:AddInput('RemoteDismantleQuery', {
			Text = 'Name contains',
			Default = '',
			Placeholder = 'e.g. Alaric',
			Finished = false,
			ClearTextOnFocus = false,
			AllowEmpty = true,
			Callback = function(value)
				dismantleSearchToken += 1
				local token = dismantleSearchToken
				task.delay(0.12, function()
					if token == dismantleSearchToken then
						refreshDismantleNameList(value, true)
					end
				end)
			end,
		})

		DismantleBox:AddDropdown('RemoteDismantleItem', {
			Text = 'Item',
			Values = dismantleLabels,
			AllowNull = true,
			Searchable = true,
		})

		DismantleBox:AddInput('RemoteDismantleAmount', {
			Text = 'Amount',
			Default = '1',
			Numeric = true,
			Finished = false,
			ClearTextOnFocus = false,
			AllowEmpty = false,
			Placeholder = '150',
			Tooltip = 'How many copies to dismantle (capped by how many you own).',
		})

		DismantleBox:AddButton('Refresh list', function()
			local q = Options.RemoteDismantleQuery and Options.RemoteDismantleQuery.Value or ''
			refreshDismantleNameList(q, false)
		end)

		DismantleBox:AddButton('Dismantle amount', function()
			if remoteDismantleBusy then
				Library:Notify('Already dismantling')
				return
			end
			local label = Options.RemoteDismantleItem and Options.RemoteDismantleItem.Value
			local name = label and dismantleLabelMap[label]
			if not name then
				Library:Notify('Select an item (search Alaric, then pick it)')
				return
			end
			local want = tonumber(Options.RemoteDismantleAmount and Options.RemoteDismantleAmount.Value)
			want = math.floor(tonumber(want) or 0)
			if want < 1 then
				Library:Notify('Amount must be at least 1')
				return
			end

			local pool = collectDismantleableByName(name)
			if #pool == 0 then
				Library:Notify('No dismantleable copies of ' .. name)
				refreshDismantleNameList(Options.RemoteDismantleQuery and Options.RemoteDismantleQuery.Value or '', true)
				return
			end
			if want > #pool then
				want = #pool
			end

			-- Keepers are never sent. Official remote is one item per fire:
			-- Event:FireServer('Equipment', { 'Dismantle', { item } })
			-- A 25-item table in one fire was wiping the copies we meant to keep.
			local targets = {}
			local keeperSet = {}
			for i = 1, want do
				targets[i] = pool[i]
			end
			for i = want + 1, #pool do
				local item = pool[i]
				keeperSet[item] = true
				local id = itemNumericId(item)
				if id ~= nil then
					keeperSet[id] = true
				end
			end
			local keep = #pool - want
			local totalAtStart = countInventoryName(name)
			local stopAt = math.max(0, totalAtStart - want)

			local Event = game:GetService('ReplicatedStorage'):FindFirstChild('Event')
			if not Event then
				Library:Notify('ReplicatedStorage.Event missing')
				return
			end

			local function isKeeper(item)
				if not item then
					return true
				end
				if keeperSet[item] then
					return true
				end
				local id = itemNumericId(item)
				return id ~= nil and keeperSet[id] == true
			end

			remoteDismantleBusy = true
			if keep > 0 then
				Library:Notify(('Dismantling %d of %d × %s (keeping %d)…'):format(want, #pool, name, keep))
			else
				Library:Notify(('Dismantling %d × %s…'):format(want, name))
			end

			task.spawn(function()
				local okRun, errRun = pcall(function()
					local BATCH = 25
					local i = 1
					local sent = 0
					while i <= #targets do
						local left = countInventoryName(name)
						if left <= stopAt then
							break
						end
						local burst = 0
						local before = left
						while i <= #targets and burst < BATCH do
							local item = targets[i]
							i += 1
							if not (item and item.Parent) then
								continue
							end
							if isKeeper(item) then
								continue
							end
							local okFire, errFire = pcall(function()
								Event:FireServer('Equipment', {
									'Dismantle',
									{ item },
								})
							end)
							if not okFire then
								error(errFire)
							end
							burst += 1
							sent += 1
							task.wait(0.03)
						end
						if burst == 0 then
							break
						end
						local deadline = os.clock() + 5
						while os.clock() < deadline do
							left = countInventoryName(name)
							if left <= stopAt or left <= before - burst then
								break
							end
							task.wait(0.08)
						end
						left = countInventoryName(name)
						Library:Notify(('Dismantled %d/%d × %s (%d left)'):format(
							math.max(0, totalAtStart - left),
							want,
							name,
							left
						))
						if left <= stopAt then
							break
						end
						task.wait(0.08)
					end
					task.wait(0.25)
					local left = countInventoryName(name)
					Library:Notify(('Dismantled %d × %s (%d left)'):format(
						math.max(0, totalAtStart - left),
						name,
						left
					))
				end)
				remoteDismantleBusy = false
				local q = Options.RemoteDismantleQuery and Options.RemoteDismantleQuery.Value or ''
				refreshDismantleNameList(q, true)
				if not okRun then
					Library:Notify('Dismantle error: ' .. tostring(errRun))
				end
			end)
		end)

		task.defer(function()
			refreshDismantleNameList('', true)
		end)
	end

	-- ── Items: snapshot Database.Items so a patch only shows NEW names ──
	do
		local HttpService = game:GetService('HttpService')
		local NONE = '(none)'
		local SEARCH_HINT = '(type to search)'
		local lastAdded = {}
		local lastRemoved = {}
		local liveCache = {} -- name -> { rarity, type, class, level }
		local liveNames = {}
		local searchToken = 0
		local chestSearchToken = 0
		local allAuraChests = {}

		local function copyText(text)
			if type(setclipboard) == 'function' then
				local ok = pcall(setclipboard, text)
				if ok then
					return true
				end
			end
			if type(toclipboard) == 'function' then
				return pcall(toclipboard, text)
			end
			return false
		end

		local function ensureItemsFolder()
			if type(writefile) ~= 'function' then
				return false
			end
			local folder = CONFIG.ConfigFolder
			if folder ~= '' and folder ~= '.' and type(makefolder) == 'function' and type(isfolder) == 'function' then
				if not isfolder(folder) then
					pcall(makefolder, folder)
				end
			end
			return true
		end

		local function valueOf(folder, name)
			local v = folder:FindFirstChild(name)
			if v and v:IsA('ValueBase') then
				return v.Value
			end
			local stats = folder:FindFirstChild('Stats')
			if stats then
				local nested = stats:FindFirstChild(name)
				if nested and nested:IsA('ValueBase') then
					return nested.Value
				end
			end
			return nil
		end

		local function recFromFolder(folder)
			local level = valueOf(folder, 'Level')
			if type(level) ~= 'number' then
				level = tonumber(level)
			end
			return {
				rarity = tostring(valueOf(folder, 'Rarity') or ''),
				type = tostring(valueOf(folder, 'Type') or ''),
				class = tostring(valueOf(folder, 'Class') or ''),
				level = level,
			}
		end

		local function formatRec(name, rec)
			if not rec then
				return name
			end
			local bits = { name }
			if rec.rarity ~= '' then
				bits[#bits + 1] = rec.rarity
			end
			if rec.type ~= '' then
				bits[#bits + 1] = rec.type
			end
			if rec.class ~= '' and rec.class ~= rec.type then
				bits[#bits + 1] = rec.class
			end
			if rec.level ~= nil and rec.level ~= '' then
				bits[#bits + 1] = 'Lv ' .. tostring(rec.level)
			end
			return table.concat(bits, ' · ')
		end

		local function getDatabase()
			return game:GetService('ReplicatedStorage'):FindFirstChild('Database')
		end

		local function getItemsFolder()
			local db = getDatabase()
			return db and db:FindFirstChild('Items')
		end

		local function getCashShop()
			local db = getDatabase()
			return db and db:FindFirstChild('CashShop')
		end

		local function getItemFolder(name)
			local items = getItemsFolder()
			return items and name and items:FindFirstChild(name)
		end

		local function extractAssetId(texture)
			if type(texture) ~= 'string' or texture == '' then
				return nil
			end
			return texture:match('id=(%d+)') or texture:match('rbxassetid://(%d+)') or texture:match('(%d+)')
		end

		local function iconIdOf(folder)
			if not folder then
				return nil
			end
			local aid = folder:FindFirstChild('AssetId')
			if aid and aid:IsA('ValueBase') and tostring(aid.Value) ~= '' then
				return tostring(aid.Value)
			end
			local icon = folder:FindFirstChild('Icon')
			if icon and icon:IsA('Decal') then
				return extractAssetId(icon.Texture)
			end
			return nil
		end

		local function formatRatio(n)
			if type(n) ~= 'number' then
				return tostring(n)
			end
			local raw = string.format('%.2f', n):gsub('0+$', ''):gsub('%.$', '')
			if raw == '-0' then
				raw = '0'
			end
			local pct = n * 100
			local pctStr
			if math.abs(pct - math.floor(pct + 0.5)) < 0.05 then
				pctStr = tostring(math.floor(pct + 0.5))
			else
				pctStr = string.format('%.1f', pct):gsub('0+$', ''):gsub('%.$', '')
			end
			return raw .. ' (' .. pctStr .. '%)'
		end

		local function prettyStatName(name)
			return tostring(name):gsub('(%l)(%u)', '%1 %2'):gsub('(%u)(%u%l)', '%1 %2')
		end

		local function readValueMap(container)
			local map = {}
			if not container then
				return map
			end
			for _, child in ipairs(container:GetChildren()) do
				if child:IsA('ValueBase') then
					map[child.Name] = child.Value
				end
			end
			return map
		end

		local FLAG_NAMES = { 'Untradeable', 'Undeletable', 'Undismantleable' }

		local function readFlags(folder)
			local flags = {}
			if not folder then
				return flags
			end
			for _, name in ipairs(FLAG_NAMES) do
				if folder:FindFirstChild(name) then
					flags[#flags + 1] = name
				end
			end
			return flags
		end

		local function itemKind(folder)
			local typ = tostring(valueOf(folder, 'Type') or '')
			local class = tostring(valueOf(folder, 'Class') or '')
			local name = folder.Name
			local lowerName = string.lower(name)
			local isShield = string.lower(class) == 'shield' or lowerName:find('shield', 1, true) ~= nil
			if typ == 'Weapon' then
				return 'Weapon'
			end
			if typ == 'Clothing' then
				return 'Armor'
			end
			if isShield then
				return 'Shield'
			end
			if typ == 'Accessory' then
				return 'Accessory'
			end
			if typ == 'Skin' then
				return 'Aura'
			end
			if typ ~= '' then
				return typ
			end
			return 'Item'
		end

		local function isShopChest(folder)
			if not folder then
				return false
			end
			local t = folder:FindFirstChild('Type')
			return t and t:IsA('ValueBase') and tostring(t.Value) == 'Chest'
		end

		local function chestLooksLikeAuras(folder)
			if folder.Name:lower():find('aura', 1, true) then
				return true
			end
			local items = folder:FindFirstChild('Items')
			if not items then
				return false
			end
			for _, child in ipairs(items:GetChildren()) do
				if string.lower(child.Name):find('aura', 1, true) then
					return true
				end
			end
			return false
		end

		local function listAuraChests()
			local names = {}
			local shop = getCashShop()
			if not shop then
				return names
			end
			for _, child in ipairs(shop:GetChildren()) do
				if isShopChest(child) and chestLooksLikeAuras(child) then
					names[#names + 1] = child.Name
				end
			end
			table.sort(names)
			return names
		end

		local function readChestContents(chestFolder)
			local rows = {}
			if not chestFolder then
				return rows
			end
			local itemsFolder = chestFolder:FindFirstChild('Items')
			if not itemsFolder then
				return rows
			end
			for _, child in ipairs(itemsFolder:GetChildren()) do
				if child:IsA('ValueBase') then
					rows[#rows + 1] = {
						name = child.Name,
						slot = tonumber(child.Value) or 0,
						iconId = iconIdOf(getItemFolder(child.Name)),
					}
				end
			end
			table.sort(rows, function(a, b)
				if a.slot ~= b.slot then
					return a.slot < b.slot
				end
				return a.name < b.name
			end)
			return rows
		end

		local function dumpWikiItem(name)
			local folder = getItemFolder(name)
			if not folder then
				return name .. '\n(not in Database.Items)'
			end
			local kind = itemKind(folder)
			local stats = readValueMap(folder:FindFirstChild('Stats'))
			local classVal = valueOf(folder, 'Class')
			local typ = valueOf(folder, 'Type')
			local rarity = valueOf(folder, 'Rarity')
			local level = valueOf(folder, 'Level')
			local damage = stats.Damage
			if damage == nil then
				damage = valueOf(folder, 'Damage')
			end
			local crit = stats.Critical
			if crit == nil then
				crit = valueOf(folder, 'Critical')
			end
			local defense = stats.Defense
			if defense == nil then
				defense = valueOf(folder, 'Defense')
			end
			local buffs = readValueMap(folder:FindFirstChild('Buffs'))
			local lines = { name }

			local function add(label, val)
				if val == nil or val == '' then
					return
				end
				lines[#lines + 1] = label .. ': ' .. tostring(val)
			end

			add('Type', typ)
			add('Class', classVal)
			add('Rarity', rarity)
			if kind ~= 'Accessory' or level ~= nil then
				add('Level', level)
			end

			if kind == 'Shield' then
				add('Defense', defense)
			elseif kind == 'Accessory' then
				add('Defense', defense)
				add('Damage', damage)
				add('Critical', crit)
			else
				add('Damage', damage)
				add('Critical', crit)
				add('Defense', defense)
			end

			local buffRows = {}
			for bname, bval in pairs(buffs) do
				buffRows[#buffRows + 1] = { bname, bval }
			end
			table.sort(buffRows, function(a, b)
				return a[1] < b[1]
			end)
			if #buffRows > 0 then
				lines[#lines + 1] = 'Buffs:'
				for _, row in ipairs(buffRows) do
					local shown = type(row[2]) == 'number' and formatRatio(row[2]) or tostring(row[2])
					lines[#lines + 1] = '  ' .. prettyStatName(row[1]) .. ': ' .. shown
				end
			end

			add('Icon', iconIdOf(folder))

			local flags = readFlags(folder)
			if #flags > 0 then
				add('Flags', table.concat(flags, ', '))
			end

			return table.concat(lines, '\n')
		end

		local function dumpWikiChest(chestName)
			local shop = getCashShop()
			local folder = shop and shop:FindFirstChild(chestName)
			if not folder then
				return chestName .. '\n(not in Database.CashShop)'
			end
			local lines = { chestName }
			local icon = iconIdOf(folder)
			if icon then
				lines[#lines + 1] = 'Icon: ' .. icon
			end
			lines[#lines + 1] = ''
			local rows = readChestContents(folder)
			if #rows == 0 then
				lines[#lines + 1] = '(no auras in Items folder)'
			else
				for i, row in ipairs(rows) do
					local slot = row.slot > 0 and tostring(row.slot) or tostring(i)
					local iconBit = row.iconId and (' — Icon: ' .. row.iconId) or ''
					lines[#lines + 1] = slot .. '. ' .. row.name .. iconBit
				end
			end
			return table.concat(lines, '\n')
		end

		local function writeWikiDump(text)
			if not ensureItemsFolder() or type(writefile) ~= 'function' then
				return
			end
			pcall(writefile, WIKI_DUMP_PATH, text)
			pcall(writefile, 'PlayerTools/wiki_dump.txt', text)
		end

		local function copyWiki(text)
			writeWikiDump(text)
			if copyText(text) then
				Library:Notify('Copied wiki dump (also PlayerTools/wiki_dump.txt)', 6)
				return true
			end
			Library:Notify('Wrote PlayerTools/wiki_dump.txt (clipboard unavailable)', 6)
			return false
		end

		local function scanLiveItems()
			table.clear(liveCache)
			table.clear(liveNames)
			local items = getItemsFolder()
			if not items then
				return 0
			end
			for _, child in ipairs(items:GetChildren()) do
				liveCache[child.Name] = recFromFolder(child)
				liveNames[#liveNames + 1] = child.Name
			end
			table.sort(liveNames)
			return #liveNames
		end

		local function knownPaths()
			return {
				ITEMS_KNOWN_PATH,
				'PlayerTools/items_known.json',
				'items_known.json',
			}
		end

		local function loadKnownSet()
			local set = {}
			if type(isfile) ~= 'function' or type(readfile) ~= 'function' then
				return set, 0
			end
			for _, path in ipairs(knownPaths()) do
				local okExists, exists = pcall(isfile, path)
				if okExists and exists then
					local okRead, body = pcall(readfile, path)
					if okRead and type(body) == 'string' and body ~= '' then
						local okJson, data = pcall(function()
							return HttpService:JSONDecode(body)
						end)
						if okJson and type(data) == 'table' then
							local n = 0
							if type(data.items) == 'table' then
								for name in pairs(data.items) do
									if type(name) == 'string' then
										set[name] = true
										n += 1
									end
								end
							elseif type(data.names) == 'table' then
								for _, name in ipairs(data.names) do
									if type(name) == 'string' then
										set[name] = true
										n += 1
									end
								end
							else
								-- plain { ["Item Name"] = true } map
								for name, flag in pairs(data) do
									if type(name) == 'string' and name ~= 'count' and flag then
										set[name] = true
										n += 1
									end
								end
							end
							return set, n
						end
					end
				end
			end
			return set, 0
		end

		local function saveKnownFromLive()
			if not ensureItemsFolder() then
				return false, 0
			end
			local count = scanLiveItems()
			local payload = {
				count = count,
				items = liveCache,
			}
			local okJson, body = pcall(function()
				return HttpService:JSONEncode(payload)
			end)
			if not okJson or type(body) ~= 'string' then
				return false, 0
			end
			pcall(writefile, ITEMS_KNOWN_PATH, body)
			pcall(writefile, 'PlayerTools/items_known.json', body)
			return true, count
		end

		local function loadKnownData()
			if type(isfile) ~= 'function' or type(readfile) ~= 'function' then
				return nil
			end
			for _, path in ipairs(knownPaths()) do
				local okExists, exists = pcall(isfile, path)
				if okExists and exists then
					local okRead, body = pcall(readfile, path)
					if okRead and type(body) == 'string' and body ~= '' then
						local okJson, data = pcall(function()
							return HttpService:JSONDecode(body)
						end)
						if okJson and type(data) == 'table' then
							if type(data.items) ~= 'table' then
								data.items = {}
								if type(data.names) == 'table' then
									for _, name in ipairs(data.names) do
										if type(name) == 'string' then
											data.items[name] = liveCache[name] or { rarity = '', type = '', class = '' }
										end
									end
								end
							end
							return data
						end
					end
				end
			end
			return nil
		end

		local function writeKnownData(data)
			if not ensureItemsFolder() or type(data) ~= 'table' then
				return false
			end
			local n = 0
			if type(data.items) == 'table' then
				for _ in pairs(data.items) do
					n += 1
				end
			end
			data.count = n
			local okJson, body = pcall(function()
				return HttpService:JSONEncode(data)
			end)
			if not okJson or type(body) ~= 'string' then
				return false
			end
			pcall(writefile, ITEMS_KNOWN_PATH, body)
			pcall(writefile, 'PlayerTools/items_known.json', body)
			return true
		end

		local function forgetNames(names)
			if type(names) ~= 'table' or #names == 0 then
				return false, {}
			end
			local data = loadKnownData()
			if not data or type(data.items) ~= 'table' then
				scanLiveItems()
				local set = loadKnownSet()
				data = { count = 0, items = {} }
				for name, rec in pairs(liveCache) do
					if set[name] then
						data.items[name] = rec
					end
				end
			end
			local removed = {}
			for _, name in ipairs(names) do
				if type(name) == 'string' and data.items[name] ~= nil then
					data.items[name] = nil
					removed[#removed + 1] = name
				end
			end
			if #removed == 0 then
				return false, removed
			end
			if not writeKnownData(data) then
				return false, removed
			end
			return true, removed
		end

		local function pickRandomKnown(count)
			scanLiveItems()
			local known = loadKnownSet()
			local pool = {}
			for _, name in ipairs(liveNames) do
				if known[name] then
					pool[#pool + 1] = name
				end
			end
			local picks = {}
			local n = math.min(count, #pool)
			for _ = 1, n do
				local idx = math.random(1, #pool)
				picks[#picks + 1] = pool[idx]
				table.remove(pool, idx)
			end
			return picks
		end

		local function setLabel(obj, text)
			if not obj then
				return
			end
			pcall(function()
				if type(obj.SetText) == 'function' then
					obj:SetText(text)
				elseif obj.Text then
					obj.Text = text
				end
			end)
		end

		local function setDropdown(option, values, fallback)
			if not option or type(option.SetValues) ~= 'function' then
				return
			end
			if not values or #values == 0 then
				values = { fallback or NONE }
			end
			pcall(function()
				option:SetValues(values)
			end)
			local cur
			pcall(function()
				cur = option.Value
			end)
			local still = false
			for _, v in ipairs(values) do
				if v == cur then
					still = true
					break
				end
			end
			if not still then
				pcall(function()
					option:SetValue(values[1])
				end)
			end
		end

		local ItemsTab = Window:AddTab('Items', 'package')
		local DiffBox = ItemsTab:AddLeftGroupbox('New since snapshot')
		local SearchBox = ItemsTab:AddRightGroupbox('Search Database.Items')
		local ChestBox = ItemsTab:AddRightGroupbox('Aura chests')
		assert(DiffBox, 'Items groupbox nil')

		local statusLabel = DiffBox:AddLabel('Scan after a drop. First run saves a baseline so nothing is marked new.')
		local detailLabel = DiffBox:AddLabel(' ')

		DiffBox:AddDropdown('NewItemList', {
			Text = 'New item names',
			Values = { NONE },
			AllowNull = true,
		}):OnChanged(function(name)
			if type(name) ~= 'string' or name == '' or name == NONE then
				setLabel(detailLabel, ' ')
				return
			end
			setLabel(detailLabel, formatRec(name, liveCache[name]))
		end)

		DiffBox:AddDropdown('RemovedItemList', {
			Text = 'Removed / renamed',
			Values = { NONE },
			AllowNull = true,
		})

		local function runScan(notifyBaseline)
			local liveCount = scanLiveItems()
			if liveCount == 0 then
				setLabel(statusLabel, 'Database.Items not found')
				Library:Notify('Database.Items not found')
				return
			end
			local known, knownCount = loadKnownSet()
			if knownCount == 0 then
				local ok, n = saveKnownFromLive()
				lastAdded = {}
				lastRemoved = {}
				setDropdown(Options.NewItemList, { NONE }, NONE)
				setDropdown(Options.RemovedItemList, { NONE }, NONE)
				local msg = ok
					and ('Saved baseline of %d items. After the next drop, Scan lists only new names.'):format(n)
					or 'Could not write items_known.json'
				setLabel(statusLabel, msg)
				if notifyBaseline ~= false then
					Library:Notify(msg, 8)
				end
				return
			end

			table.clear(lastAdded)
			table.clear(lastRemoved)
			for _, name in ipairs(liveNames) do
				if not known[name] then
					lastAdded[#lastAdded + 1] = name
				end
			end
			for name in pairs(known) do
				if not liveCache[name] then
					lastRemoved[#lastRemoved + 1] = name
				end
			end
			table.sort(lastRemoved)

			setDropdown(Options.NewItemList, lastAdded, NONE)
			setDropdown(Options.RemovedItemList, lastRemoved, NONE)
			local msg = ('Live %d · known %d · new %d · gone %d'):format(
				liveCount,
				knownCount,
				#lastAdded,
				#lastRemoved
			)
			setLabel(statusLabel, msg)
			Library:Notify(msg, 6)
		end

		local function currentSelectedName()
			local search = Options.ItemSearchResults and Options.ItemSearchResults.Value
			if type(search) == 'string' and search ~= '' and search ~= SEARCH_HINT and search ~= NONE then
				return search
			end
			local neu = Options.NewItemList and Options.NewItemList.Value
			if type(neu) == 'string' and neu ~= '' and neu ~= NONE then
				return neu
			end
			return nil
		end

		local function dumpAllNewWiki()
			if #lastAdded == 0 then
				return nil, 'No new names — Scan first'
			end
			local blocks = {}
			local shop = getCashShop()
			for _, name in ipairs(lastAdded) do
				blocks[#blocks + 1] = dumpWikiItem(name)
				local chest = shop and shop:FindFirstChild(name)
				if chest and isShopChest(chest) then
					blocks[#blocks + 1] = dumpWikiChest(name)
				end
			end
			return table.concat(blocks, '\n\n'), nil
		end

		DiffBox:AddButton('Scan for new items', function()
			runScan(true)
		end)

		DiffBox:AddButton('Copy new names', function()
			if #lastAdded == 0 then
				Library:Notify('No new names — Scan first')
				return
			end
			if copyText(table.concat(lastAdded, '\n')) then
				Library:Notify(('Copied %d new names'):format(#lastAdded))
			else
				Library:Notify('Clipboard unavailable')
			end
		end)

		DiffBox:AddButton('Copy wiki: all new', function()
			local text, err = dumpAllNewWiki()
			if not text then
				Library:Notify(err)
				return
			end
			copyWiki(text)
		end)

		DiffBox:AddButton('Save current DB as known', function()
			local ok, n = saveKnownFromLive()
			if not ok then
				Library:Notify('Could not write items_known.json')
				return
			end
			lastAdded = {}
			lastRemoved = {}
			setDropdown(Options.NewItemList, { NONE }, NONE)
			setDropdown(Options.RemovedItemList, { NONE }, NONE)
			local msg = ('Saved %d items as known. Next patch will only flag additions.'):format(n)
			setLabel(statusLabel, msg)
			Library:Notify(msg, 6)
		end)

		DiffBox:AddButton('Forget selected (test)', function()
			local name = currentSelectedName()
			if not name then
				Library:Notify('Pick a search match or new-list item first')
				return
			end
			local ok, removed = forgetNames({ name })
			if not ok or #removed == 0 then
				Library:Notify(name .. ' was not in the snapshot')
				return
			end
			Library:Notify('Forgot ' .. name .. ' — scanning')
			runScan(true)
		end)

		DiffBox:AddButton('Forget 3 random (test)', function()
			local picks = pickRandomKnown(3)
			if #picks == 0 then
				Library:Notify('No known names to forget — save a snapshot first')
				return
			end
			local ok, removed = forgetNames(picks)
			if not ok or #removed == 0 then
				Library:Notify('Could not update items_known.json')
				return
			end
			Library:Notify('Forgot: ' .. table.concat(removed, ', '), 8)
			runScan(true)
		end)

		local function applySearch(query)
			query = string.lower(tostring(query or ''):gsub('^%s+', ''):gsub('%s+$', ''))
			if query == '' then
				setDropdown(Options.ItemSearchResults, { SEARCH_HINT }, SEARCH_HINT)
				setLabel(detailLabel, ' ')
				return
			end
			if #liveNames == 0 then
				scanLiveItems()
			end
			local hits = {}
			for _, name in ipairs(liveNames) do
				if string.find(string.lower(name), query, 1, true) then
					hits[#hits + 1] = name
					if #hits >= 80 then
						break
					end
				end
			end
			setDropdown(Options.ItemSearchResults, hits, SEARCH_HINT)
			if #hits == 1 then
				setLabel(detailLabel, formatRec(hits[1], liveCache[hits[1]]))
			end
		end

		SearchBox:AddLabel('Looks up ReplicatedStorage.Database.Items by name. Floor does not matter.')

		SearchBox:AddInput('ItemSearchQuery', {
			Text = 'Name contains',
			Default = '',
			Placeholder = 'e.g. Angelic',
			Finished = false,
			ClearTextOnFocus = false,
			AllowEmpty = true,
			Callback = function(value)
				searchToken += 1
				local token = searchToken
				task.delay(0.12, function()
					if token == searchToken then
						applySearch(value)
					end
				end)
			end,
		})

		SearchBox:AddDropdown('ItemSearchResults', {
			Text = 'Matches',
			Values = { SEARCH_HINT },
			AllowNull = true,
		}):OnChanged(function(name)
			if type(name) ~= 'string' or name == '' or name == SEARCH_HINT or name == NONE then
				return
			end
			if not liveCache[name] then
				scanLiveItems()
			end
			setLabel(detailLabel, formatRec(name, liveCache[name]))
		end)

		SearchBox:AddButton('Copy selected match', function()
			local name = Options.ItemSearchResults and Options.ItemSearchResults.Value
			if type(name) ~= 'string' or name == '' or name == SEARCH_HINT or name == NONE then
				Library:Notify('Pick a search match first')
				return
			end
			if copyText(name) then
				Library:Notify('Copied ' .. name)
			else
				Library:Notify('Clipboard unavailable')
			end
		end)

		SearchBox:AddButton('Copy wiki: selected', function()
			local name = currentSelectedName()
			if not name then
				Library:Notify('Pick a search match or new-list item first')
				return
			end
			copyWiki(dumpWikiItem(name))
		end)

		local chestDetail = ChestBox:AddLabel('Search the robux shop chest name (or an aura inside it).')

		local function chestMatchesQuery(chestName, query)
			if query == '' then
				return true
			end
			if string.find(string.lower(chestName), query, 1, true) then
				return true
			end
			local shop = getCashShop()
			local folder = shop and shop:FindFirstChild(chestName)
			local items = folder and folder:FindFirstChild('Items')
			if not items then
				return false
			end
			for _, child in ipairs(items:GetChildren()) do
				if string.find(string.lower(child.Name), query, 1, true) then
					return true
				end
			end
			return false
		end

		local function currentChestQuery()
			local q = Options.AuraChestSearch and Options.AuraChestSearch.Value
			return string.lower(tostring(q or ''):gsub('^%s+', ''):gsub('%s+$', ''))
		end

		local function applyChestSearch(query, silent)
			query = string.lower(tostring(query or ''):gsub('^%s+', ''):gsub('%s+$', ''))
			local hits = {}
			for _, name in ipairs(allAuraChests) do
				if chestMatchesQuery(name, query) then
					hits[#hits + 1] = name
					if #hits >= 80 then
						break
					end
				end
			end
			setDropdown(Options.AuraChestList, hits, NONE)
			if #hits == 1 then
				pcall(function()
					Options.AuraChestList:SetValue(hits[1])
				end)
			end
			if not silent then
				if query == '' then
					setLabel(chestDetail, ('%d chests — type a shop name'):format(#allAuraChests))
				else
					setLabel(chestDetail, ('%d match "%s"'):format(#hits, query))
				end
			end
		end

		ChestBox:AddInput('AuraChestSearch', {
			Text = 'Chest name contains',
			Default = '',
			Placeholder = 'e.g. Astral Spectra',
			Finished = false,
			ClearTextOnFocus = false,
			AllowEmpty = true,
			Callback = function(value)
				chestSearchToken += 1
				local token = chestSearchToken
				task.delay(0.12, function()
					if token == chestSearchToken then
						applyChestSearch(value, false)
					end
				end)
			end,
		})

		ChestBox:AddDropdown('AuraChestList', {
			Text = 'Matches',
			Values = { NONE },
			AllowNull = true,
		}):OnChanged(function(name)
			if type(name) ~= 'string' or name == '' or name == NONE then
				setLabel(chestDetail, 'Search the robux shop chest name (or an aura inside it).')
				return
			end
			local shop = getCashShop()
			local folder = shop and shop:FindFirstChild(name)
			local rows = readChestContents(folder)
			setLabel(chestDetail, ('%s — %d auras'):format(name, #rows))
		end)

		local function refreshAuraChests(notify)
			allAuraChests = listAuraChests()
			applyChestSearch(currentChestQuery(), true)
			if notify then
				Library:Notify(('Aura chests: %d'):format(#allAuraChests))
			end
		end

		ChestBox:AddButton('Refresh chests', function()
			refreshAuraChests(true)
		end)

		ChestBox:AddButton('Copy wiki: this chest', function()
			local name = Options.AuraChestList and Options.AuraChestList.Value
			if type(name) ~= 'string' or name == '' or name == NONE then
				Library:Notify('Pick an aura chest first')
				return
			end
			copyWiki(dumpWikiChest(name))
		end)

		-- Quiet baseline so the first Scan after a real drop is a real diff.
		task.defer(function()
			refreshAuraChests(false)
			local _, knownCount = loadKnownSet()
			if knownCount == 0 then
				runScan(false)
			else
				setLabel(statusLabel, ('Known snapshot: %d items. Scan after a drop.'):format(knownCount))
			end
		end)
	end

	-- ── HiveMind (multi-client commander via shared workspace files) ──
	do
		local function loadHive()
			local paths = {
				'PlayerTools/HiveMind.lua',
				'HiveMind.lua',
			}
			for _, path in ipairs(paths) do
				if type(readfile) == 'function' then
					local okRead, src = pcall(readfile, path)
					if okRead and type(src) == 'string' and src ~= '' then
						local fn, err = (loadstring or load)(src, path)
						if fn then
							local okRun, result = pcall(fn)
							if okRun and type(result) == 'table' then
								return result
							end
						else
							warn('[Hive] compile failed: ', err)
						end
					end
				end
			end
			if type(getgenv().SB2Hive) == 'table' and getgenv().SB2Hive.start then
				return getgenv().SB2Hive
			end
			return nil
		end

		local Hive = loadHive()
		local HiveTab = Window:AddTab('Hive', 'share-2')
		local HiveBox = HiveTab:AddLeftGroupbox('Hivemind')
		local OrdersBox = HiveTab:AddRightGroupbox('Orders')
		local TradeBox = HiveTab:AddRightGroupbox('Crystal pipeline')
		assert(HiveBox, 'Hive groupbox nil')

		if not Hive then
			HiveBox:AddLabel('HiveMind.lua missing — put it in PlayerTools/')
		else
			Hive.notify = function(msg)
				Library:Notify(tostring(msg))
			end

			local statusLabel = HiveBox:AddLabel('Status: off')
			local peersLabel = HiveBox:AddLabel('Peers:\n(none)')

			local function setLabelText(label, text)
				pcall(function()
					if label.SetText then
						label:SetText(text)
					elseif label.Text ~= nil then
						label.Text = text
					end
				end)
			end

			local function refreshCommanderDropdown()
				local names = Hive.peerNames and Hive.peerNames() or {}
				if #names == 0 then
					names = { LocalPlayer.Name }
				end
				local cmdName = Hive.commanderName and select(1, Hive.commanderName())
				if cmdName and cmdName ~= '' and not table.find(names, cmdName) then
					names[#names + 1] = cmdName
					table.sort(names)
				end
				local opt = Options.HiveCommander
				if type(opt) ~= 'table' then
					return
				end
				Hive._syncingCommanderUi = true
				if type(opt.SetValues) == 'function' then
					pcall(function()
						opt:SetValues(names)
					end)
				end
				if cmdName and cmdName ~= '' and type(opt.SetValue) == 'function' and opt.Value ~= cmdName then
					pcall(function()
						opt:SetValue(cmdName)
					end)
				end
				Hive._syncingCommanderUi = false
			end

			local function refreshHiveLabels()
				if not Hive then
					return
				end
				local alive = Hive.isAlive and Hive.isAlive()
				local cmdName = Hive.commanderName and select(1, Hive.commanderName()) or '?'
				local statusText = ('Status: %s | role=%s | cmd=%s | %s'):format(
					tostring(Hive.status),
					tostring(Hive.role),
					tostring(cmdName),
					alive and 'ONLINE' or 'off'
				)
				local peersText = 'Peers:\n' .. (Hive.peerSummary and Hive.peerSummary() or '?')
				setLabelText(statusLabel, statusText)
				setLabelText(peersLabel, peersText)
				refreshCommanderDropdown()
			end

			HiveBox:AddLabel('Join hive on every client, pick the commanding account, then press an order. Others TP to that client.')
			local hiveOptedIn = true
			if type(Hive.fileOptedIn) == 'function' then
				hiveOptedIn = Hive.fileOptedIn() == true
			end
			HiveBox:AddToggle('HiveEnabled', {
				Text = 'Join hive',
				Default = hiveOptedIn,
				Tooltip = 'Off on this client stays off after reload. Does not take hive orders while off.',
			}):OnChanged(function(on)
				if type(Hive.writeOptedIn) == 'function' then
					Hive.writeOptedIn(on == true)
				end
				if on then
					Hive.start()
					if Hive.role == 'idle' then
						Hive.becomeWorker()
					end
				else
					Hive.stop({ leave = true })
				end
				refreshHiveLabels()
			end)

			HiveBox:AddDropdown('HiveCommander', {
				Text = 'Commanding client',
				Values = { LocalPlayer.Name },
				Default = LocalPlayer.Name,
				AllowNull = false,
				Searchable = true,
				Tooltip = 'Who the other clients TP / follow / stack onto. Shared across all hive clients.',
			}):OnChanged(function(name)
				if Hive._syncingCommanderUi then
					return
				end
				if not Hive.isAlive or not Hive.isAlive() then
					return
				end
				local peer = Hive.peerByName and Hive.peerByName(name)
				local userId = peer and peer.userId
				if not userId and string.lower(tostring(name)) == string.lower(LocalPlayer.Name) then
					userId = LocalPlayer.UserId
				end
				if userId then
					Hive.setSelectedCommander(userId, name)
				end
				refreshHiveLabels()
			end)

			HiveBox:AddButton('This client is commander', function()
				if type(Hive.writeOptedIn) == 'function' then
					Hive.writeOptedIn(true)
				end
				if Toggles.HiveEnabled then
					Toggles.HiveEnabled:SetValue(true)
				end
				if not Hive.isAlive() then
					Hive.start()
				end
				Hive.claimCommander()
				local opt = Options.HiveCommander
				if type(opt) == 'table' and type(opt.SetValue) == 'function' then
					pcall(function()
						opt:SetValue(LocalPlayer.Name)
					end)
				end
				refreshHiveLabels()
			end)

			HiveBox:AddButton('Refresh peers', function()
				refreshHiveLabels()
				Library:Notify('Peers refreshed')
			end)

			OrdersBox:AddLabel('TP hops to the commander then free roam. Follow/Stack keep locking until Stop workers.')
			OrdersBox:AddButton('TP others to commander', function()
				Hive.issue('rally', {})
				refreshHiveLabels()
			end)
			OrdersBox:AddButton('Follow commander', function()
				Hive.issue('follow', { radius = 5 })
				refreshHiveLabels()
			end)
			OrdersBox:AddButton('Stack on commander', function()
				Hive.issue('stack', {})
				refreshHiveLabels()
			end)
			OrdersBox:AddButton('Combat ON', function()
				Hive.issue('combat_on', {})
				refreshHiveLabels()
			end)
			OrdersBox:AddButton('Combat OFF', function()
				Hive.issue('combat_off', {})
				refreshHiveLabels()
			end)
			OrdersBox:AddButton('Stop workers', function()
				Hive.issue('stop', {})
				refreshHiveLabels()
			end)
			OrdersBox:AddButton('Resume ON (all clients)', function()
				-- Local first so the issuer does not wait for the file poll.
				pcall(function()
					if type(getgenv().SB2SetSoloResume) == 'function' then
						getgenv().SB2SetSoloResume(true)
					elseif Toggles.SoloCombatResume and Toggles.SoloCombatResume.SetValue then
						Toggles.SoloCombatResume:SetValue(true)
					end
				end)
				Hive.issue('solo_resume', {})
				refreshHiveLabels()
			end)

			TradeBox:AddLabel('Workers must be HERE (TP first). Commander auto-accepts hive trades.')
			TradeBox:AddDropdown('HiveCrystalType', {
				Text = 'Deposit type',
				Values = {
					'Common',
					'Uncommon',
					'Rare',
					'Legendary',
					'Tribute',
					'Burst',
					'Protection',
				},
				Default = 'Legendary',
				AllowNull = false,
			})
			TradeBox:AddSlider('HiveCrystalAmount', {
				Text = 'Amount',
				Default = 64,
				Min = 1,
				Max = 400,
				Rounding = 0,
			})
			TradeBox:AddToggle('HiveAcceptTrades', {
				Text = 'Commander: accept hive trades',
				Default = true,
			}):OnChanged(function(on)
				Hive.setAcceptHiveTrades(on)
			end)
			-- Default=true does not always fire OnChanged — arm accept immediately.
			pcall(function()
				Hive.setAcceptHiveTrades(true)
			end)
			TradeBox:AddButton('Workers: deposit to commander', function()
				local rarity = Options.HiveCrystalType and Options.HiveCrystalType.Value or 'Legendary'
				local amount = Options.HiveCrystalAmount and Options.HiveCrystalAmount.Value or 64
				Hive.issue('deposit_crystals', {
					rarity = rarity,
					amount = amount,
				})
				refreshHiveLabels()
			end)
			TradeBox:AddLabel('Dump: snaps to commander, gear then crystals (max 400/trade), then ALL worker vel (10% fee, receiver cap 1B). Pick commanding client first.')
			TradeBox:AddButton('Workers: trade ALL items + vel to commander', function()
				Hive.issue('dump_items', {})
				refreshHiveLabels()
			end)

			task.spawn(function()
				while getgenv()[CONFIG.GenvKey] do
					task.wait(1.25)
					local toggle = Toggles and Toggles.HiveEnabled
					-- If the toggle object is gone (script reload), do not treat that as
					-- an intentional leave — writing optin false was sticky-removing clients.
					if type(toggle) ~= 'table' then
						continue
					end
					local toggleOn = toggle.Value == true
					if Hive.isAlive and Hive.isAlive() and not toggleOn then
						pcall(function()
							Hive.stop()
						end)
					end
					if Hive.isAlive and Hive.isAlive() then
						pcall(refreshHiveLabels)
					end
				end
			end)

			task.defer(function()
				local toggleOn = Toggles.HiveEnabled and Toggles.HiveEnabled.Value == true
				local opted = not Hive.fileOptedIn or Hive.fileOptedIn() == true
				if toggleOn and opted then
					pcall(function()
						Hive.start()
					end)
					refreshHiveLabels()
				elseif Hive.isAlive and Hive.isAlive() then
					pcall(function()
						Hive.stop()
					end)
					refreshHiveLabels()
				end
			end)

			getgenv().SB2HiveStop = function()
				pcall(function()
					Hive.stop()
				end)
			end
		end
	end

	local Settings = Window:AddTab('Settings', 'settings')
	local Menu = Settings:AddLeftGroupbox('Menu')

	pcall(function()
		local combat = Library.Tabs and Library.Tabs.Combat
		if combat and type(combat.Show) == 'function' then
			combat:Show()
		end
	end)

	-- Home — AutoFarm defaults to End so both can toggle independently.
	Menu:AddLabel('Menu keybind'):AddKeyPicker('MenuKeybind', { Default = 'Home', NoUI = true })
	Library.ToggleKeybind = Options.MenuKeybind

	Menu:AddButton('Reset UI position', function()
		forceShowWindow(true)
		Library:Notify('UI moved to bottom-left')
	end)

	local function antiafkStatusText()
		if getgenv().SB2AntiAfkOn ~= true then
			return 'Anti-AFK: off'
		end
		local last = tonumber(getgenv().SB2AntiAfkLastPulse)
		if last then
			local ago = math.max(0, os.time() - last)
			return ('Anti-AFK: armed (IY-style) · last idle %ds ago'):format(ago)
		end
		return 'Anti-AFK: armed (IY-style) — no jump / no keys'
	end

	local afkStatus = Menu:AddLabel(antiafkStatusText())
	getgenv().SB2AntiAfkPaint = function()
		pcall(function()
			if afkStatus and afkStatus.SetText then
				afkStatus:SetText(antiafkStatusText())
			elseif afkStatus then
				afkStatus.Text = antiafkStatusText()
			end
		end)
	end
	task.spawn(function()
		while getgenv()[CONFIG.GenvKey] do
			pcall(getgenv().SB2AntiAfkPaint)
			task.wait(5)
		end
	end)

	Menu:AddToggle('AntiAFK', {
		Text = 'Anti-AFK',
		Default = antiafkFileOn(),
		Tooltip = 'Same as Infinite Yield antiafk: blocks the idle kick. No jump, no keys, no camera. Stays on after teleport if Autoexecute is on.',
	}):OnChanged(function(value)
		writeAntiafkFile(value == true)
		if value then
			startAntiAfk()
		else
			stopAntiAfk()
		end
		pcall(getgenv().SB2AntiAfkPaint)
	end)
	if antiafkFileOn() and getgenv().SB2AntiAfkOn ~= true then
		startAntiAfk()
	end

	Menu:AddToggle('AutoSkipLoading', {
		Text = 'Rejoin if stuck loading',
		Default = LoadSkip.fileOn(),
		Tooltip = 'If the session loading screen is still up after 15s, rejoin this client (same server). Repeats until it actually loads. Keep Autoexecute on. Does not hide/force the HUD.',
	}):OnChanged(function(value)
		LoadSkip.writeFile(value == true)
		getgenv().SB2AutoSkipLoad = value == true
	end)
	Menu:AddButton('Rejoin stuck loading now', function()
		if LoadSkip.overlayUp() then
			LoadSkip.rejoin('settings')
			Library:Notify('Rejoining — keep Autoexecute on so PlayerTools comes back.', 6)
		else
			Library:Notify('Loading overlay is not up on this client.', 4)
		end
	end)

	local autoexecute = true
	if isfile and isfile(AUTOEXEC_PATH) and readfile(AUTOEXEC_PATH) == 'false' then
		autoexecute = false
	end

	Menu:AddToggle('Autoexecute', { Text = 'Autoexecute on teleport', Default = autoexecute, Tooltip = 'Must stay on so PlayerTools (and Anti-AFK) come back after an AFK kick to F1.' }):OnChanged(function(value)
		if makefolder and writefile then
			local folder = CONFIG.ConfigFolder
			if folder ~= '' and folder ~= '.' and type(isfolder) == 'function' and not isfolder(folder) then
				makefolder(folder)
			end
			writefile(AUTOEXEC_PATH, tostring(value))
		end
	end)

	Menu:AddButton('Unload Script', function()
		if isToggleOn('ViewPlayer') then
			Toggles.ViewPlayer:SetValue(false)
		end
		if isToggleOn('AutoAttack') then
			Toggles.AutoAttack:SetValue(false)
		end
		if isToggleOn('DiveFarm') then
			Toggles.DiveFarm:SetValue(false)
		end
		-- Stop hive runtime only. Do not SetValue(false) on HiveEnabled — OnChanged
		-- would write optin false and sticky-drop this client from the peer list on reload.
		if type(getgenv().SB2HiveStop) == 'function' then
			pcall(getgenv().SB2HiveStop)
		end
		if RequiredServices and isToggleOn('ViewPlayersInventory') then
			Toggles.ViewPlayersInventory:SetValue(false)
			pcall(debug.setupvalue, RequiredServices.InventoryUI.GetInventoryData, 2, Profile)
		end
		if type(getgenv().SB2InvFilterCleanup) == 'function' then
			pcall(getgenv().SB2InvFilterCleanup)
		end
		pcall(function()
			Camera.CameraSubject = Character
		end)
		if type(getgenv().SB2FixCamera) == 'function' then
			pcall(getgenv().SB2FixCamera, LocalPlayer.Character)
		end
		if type(getgenv().SB2PlayerToolsMarkUnloaded) == 'function' then
			pcall(getgenv().SB2PlayerToolsMarkUnloaded)
		end
		pcall(function()
			getgenv().SB2AntiAfkOn = false
			local prev = getgenv().SB2AntiAfkConn
			if prev then
				prev:Disconnect()
			end
			getgenv().SB2AntiAfkConn = nil
		end)
		pcall(unloadExisting)
		getgenv()[CONFIG.GenvKey] = false
		getgenv()[LIBRARY_KEY] = nil
		getgenv().SB2PlayerToolsLoading = false
		getgenv().SB2PlayerToolsArmedNotify = nil
		Library:Notify('PlayerTools unloaded — will not auto-return until you run it again')
	end)

	pcall(function()
		local ThemeManager = compile(httpGet(CONFIG.UIRepo .. 'addons/ThemeManager.lua'))()
		ThemeManager:SetLibrary(Library)
		ThemeManager:SetFolder(CONFIG.ConfigFolder)
		ThemeManager:ApplyToTab(Settings)
	end)

	pcall(function()
		local SaveManager = compile(httpGet(CONFIG.UIRepo .. 'addons/SaveManager.lua'))()
		SaveManager:SetLibrary(Library)
		SaveManager:SetFolder(CONFIG.ConfigFolder)
		SaveManager:IgnoreThemeSettings()
		-- Dedicated inv_level_filter file owns these — autoload was wiping them via deferred loads.
		SaveManager:SetIgnoreIndexes({
			'AntiAFK',
			'AutoSkipLoading',
			'HiveEnabled',
			'HiveCommander',
			'HiveAcceptTrades',
			'HiveCrystalType',
			'HiveCrystalAmount',
			-- SoloCombatResume / AutoBlockJoin intentionally NOT ignored —
			-- Ignore skipped LoadJSON so Overwrite looked like it never stuck.
		})

		-- Profiles stay shared. Autoload pointer is per account so one client
		-- changing "Set as autoload" does not rewrite every other client.
		local function autoloadAccountKey()
			local name = string.lower(tostring(LocalPlayer.Name or 'unknown'))
			name = name:gsub('[^%w_%-]', '_')
			if name == '' then
				name = 'unknown'
			end
			return name
		end
		local function autoloadDir()
			return joinPath(CONFIG.ConfigFolder, 'autoload_by_account')
		end
		local function autoloadAccountPath()
			return joinPath(autoloadDir(), autoloadAccountKey() .. '.txt')
		end
		local function autoloadConfigJsonPath(configName)
			return joinPath(joinPath(CONFIG.ConfigFolder, 'settings'), tostring(configName) .. '.json')
		end
		local function trimConfigName(raw)
			return (tostring(raw or ''):gsub('^%s+', ''):gsub('%s+$', ''))
		end
		local function ensureAutoloadDir()
			if type(makefolder) ~= 'function' or type(isfolder) ~= 'function' then
				return
			end
			pcall(function()
				if CONFIG.ConfigFolder ~= '' and CONFIG.ConfigFolder ~= '.' and not isfolder(CONFIG.ConfigFolder) then
					makefolder(CONFIG.ConfigFolder)
				end
				local dir = autoloadDir()
				if not isfolder(dir) then
					makefolder(dir)
				end
			end)
		end
		local function configExists(configName)
			if type(isfile) ~= 'function' then
				return false
			end
			local name = trimConfigName(configName)
			if name == '' or name == 'none' then
				return false
			end
			local ok, exists = pcall(isfile, autoloadConfigJsonPath(name))
			return ok and exists == true
		end

		local origGet = SaveManager.GetAutoloadConfig
		local origSave = SaveManager.SaveAutoloadConfig
		local origDelete = SaveManager.DeleteAutoLoadConfig

		SaveManager.GetAutoloadConfig = function(self)
			local path = autoloadAccountPath()
			if type(isfile) == 'function' and type(readfile) == 'function' then
				local okExists, exists = pcall(isfile, path)
				if okExists and exists then
					local okRead, body = pcall(readfile, path)
					if not okRead then
						return 'none', false, tostring(body)
					end
					local name = trimConfigName(body)
					if name == '' or name == 'none' then
						self.AutoloadConfig = nil
						return 'none', false, 'Autoload config is not set'
					end
					if not configExists(name) then
						return 'none', false, 'Config file not found'
					end
					self.AutoloadConfig = name
					return name, true
				end
			end
			if type(origGet) == 'function' then
				return origGet(self)
			end
			return 'none', false, 'Autoload config is not set'
		end

		SaveManager.SaveAutoloadConfig = function(self, configName)
			local name = trimConfigName(configName)
			if name == '' then
				return false, 'No config is selected'
			end
			if not configExists(name) then
				return false, 'Config does not exist'
			end
			ensureAutoloadDir()
			if type(writefile) ~= 'function' then
				return false, 'writefile unavailable'
			end
			local okWrite, errWrite = pcall(writefile, autoloadAccountPath(), name)
			if not okWrite then
				return false, errWrite
			end
			self.AutoloadConfig = name
			return true
		end

		SaveManager.DeleteAutoLoadConfig = function(self)
			ensureAutoloadDir()
			if type(writefile) ~= 'function' then
				return false, 'writefile unavailable'
			end
			-- Sentinel so this account does not fall back to the shared autoload.txt.
			local okWrite, errWrite = pcall(writefile, autoloadAccountPath(), 'none')
			if not okWrite then
				return false, errWrite
			end
			self.AutoloadConfig = nil
			return true
		end

		-- Solo resume + Auto block + combat dropdowns: forced into JSON on Save and
		-- re-applied after Load (SaveManager uses task.defer per control — races Default).
		local HttpServiceSM = game:GetService('HttpService')
		local lastSoloBlock = {
			SoloCombatResume = nil,
			AutoBlockJoin = nil,
		}
		local lastCombatOptions = {
			SkillName = nil,
			SupportSkillName = nil,
			SoloResumeWaypoint = nil,
		}
		local function readToggleWanted(idx)
			local t = Toggles and Toggles[idx]
			return type(t) == 'table' and t.Value == true
		end
		local function flattenOptionValue(value)
			local fn = getgenv().SB2FlattenOptionValue
			if type(fn) == 'function' then
				return fn(value)
			end
			if value == nil then
				return nil
			end
			if type(value) == 'table' then
				if value[1] ~= nil then
					return flattenOptionValue(value[1])
				end
				for k, on in pairs(value) do
					if on == true then
						return tostring(k)
					end
				end
				if value.value ~= nil then
					return flattenOptionValue(value.value)
				end
				return nil
			end
			local s = tostring(value)
			if s == '' or string.sub(s, 1, 6) == 'table:' then
				return nil
			end
			return s
		end
		local function readDropdownWanted(idx)
			local last = getgenv().SB2LastCombatOptions
			if type(last) == 'table' and (idx == 'SkillName' or idx == 'SupportSkillName') then
				local remembered = last[idx]
				if type(remembered) == 'string' and remembered ~= '' then
					-- Prefer last user pick — refresh can briefly show (none) at save time.
					if remembered ~= '(none)' then
						return remembered
					end
				end
			end
			local opt = Options and Options[idx]
			if type(opt) ~= 'table' then
				return nil
			end
			local ok, value = pcall(function()
				return opt.Value
			end)
			if not ok then
				return nil
			end
			return flattenOptionValue(value)
		end
		local function readCombatSkillsSidecar()
			if type(isfile) ~= 'function' or type(readfile) ~= 'function' then
				return nil
			end
			local ok, exists = pcall(isfile, COMBAT_SKILLS_PATH)
			if not ok or not exists then
				return nil
			end
			local okRead, body = pcall(readfile, COMBAT_SKILLS_PATH)
			if not okRead or type(body) ~= 'string' or body == '' then
				return nil
			end
			local okDecode, decoded = pcall(function()
				return HttpServiceSM:JSONDecode(body)
			end)
			if not okDecode or type(decoded) ~= 'table' then
				return nil
			end
			return decoded
		end
		local function writeCombatSkillsSidecar(skill, support)
			if type(writefile) ~= 'function' then
				return
			end
			pcall(function()
				writefile(
					COMBAT_SKILLS_PATH,
					HttpServiceSM:JSONEncode({
						SkillName = skill,
						SupportSkillName = support,
					})
				)
			end)
		end
		local function readAutoblockFileWanted()
			if type(isfile) ~= 'function' or type(readfile) ~= 'function' then
				return nil
			end
			local ok, exists = pcall(isfile, AUTOBLOCK_PATH)
			if not ok or not exists then
				return nil
			end
			local okRead, body = pcall(readfile, AUTOBLOCK_PATH)
			if not okRead then
				return nil
			end
			local s = tostring(body or ''):lower():gsub('%s+', '')
			if s == 'true' then
				return true
			end
			if s == 'false' then
				return false
			end
			return nil
		end
		local function readSoloResumeFileWanted()
			if type(isfile) ~= 'function' or type(readfile) ~= 'function' then
				return nil
			end
			local ok, exists = pcall(isfile, SOLO_RESUME_PATH)
			if not ok or not exists then
				return nil
			end
			local okRead, body = pcall(readfile, SOLO_RESUME_PATH)
			if not okRead then
				return nil
			end
			local s = tostring(body or ''):lower():gsub('%s+', '')
			if s == 'true' then
				return true
			end
			if s == 'false' then
				return false
			end
			return nil
		end
		local function writeSoloResumeFile(on)
			if type(writefile) ~= 'function' then
				return
			end
			pcall(writefile, SOLO_RESUME_PATH, on and 'true' or 'false')
		end
		local function upsertToggleInObjects(objects, idx, value)
			if type(objects) ~= 'table' then
				return
			end
			for _, obj in ipairs(objects) do
				if type(obj) == 'table' and obj.type == 'Toggle' and obj.idx == idx then
					obj.value = value == true
					return
				end
			end
			objects[#objects + 1] = {
				type = 'Toggle',
				idx = idx,
				value = value == true,
			}
		end
		local function upsertDropdownInObjects(objects, idx, value)
			if type(objects) ~= 'table' or value == nil then
				return
			end
			for _, obj in ipairs(objects) do
				if type(obj) == 'table' and obj.type == 'Dropdown' and obj.idx == idx then
					obj.value = value
					obj.multi = false
					return
				end
			end
			objects[#objects + 1] = {
				type = 'Dropdown',
				idx = idx,
				value = value,
				multi = false,
			}
		end
		local function ensureDropdownHasValue(opt, value)
			if type(opt) ~= 'table' or value == nil then
				return
			end
			local values = opt.Values
			if type(values) == 'table' then
				local found = false
				for _, v in ipairs(values) do
					if v == value then
						found = true
						break
					end
				end
				if not found then
					local nextValues = {}
					for i, v in ipairs(values) do
						nextValues[i] = v
					end
					nextValues[#nextValues + 1] = value
					pcall(function()
						opt:SetValues(nextValues)
					end)
				end
			end
			pcall(function()
				opt:SetValue(value)
			end)
		end
		local function rememberSoloBlockFromJSON(content)
			if type(content) ~= 'string' or content == '' then
				return
			end
			local okDecode, decoded = pcall(function()
				return HttpServiceSM:JSONDecode(content)
			end)
			if not okDecode or type(decoded) ~= 'table' or type(decoded.objects) ~= 'table' then
				return
			end
			for _, obj in ipairs(decoded.objects) do
				if type(obj) ~= 'table' then
					continue
				end
				if obj.type == 'Toggle' then
					if obj.idx == 'SoloCombatResume' then
						lastSoloBlock.SoloCombatResume = obj.value == true
					elseif obj.idx == 'AutoBlockJoin' then
						lastSoloBlock.AutoBlockJoin = obj.value == true
					end
				elseif obj.type == 'Dropdown' then
					if obj.idx == 'SkillName' or obj.idx == 'SupportSkillName' or obj.idx == 'SoloResumeWaypoint' then
						local flat = flattenOptionValue(obj.value)
						if flat ~= nil then
							lastCombatOptions[obj.idx] = flat
						end
					end
				end
			end
			-- Sidecars fill gaps / win brief Default=false races.
			local fileBlock = readAutoblockFileWanted()
			if fileBlock ~= nil and lastSoloBlock.AutoBlockJoin == nil then
				lastSoloBlock.AutoBlockJoin = fileBlock
			elseif fileBlock == true then
				lastSoloBlock.AutoBlockJoin = true
			end
			local fileSolo = readSoloResumeFileWanted()
			if fileSolo ~= nil and lastSoloBlock.SoloCombatResume == nil then
				lastSoloBlock.SoloCombatResume = fileSolo
			elseif fileSolo == true then
				lastSoloBlock.SoloCombatResume = true
			end
			local sidecar = readCombatSkillsSidecar()
			if type(sidecar) == 'table' then
				if (lastCombatOptions.SkillName == nil or lastCombatOptions.SkillName == '(none)') and type(sidecar.SkillName) == 'string' and sidecar.SkillName ~= '' then
					lastCombatOptions.SkillName = sidecar.SkillName
				end
				if (lastCombatOptions.SupportSkillName == nil or lastCombatOptions.SupportSkillName == '(none)') and type(sidecar.SupportSkillName) == 'string' and sidecar.SupportSkillName ~= '' then
					lastCombatOptions.SupportSkillName = sidecar.SupportSkillName
				end
			end
			getgenv().SB2LastCombatOptions = lastCombatOptions
			getgenv().SB2LastSoloBlock = {
				SoloCombatResume = lastSoloBlock.SoloCombatResume,
				AutoBlockJoin = lastSoloBlock.AutoBlockJoin,
			}
		end
		local function applySoloBlockFromProfile()
			local soloWanted = lastSoloBlock.SoloCombatResume
			local blockWanted = lastSoloBlock.AutoBlockJoin
			if soloWanted == nil then
				soloWanted = readSoloResumeFileWanted()
			end
			if blockWanted == nil then
				blockWanted = readAutoblockFileWanted()
			end
			-- Waypoint first so a later resume TP uses the saved WP.
			pcall(function()
				local wp = lastCombatOptions.SoloResumeWaypoint
				if wp and Options.SoloResumeWaypoint then
					ensureDropdownHasValue(Options.SoloResumeWaypoint, wp)
				end
			end)
			pcall(function()
				local skill = lastCombatOptions.SkillName
				if skill and Options.SkillName then
					ensureDropdownHasValue(Options.SkillName, skill)
					getgenv().SB2HonorSavedCombatSkill = true
					if skill ~= '(none)' then
						getgenv().SB2UserPickedCombatSkill = true
					end
				end
			end)
			pcall(function()
				local support = lastCombatOptions.SupportSkillName
				if support and Options.SupportSkillName then
					ensureDropdownHasValue(Options.SupportSkillName, support)
				end
			end)
			pcall(function()
				if soloWanted ~= nil and Toggles.SoloCombatResume and type(Toggles.SoloCombatResume.SetValue) == 'function' then
					local t = Toggles.SoloCombatResume
					-- Always SetValue so a stuck Default=false UI recovers.
					t:SetValue(soloWanted == true)
					writeSoloResumeFile(soloWanted == true)
				end
			end)
			pcall(function()
				if blockWanted ~= nil and Toggles.AutoBlockJoin and type(Toggles.AutoBlockJoin.SetValue) == 'function' then
					local t = Toggles.AutoBlockJoin
					t:SetValue(blockWanted == true)
					getgenv().SB2AutoBlockWanted = blockWanted == true
					if type(writefile) == 'function' then
						pcall(function()
							if type(makefolder) == 'function' and type(isfolder) == 'function' then
								if CONFIG.ConfigFolder ~= '' and not isfolder(CONFIG.ConfigFolder) then
									makefolder(CONFIG.ConfigFolder)
								end
							end
							writefile(AUTOBLOCK_PATH, blockWanted and 'true' or 'false')
						end)
					end
				end
			end)
			getgenv().SB2SoloBlockProfileReady = true
			getgenv().SB2SoloBlockAppliedOnce = true
			if type(getgenv().SB2AutoBlockAfterConfig) == 'function' then
				pcall(getgenv().SB2AutoBlockAfterConfig)
			end
			-- After deferred loads settle: resume if toggle is on and server is empty.
			-- force=false so resumeSoloCombat skips when others are present.
			if soloWanted == true then
				task.defer(function()
					if getgenv().SB2ConfigLoading then
						return
					end
					local resumeFn = getgenv().SB2ResumeSoloCombat
					if type(resumeFn) == 'function' then
						pcall(resumeFn, 'profile', false)
					end
				end)
			end
		end
		local function scheduleSoloBlockApply()
			task.defer(applySoloBlockFromProfile)
			task.delay(0.15, applySoloBlockFromProfile)
			task.delay(0.5, applySoloBlockFromProfile)
			task.delay(1.25, applySoloBlockFromProfile)
			task.delay(2.5, function()
				getgenv().SB2ConfigLoading = false
				applySoloBlockFromProfile()
			end)
		end
		getgenv().SB2ApplySoloBlockFromProfile = applySoloBlockFromProfile

		local origSaveJSON = SaveManager.SaveJSON
		if type(origSaveJSON) == 'function' then
			SaveManager.SaveJSON = function(self, configName, ...)
				local encoded, okEnc, errEnc = origSaveJSON(self, configName, ...)
				if not okEnc or type(encoded) ~= 'string' or encoded == '' then
					return encoded, okEnc, errEnc
				end
				local okDecode, decoded = pcall(function()
					return HttpServiceSM:JSONDecode(encoded)
				end)
				if not okDecode or type(decoded) ~= 'table' then
					return encoded, okEnc, errEnc
				end
				if type(decoded.objects) ~= 'table' then
					decoded.objects = {}
				end
				local solo = readToggleWanted('SoloCombatResume')
				local block = readToggleWanted('AutoBlockJoin')
				local skill = readDropdownWanted('SkillName')
				local support = readDropdownWanted('SupportSkillName')
				local wp = readDropdownWanted('SoloResumeWaypoint')
				upsertToggleInObjects(decoded.objects, 'SoloCombatResume', solo)
				upsertToggleInObjects(decoded.objects, 'AutoBlockJoin', block)
				upsertDropdownInObjects(decoded.objects, 'SkillName', skill)
				upsertDropdownInObjects(decoded.objects, 'SupportSkillName', support)
				upsertDropdownInObjects(decoded.objects, 'SoloResumeWaypoint', wp)
				lastSoloBlock.SoloCombatResume = solo
				lastSoloBlock.AutoBlockJoin = block
				lastCombatOptions.SkillName = skill
				lastCombatOptions.SupportSkillName = support
				lastCombatOptions.SoloResumeWaypoint = wp
				getgenv().SB2LastSoloBlock = {
					SoloCombatResume = solo,
					AutoBlockJoin = block,
				}
				getgenv().SB2LastCombatOptions = lastCombatOptions
				if type(writefile) == 'function' then
					pcall(writefile, AUTOBLOCK_PATH, block and 'true' or 'false')
				end
				writeSoloResumeFile(solo)
				writeCombatSkillsSidecar(skill, support)
				local okEncode, patched = pcall(function()
					return HttpServiceSM:JSONEncode(decoded)
				end)
				if okEncode and type(patched) == 'string' then
					return patched, true
				end
				return encoded, okEnc, errEnc
			end
		end

		-- After Overwrite/Save writes the file, patch Solo/Block/skills into the JSON on disk.
		do
			local origDiskSave = SaveManager.Save
			if type(origDiskSave) == 'function' then
				SaveManager.Save = function(self, configName, ...)
					local okSave, errSave = origDiskSave(self, configName, ...)
					if not okSave then
						return okSave, errSave
					end
					local name = trimConfigName(configName)
					local path = autoloadConfigJsonPath(name)
					if type(readfile) ~= 'function' or type(writefile) ~= 'function' then
						return okSave, errSave
					end
					local okExists, exists = pcall(isfile, path)
					if not okExists or not exists then
						return okSave, errSave
					end
					local okRead, content = pcall(readfile, path)
					if not okRead or type(content) ~= 'string' then
						return okSave, errSave
					end
					local okDecode, decoded = pcall(function()
						return HttpServiceSM:JSONDecode(content)
					end)
					if not okDecode or type(decoded) ~= 'table' then
						return okSave, errSave
					end
					if type(decoded.objects) ~= 'table' then
						decoded.objects = {}
					end
					local solo = readToggleWanted('SoloCombatResume')
					local block = readToggleWanted('AutoBlockJoin')
					local skill = readDropdownWanted('SkillName')
					local support = readDropdownWanted('SupportSkillName')
					local wp = readDropdownWanted('SoloResumeWaypoint')
					upsertToggleInObjects(decoded.objects, 'SoloCombatResume', solo)
					upsertToggleInObjects(decoded.objects, 'AutoBlockJoin', block)
					upsertDropdownInObjects(decoded.objects, 'SkillName', skill)
					upsertDropdownInObjects(decoded.objects, 'SupportSkillName', support)
					upsertDropdownInObjects(decoded.objects, 'SoloResumeWaypoint', wp)
					pcall(writefile, AUTOBLOCK_PATH, block and 'true' or 'false')
					writeSoloResumeFile(solo)
					writeCombatSkillsSidecar(skill, support)
					local okEncode, patched = pcall(function()
						return HttpServiceSM:JSONEncode(decoded)
					end)
					if okEncode and type(patched) == 'string' then
						pcall(writefile, path, patched)
					end
					lastSoloBlock.SoloCombatResume = solo
					lastSoloBlock.AutoBlockJoin = block
					lastCombatOptions.SkillName = skill
					lastCombatOptions.SupportSkillName = support
					lastCombatOptions.SoloResumeWaypoint = wp
					pcall(function()
						Library:Notify(
							('Saved %q (solo=%s block=%s skill=%s)'):format(
								name,
								tostring(solo),
								tostring(block),
								tostring(skill)
							),
							3
						)
					end)
					return okSave, errSave
				end
			end
		end

		local origLoadJSON = SaveManager.LoadJSON
		if type(origLoadJSON) == 'function' then
			SaveManager.LoadJSON = function(self, content, ...)
				getgenv().SB2ConfigLoading = true
				rememberSoloBlockFromJSON(content)
				local okLoad, errLoad = origLoadJSON(self, content, ...)
				scheduleSoloBlockApply()
				return okLoad, errLoad
			end
		end

		SaveManager:BuildConfigSection(Settings)
		Settings:AddLabel('Autoload is per account. Profiles are shared — Set as autoload only changes this client.')
		Settings:AddLabel('Resume / Auto block / skills save into the profile JSON + PlayerTools/solo_resume + autoblock.')
		SaveManager:LoadAutoloadConfig()
		-- Always re-read the autoload JSON ourselves (hook can miss / race).
		pcall(function()
			local name = select(1, SaveManager:GetAutoloadConfig())
			name = trimConfigName(name)
			if name ~= '' and name ~= 'none' and configExists(name) then
				local path = autoloadConfigJsonPath(name)
				if type(readfile) == 'function' and isfile(path) then
					getgenv().SB2ConfigLoading = true
					rememberSoloBlockFromJSON(readfile(path))
					scheduleSoloBlockApply()
				end
			else
				local fileWanted = readAutoblockFileWanted()
				local soloFile = readSoloResumeFileWanted()
				if fileWanted ~= nil then
					lastSoloBlock.AutoBlockJoin = fileWanted
				end
				if soloFile ~= nil then
					lastSoloBlock.SoloCombatResume = soloFile
				end
				if fileWanted ~= nil or soloFile ~= nil then
					getgenv().SB2ConfigLoading = true
					scheduleSoloBlockApply()
				end
			end
		end)
		-- continueAfterConfig runs from scheduleSoloBlockApply after deferred loads.
		if lastSoloBlock.SoloCombatResume == nil and lastSoloBlock.AutoBlockJoin == nil then
			local fileWanted = readAutoblockFileWanted()
			local soloFile = readSoloResumeFileWanted()
			if fileWanted ~= nil then
				lastSoloBlock.AutoBlockJoin = fileWanted
			end
			if soloFile ~= nil then
				lastSoloBlock.SoloCombatResume = soloFile
			end
			if fileWanted ~= nil or soloFile ~= nil then
				getgenv().SB2ConfigLoading = true
				scheduleSoloBlockApply()
			else
				getgenv().SB2SoloBlockProfileReady = true
				getgenv().SB2ConfigLoading = false
				if type(getgenv().SB2AutoBlockAfterConfig) == 'function' then
					pcall(getgenv().SB2AutoBlockAfterConfig)
				end
			end
		end
	end)

	-- Re-apply after SaveManager deferred parsers settle.
	task.defer(function()
			-- Do not force-prefer weapon skill over a just-loaded profile skill.
		if not getgenv().SB2HonorSavedCombatSkill and type(getgenv().SB2PreferWeaponCombatSkill) == 'function' then
			pcall(getgenv().SB2PreferWeaponCombatSkill, false)
		end
	end)
	task.delay(0.15, function()
			if not getgenv().SB2HonorSavedCombatSkill and type(getgenv().SB2PreferWeaponCombatSkill) == 'function' then
			pcall(getgenv().SB2PreferWeaponCombatSkill, false)
		end
	end)
	task.delay(0.75, function()
		if not getgenv().SB2HonorSavedCombatSkill and type(getgenv().SB2PreferWeaponCombatSkill) == 'function' then
			pcall(getgenv().SB2PreferWeaponCombatSkill, false)
		end
	end)
	task.delay(1.0, function()
		if type(getgenv().SB2ApplySoloBlockFromProfile) == 'function' then
			getgenv().SB2ApplySoloBlockFromProfile()
		end
	end)

	if not getgenv().SB2PlayerToolsLoadedNotify then
		getgenv().SB2PlayerToolsLoadedNotify = true
		notify('Player Tools', 'Loaded — spectate / inventory filter (Home toggles menu)')
		task.delay(3, function()
			getgenv().SB2PlayerToolsLoadedNotify = nil
		end)
	end
end)

getgenv().SB2PlayerToolsLoading = false

if not ok then
	getgenv()[CONFIG.GenvKey] = false
	getgenv()[LIBRARY_KEY] = nil
	getgenv().SB2PlayerToolsLoading = false
	pcall(function()
		writefile('PlayerTools/_mcp_status.txt', 'PlayerTools FAILED: ' .. tostring(err))
	end)
	notify('Player Tools FAILED', tos