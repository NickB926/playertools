--[[
	PlayerTools_Starlight.lua

	Runs the real PlayerTools on the Starlight Interface Suite instead of Obsidian.

	PlayerTools_Obsidian.lua is read from disk and never written to. Two anchor lines are
	rewritten in memory so PlayerTools compiles StarlightAdapter.lua in place of
	Obsidian's Library.lua — every feature, toggle and profile keeps working
	because none of the PlayerTools logic changes.

	Fallback plan: write "obsidian" to PlayerTools/backend and reload, or run
	launch.lua with backend set to obsidian.
]]

local PT_PATH = 'PlayerTools/PlayerTools_Obsidian.lua'
local ADAPTER_PATH = 'PlayerTools/StarlightAdapter.lua'
local SL_CACHE = 'PlayerTools/StarlightSource.lua'
local SL_URL = 'https://raw.githubusercontent.com/Nebula-Softworks/Starlight-Interface-Suite/master/Source.lua'
local SL_MODEL = 132866968194043

local compile = loadstring or load

local function fail(message)
	error('[PlayerTools/Starlight] ' .. message, 0)
end

local function httpGet(url)
	local req = (syn and syn.request) or (http and http.request) or http_request or request
	if type(req) == 'function' then
		local response = req({ Url = url, Method = 'GET' })
		return response and response.Body
	end
	return game:HttpGet(url)
end

local function readIfFile(path, minBytes, mustContain)
	if type(isfile) ~= 'function' or type(readfile) ~= 'function' then
		return nil
	end
	local okExists, exists = pcall(isfile, path)
	if not (okExists and exists) then
		return nil
	end
	local okRead, body = pcall(readfile, path)
	if not okRead or type(body) ~= 'string' then
		return nil
	end
	if minBytes and #body < minBytes then
		return nil
	end
	if mustContain and not body:find(mustContain, 1, true) then
		return nil
	end
	return body
end

--============================================================================
-- 0. Tear down a previous Starlight-backed run.
--
--    PlayerTools short-circuits to SB2RefreshPlayerTools whenever it finds a
--    live window, so without this a re-run would build a fresh Starlight
--    instance that PlayerTools never adopts — leaving an orphaned ScreenGui and
--    a stale SB2StarlightLib handle.
--
--    Starlight:Destroy() does NOT always disconnect RenderStepped listeners;
--    each reload leaked ~15–20 until FPS tanked. Scrub them explicitly.
--============================================================================

do
	local g = getgenv()
	if g.SB2PlayerToolsLoading == true then
		local since = tonumber(g.SB2PlayerToolsLoadingSince) or 0
		if since > 0 and (os.clock() - since) < 90 then
			warn('[PlayerTools/Starlight] load already in progress — skipping duplicate run')
			return
		end
	end
end

local function disconnectStarlightLibHooks()
	if type(getconnections) ~= 'function' then
		return 0
	end
	local RS = game:GetService('RunService')
	local n = 0
	for _, sig in ipairs({ 'RenderStepped', 'Heartbeat', 'Stepped' }) do
		local ok, cons = pcall(getconnections, RS[sig])
		if not ok or type(cons) ~= 'table' then
			continue
		end
		for _, conn in ipairs(cons) do
			local src = ''
			pcall(function()
				src = debug.info(conn.Function, 's') or ''
			end)
			if src == '[string "Starlight"]' then
				pcall(function()
					conn:Disconnect()
				end)
				n += 1
			end
		end
	end
	return n
end

local function disconnectLeakedPlayerToolsHooks()
	if type(getconnections) ~= 'function' then
		return 0
	end
	local RS = game:GetService('RunService')
	local live = {}
	for _, key in ipairs({
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
	}) do
		local c = getgenv()[key]
		if c then
			live[c] = true
		end
	end
	local n = 0
	for _, sig in ipairs({ 'RenderStepped', 'Heartbeat', 'Stepped' }) do
		local ok, cons = pcall(getconnections, RS[sig])
		if not ok or type(cons) ~= 'table' then
			continue
		end
		for _, conn in ipairs(cons) do
			if live[conn] then
				continue
			end
			local src = ''
			pcall(function()
				src = debug.info(conn.Function, 's') or ''
			end)
			if src == '[string "PlayerTools_Starlight"]' then
				pcall(function()
					conn:Disconnect()
				end)
				n += 1
			end
		end
	end
	return n
end

local function disconnectStarlightRenderStepped()
	return disconnectStarlightLibHooks() + disconnectLeakedPlayerToolsHooks()
end

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
		if src == '' or src == '?' then
			pcall(function()
				cn:Disconnect()
			end)
			n += 1
		end
	end
	return n
end

local function countStarlightHooks()
	if type(getconnections) ~= 'function' then
		return 0, 0
	end
	local RS = game:GetService('RunService')
	local star, anon = 0, 0
	local ok, cons = pcall(getconnections, RS.RenderStepped)
	if ok and type(cons) == 'table' then
		for _, cn in ipairs(cons) do
			local src = ''
			pcall(function()
				src = debug.info(cn.Function, 's') or ''
			end)
			if src == '[string "Starlight"]' then
				star += 1
			elseif src == '' or src == '?' then
				anon += 1
			end
		end
	end
	return star, anon
end

local function scrubAllLeakedHooks()
	local totals = { star = 0, pt = 0, anon = 0, passes = 0 }
	for pass = 1, 30 do
		local s = disconnectStarlightLibHooks()
		local p = disconnectLeakedPlayerToolsHooks()
		local a = disconnectOrphanAnonymousHeartbeats()
		totals.star += s
		totals.pt += p
		totals.anon += a
		totals.passes = pass
		if s + p + a == 0 then
			break
		end
	end
	return totals
end

getgenv().SB2DisconnectStarlightLibHooks = disconnectStarlightLibHooks
getgenv().SB2DisconnectLeakedPlayerToolsHooks = disconnectLeakedPlayerToolsHooks
getgenv().SB2DisconnectStarlightRenderStepped = disconnectStarlightRenderStepped
getgenv().SB2ScrubAllLeakedHooks = scrubAllLeakedHooks
getgenv().SB2CountStarlightRenderStepped = function()
	return select(1, countStarlightHooks())
end
getgenv().SB2StarlightRSLeakThreshold = 35

do
	local g = getgenv()

	local previous = g.SB2StarlightLib
	if type(previous) == 'table' then
		pcall(function()
			previous:Destroy()
		end)
		if typeof(previous.Instance) == 'Instance' then
			pcall(function()
				previous.Instance:Destroy()
			end)
		end
	end
	local leaked = scrubAllLeakedHooks()
	if leaked.star + leaked.pt + leaked.anon > 0 then
		warn(('[PlayerTools/Starlight] scrubbed %d Starlight, %d PT, %d anon HB hooks (%d passes)'):format(
			leaked.star,
			leaked.pt,
			leaked.anon,
			leaked.passes
		))
	end
	g.SB2StarlightLib = nil
	g.SB2StarlightAdapterSource = nil

	local function sweep(container)
		if not container then
			return
		end
		local pending = {}
		for _, child in ipairs(container:GetChildren()) do
			if not child:IsA('ScreenGui') then
				continue
			end
			if child:GetAttribute('SB2StarlightPlayerTools') == true
				or child:GetAttribute('SB2PlayerTools') == true
				or child.Name == 'SB2PlayerTools'
				or child.Name == 'Starlight Interface Suite'
				or child.Name == 'Starlight'
				or (child:FindFirstChild('MainWindow') and child.MainWindow:FindFirstChild('Sidebar'))
			then
				pending[#pending + 1] = child
			end
		end
		for _, child in ipairs(pending) do
			pcall(function()
				child:Destroy()
			end)
		end
	end
	local function sweepAll()
		sweep(game:GetService('CoreGui'))
		sweep(game:GetService('CoreGui'):FindFirstChild('RobloxGui'))
		if type(gethui) == 'function' then
			pcall(function()
				sweep(gethui())
			end)
		end
		local lp = game:GetService('Players').LocalPlayer
		sweep(lp and lp:FindFirstChild('PlayerGui'))
	end
	sweepAll()

	-- Make PlayerTools take the full-load path rather than refreshing in place.
	g.SB2RefreshPlayerTools = nil
	g.SB2PlayerTools = false
	g.SB2PlayerToolsGui = nil
	g.SB2PlayerToolsLibrary = nil
	g.Library = nil
end

--============================================================================
-- 1. Starlight needs its UI model via GetObjects — check before doing work.
--============================================================================

-- Straight after a join or teleport the asset usually is not fetchable yet, so a
-- single attempt here is what used to send launch.lua down the Obsidian fallback.
local okModel, model
for attempt = 1, 6 do
	okModel, model = pcall(function()
		local objects = game:GetObjects('rbxassetid://' .. SL_MODEL)
		return objects and objects[1]
	end)
	if okModel and model then
		break
	end
	task.wait(attempt * 0.5)
end
if not okModel or not model then
	fail(
		('Starlight UI model %d could not load (GetObjects blocked). '):format(SL_MODEL)
			.. 'Rejoin, or set PlayerTools/backend to obsidian for the backup UI.'
	)
end

--============================================================================
-- 2. Starlight library (cache first, then network).
--============================================================================

local starlightSource = readIfFile(SL_CACHE, 20000, 'CreateWindow')
if not starlightSource then
	local okFetch, fetched = pcall(httpGet, SL_URL)
	if not okFetch or type(fetched) ~= 'string' or #fetched < 20000 then
		fail('could not download Starlight and no cache at ' .. SL_CACHE)
	end
	starlightSource = fetched
	if type(writefile) == 'function' then
		pcall(writefile, SL_CACHE, starlightSource)
	end
end

local starlightFactory = compile(starlightSource, 'Starlight')
if not starlightFactory then
	fail('Starlight source failed to compile')
end

local okInit, Starlight = pcall(starlightFactory)
if not okInit or type(Starlight) ~= 'table' or type(Starlight.CreateWindow) ~= 'function' then
	fail('Starlight failed to initialize: ' .. tostring(Starlight))
end

getgenv().SB2StarlightLib = Starlight

--============================================================================
-- 3. Adapter source (compiled later by PlayerTools itself).
--============================================================================

local adapterSource = readIfFile(ADAPTER_PATH, 1000, 'CreateWindow')
if not adapterSource then
	fail('missing or truncated ' .. ADAPTER_PATH)
end
getgenv().SB2StarlightAdapterSource = adapterSource

--============================================================================
-- 4. Patch PlayerTools in memory.
--============================================================================

local playerToolsSource = readIfFile(PT_PATH, 100000, 'CreateWindow')
if not playerToolsSource then
	fail('missing or truncated ' .. PT_PATH)
end

local patches = {
	{
		name = 'library source',
		from = "	local okLib, librarySource = pcall(httpGet, CONFIG.UIRepo .. 'Library.lua')",
		to = '	local okLib, librarySource = true, getgenv().SB2StarlightAdapterSource',
	},
	{
		-- Must not overwrite ObsidianLibrary.lua — that is the Obsidian fallback.
		name = 'cache write',
		from = '		writeLibCache(librarySource)',
		to = '		-- writeLibCache skipped: Starlight backend',
	},
	{
		-- Obsidian's ThemeManager pokes Obsidian internals the adapter does not have.
		name = 'theme manager',
		from = "		local ThemeManager = compile(httpGet(CONFIG.UIRepo .. 'addons/ThemeManager.lua'))()",
		to = "		local ThemeManager = error('[Starlight] ThemeManager disabled', 0)",
	},
	{
		name = 'window size',
		from = '\tWindowSize = UDim2.fromOffset(560, 520),',
		to = '\tWindowSize = UDim2.fromOffset(920, 600),',
	},
}

for _, patch in ipairs(patches) do
	local _, count = playerToolsSource:gsub(patch.from:gsub('(%W)', '%%%1'), '')
	if count ~= 1 then
		fail(
			('anchor "%s" matched %d times (expected 1) — PlayerTools_Obsidian.lua changed shape'):format(
				patch.name,
				count
			)
		)
	end
	playerToolsSource = playerToolsSource:gsub(
		patch.from:gsub('(%W)', '%%%1'),
		(patch.to:gsub('%%', '%%%%')),
		1
	)
end

--============================================================================
-- 5. Run it.
--============================================================================

local playerToolsFunc, compileError = compile(playerToolsSource, 'PlayerTools_Starlight')
if not playerToolsFunc then
	fail('patched PlayerTools failed to compile: ' .. tostring(compileError))
end

local okRun, runError = pcall(playerToolsFunc)
if not okRun then
	getgenv().SB2PlayerToolsBackend = nil
	fail('PlayerTools errored on Starlight: ' .. tostring(runError))
end

local loadedLib = getgenv().SB2PlayerToolsLibrary
if type(loadedLib) ~= 'table' or loadedLib.Backend ~= 'Starlight' then
	getgenv().SB2PlayerToolsBackend = nil
	fail(
		'Starlight adapter not active after load (Backend='
			.. tostring(loadedLib and loadedLib.Backend)
			.. '). Use PlayerTools/launch.lua — do not run PlayerTools_Obsidian.lua directly.'
	)
end
getgenv().SB2PlayerToolsBackend = 'Starlight'

-- Watchdog is owned by launch.lua (includes >80 emergency scrub during live sessions).
-- Do not install a weaker fallback here — it left 200+ hooks at 3 FPS with "not auto-scrubbing".
if type(getgenv().SB2StartHookLeakWatchdog) == 'function' then
	pcall(getgenv().SB2StartHookLeakWatchdog)
end
