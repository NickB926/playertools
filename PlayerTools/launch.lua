--[[
	PlayerTools/launch.lua

	Single entry point that decides which UI backend PlayerTools starts on, so
	the choice lives in one place instead of being duplicated across the
	KeepPlayerTools.iy teleport stub, AutoBlock.iy and init.lua.

	Backend is chosen by PlayerTools/backend:
	    "obsidian"  -> PlayerTools_Obsidian.lua   (backed-up Obsidian UI)
	    anything else / missing -> PlayerTools_Starlight.lua when it exists

	PlayerTools.lua itself is a thin shim that always calls this file.

	If the Starlight backend throws for any reason, this falls back to Obsidian
	automatically — the whole point of keeping both builds around.
]]

local compile = loadstring or load

local SCRUB_PASSES = 30
local STARLIGHT_RS_LEAK_THRESHOLD = 35
local LIVE_CONN_KEYS = {
	'SB2CameraRecoveryConn',
	'SB2AutoAttackConn',
	'SB2CombatAnchorConn',
	'SB2AutoSkillOnlyConn',
	'SB2DiveFarmConn',
	'SB2BossComboScanConn',
	'SB2NoStreamConn',
	'SB2DefaultCursorLockConn',
	'SB2ExposureLockConn',
	'SB2MaxZoomLockConn',
	'SB2MouseSensLockConn',
	'SB2HookWatchdogConn',
}

local function buildLiveConnSet()
	local live = {}
	for _, key in ipairs(LIVE_CONN_KEYS) do
		local c = getgenv()[key]
		if c then
			live[c] = true
		end
	end
	return live
end

local function countStarlightRenderStepped()
	if type(getconnections) ~= 'function' then
		return 0
	end
	local RS = game:GetService('RunService')
	local n = 0
	local ok, cons = pcall(getconnections, RS.RenderStepped)
	if ok and type(cons) == 'table' then
		for _, cn in ipairs(cons) do
			local src = ''
			pcall(function()
				src = debug.info(cn.Function, 's') or ''
			end)
			if src == '[string "Starlight"]' then
				n += 1
			end
		end
	end
	return n
end

-- Starlight:Destroy() leaves RenderStepped hooks behind; scrub on every launch.
local function disconnectOrphanAnonymousHeartbeats()
	if type(getconnections) ~= 'function' then
		return 0
	end
	local RS = game:GetService('RunService')
	local n = 0
	local ok, cons = pcall(getconnections, RS.Heartbeat)
	if not ok or type(cons) ~= 'table' then
		return 0
	end
	for _, cn in ipairs(cons) do
		local src = ''
		pcall(function()
			src = debug.info(cn.Function, 's') or ''
		end)
		-- Orphaned PlayerTools reloads often show as "?" on Potassium.
		if src == '' or src == '?' then
			pcall(function()
				cn:Disconnect()
			end)
			n += 1
		end
	end
	return n
end

local function scrubStarlightHookBatch(live)
	if type(getconnections) ~= 'function' then
		return 0
	end
	local RS = game:GetService('RunService')
	live = live or buildLiveConnSet()
	local n = 0
	for _, sig in ipairs({ 'RenderStepped', 'Heartbeat', 'Stepped' }) do
		local ok, cons = pcall(getconnections, RS[sig])
		if ok and type(cons) == 'table' then
			for _, cn in ipairs(cons) do
				local src = ''
				pcall(function()
					src = debug.info(cn.Function, 's') or ''
				end)
				local orphanPt = src == '[string "PlayerTools_Starlight"]' and not live[cn]
				if src == '[string "Starlight"]' or orphanPt then
					pcall(function()
						cn:Disconnect()
					end)
					n += 1
				end
			end
		end
	end
	return n
end

local function aggressiveScrubStarlightHooks(maxStar, maxPasses)
	maxStar = maxStar or STARLIGHT_RS_LEAK_THRESHOLD
	maxPasses = maxPasses or 60
	local lastStar = countStarlightRenderStepped()
	for pass = 1, maxPasses do
		local n = scrubStarlightHookBatch(buildLiveConnSet())
		disconnectOrphanAnonymousHeartbeats()
		lastStar = countStarlightRenderStepped()
		if lastStar <= maxStar then
			return lastStar, pass
		end
		if n > 0 then
			task.wait()
		else
			break
		end
	end
	return lastStar, maxPasses
end

local function teardownStarlightLeaks()
	local g = getgenv()
	local prev = g.SB2StarlightLib
	if type(prev) == 'table' then
		pcall(function()
			prev:Destroy()
		end)
		if typeof(prev.Instance) == 'Instance' then
			pcall(function()
				prev.Instance:Destroy()
			end)
		end
	end
	g.SB2StarlightLib = nil
	g.SB2StarlightAdapterSource = nil
	if type(getconnections) == 'function' then
		scrubStarlightHookBatch(buildLiveConnSet())
		local starLeft, scrubPasses = aggressiveScrubStarlightHooks(STARLIGHT_RS_LEAK_THRESHOLD, 60)
		if starLeft > STARLIGHT_RS_LEAK_THRESHOLD then
			warn(('[PlayerTools] scrub finished with %d Starlight RS hooks after %d passes'):format(
				starLeft,
				scrubPasses
			))
		end
	end
	local function sweep(container)
		if not container then
			return
		end
		for _, child in ipairs(container:GetChildren()) do
			if child:IsA('ScreenGui') and child:GetAttribute('SB2StarlightPlayerTools') == true then
				pcall(function()
					child:Destroy()
				end)
			end
		end
	end
	pcall(function()
		sweep(game:GetService('CoreGui'))
	end)
	pcall(function()
		if type(gethui) == 'function' then
			sweep(gethui())
		end
	end)
	local anon = disconnectOrphanAnonymousHeartbeats()
	if anon > 0 then
		warn(('[PlayerTools] disconnected %d orphaned Heartbeat hooks'):format(anon))
	end
	-- Second pass for anon hooks released by first pass.
	for _ = 1, 4 do
		local n = disconnectOrphanAnonymousHeartbeats()
		if n == 0 then
			break
		end
		anon += n
	end
	g.SB2RefreshPlayerTools = nil
	g.SB2PlayerTools = false
	g.SB2PlayerToolsGui = nil
	g.SB2PlayerToolsLibrary = nil
	g.Library = nil
	g.SB2PlayerToolsBackend = nil
	g.SB2PlayerToolsBackendError = nil
end

local function startHookLeakWatchdog()
	local g = getgenv()
	if g.SB2HookWatchdogConn then
		pcall(function()
			g.SB2HookWatchdogConn:Disconnect()
		end)
		g.SB2HookWatchdogConn = nil
	end
	local RS = game:GetService('RunService')
	local acc = 0
	g.SB2HookWatchdogConn = RS.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 20 then
			return
		end
		acc = 0
		local star = countStarlightRenderStepped()
		if star <= STARLIGHT_RS_LEAK_THRESHOLD then
			return
		end
		-- Active session with extreme leak: scrub beats running at 3 FPS with 200+ hooks.
		if g.SB2PlayerTools == true then
			if star > 80 then
				warn(('[PlayerTools] FPS emergency: scrubbing %d leaked Starlight hooks'):format(star))
				pcall(function()
					if type(g.SB2StarlightLib) == 'table' then
						g.SB2StarlightLib:Destroy()
					end
				end)
				g.SB2StarlightLib = nil
				teardownStarlightLeaks()
				local after = countStarlightRenderStepped()
				pcall(function()
					game:GetService('StarterGui'):SetCore('SendNotification', {
						Title = 'PlayerTools FPS',
						Text = ('Scrubbed hook leak (%d→%d) — run launch.lua once'):format(star, after),
						Duration = 12,
					})
				end)
				return
			end
			warn(('[PlayerTools] %d Starlight RS hooks (session active — OK if under ~25)'):format(star))
			return
		end
		warn(('[PlayerTools] Starlight hook leak: %d RenderStepped — auto-scrubbing'):format(star))
		local prev = g.SB2StarlightLib
		if type(prev) == 'table' then
			pcall(function()
				prev:Destroy()
			end)
		end
		g.SB2StarlightLib = nil
		teardownStarlightLeaks()
		local after = countStarlightRenderStepped()
		pcall(function()
			game:GetService('StarterGui'):SetCore('SendNotification', {
				Title = 'PlayerTools FPS fix',
				Text = ('Scrubbed %d leaked Starlight hooks — run PlayerTools once'):format(star),
				Duration = 10,
			})
		end)
	end)
end

getgenv().SB2CountStarlightRenderStepped = countStarlightRenderStepped
getgenv().SB2StarlightRSLeakThreshold = STARLIGHT_RS_LEAK_THRESHOLD
getgenv().SB2TeardownStarlightLeaks = teardownStarlightLeaks
getgenv().SB2AggressiveScrubStarlightHooks = aggressiveScrubStarlightHooks
getgenv().SB2RecoverStarlightFPS = function()
	teardownStarlightLeaks()
	return countStarlightRenderStepped()
end
getgenv().SB2StartHookLeakWatchdog = startHookLeakWatchdog
teardownStarlightLeaks()

local BACKEND_FILE = 'PlayerTools/backend'
local LOG_FILE = 'PlayerTools/backend_log.txt'
local STARLIGHT_PATHS = { 'PlayerTools/PlayerTools_Starlight.lua', 'PlayerTools_Starlight.lua' }
local OBSIDIAN_PATHS = { 'PlayerTools/PlayerTools_Obsidian.lua', 'PlayerTools_Obsidian.lua' }

-- Which backend actually started, and why, is otherwise invisible: a Starlight
-- crash used to fall through to Obsidian with nothing but a warn, so the old UI
-- would silently come back with no way to tell it apart from a normal load.
local function record(backend, detail)
	getgenv().SB2PlayerToolsBackend = backend
	getgenv().SB2PlayerToolsBackendError = detail
	local line = os.date('%Y-%m-%d %H:%M:%S') .. '  backend=' .. tostring(backend)
	if detail then
		line = line .. '\n' .. tostring(detail)
	end
	if type(writefile) == 'function' then
		pcall(writefile, LOG_FILE, line)
	end
end

local function announce(text)
	warn('[PlayerTools] ' .. text)
	pcall(function()
		game:GetService('StarterGui'):SetCore('SendNotification', {
			Title = 'PlayerTools: Obsidian fallback',
			Text = text,
			Duration = 12,
		})
	end)
end

local function exists(path)
	if type(isfile) ~= 'function' then
		return false
	end
	local ok, is = pcall(isfile, path)
	return ok and is == true
end

local function wantedBackend()
	if not exists(BACKEND_FILE) then
		return nil
	end
	local ok, body = pcall(readfile, BACKEND_FILE)
	if not ok then
		return nil
	end
	return (tostring(body):lower():gsub('%s', ''))
end

local function run(path)
	local src = readfile(path)
	local fn, err = compile(src, path)
	if not fn then
		error('[PlayerTools] compile failed (' .. path .. '): ' .. tostring(err))
	end
	return fn()
end

local function hideRobloxChat()
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

getgenv().SB2HideGameChat = hideRobloxChat
getgenv().SB2EnsureGameChat = ensureGameChatVisible

-- The teleport stubs fire this file the moment the new place starts, before the
-- client has really joined. Obsidian copes with that; Starlight needs GetObjects
-- and a PlayerGui, so give the client a moment rather than failing over to the
-- old UI for what is only a timing problem.
local function waitForClient(timeout)
	local Players = game:GetService('Players')
	local deadline = os.clock() + timeout
	while os.clock() < deadline do
		local lp = Players.LocalPlayer
		if game:IsLoaded() and lp and lp:FindFirstChildOfClass('PlayerGui') then
			return true
		end
		task.wait(0.25)
	end
	return false
end

local function shouldSkipStarlightLaunch(preStar)
	local g = getgenv()
	if g.SB2PlayerToolsManualUnload == true then
		warn('[PlayerTools] launch skipped — manual unload')
		return true
	end
	if g.SB2PlayerToolsLoading == true then
		local since = tonumber(g.SB2PlayerToolsLoadingSince) or 0
		-- Stuck loads used to block floor-hop relaunches for 90s.
		if since > 0 and (os.clock() - since) < 25 then
			warn('[PlayerTools] launch skipped — load already in progress')
			return true
		end
		g.SB2PlayerToolsLoading = false
		g.SB2PlayerToolsLoadingSince = nil
	end
	local gui = g.SB2PlayerToolsGui
	local lib = g.SB2PlayerToolsLibrary
	if g.SB2PlayerTools == true
		and typeof(gui) == 'Instance'
		and gui.Parent
		and type(lib) == 'table'
		and lib.Backend == 'Starlight'
		and preStar <= STARLIGHT_RS_LEAK_THRESHOLD
	then
		warn('[PlayerTools] Starlight already live — skipping duplicate launch')
		record('starlight')
		startHookLeakWatchdog()
		return true
	end
	return false
end

local requested = wantedBackend()
local reason

local starlightPath
for _, path in ipairs(STARLIGHT_PATHS) do
	if exists(path) then
		starlightPath = path
		break
	end
end

if requested == 'obsidian' then
	reason = 'PlayerTools/backend file requests obsidian'
elseif not starlightPath then
	reason = 'PlayerTools_Starlight.lua is missing'
else
	local ready = waitForClient(30)
	local preStar = countStarlightRenderStepped()
	if shouldSkipStarlightLaunch(preStar) then
		return
	end
	getgenv().SB2PlayerToolsLoading = true
	getgenv().SB2PlayerToolsLoadingSince = os.clock()
	if preStar > STARLIGHT_RS_LEAK_THRESHOLD then
		warn(('[PlayerTools] %d leaked Starlight hooks before load — scrubbing'):format(preStar))
		aggressiveScrubStarlightHooks(STARLIGHT_RS_LEAK_THRESHOLD, 60)
		preStar = countStarlightRenderStepped()
	end
	if preStar > 80 then
		reason = ('Too many leaked Starlight hooks (%d) after scrub — run PlayerTools/emergency_fps.lua, then launch.lua'):format(
			preStar
		)
		getgenv().SB2PlayerToolsLoading = false
		getgenv().SB2PlayerToolsLoadingSince = nil
	else
	local ok, err = xpcall(run, function(e)
		return tostring(e) .. '\n' .. debug.traceback('', 2)
	end, starlightPath)
	if ok then
		local lib = getgenv().SB2PlayerToolsLibrary
		if getgenv().SB2PlayerTools == true
			and type(lib) == 'table'
			and lib.Backend == 'Starlight'
			and type(getgenv().SB2StarlightLib) == 'table'
		then
			record('starlight')
			startHookLeakWatchdog()
			hideRobloxChat()
			ensureGameChatVisible()
			return
		end
		reason = ('Starlight finished but session not live (SB2PlayerTools=%s, Backend=%s, starlib=%s)'):format(
			tostring(getgenv().SB2PlayerTools),
			tostring(lib and lib.Backend),
			tostring(type(getgenv().SB2StarlightLib))
		)
	else
		reason = ('Starlight backend threw (client ready=%s):\n%s'):format(tostring(ready), tostring(err))
	end
	-- Starlight may have half-built a window before dying; clear the flags so
	-- the Obsidian load below does a full build rather than an in-place refresh.
	getgenv().SB2PlayerTools = false
	getgenv().SB2RefreshPlayerTools = nil
	getgenv().SB2PlayerToolsGui = nil
	getgenv().SB2PlayerToolsLoading = false
	getgenv().SB2PlayerToolsLoadingSince = nil
	end
end

record('obsidian', reason)
if requested ~= 'obsidian' then
	announce('Starlight failed, loaded old Obsidian UI instead. Details in ' .. LOG_FILE)
end

for _, path in ipairs(OBSIDIAN_PATHS) do
	if exists(path) then
		getgenv().SB2AllowObsidianFallback = true
		hideRobloxChat()
		ensureGameChatVisible()
		return run(path)
	end
end

error('[PlayerTools] no PlayerTools_Obsidian.lua backup found')
