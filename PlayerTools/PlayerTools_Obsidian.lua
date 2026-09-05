--[[
    PlayerTools_Obsidian.lua — Swordburst 2 feature app (Ataraxia chrome)
    Spectate + stream-spectate + view other players' inventories.
    Remote upgrade / remote dismantle (no NPC / no dismantle GUI).
    Items / Wiki tab: snapshot Database.Items, wiki dumps (stats/buffs/icon/flags), aura chests, titling.
    HiveMind — pick a commanding client; others TP / follow / stack via Hive tab.
    Combat tab: auto skill + auto attack (same stack as AutoFarm).
    Also launches Infinite Yield on start.

    Farm / vacuum / skills live in AutoFarm/AutoFarm.lua now
    (combat toggles are also on PlayerTools → Combat).

    Prefer PlayerTools/PlayerTools.lua or launch.lua (sets Ataraxia chrome).
    Toggle UI: Home (AutoFarm uses End).
    Refresh: run launch.lua / PlayerTools.lua again.

    Force re-run after a failed attempt. Do not use loadstring(...)() —
    a compile miss shows up as "attempt to call a nil value" on Script '', Line 1.
        getgenv().SB2PlayerTools = false
        local p = (isfile('PlayerTools.lua') and 'PlayerTools.lua') or 'PlayerTools/PlayerTools.lua'
        local fn, err = (loadstring or load)(readfile(p), p)
        if not fn then error('PlayerTools compile: '..tostring(err)) end
        fn()

    LUAU 200-REGISTER RULE (permanent):
    Large features MUST be ;(function() ... end)() or a separate .lua module.
    Bare `do`/`end` still shares the outer function's 200-local budget — that is
    why "Out of local registers" keeps returning when tabs grow. Combat /
    Inventory / Items / HiveMind already use own function scopes; new tabs too.
]]

-- Ataraxia-only chrome. Direct runs still force AtaraxiaLibrary.
do
	local g = getgenv()
	g.SB2UseAtaraxiaLib = true
	g.SB2AllowObsidianFallback = nil
	g.SB2StarlightAdapterSource = nil
end

-- One Tool window. HttpGet used to yield here so autoexec could start
-- PlayerTools.lua + init.lua + event_dive at once (stacked UIs).
do
	local g = getgenv()
	-- #region agent log
	local function dbgFling(hyp, loc, msg, data)
		pcall(function()
			local Hs = game:GetService('HttpService')
			local payload = Hs:JSONEncode({
				sessionId = '7e9135',
				runId = tostring(g.SB2FlingDebugRun or 'boot'),
				hypothesisId = hyp,
				location = loc,
				message = msg,
				data = data or {},
				timestamp = math.floor(os.clock() * 1000),
			})
			if type(appendfile) == 'function' then
				appendfile('debug-7e9135.log', payload .. '\n')
			elseif type(writefile) == 'function' then
				writefile('debug-7e9135.log', payload .. '\n')
			end
		end)
	end
	g.SB2DbgFling = dbgFling
	g.SB2FlingDebugRun = 'boot-' .. tostring(math.floor(os.clock()))
	local function dbgHrpSnapshot(tag)
		local snap = { tag = tag }
		pcall(function()
			local lp = game:GetService('Players').LocalPlayer
			local folder = workspace:FindFirstChild('Characters')
			local live = (lp and folder and folder:FindFirstChild(lp.Name)) or (lp and lp.Character)
			local hrp = live and (live:FindFirstChild('HumanoidRootPart') or live.PrimaryPart)
			local hum = live and live:FindFirstChildOfClass('Humanoid')
			snap.y = hrp and math.floor(hrp.Position.Y + 0.5) or nil
			snap.anchored = hrp and hrp.Anchored or nil
			snap.vel = hrp and math.floor(hrp.AssemblyLinearVelocity.Magnitude + 0.5) or nil
			snap.state = hum and hum:GetState().Name or nil
			snap.platform = hum and hum.PlatformStand or nil
			snap.anchorOn = g.SB2CombatAnchorOn == true
			snap.boss = g.SB2BossRouteWanted == true
			snap.softFlag = g.SB2SoftPlayerToolsReload == true
			snap.preserve = g.SB2SoftReloadPreserveFlight == true
			snap.skipHold = g.SB2SkipHoldAnchorOnBoot == true
			snap.animOn = type(g.SB2WeaponModState) == 'table' and g.SB2WeaponModState.AnimEnabled == true
			snap.ghost = type(g._SB2AnimGhost) == 'table'
			local cam = workspace.CurrentCamera
			local orphans = 0
			local cross = 0
			if cam then
				for _, d in ipairs(cam:GetDescendants()) do
					if d.Name == '_SB2AnimGhostChar'
						or d.Name == '_SB2AnimGhostWorld'
						or d.Name == '_SB2AnimGhostWeapons'
					then
						orphans += 1
					end
					if d:IsA('Motor6D') or d:IsA('Weld') then
						local items = workspace:FindFirstChild('CharacterItems')
						local uid = lp and tostring(lp.UserId)
						local mine = items and uid and items:FindFirstChild(uid)
						for _, side in ipairs({ d.Part0, d.Part1 }) do
							if side and live and side:IsDescendantOf(live) then
								cross += 1
							elseif side and mine and side:IsDescendantOf(mine) then
								cross += 1
							end
						end
					end
				end
			end
			snap.orphans = orphans
			snap.crossWelds = cross
		end)
		return snap
	end
	dbgFling('A,B,C,D,E', 'boot:start', 'script boot enter', dbgHrpSnapshot('enter'))
	-- Sample HRP for 3s after boot to catch fling moment.
	-- NOTE: do NOT mass-disconnect RunService hooks here — soft-refresh early-returns
	-- below and would leave the live GUI with all Heartbeats dead ("script not loading").
	-- Orphan hook purge lives in soft-reload teardown + full-rebuild path only.
	task.spawn(function()
		local run = g.SB2FlingDebugRun
		for i = 1, 15 do
			task.wait(0.2)
			if g.SB2FlingDebugRun ~= run then
				break
			end
			local snap = dbgHrpSnapshot('t' .. tostring(i * 0.2))
			if (snap.vel and snap.vel > 60)
				or snap.state == 'Ragdoll'
				or snap.state == 'FallingDown'
				or snap.state == 'Physics'
				or (snap.crossWelds and snap.crossWelds > 0)
				or (snap.y and snap.y < -20)
			then
				dbgFling('A,B,D,E', 'boot:sample', 'anomaly during boot window', snap)
			elseif i == 1 or i == 5 or i == 10 or i == 15 then
				dbgFling('B,C,E', 'boot:sample', 'boot sample', snap)
			end
		end
	end)
	-- #endregion
	-- FIRST: tear down client anim ghosts. Clone keeps Motor6D → live CharacterItems.Handle;
	-- leaving that weld up for even one frame on reload ragdolls you.
	pcall(function()
		if type(g.SB2AnimSwapStop) == 'function' then
			g.SB2AnimSwapStop()
		end
	end)
	pcall(function()
		local ghost = g._SB2AnimGhost
		if type(ghost) == 'table' then
			pcall(function()
				if ghost.hb then
					ghost.hb:Disconnect()
				end
			end)
			pcall(function()
				if ghost.played then
					ghost.played:Disconnect()
				end
			end)
			pcall(function()
				if ghost.weaponFolder then
					ghost.weaponFolder:Destroy()
				end
			end)
			pcall(function()
				if ghost.clone then
					ghost.clone:Destroy()
				end
			end)
			pcall(function()
				if ghost.world then
					ghost.world:Destroy()
				end
			end)
			g._SB2AnimGhost = nil
		end
		local cam = workspace.CurrentCamera
		if cam then
			for _, name in ipairs({
				'_SB2AnimGhostWorld',
				'_SB2AnimGhostChar',
				'_SB2AnimGhostWeapons',
			}) do
				local orphan = cam:FindFirstChild(name)
				if orphan then
					orphan:Destroy()
				end
			end
			for _, d in ipairs(cam:GetDescendants()) do
				if d.Name == '_SB2AnimGhostWorld'
					or d.Name == '_SB2AnimGhostChar'
					or d.Name == '_SB2AnimGhostWeapons'
				then
					pcall(function()
						d:Destroy()
					end)
				end
			end
		end
		if type(g.SB2WeaponModState) == 'table' then
			-- Don't auto-reapply anim on this boot — user re-enables or hits Re-apply.
			g.SB2WeaponModState._AnimSkipAutoApply = true
			g.SB2WeaponModState.AnimEnabled = false
		end
		g._SB2AnimGhostWant = nil
	end)
	-- #region agent log
	dbgFling('A,D', 'boot:afterGhostKill', 'after anim ghost kill', dbgHrpSnapshot('afterGhostKill'))
	-- #endregion
	-- Stuck mid-load from a prior crash must not soft-lock relaunches.
	if g.SB2PlayerToolsLoading == true then
		local since = tonumber(g.SB2PlayerToolsLoadingSince) or 0
		if since == 0 or (os.clock() - since) > 45 then
			g.SB2PlayerToolsLoading = false
			g.SB2PlayerToolsLoadingSince = nil
		end
	end
	local keep = g.SB2PlayerToolsGui
	local softReload = g.SB2SoftPlayerToolsReload == true
	local hopGrace = os.clock() < (tonumber(g.SB2MenuHopGraceUntil) or 0)
	-- Soft reload while floating (boss route / Anchor): remember pose so we do NOT
	-- unanchor into the void during teardown + holdCombatAnchor(4) boot.
	if softReload then
		g.SB2SoftReloadPreserveFlight = true
		g.SB2SoftReloadHadAnchor = g.SB2CombatAnchorOn == true
		g.SB2SoftReloadHadBoss = g.SB2BossRouteWanted == true
		g.SB2SoftReloadHadAutoAttack = g.SB2AutoAttackOn == true
		-- AutoSkill has no durable genv bool; connection presence is the live signal.
		g.SB2SoftReloadHadAutoSkill = false
		pcall(function()
			local c = g.SB2AutoSkillOnlyConn
			if c and (typeof(c) ~= 'RBXScriptConnection' or c.Connected ~= false) then
				g.SB2SoftReloadHadAutoSkill = true
			end
		end)
		pcall(function()
			local lp = game:GetService('Players').LocalPlayer
			local folder = workspace:FindFirstChild('Characters')
			local live = (lp and folder and folder:FindFirstChild(lp.Name))
				or (lp and lp.Character)
			local hrp = live and (live:FindFirstChild('HumanoidRootPart') or live.PrimaryPart)
			if hrp and hrp:IsA('BasePart') then
				-- Never snapshot a void pose — that would pin you under the map.
				if hrp.Position.Y > -20 then
					g.SB2SoftReloadPinCF = hrp.CFrame
				else
					g.SB2SoftReloadPinCF = nil
					-- Also drop active TP pins that point into the void.
					if typeof(g.SB2TpPinCFrame) == 'CFrame' and g.SB2TpPinCFrame.Position.Y < -20 then
						g.SB2TpPinCFrame = nil
						g.SB2TpPinActive = false
						g.SB2TpPinGen = (tonumber(g.SB2TpPinGen) or 0) + 1
						g.SB2TpPinUntil = 0
					end
				end
				g.SB2SoftReloadWasAnchored = hrp.Anchored == true
				-- Keep locked through the reload gap.
				if hrp.Anchored or g.SB2SoftReloadHadAnchor or g.SB2SoftReloadHadBoss or hrp.Position.Y > 40 then
					hrp.Anchored = true
					hrp.AssemblyLinearVelocity = Vector3.zero
					hrp.AssemblyAngularVelocity = Vector3.zero
				end
			end
		end)
		g.SB2SkipHoldAnchorOnBoot = true
	end
	-- #region agent log
	dbgFling('B,C', 'boot:softReloadGate', 'soft reload preserve decision', {
		softReload = softReload,
		preserve = g.SB2SoftReloadPreserveFlight == true,
		hadAnchor = g.SB2SoftReloadHadAnchor == true,
		hadBoss = g.SB2SoftReloadHadBoss == true,
		skipHold = g.SB2SkipHoldAnchorOnBoot == true,
		pinY = typeof(g.SB2SoftReloadPinCF) == 'CFrame' and math.floor(g.SB2SoftReloadPinCF.Position.Y + 0.5) or nil,
		hrp = dbgHrpSnapshot('softGate'),
	})
	-- #endregion
	local function tryReparent(gui)
		if typeof(gui) ~= 'Instance' or gui.Parent then
			return typeof(gui) == 'Instance' and gui.Parent ~= nil
		end
		pcall(function()
			local host = nil
			if type(gethui) == 'function' then
				local okH, h = pcall(gethui)
				if okH then
					host = h
				end
			end
			local cg = game:FindService('CoreGui') or game:GetService('CoreGui')
			host = host or (cg and cg:FindFirstChild('RobloxGui')) or cg
			gui.Parent = host
			if not gui.Parent then
				local lp = game:GetService('Players').LocalPlayer
				local pg = lp and lp:FindFirstChildOfClass('PlayerGui')
				if pg then
					gui.Parent = pg
				end
			end
			if gui.Parent then
				gui.Enabled = true
				if gui.DisplayOrder < 500 then
					gui.DisplayOrder = 998
				end
			end
		end)
		return gui.Parent ~= nil
	end
	-- Recover orphaned UI before deciding live vs destroy.
	-- Floor hops often leave Parent=nil briefly — retry instead of Destroy→full rebuild flash.
	if typeof(keep) == 'Instance' and not keep.Parent then
		local attempts = (softReload or hopGrace) and 12 or 4
		for i = 1, attempts do
			if tryReparent(keep) then
				break
			end
			if i < attempts then
				task.wait(0.35)
			end
		end
		if not keep.Parent then
			-- Dead reference — drop it so a full load can create a new ScreenGui.
			pcall(function()
				keep:Destroy()
			end)
			g.SB2PlayerToolsGui = nil
			keep = nil
			g.SB2PlayerTools = false
			-- Keep Refresh if soft/hop so a late soft path can still recover Library state.
			if not softReload and not hopGrace then
				g.SB2RefreshPlayerTools = nil
			end
		end
	end
	local parentOk = typeof(keep) == 'Instance' and keep.Parent ~= nil
	local live = parentOk and g.SB2PlayerTools == true
	local function sweepExtras()
		local function sweep(parent)
			if not parent then
				return
			end
			local liveGui = g.SB2PlayerToolsGui
			local libGui = g.Library and g.Library.ScreenGui
			for _, gui in ipairs(parent:GetChildren()) do
				if gui:IsA('ScreenGui') and gui ~= keep and gui ~= liveGui and gui ~= libGui then
					if gui:GetAttribute('SB2PlayerTools') == true
						or gui:GetAttribute('SB2StarlightPlayerTools') == true
						or gui.Name == 'SB2PlayerTools'
					then
						pcall(function()
							gui:Destroy()
						end)
					end
				end
			end
		end
		local lp = game:FindService('Players') and game:GetService('Players').LocalPlayer
		if lp then
			sweep(lp:FindFirstChild('PlayerGui'))
		end
		pcall(function()
			local cg = game:GetService('CoreGui')
			sweep(cg)
			sweep(cg:FindFirstChild('RobloxGui'))
		end)
		pcall(function()
			if type(gethui) == 'function' then
				sweep(gethui())
			end
		end)
	end
	if parentOk and type(g.SB2RefreshPlayerTools) == 'function' and g.SB2ForceFullReload ~= true then
		-- Soft refresh only — never full rebuild. Quiet keeper so it won't relaunch mid-refresh.
		g.SB2UiKeeperQuietUntil = os.clock() + 20
		g.SB2MenuHopGraceUntil = os.clock() + 20
		g.SB2MenuWantOpen = true
		sweepExtras()
		g.SB2PlayerTools = true
		pcall(g.SB2RefreshPlayerTools)
		g.SB2PlayerToolsLoading = false
		g.SB2PlayerToolsLoadingSince = nil
		g.SB2SoftPlayerToolsReload = nil
		return
	end
	if parentOk and (softReload or hopGrace or live) and g.SB2ForceFullReload ~= true then
		g.SB2UiKeeperQuietUntil = os.clock() + 20
		g.SB2MenuHopGraceUntil = os.clock() + 20
		g.SB2MenuWantOpen = true
		sweepExtras()
		g.SB2PlayerTools = true
		if type(g.SB2RefreshPlayerTools) == 'function' then
			pcall(g.SB2RefreshPlayerTools)
		end
		g.SB2PlayerToolsLoading = false
		g.SB2PlayerToolsLoadingSince = nil
		g.SB2SoftPlayerToolsReload = nil
		return
	end
	-- Full rebuild path: drop any existing GUI so CreateWindow is not soft-skipped.
	if typeof(keep) == 'Instance' then
		pcall(function()
			keep:Destroy()
		end)
		g.SB2PlayerToolsGui = nil
		keep = nil
		parentOk = false
		live = false
	end
	g.SB2ForceFullReload = nil
	-- Full rebuild: purge orphan RunService hooks from prior soft-reloads (FPS death spiral).
	-- Must run AFTER soft-refresh early-returns above, never before.
	pcall(function()
		if type(getconnections) ~= 'function' then
			return
		end
		local RS = game:GetService('RunService')
		for pass = 1, 8 do
			local n = 0
			for _, sig in ipairs({ 'Heartbeat', 'RenderStepped', 'Stepped' }) do
				local ok, cons = pcall(getconnections, RS[sig])
				if ok and type(cons) == 'table' then
					for _, cn in ipairs(cons) do
						local src = ''
						pcall(function()
							src = debug.info(cn.Function, 's') or ''
						end)
						if string.find(src, 'PlayerTools_Obsidian', 1, true)
							or string.find(src, 'PlayerTools_Starlight', 1, true)
							or src == '[string "Starlight"]'
						then
							pcall(function()
								cn:Disconnect()
							end)
							n += 1
						end
					end
				end
			end
			if n == 0 then
				break
			end
		end
		pcall(function()
			RS:UnbindFromRenderStep('SB2CamLock')
			RS:UnbindFromRenderStep('SB2CamLockLast')
		end)
	end)
	if live then
		-- Older instance without refresh: fall through so unloadExisting replaces this one window.
		g.SB2PlayerTools = false
	end
	-- Only destroy a truly dead/orphaned GUI we failed to reparent.
	if typeof(keep) == 'Instance' and not keep.Parent then
		pcall(function()
			keep:Destroy()
		end)
		g.SB2PlayerToolsGui = nil
	end
	g.SB2RefreshPlayerTools = nil
	g.SB2PlayerTools = false
	g.SB2PlayerToolsInstance = true
	g.SB2PlayerToolsInstanceAt = os.clock()
end

-- Infinite Yield — load before PlayerTools UI (skip if already running).
pcall(function()
	if getgenv().IY_LOADED or getgenv().IYLoaded or getgenv().loadedIY or IY_LOADED then
		return
	end
	local okGet, src = pcall(function()
		return game:HttpGet('https://raw.githubusercontent.com/EdgeIY/infiniteyield/master/source')
	end)
	if not okGet or type(src) ~= 'string' or src == '' then
		warn('[PlayerTools] Infinite Yield download failed')
		return
	end
	local fn, iyErr = (loadstring or load)(src)
	if not fn then
		warn('[PlayerTools] Infinite Yield compile failed: ' .. tostring(iyErr))
		return
	end
	fn()
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

local scriptPath = fileExists('PlayerTools/PlayerTools_Obsidian.lua') and 'PlayerTools/PlayerTools_Obsidian.lua'
	or fileExists('PlayerTools_Obsidian.lua') and 'PlayerTools_Obsidian.lua'
	or 'PlayerTools/PlayerTools_Obsidian.lua'

local configFolder = fileExists('PlayerTools/autoexec') and 'PlayerTools'
	or fileExists('autoexec') and '.'
	or 'PlayerTools'

local CONFIG = {
	GenvKey = 'SB2PlayerTools',
	Title = 'Ataraxia',
	Footer = 'If you gaze long into an abyss, the abyss also gazes into you.',
	WindowSize = UDim2.fromOffset(560, 520),
	WindowMinSize = Vector2.new(520, 460), -- Obsidian defaults to 480×360 min otherwise
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
local FRESH_FINDER_PATH = joinPath(CONFIG.ConfigFolder, 'fresh_server_finder.json')
local SOLO_RESUME_PATH = joinPath(CONFIG.ConfigFolder, 'solo_resume')
local COMBAT_SKILLS_PATH = joinPath(CONFIG.ConfigFolder, 'combat_skills.json')
local COMBAT_PREFS_PATH = joinPath(CONFIG.ConfigFolder, 'combat_prefs.json')
local WEAPON_MOD_PATH = joinPath(CONFIG.ConfigFolder, 'weapon_mod.json')
-- Profile-independent: dive height / flee depth / combat+dive skills.
local COMBAT_PREFS_INDEXES = {
	DiveFarmHeight = true,
	DiveFleeDepth = true,
	DiveFleeDepthBoss = true,
	SkillName = true,
	SupportSkillName = true,
	FarmSkillName = true,
	FarmSupportSkillName = true,
	FarmHealSkillName = true,
	FarmMendSkillName = true,
}
local MANUAL_UNLOAD_PATH = joinPath(CONFIG.ConfigFolder, 'manual_unload')
local ITEMS_KNOWN_PATH = joinPath(CONFIG.ConfigFolder, 'items_known.json')
local WIKI_DUMP_PATH = joinPath(CONFIG.ConfigFolder, 'wiki_dump.txt')
local TAGS_KNOWN_PATH = joinPath(CONFIG.ConfigFolder, 'tags_known.json')
local WIKI_TAGS_DUMP_PATH = joinPath(CONFIG.ConfigFolder, 'wiki_tags_dump.txt')
local LIBRARY_KEY = 'SB2PlayerToolsLibrary'
local SCRIPT_PATHS = {
	'PlayerTools/PlayerTools_Obsidian.lua',
	'PlayerTools_Obsidian.lua',
	CONFIG.ScriptPath,
}
local AUTOEXEC_PATHS = {
	'PlayerTools/autoexec',
	'autoexec',
	AUTOEXEC_PATH,
}

-- Solo resume / auto-block treat these as you (combat stays on, no block hop).
-- Whitelist by UserId only — usernames can change / become roblox_user_<id>.
local OWN_ALT_USERIDS = {
	[105008790] = true, -- NickB926
	[58534583] = true, -- NickB925
	[5629930206] = true, -- NickB910
	[2948744565] = true, -- NickB929
	[2567665744] = true, -- NickB928
	[1781632332] = true, -- dyildolover (often roblox_user_1781632332)
	[475975042] = true, -- Pyrixl
	[5512085079] = true, -- 4maug (was Formauglejuregiant)
	[3851863758] = true, -- iSweatBadges
	[4212822041] = true, -- marriel_lee
	[7519173184] = true, -- TworzTheAncientTree
	[5667361490] = true, -- TworzLeAncientTree
	[8026129747] = true, -- SimplyPeek
	[9461039114] = true, -- SimpIyLeek
	[9665540384] = true, -- SFlTST
	[9687273225] = true, -- xKilluaXx124
	[571865792] = true, -- XxBluepok
	[11416094898] = true, -- Da_TheDemeanor
	[11416160497] = true, -- Ra_TheEnlightener
	[11416154884] = true, -- Ka_TheMischief
	[11416179129] = true, -- Z4_TheEldest
	[11416183253] = true, -- Wa_TheCurious
	[11025682106] = true, -- SB2ButOnlyTrading
	[285463210] = true, -- 62qx
}
local function normalizeAltKey(raw)
	-- Only for per-account profile filenames — whitelist itself is UserId-based.
	local s = string.lower(tostring(raw or ''))
	s = s:gsub('%s+', ''):gsub('[^%w_%-]', '')
	return s
end
local function accountFileKey()
	local lp = game:GetService('Players').LocalPlayer
	local name = normalizeAltKey(lp and lp.Name or 'unknown')
	if name == '' then
		name = 'unknown'
	end
	return name
end
local function isOwnAltId(uid)
	uid = tonumber(uid)
	if not uid then
		return false
	end
	if OWN_ALT_USERIDS[uid] then
		return true
	end
	local extras = rawget(getgenv(), 'SB2OwnAltUserIds')
	return type(extras) == 'table' and extras[uid] == true
end
local function isOwnAlt(plr)
	if not plr then
		return false
	end
	local uid = tonumber(plr.UserId)
	if isOwnAltId(uid) then
		return true
	end
	-- Banned/renamed placeholder: roblox_user_<userid>
	local name = string.lower(tostring(plr.Name or ''))
	local stubId = name:match('^roblox_user_(%d+)$')
	if stubId and isOwnAltId(tonumber(stubId)) then
		return true
	end
	return false
end
getgenv().SB2IsOwnAlt = isOwnAlt
getgenv().SB2IsOwnAltId = isOwnAltId
getgenv().SB2OwnAltUserIds = getgenv().SB2OwnAltUserIds or {}
for id, v in pairs(OWN_ALT_USERIDS) do
	getgenv().SB2OwnAltUserIds[id] = v
end
-- Legacy name map kept empty for older plugins that still read SB2OwnAltNames.
getgenv().SB2OwnAltNames = getgenv().SB2OwnAltNames or {}

local notify = function(title, text)
	local now = os.clock()
	local bootQuietUntil = tonumber(getgenv().SB2NotifyQuietUntil) or 0
	if now < bootQuietUntil then
		return
	end
	local last = getgenv().SB2LastNotify
	local key = tostring(title) .. '\0' .. tostring(text)
	if type(last) == 'table' and last.key == key and (now - (tonumber(last.at) or 0)) < 6 then
		return
	end
	local recent = tonumber(getgenv().SB2NotifyCountWindow) or 0
	local windowStart = tonumber(getgenv().SB2NotifyWindowStart) or 0
	if now - windowStart > 8 then
		windowStart = now
		recent = 0
	end
	recent += 1
	getgenv().SB2NotifyWindowStart = windowStart
	getgenv().SB2NotifyCountWindow = recent
	if recent > 2 then
		return
	end
	getgenv().SB2LastNotify = { key = key, at = now }
	pcall(function()
		game:GetService('StarterGui'):SetCore('SendNotification', {
			Title = title,
			Text = text,
			Duration = 4,
		})
	end)
end
-- Quiet boot toasts while autoload / IY / resume settle.
if type(getgenv().SB2NotifyQuietUntil) ~= 'number' or getgenv().SB2NotifyQuietUntil < os.clock() then
	getgenv().SB2NotifyQuietUntil = os.clock() + 25
end

local unloadExisting = function()
	-- Retire any prior UI keeper loop before tearing down ScreenGui (otherwise
	-- orphaned-gui detection retriggers launch.lua in a tight loop).
	getgenv().SB2UiKeeperGen = (tonumber(getgenv().SB2UiKeeperGen) or 0) + 1
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
			if gui:IsA('ScreenGui') then
				if gui:GetAttribute('SB2PlayerTools') == true
					or gui:GetAttribute('SB2StarlightPlayerTools') == true
					or gui.Name == 'SB2PlayerTools'
				then
					pcall(function()
						gui:Destroy()
					end)
				end
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
	-- Soft-reload path: kill anim ghosts again after GUI teardown (boot kill may race).
	pcall(function()
		if type(getgenv().SB2AnimSwapStop) == 'function' then
			getgenv().SB2AnimSwapStop()
		end
		if type(getgenv().SB2WeaponModCleanup) == 'function' then
			getgenv().SB2WeaponModCleanup()
		end
		local cam = workspace.CurrentCamera
		if cam then
			for _, name in ipairs({
				'_SB2AnimGhostWorld',
				'_SB2AnimGhostChar',
				'_SB2AnimGhostWeapons',
			}) do
				local orphan = cam:FindFirstChild(name)
				if orphan then
					orphan:Destroy()
				end
			end
		end
		getgenv()._SB2AnimGhost = nil
	end)
	pcall(function()
		-- Soft reload mid-air: do NOT clear Anchor — that drops you through the floor.
		if getgenv().SB2SoftReloadPreserveFlight == true then
			pcall(function()
				local lp = game:GetService('Players').LocalPlayer
				local folder = workspace:FindFirstChild('Characters')
				local live = (lp and folder and folder:FindFirstChild(lp.Name))
					or (lp and lp.Character)
				local hrp = live and (live:FindFirstChild('HumanoidRootPart') or live.PrimaryPart)
				local pin = getgenv().SB2SoftReloadPinCF
				if hrp and hrp:IsA('BasePart') then
					if typeof(pin) == 'CFrame' then
						hrp.CFrame = pin
					end
					hrp.Anchored = true
					hrp.AssemblyLinearVelocity = Vector3.zero
					hrp.AssemblyAngularVelocity = Vector3.zero
				end
			end)
			if getgenv().SB2SoftReloadHadAnchor == true then
				getgenv().SB2CombatAnchorOn = true
			end
		else
			getgenv().SB2AutoAttackOn = false
			getgenv().SB2CombatAnchorOn = false
		end
		local function dropConn(key)
			local c = getgenv()[key]
			if c then
				pcall(function()
					c:Disconnect()
				end)
			end
			getgenv()[key] = nil
		end
		for _, key in ipairs({
			'SB2AutoAttackConn',
			'SB2CombatAnchorConn',
			'SB2AutoSkillOnlyConn',
			'SB2CameraRecoveryConn',
			'SB2BossComboScanConn',
			'SB2BossComboAddConn',
			'SB2CombatJoinDisableConn',
			'SB2CombatSoloResumeConn',
			'SB2CombatAltSeedConn',
			'SB2NoStreamConn',
			'SB2SkillFxJanitorAddConn',
			'SB2SkillFxJanitorHbConn',
			'SB2FarmFpsConn',
			'SB2FarmFpsLightConn',
			'SB2WsDeleteLogConn',
			'SB2VoidProbeHbConn',
			'SB2DiveFarmConn',
			'SB2WeaponModConn',
			'SB2AnchorDescConn',
		}) do
			dropConn(key)
		end
		-- Soft-reloads used to leave orphan Heartbeats (genv pointer lost → 5x Obsidian HB).
		-- Kill every RunService hook from our scripts before the new load installs fresh ones.
		pcall(function()
			if type(getconnections) ~= 'function' then
				return
			end
			local RS = game:GetService('RunService')
			for pass = 1, 8 do
				local n = 0
				for _, sig in ipairs({ 'Heartbeat', 'RenderStepped', 'Stepped' }) do
					local ok, cons = pcall(getconnections, RS[sig])
					if ok and type(cons) == 'table' then
						for _, cn in ipairs(cons) do
							local src = ''
							pcall(function()
								src = debug.info(cn.Function, 's') or ''
							end)
							if string.find(src, 'PlayerTools_Obsidian', 1, true)
								or string.find(src, 'PlayerTools_Starlight', 1, true)
								or src == '[string "Starlight"]'
							then
								pcall(function()
									cn:Disconnect()
								end)
								n += 1
							end
						end
					end
				end
				if n == 0 then
					break
				end
			end
		end)
		pcall(function()
			local RS = game:GetService('RunService')
			RS:UnbindFromRenderStep('SB2CamLock')
			RS:UnbindFromRenderStep('SB2CamLockLast')
		end)
		getgenv().SB2LogVoidProbe = nil
		getgenv().SB2LastVoidProbe = nil
		local camLock = getgenv().SB2CameraLockConn
		if camLock then
			pcall(function()
				if type(camLock) == 'table' and type(camLock.Disconnect) == 'function' then
					camLock:Disconnect()
				elseif type(camLock.Disconnect) == 'function' then
					camLock:Disconnect()
				end
			end)
			getgenv().SB2CameraLockConn = nil
		end
	end)
	pcall(function()
		if type(getgenv().SB2StopCombatRuntime) == 'function' then
			-- #region agent log
			if type(getgenv().SB2DbgFling) == 'function' then
				getgenv().SB2DbgFling(
					'B,C',
					'teardown:stopCombat',
					'about to StopCombatRuntime',
					{
						preserve = getgenv().SB2SoftReloadPreserveFlight == true,
						willUnanchor = getgenv().SB2SoftReloadPreserveFlight ~= true,
					}
				)
			end
			-- #endregion
			if getgenv().SB2SoftReloadPreserveFlight == true then
				-- false = stop loops but keep HRP anchored (no void drop).
				pcall(getgenv().SB2StopCombatRuntime, false)
				if getgenv().SB2SoftReloadHadAnchor == true then
					getgenv().SB2CombatAnchorOn = true
				end
			else
				getgenv().SB2StopCombatRuntime()
			end
			-- #region agent log
			if type(getgenv().SB2DbgFling) == 'function' then
				local snap = {}
				pcall(function()
					local lp = game:GetService('Players').LocalPlayer
					local folder = workspace:FindFirstChild('Characters')
					local live = (lp and folder and folder:FindFirstChild(lp.Name)) or (lp and lp.Character)
					local hrp = live and live:FindFirstChild('HumanoidRootPart')
					local hum = live and live:FindFirstChildOfClass('Humanoid')
					snap.y = hrp and math.floor(hrp.Position.Y + 0.5)
					snap.anchored = hrp and hrp.Anchored
					snap.vel = hrp and math.floor(hrp.AssemblyLinearVelocity.Magnitude + 0.5)
					snap.state = hum and hum:GetState().Name
					snap.anchorOn = getgenv().SB2CombatAnchorOn == true
				end)
				getgenv().SB2DbgFling('B,C,E', 'teardown:afterStopCombat', 'after StopCombatRuntime', snap)
			end
			-- #endregion
		end
	end)
	pcall(function()
		getgenv().SB2DiveFarmOn = false
		local farmThread = getgenv().SB2DiveFarmThread
		if farmThread then
			pcall(function()
				task.cancel(farmThread)
			end)
		end
		getgenv().SB2DiveFarmThread = nil
		local diveConn = getgenv().SB2DiveFarmConn
		if diveConn then
			diveConn:Disconnect()
		end
		getgenv().SB2DiveFarmConn = nil
		local vel = getgenv().SB2DiveLinVel
		if vel then
			vel.Parent = nil
			vel:Destroy()
		end
		getgenv().SB2DiveLinVel = nil
		local ang = getgenv().SB2DiveAngLock
		if ang then
			ang.Parent = nil
			ang:Destroy()
		end
		getgenv().SB2DiveAngLock = nil
		local align = getgenv().SB2DiveAlign
		if align then
			align.Parent = nil
			align:Destroy()
		end
		getgenv().SB2DiveAlign = nil
		-- Tear down dive noclip hooks left from prior inject (locals are gone).
		for _, key in ipairs({ 'SB2DiveNoclipStepped', 'SB2DiveNoclipHeartbeat' }) do
			local conn = getgenv()[key]
			if conn then
				pcall(function()
					conn:Disconnect()
				end)
				getgenv()[key] = nil
			end
		end
		getgenv().SB2DiveNoclipOn = false
		getgenv().SB2DiveFlyOn = false
		if type(getgenv().SB2DiveForceClip) == 'function' then
			pcall(getgenv().SB2DiveForceClip)
		elseif type(getgenv().SB2DiveSetNoclip) == 'function' then
			pcall(getgenv().SB2DiveSetNoclip, false)
		else
			-- Fallback clip if prior session left character intangible.
			pcall(function()
				local char = LocalPlayer.Character
					or (workspace:FindFirstChild('Characters') and workspace.Characters:FindFirstChild(LocalPlayer.Name))
				if not char then
					return
				end
				for _, p in ipairs(char:GetDescendants()) do
					if p:IsA('BasePart') then
						if p.CollisionGroup == 'SB2DiveNoclip' then
							p.CollisionGroup = 'Players'
						end
						if p.Name == 'HumanoidRootPart'
							or p.Name == 'UpperTorso'
							or p.Name == 'LowerTorso'
							or p.Name == 'Torso'
							or p.Name == 'Head'
						then
							p.CanCollide = true
						end
						p.CanTouch = true
					end
				end
				local hum = char:FindFirstChildOfClass('Humanoid')
				if hum then
					hum.PlatformStand = false
					hum.AutoRotate = true
				end
			end)
		end
	end)

	getgenv()[LIBRARY_KEY] = nil
	-- Fresh server finder is owned by AutoBlock.iy — never stop it on ordinary
	-- PlayerTools re-exec / soft reload / hop. Only stop on intentional Unload.
	local fsf = getgenv().SB2FreshServerFinder
	local freshFinderLive = type(fsf) == 'table' and fsf.active == true
	local softReload = getgenv().SB2SoftPlayerToolsReload == true
	local manualUnload = getgenv().SB2PlayerToolsManualUnload == true
	getgenv().SB2SoftPlayerToolsReload = nil
	if manualUnload and not freshFinderLive and not softReload then
		if type(getgenv().SB2StopFreshServerFinder) == 'function' then
			pcall(getgenv().SB2StopFreshServerFinder, 'PlayerTools unloaded')
		elseif type(getgenv().SB2WriteFreshServerFinder) == 'function' then
			pcall(getgenv().SB2WriteFreshServerFinder, { active = false, placeId = game.PlaceId, tried = {}, hops = 0 })
		end
	end
	if not freshFinderLive then
		getgenv().SB2FreshServerFinderTick = nil
	end
	if type(getgenv().SB2ScrubAllLeakedHooks) == 'function' then
		pcall(getgenv().SB2ScrubAllLeakedHooks)
	elseif type(getgenv().SB2TeardownStarlightLeaks) == 'function' then
		pcall(getgenv().SB2TeardownStarlightLeaks)
	end
end

-- Re-execute from Potassium must always proceed; a stuck prior load used to
-- leave this true and make later injects silently no-op.
getgenv().SB2PlayerToolsLoading = true
getgenv().SB2PlayerToolsLoadingSince = os.clock()
getgenv().SB2CombatBootGraceUntil = os.clock() + 15

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
	getgenv()[CONFIG.GenvKey] = true
else
	getgenv()[CONFIG.GenvKey] = true
	pcall(unloadExisting)
end

local ok, err = pcall(function()
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end

	if game.GameId ~= 212154879 then
		getgenv()[CONFIG.GenvKey] = false
		notify('Player Tools', 'Wrong game — need Swordburst 2')
		return
	end

	-- Launch allowlist = ReplicatedStorage.Database.Locations (dynamic: events/future floors
	-- included automatically). Login hub is not a Locations playable place.
	local LOGIN_PLACE_ID = 659222129
	local function refreshLocationsPlaceIds()
		local ids = getgenv().SB2LocationsPlaceIds
		if type(ids) == 'table' and next(ids) ~= nil then
			return ids
		end
		if type(getgenv().SB2EnsureServerHopCatalog) == 'function' then
			pcall(getgenv().SB2EnsureServerHopCatalog)
			ids = getgenv().SB2LocationsPlaceIds
			if type(ids) == 'table' and next(ids) ~= nil then
				return ids
			end
		end
		ids = {}
		local okReq, mod = pcall(function()
			local db = game:GetService('ReplicatedStorage'):FindFirstChild('Database')
			local loc = db and db:FindFirstChild('Locations')
			if not loc or not loc:IsA('ModuleScript') then
				return nil
			end
			local req = (getrenv and getrenv().require) or require
			return req(loc)
		end)
		if okReq and type(mod) == 'table' then
			local floors = mod.floors or mod.Floors or mod
			if type(floors) == 'table' then
				for _, entry in pairs(floors) do
					if type(entry) == 'table' then
						local pid = tonumber(entry.PlaceId or entry.placeId or entry.PlaceID)
						if pid then
							ids[pid] = true
						end
					end
				end
			end
		end
		getgenv().SB2LocationsPlaceIds = ids
		return ids
	end

	local locationIds = refreshLocationsPlaceIds()
	local onListedPlace = type(locationIds) == 'table' and locationIds[game.PlaceId] == true
	if game.PlaceId == LOGIN_PLACE_ID and not onListedPlace then
		pcall(function()
			game:GetService('ReplicatedStorage'):WaitForChild('Function'):InvokeServer('Login')
		end)
		getgenv()[CONFIG.GenvKey] = false
		notify('Player Tools', 'On main menu — join a floor first')
		return
	end
	-- Any Database.Locations id (Arcadia, story, events like Undershroud, rotating, …) is allowed.
	-- If Locations hasn't loaded yet, still allow non-login SB2 places so event floors aren't blocked.
	if next(locationIds) ~= nil and not onListedPlace and game.PlaceId ~= LOGIN_PLACE_ID then
		-- Rare: brand-new place before Locations module updates — still allow under SB2 GameId.
		warn('[PlayerTools] PlaceId ' .. tostring(game.PlaceId) .. ' not in Database.Locations yet — launching anyway (SB2)')
	end

	local WORKSPACE_SCRIPT = 'PlayerTools/PlayerTools_Obsidian.lua'
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
		if type(src) == 'string' and src ~= '' and src:find('SB2_PLAYERTOOLS_EOF', 1, true) then
			getgenv().SB2PlayerToolsCode = src
			-- Never mirror-overwrite disk from a stale in-memory/other-path body.
			-- That previously clobbered fixed Obsidian.lua and left fling ghosts.
			if type(writefile) == 'function'
				and src:find('SB2DbgFling', 1, true)
				and src:find('_SB2AnimGhostWorld', 1, true)
			then
				if type(makefolder) == 'function' and type(isfolder) == 'function' then
					if not isfolder('PlayerTools') then
						pcall(makefolder, 'PlayerTools')
					end
				end
				pcall(writefile, WORKSPACE_SCRIPT, src)
				-- PlayerTools.lua is the entry shim; never mirror over it.
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

	-- Hide Roblox "Gameplay paused" streaming overlay (keeps UI clean while diving/hopping).
	do
		local GuiService = game:GetService('GuiService')
		local function setGameplayPausedUi(enabled)
			pcall(function()
				GuiService:SetGameplayPausedNotificationEnabled(enabled == true)
			end)
		end
		local function hideGameplayPausedUi()
			setGameplayPausedUi(false)
		end
		getgenv().SB2SetGameplayPausedUi = setGameplayPausedUi
		getgenv().SB2HideGameplayPausedUi = hideGameplayPausedUi
		if getgenv().SB2HideGameplayPaused ~= false then
			hideGameplayPausedUi()
			if not getgenv().SB2GameplayPausedUiWatch then
				getgenv().SB2GameplayPausedUiWatch = true
				task.spawn(function()
					while getgenv()[CONFIG.GenvKey] and getgenv().SB2GameplayPausedUiWatch do
						if getgenv().SB2HideGameplayPaused ~= false then
							hideGameplayPausedUi()
						end
						task.wait(15)
					end
					getgenv().SB2GameplayPausedUiWatch = nil
				end)
			end
		end
	end

	local function safeConnect(signal, handler)
		if typeof(signal) ~= 'RBXScriptSignal' then
			return nil
		end
		local okConn, conn = pcall(function()
			return signal:Connect(handler)
		end)
		if okConn then
			return conn
		end
		warn('[PlayerTools] Connect failed: ' .. tostring(conn))
		return nil
	end

	local queueTeleport = (type(queueteleport) == 'function' and queueteleport)
		or (type(queue_on_teleport) == 'function' and queue_on_teleport)
		or (type(queueonteleport) == 'function' and queueonteleport)
		or (getgenv() and type(getgenv().queueteleport) == 'function' and getgenv().queueteleport)

	-- Soft-first: reparent + refresh across floor hops. Full rebuild only after
	-- retries, and never while another stub/load is already rebuilding (avoids
	-- load→unload flash from stacked KeepPlayerTools + armTeleport stubs).
	local TELEPORT_STUB =
		"if isfile and isfile('PlayerTools/manual_unload') then local ok,b=pcall(readfile,'PlayerTools/manual_unload'); if ok and tostring(b)=='true' then return end end;"
		.. "if getgenv().SB2PlayerToolsManualUnload then return end;"
		.. "getgenv().SB2MenuHopGraceUntil=os.clock()+25;"
		.. "getgenv().SB2UiKeeperQuietUntil=os.clock()+25;"
		.. "getgenv().SB2MenuWantOpen=true;"
		.. "local function soft()"
		.. "local gui=getgenv().SB2PlayerToolsGui;"
		.. "if typeof(gui)~='Instance' then return false end;"
		.. "if not gui.Parent then pcall(function()"
		.. "local h=nil; if gethui then local ok,x=pcall(gethui); if ok then h=x end end;"
		.. "local cg=game:FindService('CoreGui') or game:GetService('CoreGui');"
		.. "gui.Parent=h or (cg and cg:FindFirstChild('RobloxGui')) or cg;"
		.. "if not gui.Parent then local lp=game:GetService('Players').LocalPlayer; local pg=lp and lp:FindFirstChildOfClass('PlayerGui'); if pg then gui.Parent=pg end end;"
		.. "if gui.Parent then gui.Enabled=true; if gui.DisplayOrder<500 then gui.DisplayOrder=998 end end;"
		.. "end) end;"
		.. "if not gui.Parent then return false end;"
		.. "getgenv().SB2PlayerTools=true; getgenv().SB2PlayerToolsGui=gui; getgenv().SB2UiOrphanFails=0;"
		.. "if type(getgenv().SB2RefreshPlayerTools)=='function' then pcall(getgenv().SB2RefreshPlayerTools) end;"
		.. "return true; end;"
		.. "if soft() then return end;"
		.. "if getgenv().SB2PlayerToolsLoading==true then "
		.. "for _=1,50 do task.wait(0.4); if getgenv().SB2PlayerToolsManualUnload then return end; if soft() then return end; if getgenv().SB2PlayerToolsLoading~=true then break end end;"
		.. "if soft() then return end; end;"
		.. "for _=1,10 do task.wait(0.4); if soft() then return end end;"
		.. "if getgenv().SB2PlayerToolsLoading==true then return end;"
		.. "getgenv().SB2SoftPlayerToolsReload=true;"
		.. "getgenv().SB2PlayerToolsLoading=true;"
		.. "getgenv().SB2PlayerToolsLoadingSince=os.clock();"
		.. "getgenv().SB2PlayerTools=false;"
		.. "getgenv().SB2PlayerToolsInstance=nil;"
		.. "getgenv().SB2PlayerToolsLibrary=nil;"
		.. "local ok,err=pcall(function()"
		.. "local p=(isfile and isfile('PlayerTools/launch.lua') and 'PlayerTools/launch.lua')"
		.. "or(isfile and isfile('PlayerTools/PlayerTools.lua') and 'PlayerTools/PlayerTools.lua')"
		.. "or(isfile and isfile('PlayerTools.lua') and 'PlayerTools.lua');"
		.. "assert(p,'PlayerTools.lua missing from workspace');"
		.. "local compile=loadstring or load;"
		.. "local src=readfile(p);"
		.. "local fn,cerr=compile(src,p);"
		.. "if not fn then error('PlayerTools compile: '..tostring(cerr)) end;"
		.. "fn()"
		.. "end);if not ok then getgenv().SB2PlayerToolsLoading=false; getgenv().SB2SoftPlayerToolsReload=nil; warn('[PlayerTools] rejoin failed: '..tostring(err)) end"

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
		getgenv().SB2AntiAfkConn = safeConnect(LocalPlayer.Idled, onRobloxIdled)
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

	-- Session loader (PlayerGui.Gui) can hang. Stuck-load rejoin is owned by
	-- Infinite Yield plugin StuckLoadRejoin.iy (same checks, 15s default).
	-- PlayerTools only syncs the toggle / sidecar + forwards manual rejoin.
	local LoadSkip = (function()
		local PATH = joinPath(CONFIG.ConfigFolder, 'autoskip_load')

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

		local function syncIy(on, silent)
			on = on == true
			writeFile(on)
			getgenv().SB2AutoSkipLoad = on
			if type(getgenv().SB2SetStuckLoadRejoin) == 'function' then
				pcall(getgenv().SB2SetStuckLoadRejoin, on, silent == true, { persist = true })
			elseif on and not silent then
				notify('Player Tools', 'Install IY plugin StuckLoadRejoin.iy — stuck-load rejoin moved there')
			end
			return on
		end

		local function overlayUp()
			if type(getgenv().SB2LoadOverlayUp) == 'function' then
				local ok, up = pcall(getgenv().SB2LoadOverlayUp)
				if ok then
					return up == true
				end
			end
			return false
		end

		local function rejoin(reason)
			local fn = getgenv().SB2ForceFinishLoad or getgenv().SB2StuckLoadRejoin
			if type(fn) == 'function' then
				return fn(reason) == true
			end
			notify('Player Tools', 'Install IY plugin StuckLoadRejoin.iy first')
			return false
		end

		getgenv().SB2AutoSkipLoad = fileOn()
		-- Do not start a PlayerTools watcher — StuckLoadRejoin.iy owns it.
		if getgenv().SB2StuckLoadIyOwner ~= true and fileOn() then
			task.defer(function()
				if getgenv().SB2StuckLoadIyOwner ~= true then
					notify('Player Tools', 'Stuck-load rejoin needs IY plugin StuckLoadRejoin.iy')
				end
			end)
		end

		return {
			rejoin = rejoin,
			overlayUp = overlayUp,
			fileOn = fileOn,
			writeFile = writeFile,
			sync = syncIy,
			stuckSecs = function()
				return tonumber(getgenv().SB2LoadStuckSecs) or 15
			end,
			ready = function()
				return getgenv().SB2StuckLoadIyOwner == true
			end,
		}
	end)()
	getgenv().SB2ForceFinishLoad = getgenv().SB2ForceFinishLoad or LoadSkip.rejoin
	getgenv().SB2LoadOverlayUp = getgenv().SB2LoadOverlayUp or LoadSkip.overlayUp
	getgenv().SB2LoadStuckSecs = getgenv().SB2LoadStuckSecs or 15

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

	-- SB3 / title screens use Scriptable+cinematic cams. Forcing Custom or
	-- StreamingEnabled=false there paints a black void (3/4 clients in multi).
	local titleMenuCache, titleMenuCacheAt = false, 0
	local function titleMenuVisible()
		local now = os.clock()
		if (now - titleMenuCacheAt) < 0.75 then
			return titleMenuCache
		end
		titleMenuCacheAt = now
		titleMenuCache = false
		local pg = LocalPlayer:FindFirstChild('PlayerGui')
		if not pg then
			titleMenuCache = true
			return true
		end
		local cui = pg:FindFirstChild('CardinalUI')
		local hudOn = cui and cui:IsA('LayerCollector') and cui.Enabled == true
		if hudOn then
			return false
		end
		local scanned = 0
		for _, d in ipairs(pg:GetDescendants()) do
			scanned += 1
			if scanned > 1200 then
				break
			end
			if d:IsA('TextLabel') or d:IsA('TextButton') then
				local raw = string.upper((d.Text or ''):gsub('%s+', ''))
				if raw == 'PLAY' or raw == 'EXTRAS' then
					if d.Visible and d.AbsoluteSize.X > 24 and d.AbsoluteSize.Y > 12 then
						titleMenuCache = true
						return true
					end
				end
			end
		end
		return false
	end

	local function inGameplayWorld()
		if LoadSkip and LoadSkip.overlayUp and LoadSkip.overlayUp() then
			return false
		end
		if titleMenuVisible() then
			return false
		end
		local model = LocalPlayer.Character
		if not model or not model.Parent then
			return false
		end
		local hrp = model:FindFirstChild('HumanoidRootPart')
		local hum = model:FindFirstChildOfClass('Humanoid')
		if not hrp or not hum or hum.Health <= 0 then
			return false
		end
		local cam = workspace.CurrentCamera
		if cam and (cam.CameraType == Enum.CameraType.Scriptable or cam.CameraType == Enum.CameraType.Fixed) then
			if cam.CameraSubject ~= hum then
				return false
			end
		end
		return true
	end
	getgenv().SB2InGameplayWorld = inGameplayWorld

	-- Kill client streaming so the map stops unreplicating (void Workspace).
	-- Needs executor setscriptable / sethiddenproperty; re-applies if it flips back on.
	-- NEVER on title / pre-PLAY — that blacks the whole client.
	local function disableWorkspaceStreaming()
		if not inGameplayWorld() then
			return false
		end
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
	task.defer(function()
		if inGameplayWorld() then
			disableWorkspaceStreaming()
		end
	end)
	-- One-shot + event: if the game re-enables streaming, flip it off again (no Heartbeat poll).
	do
		if getgenv().SB2NoStreamConn then
			pcall(function()
				getgenv().SB2NoStreamConn:Disconnect()
			end)
			getgenv().SB2NoStreamConn = nil
		end
		getgenv().SB2NoStreamConn = workspace:GetPropertyChangedSignal('StreamingEnabled'):Connect(function()
			if not getgenv()[CONFIG.GenvKey] then
				return
			end
			if inGameplayWorld() and workspace.StreamingEnabled then
				disableWorkspaceStreaming()
			end
		end)
	end

	-- Sweeping Strike / Water Blast / Infinity Slash clone BodyVelocity parts into
	-- Workspace and never destroy them (7k+ per farm client). TTL then batch-delete.
	-- Vampiric bats also block other casts until cleared.
	;(function()
		local RunService = game:GetService('RunService')
		local ATTR = 'SB2FxJ'
		local pending = {}
		local queued = {}
		local lastSweep = 0
		local FX_NAME = {
			SweepingStrike = true,
			Bat = true,
			ActiveBats = true,
			Trail = true,
			SoulLightning = true,
			Meteor = true,
			Soul = true,
			Whirlpool = true,
			Lava = true,
			Indicator = true,
			Lines = true,
			['Trail/Slash'] = true,
			Circle = true,
			EffectHitbox = true,
			Skill = true,
			SummonPortal = true,
			TreeEffect = true,
		}
		local PROTECT_NAME = {
			Characters = true,
			Mobs = true,
			Terrain = true,
			Camera = true,
			CurrentCamera = true,
		}

		local function dropConn(key)
			local c = getgenv()[key]
			if c then
				pcall(function()
					c:Disconnect()
				end)
			end
			getgenv()[key] = nil
		end

		local function hasBodyMover(inst)
			return inst:FindFirstChildWhichIsA('BodyVelocity') ~= nil
				or inst:FindFirstChildWhichIsA('LinearVelocity') ~= nil
				or inst:FindFirstChildWhichIsA('VectorForce') ~= nil
		end

		local function isSkillFxDebris(inst)
			if not inst or inst.Parent ~= workspace then
				return false
			end
			local name = inst.Name
			if PROTECT_NAME[name] then
				return false
			end
			-- Summoned undead / map mobs — never janitor these.
			if name ~= 'Bat' then
				local hum = inst:FindFirstChildWhichIsA('Humanoid')
					or inst:FindFirstChildWhichIsA('Humanoid', true)
				if hum then
					return false
				end
			end
			if FX_NAME[name] then
				return true
			end
			local cls = inst.ClassName
			if cls == 'Sound' or cls == 'Attachment' then
				return true
			end
			if cls ~= 'Part' and cls ~= 'MeshPart' then
				return false
			end
			return hasBodyMover(inst)
		end

		local function debrisTtl(inst)
			local name = inst and inst.Name or ''
			if name == 'Bat' or name == 'ActiveBats' or name == 'Trail' then
				return 10
			end
			if name == 'Meteor' or name == 'Whirlpool' or name == 'Lava' then
				return 6
			end
			if name == 'SweepingStrike' or hasBodyMover(inst) then
				return 1.35
			end
			return 2.4
		end

		local function neutralize(inst)
			pcall(function()
				if inst:IsA('BasePart') then
					inst.CanCollide = false
					inst.CastShadow = false
					inst.CanQuery = false
					inst.CanTouch = false
				end
				local desc = inst:GetDescendants()
				for i = 1, #desc do
					local d = desc[i]
					local dCls = d.ClassName
					if dCls == 'ParticleEmitter' or dCls == 'Trail' or dCls == 'Beam'
						or dCls == 'Fire' or dCls == 'Smoke' or dCls == 'Sparkles'
					then
						d.Enabled = false
					elseif dCls == 'PointLight' or dCls == 'SpotLight' or dCls == 'SurfaceLight' then
						d.Enabled = false
					elseif d:IsA('BasePart') then
						d.CanCollide = false
						d.CastShadow = false
					end
				end
			end)
		end

		local function killMoversAndAnchor(inst)
			pcall(function()
				if inst:IsA('BasePart') then
					inst.Anchored = true
					inst.AssemblyLinearVelocity = Vector3.zero
				end
				local desc = inst:GetDescendants()
				for i = 1, #desc do
					local d = desc[i]
					local dCls = d.ClassName
					if dCls == 'BodyVelocity' or dCls == 'BodyGyro' or dCls == 'BodyThrust'
						or dCls == 'LinearVelocity' or dCls == 'VectorForce'
					then
						d:Destroy()
					elseif d:IsA('BasePart') then
						d.Anchored = true
					end
				end
			end)
		end

		local function stamp(inst)
			pcall(function()
				if inst:GetAttribute(ATTR) == nil then
					inst:SetAttribute(ATTR, os.clock())
				end
			end)
		end

		local function age(inst)
			local t = nil
			pcall(function()
				t = inst:GetAttribute(ATTR)
			end)
			t = tonumber(t)
			if not t then
				return 99
			end
			return os.clock() - t
		end

		local function enqueue(inst)
			if queued[inst] or not isSkillFxDebris(inst) then
				return
			end
			stamp(inst)
			neutralize(inst)
			queued[inst] = true
			pending[#pending + 1] = inst
		end

		local function flushBatch()
			if #pending == 0 then
				return
			end
			local overload = #pending > 400
			local batch = overload and 280 or 160
			local n = 0
			local keep = {}
			for i = 1, #pending do
				local inst = pending[i]
				if not inst or inst.Parent ~= workspace or not isSkillFxDebris(inst) then
					queued[inst] = nil
				else
					local a = age(inst)
					if a >= math.max(0.45, debrisTtl(inst) - 0.35) then
						killMoversAndAnchor(inst)
					end
					local ttl = overload and math.min(debrisTtl(inst), 0.8) or debrisTtl(inst)
					if a >= ttl then
						if n < batch then
							queued[inst] = nil
							pcall(function()
								inst:Destroy()
							end)
							n += 1
						else
							keep[#keep + 1] = inst
						end
					else
						keep[#keep + 1] = inst
					end
				end
			end
			pending = keep
		end

		local function scanWorkspace()
			local kids = workspace:GetChildren()
			for i = 1, #kids do
				enqueue(kids[i])
			end
		end

		dropConn('SB2SkillFxJanitorAddConn')
		dropConn('SB2SkillFxJanitorHbConn')
		scanWorkspace()
		getgenv().SB2SkillFxJanitorAddConn = workspace.ChildAdded:Connect(function(ch)
			if not getgenv()[CONFIG.GenvKey] then
				return
			end
			task.defer(function()
				enqueue(ch)
			end)
		end)
			getgenv().SB2SkillFxJanitorHbConn = RunService.Heartbeat:Connect(function()
				if not getgenv()[CONFIG.GenvKey] then
					return
				end
				local now = os.clock()
				-- Flush at most ~4Hz; full workspace scan every 8s (was every Heartbeat + 4s scan).
				if now - (getgenv().SB2SkillFxFlushAt or 0) >= 0.25 then
					getgenv().SB2SkillFxFlushAt = now
					flushBatch()
				end
				if now - lastSweep >= 8 then
					lastSweep = now
					scanWorkspace()
				end
			end)
		getgenv().SB2SweepSkillFx = function()
			scanWorkspace()
			for i = 1, #pending do
				local inst = pending[i]
				pcall(function()
					if inst then
						inst:SetAttribute(ATTR, 0)
					end
				end)
			end
			flushBatch()
		end
	end)()

	-- Potato render: quality 1, no global shadows, mute lighting post-fx.
	-- Does not Destroy skill clones (janitor owns those) and does not strip GUIs.
	;(function()
		local Lighting = game:GetService('Lighting')
		local RunService = game:GetService('RunService')
		local lastPin = 0

		local function dropConn(key)
			local c = getgenv()[key]
			if c then
				pcall(function()
					c:Disconnect()
				end)
			end
			getgenv()[key] = nil
		end

		local function pinQuality()
			-- Only touch settings when drifted — rewriting QualityLevel every N seconds
			-- forces a render hitch (felt like a stutter every ~5–10s on the main).
			pcall(function()
				local rend = settings().Rendering
				if rend.QualityLevel ~= Enum.QualityLevel.Level01 and rend.QualityLevel ~= 1 then
					rend.QualityLevel = 1
				end
			end)
			pcall(function()
				local gs = UserSettings():GetService('UserGameSettings')
				if gs.SavedQualityLevel ~= Enum.SavedQualityLevel.QualityLevel1 then
					gs.SavedQualityLevel = Enum.SavedQualityLevel.QualityLevel1
				end
			end)
			pcall(function()
				if Lighting.GlobalShadows ~= false then
					Lighting.GlobalShadows = false
				end
				if Lighting.FogEnd ~= 400 then
					Lighting.FogEnd = 400
					Lighting.FogStart = 0
				end
			end)
			pcall(function()
				local kids = Lighting:GetChildren()
				for i = 1, #kids do
					local ch = kids[i]
					if ch:IsA('BlurEffect') or ch:IsA('BloomEffect') or ch:IsA('SunRaysEffect')
						or ch:IsA('DepthOfFieldEffect')
					then
						if ch.Enabled then
							ch.Enabled = false
						end
					end
				end
			end)
		end

		local function startFarmFps()
			getgenv().SB2FarmFpsOn = true
			pinQuality()
			dropConn('SB2FarmFpsConn')
			dropConn('SB2FarmFpsLightConn')
			getgenv().SB2FarmFpsLightConn = Lighting.ChildAdded:Connect(function(ch)
				if getgenv().SB2FarmFpsOn ~= true then
					return
				end
				task.defer(function()
					if ch:IsA('BlurEffect') or ch:IsA('BloomEffect') or ch:IsA('SunRaysEffect')
						or ch:IsA('DepthOfFieldEffect')
					then
						pcall(function()
							ch.Enabled = false
						end)
					end
				end)
			end)
			getgenv().SB2FarmFpsConn = RunService.Heartbeat:Connect(function()
				if getgenv().SB2FarmFpsOn ~= true or not getgenv()[CONFIG.GenvKey] then
					return
				end
				local now = os.clock()
				if now - lastPin < 30 then
					return
				end
				lastPin = now
				pinQuality()
			end)
		end

		local function stopFarmFps()
			getgenv().SB2FarmFpsOn = false
			dropConn('SB2FarmFpsConn')
			dropConn('SB2FarmFpsLightConn')
		end

		getgenv().SB2StartFarmFps = startFarmFps
		getgenv().SB2StopFarmFps = stopFarmFps
		if getgenv().SB2FarmFpsOn ~= false then
			startFarmFps()
		end
	end)()

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
	local ANCHOR_COLGROUP_ATTR = 'SB2PrevColGroup'
	-- SB2 already has HelperMob: collides with Default (floor), NOT Players/Mobs/MobHitbox.
	-- Client cannot edit the collision matrix (server-only), but CAN assign parts to this group.
	local ANCHOR_GHOST_GROUP = 'HelperMob'
	local function ghostPartForAnchor(part, enabled)
		if not part or not part:IsA('BasePart') then
			return
		end
		if enabled then
			if part:GetAttribute(ANCHOR_COLGROUP_ATTR) == nil then
				part:SetAttribute(ANCHOR_COLGROUP_ATTR, part.CollisionGroup)
			end
			if part.CollisionGroup ~= ANCHOR_GHOST_GROUP then
				pcall(function()
					part.CollisionGroup = ANCHOR_GHOST_GROUP
				end)
			end
			-- Keep CanCollide so floor (Default) still works via HelperMob matrix.
			if part:GetAttribute(ANCHOR_NOCLIP_ATTR) == nil then
				part:SetAttribute(ANCHOR_NOCLIP_ATTR, part.CanCollide == true)
			end
			if not part.CanCollide then
				part.CanCollide = true
			end
		else
			local prevG = part:GetAttribute(ANCHOR_COLGROUP_ATTR)
			if prevG ~= nil then
				pcall(function()
					part.CollisionGroup = tostring(prevG)
				end)
				part:SetAttribute(ANCHOR_COLGROUP_ATTR, nil)
			elseif part.CollisionGroup == ANCHOR_GHOST_GROUP
				or part.CollisionGroup == 'NoCollision'
				or part.CollisionGroup == 'MobsNoCollision'
			then
				pcall(function()
					part.CollisionGroup = 'Players'
				end)
			end
			local was = part:GetAttribute(ANCHOR_NOCLIP_ATTR)
			if was ~= nil then
				part.CanCollide = was == true
				part:SetAttribute(ANCHOR_NOCLIP_ATTR, nil)
			end
		end
	end
	local function setAnchorPlayerNoclip(enabled)
		-- Body only → HelperMob (walk-through players/mobs, floor OK).
		-- NEVER touch CharacterItems / weapon Handles — putting them on HelperMob
		-- (or mixing HelperMob grip + Default blade) shoves the sword sideways.
		local model = getMyCharacterModel() or LocalPlayer.Character
		if model then
			for _, part in ipairs(model:GetDescendants()) do
				if part:IsA('BasePart') then
					-- Grip anchors are tiny weld hosts — keep them non-colliding so they
					-- cannot push the Default-group Handle when the body is HelperMob.
					if part.Name == 'RightGrip' or part.Name == 'LeftGrip' then
						if enabled then
							if part:GetAttribute(ANCHOR_NOCLIP_ATTR) == nil then
								part:SetAttribute(ANCHOR_NOCLIP_ATTR, part.CanCollide == true)
							end
							part.CanCollide = false
						else
							local was = part:GetAttribute(ANCHOR_NOCLIP_ATTR)
							if was ~= nil then
								part.CanCollide = was == true
								part:SetAttribute(ANCHOR_NOCLIP_ATTR, nil)
							end
						end
					else
						ghostPartForAnchor(part, enabled)
					end
				end
			end
		end
		-- If a prior build left weapons on HelperMob, restore them to Default/prev.
		pcall(function()
			local items = workspace:FindFirstChild('CharacterItems')
			local mine = items and items:FindFirstChild(tostring(LocalPlayer.UserId))
			if not mine then
				return
			end
			for _, part in ipairs(mine:GetDescendants()) do
				if part:IsA('BasePart') then
					local prevG = part:GetAttribute(ANCHOR_COLGROUP_ATTR)
					if prevG ~= nil then
						pcall(function()
							part.CollisionGroup = tostring(prevG)
						end)
						part:SetAttribute(ANCHOR_COLGROUP_ATTR, nil)
					elseif part.CollisionGroup == ANCHOR_GHOST_GROUP then
						pcall(function()
							part.CollisionGroup = 'Default'
						end)
					end
					part:SetAttribute(ANCHOR_NOCLIP_ATTR, nil)
				end
			end
		end)
		getgenv().SB2AnchorNoclipOn = enabled == true
		-- #region agent log
		if type(getgenv().SB2DbgFling) == 'function' then
			pcall(getgenv().SB2DbgFling, 'I', 'setAnchorPlayerNoclip', 'anchor_body_only_ghost', {
				enabled = enabled == true,
				group = ANCHOR_GHOST_GROUP,
			})
		end
		-- #endregion
	end
	getgenv().SB2SetAnchorPlayerNoclip = setAnchorPlayerNoclip
	getgenv().SB2GhostPartForAnchor = ghostPartForAnchor

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
		if getgenv().SB2DiveFarmOn then
			return
		end
		if type(isToggleOn) == 'function' and isToggleOn('DiveFarm') then
			return
		end
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

	-- Soft Combat Anchor: NEVER hard-Anchored while farming.
	-- Hard Anchored + local PivotTo desyncs server position → 0 damage.
	-- Soft lock: Anchored=false so TPs replicate; zero velocity + snap-back
	-- kills mob pushes / CTF yeets without freezing replication.
	local ANCHOR_PUSH_SNAP = 2.5 -- studs off lock before snap-back (not every frame)
	local ANCHOR_REPLICATE_SEC = 0.65 -- unanchored settle after TP so server gets CFrame
	local ANCHOR_GHOST_REFRESH = 1.25 -- seconds between full HelperMob rescans

	local function anchorReplicating()
		return os.clock() < (tonumber(getgenv().SB2AnchorReplicateUntil) or 0)
	end

	local function setAnchorLockCF(cf)
		if typeof(cf) == 'CFrame' then
			getgenv().SB2AnchorLockCF = cf
		end
	end

	local function beginAnchorReplicate(seconds)
		seconds = tonumber(seconds) or ANCHOR_REPLICATE_SEC
		local untilT = os.clock() + math.max(0.2, seconds)
		local prev = tonumber(getgenv().SB2AnchorReplicateUntil) or 0
		if untilT > prev then
			getgenv().SB2AnchorReplicateUntil = untilT
		end
		-- Hold window must not force-unanchor over the replicate settle incorrectly;
		-- replicate itself keeps Anchored=false.
		getgenv().SB2AnchorHoldUntil = 0
	end

	local function maintainAnchorGhost(model, hrp, force)
		-- Cheap: only full-scan when HRP left HelperMob or refresh interval elapsed.
		if getgenv().SB2CombatAnchorOn ~= true and getgenv().SB2AnchorNoclipOn ~= true then
			return
		end
		local now = os.clock()
		local last = tonumber(getgenv().SB2AnchorGhostAt) or 0
		local groupOk = hrp and hrp.CollisionGroup == ANCHOR_GHOST_GROUP
		if not force and groupOk and (now - last) < ANCHOR_GHOST_REFRESH then
			return
		end
		getgenv().SB2AnchorGhostAt = now
		pcall(setAnchorPlayerNoclip, true)
	end

	local function softLockRoot(model, hrp, opts)
		opts = opts or {}
		if not hrp or not hrp:IsA('BasePart') then
			return
		end
		-- Lightweight: used by TP pin end / rare callers. No descendant scans.
		hrp.Anchored = false
		local vel = hrp.AssemblyLinearVelocity
		if vel.Magnitude > 1 then
			hrp.AssemblyLinearVelocity = Vector3.zero
			hrp.AssemblyAngularVelocity = Vector3.zero
		end
		local lock = getgenv().SB2AnchorLockCF
		if typeof(lock) ~= 'CFrame' then
			setAnchorLockCF(hrp.CFrame)
			return
		end
		local dist = (hrp.Position - lock.Position).Magnitude
		if anchorReplicating() or getgenv().SB2TpPinActive == true then
			if dist > 1.0 then
				if model and model.PivotTo then
					model:PivotTo(lock)
				else
					hrp.CFrame = lock
				end
			end
			return
		end
		if opts.skipSnap then
			return
		end
		if dist > ANCHOR_PUSH_SNAP then
			if model and model.PivotTo then
				model:PivotTo(lock)
			else
				hrp.CFrame = lock
			end
		end
	end

	-- Anchoring HRP before the server has our CFrame freezes us at spawn:
	-- mobs never stream, other clients never see us. Hold unanchored after spawn/TP.
	-- Soft pin (pinTeleportCFrame) keeps Anchored=false while holding destination.
	local function combatAnchorHolding()
		if getgenv().SB2TpPinActive == true then
			return false
		end
		if anchorReplicating() then
			return true -- treat as "don't hard-lock yet"
		end
		return os.clock() < (tonumber(getgenv().SB2AnchorHoldUntil) or 0)
	end
	local function holdCombatAnchor(seconds)
		-- During an active TP pin, never schedule an extra hold that fights the pin.
		if getgenv().SB2TpPinActive == true then
			return
		end
		seconds = tonumber(seconds) or 3.5
		if seconds < 0 then
			seconds = 0
		end
		local untilT = os.clock() + seconds
		local prev = tonumber(getgenv().SB2AnchorHoldUntil) or 0
		if untilT > prev then
			getgenv().SB2AnchorHoldUntil = untilT
		end
		beginAnchorReplicate(math.min(seconds, ANCHOR_REPLICATE_SEC + 0.15))
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
				setAnchorLockCF(hrp.CFrame)
				LocalPlayer:RequestStreamAroundAsync(hrp.Position, 40)
			end)
		end
	end
	-- Soft-pin HRP at cf: stay UNanchored so server learns the new CFrame, hold
	-- with PivotTo + zero velocity (anti-gravity / anti-push) for a short settle.
	local function pinTeleportCFrame(cf, seconds)
		seconds = tonumber(seconds) or 0.9
		if typeof(cf) ~= 'CFrame' then
			return
		end
		-- Never pin into the void (boss WP saved under the map → 0 damage AA).
		if cf.Position.Y < -20 then
			-- #region agent log
			if type(getgenv().SB2DbgFling) == 'function' then
				pcall(getgenv().SB2DbgFling, 'A', 'pinTeleportCFrame', 'pin_void_reject', {
					y = cf.Position.Y,
					x = cf.Position.X,
					z = cf.Position.Z,
				})
			end
			-- #endregion
			return
		end
		local model = getMyCharacterModel() or LocalPlayer.Character
		if not model then
			return
		end
		local hrp = model:FindFirstChild('HumanoidRootPart') or model:FindFirstChild('UpperTorso')
		if not hrp or not hrp:IsA('BasePart') then
			return
		end
		getgenv().SB2AnchorHoldUntil = 0
		getgenv().SB2TpPinActive = true
		getgenv().SB2TpPinCFrame = cf
		setAnchorLockCF(cf)
		beginAnchorReplicate(math.max(seconds, ANCHOR_REPLICATE_SEC))
		local gen = (tonumber(getgenv().SB2TpPinGen) or 0) + 1
		getgenv().SB2TpPinGen = gen
		local untilT = os.clock() + math.max(0.25, seconds)
		getgenv().SB2TpPinUntil = untilT
		pcall(function()
			hrp.Anchored = false
			hrp.AssemblyLinearVelocity = Vector3.zero
			hrp.AssemblyAngularVelocity = Vector3.zero
			-- PivotTo keeps CharacterItems Handle welded; bare hrp.CFrame desyncs the grip
			-- and DealDamage lands 0 (sword left at the old pad).
			if model.PivotTo then
				model:PivotTo(cf)
			else
				hrp.CFrame = cf
			end
			-- CRITICAL: do NOT Anchored=true here — that freezes client pose while the
			-- server still has the pre-TP position (desync → 0 damage).
		end)
		-- #region agent log
		if type(getgenv().SB2DbgFling) == 'function' then
			pcall(getgenv().SB2DbgFling, 'H', 'pinTeleportCFrame', 'soft_pin_start', {
				y = cf.Position.Y,
				sec = seconds,
				anchored = hrp.Anchored,
			})
		end
		-- #endregion
		lockReplicationFocus(model)
		pcall(function()
			LocalPlayer:RequestStreamAroundAsync(cf.Position, 48)
		end)
		task.spawn(function()
			while getgenv().SB2TpPinGen == gen and os.clock() < untilT do
				RunService.Heartbeat:Wait()
				local m = getMyCharacterModel() or LocalPlayer.Character
				local root = m and (m:FindFirstChild('HumanoidRootPart') or m:FindFirstChild('UpperTorso'))
				if not root or not root:IsA('BasePart') then
					continue
				end
				pcall(function()
					root.Anchored = false
					root.AssemblyLinearVelocity = Vector3.zero
					root.AssemblyAngularVelocity = Vector3.zero
					if (root.Position - cf.Position).Magnitude > 1.5 then
						if m.PivotTo then
							m:PivotTo(cf)
						else
							root.CFrame = cf
						end
					else
						-- Keep Y locked even if XZ drifted slightly from physics.
						local p = root.Position
						local locked = CFrame.new(p.X, cf.Position.Y, p.Z) * (cf - cf.Position)
						if m.PivotTo then
							m:PivotTo(locked)
						else
							root.CFrame = locked
						end
					end
				end)
			end
			if getgenv().SB2TpPinGen ~= gen then
				return
			end
			getgenv().SB2TpPinActive = false
			getgenv().SB2TpPinCFrame = nil
			-- Soft Combat Anchor: stay unanchored, lock CF for push snap-back.
			setAnchorLockCF(cf)
			beginAnchorReplicate(0.35)
			if getgenv().SB2CombatAnchorOn == true or isToggleOn('CombatAnchor') then
				pcall(function()
					local m = getMyCharacterModel() or LocalPlayer.Character
					local root = m and (m:FindFirstChild('HumanoidRootPart') or m:FindFirstChild('UpperTorso'))
					if root and root:IsA('BasePart') then
						softLockRoot(m, root, { skipSnap = true })
					end
				end)
			end
			-- #region agent log
			if type(getgenv().SB2DbgFling) == 'function' then
				pcall(getgenv().SB2DbgFling, 'H', 'pinTeleportCFrame', 'soft_pin_end', {
					y = cf.Position.Y,
				})
			end
			-- #endregion
		end)
	end
	getgenv().SB2HoldCombatAnchor = holdCombatAnchor
	getgenv().SB2CombatAnchorHolding = combatAnchorHolding
	getgenv().SB2PinTeleportCFrame = pinTeleportCFrame
	getgenv().SB2SoftLockRoot = softLockRoot
	getgenv().SB2BeginAnchorReplicate = beginAnchorReplicate
	getgenv().SB2SetAnchorLockCF = setAnchorLockCF
	task.defer(function()
		if not LocalPlayer.Character then
			return
		end
		-- Soft reload / boss air: never open the unanchor window (void drop).
		if getgenv().SB2SkipHoldAnchorOnBoot == true then
			-- #region agent log
			if type(getgenv().SB2DbgFling) == 'function' then
				getgenv().SB2DbgFling('B', 'boot:holdAnchor', 'SKIP holdCombatAnchor (soft preserve)', {
					skip = true,
					hadAnchor = getgenv().SB2SoftReloadHadAnchor == true,
				})
			end
			-- #endregion
			getgenv().SB2SkipHoldAnchorOnBoot = nil
			local pin = getgenv().SB2SoftReloadPinCF
			local model = getMyCharacterModel() or LocalPlayer.Character
			local hrp = model and (model:FindFirstChild('HumanoidRootPart') or model:FindFirstChild('UpperTorso'))
			if hrp and hrp:IsA('BasePart') then
				if typeof(pin) == 'CFrame' then
					if model.PivotTo then
						pcall(function()
							model:PivotTo(pin)
						end)
					else
						hrp.CFrame = pin
					end
					if type(getgenv().SB2SetAnchorLockCF) == 'function' then
						getgenv().SB2SetAnchorLockCF(pin)
					else
						getgenv().SB2AnchorLockCF = pin
					end
				end
				hrp.AssemblyLinearVelocity = Vector3.zero
				hrp.AssemblyAngularVelocity = Vector3.zero
				-- Soft anchor only — hard Anchored here caused TP desync after reload.
				hrp.Anchored = false
				if type(getgenv().SB2BeginAnchorReplicate) == 'function' then
					getgenv().SB2BeginAnchorReplicate(0.5)
				end
			end
			return
		end
		if getgenv().SB2BossRouteWanted == true or getgenv().SB2CombatAnchorOn == true then
			-- #region agent log
			if type(getgenv().SB2DbgFling) == 'function' then
				getgenv().SB2DbgFling('B', 'boot:holdAnchor', 'SKIP hold (boss/anchor on)', {
					boss = getgenv().SB2BossRouteWanted == true,
					anchorOn = getgenv().SB2CombatAnchorOn == true,
				})
			end
			-- #endregion
			return
		end
		local model = getMyCharacterModel() or LocalPlayer.Character
		local hrp = model and model:FindFirstChild('HumanoidRootPart')
		if hrp and hrp:IsA('BasePart') and hrp.Position.Y > 40 then
			-- #region agent log
			if type(getgenv().SB2DbgFling) == 'function' then
				getgenv().SB2DbgFling('B', 'boot:holdAnchor', 'SKIP hold (high Y) — do not hard-anchor', {
					y = math.floor(hrp.Position.Y + 0.5),
					anchored = hrp.Anchored,
				})
			end
			-- #endregion
			-- Do NOT force Anchored=true here — that stuck players mid-air unable to walk.
			-- Only skip the unanchor window.
			return
		end
		-- #region agent log
		if type(getgenv().SB2DbgFling) == 'function' then
			getgenv().SB2DbgFling('B', 'boot:holdAnchor', 'CALL holdCombatAnchor(4)', {
				y = hrp and math.floor(hrp.Position.Y + 0.5),
				anchored = hrp and hrp.Anchored,
			})
		end
		-- #endregion
		holdCombatAnchor(4)
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

	-- Workspace delete log is DEBUG-only — ChildRemoved + writefile storms crush FPS.
	if getgenv().SB2WsDeleteLog ~= true then
		-- skip installer
	else
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
		getgenv().SB2WsDeleteLogConn = safeConnect(workspace.ChildRemoved, function(child)
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
	end

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
						Library:Notify('Map still empty — wait for stream or rejoin')
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
			if cam.CameraSubject ~= subject then
				cam.CameraSubject = subject
			end
			-- Repark void cam at origin only — never snap while the user is zoomed/panned out.
			if hrp and (cam.CFrame.Position - hrp.Position).Magnitude > 60 then
				if cam.CFrame.Position.Magnitude < 100 or cam.CameraSubject == nil then
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
		-- Title / cinematic Scriptable cams must not be forced to Custom (black screen).
		if not inGameplayWorld() then
			return false
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
			-- Normal scroll zoom exceeds 60 studs — only void when cam is parked at origin.
			if dist > 60 and cp.Magnitude < 100 then
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
					pcall(function()
						local fn = getgenv().SB2InstallCurseSelfDamageBlock
						if type(fn) == 'function' then
							fn()
						end
					end)
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

	-- Ataraxia chrome only — no Obsidian Library.lua download / cache fallback.
	getgenv().SB2UseAtaraxiaLib = true
	local librarySource
	do
		local ataPath = nil
		for _, path in ipairs({ 'PlayerTools/AtaraxiaLibrary.lua', 'AtaraxiaLibrary.lua' }) do
			if type(isfile) == 'function' and isfile(path) then
				ataPath = path
				break
			end
		end
		if not ataPath then
			error('[PlayerTools] AtaraxiaLibrary.lua missing — required for UI chrome', 0)
		end
		local okA, ataSrc = pcall(readfile, ataPath)
		if not okA or type(ataSrc) ~= 'string' or #ataSrc < 500 or not ataSrc:find('CreateWindow', 1, true) then
			error('[PlayerTools] AtaraxiaLibrary.lua invalid or unreadable: ' .. tostring(ataSrc), 0)
		end
		librarySource = ataSrc
		warn('[PlayerTools] using AtaraxiaLibrary (custom chrome)')
	end

	local libraryFunc = compile(librarySource)
	assert(libraryFunc, 'AtaraxiaLibrary.lua failed to compile')

	-- Force a fresh library instance so AutoFarm can run beside us.
	getgenv().Library = nil
	local Library = libraryFunc()
	assert(Library and Library.CreateWindow, 'Ataraxia library failed to initialize')
	assert(Library.Backend == 'Ataraxia', 'Expected Ataraxia Backend, got ' .. tostring(Library.Backend))
	do
		local origGetTextBounds = Library.GetTextBounds
		if type(origGetTextBounds) == 'function' then
			Library.GetTextBounds = function(self, Text, Font, Size, Width)
				if Font == nil and self.Scheme and self.Scheme.Font then
					Font = self.Scheme.Font
				end
				local ok, x, y = pcall(origGetTextBounds, self, Text, Font, Size, Width)
				if ok and type(x) == 'number' and type(y) == 'number' then
					return x, y
				end
				local size = (type(Size) == 'number' and Size) or 14
				return math.max(8, #tostring(Text or '') * size * 0.52), size + 4
			end
		end
	end
	getgenv()[LIBRARY_KEY] = Library
	-- Tab-switch tweens leave CanvasGroup at GroupTransparency=1 when interrupted
	-- (floor hop / soft reload) — entire tab looks empty including dropdown lists.
	do
		Library.Animations = type(Library.Animations) == 'table' and Library.Animations or {}
		Library.Animations.TabSwitch = false
	end
	-- Rate-limit toasts the same way as notify() — join storms were lagging.
	-- User-driven info (View stats / Mob kills, duration>=8) always bypasses the cap.
	-- Draw on a dedicated ScreenGui. Ataraxia's in-window toast is 40px and clips.
	local function showBigToast(text, duration)
		duration = tonumber(duration) or 5
		local lp = game:GetService('Players').LocalPlayer
		local pg = lp and lp:FindFirstChildOfClass('PlayerGui')
		if not pg then
			warn('[Ataraxia] ' .. tostring(text))
			return
		end
		local tween = game:GetService('TweenService')
		local gui = pg:FindFirstChild('SB2Toasts')
		if not (typeof(gui) == 'Instance' and gui:IsA('ScreenGui')) then
			gui = Instance.new('ScreenGui')
			gui.Name = 'SB2Toasts'
			gui.ResetOnSpawn = false
			gui.IgnoreGuiInset = true
			gui.DisplayOrder = 100000
			gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
			if type(protectgui) == 'function' then
				pcall(protectgui, gui)
			end
			gui.Parent = pg
			local holder = Instance.new('Frame')
			holder.Name = 'Holder'
			holder.BackgroundTransparency = 1
			holder.ClipsDescendants = false
			holder.Size = UDim2.fromOffset(380, 700)
			holder.Position = UDim2.new(1, -396, 0, 16)
			holder.Parent = gui
		end
		local holder = gui:FindFirstChild('Holder')
		if not holder then
			warn('[Ataraxia] ' .. tostring(text))
			return
		end
		holder.Position = UDim2.new(1, -396, 0, 16)
		for _, ch in ipairs(holder:GetChildren()) do
			if ch:IsA('GuiObject') then
				ch:Destroy()
			end
		end
		local body = tostring(text):gsub('\r\n', '\n'):gsub('\r', '\n')
		local rows = {}
		local start = 1
		while true do
			local nl = string.find(body, '\n', start, true)
			rows[#rows + 1] = string.sub(body, start, nl and (nl - 1) or #body)
			if not nl then
				break
			end
			start = nl + 1
		end
		if #rows == 0 then
			rows[1] = body
		end
		local fontSize = 14
		local lineH = 20
		local barH = 4
		local t = Instance.new('Frame')
		t.Name = 'Toast'
		t.Size = UDim2.new(1, 0, 0, 22 + #rows * lineH + barH)
		t.BackgroundColor3 = Color3.fromRGB(26, 26, 26)
		t.BorderSizePixel = 0
		t.ClipsDescendants = true
		t.Parent = holder
		local cr = Instance.new('UICorner')
		cr.CornerRadius = UDim.new(0, 6)
		cr.Parent = t
		local outline = Instance.new('UIStroke')
		outline.Color = Color3.fromRGB(255, 255, 255)
		outline.Thickness = 1
		outline.Transparency = 0
		outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		outline.Parent = t
		for i, row in ipairs(rows) do
			local l = Instance.new('TextLabel')
			l.BackgroundTransparency = 1
			l.Font = Enum.Font.SourceSans
			l.TextSize = fontSize
			l.TextColor3 = Color3.fromRGB(242, 242, 242)
			l.TextXAlignment = Enum.TextXAlignment.Left
			l.TextYAlignment = Enum.TextYAlignment.Center
			l.Text = row
			l.Size = UDim2.new(1, -24, 0, lineH)
			l.Position = UDim2.fromOffset(12, 10 + (i - 1) * lineH)
			l.TextWrapped = false
			l.TextTruncate = Enum.TextTruncate.None
			l.Parent = t
		end
		local track = Instance.new('Frame')
		track.BackgroundColor3 = Color3.fromRGB(48, 48, 48)
		track.BorderSizePixel = 0
		track.Size = UDim2.new(1, -16, 0, barH)
		track.Position = UDim2.new(0, 8, 1, -(barH + 6))
		track.Parent = t
		local trackC = Instance.new('UICorner')
		trackC.CornerRadius = UDim.new(0, 2)
		trackC.Parent = track
		local fill = Instance.new('Frame')
		fill.BackgroundColor3 = Color3.new(1, 1, 1)
		fill.BorderSizePixel = 0
		fill.Size = UDim2.new(1, 0, 1, 0)
		fill.Parent = track
		local fillC = Instance.new('UICorner')
		fillC.CornerRadius = UDim.new(0, 2)
		fillC.Parent = fill
		tween:Create(fill, TweenInfo.new(duration, Enum.EasingStyle.Linear), {
			Size = UDim2.new(0, 0, 1, 0),
		}):Play()
		local flash = Instance.new('Frame')
		flash.BackgroundColor3 = Color3.new(1, 1, 1)
		flash.BackgroundTransparency = 0.45
		flash.BorderSizePixel = 0
		flash.Size = UDim2.new(1, 0, 1, 0)
		flash.ZIndex = (t.ZIndex or 1) + 8
		flash.Parent = t
		local flashC = Instance.new('UICorner')
		flashC.CornerRadius = UDim.new(0, 6)
		flashC.Parent = flash
		tween:Create(flash, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = 1,
		}):Play()
		task.delay(0.3, function()
			if flash.Parent then
				flash:Destroy()
			end
		end)
		task.delay(duration, function()
			if t.Parent then
				t:Destroy()
			end
		end)
	end
	getgenv().SB2ShowBigToast = showBigToast
	do
		local rawNotify = Library.Notify
		if type(rawNotify) == 'function' then
			Library.Notify = function(self, text, duration, force)
				local now = os.clock()
				local dur = tonumber(duration) or 5
				local important = force == true or dur >= 8
				local function fire()
					local ok, err = pcall(showBigToast, text, duration)
					if not ok then
						warn('[PlayerTools] Notify failed: ', err, ' | ', tostring(text):sub(1, 80))
						pcall(rawNotify, self, text, duration)
					end
				end
				if important then
					getgenv().SB2LastLibNotify = { key = tostring(text), at = now }
					-- #region agent log
					pcall(function()
						local payload = game:GetService('HttpService'):JSONEncode({
							sessionId = '7e9135',
							hypothesisId = 'N1',
							location = 'Library.Notify',
							message = 'important notify bypass',
							data = { dur = dur, preview = tostring(text):sub(1, 80) },
							timestamp = os.time() * 1000,
						})
						if type(appendfile) == 'function' then
							pcall(appendfile, 'PlayerTools/debug-7e9135.log', payload .. '\n')
						end
					end)
					-- #endregion
					task.defer(fire)
					return
				end
				if now < (tonumber(getgenv().SB2NotifyQuietUntil) or 0) then
					return
				end
				local key = tostring(text)
				local last = getgenv().SB2LastLibNotify
				if type(last) == 'table' and last.key == key and (now - (tonumber(last.at) or 0)) < 5 then
					return
				end
				local recent = tonumber(getgenv().SB2LibNotifyCount) or 0
				local windowStart = tonumber(getgenv().SB2LibNotifyWindow) or 0
				if now - windowStart > 8 then
					windowStart = now
					recent = 0
				end
				recent += 1
				getgenv().SB2LibNotifyWindow = windowStart
				getgenv().SB2LibNotifyCount = recent
				if recent > 3 then
					-- #region agent log
					pcall(function()
						local payload = game:GetService('HttpService'):JSONEncode({
							sessionId = '7e9135',
							hypothesisId = 'N1',
							location = 'Library.Notify',
							message = 'notify dropped by rate limit',
							data = { recent = recent, preview = tostring(text):sub(1, 60) },
							timestamp = os.time() * 1000,
						})
						if type(appendfile) == 'function' then
							pcall(appendfile, 'PlayerTools/debug-7e9135.log', payload .. '\n')
						end
					end)
					-- #endregion
					return
				end
				getgenv().SB2LastLibNotify = { key = key, at = now }
				task.defer(fire)
			end
		end
	end

	local function ensurePlayerToolsGuiParent(gui)
		if typeof(gui) ~= 'Instance' then
			return false
		end
		pcall(function()
			if gui:IsA('ScreenGui') then
				gui.ResetOnSpawn = false
				gui.IgnoreGuiInset = true
				gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
				if gui.DisplayOrder < 500 then
					gui.DisplayOrder = 998
				end
				gui.Enabled = true
			end
		end)
		if gui.Parent then
			return true
		end
		-- Do NOT call protect_gui here — on Potassium it often leaves Parent=nil
		-- and the menu vanishes. Just parent to a host.
		local function tryParent(host)
			if not host then
				return false
			end
			local ok = pcall(function()
				gui.Parent = host
			end)
			return ok and gui.Parent ~= nil
		end
		local function tryAllHosts()
			if type(gethui) == 'function' then
				local okH, host = pcall(gethui)
				if okH and tryParent(host) then
					return true
				end
			end
			local cg = game:FindService('CoreGui') or game:GetService('CoreGui')
			if tryParent(cg) then
				return true
			end
			-- RobloxGui is valid on this executor (visible menu).
			if cg and tryParent(cg:FindFirstChild('RobloxGui')) then
				return true
			end
			local lp = game:GetService('Players').LocalPlayer
			if lp then
				local pg = lp:FindFirstChildOfClass('PlayerGui')
				if not pg then
					pcall(function()
						pg = lp:WaitForChild('PlayerGui', 2)
					end)
				end
				if tryParent(pg) then
					return true
				end
			end
			return gui.Parent ~= nil
		end
		if tryAllHosts() then
			return true
		end
		for _ = 1, 20 do
			task.wait(0.15)
			if gui.Parent or tryAllHosts() then
				return gui.Parent ~= nil
			end
		end
		return gui.Parent ~= nil
	end

	if Library.ScreenGui then
		pcall(function()
			Library.ScreenGui:SetAttribute('SB2PlayerTools', true)
			Library.ScreenGui.Name = 'SB2PlayerTools'
		end)
		ensurePlayerToolsGuiParent(Library.ScreenGui)
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
	local defaultWindowPosition = UDim2.new(0.5, -math.floor(windowWidth / 2), 0.5, -math.floor(windowHeight / 2))
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

	-- #region agent log
	pcall(function()
		local payload = game:GetService('HttpService'):JSONEncode({
			sessionId = '7e9135',
			hypothesisId = 'UI2',
			location = 'PlayerTools_Obsidian.lua:CreateWindow',
			message = 'window created',
			data = { hasWindow = Window ~= nil },
			timestamp = os.time() * 1000,
		})
		getgenv().SB2LoadCK = getgenv().SB2LoadCK or {}
		getgenv().SB2LoadCK.WINDOW = os.clock()
		if type(appendfile) == 'function' then
			pcall(appendfile, 'PlayerTools/debug-7e9135.log', payload .. '\n')
		end
	end)
	-- #endregion

	-- Interrupted tab/context-menu tweens leave CanvasGroup invisible or dropdown menus 0px wide.
	local function disableObsidianUiAnimations()
		Library.Animations = type(Library.Animations) == 'table' and Library.Animations or {}
		Library.Animations.TabSwitch = false
		Library.Animations.Dropdown = false
		Library.Animations.KeyPicker = false
	end
	disableObsidianUiAnimations()

	-- #region agent log
	pcall(function()
		getgenv().SB2LoadCK = getgenv().SB2LoadCK or {}
		getgenv().SB2LoadCK.AFTER_ANIM = os.clock()
	end)
	-- #endregion

	local function repairObsidianTabCanvas()
		local lib = Library
		if type(lib) ~= 'table' or lib.Unloaded then
			return false
		end
		local fixed = false
		local active = lib.ActiveTab
		if type(active) ~= 'table' and type(lib.Tabs) == 'table' then
			for _, tab in pairs(lib.Tabs) do
				if type(tab) == 'table' and type(tab.Show) == 'function' then
					pcall(function()
						tab:Show()
					end)
					active = lib.ActiveTab
					fixed = true
					break
				end
			end
		end
		if type(active) ~= 'table' and type(lib.Tabs) == 'table' then
			-- Prefer currently-visible sidebar selection; else first tab.
			for _, tab in pairs(lib.Tabs) do
				if type(tab) == 'table' and typeof(tab.Container) == 'Instance' and tab.Container.Visible then
					active = tab
					break
				end
			end
			if type(active) ~= 'table' then
				for _, tab in pairs(lib.Tabs) do
					if type(tab) == 'table' then
						active = tab
						break
					end
				end
			end
			lib.ActiveTab = active
		end

		-- Only one tab Container should be visible.
		if type(lib.Tabs) == 'table' and type(active) == 'table' then
			for _, tab in pairs(lib.Tabs) do
				if type(tab) == 'table' and typeof(tab.Container) == 'Instance' and tab.Container:IsA('GuiObject') then
					local want = tab == active
					if tab.Container.Visible ~= want then
						tab.Container.Visible = want
						fixed = true
					end
				end
			end
		end

		if type(active) == 'table' and typeof(active.Canvas) == 'Instance' then
			local cg = active.Canvas
			if cg:IsA('CanvasGroup') then
				if cg.GroupTransparency >= 0.99 or cg.Visible ~= true then
					cg.GroupTransparency = 0
					cg.Visible = true
					cg.Position = UDim2.fromScale(0, 0)
					fixed = true
				end
			elseif cg:IsA('GuiObject') then
				cg.Visible = true
				cg.Position = UDim2.fromScale(0, 0)
			end
		end
		-- Starlight/Obsidian Frame tabs: content lives on Tab.Container (not Canvas).
		if type(active) == 'table' and typeof(active.Container) == 'Instance' then
			local c = active.Container
			if c:IsA('GuiObject') then
				if c.Visible ~= true then
					c.Visible = true
					fixed = true
				end
				-- Unstick nested scroll/group hosts that sometimes stay at 0 size / hidden.
				for _, d in ipairs(c:GetDescendants()) do
					if d:IsA('ScrollingFrame') then
						if d.Visible ~= true then
							d.Visible = true
							fixed = true
						end
						pcall(function()
							if d.AbsoluteSize.Y < 2 and d.Parent and d.Parent:IsA('GuiObject') then
								d.Size = UDim2.new(1, 0, 1, 0)
								fixed = true
							end
						end)
					elseif d:IsA('TextLabel') or d:IsA('TextButton') then
						-- Theme/animation can leave labels nearly invisible on dark panels.
						if d.TextTransparency > 0.35 and tostring(d.Text or '') ~= '' then
							d.TextTransparency = 0
							fixed = true
						end
					end
				end
			end
		end
		return fixed
	end
	getgenv().SB2RepairObsidianTabCanvas = repairObsidianTabCanvas

	Library.PlayTabAnimation = function(_self, tabCanvas, showing, onComplete)
		if not tabCanvas then
			if onComplete then
				onComplete()
			end
			return
		end
		-- Obsidian passes either a Canvas/Frame Instance OR the Tab table itself.
		local canvas = tabCanvas
		if type(tabCanvas) == 'table' and typeof(tabCanvas) ~= 'Instance' then
			canvas = tabCanvas.Canvas or tabCanvas.Container or tabCanvas
		end
		if typeof(canvas) == 'Instance' then
			if canvas:IsA('GuiObject') then
				canvas.Visible = showing == true
				pcall(function()
					canvas.Position = UDim2.fromScale(0, 0)
				end)
			end
			if canvas:IsA('CanvasGroup') then
				canvas.GroupTransparency = showing and 0 or 1
			end
		elseif type(tabCanvas) == 'table' then
			-- Legacy Obsidian path: mutate tab fields (do NOT call Instance methods).
			tabCanvas.Visible = showing == true
			tabCanvas.GroupTransparency = showing and 0 or 1
			tabCanvas.Position = UDim2.fromScale(0, 0)
			if typeof(tabCanvas.Container) == 'Instance' and tabCanvas.Container:IsA('GuiObject') then
				tabCanvas.Container.Visible = showing == true
			end
		end
		if onComplete then
			onComplete()
		end
	end

	do
		local origAddContextMenu = Library.AddContextMenu
		if type(origAddContextMenu) == 'function' then
			Library.AddContextMenu = function(self, holder, size, offset, list, activeCallback, ...)
				local menuTable = origAddContextMenu(self, holder, size, offset, list, activeCallback, ...)
				if list == 2 and type(menuTable) == 'table' and type(menuTable.Open) == 'function' then
					local origOpen = menuTable.Open
					menuTable.Open = function(...)
						pcall(repairObsidianTabCanvas)
						origOpen(...)
						task.defer(function()
							if menuTable.Active and type(menuTable.SetSize) == 'function' and menuTable.Size then
								pcall(function()
									menuTable:SetSize(menuTable.Size)
								end)
							end
						end)
					end
				end
				return menuTable
			end
		end
	end

	-- CreateWindow may rebuild ScreenGui; parent again with ProtectGui / gethui / PlayerGui.
	do
		local gui = Library.ScreenGui
		if typeof(gui) == 'Instance' then
			pcall(function()
				gui:SetAttribute('SB2PlayerTools', true)
				gui.Name = 'SB2PlayerTools'
			end)
			ensurePlayerToolsGuiParent(gui)
			getgenv().SB2PlayerToolsGui = gui
		end
		if not (Library.ScreenGui and Library.ScreenGui.Parent) then
			-- Don't abort the whole script on floor-hop races — keep retrying in background.
			local warnKey = 'SB2UiParentDelayWarnedAt'
			local lastWarn = tonumber(getgenv()[warnKey]) or 0
			if (os.clock() - lastWarn) > 8 then
				getgenv()[warnKey] = os.clock()
				warn('[PlayerTools] UI parent delayed — retrying (PlayerGui not ready yet)')
			end
			task.spawn(function()
				local gui2 = Library.ScreenGui
				for _ = 1, 40 do
					if not gui2 or not gui2.Parent then
						if typeof(gui2) == 'Instance' then
							ensurePlayerToolsGuiParent(gui2)
						end
					end
					if gui2 and gui2.Parent then
						getgenv().SB2PlayerToolsGui = gui2
						return
					end
					task.wait(0.25)
				end
				warn('[PlayerTools] UI still unparented after retries — press Home / re-run PlayerTools')
			end)
		end
	end
	pcall(function()
		local keep = Library.ScreenGui
		local function sweep(parent)
			if not parent then
				return
			end
			for _, gui in ipairs(parent:GetChildren()) do
				if gui:IsA('ScreenGui') and gui ~= keep then
					if gui:GetAttribute('SB2PlayerTools') == true or gui.Name == 'SB2PlayerTools' then
						pcall(function()
							gui:Destroy()
						end)
					end
				end
			end
		end
		local lp = game:GetService('Players').LocalPlayer
		if lp then
			sweep(lp:FindFirstChild('PlayerGui'))
		end
		sweep(game:GetService('CoreGui'))
		if type(gethui) == 'function' then
			sweep(gethui())
		end
	end)
	pcall(function()
		Library.ShowCustomCursor = false
		Library.OriginalMinSize = minSize
		Library.MinSize = minSize * (Library.DPIScale or 1)
	end)
	pcall(function()
		local main = Library.ScreenGui and Library.ScreenGui:FindFirstChild('Main')
		if not main then
			return
		end
		if Library.Backend == 'Ataraxia' then
			local w = math.max(880, windowSize.X.Offset)
			local h = math.max(560, windowSize.Y.Offset)
			main.Size = UDim2.fromOffset(w, h)
			Library.MinSize = Vector2.new(880, 560)
			Library.OriginalMinSize = Library.MinSize
			return
		end
		main.Size = windowSize
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
		pcall(repairObsidianTabCanvas)
		pcall(function()
			if Library.Unloaded then
				return
			end
			getgenv().SB2MenuWantOpen = true
			local gui = Library.ScreenGui or getgenv().SB2PlayerToolsGui
			if typeof(gui) == 'Instance' then
				pcall(ensurePlayerToolsGuiParent, gui)
				gui.Enabled = true
			end
			local main = gui and gui:FindFirstChild('Main')
			-- Do NOT call Library:Toggle() here — on floor hops it races and can close
			-- the menu after we open it. Pin flags + Main.Visible directly.
			pcall(function()
				Library.Toggled = true
				if Library.Open ~= nil then
					Library.Open = true
				end
			end)
			if main then
				main.Visible = true
				if resetPos or not isPositionOnScreen(main.Position) then
					main.Position = defaultWindowPosition
					saveWindowPosition(defaultWindowPosition)
				end
			end
			-- #region agent log
			pcall(function()
				local payload = game:GetService('HttpService'):JSONEncode({
					sessionId = '7e9135',
					hypothesisId = 'UI4',
					location = 'forceShowWindow',
					message = 'pinned menu open (no Toggle)',
					data = {
						mainVis = main and main.Visible == true,
						toggled = Library.Toggled == true,
						place = game.PlaceId,
						grace = (tonumber(getgenv().SB2MenuHopGraceUntil) or 0) > os.clock(),
						resetPos = resetPos == true,
					},
					timestamp = os.time() * 1000,
				})
				if type(appendfile) == 'function' then
					pcall(appendfile, 'PlayerTools/debug-7e9135.log', payload .. '\n')
				end
			end)
			-- #endregion
			pcall(repairObsidianTabCanvas)
			local active = Library.ActiveTab
			if type(active) == 'table' then
				if typeof(active.Container) == 'Instance' and active.Container:IsA('GuiObject') then
					active.Container.Visible = true
				end
				if type(active.Show) == 'function' then
					pcall(function()
						active:Show()
					end)
				end
			end
			-- Re-assert after Obsidian/Starlight animations finish (floor-hop flash).
			local gen = (tonumber(getgenv().SB2MenuPinGen) or 0) + 1
			getgenv().SB2MenuPinGen = gen
			for _, delaySec in ipairs({ 0.35, 1.0, 2.5 }) do
				task.delay(delaySec, function()
					if getgenv().SB2MenuPinGen ~= gen then
						return
					end
					if getgenv().SB2MenuWantOpen ~= true then
						return
					end
					if getgenv().SB2PlayerToolsManualUnload == true then
						return
					end
					local g2 = Library.ScreenGui or getgenv().SB2PlayerToolsGui
					local m2 = g2 and g2:FindFirstChild('Main')
					if typeof(g2) == 'Instance' then
						g2.Enabled = true
					end
					if m2 and m2.Visible ~= true then
						-- #region agent log
						pcall(function()
							local payload = game:GetService('HttpService'):JSONEncode({
								sessionId = '7e9135',
								hypothesisId = 'UI4',
								location = 'forceShowWindow.reassert',
								message = 're-opened after animation/hop',
								data = { delaySec = delaySec, place = game.PlaceId },
								timestamp = os.time() * 1000,
							})
							if type(appendfile) == 'function' then
								pcall(appendfile, 'PlayerTools/debug-7e9135.log', payload .. '\n')
							end
						end)
						-- #endregion
						m2.Visible = true
						pcall(function()
							Library.Toggled = true
						end)
						pcall(repairObsidianTabCanvas)
					end
				end)
			end
		end)
	end
	getgenv().SB2ForceShowPlayerTools = forceShowWindow

	-- Same as pressing the menu keybind (Home): hide UI, do not Unload.
	-- DEV copy only: NickB926 keeps the menu; alts still hide.
	local function isDevCopy()
		if type(isfile) ~= 'function' then
			return false
		end
		local ok, exists = pcall(isfile, 'PlayerTools/_dev_copy')
		return ok and exists == true
	end
	local function isMainDevClient()
		local lp = LocalPlayer
		if not lp then
			return false
		end
		if tonumber(lp.UserId) == 105008790 then
			return true
		end
		return string.lower(tostring(lp.Name or '')) == 'nickb926'
	end
	getgenv().SB2IsDevCopy = isDevCopy
	getgenv().SB2IsMainDevClient = isMainDevClient

	getgenv().SB2HidePlayerToolsMenu = function()
		if isDevCopy() and isMainDevClient() then
			return
		end
		getgenv().SB2MenuWantOpen = false
		getgenv().SB2MenuPinGen = (tonumber(getgenv().SB2MenuPinGen) or 0) + 1
		-- Prefer forced close so Ataraxia shows the Tap-to-show pill.
		if type(Library.Toggle) == 'function' then
			pcall(function()
				Library:Toggle(false)
			end)
		end
		getgenv().SB2MenuWantOpen = false
		pcall(function()
			Library.Toggled = false
			if Library.Open ~= nil then
				Library.Open = false
			end
		end)
		local gui = Library.ScreenGui or getgenv().SB2PlayerToolsGui
		local main = gui and gui:FindFirstChild('Main')
		if main then
			main.Visible = false
		end
		local pill = gui and gui:FindFirstChild('ShowPill')
		if pill then
			pill.Visible = true
		end
	end

	local HIDE_MENU_FILE = joinPath(CONFIG.ConfigFolder, '_hide_menu')
	local HIDE_MENU_FILE_ALT = 'PlayerTools/_hide_menu'
	local TILE_NOW_FILE = joinPath(CONFIG.ConfigFolder, '_tile_now')
	getgenv().SB2HideMenuLast = getgenv().SB2HideMenuLast or ''

	local function readHideStamp()
		if type(readfile) ~= 'function' then
			return nil
		end
		for _, path in ipairs({ HIDE_MENU_FILE, HIDE_MENU_FILE_ALT }) do
			local okExists, exists = pcall(function()
				return type(isfile) == 'function' and isfile(path)
			end)
			if okExists and exists then
				local ok, body = pcall(readfile, path)
				if ok and type(body) == 'string' and body ~= '' then
					return body
				end
			end
		end
		return nil
	end

	local function ensureHideMenuPoller()
		-- Soft reloads used to kill the loop (GenvKey flicker) and never restart it.
		if getgenv().SB2HideMenuPollerAlive == true then
			return
		end
		getgenv().SB2HideMenuPollGen = (tonumber(getgenv().SB2HideMenuPollGen) or 0) + 1
		local myGen = getgenv().SB2HideMenuPollGen
		getgenv().SB2HideMenuPoller = true
		getgenv().SB2HideMenuPollerAlive = true
		task.spawn(function()
			while getgenv()[CONFIG.GenvKey] and getgenv().SB2HideMenuPollGen == myGen do
				local body = readHideStamp()
				if body and body ~= getgenv().SB2HideMenuLast then
					getgenv().SB2HideMenuLast = body
					if type(getgenv().SB2HidePlayerToolsMenu) == 'function' then
						pcall(getgenv().SB2HidePlayerToolsMenu)
					end
				end
				task.wait(0.25)
			end
			if getgenv().SB2HideMenuPollGen == myGen then
				getgenv().SB2HideMenuPoller = nil
				getgenv().SB2HideMenuPollerAlive = nil
			end
		end)
	end
	ensureHideMenuPoller()

	getgenv().SB2BroadcastHideMenus = function()
		ensureHideMenuPoller()
		local stamp = tostring(os.clock()) .. ':' .. tostring(math.random(1, 1e9))
		getgenv().SB2HideMenuLast = stamp
		if type(writefile) == 'function' then
			pcall(writefile, HIDE_MENU_FILE, stamp)
			pcall(writefile, HIDE_MENU_FILE_ALT, stamp)
		end
		-- Self-hide still goes through SB2HidePlayerToolsMenu (DEV main no-ops).
		if type(getgenv().SB2HidePlayerToolsMenu) == 'function' then
			pcall(getgenv().SB2HidePlayerToolsMenu)
		end
		local hive = getgenv().SB2Hive
		if type(hive) == 'table' and hive._alive == true and type(hive.issue) == 'function' then
			pcall(function()
				hive.issue('hide_menu', {})
			end)
		end
	end

	-- Tile = write flags only. Roblox/Potassium cannot launch PowerShell.
	-- Host watcher (Tile Roblox.bat / watch-tile.ps1) tiles when _tile_now changes.
	-- Every client polls _hide_menu and closes the UI (DEV main skips).
	getgenv().SB2TileRobloxWindows = function()
		ensureHideMenuPoller()
		local stamp = tostring(os.clock()) .. ':' .. tostring(math.random(1, 1e9))
		local altsOnly = isDevCopy()
		if type(getgenv().SB2BroadcastHideMenus) == 'function' then
			pcall(getgenv().SB2BroadcastHideMenus)
		elseif type(getgenv().SB2HidePlayerToolsMenu) == 'function' then
			pcall(getgenv().SB2HidePlayerToolsMenu)
		end
		if type(writefile) == 'function' then
			-- Workspace + scripts paths so the Windows watcher sees either.
			pcall(writefile, TILE_NOW_FILE, stamp)
			pcall(writefile, 'PlayerTools/_tile_now', stamp)
			if altsOnly then
				pcall(writefile, joinPath(CONFIG.ConfigFolder, '_tile_alts_only'), stamp)
				pcall(writefile, 'PlayerTools/_tile_alts_only', stamp)
				-- Title match beats "largest window" (that was tiling Nick / crashing him).
				local skipBody = "nickb926\nNickB926\n"
				pcall(writefile, joinPath(CONFIG.ConfigFolder, '_tile_skip_names'), skipBody)
				pcall(writefile, 'PlayerTools/_tile_skip_names', skipBody)
			end
		end
		if type(Library.Notify) == 'function' then
			if altsOnly then
				Library:Notify('Tile signal sent — alts only (DEV); NickB926 window never resized.', 5)
			else
				Library:Notify('Tile signal sent — host watcher tiles all windows + every client hides UI.', 5)
			end
		end
	end

	-- Track intentional close vs hop races. During hop grace, ignore closes.
	do
		local rawToggle = Library.Toggle
		if type(rawToggle) == 'function' and Library._SB2TogglePinned ~= true then
			Library.Toggle = function(self, ...)
				local before = self.Toggled == true
				local results = table.pack(pcall(rawToggle, self, ...))
				local after = self.Toggled == true
				local grace = os.clock() < (tonumber(getgenv().SB2MenuHopGraceUntil) or 0)
				if grace and getgenv().SB2MenuWantOpen == true and after ~= true then
					-- Something closed us during floor hop — pin back open.
					pcall(forceShowWindow, false)
				elseif not grace then
					getgenv().SB2MenuWantOpen = after
				end
				if results[1] then
					return table.unpack(results, 2, results.n)
				end
			end
			Library._SB2TogglePinned = true
		end
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
		getgenv().SB2MenuHopGraceUntil = os.clock() + 20
		getgenv().SB2UiKeeperQuietUntil = os.clock() + 12
		getgenv().SB2MenuWantOpen = true
		forceShowWindow(true)
	end)

	-- If ScreenGui gets unparented, put it back immediately (don't wait on protect_gui).
	-- Also re-assert the session flag — floor hops often left GUI alive with
	-- SB2PlayerTools=false, which stopped this loop and made the menu "unload".
	task.spawn(function()
		getgenv().SB2UiKeeperGen = (tonumber(getgenv().SB2UiKeeperGen) or 0) + 1
		local keeperGen = getgenv().SB2UiKeeperGen
		local lastPlace = game.PlaceId
		local function sessionBlocked()
			return getgenv().SB2PlayerToolsManualUnload == true
		end
		local function tryRelaunch(reason)
			if sessionBlocked() then
				return
			end
			if getgenv().SB2PlayerToolsLoading == true then
				return
			end
			local quietUntil = tonumber(getgenv().SB2UiKeeperQuietUntil) or 0
			if os.clock() < quietUntil then
				return
			end
			-- During floor-hop grace, only soft-reparent — never full rebuild (causes flash).
			if os.clock() < (tonumber(getgenv().SB2MenuHopGraceUntil) or 0) then
				local gui = getgenv().SB2PlayerToolsGui or (Library and Library.ScreenGui)
				if typeof(gui) == 'Instance' then
					pcall(ensurePlayerToolsGuiParent, gui)
					if gui.Parent then
						pcall(forceShowWindow, false)
					end
				end
				return
			end
			-- Prefer soft refresh — full launch.lua calls unloadExisting and nukes the menu.
			local gui = getgenv().SB2PlayerToolsGui or (Library and Library.ScreenGui)
			if typeof(gui) == 'Instance' then
				pcall(ensurePlayerToolsGuiParent, gui)
				if gui.Parent and type(getgenv().SB2RefreshPlayerTools) == 'function' then
					getgenv().SB2PlayerTools = true
					getgenv().SB2PlayerToolsGui = gui
					getgenv().SB2UiKeeperQuietUntil = os.clock() + 8
					pcall(getgenv().SB2RefreshPlayerTools)
					return
				end
				-- Instance still exists but unparented — keep retrying reparent, don't rebuild yet.
				local fails = (tonumber(getgenv().SB2UiOrphanFails) or 0) + 1
				getgenv().SB2UiOrphanFails = fails
				local needFails = 10
				if fails < needFails then
					-- #region agent log
					pcall(function()
						local payload = game:GetService('HttpService'):JSONEncode({
							sessionId = '7e9135',
							hypothesisId = 'UI5',
							location = 'tryRelaunch',
							message = 'orphan reparent retry (no full relaunch)',
							data = { fails = fails, reason = tostring(reason) },
							timestamp = os.time() * 1000,
						})
						if type(appendfile) == 'function' then
							pcall(appendfile, 'PlayerTools/debug-7e9135.log', payload .. '\n')
						end
					end)
					-- #endregion
					return
				end
			end
			local now = os.clock()
			local lastAt = tonumber(getgenv().SB2UiKeeperRelaunchAt) or 0
			if (now - lastAt) < 60 then
				return
			end
			getgenv().SB2UiKeeperRelaunchAt = now
			getgenv().SB2UiOrphanFails = 0
			getgenv().SB2PlayerToolsLoading = true
			getgenv().SB2PlayerToolsLoadingSince = now
			getgenv().SB2SoftPlayerToolsReload = true
			getgenv().SB2UiKeeperQuietUntil = now + 15
			warn('[PlayerTools] UI keeper relaunch — ' .. tostring(reason))
			-- #region agent log
			pcall(function()
				local payload = game:GetService('HttpService'):JSONEncode({
					sessionId = '7e9135',
					hypothesisId = 'UI5',
					location = 'tryRelaunch',
					message = 'full relaunch',
					data = { reason = tostring(reason), place = game.PlaceId },
					timestamp = os.time() * 1000,
				})
				if type(appendfile) == 'function' then
					pcall(appendfile, 'PlayerTools/debug-7e9135.log', payload .. '\n')
				end
			end)
			-- #endregion
			task.defer(function()
				pcall(function()
					local p = (isfile and isfile('PlayerTools/PlayerTools.lua') and 'PlayerTools/PlayerTools.lua')
						or (isfile and isfile('PlayerTools/launch.lua') and 'PlayerTools/launch.lua')
					if not p then
						getgenv().SB2PlayerToolsLoading = false
						getgenv().SB2PlayerToolsLoadingSince = nil
						getgenv().SB2SoftPlayerToolsReload = nil
						return
					end
					getgenv().SB2RefreshPlayerTools = nil
					local fn, cerr = (loadstring or load)(readfile(p), p)
					if fn then
						fn()
					else
						warn('[PlayerTools] keeper compile failed: ' .. tostring(cerr))
						getgenv().SB2PlayerToolsLoading = false
						getgenv().SB2PlayerToolsLoadingSince = nil
						getgenv().SB2SoftPlayerToolsReload = nil
					end
				end)
			end)
		end
		pcall(function()
			local gui0 = getgenv().SB2PlayerToolsGui or (Library and Library.ScreenGui)
			if typeof(gui0) == 'Instance' then
				gui0.AncestryChanged:Connect(function(_, parent)
					if sessionBlocked() then
						return
					end
					if parent then
						getgenv().SB2PlayerTools = true
						getgenv().SB2UiOrphanFails = 0
						return
					end
					-- Immediate soft recover — do not full-relaunch from AncestryChanged.
					task.defer(function()
						local gui = getgenv().SB2PlayerToolsGui or gui0
						if typeof(gui) ~= 'Instance' then
							return
						end
						if gui.Parent then
							getgenv().SB2PlayerTools = true
							getgenv().SB2UiOrphanFails = 0
							return
						end
						for _ = 1, 6 do
							pcall(ensurePlayerToolsGuiParent, gui)
							if gui.Parent then
								getgenv().SB2PlayerTools = true
								getgenv().SB2PlayerToolsGui = gui
								getgenv().SB2UiOrphanFails = 0
								pcall(forceShowWindow, false)
								return
							end
							task.wait(0.2)
						end
					end)
				end)
			end
		end)
		while true do
			if getgenv().SB2UiKeeperGen ~= keeperGen then
				break
			end
			if sessionBlocked() then
				break
			end
			task.wait(1)
			if getgenv().SB2UiKeeperGen ~= keeperGen then
				break
			end
			if getgenv().SB2PlayerToolsLoading == true then
				continue
			end
			-- Keep session flag alive while the window exists.
			local gui = getgenv().SB2PlayerToolsGui or (Library and Library.ScreenGui)
			if typeof(gui) == 'Instance' and gui.Parent then
				if getgenv().SB2PlayerTools ~= true then
					getgenv().SB2PlayerTools = true
					if getgenv().SB2PlayerToolsLibrary == nil and type(Library) == 'table' then
						getgenv().SB2PlayerToolsLibrary = Library
					end
					if type(repairObsidianTabCanvas) == 'function' then
						pcall(repairObsidianTabCanvas)
					end
					if type(getgenv().SB2RefreshAllDropdownDisplays) == 'function' then
						pcall(getgenv().SB2RefreshAllDropdownDisplays)
					end
				end
				if gui.Enabled == false then
					pcall(function()
						gui.Enabled = true
					end)
				end
				-- Recover "loaded but invisible" desync during/after floor hops.
				pcall(function()
					local main = gui:FindFirstChild('Main')
					if not main then
						return
					end
					local want = getgenv().SB2MenuWantOpen ~= false
					local grace = os.clock() < (tonumber(getgenv().SB2MenuHopGraceUntil) or 0)
					if want and main.Visible ~= true and (Library.Toggled == true or grace) then
						main.Visible = true
						Library.Toggled = true
						if type(repairObsidianTabCanvas) == 'function' then
							repairObsidianTabCanvas()
						end
					elseif Library.Toggled == true and main.Visible ~= true then
						main.Visible = true
						if type(repairObsidianTabCanvas) == 'function' then
							repairObsidianTabCanvas()
						end
					end
				end)
			elseif typeof(gui) == 'Instance' and not gui.Parent then
				pcall(ensurePlayerToolsGuiParent, gui)
				if gui.Parent then
					getgenv().SB2PlayerTools = true
					getgenv().SB2PlayerToolsGui = gui
					getgenv().SB2UiOrphanFails = 0
					pcall(function()
						Library.ScreenGui = gui
						gui.Enabled = true
						local main = gui:FindFirstChild('Main')
						if main then
							main.Visible = true
						end
					end)
					pcall(forceShowWindow, false)
					if type(getgenv().SB2RefreshAllDropdownDisplays) == 'function' then
						task.defer(getgenv().SB2RefreshAllDropdownDisplays)
					end
				else
					task.wait(0.75)
					if getgenv().SB2UiKeeperGen ~= keeperGen or getgenv().SB2PlayerToolsLoading == true then
						continue
					end
					pcall(ensurePlayerToolsGuiParent, gui)
					if gui.Parent then
						getgenv().SB2PlayerTools = true
						getgenv().SB2PlayerToolsGui = gui
						getgenv().SB2UiOrphanFails = 0
						pcall(forceShowWindow, false)
					else
						tryRelaunch('ScreenGui orphaned after floor hop')
					end
				end
			elseif getgenv().SB2PlayerTools == true then
				-- Flag says live but no GUI — rebuild only after soft retries fail.
				tryRelaunch('session flag set but ScreenGui missing')
			end
			if game.PlaceId ~= lastPlace then
				lastPlace = game.PlaceId
				getgenv().SB2MenuHopGraceUntil = os.clock() + 25
				getgenv().SB2UiKeeperQuietUntil = os.clock() + 25
				getgenv().SB2MenuWantOpen = true
				getgenv().SB2UiOrphanFails = 0
				-- #region agent log
				pcall(function()
					local payload = game:GetService('HttpService'):JSONEncode({
						sessionId = '7e9135',
						hypothesisId = 'UI4',
						location = 'uiKeeper.PlaceId',
						message = 'place changed — hop grace',
						data = { place = game.PlaceId },
						timestamp = os.time() * 1000,
					})
					if type(appendfile) == 'function' then
						pcall(appendfile, 'PlayerTools/debug-7e9135.log', payload .. '\n')
					end
				end)
				-- #endregion
				if type(getgenv().SB2PlayerToolsArmTeleport) == 'function' then
					pcall(getgenv().SB2PlayerToolsArmTeleport)
				end
				task.defer(function()
					local g2 = getgenv().SB2PlayerToolsGui or (Library and Library.ScreenGui)
					if typeof(g2) == 'Instance' and not g2.Parent then
						for _ = 1, 8 do
							pcall(ensurePlayerToolsGuiParent, g2)
							if g2.Parent then
								break
							end
							task.wait(0.25)
						end
					end
					-- Soft reopen only during hop — never full relaunch from PlaceId change.
					if typeof(g2) == 'Instance' and g2.Parent then
						getgenv().SB2PlayerTools = true
						getgenv().SB2UiOrphanFails = 0
						pcall(forceShowWindow, false)
					end
				end)
			end
			-- Stop only on intentional unload (not when flag was falsely cleared).
			if getgenv().SB2PlayerToolsManualUnload == true then
				break
			end
		end
	end)

	task.spawn(function()
		for _ = 1, 10 do
			if applyTitleIcon(windowIcon) then
				break
			end
			task.wait(0.1)
		end
	end)

	-- #region agent log
	pcall(function()
		getgenv().SB2LoadCK = getgenv().SB2LoadCK or {}
		getgenv().SB2LoadCK.BEFORE_PLAYERS = os.clock()
		local payload = game:GetService('HttpService'):JSONEncode({
			sessionId = '7e9135',
			hypothesisId = 'UI2',
			location = 'PlayerTools_Obsidian.lua:beforePlayers',
			message = 'about to AddTab Players',
			data = {},
			timestamp = os.time() * 1000,
		})
		if type(appendfile) == 'function' then
			pcall(appendfile, 'PlayerTools/debug-7e9135.log', payload .. '\n')
		end
	end)
	-- #endregion

	local HomeTab = Window:AddTab('Home', 'home')
	local HomeBox = HomeTab:AddLeftGroupbox('Ataraxia')
	assert(HomeBox, 'Home groupbox nil')

	local PlayersTab = Window:AddTab('Players', 'users')
	local PlayersBox = PlayersTab:AddLeftGroupbox('Players')
	assert(PlayersBox, 'AddLeftGroupbox returned nil')

	-- #region agent log
	pcall(function()
		getgenv().SB2LoadCK = getgenv().SB2LoadCK or {}
		getgenv().SB2LoadCK.PLAYERSBOX = os.clock()
	end)
	-- #endregion

	local selectedPlayer
	local selectedProfileName
	local spectateTargetName = nil -- locked username while Spectate / Spectate (stream) is on
	getgenv().SB2SpectateTargetName = nil

	local getProfilesFolder = function()
		if Profiles and Profiles.Parent then
			return Profiles
		end
		local folder = game:GetService('ReplicatedStorage'):FindFirstChild('Profiles')
		if folder then
			Profiles = folder
		end
		return folder
	end

	local resolveProfileName = function(value)
		if type(value) == 'string' and value ~= '' then
			return value
		end
		if typeof(value) == 'Instance' then
			if value:IsA('Player') then
				return value.Name
			end
			-- Profile folder under ReplicatedStorage.Profiles
			if value.Parent and value.Parent.Name == 'Profiles' then
				return value.Name
			end
			return value.Name
		end
		return nil
	end

	local resolvePlayerInstance = function(value)
		if typeof(value) == 'Instance' and value:IsA('Player') then
			return value
		end
		local name = resolveProfileName(value)
		if name then
			return Players:FindFirstChild(name) or Players:FindFirstChild(name:match('^([^%s]+)'))
		end
		return nil
	end

	local getSelectedProfileName = function()
		-- Prefer live dropdown Value — cached selectedPlayer was sticking spectate
		-- on the previous pick when the list UI changed.
		if type(spectateTargetName) == 'string' and spectateTargetName ~= ''
			and (isToggleOn('ViewPlayer') or isToggleOn('ViewPlayerStream'))
		then
			return spectateTargetName
		end
		local fromOpt = Options.PlayerList and Options.PlayerList.Value
		local name = resolveProfileName(fromOpt)
		if name and name ~= '' then
			return name
		end
		return resolveProfileName(selectedProfileName) or resolveProfileName(selectedPlayer)
	end

	local getSelectedProfile = function()
		local name = getSelectedProfileName()
		local folder = getProfilesFolder()
		return name and folder and folder:FindFirstChild(name) or nil
	end

	local getSelectedPlayer = function()
		local name = getSelectedProfileName()
		if name and name ~= '' then
			local plr = Players:FindFirstChild(name)
			if plr then
				return plr
			end
		end
		return resolvePlayerInstance(selectedPlayer)
	end

	local resolvePlayerCharacter = function(player)
		if not player then
			return nil
		end
		local char = player.Character
		if char and char.Parent then
			return char
		end
		local folder = workspace:FindFirstChild('Characters')
		local alt = folder and folder:FindFirstChild(player.Name)
		if alt and alt.Parent then
			return alt
		end
		return nil
	end

	local resolveCharacterByName = function(name)
		if type(name) ~= 'string' or name == '' then
			return nil
		end
		local plr = Players:FindFirstChild(name)
		local char = plr and resolvePlayerCharacter(plr)
		if char then
			return char, plr
		end
		local folder = workspace:FindFirstChild('Characters')
		local alt = folder and folder:FindFirstChild(name)
		if alt and alt.Parent then
			return alt, plr
		end
		return nil, plr
	end

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

	local getInventoryItemById = function(profile, id)
		if not profile or not id or id == 0 then
			return nil
		end
		local inv = profile:FindFirstChild('Inventory')
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

	local getInventoryItemNameById = function(profile, id)
		if not profile or not id or id == 0 then
			return 'none'
		end
		local item = getInventoryItemById(profile, id)
		return item and item.Name or 'unknown'
	end

	-- Skin StringValue on inventory items = vanity / body aura / weapon aura.
	local getInventoryItemSkinById = function(profile, id)
		local item = getInventoryItemById(profile, id)
		if not item then
			return nil
		end
		local skin = item:FindFirstChild('Skin')
		if skin and skin:IsA('StringValue') then
			local s = tostring(skin.Value or '')
			if s ~= '' then
				return s
			end
		end
		return nil
	end

	local formatEquippedWithVanity = function(profile, id)
		local name = getInventoryItemNameById(profile, id)
		if name == 'none' or name == 'unknown' then
			return name
		end
		local skin = getInventoryItemSkinById(profile, id)
		if skin then
			return name .. ' (' .. skin .. ')'
		end
		return name
	end

	local readPlayerStats = function(playerOrName)
		local name = resolveProfileName(playerOrName)
			or (typeof(playerOrName) == 'Instance' and playerOrName.Name)
		if not name then
			return nil
		end
		local folder = getProfilesFolder()
		local profile = folder and folder:FindFirstChild(name)
		if not profile then
			return nil
		end
		local player = (typeof(playerOrName) == 'Instance' and playerOrName:IsA('Player') and playerOrName)
			or Players:FindFirstChild(name)
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

		local char = (player and player.Character)
			or (workspace:FindFirstChild('Characters') and workspace.Characters:FindFirstChild(name))
		local entity = char and char:FindFirstChild('Entity')
		local buffs = entity and entity:FindFirstChild('Buffs')
		local hum = char and char:FindFirstChildOfClass('Humanoid')

		local readBuff = function(buffName)
			local v = buffs and buffs:FindFirstChild(buffName)
			if v and typeof(v.Value) == 'number' then
				return v.Value
			end
			return nil
		end

		local walkSpeed = nil
		if char then
			-- Game stores base on the character attribute; Humanoid.WalkSpeed is the live value
			-- (may be modified by PlayerTools / buffs). Prefer attribute when present.
			local attr = char:GetAttribute('Walkspeed') or char:GetAttribute('WalkSpeed')
			if type(attr) == 'number' and attr > 0 then
				walkSpeed = attr
			end
		end
		if not walkSpeed or walkSpeed == 0 then
			walkSpeed = hum and hum.WalkSpeed or nil
		end

		return {
			profile = profile,
			name = name,
			level = getLevelFromExp(exp),
			vel = vel,
			right = formatEquippedWithVanity(profile, rightId),
			left = formatEquippedWithVanity(profile, leftId),
			armor = formatEquippedWithVanity(profile, armorId),
			companion = formatEquippedWithVanity(profile, companionId),
			accessory1 = formatEquippedWithVanity(profile, accessory1Id),
			accessory2 = formatEquippedWithVanity(profile, accessory2Id),
			staminaRegen = readBuff('StaminaRegeneration'),
			healthRegen = readBuff('HealthRegeneration'),
			speedBuff = readBuff('Speed'),
			walkSpeed = walkSpeed,
			jumpPower = hum and hum.JumpPower or nil,
			jumpHeight = hum and hum.JumpHeight or nil,
			loaded = char ~= nil,
			online = player ~= nil,
		}
	end

	local copyTextToClipboard = function(text)
		if type(setclipboard) == 'function' and pcall(setclipboard, text) then
			return true
		end
		if type(toclipboard) == 'function' and pcall(toclipboard, text) then
			return true
		end
		return false
	end

	local readPlayerMobKills = function(playerOrName)
		local name = resolveProfileName(playerOrName)
			or (typeof(playerOrName) == 'Instance' and playerOrName.Name)
		if not name then
			return nil
		end
		local folder = getProfilesFolder()
		local profile = folder and folder:FindFirstChild(name)
		local mobs = profile and profile:FindFirstChild('Mobs')
		if not mobs then
			return nil
		end
		local rows = {}
		local total = 0
		for _, child in ipairs(mobs:GetChildren()) do
			if child:IsA('NumberValue') or child:IsA('IntValue') then
				local n = math.floor(tonumber(child.Value) or 0)
				total += n
				rows[#rows + 1] = { name = child.Name, count = n }
			end
		end
		table.sort(rows, function(a, b)
			if a.count == b.count then
				return a.name:lower() < b.name:lower()
			end
			return a.count > b.count
		end)
		return total, rows, name
	end

	local showPlayerMobKills = function()
		local name = getSelectedProfileName()
		local player = getSelectedPlayer()
		-- #region agent log
		pcall(function()
			local payload = game:GetService('HttpService'):JSONEncode({
				sessionId = '7e9135',
				hypothesisId = 'N2',
				location = 'showPlayerMobKills',
				message = 'mob kills clicked',
				data = {
					hasPlayer = player ~= nil,
					name = name or tostring(Options.PlayerList and Options.PlayerList.Value),
					notifyCount = getgenv().SB2LibNotifyCount,
				},
				timestamp = os.time() * 1000,
			})
			if type(appendfile) == 'function' then
				pcall(appendfile, 'PlayerTools/debug-7e9135.log', payload .. '\n')
			end
		end)
		-- #endregion
		if not name then
			Library:Notify('Select a player first', 8, true)
			return
		end
		local total, rows = readPlayerMobKills(name)
		if total == nil then
			Library:Notify(name .. ' — mob kills unavailable', 8, true)
			return
		end
		local lines = {
			('TOTAL(%d)'):format(total),
		}
		local limit = math.min(10, #rows)
		for i = 1, limit do
			local row = rows[i]
			lines[#lines + 1] = ('%s(%d)'):format(row.name, row.count)
		end
		local text = table.concat(lines, '\n')
		local copied = copyTextToClipboard(text)
		Library:Notify(name .. ' — mob kills\n' .. text, 14, true)
		if copied then
			task.defer(function()
				Library:Notify('Copied mob kills to clipboard', 4)
			end)
		else
			task.defer(function()
				Library:Notify('Clipboard unavailable', 4)
			end)
		end
	end

	local showAllProfilesMobKills = function()
		local folder = getProfilesFolder()
		if not folder then
			Library:Notify('Profiles folder unavailable', 8, true)
			return
		end
		Library:Notify('Scanning all profile kills…', 3)
		task.spawn(function()
			local rankings = {}
			for _, child in ipairs(folder:GetChildren()) do
				if child:IsA('LocalScript') or child:IsA('ModuleScript') or child:IsA('Script') then
					continue
				end
				local total = readPlayerMobKills(child.Name)
				if type(total) == 'number' then
					rankings[#rankings + 1] = { name = child.Name, total = total }
				end
			end
			if #rankings == 0 then
				Library:Notify('No profile kill data found', 8, true)
				return
			end
			table.sort(rankings, function(a, b)
				if a.total == b.total then
					return a.name:lower() < b.name:lower()
				end
				return a.total > b.total
			end)
			local top = rankings[1]
			local lines = {
				('Highest: %s — %s kills'):format(top.name, formatNumber(top.total)),
				('All profiles (%d):'):format(#rankings),
			}
			local limit = math.min(20, #rankings)
			for i = 1, limit do
				local row = rankings[i]
				lines[#lines + 1] = ('#%d %s — %s'):format(i, row.name, formatNumber(row.total))
			end
			if #rankings > limit then
				lines[#lines + 1] = ('… +%d more'):format(#rankings - limit)
			end
			local text = table.concat(lines, '\n')
			copyTextToClipboard(text)
			Library:Notify(text, 16, true)
		end)
	end

	local showPlayerStatsNotify = function()
		local name = getSelectedProfileName()
		local player = getSelectedPlayer()
		-- #region agent log
		pcall(function()
			local payload = game:GetService('HttpService'):JSONEncode({
				sessionId = '7e9135',
				hypothesisId = 'N2',
				location = 'showPlayerStatsNotify',
				message = 'view stats clicked',
				data = {
					hasPlayer = player ~= nil,
					name = name or tostring(Options.PlayerList and Options.PlayerList.Value),
					notifyCount = getgenv().SB2LibNotifyCount,
				},
				timestamp = os.time() * 1000,
			})
			if type(appendfile) == 'function' then
				pcall(appendfile, 'PlayerTools/debug-7e9135.log', payload .. '\n')
			end
		end)
		-- #endregion
		if not name then
			Library:Notify('Select a player first', 8, true)
			return
		end
		local info = readPlayerStats(name)
		if not info then
			Library:Notify(name .. ' — profile unavailable', 8, true)
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

		local label = name .. (info.online and '' or ' (offline)')
		local gearLines = {
			label .. ' — gear',
			'Right: ' .. info.right,
			'Left: ' .. info.left,
			'Armor: ' .. info.armor,
			'Accessory 1: ' .. info.accessory1,
			'Accessory 2: ' .. info.accessory2,
			'Companion: ' .. info.companion,
		}
		local statLines = {
			label .. ' — stats',
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
		Library:Notify(table.concat(gearLines, '\n'), 12, true)
		task.defer(function()
			Library:Notify(table.concat(statLines, '\n'), 10, true)
		end)
	end

	local playerListDropdown = PlayersBox:AddDropdown('PlayerList', {
		Text = 'Profiles',
		Values = {},
		AllowNull = true,
		-- Names from ReplicatedStorage.Profiles (not live Players:GetPlayers).
	})
	local function refreshPlayerListDropdown()
		local ok, err = pcall(function()
			local list = {}
			local folder = getProfilesFolder()
			if not folder then
				return
			end
			for _, child in ipairs(folder:GetChildren()) do
				if not child:IsA('LocalScript') and not child:IsA('ModuleScript') and not child:IsA('Script') then
					list[#list + 1] = child.Name
				end
			end
			table.sort(list, function(a, b)
				return a:lower() < b:lower()
			end)
			if not playerListDropdown or type(playerListDropdown.SetValues) ~= 'function' then
				return
			end
			-- Capture BEFORE SetValues — Obsidian often clears/changes Value during rebuild.
			local keep = resolveProfileName(playerListDropdown.Value)
				or resolveProfileName(selectedProfileName)
				or spectateTargetName
			playerListDropdown:SetValues(list)
			local stillHere = false
			if keep then
				for _, n in ipairs(list) do
					if n == keep then
						stillHere = true
						break
					end
				end
			end
			if stillHere then
				pcall(function()
					if playerListDropdown.Value ~= keep then
						playerListDropdown:SetValue(keep)
					elseif type(playerListDropdown.Display) == 'function' then
						playerListDropdown:Display()
					end
				end)
			else
				-- Prefer someone else — defaulting to LocalPlayer made "Join selected" always self.
				local pick = nil
				for _, n in ipairs(list) do
					if n ~= LocalPlayer.Name and n ~= LocalPlayer.DisplayName then
						pick = n
						break
					end
				end
				if not pick then
					pick = list[1]
				end
				if pick then
					pcall(function()
						playerListDropdown:SetValue(pick)
					end)
				end
			end
		end)
		if not ok then
			warn('[PlayerTools] refresh profiles failed: ', err)
		end
	end
	task.defer(refreshPlayerListDropdown)
	task.delay(1, refreshPlayerListDropdown)
	task.delay(3, refreshPlayerListDropdown)
	task.spawn(function()
		local folder = getProfilesFolder()
			or game:GetService('ReplicatedStorage'):WaitForChild('Profiles', 60)
		if not folder then
			return
		end
		Profiles = folder
		refreshPlayerListDropdown()
		folder.ChildAdded:Connect(function()
			task.defer(refreshPlayerListDropdown)
		end)
		folder.ChildRemoved:Connect(function()
			task.defer(refreshPlayerListDropdown)
		end)
	end)

	playerListDropdown:OnChanged(function(value)
		local name = resolveProfileName(value)
		selectedProfileName = name
		selectedPlayer = name and Players:FindFirstChild(name) or nil
		if isToggleOn('ViewPlayer') or isToggleOn('ViewPlayerStream') then
			spectateTargetName = name
			getgenv().SB2SpectateTargetName = name
		end

		local folder = getProfilesFolder()
		local profile = name and folder and folder:FindFirstChild(name)
		if RequiredServices
			and isToggleOn('ViewPlayersInventory')
			and RequiredServices.InventoryUI
			and RequiredServices.InventoryUI.GetInventoryData
			and profile
		then
			debug.setupvalue(RequiredServices.InventoryUI.GetInventoryData, 2, profile)
		end
	end)

	PlayersBox:AddButton('Refresh profiles', refreshPlayerListDropdown)

	-- Rebuild dropdown option rows after load / floor-hop UI recovery.
	-- Obsidian can leave Values in memory while the visible list stays empty/"---".
	local function refreshAllDropdownDisplays()
		repairObsidianTabCanvas()
		local opts = Options
		if type(opts) ~= 'table' then
			return 0
		end
		local n = 0
		for _, opt in pairs(opts) do
			if type(opt) == 'table' and opt.Type == 'Dropdown' and opt.Destroyed ~= true then
				pcall(function()
					if type(opt.BuildDropdownList) == 'function' then
						opt:BuildDropdownList()
					elseif type(opt.SetValues) == 'function' and type(opt.Values) == 'table' then
						opt:SetValues(opt.Values)
					end
					if type(opt.Display) == 'function' then
						opt:Display()
					end
				end)
				n += 1
			end
		end
		pcall(refreshPlayerListDropdown)
		return n
	end
	getgenv().SB2RefreshAllDropdownDisplays = refreshAllDropdownDisplays
	task.defer(function()
		task.wait(0.35)
		refreshAllDropdownDisplays()
		pcall(repairObsidianTabCanvas)
	end)
	task.delay(2, function()
		refreshAllDropdownDisplays()
		pcall(repairObsidianTabCanvas)
	end)
	-- Keep tab content visible: wrap Show so Container can't stay stuck hidden.
	task.defer(function()
		local tabs = Library and Library.Tabs
		if type(tabs) ~= 'table' then
			return
		end
		for _, tab in pairs(tabs) do
			if type(tab) == 'table' and type(tab.Show) == 'function' and tab._SB2ShowPatched ~= true then
				local origShow = tab.Show
				tab.Show = function(self, ...)
					local ok, a, b, c = pcall(origShow, self, ...)
					-- Manual fallback if library Show fails mid-animation.
					if type(Library.Tabs) == 'table' then
						for _, other in pairs(Library.Tabs) do
							if other ~= self
								and type(other) == 'table'
								and typeof(other.Container) == 'Instance'
								and other.Container:IsA('GuiObject')
							then
								other.Container.Visible = false
							end
						end
					end
					if typeof(self.Container) == 'Instance' and self.Container:IsA('GuiObject') then
						self.Container.Visible = true
					end
					if typeof(self.Canvas) == 'Instance' and self.Canvas:IsA('CanvasGroup') then
						self.Canvas.Visible = true
						self.Canvas.GroupTransparency = 0
					elseif typeof(self.Canvas) == 'Instance' and self.Canvas:IsA('GuiObject') then
						self.Canvas.Visible = true
					end
					Library.ActiveTab = self
					task.defer(repairObsidianTabCanvas)
					if ok then
						return a, b, c
					end
				end
				tab._SB2ShowPatched = true
				if typeof(tab.Button) == 'Instance' and tab.Button:IsA('GuiButton') then
					tab.Button.MouseButton1Click:Connect(function()
						task.defer(function()
							pcall(function()
								tab:Show()
							end)
							repairObsidianTabCanvas()
						end)
					end)
				end
			end
		end
		pcall(repairObsidianTabCanvas)
	end)

	PlayersBox:AddButton('Copy selected username', function()
		local name = getSelectedProfileName()
			or resolveProfileName(Options.PlayerList and Options.PlayerList.Value)
		if not name then
			Library:Notify('Select a player first')
			return
		end
		local copied = false
		if type(setclipboard) == 'function' then
			copied = pcall(setclipboard, name)
		end
		if not copied and type(toclipboard) == 'function' then
			copied = pcall(toclipboard, name)
		end
		if copied then
			Library:Notify('Copied: ' .. name)
		else
			Library:Notify('Clipboard unavailable')
		end
	end)

	PlayersBox:AddButton('View stats', function()
		showPlayerStatsNotify()
	end)

	PlayersBox:AddButton('Mob kills', function()
		showPlayerMobKills()
	end)
	PlayersBox:AddButton('All kills', function()
		showAllProfilesMobKills()
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

			local name = getSelectedProfileName()
				or resolveProfileName(Options.PlayerList and Options.PlayerList.Value)
			local folder = getProfilesFolder()
			local profile = name and folder and folder:FindFirstChild(name)
			if not profile then
				Library:Notify('Select a profile first')
				if Toggles.ViewPlayersInventory then
					Toggles.ViewPlayersInventory:SetValue(false)
				end
				return
			end

			debug.setupvalue(RequiredServices.InventoryUI.GetInventoryData, 2, profile)
			Library:Notify('Open your inventory in-game to view ' .. name .. "'s items")
		end)
	else
		PlayersBox:AddLabel('Inventory viewing unavailable')
		PlayersBox:AddLabel('(executor missing getgc/debug.setupvalue?)')
	end

	PlayersBox:AddToggle('ViewPlayer', { Text = 'Spectate' }):OnChanged(function(value)
		if not value then
			spectateTargetName = nil
			getgenv().SB2SpectateTargetName = nil
			fixCamera(LocalPlayer.Character or Character)
			return
		end

		if Toggles.ViewPlayerStream and isToggleOn('ViewPlayerStream') then
			Toggles.ViewPlayerStream:SetValue(false)
		end

		local name = getSelectedProfileName()
		spectateTargetName = name
		getgenv().SB2SpectateTargetName = name
		selectedProfileName = name
		selectedPlayer = name and Players:FindFirstChild(name) or nil
		if not name then
			Library:Notify('Select a player in Profiles to spectate', 8, true)
			Toggles.ViewPlayer:SetValue(false)
			return
		end
		Library:Notify('Spectating ' .. name)

		-- Never block the toggle OnChanged thread (SetValue / UI deadlocks).
		task.spawn(function()
			while isToggleOn('ViewPlayer') do
				name = spectateTargetName or getSelectedProfileName()
				if not name then
					fixCamera(LocalPlayer.Character or Character)
					task.wait(0.1)
					continue
				end
				local char, plr = resolveCharacterByName(name)
				selectedProfileName = name
				selectedPlayer = plr
				local cam = getLiveCamera()
				if char and not isDead(char) then
					local subject = cameraSubjectFrom(char)
					if cam and subject and cam.CameraSubject ~= subject then
						cam.CameraSubject = subject
					elseif cam and subject then
						cam.CameraSubject = subject
					end
				else
					fixCamera(LocalPlayer.Character or Character)
				end
				task.wait(0.1)
			end
			if not isToggleOn('ViewPlayerStream') then
				fixCamera(LocalPlayer.Character or Character)
			end
		end)
	end)

	-- Stream spectate: briefly sit ≥600 studs above them so their chunk loads, return home,
	-- keep CameraSubject + ReplicationFocus on them (body stays at your spot).
	local STREAM_SPECTATE_Y = 600
	local lastStreamSpectatePullAt = 0
	PlayersBox:AddToggle('ViewPlayerStream', {
		Text = 'Spectate (stream)',
		Tooltip = 'Teleport ≥600 studs above target to stream them in, return to your position, keep viewing them',
	}):OnChanged(function(value)
		if not value then
			if not isToggleOn('ViewPlayer') then
				spectateTargetName = nil
				getgenv().SB2SpectateTargetName = nil
			end
			lockReplicationFocus(LocalPlayer.Character or Character)
			fixCamera(LocalPlayer.Character or Character)
			return
		end

		if Toggles.ViewPlayer and isToggleOn('ViewPlayer') then
			Toggles.ViewPlayer:SetValue(false)
		end

		local name = getSelectedProfileName()
		spectateTargetName = name
		getgenv().SB2SpectateTargetName = name
		selectedProfileName = name
		selectedPlayer = name and Players:FindFirstChild(name) or nil
		if not name then
			Library:Notify('Select a player in Profiles to stream-spectate', 8, true)
			Toggles.ViewPlayerStream:SetValue(false)
			return
		end

		task.spawn(function()
			local myChar = getMyCharacterModel() or LocalPlayer.Character
			local myHrp = myChar and myChar:FindFirstChild('HumanoidRootPart')
			local tChar = select(1, resolveCharacterByName(name))
			local tHrp = tChar and tChar:FindFirstChild('HumanoidRootPart')
			if not myHrp or not tHrp then
				Library:Notify('Need your HRP and their character to stream-spectate')
				Toggles.ViewPlayerStream:SetValue(false)
				return
			end

			local homeCf = myHrp.CFrame
			local streamCf = CFrame.new(tHrp.Position + Vector3.new(0, STREAM_SPECTATE_Y, 0))
			pcall(function()
				myHrp.AssemblyLinearVelocity = Vector3.zero
				myHrp.AssemblyAngularVelocity = Vector3.zero
				myHrp.CFrame = streamCf
			end)
			pcall(function()
				LocalPlayer.ReplicationFocus = tHrp
			end)
			pcall(function()
				LocalPlayer:RequestStreamAroundAsync(tHrp.Position, 40)
			end)
			task.wait(0.4)
			name = spectateTargetName or name
			tChar = select(1, resolveCharacterByName(name))
			tHrp = tChar and tChar:FindFirstChild('HumanoidRootPart') or tHrp
			if myHrp.Parent then
				pcall(function()
					myHrp.AssemblyLinearVelocity = Vector3.zero
					myHrp.AssemblyAngularVelocity = Vector3.zero
					myHrp.CFrame = homeCf
				end)
			end
			if tHrp then
				pcall(function()
					LocalPlayer.ReplicationFocus = tHrp
					LocalPlayer:RequestStreamAroundAsync(tHrp.Position, 40)
				end)
			end
			Library:Notify('Stream spectate on — viewing ' .. tostring(name))

			while isToggleOn('ViewPlayerStream') do
				name = spectateTargetName or getSelectedProfileName()
				if not name then
					fixCamera(LocalPlayer.Character or Character)
					task.wait(0.1)
					continue
				end
				local char, plr = resolveCharacterByName(name)
				selectedProfileName = name
				selectedPlayer = plr
				local cam = getLiveCamera()
				if char and not isDead(char) then
					local subject = cameraSubjectFrom(char)
					local thrp = char:FindFirstChild('HumanoidRootPart')
					if cam and subject then
						cam.CameraSubject = subject
					end
					if thrp then
						pcall(function()
							if LocalPlayer.ReplicationFocus ~= thrp then
								LocalPlayer.ReplicationFocus = thrp
							end
						end)
						local now = os.clock()
						if (now - lastStreamSpectatePullAt) >= 2.5 then
							lastStreamSpectatePullAt = now
							task.defer(function()
								pcall(function()
									if thrp.Parent then
										LocalPlayer:RequestStreamAroundAsync(thrp.Position, 40)
									end
								end)
							end)
						end
					end
				else
					fixCamera(LocalPlayer.Character or Character)
				end
				task.wait(0.1)
			end

			if not isToggleOn('ViewPlayer') then
				lockReplicationFocus(LocalPlayer.Character or Character)
				fixCamera(LocalPlayer.Character or Character)
			end
		end)
	end)

	-- Join any Roblox username's SB2 server (right column, beside Players).
	-- GetPlayerPlaceInstanceAsync is server-only — look up via Presence HTTP instead.
	do
		local JoinBox = PlayersTab:AddRightGroupbox('Join player')
		assert(JoinBox, 'Join player groupbox nil')
		local HttpService = game:GetService('HttpService')
		local TeleportService = game:GetService('TeleportService')

		JoinBox:AddInput('JoinPlayerName', {
			Text = 'Username',
			Default = '',
			Placeholder = 'Exact Roblox username',
			Finished = false,
			ClearTextOnFocus = false,
			AllowEmpty = true,
			Tooltip = 'Type a username (or user id), then press Join. Join selected uses the Profiles dropdown on the left.',
		})

		local function httpRequest(opts)
			local req = (syn and syn.request)
				or (http and http.request)
				or http_request
				or request
			if type(req) ~= 'function' then
				return nil, 'no http request function'
			end
			local ok, res = pcall(req, opts)
			if not ok then
				return nil, tostring(res)
			end
			return res
		end

		local function trimName(raw)
			return tostring(raw or ''):gsub('^%s+', ''):gsub('%s+$', '')
		end

		local function resolveJoinUserId(raw)
			raw = trimName(raw)
			if raw == '' then
				return nil, 'Enter a username'
			end
			local asNum = tonumber(raw)
			if asNum and asNum == math.floor(asNum) and asNum > 0 then
				return asNum, raw
			end
			local ok, userId = pcall(function()
				return Players:GetUserIdFromNameAsync(raw)
			end)
			if not ok or type(userId) ~= 'number' then
				return nil, 'Unknown user: ' .. raw
			end
			return userId, raw
		end

		-- Profiles can be roblox_user_<id> while typed name is the real username (same person).
		local function isLocalIdentity(nameOrId)
			if nameOrId == nil then
				return false
			end
			if type(nameOrId) == 'number' then
				return nameOrId == LocalPlayer.UserId
			end
			local name = trimName(nameOrId)
			if name == '' then
				return false
			end
			if name == LocalPlayer.Name or name == LocalPlayer.DisplayName then
				return true
			end
			if name:lower() == ('roblox_user_' .. tostring(LocalPlayer.UserId)):lower() then
				return true
			end
			local uid = select(1, resolveJoinUserId(name))
			return type(uid) == 'number' and uid == LocalPlayer.UserId
		end

		local function getTypedJoinName()
			local raw = trimName(Options.JoinPlayerName and Options.JoinPlayerName.Value)
			if raw == '' then
				return nil
			end
			return raw
		end

		-- Profiles dropdown only (not spectate lock).
		local function getJoinProfileName()
			local fromOpt = Options.PlayerList and Options.PlayerList.Value
			local name = resolveProfileName(fromOpt)
			if name and name ~= '' then
				return name
			end
			return resolveProfileName(selectedProfileName)
		end

		local function lookupPlaceViaPresence(userId)
			local body = HttpService:JSONEncode({ userIds = { userId } })
			local urls = {
				'https://presence.roblox.com/v1/presence/users',
				'https://presence.roproxy.com/v1/presence/users',
			}
			local lastErr = nil
			for _, url in ipairs(urls) do
				local res, err = httpRequest({
					Url = url,
					Method = 'POST',
					Headers = {
						['Content-Type'] = 'application/json',
						['Accept'] = 'application/json',
					},
					Body = body,
				})
				if not res then
					lastErr = err
					continue
				end
				local status = tonumber(res.StatusCode) or tonumber(res.Status) or 0
				local rawBody = res.Body or res.body or ''
				if status < 200 or status >= 300 or type(rawBody) ~= 'string' or rawBody == '' then
					lastErr = ('HTTP %s'):format(tostring(status))
					continue
				end
				local okDecode, data = pcall(function()
					return HttpService:JSONDecode(rawBody)
				end)
				if not okDecode or type(data) ~= 'table' then
					lastErr = 'bad presence JSON'
					continue
				end
				local list = data.userPresences or data.UserPresences
				local row = type(list) == 'table' and list[1] or nil
				if type(row) ~= 'table' then
					lastErr = 'no presence row'
					continue
				end
				local presenceType = tonumber(row.userPresenceType or row.UserPresenceType) or 0
				local placeId = tonumber(row.placeId or row.PlaceId or row.rootPlaceId or row.RootPlaceId)
				local jobId = row.gameId or row.GameId or row.instanceId or row.InstanceId
				if type(jobId) == 'string' and jobId == '' then
					jobId = nil
				end
				if presenceType == 0 then
					return nil, nil, 'offline'
				end
				if presenceType == 1 then
					return nil, nil, 'online on website (not in a game)'
				end
				if type(placeId) ~= 'number' or placeId <= 0 or type(jobId) ~= 'string' then
					return nil, nil, 'in a game but place/job hidden (join privacy / not friends)'
				end
				return placeId, jobId, nil
			end
			return nil, nil, lastErr or 'presence lookup failed'
		end

		local function joinUserId(userId, displayName)
			if isLocalIdentity(userId) then
				Library:Notify("That's you — pick another profile on the left, or type someone else's username", 8, true)
				return
			end
			for _, plr in ipairs(Players:GetPlayers()) do
				if plr.UserId == userId then
					Library:Notify(tostring(displayName) .. ' is already in this server')
					return
				end
			end

			Library:Notify('Looking up ' .. tostring(displayName) .. '…')
			local placeId, jobId, lookErr = lookupPlaceViaPresence(userId)
			if not placeId or not jobId then
				Library:Notify(
					('Cannot join %s — %s'):format(tostring(displayName), tostring(lookErr or 'unknown')),
					10,
					true
				)
				return
			end
			if placeId == game.PlaceId and jobId == game.JobId then
				Library:Notify(tostring(displayName) .. ' is already in this server')
				return
			end

			if type(getgenv().SB2PlayerToolsArmTeleport) == 'function' then
				pcall(getgenv().SB2PlayerToolsArmTeleport)
			end
			Library:Notify(
				('Joining %s — place %s'):format(tostring(displayName), tostring(placeId)),
				6
			)
			local tpOk, tpErr = pcall(function()
				TeleportService:TeleportToPlaceInstance(placeId, jobId, LocalPlayer)
			end)
			if not tpOk then
				Library:Notify('Teleport failed: ' .. tostring(tpErr), 8, true)
			end
		end

		local function startJoin(rawName)
			local userId, label = resolveJoinUserId(rawName)
			if not userId then
				Library:Notify(tostring(label) or 'Enter a username')
				return
			end
			task.spawn(joinUserId, userId, label)
		end

		-- Join = typed username first; if empty, use Profiles (skipping yourself).
		JoinBox:AddButton('Join', function()
			local typed = getTypedJoinName()
			if typed and not isLocalIdentity(typed) then
				startJoin(typed)
				return
			end
			local profile = getJoinProfileName()
			if profile and not isLocalIdentity(profile) then
				if Options.JoinPlayerName and type(Options.JoinPlayerName.SetValue) == 'function' then
					pcall(function()
						Options.JoinPlayerName:SetValue(profile)
					end)
				end
				startJoin(profile)
				return
			end
			if typed and isLocalIdentity(typed) then
				Library:Notify("Username is you — type someone else's name, or pick them in Profiles", 8, true)
				return
			end
			Library:Notify('Type a username above, or select someone else in Profiles', 8, true)
		end)

		JoinBox:AddButton('Join selected profile', function()
			local profile = getJoinProfileName()
			local typed = getTypedJoinName()
			local target = nil
			if profile and not isLocalIdentity(profile) then
				target = profile
			elseif typed and not isLocalIdentity(typed) then
				-- Profiles still on you, but they typed someone else — use the typed name.
				target = typed
				Library:Notify('Profiles was you — joining typed username: ' .. target, 5)
			else
				Library:Notify(
					'Select someone else in Profiles (left), or type their username and press Join',
					8,
					true
				)
				return
			end
			if Options.JoinPlayerName and type(Options.JoinPlayerName.SetValue) == 'function' then
				pcall(function()
					Options.JoinPlayerName:SetValue(target)
				end)
			end
			startJoin(target)
		end)
	end

	-- Walkspeed (local character). Default comes from the same place View stats reads
	-- (character Walkspeed attribute / Humanoid), not a hardcoded 16.
	do
		local FALLBACK_WALKSPEED = 16
		local WalkBox = PlayersTab:AddLeftGroupbox('Walkspeed')
		assert(WalkBox, 'Walkspeed groupbox nil')

		local function myCharacter()
			local char = LocalPlayer.Character
			if not char then
				local folder = workspace:FindFirstChild('Characters')
				char = folder and folder:FindFirstChild(LocalPlayer.Name)
			end
			return char
		end

		local function myHumanoid()
			local char = myCharacter()
			return char and char:FindFirstChildOfClass('Humanoid')
		end

		-- Same source as readPlayerStats / View stats (attribute first = game default).
		local function getDefaultWalkSpeed()
			local char = myCharacter()
			if char then
				local attr = char:GetAttribute('Walkspeed') or char:GetAttribute('WalkSpeed')
				if type(attr) == 'number' and attr > 0 then
					return math.clamp(attr, 1, 500)
				end
			end
			local info = readPlayerStats(LocalPlayer.Name)
			if info and type(info.walkSpeed) == 'number' and info.walkSpeed > 0 then
				return math.clamp(info.walkSpeed, 1, 500)
			end
			local hum = myHumanoid()
			if hum and type(hum.WalkSpeed) == 'number' and hum.WalkSpeed > 0 and not getgenv().SB2WalkSpeedWant then
				return math.clamp(hum.WalkSpeed, 1, 500)
			end
			return FALLBACK_WALKSPEED
		end

		local function applyWalkSpeed(spd, pin)
			spd = math.clamp(tonumber(spd) or getDefaultWalkSpeed(), 1, 500)
			local hum = myHumanoid()
			if hum then
				pcall(function()
					hum.WalkSpeed = spd
				end)
			end
			if pin then
				getgenv().SB2WalkSpeedWant = spd
			else
				getgenv().SB2WalkSpeedWant = nil
			end
		end

		local initialDefault = getDefaultWalkSpeed()

		WalkBox:AddSlider('WalkSpeed', {
			Text = 'Walkspeed',
			Default = initialDefault,
			Min = 1,
			Max = 500,
			Rounding = 0,
			Tooltip = 'Your character walkspeed (1–500). Default uses the same Walkspeed value as View stats.',
		}):OnChanged(function(value)
			local base = getDefaultWalkSpeed()
			local spd = math.clamp(tonumber(value) or base, 1, 500)
			applyWalkSpeed(spd, math.abs(spd - base) > 0.05)
		end)

		WalkBox:AddButton('Default walkspeed', function()
			local base = getDefaultWalkSpeed()
			if Options.WalkSpeed and type(Options.WalkSpeed.SetValue) == 'function' then
				pcall(function()
					Options.WalkSpeed:SetValue(base)
				end)
			end
			applyWalkSpeed(base, false)
			Library:Notify('Walkspeed → ' .. tostring(base) .. ' (default)')
		end)

		getgenv().SB2WalkSpeedWant = nil
		local walkGen = (tonumber(getgenv().SB2WalkSpeedGen) or 0) + 1
		getgenv().SB2WalkSpeedGen = walkGen
		task.spawn(function()
			while getgenv().SB2WalkSpeedGen == walkGen do
				if getgenv().SB2PlayerToolsManualUnload == true then
					break
				end
				local want = tonumber(getgenv().SB2WalkSpeedWant)
				if want then
					local hum = myHumanoid()
					if hum and math.abs((hum.WalkSpeed or 0) - want) > 0.05 then
						pcall(function()
							hum.WalkSpeed = want
						end)
					end
				end
				task.wait(0.12)
			end
		end)

		pcall(function()
			safeConnect(LocalPlayer.CharacterAdded, function()
				task.defer(function()
					local want = tonumber(getgenv().SB2WalkSpeedWant)
					if want then
						applyWalkSpeed(want, true)
					end
				end)
			end)
		end)
	end

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
	-- One-shot after load (no Heartbeat / no periodic strip loop).
	getgenv().SB2DefaultCursorLock = true
	restoreDefaultCursor()
	stripObsidianCursor()
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
		if not inGameplayWorld() then
			return false
		end
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
		getgenv().SB2AutoAttackOn = false
		getgenv().SB2CombatAnchorOn = false
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
			if Toggles.CombatAnchor and Toggles.CombatAnchor.Value then
				Toggles.CombatAnchor:SetValue(false)
			end
		end)
		pcall(function()
			if Toggles.DiveFarm and Toggles.DiveFarm.Value then
				Toggles.DiveFarm:SetValue(false)
			end
		end)
		if type(getgenv().SB2StopCombatRuntime) == 'function' then
			pcall(getgenv().SB2StopCombatRuntime, true)
		else
			local conn = getgenv().SB2AutoAttackConn
			if conn then
				pcall(function()
					conn:Disconnect()
				end)
				getgenv().SB2AutoAttackConn = nil
			end
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

	safeConnect(LocalPlayer.CharacterAdded, function(newCharacter)
		Character = newCharacter
		cachedMyChar, cachedMyCharAt = nil, 0
		lastCharacterAddedAt = os.clock()
		voidHuskSince = nil
		task.spawn(function()
			-- If Event dive is off, never spawn into leftover dive noclip.
			if getgenv().SB2DiveFarmOn ~= true then
				local diveToggle = Toggles and Toggles.DiveFarm
				local diveOn = type(diveToggle) == 'table' and diveToggle.Value == true
				if not diveOn then
					if type(getgenv().SB2DiveForceClip) == 'function' then
						pcall(getgenv().SB2DiveForceClip)
					elseif type(getgenv().SB2DiveSetNoclip) == 'function' then
						pcall(getgenv().SB2DiveSetNoclip, false)
					end
					task.defer(function()
						pcall(function()
							for _, p in ipairs(newCharacter:GetDescendants()) do
								if p:IsA('BasePart') then
									if p.CollisionGroup == 'SB2DiveNoclip' then
										p.CollisionGroup = 'Players'
									end
									if p.Name == 'HumanoidRootPart'
										or p.Name == 'UpperTorso'
										or p.Name == 'LowerTorso'
										or p.Name == 'Torso'
										or p.Name == 'Head'
									then
										p.CanCollide = true
									end
								end
							end
						end)
					end)
				end
			end
			local hum = newCharacter:WaitForChild('Humanoid', 15)
			if not hum then
				return
			end
			local hrp = newCharacter:WaitForChild('HumanoidRootPart', 10)
			if hrp then
				-- Wait until past title / PLAY screen before touching camera or streaming.
				for _ = 1, 40 do
					if inGameplayWorld() then
						break
					end
					task.wait(0.25)
				end
				if not inGameplayWorld() then
					return
				end
				lockReplicationFocus(newCharacter)
				requestStreamAround(newCharacter, true)
				holdCombatAnchor(4)
			end
			for _ = 1, 30 do
				if isToggleOn('ViewPlayer') or isToggleOn('ViewPlayerStream') then
					return
				end
				if not inGameplayWorld() then
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

	-- Camera recovery Heartbeat removed (was polling void cam / map-gone every 2s).
	do
		local prev = getgenv().SB2CameraRecoveryConn
		if prev then
			pcall(function()
				prev:Disconnect()
			end)
			getgenv().SB2CameraRecoveryConn = nil
		end
	end

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

		-- Combat Anchor only — soft lock lives on the Anchor Heartbeat (throttled).
		-- Do NOT soft-lock from the 20Hz camera step (that was PivotTo / scan spam → low FPS).
		local function pinHighAir(char)
			if not isToggleOn('CombatAnchor') then
				return
			end
			if isToggleOn('DiveFarm') or getgenv().SB2DiveFarmOn == true then
				local hrpDive = char and char:FindFirstChild('HumanoidRootPart')
				if hrpDive then
					pcall(function()
						hrpDive.Anchored = false
					end)
				end
				return
			end
			local hrp = char and char:FindFirstChild('HumanoidRootPart')
			if not hrp then
				return
			end
			-- Cheap: never re-anchor from camera. Soft-lock / ghost is elsewhere.
			if hrp.Anchored then
				hrp.Anchored = false
			end
		end

		local function hardenCamera()
			if not getgenv()[CONFIG.GenvKey] then
				return
			end
			if isToggleOn('ViewPlayer') or isToggleOn('ViewPlayerStream') then
				return
			end
			-- Leave title / PLAY-menu cinematic cams alone (forcing Custom = black screen).
			if not inGameplayWorld() then
				return
			end
			local cam = getLiveCamera()
			local char = getMyCharacterModel() or LocalPlayer.Character
			lockReplicationFocus(char)
			pinHighAir(char)
			if cameraLooksBroken(cam, char) then
				fixCamera(char)
				pinHighAir(char)
			end

			-- mapLooksGone / GetPartBoundsInRadius / RequestStreamAround are expensive —
			-- throttle hard (was 1.5s hitch cadence with overlap queries).
			local now = os.clock()
			if (now - lastHeavyCamCheckAt) < 4 then
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
			-- Skip worldLooksUnloaded / GetPartBoundsInRadius while farming — ~13ms+ hitch.
			if getgenv().SB2DiveFarmOn or (type(isToggleOn) == 'function' and isToggleOn('DiveFarm')) then
				return
			end
			-- Don't pull stream back to yourself while stream-spectating someone far away.
			if isToggleOn('ViewPlayerStream') then
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
		-- 4Hz is enough; 20Hz hardenCamera was a major FPS sink (~15fps).
		local lastHardenAt = 0
		local function hardenCameraStepped()
			local now = os.clock()
			if (now - lastHardenAt) < 0.25 then
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
		-- Server rejects aura damage past ~melee/skill reach on elites/bosses even when
		-- the instance is streamed. Prefer real/attack CF within these XZ radii.
		local AURA_DAMAGE_RANGE = 260
		local BOSS_DAMAGE_RANGE = 420
		local AUTO_ATTACK_INTERVAL = 0.08
		local AUTO_ATTACK_DELAY = 0.04
		local HIT_LIVES_ATTACK_INTERVAL = 0.05
		local HIT_LIVES_ATTACK_DELAY = 0.05
		local HIT_LIVES_MIN_DELAY = 0.05
		-- Killaura: hit many streamed mobs per tick (14 left most of a pack untouched).
		local MAX_ATTACKS_PER_TICK = 48
		-- Dump extra swings into bosses/elites per tick (1/tick felt like "not hitting").
		local BOSS_HITS_PER_TICK = 10
		local BOSS_ATTACK_DELAY = 0.02
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
			-- DISABLED: hookmetamethod(__namecall) was silently zeroing all combat
			-- damage. Runtime proof (session 7e9135): with sniffer on → 1000+ client
			-- "hits" and Warlord HP delta 0; after restoring old namecall → 517500
			-- HP in ~1s with the same DealDamage/UseSkill path.
			-- rpcKey already comes from refreshRpcKey / prior sniff; do not re-hook.
			if getgenv()._SB2CombatSnifferDisabled == true then
				return
			end
			getgenv()._SB2CombatSnifferDisabled = true
			-- If a prior load left the hook installed, unwrap it now.
			if type(getgenv().SB2CombatSnifferOld) == 'function'
				and getgenv().SB2CombatSnifferInstalled
				and type(getrawmetatable) == 'function'
			then
				pcall(function()
					local mt = getrawmetatable(game)
					setreadonly(mt, false)
					mt.__namecall = getgenv().SB2CombatSnifferOld
					setreadonly(mt, true)
					getgenv().SB2CombatSnifferDispatch = nil
					getgenv().SB2CombatSnifferInstalled = false
				end)
			end
			-- #region agent log
			if type(getgenv().SB2DbgFling) == 'function' then
				pcall(getgenv().SB2DbgFling, 'G', 'installCombatSniffer', 'sniffer_disabled', {
					hadOld = type(getgenv().SB2CombatSnifferOld) == 'function',
				})
			end
			-- #endregion
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
				or mob.PrimaryPart
			if root and root:IsA('BasePart') then
				return root
			end
			for _, d in ipairs(mob:GetChildren()) do
				if d:IsA('BasePart') then
					return d
				end
			end
			return nil
		end

		local isDeadMob = function(mob)
			if not mob or not mob.Parent then
				return true
			end
			-- Corpses stay in workspace.Mobs briefly with Died=true; Health can
			-- still look valid, so killaura wasted the whole tick on them.
			if mob:GetAttribute('Died') == true then
				return true
			end
			local entity = mob:FindFirstChild('Entity')
			if not entity then
				return true
			end
			if entity:GetAttribute('Died') == true then
				return true
			end
			local health = entity:FindFirstChild('Health')
			if not health then
				return true
			end
			local okHealth, healthValue = pcall(function()
				return health.Value
			end)
			if not okHealth or type(healthValue) ~= 'number' or healthValue <= 0 then
				return true
			end
			local hitLives = entity:FindFirstChild('HitLives')
			if hitLives then
				local okHits, hitsValue = pcall(function()
					return hitLives.Value
				end)
				if okHits and type(hitsValue) == 'number' and hitsValue <= 0 then
					return true
				end
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
			local anytimeInst = entry:FindFirstChild('Anytime')
			-- Native Anytime (Shadow Step / CE) vs SB2-injected folder for menu casting.
			local anytime = anytimeInst ~= nil
				and anytimeInst:GetAttribute('SB2ForcedAnytime') ~= true
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

		local SKILL_EFFECT_MODULES = {
			['Cursed Three Fold Slash'] = 'CursedThreeFoldSlash',
			['Cursed Enhancement'] = 'CursedEnhancement',
		}

		-- Cursed skills self-damage runs through client DoEffect (local UseSkill handler
		-- or server Graphics/SkillEffects DoEffect). fireUseSkill already skips local
		-- DoEffect for CTF; block replicated DoEffect + curse modules for CE (not HP hacks).
		local CURSE_SELF_DAMAGE_SKILLS = {
			['Cursed Enhancement'] = true,
			['Cursed Three Fold Slash'] = true,
		}

		local function normalizeCurseSkillArg(arg)
			if type(arg) == 'string' then
				return arg
			end
			if type(arg) == 'table' then
				return arg.Name or arg.Skill or arg.skill or arg[1]
			end
			return nil
		end

		local function isCurseSelfDamageSkill(skillName)
			local name = normalizeCurseSkillArg(skillName) or skillName
			if type(name) ~= 'string' or name == '' then
				return false
			end
			if CURSE_SELF_DAMAGE_SKILLS[name] then
				return true
			end
			local key = string.lower(name):gsub('%s+', '')
			return key == 'cursedenhancement' or key == 'cursedthreefoldslash'
		end

		local function shouldBlockCurseEffect(...)
			for i = 1, select('#', ...) do
				if isCurseSelfDamageSkill(select(i, ...)) then
					return true
				end
			end
			return false
		end

		local function wrapServiceDoEffect(service, tag)
			if not service or type(service.DoEffect) ~= 'function' then
				return false
			end
			local key = 'SB2CurseDoEffectOld_' .. tostring(tag or 'x')
			if getgenv()[key] then
				return true
			end
			local old = service.DoEffect
			getgenv()[key] = old
			local wrapped
			wrapped = function(...)
				if shouldBlockCurseEffect(...) then
					return nil
				end
				return old(...)
			end
			if type(newcclosure) == 'function' then
				wrapped = newcclosure(wrapped)
			end
			service.DoEffect = wrapped
			return true
		end

		local function wrapServiceServerEvent(service, tag, blockEvents)
			if not service or type(service.ServerEvent) ~= 'function' then
				return false
			end
			blockEvents = blockEvents or { DoEffect = true }
			local key = 'SB2CurseServerEventOld_' .. tostring(tag or 'x')
			if getgenv()[key] then
				return true
			end
			local old = service.ServerEvent
			getgenv()[key] = old
			local wrapped
			wrapped = function(eventName, ...)
				if blockEvents[eventName] and shouldBlockCurseEffect(...) then
					return nil
				end
				return old(eventName, ...)
			end
			if type(newcclosure) == 'function' then
				wrapped = newcclosure(wrapped)
			end
			service.ServerEvent = wrapped
			return true
		end

		local function wrapSkillEffectModule(modScript, modName)
			if not modScript or not modScript:IsA('ModuleScript') then
				return false
			end
			local req = require or getrenv().require
			local okReq, mod = pcall(req, modScript)
			if not okReq or type(mod) ~= 'table' then
				return false
			end
			local hooked = false
			for _, fnName in ipairs({ 'DoEffect', 'Client', 'Effect', 'Activate', 'Run', 'Local' }) do
				local fn = mod[fnName]
				if type(fn) == 'function' then
					local key = 'SB2CurseModOld_' .. tostring(modName) .. '_' .. fnName
					if not getgenv()[key] then
						getgenv()[key] = fn
						local stub = function(...)
							return nil
						end
						if type(newcclosure) == 'function' then
							stub = newcclosure(stub)
						end
						mod[fnName] = stub
						hooked = true
					end
				end
			end
			return hooked
		end

		local function installCurseSelfDamageBlock()
			local svc = RequiredServices or getgenv().SB2RequiredServices
			if not svc then
				return false
			end
			local ok = false
			if svc.Graphics then
				ok = wrapServiceDoEffect(svc.Graphics, 'Gfx') or ok
				ok = wrapServiceServerEvent(svc.Graphics, 'Gfx', { DoEffect = true }) or ok
			end
			if svc.SkillEffects then
				ok = wrapServiceDoEffect(svc.SkillEffects, 'SE') or ok
				ok = wrapServiceServerEvent(svc.SkillEffects, 'SE', { DoEffect = true }) or ok
			end
			pcall(function()
				local cc = game:GetService('ReplicatedStorage'):FindFirstChild('CardinalClient')
				local seFolder = cc and cc.MainModule and cc.MainModule.Services
					and cc.MainModule.Services:FindFirstChild('SkillEffects')
				if seFolder then
					for skillName, modName in pairs(SKILL_EFFECT_MODULES) do
						if CURSE_SELF_DAMAGE_SKILLS[skillName] then
							local ms = seFolder:FindFirstChild(modName)
							if ms then
								ok = wrapSkillEffectModule(ms, modName) or ok
							end
						end
					end
				end
			end)
			if ok then
				getgenv().SB2CurseSelfDamageBlock = true
			end
			return ok
		end
		getgenv().SB2InstallCurseSelfDamageBlock = installCurseSelfDamageBlock

		if not installCurseSelfDamageBlock() then
			task.spawn(function()
				for _ = 1, 120 do
					if installCurseSelfDamageBlock() then
						break
					end
					task.wait(0.25)
				end
			end)
		end

		local function skillEffectModuleName(skillName)
			if SKILL_EFFECT_MODULES[skillName] then
				return SKILL_EFFECT_MODULES[skillName]
			end
			return tostring(skillName or ''):gsub('%s+', '')
		end

		local function parseSkillHitRangeFromSource(source)
			if type(source) ~= 'string' then
				return nil
			end
			local maxR = 0
			for radius in string.gmatch(source, 'DamageArea%([^)]-%s(%d+%.?%d*)%s*[,)]') do
				maxR = math.max(maxR, tonumber(radius) or 0)
			end
			return maxR > 0 and maxR or nil
		end

		local function getSkillHitRange(skillName)
			if not skillName or skillName == '' then
				return nil
			end
			getgenv().SB2SkillHitRange = getgenv().SB2SkillHitRange or {}
			if getgenv().SB2SkillHitRange[skillName] then
				return getgenv().SB2SkillHitRange[skillName]
			end
			local modName = skillEffectModuleName(skillName)
			pcall(function()
				local cc = game:GetService('ReplicatedStorage'):FindFirstChild('CardinalClient')
				local services = cc and cc:FindFirstChild('MainModule') and cc.MainModule:FindFirstChild('Services')
				local se = services and services:FindFirstChild('SkillEffects')
				local mod = se and se:FindFirstChild(modName)
				if not mod or not mod:IsA('ModuleScript') then
					return
				end
				local src = nil
				if type(decompile) == 'function' then
					local ok, out = pcall(decompile, mod)
					if ok and type(out) == 'string' then
						src = out
					end
				end
				if src then
					local r = parseSkillHitRangeFromSource(src)
					if r then
						getgenv().SB2SkillHitRange[skillName] = r
					end
				end
			end)
			return getgenv().SB2SkillHitRange[skillName]
		end
		getgenv().SB2GetSkillHitRange = getSkillHitRange

		-- Do NOT inject Anytime folders onto weapon skills — leave Database defaults.
		-- Strip any SB2-forced Anytime folders left from older builds.
		local function stripForcedAnytimeFolders()
			local skillsDb = getSkillDatabase()
			if not skillsDb then
				return 0
			end
			local n = 0
			for _, entry in ipairs(skillsDb:GetChildren()) do
				local anytime = entry:FindFirstChild('Anytime')
				if anytime and anytime:GetAttribute('SB2ForcedAnytime') == true then
					pcall(function()
						anytime:Destroy()
					end)
					n += 1
				end
			end
			return n
		end
		local ensureSkillAnytimeFolder = function(_skillNameOrEntry)
			-- No-op: casting uses the game's native Anytime rules only.
			return nil
		end
		local ensureClassSkillsAnytime = function()
			return stripForcedAnytimeFolders()
		end
		task.defer(function()
			local n = stripForcedAnytimeFolders()
			-- #region agent log
			pcall(function()
				local payload = game:GetService('HttpService'):JSONEncode({
					sessionId = '7e9135',
					hypothesisId = 'ANY1',
					location = 'stripForcedAnytimeFolders',
					message = 'stripped SB2 forced Anytime',
					data = { removed = n },
					timestamp = os.time() * 1000,
				})
				if type(appendfile) == 'function' then
					pcall(appendfile, 'PlayerTools/debug-7e9135.log', payload .. '\n')
				end
			end)
			-- #endregion
		end)
		getgenv().SB2EnsureSkillAnytime = ensureClassSkillsAnytime
		getgenv().SB2EnsureSkillAnytimeOne = ensureSkillAnytimeFolder
		getgenv().SB2StripForcedAnytime = stripForcedAnytimeFolders

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
		-- Dash / pistol names do not open a DealDamage tag window. CTF / smash do.
		-- Alts saved on Leaping Slash look like they are hitting and deal 0.
		local POOR_AURA_TAG_SKILLS = {
			['Leaping Slash'] = true,
			['Summon Pistol'] = true,
			['Pistol Summon'] = true,
		}
		local AURA_SKILL_PRIORITY = {
			'Cursed Three Fold Slash',
			'Downward Smash',
			'Sweeping Strike',
			'Everfrost Strike',
			'Water Blast',
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
				-- Class weapon skills stay in this list even after we inject Anytime
				-- (menu cast). Support list is anytime + no Class.
				if not info.class then
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

		local function isPoorAuraTagSkill(skillName)
			if type(skillName) ~= 'string'
				or skillName == ''
				or skillName == '(none)'
				or skillName == '(none for held weapon)'
			then
				return true
			end
			if FORCE_ATTACK_SKILLS[skillName] or POOR_AURA_TAG_SKILLS[skillName] then
				return true
			end
			local lower = string.lower(skillName)
			return string.find(lower, 'leap', 1, true) ~= nil
				or string.find(lower, 'dash', 1, true) ~= nil
				or string.find(lower, 'lunge', 1, true) ~= nil
		end

		local function pickBestAuraWeaponSkill()
			local values = getAvailableSkills()
			local have = {}
			for _, name in ipairs(values) do
				have[name] = true
			end
			for _, name in ipairs(AURA_SKILL_PRIORITY) do
				if have[name] then
					return name
				end
			end
			for _, name in ipairs(values) do
				if name ~= '(none)'
					and name ~= '(none for held weapon)'
					and not isPoorAuraTagSkill(name)
				then
					return name
				end
			end
			-- Only Leaping Slash / pistol unlocked — nil so killaura uses the weapon.
			return nil
		end

		local function resolveAuraWeaponSkill(skillName)
			if not isPoorAuraTagSkill(skillName) then
				return skillName
			end
			-- Dash/pistol: use smash/CTF if they own it. Otherwise nil = basic weapon hits.
			return pickBestAuraWeaponSkill()
		end
		getgenv().SB2PickBestAuraWeaponSkill = pickBestAuraWeaponSkill

		-- Anytime / support buffs (Cursed Enhancement, Realm Judgement, etc.).
		local SUPPORT_FORCE_INCLUDE = {
			['Cursed Enhancement'] = true,
			['Realm Judgement'] = true,
		}
		local getAvailableSupportSkills = function()
			-- Multi-select: empty selection = none (no '(none)' row).
			local names = {}
			local seen = {}
			local level = getPlayerLevel()
			local mySkills = getLiveProfile() and getLiveProfile():FindFirstChild('Skills')
			local skillsDb = getSkillDatabase()

			local tryAdd = function(skillName)
				if not skillName or seen[skillName] or FORCE_ATTACK_SKILLS[skillName] then
					return
				end
				local forced = SUPPORT_FORCE_INCLUDE[skillName] == true
				if SKIP_UTILITY_SKILLS[skillName] and not forced then
					return
				end
				local info = getSkillInfo(skillName)
				-- Native support/utility only (no Class), unless force-included.
				if not forced and (not info.anytime or info.class) then
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
					if entry:FindFirstChild('Anytime') or SUPPORT_FORCE_INCLUDE[entry.Name] then
						tryAdd(entry.Name)
					end
				end
			end
			for forceName in pairs(SUPPORT_FORCE_INCLUDE) do
				tryAdd(forceName)
			end

			table.sort(names)
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

		-- Multi dropdown Value is { [name] = true } (unordered). Track pick order separately.
		local collectMultiSkillMap = function(value)
			local map = {}
			if value == nil then
				return map
			end
			if type(value) == 'string' then
				if value ~= '' and value ~= '(none)' then
					map[value] = true
				end
				return map
			end
			if type(value) ~= 'table' then
				return map
			end
			for k, on in pairs(value) do
				if on == true and type(k) == 'string' and k ~= '' and k ~= '(none)' then
					map[k] = true
				elseif type(on) == 'string' and on ~= '' and on ~= '(none)' then
					map[on] = true
				end
			end
			return map
		end
		getgenv().SB2CollectMultiSkillMap = collectMultiSkillMap

		local syncMultiSkillOrder = function(orderKey, selectedMap)
			local order = getgenv()[orderKey]
			if type(order) ~= 'table' then
				order = {}
				getgenv()[orderKey] = order
			end
			selectedMap = selectedMap or {}
			for i = #order, 1, -1 do
				if not selectedMap[order[i]] then
					table.remove(order, i)
				end
			end
			for name in pairs(selectedMap) do
				if not table.find(order, name) then
					order[#order + 1] = name
				end
			end
			return order
		end
		getgenv().SB2SyncMultiSkillOrder = syncMultiSkillOrder

		local refreshDropdownValues = function(option, values, invalidPlaceholder)
			if not option or not option.SetValues then
				return
			end
			local nextValues = {}
			local seen = {}
			for _, v in ipairs(values or {}) do
				if v and v ~= '(none)' and not seen[v] then
					seen[v] = true
					nextValues[#nextValues + 1] = v
				elseif v == '(none)' and not option.Multi and not seen[v] then
					seen[v] = true
					nextValues[#nextValues + 1] = v
				end
			end
			if option.Multi then
				local keepMap = collectMultiSkillMap(option.Value)
				if not next(keepMap) and type(getgenv().SB2LastCombatOptions) == 'table' then
					if option == Options.SupportSkillName then
						keepMap = collectMultiSkillMap(getgenv().SB2LastCombatOptions.SupportSkillName)
					elseif option == Options.FarmSupportSkillName then
						keepMap = collectMultiSkillMap(getgenv().SB2LastCombatOptions.FarmSupportSkillName)
					end
				end
				for name in pairs(keepMap) do
					if name and name ~= '(none)' and not seen[name] then
						seen[name] = true
						nextValues[#nextValues + 1] = name
					end
				end
				pcall(function()
					option:SetValues(nextValues)
				end)
				pcall(function()
					option:SetValue(keepMap)
				end)
				local orderKey = (option == Options.FarmSupportSkillName) and 'SB2FarmSupportSkillOrder'
					or 'SB2SupportSkillOrder'
				syncMultiSkillOrder(orderKey, keepMap)
				return
			end
			local cur = flattenOptionValue(option.Value)
			local keep = cur
			if (not keep or keep == '(none)') and type(getgenv().SB2LastCombatOptions) == 'table' then
				if option == Options.SkillName then
					keep = getgenv().SB2LastCombatOptions.SkillName
				elseif option == Options.SupportSkillName then
					keep = flattenOptionValue(getgenv().SB2LastCombatOptions.SupportSkillName)
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
		local getAvailableHealSkills

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
			-- Keep smash/CTF. Do not keep dash/pistol — those tag 0 from killaura.
			if cur and not isPoorAuraTagSkill(cur) then
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
			local healValues = getAvailableHealSkills()
			refreshDropdownValues(Options.SkillName, values, '(none)')
			refreshDropdownValues(Options.SupportSkillName, supportValues, '(none)')
			refreshDropdownValues(Options.FarmSkillName, values, '(none)')
			refreshDropdownValues(Options.FarmSupportSkillName, supportValues, '(none)')
			refreshDropdownValues(Options.FarmHealSkillName, healValues, '(none)')
			refreshDropdownValues(Options.FarmMendSkillName, healValues, '(none)')
			-- Keep combat Skill filled — empty Skill+(FarmSkill set) broke non-dive UseSkill.
			pcall(function()
				local combat = flattenOptionValue(Options.SkillName and Options.SkillName.Value)
				local farm = flattenOptionValue(Options.FarmSkillName and Options.FarmSkillName.Value)
				if (combat == nil or combat == '' or combat == '(none)')
					and type(farm) == 'string'
					and farm ~= ''
					and farm ~= '(none)'
				then
					local held = getEquippedWeaponClasses()
					local info = getSkillInfo(farm)
					if info.class and held[info.class] then
						Options.SkillName:SetValue(farm)
					else
						preferWeaponCombatSkill(false)
					end
				end
			end)
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

		local function getGameSkillsService()
			local svc = RequiredServices or getgenv().SB2RequiredServices
			if type(svc) == 'table' and type(svc.Skills) == 'table' then
				return svc.Skills
			end
			return nil
		end

		local function gameSkillCooldown(skillName)
			local skills = getGameSkillsService()
			if not skills or type(skills.GetCooldown) ~= 'function' then
				return nil
			end
			local ok, cd = pcall(skills.GetCooldown, skillName)
			if ok and type(cd) == 'number' then
				return cd
			end
			return nil
		end

		local function syncSkillCdFromGame(skillName)
			local cd = gameSkillCooldown(skillName)
			if cd == nil then
				return
			end
			if type(getgenv().SB2SkillCdUntil) ~= 'table' then
				getgenv().SB2SkillCdUntil = {}
			end
			if cd >= 0 then
				getgenv().SB2SkillCdUntil[skillName] = nil
			else
				getgenv().SB2SkillCdUntil[skillName] = time() - cd
			end
		end

		local function gameSkillReady(skillName)
			local cd = gameSkillCooldown(skillName)
			if cd == nil then
				return nil
			end
			syncSkillCdFromGame(skillName)
			return cd >= 0
		end

		local function gameSkillCanCast(skillName)
			local skills = getGameSkillsService()
			if not skills then
				return nil
			end
			if skills.usingSkill and skills.usingSkill ~= 'none' and skills.usingSkill ~= skillName then
				return false
			end
			local ready = gameSkillReady(skillName)
			if ready == false then
				return false
			end
			if type(skills.HasStamina) == 'function' then
				local info = getSkillInfo(skillName)
				local ok, has = pcall(skills.HasStamina, info.cost or 0)
				if ok and has == false then
					return false
				end
			end
			return ready ~= false
		end

		local isSkillReady = function(skillName)
			local gameReady = gameSkillReady(skillName)
			if gameReady == false then
				return false
			end
			if gameReady == true then
				return true
			end
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
			local map = collectMultiSkillMap(raw)
			if not next(map) then
				return nil
			end
			local order = syncMultiSkillOrder('SB2SupportSkillOrder', map)
			return order[1]
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
			if opt.Multi then
				local map = collectMultiSkillMap(raw)
				if not next(map) then
					return nil
				end
				local orderKey = (optName == 'FarmSupportSkillName') and 'SB2FarmSupportSkillOrder'
					or 'SB2SupportSkillOrder'
				local order = syncMultiSkillOrder(orderKey, map)
				return order[1]
			end
			local value = flattenOptionValue(raw)
			if value == nil or value == '' or value == '(none)' or value == '(none for held weapon)' then
				return nil
			end
			return value
		end

		local function usingEventFarmSkills()
			return isToggleOn('DiveFarm') or getgenv().SB2DiveFarmOn == true
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

		local function getActiveSupportSkillList()
			local farmOpt = Options.FarmSupportSkillName
			local combatOpt = Options.SupportSkillName
			local farmMap = {}
			local combatMap = {}
			if type(farmOpt) == 'table' then
				local ok, raw = pcall(function()
					return farmOpt.Value
				end)
				if ok then
					farmMap = collectMultiSkillMap(raw)
				end
			end
			if type(combatOpt) == 'table' then
				local ok, raw = pcall(function()
					return combatOpt.Value
				end)
				if ok then
					combatMap = collectMultiSkillMap(raw)
				end
			end
			if usingEventFarmSkills() then
				if next(farmMap) then
					return syncMultiSkillOrder('SB2FarmSupportSkillOrder', farmMap)
				end
				return syncMultiSkillOrder('SB2SupportSkillOrder', combatMap)
			end
			if next(combatMap) then
				return syncMultiSkillOrder('SB2SupportSkillOrder', combatMap)
			end
			return syncMultiSkillOrder('SB2FarmSupportSkillOrder', farmMap)
		end

		local function getActiveWeaponSkillName()
			local farm = getSelectedFarmSkillName()
			local combat = getSelectedSkillName()
			local picked
			if usingEventFarmSkills() then
				picked = farm or combat
			elseif combat then
				picked = combat
			elseif farm then
				-- Skill dropdown often left on (none) while FarmSkill is set — that made
				-- UseSkill / killaura tags only work during Event dive.
				picked = farm
			else
				local avail = getAvailableSkills()
				for _, name in ipairs(avail) do
					if name ~= '(none)' and name ~= '(none for held weapon)' then
						picked = name
						break
					end
				end
				picked = picked or farm
			end
			return resolveAuraWeaponSkill(picked)
		end

		local function getActiveSupportSkillName()
			local list = getActiveSupportSkillList()
			return list and list[1] or nil
		end

		local HEAL_SKILL_PRIORITY = {
			'Heal',
			'Mending Spirit',
		}
		local BURST_HEAL_NAME = 'Heal'
		local MEND_HEAL_NAME = 'Mending Spirit'
		local MEND_HOLD_FALLBACK = 8
		local MEND_AOE_STAY = 10

		getAvailableHealSkills = function()
			local names = { '(none)' }
			local seen = { ['(none)'] = true }
			local mySkills = getLiveProfile() and getLiveProfile():FindFirstChild('Skills')
			local function tryAdd(skillName)
				if not skillName or seen[skillName] then
					return
				end
				seen[skillName] = true
				names[#names + 1] = skillName
			end
			for _, skillName in ipairs(HEAL_SKILL_PRIORITY) do
				tryAdd(skillName)
			end
			if mySkills then
				for _, owned in ipairs(mySkills:GetChildren()) do
					local lower = string.lower(owned.Name)
					if string.find(lower, 'heal', 1, true)
						or string.find(lower, 'mending', 1, true)
					then
						tryAdd(owned.Name)
					end
				end
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
			'BOB',
			'Bob',
			'Borik the BeeKeeper',
			'Corrupted Atheon',
			'Count Dracula',
			'Da, the Demeanor',
			'Duality Reaper',
			'Enraged Wendigo',
			'Formaug the Jungle Giant',
			'Grim the Overseer',
			"Guardian's Vessel",
			'Headless Horseman',
			'Irath the Lion',
			'Jolrock the Snow Protecter',
			'Ka, the Mischief',
			'Limor the Devourer',
			'Mortis the Flaming Sear',
			'Orc King',
			'Pan Ku, Chaos-born',
			'Panku',
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
			'Hunter',
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
			if string.find(lower, 'boss', 1, true)
				or string.find(lower, 'warlord', 1, true)
				or string.find(lower, 'miniboss', 1, true)
				or string.find(lower, 'elite', 1, true)
			then
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
			-- Floor elites / multi-bar tanks (Warlord, Orange FE, etc.).
			local bars = entity and entity:FindFirstChild('HealthbarCount')
			if bars and typeof(bars.Value) == 'number' and bars.Value > 1 then
				return true
			end
			local diff = entity and entity:FindFirstChild('Difficulty')
			if diff and typeof(diff.Value) == 'string' then
				local d = string.lower(diff.Value)
				if string.find(d, 'boss', 1, true)
					or string.find(d, 'mini', 1, true)
					or d == 'hard'
					or d == 'extreme'
				then
					return true
				end
			end
			local health = entity and entity:FindFirstChild('Health')
			if health and typeof(health.Value) == 'number' and health.Value >= 400000 then
				return true
			end
			return false
		end

		local function isPriorityMob(mob)
			if isBossMob(mob) then
				return true
			end
			if not mob then
				return false
			end
			local lower = string.lower(tostring(mob.Name))
			-- Colored / named floor elites that aren't full wiki bosses.
			if string.find(lower, 'orange', 1, true) and string.find(lower, 'experiment', 1, true) then
				return true
			end
			if string.find(lower, 'lord', 1, true) or string.find(lower, 'king', 1, true) then
				return true
			end
			local entity = mob:FindFirstChild('Entity')
			local health = entity and entity:FindFirstChild('Health')
			if health and typeof(health.Value) == 'number' and health.Value >= 200000 then
				return true
			end
			return false
		end

		-- One-shot / arena-nuke bosses: charge telegraphs + head-top autofarm height.
		local NUKE_BOSS_NEEDLES = {
			'aeganatos',
			'aegatanos',
			'deityoftheflame',
			'deityof',
			'deity',
			'atheon',
			'vyroth',
			'frostflame',
			'basileus',
			'basileusyansafe',
			'yansafe',
			'panku',
			'pankuchaos',
			'terrorincarnat',
			'terrorincarnate',
			'guardiansvessel',
			'guardianvessel',
			'enragedwendigo',
			'wendigo',
			'countdracula',
			'dracula',
		}
		local function isNukeBossMob(mob)
			if not mob or not mob.Parent then
				return false
			end
			local key = normBossKey(mob.Name)
			if key == 'bob' then
				return true
			end
			for i = 1, #NUKE_BOSS_NEEDLES do
				if string.find(key, NUKE_BOSS_NEEDLES[i], 1, true) then
					return true
				end
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

		-- Event elites that should still get CE even when "support only on bosses" is on
		-- (Meta Figure / DJ Reaper aren't in the wiki boss list).
		local function supportWorthyMobsPresent()
			if anyBossPresent() then
				return true
			end
			if usingEventFarmSkills() then
				return true
			end
			local mobs = workspace:FindFirstChild('Mobs')
			if not mobs then
				return false
			end
			for _, mob in ipairs(mobs:GetChildren()) do
				if isDeadMob(mob) then
					continue
				end
				local n = string.lower(tostring(mob.Name or ''))
				if string.find(n, 'metafigure', 1, true)
					or string.find(n, 'dj reaper', 1, true)
					or string.find(n, 'aeganatos', 1, true)
					or string.find(n, 'aegatanos', 1, true)
					or string.find(n, 'sunken sovereign', 1, true)
					or string.find(n, 'saurus', 1, true)
				then
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
			-- Game has a hard attack-speed floor; extra delay sliders / rush mode do nothing useful.
			return false
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
				-- No toggle yet: allow if any support skill is selected.
				local list = getActiveSupportSkillList()
				return type(list) == 'table' and #list > 0
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
			if not opts.skipReadyCheck and not isSkillReady(skillName) then
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

		-- Support multi: CE always first when ready; then selection order + CD.
		-- Under map: heals outrank support (handled in castSelectedSupportSkill).
		local getSupportCastTarget = function()
			if not wantSupportSkill() then
				return nil, nil
			end
			if not workspaceHasMobs() then
				return nil, nil
			end
			if wantSupportBossOnly() and not supportWorthyMobsPresent() and not wantHitLivesRush() then
				return nil, nil
			end

			local mySkills = getLiveProfile() and getLiveProfile():FindFirstChild('Skills')
			local function canCast(skillName)
				if not skillName or skillName == '(none)' then
					return nil
				end
				local forced = SUPPORT_FORCE_INCLUDE[skillName] == true
				if SKIP_UTILITY_SKILLS[skillName] and not forced then
					return nil
				end
				local info = getSkillInfo(skillName)
				local isKnownSupport = forced
					or (info.anytime == true and not info.class)
				if not isKnownSupport then
					return nil
				end
				if mySkills and not mySkills:FindFirstChild(skillName) then
					return nil
				end
				if not isSkillReady(skillName) then
					return nil
				end
				local stam = getPlayerStamina()
				if stam < (info.cost or 0) then
					return nil
				end
				return info
			end

			-- Always: Cursed Enhancement outranks every other support when ready.
			local ceInfo = canCast('Cursed Enhancement')
			if ceInfo then
				return 'Cursed Enhancement', ceInfo
			end

			local list = getActiveSupportSkillList()
			for _, skillName in ipairs(list) do
				if skillName ~= 'Cursed Enhancement' then
					local info = canCast(skillName)
					if info then
						return skillName, info
					end
				end
			end
			return nil, nil
		end

		local castSelectedSupportSkill = function()
			if (tonumber(getgenv().SB2CombatBootGraceUntil) or 0) > os.clock() then
				return false
			end
			-- Under map: heal skills always take priority over support buffs.
			local underMap = getgenv().SB2DiveUnderMap == true
			if underMap then
				local healFn = getgenv().SB2TryCastEventHeal
				local before = getgenv().SB2LastEventHeal
				local beforeAt = type(before) == 'table' and before.at or 0
				if type(healFn) == 'function' then
					pcall(healFn, 'under', nil)
				end
				local after = getgenv().SB2LastEventHeal
				if type(after) == 'table' and (after.at or 0) > beforeAt and (os.clock() - (after.at or 0)) < 0.75 then
					return true
				end
			end
			local skillName, info = getSupportCastTarget()
			if not skillName then
				return false
			end
			-- ignoreGap: weapon UseSkill spam was eating the shared cast gap so CE never fired.
			local ok = fireUseSkill(skillName, info, {
				muteFor = 2.0,
				silentFail = true,
				ignoreGap = true,
			}) == true
			if ok then
				getgenv().SB2LastSupportCast = { skill = skillName, at = os.clock() }
			end
			return ok
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
			if (tonumber(getgenv().SB2CombatBootGraceUntil) or 0) > os.clock() then
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
					or isPoorAuraTagSkill(skillName)
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
				or isPoorAuraTagSkill(skillName)
			then
				return nil
			end

			local info = getSkillInfo(skillName)
			local forced = FORCE_ATTACK_SKILLS[skillName] == true
			-- Class gate: skip when Event dive owns the farm skill, or when the
			-- selected combat skill matches held weapons.
			if not forced then
				if not info.class then
					return nil
				end
				if not usingEventFarmSkills() then
					local held = getEquippedWeaponClassesCached()
					if not held[info.class] then
						-- Try first held-class skill instead of silently doing nothing.
						local avail = getAvailableSkills()
						local alt = nil
						for _, name in ipairs(avail) do
							if name ~= '(none)' and name ~= '(none for held weapon)' then
								alt = name
								break
							end
						end
						if not alt then
							return nil
						end
						skillName = alt
						info = getSkillInfo(skillName)
						if not info.class or not held[info.class] then
							return nil
						end
					end
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
			-- Keep the skill name even if UseSkill is on CD / fails — AutoAttack
			-- still needs it for DealDamage/Attack tags between casts.
			getgenv().SB2SkillActiveName = skillName

			local ok = fireUseSkill(skillName, info, { muteFor = 1.35 })
			task.defer(function()
				task.wait(0.15)
				getgenv().SB2SkillCastLock = false
			end)
			-- Keep the tag window open even when UseSkill fails (CD / range).
			-- Bare DealDamage(nil) barely ticks; skill-tagged hits still work.
			getgenv().SB2SkillActiveUntil = now + 2.25
			if not ok then
				return skillName
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
				-- Far = trustworthy world position. Always refresh.
				if dist > 40 then
					mobRealCF[mob] = root.CFrame
				elseif not stacked then
					-- Not stacked: client pos is real enough to keep/update.
					if dist > 12 or not mobRealCF[mob] then
						mobRealCF[mob] = root.CFrame
					end
				end
				-- When stacked and we already have a cache, keep it (real world spot).
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

		;(function()
		local CombatTab = Window:AddTab('Combat', 'swords')
		local FarmTab = Window:AddTab('Farm', 'swords')
		local BossTab = Window:AddTab('Boss', 'swords')
		local CombatBox = CombatTab:AddLeftGroupbox('Combat')
		local FarmBox = FarmTab:AddLeftGroupbox('Event dive')
		local BossBox = BossTab:AddLeftGroupbox('Boss route')
		assert(CombatBox, 'Combat groupbox nil')
		assert(FarmBox, 'Farm groupbox nil')
		assert(BossBox, 'Boss groupbox nil')

		CombatBox:AddToggle('AutoSkill', {
			Text = 'Auto skill damage',
			Default = false,
			Tooltip = 'UseSkill once, then tag DealDamage/Attack with that skill (all streamed mobs) for ~1s. Works with or without Event dive.',
		})

		local function startAutoSkillLoop()
			getgenv().SB2AutoSkillOn = true
			local prev = getgenv().SB2AutoSkillOnlyConn
			if prev then
				pcall(function()
					prev:Disconnect()
				end)
				getgenv().SB2AutoSkillOnlyConn = nil
			end
			getgenv().SB2SkillCastLock = false
			local lastPulse = 0
			getgenv().SB2AutoSkillOnlyConn = RunService.Heartbeat:Connect(function()
				if getgenv().SB2AutoSkillOn ~= true or not isToggleOn('AutoSkill') then
					local conn = getgenv().SB2AutoSkillOnlyConn
					if conn then
						pcall(function()
							conn:Disconnect()
						end)
						getgenv().SB2AutoSkillOnlyConn = nil
					end
					return
				end
				if (tonumber(getgenv().SB2CombatBootGraceUntil) or 0) > os.clock() then
					return
				end
				if isToggleOn('DiveFarm')
					and getgenv().SB2DiveFarmOn == true
					and getgenv().SB2DiveFarmThread ~= nil
				then
					pcall(castSelectedSupportSkill)
					return
				end
				local now = os.clock()
				if now - lastPulse < 0.4 then
					return
				end
				lastPulse = now
				if not isLocalAlive() then
					return
				end
				pcall(castSelectedSupportSkill)
				pcall(ensureSkillWindow)
			end)
		end

		Toggles.AutoSkill:OnChanged(function(value)
			getgenv().SB2AutoSkillOn = value == true
			local prev = getgenv().SB2AutoSkillOnlyConn
			if prev then
				pcall(function()
					prev:Disconnect()
				end)
				getgenv().SB2AutoSkillOnlyConn = nil
			end
			if not value then
				return
			end
			startAutoSkillLoop()
		end)
		-- Profile/autoload may paint AutoSkill=true without firing OnChanged.
		task.defer(function()
			local t = Toggles.AutoSkill
			if type(t) == 'table' and t.Value == true and getgenv().SB2AutoSkillOnlyConn == nil then
				startAutoSkillLoop()
			end
		end)

		local applyCombatAnchor = function(enabled)
			-- Event dive / vacuum must move HRP — never hard-anchor while diving.
			if enabled and (isToggleOn('DiveFarm') or getgenv().SB2DiveFarmOn == true) then
				enabled = false
			end
			local model = getMyCharacterModel()
			local hrp = model and (model:FindFirstChild('HumanoidRootPart') or model:FindFirstChild('UpperTorso'))
			if not hrp or not hrp:IsA('BasePart') then
				-- Still toggle ghost if we can.
				pcall(setAnchorPlayerNoclip, enabled == true)
				return false
			end
			pcall(function()
				hrp.Anchored = false
				if enabled == true then
					if typeof(getgenv().SB2AnchorLockCF) ~= 'CFrame' then
						if type(getgenv().SB2SetAnchorLockCF) == 'function' then
							getgenv().SB2SetAnchorLockCF(hrp.CFrame)
						else
							getgenv().SB2AnchorLockCF = hrp.CFrame
						end
					end
				else
					getgenv().SB2AnchorLockCF = nil
				end
			end)
			-- ONE-SHOT ghost assign/restore. Do NOT call this from Heartbeat — full
			-- descendant scans were the Anchor lag (HelperMob does not reset on its own).
			pcall(setAnchorPlayerNoclip, enabled == true)
			if enabled ~= true then
				pcall(function()
					hrp.AssemblyLinearVelocity = Vector3.zero
					hrp.AssemblyAngularVelocity = Vector3.zero
				end)
				if getgenv().SB2TpPinActive == true then
					getgenv().SB2TpPinGen = (tonumber(getgenv().SB2TpPinGen) or 0) + 1
					getgenv().SB2TpPinActive = false
					getgenv().SB2TpPinCFrame = nil
					getgenv().SB2TpPinUntil = 0
				end
				local descConn = getgenv().SB2AnchorDescConn
				if descConn then
					pcall(function()
						descConn:Disconnect()
					end)
					getgenv().SB2AnchorDescConn = nil
				end
				local g = getgenv()._SB2AnimGhost
				if type(g) == 'table' then
					pcall(function()
						if g.clone then
							for _, d in ipairs(g.clone:GetDescendants()) do
								if d:IsA('BasePart') then
									d.CanCollide = false
									d.CanTouch = false
									d.Massless = true
								end
							end
						end
						if g.weaponFolder then
							for _, d in ipairs(g.weaponFolder:GetDescendants()) do
								if d:IsA('BasePart') then
									d.CanCollide = false
									d.CanTouch = false
									d.Massless = true
								end
							end
						end
					end)
				end
			else
				-- New parts only (accessories / weapons) — no periodic full rescan.
				local prevDesc = getgenv().SB2AnchorDescConn
				if prevDesc then
					pcall(function()
						prevDesc:Disconnect()
					end)
				end
				if model then
					getgenv().SB2AnchorDescConn = model.DescendantAdded:Connect(function(inst)
						if getgenv().SB2CombatAnchorOn ~= true then
							return
						end
						if inst:IsA('BasePart') and type(getgenv().SB2GhostPartForAnchor) == 'function' then
							pcall(getgenv().SB2GhostPartForAnchor, inst, true)
						end
					end)
				end
			end
			return true
		end

		CombatBox:AddToggle('AutoAttack', {
			Text = 'Killaura',
			Tooltip = 'DealDamage/Attack nearby (and streamed) mobs. Pair with Auto skill for UseSkill + skill-tagged hits.',
		}):OnChanged(function(value)
			getgenv().SB2AutoAttackOn = value == true
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

			-- Hive stack / raw CFrame TP leaves the server at the old pad → 0 weapon damage.
			pcall(function()
				if isPoorAuraTagSkill(getgenv().SB2SkillActiveName) then
					getgenv().SB2SkillActiveName = nil
					getgenv().SB2SkillActiveUntil = 0
				end
				local model = getMyCharacterModel() or LocalPlayer.Character
				local hrp = model and (model:FindFirstChild('HumanoidRootPart') or model:FindFirstChild('UpperTorso'))
				if hrp and hrp:IsA('BasePart') and type(pinTeleportCFrame) == 'function' then
					pinTeleportCFrame(hrp.CFrame, 0.9)
				end
			end)

			-- One safe RPCKey fetch if we don't have it yet — never RefillKeys / gc brute.
			task.spawn(function()
				pcall(refreshRpcKey)
			end)
			-- Clear stuck skill lock/CD from old laggy sessions.
			getgenv().SB2SkillCastLock = false
			getgenv().SB2SkillCdUntil = {}
			-- Keep last skill tag name — wiping it made the first seconds of killaura do nothing.
			if type(getgenv().SB2SkillActiveUntil) ~= 'number' or getgenv().SB2SkillActiveUntil < time() then
				getgenv().SB2SkillActiveUntil = 0
			end
			-- Combat Skill often left on (none) while FarmSkill is set — fill it so tags work.
			pcall(function()
				local combat = flattenOptionValue(Options.SkillName and Options.SkillName.Value)
				local farm = flattenOptionValue(Options.FarmSkillName and Options.FarmSkillName.Value)
				if (not combat or combat == '' or combat == '(none)')
					and type(farm) == 'string'
					and farm ~= ''
					and farm ~= '(none)'
					and Options.SkillName
					and type(Options.SkillName.SetValue) == 'function'
				then
					Options.SkillName:SetValue(farm)
				end
			end)
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
				local gui = getgenv().SB2PlayerToolsGui
				if getgenv().SB2AutoAttackOn ~= true or not (gui and gui.Parent) then
					local conn = getgenv().SB2AutoAttackConn
					if conn then
						conn:Disconnect()
						getgenv().SB2AutoAttackConn = nil
					end
					getgenv().SB2AutoAttackOn = false
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
				if (tonumber(getgenv().SB2CombatBootGraceUntil) or 0) > os.clock() then
					return
				end
				-- Soft re-fetch RPC key if it never landed (boot race / hop).
				if not combatState.rpcReady and (now - (combatState.lastRpcTry or 0)) > 2.5 then
					combatState.lastRpcTry = now
					task.spawn(function()
						pcall(refreshRpcKey)
					end)
				end
				local myPart = getMyBringPart()
				local mobsRoot = workspace:FindFirstChild('Mobs')
				if not myPart or not mobsRoot then
					return
				end

				local aaRange = AUTO_ATTACK_RANGE
				local skillRange = SKILL_HIT_RANGE
				if usingEventFarmSkills() then
					aaRange = math.max(aaRange, SKILL_HIT_RANGE)
					skillRange = SKILL_HIT_RANGE
				end
				local delay = AUTO_ATTACK_DELAY
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
				-- Prefer attack CFrame (handles client-stack). Unlimited stream wasted the
				-- tick on far elites the server refuses to damage — bosses felt unhittable.
				local range = AURA_DAMAGE_RANGE
				local bossRange = BOSS_DAMAGE_RANGE
				local rangeSq = range * range
				local bossRangeSq = bossRange * bossRange
				local attackAllStreamed = false
				if pistolMode then
					range = aaRange
					rangeSq = range * range
				end

				-- Always refresh real-CF cache so stacked packs + far bosses range-check right.
				cacheMobRealPositions(origin)

				-- Hit-lives mobs die by hit count — CE buff + basic swings, no weapon UseSkill.
				local attackName = nil
				local function skillTagFallback()
					if pistolMode then
						return nil
					end
					local fallback = selectedSkill
					if (not fallback or fallback == '' or fallback == '(none)' or FORCE_ATTACK_SKILLS[fallback])
						and type(getgenv().SB2SkillActiveName) == 'string'
					then
						fallback = getgenv().SB2SkillActiveName
					end
					if type(fallback) ~= 'string'
						or fallback == ''
						or fallback == '(none)'
						or fallback == '(none for held weapon)'
						or FORCE_ATTACK_SKILLS[fallback]
						or isPoorAuraTagSkill(fallback)
						or fallback == 'Block'
						or fallback == 'Roll'
						or fallback == 'Sprint'
					then
						return nil
					end
					return fallback
				end
				if hitLivesRush then
					if isToggleOn('AutoSkill') then
						pcall(castSelectedSupportSkill)
					end
				elseif isToggleOn('AutoSkill') then
					attackName = ensureSkillWindow()
					-- Between UseSkill casts, bare DealDamage(nil) does almost nothing past
					-- melee. Keep tagging the selected/last skill so ranged ticks still hurt.
					if not attackName then
						attackName = skillTagFallback()
					end
				else
					-- Killaura alone: still tag the selected skill. Without a name,
					-- DealDamage(nil) barely ticks at aura range.
					attackName = skillTagFallback()
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
					local priority = isPriorityMob(mob)
					local atkCF = getMobAttackCFrame(mob, root, origin)
					local dx = atkCF.Position.X - origin.X
					local dz = atkCF.Position.Z - origin.Z
					local distSq = dx * dx + dz * dz
					-- Live root fallback (sometimes more accurate than stale cache).
					local lx = root.Position.X - origin.X
					local lz = root.Position.Z - origin.Z
					local liveSq = lx * lx + lz * lz
					if liveSq < distSq then
						distSq = liveSq
					end
					local maxSq = priority and bossRangeSq or rangeSq
					if pistolMode then
						maxSq = rangeSq
					end
					if not attackAllStreamed and distSq > maxSq then
						continue
					end
					mobList[#mobList + 1] = {
						mob = mob,
						hitLives = mobUsesHitLives(mob),
						boss = isBossMob(mob),
						priority = priority,
						special = mobHasSpecialAttribute(mob),
						distSq = distSq,
					}
				end
				table.sort(mobList, function(a, b)
					if a.hitLives ~= b.hitLives then
						return a.hitLives
					end
					if a.priority ~= b.priority then
						return a.priority
					end
					if a.boss ~= b.boss then
						return a.boss
					end
					if a.special ~= b.special then
						return a.special
					end
					return a.distSq < b.distSq
				end)

				local attacked = 0
				for _, entry in ipairs(mobList) do
					local mob = entry.mob
					if attacked >= MAX_ATTACKS_PER_TICK then
						break
					end
					local strikes = 1
					if entry.priority or entry.boss or entry.hitLives then
						strikes = BOSS_HITS_PER_TICK
					end
					for _ = 1, strikes do
						if attacked >= MAX_ATTACKS_PER_TICK then
							break
						end
						if onCooldown[mob] and not (entry.priority or entry.boss) then
							break
						end
						if fireMobAttack(mob, attackName) then
							attacked += 1
							if not (entry.priority or entry.boss or entry.hitLives) then
								onCooldown[mob] = true
								task.delay(delay, function()
									onCooldown[mob] = nil
								end)
								break
							else
								-- Bosses: brief per-strike spacing only.
								onCooldown[mob] = true
								task.delay(BOSS_ATTACK_DELAY, function()
									onCooldown[mob] = nil
								end)
							end
						else
							break
						end
					end
				end
			end)
		end)

		CombatBox:AddToggle('CombatAnchor', {
			Text = 'Anchor',
			Default = false,
			Tooltip = 'One-shot HelperMob ghost (mobs/players walk through) + rare push snap (~1s). No per-frame work. TPs stay unanchored so they replicate. Auto-off during Event dive.',
		}):OnChanged(function(value)
			-- Resume/profile setCombatTrio must not pin HRP during Event dive.
			if value and (isToggleOn('DiveFarm') or getgenv().SB2DiveFarmOn == true) then
				getgenv().SB2CombatAnchorOn = false
				local prev = getgenv().SB2CombatAnchorConn
				if prev then
					pcall(function()
						prev:Disconnect()
					end)
					getgenv().SB2CombatAnchorConn = nil
				end
				applyCombatAnchor(false)
				task.defer(function()
					local t = Toggles.CombatAnchor
					if type(t) == 'table' and type(t.SetValue) == 'function' and t.Value == true then
						t:SetValue(false)
					end
				end)
				return
			end
			getgenv().SB2CombatAnchorOn = value == true
			local prev = getgenv().SB2CombatAnchorConn
			if prev then
				pcall(function()
					prev:Disconnect()
				end)
				getgenv().SB2CombatAnchorConn = nil
			end
			if not value then
				getgenv().SB2AnchorHoldUntil = 0
				-- Cancel any active TP pin loop — it re-sets Anchored=true every Heartbeat
				-- and leaves you floating after turning Anchor off.
				getgenv().SB2TpPinGen = (tonumber(getgenv().SB2TpPinGen) or 0) + 1
				getgenv().SB2TpPinActive = false
				getgenv().SB2TpPinCFrame = nil
				getgenv().SB2TpPinUntil = 0
				applyCombatAnchor(false)
				pcall(function()
					local model = getMyCharacterModel() or LocalPlayer.Character
					local root = model
						and (model:FindFirstChild('HumanoidRootPart') or model:FindFirstChild('UpperTorso'))
					local hum = model and model:FindFirstChildOfClass('Humanoid')
					if root and root:IsA('BasePart') then
						root.Anchored = false
						root.AssemblyLinearVelocity = Vector3.zero
						root.AssemblyAngularVelocity = Vector3.zero
					end
					if hum then
						hum.PlatformStand = false
						pcall(function()
							hum:ChangeState(Enum.HumanoidStateType.Freefall)
						end)
					end
				end)
				return
			end
			-- Boss-route / TP pin: do NOT open an unanchor window — that drops you into the floor.
			if getgenv().SB2TpPinActive == true or getgenv().SB2BossRouteWanted == true then
				getgenv().SB2AnchorHoldUntil = 0
			else
				holdCombatAnchor(0.5)
			end
			applyCombatAnchor(true)
			-- NO Heartbeat soft-lock. Probe: Anchor heartbeat/scans were ~16fps.
			-- HelperMob is one-shot; DescendantAdded covers new parts; push snap is optional via TP pin only.
			getgenv().SB2CombatAnchorConn = nil
		end)

		-- Soft reload: restore pose + combat toggles that teardown cleared.
		task.defer(function()
			if getgenv().SB2SoftReloadPreserveFlight ~= true then
				return
			end
			local pin = getgenv().SB2SoftReloadPinCF
			local wantAnchor = getgenv().SB2SoftReloadHadAnchor == true
			local wantAA = getgenv().SB2SoftReloadHadAutoAttack == true
			local wantSkill = getgenv().SB2SoftReloadHadAutoSkill == true
			if typeof(pin) == 'CFrame' and pin.Position.Y > -20 then
				pcall(function()
					local model = getMyCharacterModel() or LocalPlayer.Character
					local hrp = model
						and (model:FindFirstChild('HumanoidRootPart') or model:FindFirstChild('UpperTorso'))
					if hrp and hrp:IsA('BasePart') then
						hrp.CFrame = pin
						hrp.AssemblyLinearVelocity = Vector3.zero
						hrp.AssemblyAngularVelocity = Vector3.zero
						-- Soft Anchor only — hard Anchored from reload gap tanks nothing useful and fights soft-lock.
						hrp.Anchored = false
					end
				end)
				if wantAnchor then
					if type(pinTeleportCFrame) == 'function' then
						pcall(pinTeleportCFrame, pin, 0.75)
					end
					if Toggles.CombatAnchor and type(Toggles.CombatAnchor.SetValue) == 'function' then
						pcall(function()
							Toggles.CombatAnchor:SetValue(true)
						end)
					end
				else
					-- Landing / walk: release HRP after a short settle.
					task.delay(0.35, function()
						if getgenv().SB2CombatAnchorOn == true then
							return
						end
						pcall(function()
							local model = getMyCharacterModel() or LocalPlayer.Character
							local hrp = model and model:FindFirstChild('HumanoidRootPart')
							if hrp and hrp:IsA('BasePart') then
								hrp.Anchored = false
							end
						end)
					end)
				end
			end
			-- Teardown clears AA/skill; put them back if they were on.
			task.defer(function()
				if wantAA and Toggles.AutoAttack and type(Toggles.AutoAttack.SetValue) == 'function' then
					pcall(function()
						Toggles.AutoAttack:SetValue(true)
					end)
				end
				if wantSkill and Toggles.AutoSkill and type(Toggles.AutoSkill.SetValue) == 'function' then
					pcall(function()
						Toggles.AutoSkill:SetValue(true)
					end)
				end
			end)
			getgenv().SB2SoftReloadPreserveFlight = nil
			getgenv().SB2SoftReloadPinCF = nil
			getgenv().SB2SoftReloadHadAnchor = nil
			getgenv().SB2SoftReloadHadBoss = nil
			getgenv().SB2SoftReloadWasAnchored = nil
			getgenv().SB2SoftReloadHadAutoAttack = nil
			getgenv().SB2SoftReloadHadAutoSkill = nil
		end)

		-- Event dive: Bluu XZ-follow on the mob's *real* CF, Y under the floor
		-- Vacuum-style event farm: hover ABOVE the attack CFrame (real CF when
		-- client-stacked) and DealDamage from the dive loop — same idea as
		-- AutoFarm BringMobs. Fight height scales with equipped Blade hitbox length.
		local DIVE_HOVER = 8 -- fallback when blade can't be measured
		-- CTF reach height: HRP ~one platform below mob feet (see Event dive approach).
		local DIVE_FIGHT_BELOW_FEET = 2
		-- Nuke-boss fight height: stand on head/crown top (+ studs above highest part).
		local DIVE_NUKE_HEAD_ABOVE = 16 -- head-top grind (Atheon/Deity + Vyroth, Panku, Terror*, Guardian's Vessel, Wendigo, Dracula, …)
		local DIVE_NUKE_AIM_BODY_UP = 0.35
		local DIVE_BOSS_MOVE_THRESH = 8
		local DIVE_BOSS_Y_THRESH = 5
		local DIVE_WRITE_DEBOUNCE = 1.5
		local DIVE_PLATFORM_STEP = 5.5 -- one tier down (lower ledge CTF range)
		local DIVE_APPROACH_MAX = 380 -- was 120 — aborting here never teleported, felt "stuck"
		local DIVE_SURFACE_FLEE_SEC = 4 -- fight/heal on surface before under-map when already low HP
		local DIVE_ARRIVE = 7
		local DIVE_SNAP_DIST = 8
		local DIVE_TWEEN_SPEED = 300
		local DIVE_APPROACH_SPEED_MULT = 1.9
		local DIVE_DASH_CHASE_MULT = 2.8
		local DIVE_DASH_BLINK_FLAT = 48
		local DIVE_BOSS_TRACK_INTERVAL = 0.14
		local DIVE_HIT_DELAY = 0.06
		local DIVE_AURA_RANGE = AUTO_ATTACK_RANGE
		local DIVE_FLEE_RANGE = math.max(320, AUTO_ATTACK_RANGE)
		local DIVE_STREAM_RADIUS = 512
		local DIVE_MAX_KEEP = 360
		local DIVE_HP_FLEE = 0.50
		local DIVE_HP_RETURN = 0.95
		local DIVE_HP_PANIC = 0.25
		local DIVE_CENTER_RANGE = 14
		local DIVE_POISON_HEAL = 0.82

		-- Place-specific Event dive farm pads. F5: stay in the labyrinth (grid),
		-- never the boss castle box on the right.
		local DIVE_FARM_ZONES = {
			[580239979] = { -- F5 Desolate Dunes
				-- Keep well inside the maze — maxZ used to sit on the bridge and
				-- pin bots against the boss-room edge (looked like a freeze).
				minX = 1780,
				maxX = 2720,
				minZ = -2450,
				maxZ = -1300,
				edgeInset = 55,
				bossExcludeRadius = 420,
				bossSpawnName = 'ASpawnBoss',
				skipBosses = true,
				label = 'F5 labyrinth',
			},
		}
		local DIVE_FIRE_HEAL = 0.65
		local DIVE_RETARGET_SEC = 0.35
		-- Drop under arena floor to regen; keep XZ near boss so stream doesn't despawn him.
		local DIVE_FLEE_UNDER = 38
		local DIVE_FLEE_UNDER_BOSS = 58
		local DIVE_FLEE_RING = 14
		local DIVE_TELE_NEAR = 160
		local DIVE_NUKE_HOLD = 1.2
		local DIVE_NUKE_COOLDOWN = 2.5
		local DIVE_TELE_CACHE_SEC = 0.45
		-- Hard rails — never blink across the map / into void.
		local DIVE_SAFE_FLAT = 48
		local DIVE_SAFE_Y = 36
		local DIVE_MAX_BLINK = 42
		local DIVE_DODGE_RING = 38

		local function diveOptNumber(name, fallback)
			local opt = Options and Options[name]
			local v = opt and tonumber(opt.Value)
			if v == nil then
				return fallback
			end
			return v
		end

		local function diveAutoHeightOn()
			local t = Toggles and Toggles.DiveAutoHeight
			if type(t) == 'table' then
				return t.Value == true
			end
			return true
		end

		-- Farm height slider = studs relative to mob top (negative = into/below top).
		-- Auto farm height only raises the floor for long weapons — never lowers
		-- a user-set slider.
		local function diveFarmAboveStuds()
			local manual = math.clamp(diveOptNumber('DiveFarmHeight', DIVE_HOVER), -40, 80)
			if diveAutoHeightOn() then
				local reach = tonumber(getgenv().SB2DiveWeaponReach) or DIVE_HOVER
				local autoH = math.clamp(reach * 0.55, 6, 40)
				return math.max(manual, autoH)
			end
			return manual
		end

		local function diveFleeUnderDepth(isBoss)
			local base = math.clamp(diveOptNumber('DiveFleeDepth', DIVE_FLEE_UNDER), 10, 120)
			if isBoss then
				local bossFloor = math.clamp(diveOptNumber('DiveFleeDepthBoss', DIVE_FLEE_UNDER_BOSS), 10, 140)
				return math.max(base, bossFloor)
			end
			return base
		end

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
		local diveNoclipGroups = {}
		local DIVE_NOCLIP_GROUP = 'SB2DiveNoclip'
		local diveNoclipGroupReady = false
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

		local function ensureDiveNoclipGroup()
			if diveNoclipGroupReady then
				return
			end
			pcall(function()
				PhysicsService:RegisterCollisionGroup(DIVE_NOCLIP_GROUP)
			end)
			pcall(function()
				PhysicsService:CreateCollisionGroup(DIVE_NOCLIP_GROUP)
			end)
			for _, other in ipairs({
				'Default',
				'Players',
				'Characters',
				'Mobs',
				'MobsNoCollision',
				'Mob',
				'Enemies',
				'Map',
				'World',
				'Terrain',
				'Water',
				'Collision',
			}) do
				pcall(function()
					PhysicsService:CollisionGroupSetCollidable(DIVE_NOCLIP_GROUP, other, false)
				end)
			end
			pcall(function()
				PhysicsService:CollisionGroupSetCollidable(DIVE_NOCLIP_GROUP, DIVE_NOCLIP_GROUP, false)
			end)
			diveNoclipGroupReady = true
		end

		local function diveNoclipModels()
			local models = {}
			local seen = {}
			local function add(m)
				if m and m.Parent and not seen[m] then
					seen[m] = true
					models[#models + 1] = m
				end
			end
			-- Character only — NEVER CharacterItems. Massless/PivotTo on weapons
			-- left the body welded to a world-frozen blade ("stuck to weapon").
			add(getMyCharacterModel())
			add(LocalPlayer.Character)
			return models
		end

		local function diveApplyNoclipParts()
			ensureDiveNoclipGroup()
			for _, model in ipairs(diveNoclipModels()) do
				for _, child in ipairs(model:GetDescendants()) do
					if child:IsA('BasePart') then
						if diveNoclipOrig[child] == nil then
							-- If already stuck in dive group, do not poison orig as false/dive.
							local alreadyDive = false
							pcall(function()
								alreadyDive = child.CollisionGroup == DIVE_NOCLIP_GROUP
							end)
							if alreadyDive then
								local solid = child.Name == 'HumanoidRootPart'
									or child.Name == 'UpperTorso'
									or child.Name == 'LowerTorso'
									or child.Name == 'Torso'
									or child.Name == 'Head'
								diveNoclipOrig[child] = solid
							else
								diveNoclipOrig[child] = child.CanCollide
							end
						end
						if diveNoclipGroups[child] == nil then
							local okG, groupName = pcall(function()
								return child.CollisionGroup
							end)
							if okG and type(groupName) == 'string' and groupName ~= '' and groupName ~= DIVE_NOCLIP_GROUP then
								diveNoclipGroups[child] = groupName
							else
								diveNoclipGroups[child] = 'Players'
							end
						end
						child.CanCollide = false
						child.CanTouch = false
						-- Do NOT set Massless — breaks assembly + CharacterItems welds.
						pcall(function()
							child.CollisionGroup = DIVE_NOCLIP_GROUP
						end)
					end
				end
			end
		end

		local function diveForceClipParts()
			for _, model in ipairs(diveNoclipModels()) do
				for _, child in ipairs(model:GetDescendants()) do
					if child:IsA('BasePart') then
						local solid = child.Name == 'HumanoidRootPart'
							or child.Name == 'UpperTorso'
							or child.Name == 'LowerTorso'
							or child.Name == 'Torso'
							or child.Name == 'Head'
						local orig = diveNoclipOrig[child]
						local group = diveNoclipGroups[child]
						if type(group) ~= 'string' or group == '' or group == DIVE_NOCLIP_GROUP then
							group = 'Players'
						end
						pcall(function()
							child.CollisionGroup = group
						end)
						if solid then
							child.CanCollide = true
						elseif orig ~= nil then
							child.CanCollide = orig == true
						end
						child.CanTouch = true
					end
				end
			end
			table.clear(diveNoclipOrig)
			table.clear(diveNoclipGroups)
		end
		getgenv().SB2DiveForceClip = diveForceClipParts

		local function diveSetFlyHumanoid(on)
			pcall(function()
				local model = getMyCharacterModel() or LocalPlayer.Character
				local hum = model and model:FindFirstChildOfClass('Humanoid')
				if not hum then
					return
				end
				if on then
					hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
					hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
					hum:SetStateEnabled(Enum.HumanoidStateType.Physics, false)
					hum.Sit = false
					hum.PlatformStand = true -- fly: no ground physics
					hum.AutoRotate = false
					pcall(function()
						-- Freefall + upright lock: Physics state is what tumbles you.
						hum:ChangeState(Enum.HumanoidStateType.Freefall)
					end)
				else
					hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true)
					hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, true)
					hum:SetStateEnabled(Enum.HumanoidStateType.Physics, true)
					hum.PlatformStand = false
					hum.AutoRotate = true
					pcall(function()
						hum:ChangeState(Enum.HumanoidStateType.GettingUp)
					end)
				end
			end)
		end
		local diveDashed = setmetatable({}, { __mode = 'k' })
		local diveSeenAt = setmetatable({}, { __mode = 'k' })
		local divePartSample = setmetatable({}, { __mode = 'k' })
		local diveTeleCache = { at = 0, hits = {}, origin = nil, nearR = 0 }
		local diveFleeing = false
		local diveNukeUntil = 0
		local diveNukeCooldownUntil = 0
		local diveNukeAnchor = nil
		local diveYaw = (((tonumber(LocalPlayer.UserId) or 1) % 12) / 12) * math.pi * 2
		local lastDiveStreamAt = 0
		local lastDiveMoveAt = 0
		local lastDiveHealAt = 0
		local lastDiveMendAt = 0
		local lastDiveHitAt = 0
		local lastDiveDebugAt = 0
		local diveMendingUntil = 0
		local diveMendingPos = nil
		local diveHpSamples = {}
		local diveElementCache = { id = nil, at = 0 }
		local diveStickMob = nil
		local diveStickRoot = nil
		local diveShouldRetarget = true
		local diveMobsFolderConns = {}
		local diveReturnCF = nil
		local diveRestoreGen = 0
		local diveHoldPos = nil
		local diveTween = nil
		local diveHoldConn = nil
		local diveStepConn = nil
		local lastDiveWritePos = nil
		local diveStreamPart = nil
		pcall(function()
			local oldVel = getgenv().SB2DiveLinVel
			if oldVel then
				oldVel:Destroy()
			end
		end)
		local diveLinVel = Instance.new('LinearVelocity')
		diveLinVel.Name = 'SB2DiveLinVel'
		diveLinVel.MaxForce = 1e5
		diveLinVel.VectorVelocity = Vector3.zero
		diveLinVel.RelativeTo = Enum.ActuatorRelativeTo.World
		getgenv().SB2DiveLinVel = diveLinVel
		-- Upright lock lives on getgenv — Combat IIFE is at Luau's 200-local limit.
		pcall(function()
			local oldAng = getgenv().SB2DiveAngLock
			if oldAng then
				oldAng:Destroy()
			end
			local oldAlign = getgenv().SB2DiveAlign
			if oldAlign then
				oldAlign:Destroy()
			end
		end)
		do
			-- Soft AlignOrientation only — AngularVelocity MaxTorque=huge + Rigidity
			-- fought CFrame writes on boss respawn and flung to 25k+ studs/s.
			local diveAlign = Instance.new('AlignOrientation')
			diveAlign.Name = 'SB2DiveAlign'
			diveAlign.Mode = Enum.OrientationAlignmentMode.OneAttachment
			diveAlign.RigidityEnabled = false
			diveAlign.Responsiveness = 25
			diveAlign.MaxTorque = 5e4
			getgenv().SB2DiveAlign = diveAlign
			getgenv().SB2DiveAngLock = nil
			getgenv().SB2DiveEnsureFlyAttachment = function(hrp)
				if not hrp then
					return nil
				end
				local att = hrp:FindFirstChild('SB2DiveAttachment')
					or hrp:FindFirstChild('RootAttachment')
					or hrp:FindFirstChildWhichIsA('Attachment')
				if not att then
					att = Instance.new('Attachment')
					att.Name = 'SB2DiveAttachment'
					att.Parent = hrp
				end
				return att
			end
			getgenv().SB2DiveAttachUprightLock = function(hrp, faceCf)
				if not hrp then
					return
				end
				pcall(function()
					local ensure = getgenv().SB2DiveEnsureFlyAttachment
					local att = type(ensure) == 'function' and ensure(hrp) or nil
					if not att then
						return
					end
					local align = getgenv().SB2DiveAlign
					if align then
						align.Attachment0 = att
						local orient = faceCf
						if typeof(orient) ~= 'CFrame' then
							orient = hrp.CFrame
						end
						local _, yaw = orient:ToEulerAnglesYXZ()
						align.CFrame = CFrame.fromEulerAnglesYXZ(0, yaw, 0)
						align.Parent = hrp
					end
					hrp.AssemblyAngularVelocity = Vector3.zero
				end)
			end
			getgenv().SB2DiveDetachUprightLock = function()
				pcall(function()
					local ang = getgenv().SB2DiveAngLock
					local align = getgenv().SB2DiveAlign
					if ang then
						ang.Parent = nil
						ang.Attachment0 = nil
					end
					if align then
						align.Parent = nil
						align.Attachment0 = nil
					end
				end)
			end
			getgenv().SB2DiveClampVelocity = function(hrp, reason)
				if not hrp then
					return false
				end
				local mag = hrp.AssemblyLinearVelocity.Magnitude
				if mag <= 420 then
					hrp.AssemblyAngularVelocity = Vector3.zero
					return false
				end
				--#region agent log
				pcall(function()
					if type(appendfile) ~= 'function' and type(writefile) ~= 'function' then
						return
					end
					local line = game:GetService('HttpService'):JSONEncode({
						sessionId = '7e9135',
						runId = 'fling-rail',
						hypothesisId = 'H1,H5',
						location = 'SB2DiveClampVelocity',
						message = 'capped runaway velocity',
						data = {
							reason = tostring(reason),
							mag = math.floor(mag + 0.5),
							y = math.floor(hrp.Position.Y + 0.5),
							diveOn = getgenv().SB2DiveFarmOn == true,
						},
						timestamp = math.floor(os.clock() * 1000),
					})
					if type(appendfile) == 'function' then
						appendfile('debug-7e9135.log', line .. '\n')
					else
						writefile('debug-7e9135.log', line .. '\n')
					end
				end)
				--#endregion
				hrp.AssemblyLinearVelocity = Vector3.zero
				hrp.AssemblyAngularVelocity = Vector3.zero
				local vel = getgenv().SB2DiveLinVel
				if vel then
					vel.VectorVelocity = Vector3.zero
				end
				return true
			end
		end
		local diveNoclipStepped = nil
		local diveNoclipHeartbeat = nil
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

		local function diveHealthFrac()
			local model = getMyCharacterModel()
			if not model then
				return 1
			end
			local entity = model:FindFirstChild('Entity')
			local h = entity and entity:FindFirstChild('Health')
			if h then
				local okCur, cur = pcall(function()
					return h.Value
				end)
				local maxV = nil
				-- SB2 uses IntConstrainedValue — max is MaxValue, not a sibling MaxHealth.
				pcall(function()
					if typeof(h.MaxValue) == 'number' and h.MaxValue > 0 then
						maxV = h.MaxValue
					end
				end)
				if not maxV then
					local m = entity and entity:FindFirstChild('MaxHealth')
					if m then
						pcall(function()
							if typeof(m.Value) == 'number' and m.Value > 0 then
								maxV = m.Value
							end
						end)
					end
				end
				if okCur and type(cur) == 'number' and type(maxV) == 'number' and maxV > 0 then
					return math.clamp(cur / maxV, 0, 1)
				end
			end
			local hum = model:FindFirstChildOfClass('Humanoid')
			if hum and hum.MaxHealth > 0 then
				return math.clamp(hum.Health / hum.MaxHealth, 0, 1)
			end
			return 1
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

		local function diveCastHealSkill(skillName, info, opts)
			opts = opts or {}
			local ok = fireUseSkill(skillName, info, {
				muteFor = 1.2,
				silentFail = true,
				ignoreGap = true,
				ignoreMobsGate = true,
				skipReadyCheck = opts.skipReadyCheck == true,
			})
			if ok then
				return true
			end
			local skills = getGameSkillsService()
			if skills and type(skills.UseSkill) == 'function' and gameSkillCanCast(skillName) ~= false then
				local directOk = pcall(skills.UseSkill, skillName)
				if directOk then
					local cd = info.cooldown or 2
					markSkillUsed(skillName, cd)
					return true
				end
			end
			return false
		end

		local function tryCastNamedHeal(skillName, reason, opts)
			opts = opts or {}
			-- Heals during Event dive even if AutoSkill was toggled off mid-fight.
			local diving = isToggleOn('DiveFarm') or getgenv().SB2DiveFarmOn == true
			if not skillName or not diving then
				return false
			end
			if not ownedSkill(skillName) then
				return false
			end
			syncSkillCdFromGame(skillName)
			local now = os.clock()
			local gap = opts.gap or 0.85
			local lastAt = opts.mend and lastDiveMendAt or lastDiveHealAt
			local gameReady = gameSkillCanCast(skillName)
			local mendExpired = opts.mend and os.clock() >= diveMendingUntil
			if now - lastAt < gap then
				if not (opts.force and (gameReady == true or mendExpired)) then
					return false
				end
			end
			if not isSkillReady(skillName) then
				return false
			end
			if gameReady == false then
				return false
			end
			local info = getSkillInfo(skillName)
			if getPlayerStamina() < (info.cost or 0) then
				return false
			end
			local ok = diveCastHealSkill(skillName, info, {})
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
			getgenv().SB2LastEventHeal = { skill = skillName, reason = reason, at = now, mend = opts.mend == true, hp = opts.hp }
			return true
		end

		local function tryCastEventHeal(reason, hp)
			hp = tonumber(hp) or diveHealthFrac()
			local under = reason == 'under' or reason == 'panic' or reason == 'low-hp'
			local burst = pickBurstHealName()
			local mend = pickMendHealName()
			if under then
				-- Under map: cast every owned heal the instant its game cooldown is ready.
				local order = {}
				local seen = {}
				local function queue(name, mendSlot)
					if not name or seen[name] then
						return
					end
					seen[name] = true
					order[#order + 1] = { name = name, mend = mendSlot == true }
				end
				queue(mend, true)
				queue(burst, false)
				for _, skillName in ipairs(HEAL_SKILL_PRIORITY) do
					if ownedSkill(skillName) then
						queue(skillName, skillName == MEND_HEAL_NAME)
					end
				end
				for _, slot in ipairs(order) do
					tryCastNamedHeal(slot.name, reason, {
						mend = slot.mend,
						gap = 0.3,
						hp = hp,
						force = true,
					})
				end
				return true
			end
			-- Burst Heal for emergency / poison ticks. Mending Spirit for overtime regen.
			local wantBurst = hp <= DIVE_HP_PANIC
				or hp <= DIVE_HP_FLEE
				or hp <= 0.55
			local wantMend = reason == 'poison'
				or reason == 'fire'
				or hp <= DIVE_POISON_HEAL
			if wantBurst and not burst then
				burst = mend
			end
			if wantBurst and burst then
				tryCastNamedHeal(burst, reason, { gap = 0.6, hp = hp })
			end
			if wantMend and mend then
				tryCastNamedHeal(mend, reason, { mend = true, gap = 1.2, hp = hp })
			end
			return true
		end
		getgenv().SB2TryCastEventHeal = tryCastEventHeal

		local function setDiveNoclip(on)
			getgenv().SB2DiveNoclipOn = on == true
			getgenv().SB2DiveFlyOn = on == true
			--#region agent log
			pcall(function()
				local hrp = getMyBringPart()
				local sampleCollide = hrp and hrp.CanCollide
				local sampleGroup = nil
				if hrp then
					pcall(function()
						sampleGroup = hrp.CollisionGroup
					end)
				end
				local origN, groupN = 0, 0
				for _ in pairs(diveNoclipOrig) do
					origN += 1
				end
				for _ in pairs(diveNoclipGroups) do
					groupN += 1
				end
				local line = game:GetService('HttpService'):JSONEncode({
					sessionId = '7e9135',
					runId = 'noclip-off',
					hypothesisId = 'H3,H4,H5',
					location = 'setDiveNoclip',
					message = on and 'noclip ON' or 'noclip OFF',
					data = {
						on = on == true,
						farmOn = getgenv().SB2DiveFarmOn == true,
						toggle = isToggleOn('DiveFarm'),
						hrpCollide = sampleCollide,
						hrpGroup = sampleGroup,
						origN = origN,
						groupN = groupN,
						stepped = diveNoclipStepped ~= nil,
						hb = diveNoclipHeartbeat ~= nil,
					},
					timestamp = math.floor(os.clock() * 1000),
				})
				if type(appendfile) == 'function' then
					appendfile('debug-7e9135.log', line .. '\n')
				end
			end)
			--#endregion
			if on then
				setDiveMobIntangible(true)
				diveApplyNoclipParts()
				diveSetFlyHumanoid(true)
				if not diveNoclipStepped then
					diveNoclipStepped = RunService.Stepped:Connect(function()
						if getgenv().SB2DiveFarmOn ~= true and not isToggleOn('DiveFarm') then
							return
						end
						diveApplyNoclipParts()
						diveSetFlyHumanoid(true)
						local hrp = getMyBringPart()
						if hrp then
							-- Keep unanchored so the model + weapon welds stay one assembly.
							hrp.Anchored = false
							hrp.AssemblyAngularVelocity = Vector3.zero
							local clampVel = getgenv().SB2DiveClampVelocity
							if type(clampVel) == 'function' then
								clampVel(hrp, 'stepped')
							end
							local attachLock = getgenv().SB2DiveAttachUprightLock
							if type(attachLock) == 'function' then
								attachLock(hrp, hrp.CFrame)
							end
						end
					end)
					getgenv().SB2DiveNoclipStepped = diveNoclipStepped
				end
				if not diveNoclipHeartbeat then
					diveNoclipHeartbeat = RunService.Heartbeat:Connect(function()
						if getgenv().SB2DiveFarmOn ~= true and not isToggleOn('DiveFarm') then
							return
						end
						diveApplyNoclipParts()
						local hrp = getMyBringPart()
						if hrp then
							local clampVel = getgenv().SB2DiveClampVelocity
							if type(clampVel) == 'function' then
								clampVel(hrp, 'heartbeat')
							else
								hrp.AssemblyAngularVelocity = Vector3.zero
							end
						end
					end)
					getgenv().SB2DiveNoclipHeartbeat = diveNoclipHeartbeat
				end
				local hrp = getMyBringPart()
				if hrp then
					pcall(function()
						hrp.Anchored = false
						local ensure = getgenv().SB2DiveEnsureFlyAttachment
						local att = type(ensure) == 'function' and ensure(hrp) or nil
						-- Soft anti-grav fly assist — not a hard freeze (MaxForce+0 vel stuck you).
						diveLinVel.Attachment0 = att
						diveLinVel.MaxForce = 1e5
						diveLinVel.VectorVelocity = Vector3.zero
						diveLinVel.Parent = hrp
						local attachLock = getgenv().SB2DiveAttachUprightLock
						if type(attachLock) == 'function' then
							attachLock(hrp, hrp.CFrame)
						end
					end)
					if diveAnchorHook then
						pcall(function()
							diveAnchorHook:Disconnect()
						end)
						diveAnchorHook = nil
					end
				end
			else
				setDiveMobIntangible(false)
				if diveNoclipStepped then
					pcall(function()
						diveNoclipStepped:Disconnect()
					end)
					diveNoclipStepped = nil
				end
				if diveNoclipHeartbeat then
					pcall(function()
						diveNoclipHeartbeat:Disconnect()
					end)
					diveNoclipHeartbeat = nil
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
					diveLinVel.VectorVelocity = Vector3.zero
				end)
				local detachLock = getgenv().SB2DiveDetachUprightLock
				if type(detachLock) == 'function' then
					detachLock()
				end
				-- Hard clip — never trust poisoned orig/group snapshots alone.
				diveForceClipParts()
				pcall(function()
					local hrp = getMyBringPart()
					if hrp then
						hrp.Anchored = false
						hrp.AssemblyLinearVelocity = Vector3.zero
						hrp.AssemblyAngularVelocity = Vector3.zero
					end
				end)
				diveSetFlyHumanoid(false)
				getgenv().SB2DiveNoclipStepped = nil
				getgenv().SB2DiveNoclipHeartbeat = nil
			end
			getgenv().SB2DiveSetNoclip = setDiveNoclip
		end

		local function diveCancelTween()
			if diveTween then
				pcall(function()
					diveTween:Cancel()
				end)
				diveTween = nil
			end
		end

		local function diveWriteCFrame(hrp, dest, lookAt, writeOpts)
			if not hrp or not dest then
				return false
			end
			writeOpts = writeOpts or {}
			-- Reject absurd blinks (boss respawn / void) that explode physics.
			local fromPos = hrp.Position
			local jump = (dest - fromPos).Magnitude
			if jump > 2500 or math.abs(dest.Y - fromPos.Y) > 800 then
				--#region agent log
				pcall(function()
					local line = game:GetService('HttpService'):JSONEncode({
						sessionId = '7e9135',
						runId = 'fling-rail',
						hypothesisId = 'H2,H4',
						location = 'diveWriteCFrame',
						message = 'rejected absurd dest',
						data = {
							jump = math.floor(jump + 0.5),
							fromY = math.floor(fromPos.Y + 0.5),
							toY = math.floor(dest.Y + 0.5),
						},
						timestamp = math.floor(os.clock() * 1000),
					})
					if type(appendfile) == 'function' then
						appendfile('debug-7e9135.log', line .. '\n')
					end
				end)
				--#endregion
				return false
			end
			if not writeOpts.force and typeof(lastDiveWritePos) == 'Vector3' then
				if (dest - lastDiveWritePos).Magnitude < DIVE_WRITE_DEBOUNCE then
					return true
				end
			end
			local anchor = diveLastCluster
			if not writeOpts.noClamp and anchor then
				dest = diveClampGoal(dest, anchor, writeOpts.clamp or {
					yRef = anchor.Y,
					yPad = 10,
					yMin = anchor.Y - 6,
					yMax = anchor.Y + 6,
				})
			end
			diveHoldPos = nil
			pcall(function()
				local look = lookAt or (diveStickRoot and diveStickRoot.Parent and diveStickRoot.Position) or (dest - Vector3.new(0, DIVE_HOVER, 0))
				local cf
				local preserve = writeOpts.preserveFacing
				if preserve == nil and getgenv().SB2DiveFarmOn then
					preserve = not writeOpts.forceLook
				end
				if preserve then
					cf = CFrame.new(dest) * (hrp.CFrame - hrp.CFrame.Position)
				else
					cf = CFrame.lookAt(dest, look)
				end
				-- HRP only — PivotTo desyncs CharacterItems welds (stuck-to-weapon).
				local toDest = dest - hrp.Position
				hrp.Anchored = false
				hrp.CFrame = cf
				if toDest.Magnitude > 2 then
					local speed = math.clamp(toDest.Magnitude * 10, 50, DIVE_TWEEN_SPEED * 1.25)
					local vel = toDest.Unit * speed
					-- Vertical LV + CFrame Y snaps fight each other → bobbing.
					-- Y is CFrame-pinned; LV only assists XZ (flee may allow vertical).
					if writeOpts.allowVerticalVel ~= true then
						vel = Vector3.new(vel.X, 0, vel.Z)
					end
					diveLinVel.VectorVelocity = vel
				else
					-- Soft hover hold (anti-grav), not a hard freeze.
					diveLinVel.VectorVelocity = Vector3.zero
					local v = hrp.AssemblyLinearVelocity
					hrp.AssemblyLinearVelocity = Vector3.new(v.X, 0, v.Z)
				end
				diveLinVel.MaxForce = 1e5
				if diveLinVel.Parent ~= hrp then
					local ensure = getgenv().SB2DiveEnsureFlyAttachment
					local att = type(ensure) == 'function' and ensure(hrp) or nil
					diveLinVel.Attachment0 = att
					diveLinVel.Parent = hrp
				end
				local attachLock = getgenv().SB2DiveAttachUprightLock
				if type(attachLock) == 'function' then
					attachLock(hrp, cf)
				end
				local clampVel = getgenv().SB2DiveClampVelocity
				if type(clampVel) == 'function' then
					clampVel(hrp, 'write')
				else
					hrp.AssemblyAngularVelocity = Vector3.zero
				end
				--#region agent log
				if math.abs(hrp.AssemblyLinearVelocity.Y) > 12 or math.abs(toDest.Y) > 3 then
					pcall(function()
						local now = os.clock()
						if (now - (getgenv().SB2DbgBobLogAt or 0)) < 0.8 then
							return
						end
						getgenv().SB2DbgBobLogAt = now
						local line = game:GetService('HttpService'):JSONEncode({
							sessionId = '7e9135',
							runId = 'bob-fix',
							hypothesisId = 'H-bob',
							location = 'diveWriteCFrame',
							message = 'y write',
							data = {
								destY = math.floor(dest.Y * 10 + 0.5) / 10,
								posY = math.floor(hrp.Position.Y * 10 + 0.5) / 10,
								vy = math.floor(hrp.AssemblyLinearVelocity.Y * 10 + 0.5) / 10,
								lvY = diveLinVel.VectorVelocity.Y,
								allowVert = writeOpts.allowVerticalVel == true,
							},
							timestamp = math.floor(os.clock() * 1000),
						})
						if type(appendfile) == 'function' then
							appendfile('debug-7e9135.log', line .. '\n')
						end
					end)
				end
				--#endregion
				lastDiveWritePos = dest
			end)
			return true
		end

		local function diveSnapTo(hrp, goalPos, lookAt, clampOpts)
			if not hrp or not goalPos then
				return false
			end
			diveWriteCFrame(hrp, goalPos, lookAt, { clamp = clampOpts })
			pcall(function()
				lockReplicationFocus(getMyCharacterModel())
			end)
			task.wait(0.05)
			return hrp and hrp.Parent ~= nil
		end

		local function diveReassertHold()
			if not getgenv().SB2DiveFarmOn or not diveHoldPos then
				return
			end
			local hrp = getMyBringPart()
			if not hrp then
				return
			end
			if (hrp.Position - diveHoldPos).Magnitude > 1.25 then
				diveWriteCFrame(hrp, diveHoldPos)
			end
		end

		local function diveEnsureHoldConns()
			if not diveHoldConn then
				pcall(function()
					RunService:UnbindFromRenderStep('SB2DiveHold')
				end)
				pcall(function()
					RunService:BindToRenderStep('SB2DiveHold', Enum.RenderPriority.Last.Value, diveReassertHold)
				end)
				diveHoldConn = true
			end
			if not diveStepConn then
				diveStepConn = RunService.Stepped:Connect(diveReassertHold)
			end
		end

		local function diveClearHoldConns()
			diveHoldPos = nil
			lastDiveWritePos = nil
			diveCancelTween()
			if diveHoldConn then
				pcall(function()
					RunService:UnbindFromRenderStep('SB2DiveHold')
				end)
				diveHoldConn = nil
			end
			if diveStepConn then
				pcall(function()
					diveStepConn:Disconnect()
				end)
				diveStepConn = nil
			end
		end

		local function diveApplyCFrame(hrp, dest)
			diveCancelTween()
			diveWriteCFrame(hrp, dest)
			diveEnsureHoldConns()
		end

		-- Vacuum move: snap when far, else lerp toward hover stick.
		local function diveFlyStep(hrp, targetPos, dt)
			if not hrp or not targetPos then
				return
			end
			setDiveNoclip(true)
			diveEnsureHoldConns()
			dt = tonumber(dt) or 0.016
			if dt <= 0 then
				dt = 1 / 60
			end
			local pos = hrp.Position
			local toTarget = targetPos - pos
			local totalDist = toTarget.Magnitude
			if totalDist == 0 then
				diveHoldPos = targetPos
				return
			end
			local lookAt = (diveStickRoot and diveStickRoot.Parent and diveStickRoot.Position)
				or (targetPos - Vector3.new(0, DIVE_HOVER, 0))
			if totalDist > DIVE_ARRIVE + 2 or math.abs(toTarget.Y) > 8 then
				diveWriteCFrame(hrp, targetPos, lookAt)
				return
			end
			local speed = DIVE_TWEEN_SPEED
			local step = math.min(totalDist, speed * dt)
			local nextPos = pos + toTarget.Unit * step
			diveWriteCFrame(hrp, nextPos, lookAt)
		end

		local function diveMoveTo(hrp, pos, _look)
			diveFlyStep(hrp, pos, 1)
		end

		-- Real world mob position (prefer cache when client-stacked near feet).
		local function diveMobWorldPos(mob, root, origin)
			if not root then
				return nil
			end
			if origin then
				pcall(cacheMobRealPositions, origin)
				local ok, cf = pcall(getMobAttackCFrame, mob, root, origin)
				if ok and typeof(cf) == 'CFrame' then
					return cf.Position
				end
			end
			local cached = mobRealCF[mob]
			if typeof(cached) == 'CFrame' then
				return cached.Position
			end
			if origin and looksClientStacked(origin) then
				local dx = root.Position.X - origin.X
				local dz = root.Position.Z - origin.Z
				if (dx * dx + dz * dz) < (40 * 40) then
					return nil
				end
			end
			return root.Position
		end

		-- Vacuum hover stick: prefer attack CF (real world when stacked) so
		-- AutoAttack XZ range and our hover share the same target.
		local function diveVacuumTargetPos(mob, root, hrp, horizontal)
			if not root or not hrp then
				return nil
			end
			local origin = hrp.Position
			pcall(cacheMobRealPositions, origin)
			local atkCF = getMobAttackCFrame(mob, root, origin)
			local worldPos = atkCF and atkCF.Position or root.Position
			-- Not stacked: follow the live root (mob can walk).
			if not looksClientStacked(origin) then
				worldPos = root.Position
			end
			local hover = diveFarmAboveStuds()
			local targetPos = Vector3.new(worldPos.X, worldPos.Y + hover, worldPos.Z)
			local bv = root:FindFirstChild('BodyVelocity')
			if bv then
				local vel = nil
				pcall(function()
					if typeof(bv.VectorVelocity) == 'Vector3' and bv.VectorVelocity.Magnitude > 0 then
						vel = bv.VectorVelocity
					elseif typeof(bv.Velocity) == 'Vector3' and bv.Velocity.Magnitude > 0 then
						vel = bv.Velocity
					end
				end)
				if vel and vel.Magnitude > 0 then
					local lead = vel.Unit
					targetPos = Vector3.new(targetPos.X + lead.X, targetPos.Y, targetPos.Z + lead.Z)
				end
			end
			horizontal = tonumber(horizontal) or 0
			if horizontal > 0 then
				local diff = Vector3.new(origin.X - worldPos.X, 0, origin.Z - worldPos.Z)
				if diff.Magnitude > 0.05 then
					local u = diff.Unit * horizontal
					targetPos = Vector3.new(targetPos.X + u.X, targetPos.Y, targetPos.Z + u.Z)
				end
			end
			return targetPos
		end

		-- Hit from the dive loop (like AutoFarm vacuum) so we don't depend on
		-- AutoAttack alone when hover XZ and attack-CF XZ briefly disagree.
		local function divePulseAttack()
			local now = os.clock()
			if now - lastDiveHitAt < DIVE_HIT_DELAY then
				return
			end
			lastDiveHitAt = now
			local attackName = nil
			if isToggleOn('AutoSkill') then
				pcall(function()
					attackName = ensureSkillWindow()
				end)
			end
			if diveStickMob and diveStickMob.Parent and not isDeadMob(diveStickMob) then
				pcall(fireMobAttack, diveStickMob, attackName)
			end
			local mobsRoot = workspace:FindFirstChild('Mobs')
			local hrp = getMyBringPart()
			if not mobsRoot or not hrp then
				return
			end
			local origin = hrp.Position
			local aura = math.max(80, AUTO_ATTACK_RANGE)
			local auraSq = aura * aura
			local tagged = 0
			for _, mob in ipairs(mobsRoot:GetChildren()) do
				if tagged >= MAX_ATTACKS_PER_TICK then
					break
				end
				if mob == diveStickMob or isDeadMob(mob) or shouldSkipMob(mob) then
					continue
				end
				local nm = string.lower(tostring(mob.Name or ''))
				if string.find(nm, 'chest', 1, true) or string.find(nm, 'crate', 1, true) then
					continue
				end
				local root = getMobRoot(mob)
				if not root then
					continue
				end
				local atkCF = getMobAttackCFrame(mob, root, origin)
				local dx = atkCF.Position.X - origin.X
				local dz = atkCF.Position.Z - origin.Z
				if (dx * dx + dz * dz) > auraSq then
					continue
				end
				if fireMobAttack(mob, attackName) then
					tagged += 1
				end
			end
		end

		local function diveHoverY(clusterPos)
			local above = diveFarmAboveStuds()
			if not clusterPos then
				return above
			end
			return clusterPos.Y + above
		end

		local function divePreviewGroundY(xzPos)
			local hrp = getMyBringPart()
			local base = typeof(xzPos) == 'Vector3' and xzPos
				or (hrp and hrp.Position)
				or Vector3.zero
			local ref = diveReturnCF or getgenv().SB2DiveReturnCF
			local startY = (typeof(ref) == 'CFrame' and ref.Position.Y) or base.Y
			local origin = Vector3.new(base.X, startY + 40, base.Z)
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			local exclude = {}
			local model = getMyCharacterModel()
			if model then
				exclude[#exclude + 1] = model
			end
			if LocalPlayer.Character then
				exclude[#exclude + 1] = LocalPlayer.Character
			end
			params.FilterDescendantsInstances = exclude
			local hit = workspace:Raycast(origin, Vector3.new(0, -600, 0), params)
			if hit then
				return hit.Position.Y
			end
			return startY
		end

		local function diveIdleHoverPos(hrp)
			if not hrp then
				return nil
			end
			local groundY = divePreviewGroundY(hrp.Position)
			-- Always prefer the Farm height slider for live preview / testing
			-- (even when Auto farm height is ON — combat still uses auto).
			local above = math.clamp(diveOptNumber('DiveFarmHeight', diveFarmAboveStuds()), -40, 80)
			local pos = Vector3.new(hrp.Position.X, groundY + math.max(above, 0), hrp.Position.Z)
			if diveFarmZone() and not divePosInFarmZone(hrp.Position) then
				local center = diveFarmZoneCenter(groundY + math.max(above, 0))
				if center then
					pos = center
				end
			else
				pos = diveClampToFarmZone(pos)
			end
			return pos
		end

		local function diveStayUnder(hrp, xzPos, dt)
			if not hrp or not xzPos then
				return
			end
			setDiveNoclip(true)
			if diveStickMob and diveStickRoot and diveStickRoot.Parent then
				local dest = diveVacuumTargetPos(diveStickMob, diveStickRoot, hrp, 0)
				if dest then
					diveFlyStep(hrp, diveClampToFarmZone(dest), dt or 1)
					return
				end
			end
			local goal = diveClampToFarmZone(Vector3.new(xzPos.X, diveHoverY(xzPos), xzPos.Z))
			diveFlyStep(hrp, goal, dt or 1)
		end

		local function captureDiveReturnCF()
			local hrp = getMyBringPart()
			if not hrp then
				return
			end
			-- Prefer standing on ground so disable returns to floor, not mid-air hover.
			local groundY = divePreviewGroundY(hrp.Position)
			local pos = Vector3.new(hrp.Position.X, groundY + 3, hrp.Position.Z)
			diveReturnCF = CFrame.new(pos) * (hrp.CFrame - hrp.CFrame.Position)
			getgenv().SB2DiveReturnCF = diveReturnCF
		end

		local function restoreDiveReturnCF()
			local cf = diveReturnCF or getgenv().SB2DiveReturnCF
			diveReturnCF = nil
			getgenv().SB2DiveReturnCF = nil
			--#region agent log
			pcall(function()
				local line = game:GetService('HttpService'):JSONEncode({
					sessionId = '7e9135',
					runId = 'noclip-off',
					hypothesisId = 'H1,H2',
					location = 'restoreDiveReturnCF',
					message = 'restore enter',
					data = {
						cfOk = typeof(cf) == 'CFrame',
						cfType = typeof(cf),
						farmOn = getgenv().SB2DiveFarmOn == true,
						toggle = isToggleOn('DiveFarm'),
						noclipOn = getgenv().SB2DiveNoclipOn == true,
						gen = diveRestoreGen,
					},
					timestamp = math.floor(os.clock() * 1000),
				})
				if type(appendfile) == 'function' then
					appendfile('debug-7e9135.log', line .. '\n')
				end
			end)
			--#endregion
			if typeof(cf) ~= 'CFrame' then
				--#region agent log
				pcall(function()
					local line = game:GetService('HttpService'):JSONEncode({
						sessionId = '7e9135',
						runId = 'noclip-off',
						hypothesisId = 'H1',
						location = 'restoreDiveReturnCF',
						message = 'cf missing — force clip',
						data = { cfType = typeof(cf) },
						timestamp = math.floor(os.clock() * 1000),
					})
					if type(appendfile) == 'function' then
						appendfile('debug-7e9135.log', line .. '\n')
					end
				end)
				--#endregion
				setDiveNoclip(false)
				return
			end
			diveRestoreGen += 1
			local gen = diveRestoreGen
			task.spawn(function()
				-- Do NOT setDiveNoclip(true) here — that re-snapshots CanCollide=false /
				-- SB2DiveNoclip as "original" and permanently poisons restore.
				-- Parts are already noclip from the farm session until we clip below.
				local groundY = divePreviewGroundY(cf.Position)
				local destPos = Vector3.new(cf.Position.X, groundY + 3, cf.Position.Z)
				local dest = CFrame.new(destPos) * (cf - cf.Position)
				-- Immediate snap so disable feels instant.
				pcall(function()
					local hrp = getMyBringPart()
					if hrp then
						hrp.Anchored = false
						hrp.CFrame = dest
						hrp.AssemblyLinearVelocity = Vector3.zero
						hrp.AssemblyAngularVelocity = Vector3.zero
					end
				end)
				for _ = 1, 24 do
					if gen ~= diveRestoreGen or getgenv().SB2DiveFarmOn then
						--#region agent log
						pcall(function()
							local line = game:GetService('HttpService'):JSONEncode({
								sessionId = '7e9135',
								runId = 'noclip-off',
								hypothesisId = 'H2',
								location = 'restoreDiveReturnCF',
								message = 'early exit mid-loop',
								data = {
									gen = gen,
									curGen = diveRestoreGen,
									farmOn = getgenv().SB2DiveFarmOn == true,
									noclipOn = getgenv().SB2DiveNoclipOn == true,
								},
								timestamp = math.floor(os.clock() * 1000),
							})
							if type(appendfile) == 'function' then
								appendfile('debug-7e9135.log', line .. '\n')
							end
						end)
						--#endregion
						if getgenv().SB2DiveFarmOn ~= true and not isToggleOn('DiveFarm') then
							setDiveNoclip(false)
						end
						return
					end
					local hrp = getMyBringPart()
					if not hrp then
						break
					end
					pcall(function()
						hrp.Anchored = false
						hrp.CFrame = dest
						hrp.AssemblyLinearVelocity = Vector3.zero
						hrp.AssemblyAngularVelocity = Vector3.zero
					end)
					if (hrp.Position - dest.Position).Magnitude <= 6 then
						break
					end
					RunService.Heartbeat:Wait()
				end
				if gen ~= diveRestoreGen or getgenv().SB2DiveFarmOn then
					--#region agent log
					pcall(function()
						local line = game:GetService('HttpService'):JSONEncode({
							sessionId = '7e9135',
							runId = 'noclip-off',
							hypothesisId = 'H2',
							location = 'restoreDiveReturnCF',
							message = 'early exit pre-clip',
							data = {
								gen = gen,
								curGen = diveRestoreGen,
								farmOn = getgenv().SB2DiveFarmOn == true,
								noclipOn = getgenv().SB2DiveNoclipOn == true,
							},
							timestamp = math.floor(os.clock() * 1000),
						})
						if type(appendfile) == 'function' then
							appendfile('debug-7e9135.log', line .. '\n')
						end
					end)
					--#endregion
					if getgenv().SB2DiveFarmOn ~= true and not isToggleOn('DiveFarm') then
						setDiveNoclip(false)
					end
					return
				end
				setDiveNoclip(false)
				--#region agent log
				pcall(function()
					local hrp = getMyBringPart()
					local line = game:GetService('HttpService'):JSONEncode({
						sessionId = '7e9135',
						runId = 'noclip-off',
						hypothesisId = 'H3,H4',
						location = 'restoreDiveReturnCF',
						message = 'restore done',
						data = {
							noclipOn = getgenv().SB2DiveNoclipOn == true,
							hrpCollide = hrp and hrp.CanCollide,
							hrpGroup = hrp and hrp.CollisionGroup,
						},
						timestamp = math.floor(os.clock() * 1000),
					})
					if type(appendfile) == 'function' then
						appendfile('debug-7e9135.log', line .. '\n')
					end
				end)
				--#endregion
				pcall(function()
					LocalPlayer:RequestStreamAroundAsync(dest.Position, 40)
				end)
			end)
		end

		local function diveFocusStream(cluster)
			if not cluster then
				return
			end
			-- Stream mobs near the fight — NEVER move ReplicationFocus off the player
			-- (that desyncs the character mesh from HRP while we blink around).
			pcall(function()
				LocalPlayer:RequestStreamAroundAsync(cluster, DIVE_STREAM_RADIUS)
			end)
			pcall(function()
				lockReplicationFocus(getMyCharacterModel())
			end)
		end

		local diveLastCluster = nil

		local function diveArenaRefY()
			local cf = diveReturnCF or getgenv().SB2DiveReturnCF
			if typeof(cf) == 'CFrame' then
				return cf.Position.Y
			end
			if diveLastCluster then
				return diveLastCluster.Y
			end
			local hrp = getMyBringPart()
			if hrp then
				return hrp.Position.Y
			end
			return 0
		end

		-- Never chase client-flinged boss parts into the skybox / void.
		local function diveClampGoal(goalPos, anchor, opts)
			opts = opts or {}
			if typeof(goalPos) ~= 'Vector3' or typeof(anchor) ~= 'Vector3' then
				return goalPos
			end
			local flatMax = opts.flatMax or DIVE_SAFE_FLAT
			local yRef = opts.yRef or anchor.Y
			local yPad = opts.yPad or 10
			local yMin = opts.yMin
			local yMax = opts.yMax
			if yMin == nil then
				local under = diveFleeUnderDepth(false)
				if opts.allowUnder and type(opts.floorY) == 'number' then
					yMin = opts.floorY - under
				else
					yMin = yRef - (opts.allowUnder and under or yPad)
				end
			end
			if yMax == nil then
				yMax = yRef + yPad
			end
			local y = math.clamp(goalPos.Y, yMin, yMax)
			local dx = goalPos.X - anchor.X
			local dz = goalPos.Z - anchor.Z
			local flat = math.sqrt(dx * dx + dz * dz)
			if flat > flatMax and flat > 0.01 then
				local s = flatMax / flat
				dx *= s
				dz *= s
			end
			return Vector3.new(anchor.X + dx, y, anchor.Z + dz)
		end

		local function diveFarmZone()
			return DIVE_FARM_ZONES[game.PlaceId]
		end

		local function diveBossSpawnPos(zone)
			zone = zone or diveFarmZone()
			if not zone then
				return nil
			end
			local m = workspace:FindFirstChild(zone.bossSpawnName or 'ASpawnBoss')
			if not m then
				return nil
			end
			local ok, p = pcall(function()
				return m:GetPivot().Position
			end)
			if ok and typeof(p) == 'Vector3' then
				return p
			end
			return nil
		end

		local function divePosInFarmZone(pos)
			local zone = diveFarmZone()
			if not zone or typeof(pos) ~= 'Vector3' then
				return true
			end
			if pos.X < zone.minX or pos.X > zone.maxX or pos.Z < zone.minZ or pos.Z > zone.maxZ then
				return false
			end
			local boss = diveBossSpawnPos(zone)
			local r = tonumber(zone.bossExcludeRadius) or 0
			if boss and r > 0 then
				local dx = pos.X - boss.X
				local dz = pos.Z - boss.Z
				if (dx * dx + dz * dz) <= (r * r) then
					return false
				end
			end
			return true
		end

		local function diveClampToFarmZone(pos)
			local zone = diveFarmZone()
			if not zone or typeof(pos) ~= 'Vector3' then
				return pos
			end
			local inset = math.max(0, tonumber(zone.edgeInset) or 0)
			local minX, maxX = zone.minX, zone.maxX
			local minZ, maxZ = zone.minZ, zone.maxZ
			local outside = pos.X < minX or pos.X > maxX or pos.Z < minZ or pos.Z > maxZ
			-- Only hard-clamp when leaving the pad. Pull inward past the wall so
			-- we never park exactly on the boss-side edge (freeze look).
			local x, z = pos.X, pos.Z
			if outside then
				x = math.clamp(pos.X, minX + inset, maxX - inset)
				z = math.clamp(pos.Z, minZ + inset, maxZ - inset)
			end
			local out = Vector3.new(x, pos.Y, z)
			local boss = diveBossSpawnPos(zone)
			local r = tonumber(zone.bossExcludeRadius) or 0
			if boss and r > 0 then
				local dx = out.X - boss.X
				local dz = out.Z - boss.Z
				local d2 = dx * dx + dz * dz
				if d2 < (r * r) then
					-- Always retreat toward maze center — radial push could pin on the rim.
					out = Vector3.new((minX + maxX) * 0.5, out.Y, (minZ + maxZ) * 0.5)
				end
			end
			return out
		end

		local function diveFarmZoneCenter(y)
			local zone = diveFarmZone()
			if not zone then
				return nil
			end
			return Vector3.new(
				(zone.minX + zone.maxX) * 0.5,
				y or 1250,
				(zone.minZ + zone.maxZ) * 0.5
			)
		end

		local diveRoamGoal = nil
		local diveRoamUntil = 0

		local function diveRoamFarmPos(hrp)
			local zone = diveFarmZone()
			if not zone or not hrp then
				return diveIdleHoverPos(hrp)
			end
			local groundY = divePreviewGroundY(hrp.Position)
			local above = math.clamp(diveOptNumber('DiveFarmHeight', diveFarmAboveStuds()), -40, 80)
			local y = groundY + math.max(above, 0)
			local inset = math.max(40, tonumber(zone.edgeInset) or 55)
			local spanX = (zone.maxX - zone.minX) - inset * 2
			local spanZ = (zone.maxZ - zone.minZ) - inset * 2
			if spanX < 20 or spanZ < 20 then
				return diveFarmZoneCenter(y)
			end
			local x = zone.minX + inset + math.random() * spanX
			local z = zone.minZ + inset + math.random() * spanZ
			return Vector3.new(x, y, z)
		end

		local function diveSanitizeGoal(goalPos, preferY)
			if typeof(goalPos) ~= 'Vector3' then
				return goalPos
			end
			local refY = preferY
			if type(refY) ~= 'number' then
				refY = diveArenaRefY()
			end
			local y = goalPos.Y
			if y > refY + DIVE_SAFE_Y then
				y = refY + DIVE_SAFE_Y
			else
				local under = diveFleeUnderDepth(false)
				if y < refY - under then
					y = refY - under
				end
			end
			return diveClampToFarmZone(Vector3.new(goalPos.X, y, goalPos.Z))
		end

		local function clampNearCluster(pos, cluster, maxDist)
			maxDist = math.min(maxDist or DIVE_SAFE_FLAT, DIVE_SAFE_FLAT)
			local flat = Vector3.new(pos.X - cluster.X, 0, pos.Z - cluster.Z)
			if flat.Magnitude <= maxDist then
				return diveClampGoal(Vector3.new(pos.X, pos.Y, pos.Z), cluster, { yRef = cluster.Y })
			end
			local u = flat.Unit * maxDist
			return diveClampGoal(Vector3.new(cluster.X + u.X, pos.Y, cluster.Z + u.Z), cluster, { yRef = cluster.Y })
		end

		local function diveShouldSkipMob(mob)
			if shouldSkipMob(mob) then
				return true
			end
			local name = string.lower(tostring(mob.Name or ''))
			-- Chests / crates are in Mobs but are not event targets.
			if string.find(name, 'chest', 1, true) or string.find(name, 'crate', 1, true) then
				return true
			end
			local zone = diveFarmZone()
			if zone then
				if zone.skipBosses and isBossMob(mob) then
					return true
				end
				local root = getMobRoot(mob)
				local pos = root and root.Position
				if typeof(pos) == 'Vector3' and not divePosInFarmZone(pos) then
					return true
				end
			end
			return false
		end

		local function diveLiveMobs()
			local mobsRoot = workspace:FindFirstChild('Mobs')
			if not mobsRoot then
				return {}
			end
			local origin = nil
			local hrp = getMyBringPart()
			if hrp then
				origin = hrp.Position
				pcall(cacheMobRealPositions, origin)
			end
			local stacked = origin and looksClientStacked(origin)
			local out = {}
			for _, mob in ipairs(mobsRoot:GetChildren()) do
				if isDeadMob(mob) or diveShouldSkipMob(mob) then
					continue
				end
				local root = getMobRoot(mob)
				if not root then
					continue
				end
				local pos = diveMobWorldPos(mob, root, origin)
				if not pos then
					continue
				end
				-- While stacked with no real cache yet, root.Position is your feet — skip.
				if stacked and origin and not mobRealCF[mob] then
					local dx = pos.X - origin.X
					local dz = pos.Z - origin.Z
					if (dx * dx + dz * dz) < (35 * 35) then
						continue
					end
				end
				out[#out + 1] = { mob = mob, pos = pos }
			end
			return out
		end

		-- Stick to one live mob (Bluu). Pack radius only for aura/flee math.
		local function diveFocus(origin)
			if origin then
				pcall(cacheMobRealPositions, origin)
			end
			local entries = diveLiveMobs()
			if #entries == 0 then
				diveStickMob = nil
				diveStickRoot = nil
				return nil, 0, 0, nil
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
				local ref = diveLastCluster or origin
				for i = 1, #entries do
					local e = entries[i]
					-- Prefer mobs we have a real-world cache for (avoids void dive).
					local score = 0
					if mobRealCF[e.mob] then
						score = -1e6
					end
					local d = 0
					if ref then
						local dx = e.pos.X - ref.X
						local dz = e.pos.Z - ref.Z
						d = math.sqrt(dx * dx + dz * dz)
					end
					local key = score + d
					if key < bestD then
						best, bestD = e, key
					end
				end
				stick = best
				diveStickMob = stick and stick.mob or nil
			end
			if not stick then
				diveStickRoot = nil
				return nil, 0, 0, nil
			end
			for i = 1, #entries do
				if entries[i].mob == stick.mob then
					stick = entries[i]
					break
				end
			end
			local root = getMobRoot(stick.mob)
			diveStickRoot = root
			-- Prefer live root world pos (Bluu) when not client-stacked; else cached.
			local stickPos = stick.pos
			if root and origin and not looksClientStacked(origin) then
				stickPos = root.Position
			elseif root and mobRealCF[stick.mob] then
				stickPos = mobRealCF[stick.mob].Position
			end
			local aura = AUTO_ATTACK_RANGE
			if getgenv().SB2DiveFarmOn then
				aura = math.max(aura, SKILL_HIT_RANGE)
			end
			local n, packR = 0, 0
			for i = 1, #entries do
				local e = entries[i]
				local dx = e.pos.X - stickPos.X
				local dz = e.pos.Z - stickPos.Z
				local d = math.sqrt(dx * dx + dz * dz)
				if d <= aura then
					n += 1
					if d > packR then
						packR = d
					end
				end
			end
			if n <= 0 then
				n = 1
			end
			return stickPos, n, packR, root
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
				or string.find(n, 'windup', 1, true)
				or string.find(n, 'cast', 1, true)
				or string.find(n, 'fillin', 1, true)
				or string.find(n, 'fadein', 1, true)
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
				or string.find(n, 'crimson', 1, true)
				or string.find(n, 'smite', 1, true)
				or string.find(n, 'sinister', 1, true)
				or string.find(n, 'frostflare', 1, true)
				or string.find(n, 'panstorm', 1, true)
				or string.find(n, 'guardian', 1, true)
				or string.find(n, 'enemyskill', 1, true)
		end

		-- Windup / FillIn markers for arena one-shots (strict — avoids idle VFX spam).
		local function nameLooksChargeNuke(name)
			local n = string.lower(tostring(name or ''))
			if n == '' or n == 'humanoidrootpart' or n == 'torso' or n == 'head' then
				return false
			end
			return string.find(n, 'charge', 1, true)
				or string.find(n, 'windup', 1, true)
				or string.find(n, 'fillin', 1, true)
				or string.find(n, 'fadein', 1, true)
				or string.find(n, 'telegraph', 1, true)
				or string.find(n, 'warn', 1, true)
				or string.find(n, 'indicat', 1, true)
				or string.find(n, 'nuke', 1, true)
				or string.find(n, 'omega', 1, true)
				or string.find(n, 'gyzer', 1, true)
				or string.find(n, 'geyser', 1, true)
				or string.find(n, 'lavagyzer', 1, true)
				or string.find(n, 'lavasmash', 1, true)
				or string.find(n, 'enemyskillhitbox', 1, true)
				or string.find(n, 'giantsword', 1, true)
				or string.find(n, 'giantblade', 1, true)
				or (string.find(n, 'sword', 1, true) and string.find(n, 'skill', 1, true))
				or (string.find(n, 'sword', 1, true) and string.find(n, 'hitbox', 1, true))
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

		local function partIsGrowingCharge(part)
			if not part or not part:IsA('BasePart') then
				return false
			end
			local s = part.Size
			local mx = math.max(s.X, s.Y, s.Z)
			local vol = s.X * s.Y * s.Z
			local now = os.clock()
			local prev = divePartSample[part]
			divePartSample[part] = { t = now, mx = mx, vol = vol }
			if not prev then
				return false
			end
			local dt = now - (prev.t or now)
			if dt <= 0 or dt > 1.6 then
				return false
			end
			-- FillIn hitboxes swell during the charge window.
			if vol >= (prev.vol or 0) * 1.18 and vol > 40 and mx >= 4 then
				return true
			end
			if mx >= (prev.mx or 0) + 2.5 and mx >= 8 then
				return true
			end
			return false
		end

		local function considerTelegraph(part, into, myChar, origin, opts)
			opts = opts or {}
			if not part or not part:IsA('BasePart') or not part.Parent then
				return
			end
			if myChar and part:IsDescendantOf(myChar) then
				return
			end
			local chargeNamed = nameLooksChargeNuke(part.Name)
				or nameLooksChargeNuke(part.Parent and part.Parent.Name)
			local named = chargeNamed
				or nameLooksTelegraph(part.Name)
				or nameLooksTelegraph(part.Parent and part.Parent.Name)
			-- Nearly invisible FillIn discs still matter while charging.
			if part.Transparency >= (chargeNamed and 0.995 or 0.98) then
				return
			end
			local s = part.Size
			local minSize = chargeNamed and 3 or 6
			if math.max(s.X, s.Y, s.Z) < minSize then
				return
			end
			local nearR = opts.nearR or DIVE_TELE_NEAR
			if origin then
				local dx = part.Position.X - origin.X
				local dz = part.Position.Z - origin.Z
				if (dx * dx + dz * dz) > (nearR * nearR) then
					return
				end
			end
			local growing = partIsGrowingCharge(part)
			if not named and not growing and not partIsBeamish(part, part.Name) and not partLooksProjectile(part, part.Name) then
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
				charge = chargeNamed or growing,
				growing = growing,
				seenAt = diveSeenAt[part],
			}
		end

		local function collectTelegraphs(opts)
			opts = opts or {}
			local myChar = getMyCharacterModel()
			local origin = opts.origin
			if not origin then
				local hrp = getMyBringPart()
				if hrp then
					origin = hrp.Position
				elseif diveLastCluster then
					origin = diveLastCluster
				end
			end
			local nearR = opts.nearR or DIVE_TELE_NEAR
			local now = os.clock()
			if not opts.fresh
				and diveTeleCache.hits
				and (now - (diveTeleCache.at or 0)) < DIVE_TELE_CACHE_SEC
				and diveTeleCache.nearR == nearR
				and diveTeleCache.origin
				and origin
				and (diveTeleCache.origin - origin).Magnitude < 25
			then
				return diveTeleCache.hits
			end
			local hits = {}
			local nearOpts = { nearR = nearR }
			for _, child in ipairs(workspace:GetChildren()) do
				if DIVE_IGNORE_WS[child.Name] then
					continue
				end
				if child:IsA('BasePart') then
					considerTelegraph(child, hits, myChar, origin, nearOpts)
				elseif child:IsA('Model') or child:IsA('Folder') or child:IsA('Accoutrement') then
					-- Skip CharacterItems spam — biggest lag source; only scan Effects / tagged.
					if child.Name == 'CharacterItems' then
						continue
					end
					local n = 0
					local cap = 120
					for _, d in ipairs(child:GetDescendants()) do
						n += 1
						if n > cap then
							break
						end
						if d:IsA('BasePart') then
							considerTelegraph(d, hits, myChar, origin, nearOpts)
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
						if n > 100 then
							break
						end
						if d:IsA('BasePart')
							and (
								nameLooksTelegraph(d.Name)
								or nameLooksTelegraph(d.Parent and d.Parent.Name)
								or nameLooksChargeNuke(d.Name)
								or nameLooksChargeNuke(d.Parent and d.Parent.Name)
							)
						then
							considerTelegraph(d, hits, myChar, origin, nearOpts)
						end
					end
				end
			end
			-- Tagged EnemySkillHitbox / FillIn instances (SB2 Cardinal).
			pcall(function()
				local CS = game:GetService('CollectionService')
				local tags = { 'EnemySkillHitbox', 'FillIn' }
				for ti = 1, #tags do
					local tagged = CS:GetTagged(tags[ti])
					for i = 1, math.min(#tagged, 40) do
						local inst = tagged[i]
						if inst:IsA('BasePart') then
							considerTelegraph(inst, hits, myChar, origin, nearOpts)
						end
					end
				end
			end)
			diveTeleCache = { at = now, hits = hits, origin = origin, nearR = nearR }
			return hits
		end

		local function mobPlayingChargeAnim(mob)
			if not mob then
				return false, nil
			end
			local foundName = nil
			local function scanAnimator(animator)
				if not animator or not animator.GetPlayingAnimationTracks then
					return
				end
				local ok, tracks = pcall(function()
					return animator:GetPlayingAnimationTracks()
				end)
				if not ok or type(tracks) ~= 'table' then
					return
				end
				for i = 1, #tracks do
					local tr = tracks[i]
					local nm = string.lower(tostring((tr and tr.Name) or ''))
					local anim = tr and tr.Animation
					local an = string.lower(tostring((anim and anim.Name) or ''))
					local blob = nm .. ' ' .. an
					-- Strict only — idle/attack loops often contain wave/cast/skill.
					if string.find(blob, 'charge', 1, true)
						or string.find(blob, 'windup', 1, true)
						or string.find(blob, 'fillin', 1, true)
						or string.find(blob, 'omega', 1, true)
						or string.find(blob, 'gyzer', 1, true)
						or string.find(blob, 'geyser', 1, true)
						or string.find(blob, 'nuke', 1, true)
					then
						foundName = nm ~= '' and nm or an
						return
					end
				end
			end
			pcall(function()
				local hum = mob:FindFirstChildOfClass('Humanoid')
				if hum then
					scanAnimator(hum:FindFirstChildOfClass('Animator') or hum)
				end
				local ac = mob:FindFirstChildOfClass('AnimationController')
				if ac then
					scanAnimator(ac:FindFirstChildOfClass('Animator') or ac)
				end
			end)
			return foundName ~= nil, foundName
		end

		-- True only on real FillIn growth (anim/fresh names caused constant under↔up Y flicker).
		local function detectBossNukeCharge(origin, stickMob)
			local nearNuke = stickMob and isNukeBossMob(stickMob)
			if not nearNuke then
				return false, nil
			end
			if os.clock() < diveNukeCooldownUntil then
				return false, nil
			end
			local hits = collectTelegraphs({ origin = origin, nearR = 200 })
			for i = 1, #hits do
				local hit = hits[i]
				if hit.growing == true then
					local part = hit.part
					local s = part and part.Size
					local mx = s and math.max(s.X, s.Y, s.Z) or 0
					local vol = s and (s.X * s.Y * s.Z) or 0
					if mx >= 10 and vol >= 80 then
						return true, 'grow:' .. tostring(part and part.Name)
					end
				end
			end
			return false, nil
		end

		local function telegraphEscape(hrpPos, cluster)
			local hits = collectTelegraphs({ origin = hrpPos })
			if #hits == 0 then
				return nil, false, nil, false
			end
			local pos = Vector3.new(hrpPos.X, hrpPos.Y, hrpPos.Z)
			local needDash = false
			local dashDir = nil
			local moved = false
			local chargeThreat = false
			local now = os.clock()
			for _, hit in ipairs(hits) do
				local part = hit.part
				local p = part.Position
				local age = now - (hit.seenAt or now)
				-- Only treat as nuke-charge if filling or brand-new strict telegraph.
				if hit.growing or (hit.charge and age <= 0.7 and nameLooksChargeNuke(part.Name)) then
					-- chargeThreat only from real FillIn growth (stops under-map Y thrash).
					if hit.growing then
						chargeThreat = true
					end
				end
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
					if dist < halfW + 6 then
						pos = Vector3.new(pos.X + side.X * (halfW + 12 - dist), pos.Y, pos.Z + side.Z * (halfW + 12 - dist))
						moved = true
					end
					local firing = part.Transparency < 0.25 or (age >= 0.55 and age <= 1.6)
					if firing and not diveDashed[part] and dist < halfW + 10 then
						needDash = true
						moved = true
						if dist >= halfW + 6 then
							pos = Vector3.new(pos.X + side.X * 16, pos.Y, pos.Z + side.Z * 16)
						end
					end
				else
					-- Ignore stale AoE leftovers that cause perpetual side-hops.
					if age > 2.2 and not hit.growing then
						continue
					end
					local radius = math.max(part.Size.X, part.Size.Z) * 0.5 + (hit.charge and 12 or 6)
					local flat = Vector3.new(pos.X - p.X, 0, pos.Z - p.Z)
					if flat.Magnitude < radius then
						if flat.Magnitude < 0.2 then
							flat = Vector3.new(math.cos(diveYaw), 0, math.sin(diveYaw))
						end
						local u = flat.Unit
						pos = Vector3.new(p.X + u.X * (radius + 8), pos.Y, p.Z + u.Z * (radius + 8))
						moved = true
					end
				end
			end
			if not moved and not chargeThreat then
				return nil, false, nil, false
			end
			if not moved then
				return nil, false, nil, chargeThreat
			end
			if cluster then
				pos = clampNearCluster(pos, cluster, DIVE_DODGE_RING)
			end
			return pos, needDash, dashDir, chargeThreat
		end

		local function diveTryDash(hrp, dir)
			return
		end

		local function stopDiveFarm(restore)
			local wasOn = getgenv().SB2DiveFarmOn == true
			getgenv().SB2DiveFarmOn = false
			getgenv().SB2DiveUnderMap = false
			diveFleeing = false
			diveNukeUntil = 0
			diveNukeCooldownUntil = 0
			diveNukeAnchor = nil
			diveClearHoldConns()
			pcall(function()
				local hrp = getMyBringPart()
				if hrp then
					hrp.Anchored = false
					hrp.AssemblyLinearVelocity = Vector3.zero
					hrp.AssemblyAngularVelocity = Vector3.zero
				end
			end)
			pcall(function()
				if diveLinVel then
					diveLinVel.VectorVelocity = Vector3.zero
					diveLinVel.Parent = nil
					diveLinVel.Attachment0 = nil
				end
			end)
			local detachLock = getgenv().SB2DiveDetachUprightLock
			if type(detachLock) == 'function' then
				pcall(detachLock)
			end
			pcall(applyCombatAnchor, false)
			diveStickMob = nil
			diveStickRoot = nil
			diveShouldRetarget = true
			diveLastCluster = nil
			diveMendingUntil = 0
			diveMendingPos = nil
			local farmThread = getgenv().SB2DiveFarmThread
			if farmThread then
				pcall(function()
					task.cancel(farmThread)
				end)
				getgenv().SB2DiveFarmThread = nil
			end
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
			diveClearHoldConns()
			if diveStreamPart then
				pcall(function()
					diveStreamPart:Destroy()
				end)
				diveStreamPart = nil
			end
			pcall(function()
				lockReplicationFocus(getMyCharacterModel())
			end)
			-- Only restore once — Heartbeat + toggle OnChanged both call stop.
			--#region agent log
			pcall(function()
				local line = game:GetService('HttpService'):JSONEncode({
					sessionId = '7e9135',
					runId = 'noclip-off',
					hypothesisId = 'H1,H4',
					location = 'stopDiveFarm',
					message = 'stop',
					data = {
						restore = restore == true,
						wasOn = wasOn,
						farmOn = getgenv().SB2DiveFarmOn == true,
						toggle = isToggleOn('DiveFarm'),
						noclipOn = getgenv().SB2DiveNoclipOn == true,
						hasReturnCF = typeof(diveReturnCF) == 'CFrame' or typeof(getgenv().SB2DiveReturnCF) == 'CFrame',
					},
					timestamp = math.floor(os.clock() * 1000),
				})
				if type(appendfile) == 'function' then
					appendfile('debug-7e9135.log', line .. '\n')
				end
			end)
			--#endregion
			if restore and wasOn then
				-- Clip immediately — do not wait on async land (that left people
				-- intangible through death/respawn when restore aborted).
				setDiveNoclip(false)
				restoreDiveReturnCF()
			elseif not restore then
				setDiveNoclip(false)
			elseif restore and not wasOn then
				-- Second stop while restore already running — leave land alone.
				if getgenv().SB2DiveNoclipOn == true then
					setDiveNoclip(false)
				end
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
			diveNukeUntil = 0
			diveNukeCooldownUntil = 0
			diveNukeAnchor = nil
			diveShouldRetarget = true
			diveClearHoldConns()
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
			-- Combat support often left empty — mirror Dive multi-support so CE actually fires.
			pcall(function()
				local farmOpt = Options.FarmSupportSkillName
				local combatOpt = Options.SupportSkillName
				if type(farmOpt) ~= 'table' or type(combatOpt) ~= 'table' or not combatOpt.SetValue then
					return
				end
				local farmMap = collectMultiSkillMap(farmOpt.Value)
				local combatMap = collectMultiSkillMap(combatOpt.Value)
				if next(farmMap) and not next(combatMap) then
					combatOpt:SetValue(farmMap)
					syncMultiSkillOrder('SB2SupportSkillOrder', farmMap)
				end
			end)
			applyCombatAnchor(false)
			setDiveNoclip(true)
			pcall(function()
				local hrp = getMyBringPart()
				if hrp then
					hrp.Anchored = false
					hrp.AssemblyLinearVelocity = Vector3.zero
				end
			end)
			local DIVE_KILL_TIMEOUT = 45
			local DIVE_LONG_HOP = 350
			local DIVE_SKIP_FINISHED = 1.0
			local diveFinishedUntil = setmetatable({}, { __mode = 'k' })

			local function stillActive()
				if getgenv().SB2DiveFarmOn ~= true or not isToggleOn('DiveFarm') then
					return false
				end
				-- Bail if a stranger is already here (join race / missed PlayerAdded).
				for _, plr in ipairs(Players:GetPlayers()) do
					if plr ~= LocalPlayer and not isOwnAlt(plr) then
						return false
					end
				end
				return true
			end

			local function diveDebug(msg, extra)
				-- Throttle: disk I/O every frame was a major lag source.
				local now = os.clock()
				if (now - lastDiveDebugAt) < 0.35 and msg ~= 'sky-rescue' and msg ~= 'nuke-return' then
					getgenv().SB2DiveLastDebug = tostring(msg) .. ' | ' .. tostring(extra or '')
					return
				end
				lastDiveDebugAt = now
				local tag = tostring(LocalPlayer.Name or 'x')
				local hrp = getMyBringPart()
				local stick = diveStickMob and tostring(diveStickMob.Name) or '-'
				local line = string.format(
					'%.2f %s stick=%s y=%s anc=%s | %s',
					now,
					tostring(msg),
					stick,
					hrp and string.format('%.0f', hrp.Position.Y) or '?',
					hrp and tostring(hrp.Anchored) or '?',
					tostring(extra or '')
				)
				getgenv().SB2DiveLastDebug = line
				task.defer(function()
					pcall(function()
						writefile('PlayerTools/_dive_live_' .. tag .. '.txt', line)
					end)
				end)
			end

			local function markDiveFinished(mob)
				if mob then
					diveFinishedUntil[mob] = os.clock() + DIVE_SKIP_FINISHED
					mobRealCF[mob] = nil
				end
				if diveStickMob == mob then
					diveStickMob = nil
					diveStickRoot = nil
				end
			end

			local function isDiveFinished(mob)
				local untilT = diveFinishedUntil[mob]
				if type(untilT) ~= 'number' then
					return false
				end
				if os.clock() >= untilT then
					diveFinishedUntil[mob] = nil
					return false
				end
				return true
			end

			local function diveGetMobHealth(mob)
				local entity = mob and mob:FindFirstChild('Entity')
				local health = entity and entity:FindFirstChild('Health')
				if health and typeof(health.Value) == 'number' then
					return health.Value
				end
				return nil
			end

			-- Missing Entity/Health = still streaming (T-pose silhouettes), NOT dead.
			local function diveMobGone(mob)
				if not mob or not mob.Parent then
					return true
				end
				local hp = diveGetMobHealth(mob)
				if type(hp) == 'number' and hp <= 0 then
					return true
				end
				local entity = mob:FindFirstChild('Entity')
				if entity then
					local hitLives = entity:FindFirstChild('HitLives')
					if hitLives then
						local ok, hits = pcall(function()
							return hitLives.Value
						end)
						if ok and type(hits) == 'number' and hits <= 0 then
							return true
						end
					end
				end
				return false
			end

			-- Silhouettes have a root but no Entity yet — engaging them hangs/soft-locks.
			local function diveMobStreamed(mob)
				if not mob or not mob.Parent then
					return false
				end
				local entity = mob:FindFirstChild('Entity')
				return entity ~= nil and entity:FindFirstChild('Health') ~= nil
			end

			-- Prefer real Hitbox parts (Atheon etc.) over HumanoidRootPart.
			-- IMPORTANT: never call GetDescendants / GetBoundingBox here — on Potassium
			-- those stall the Event Dive thread forever (nickb910 stuck on "target").
			local function isAeganatosMob(mob)
				local n = string.lower(tostring(mob and mob.Name or ''))
				return string.find(n, 'aeganatos', 1, true) ~= nil
					or string.find(n, 'aegatanos', 1, true) ~= nil
					or string.find(n, 'sunken sovereign', 1, true) ~= nil
			end

			local function diveHeadTopBoss(mob)
				return isNukeBossMob(mob) or isAeganatosMob(mob)
			end

			local function diveFindHitFocus(mob, root)
				if not root then
					return nil, nil
				end
				if not mob then
					return root, root.Position
				end
				-- Nuke / head-top bosses: Body + crown/head parts (not feet root).
				if diveHeadTopBoss(mob) then
					local focusPart = root
					pcall(function()
						local body = mob:FindFirstChild('Body')
						if body and body:IsA('BasePart') then
							focusPart = body
							return
						end
						local named = mob:FindFirstChild('Hitbox')
							or mob:FindFirstChild('Hurtbox')
							or mob:FindFirstChild('DamageHitbox')
							or mob:FindFirstChild('Torso')
							or mob:FindFirstChild('UpperTorso')
						if named and named:IsA('BasePart') then
							focusPart = named
						end
					end)
					if focusPart and focusPart:IsA('BasePart') then
						return focusPart, focusPart.Position
					end
					return root, root.Position
				end
				local hit = nil
				pcall(function()
					hit = mob:FindFirstChild('Hitbox')
						or mob:FindFirstChild('Hurtbox')
						or mob:FindFirstChild('DamageHitbox')
					if not hit then
						local entity = mob:FindFirstChild('Entity')
						if entity then
							hit = entity:FindFirstChild('Hitbox')
								or entity:FindFirstChild('Hurtbox')
						end
					end
				end)
				if hit and hit:IsA('BasePart') then
					return hit, hit.Position
				end
				return root, root.Position
			end

			local function diveFightHeights(mob, root, engagePlaneY)
				local focusPart, hitPos = diveFindHitFocus(mob, root)
				if not focusPart or not hitPos or not focusPart:IsA('BasePart') then
					return nil, nil, nil, nil
				end
				local half = focusPart.Size.Y * 0.5
				local floorY = focusPart.Position.Y - half
				local aimY = focusPart.Position.Y
				local function diveBodyFightY(floor, aim, forNukeBoss)
					local bodyH = math.max(6, aim - floor)
					if forNukeBoss then
						return math.max(floor + 12, floor + math.min(bodyH * 0.64, math.max(48, bodyH * 0.52)))
					end
					local fight = aim - math.min(5, bodyH * 0.12)
					return math.max(fight, floor + math.min(bodyH * 0.45, 24))
				end
				if diveHeadTopBoss(mob) then
					local fightY = nil
					pcall(function()
						local body = mob:FindFirstChild('Body') or focusPart
						if body and body:IsA('BasePart') then
							floorY = body.Position.Y - body.Size.Y * 0.5
						end
						if root and root:IsA('BasePart') then
							floorY = math.min(floorY or root.Position.Y, root.Position.Y - root.Size.Y * 0.5)
						end
						local topY = floorY or focusPart.Position.Y
						local aimPart = body or focusPart
						local function considerTopPart(p)
							if p and p:IsA('BasePart') then
								local pTop = p.Position.Y + p.Size.Y * 0.5
								if pTop > topY then
									topY = pTop
									aimPart = p
								end
							end
						end
						for _, name in ipairs({
							'Crown',
							'Head',
							'FakeHead',
							'UpperTorso',
							'Torso',
							'Pillar',
							'Antlers',
							'Horns',
							'Hair',
						}) do
							considerTopPart(mob:FindFirstChild(name))
							local entity = mob:FindFirstChild('Entity')
							if entity then
								considerTopPart(entity:FindFirstChild(name))
							end
						end
						if body and body:IsA('BasePart') then
							topY = math.max(topY, body.Position.Y + body.Size.Y * 0.5)
						end
						local headAbove = diveFarmAboveStuds()
						if diveAutoHeightOn() then
							headAbove = math.max(headAbove, DIVE_NUKE_HEAD_ABOVE)
						end
						fightY = topY + headAbove
						aimY = aimPart and aimPart.Position.Y or (topY - 6)
						if body and body:IsA('BasePart') then
							aimY = body.Position.Y + body.Size.Y * DIVE_NUKE_AIM_BODY_UP
						end
					end)
					if not fightY then
						fightY = diveBodyFightY(floorY, aimY, true)
					end
					return focusPart, fightY, floorY, Vector3.new(hitPos.X, aimY, hitPos.Z)
				end
				local bodyH = math.max(0.5, aimY - floorY)
				-- Exact focus-part top (do not pad short parts — that made "0" sit too high).
				local topY = aimY + bodyH
				local above = diveFarmAboveStuds()
				local fightY = topY + above
				if typeof(engagePlaneY) == 'number' and floorY > engagePlaneY + 2.5 then
					-- Mob above your ledge: still hover relative to the mob, not dig under.
					fightY = topY + above
				end
				--#region agent log
				pcall(function()
					local now = os.clock()
					if (now - (getgenv().SB2DbgHgtLogAt or 0)) < 0.9 then
						return
					end
					getgenv().SB2DbgHgtLogAt = now
					local line = game:GetService('HttpService'):JSONEncode({
						sessionId = '7e9135',
						runId = 'height-fix',
						hypothesisId = 'H-h3,H-h4',
						location = 'diveFightHeights',
						message = 'fightY',
						data = {
							above = math.floor(above * 10 + 0.5) / 10,
							topY = math.floor(topY * 10 + 0.5) / 10,
							fightY = math.floor(fightY * 10 + 0.5) / 10,
							floorY = math.floor(floorY * 10 + 0.5) / 10,
							bodyH = math.floor(bodyH * 10 + 0.5) / 10,
							auto = diveAutoHeightOn(),
							slider = diveOptNumber('DiveFarmHeight', -999),
						},
						timestamp = math.floor(os.clock() * 1000),
					})
					if type(appendfile) == 'function' then
						appendfile('debug-7e9135.log', line .. '\n')
					end
				end)
				--#endregion
				return focusPart, fightY, floorY, Vector3.new(hitPos.X, aimY, hitPos.Z)
			end

			-- Lock XZ to a trusted world point. Event mobs' live roots often
			-- fling client-side; chasing that is what sent you off the map.
			local function diveTrustMobPos(mob, root, origin, lockedPos)
				if not root then
					return lockedPos
				end
				local dashBoss = mob and diveHeadTopBoss(mob)
				pcall(cacheMobRealPositions, origin)
				local _, focusLive = diveFindHitFocus(mob, root)
				local live = focusLive or root.Position
				local cached = mobRealCF[mob]
				local cand = live
				if typeof(cached) == 'CFrame' then
					local drift = (live - cached.Position).Magnitude
					if drift > 55 then
						if dashBoss and drift <= 140 then
							cand = live
						else
							cand = cached.Position
						end
					end
				end
				if lockedPos then
					local off = (cand - lockedPos).Magnitude
					if off > 55 then
						if dashBoss then
							local flat = Vector3.new(cand.X - lockedPos.X, 0, cand.Z - lockedPos.Z)
							if flat.Magnitude > 130 then
								cand = lockedPos
							end
						else
							cand = lockedPos
						end
					end
				end
				if origin and (cand - origin).Magnitude > 80 then
					if dashBoss then
						local flat = Vector3.new(cand.X - origin.X, 0, cand.Z - origin.Z)
						if flat.Magnitude > 165 then
							if lockedPos then
								cand = lockedPos
							elseif typeof(cached) == 'CFrame' then
								cand = cached.Position
							end
						end
					elseif lockedPos then
						cand = lockedPos
					elseif typeof(cached) == 'CFrame' then
						cand = cached.Position
					end
				end
				return cand
			end

			-- CharacterItems Right/LeftWeapon Tool.Blade (or Hitbox) longest axis.
			local diveReachCache, diveReachAt = 0, 0
			local function diveGetWeaponReach()
				if diveReachCache > 0 and (os.clock() - diveReachAt) < 1.25 then
					return diveReachCache
				end
				local best = 0
				pcall(function()
					local items = workspace:FindFirstChild('CharacterItems')
					local mine = items and items:FindFirstChild(tostring(LocalPlayer.UserId))
					if not mine then
						return
					end
					local function consider(part)
						if not part or not part:IsA('BasePart') then
							return
						end
						local len = math.max(part.Size.X, part.Size.Y, part.Size.Z)
						if len > best then
							best = len
						end
					end
					for _, hand in ipairs({ 'RightWeapon', 'LeftWeapon' }) do
						local weapon = mine:FindFirstChild(hand)
						if not weapon then
							continue
						end
						local tool = weapon:FindFirstChild('Tool')
						consider(tool and tool:FindFirstChild('Blade'))
						local n = 0
						for _, d in ipairs(weapon:GetDescendants()) do
							n += 1
							if n > 120 then
								break
							end
							if d:IsA('BasePart') then
								local nm = string.lower(d.Name)
								if nm == 'blade'
									or string.find(nm, 'hitbox', 1, true)
									or string.find(nm, 'hurtbox', 1, true)
								then
									consider(d)
								end
							end
						end
					end
				end)
				if best < 3 then
					best = DIVE_HOVER
				end
				diveReachCache = best
				diveReachAt = os.clock()
				getgenv().SB2DiveWeaponReach = best
				return best
			end

			-- Usable connect distance: sit under blade max so swings still land.
			local function diveHoverBudget(pullIn)
				local reach = diveGetWeaponReach()
				local frac = pullIn and 0.52 or 0.78
				return math.clamp(reach * frac, 3, 36)
			end

			-- Height / XZ from blade reach. pullIn = orbit on the blade ring (NOT dig into mesh).
			local function diveComputeFightPos(mob, root, myPos, lockedFocus, pullIn)
				local focusPart, focusPos = diveFindHitFocus(mob, root)
				if not focusPos then
					return nil, nil, nil
				end
				if lockedFocus then
					if (focusPos - lockedFocus).Magnitude > 80 then
						focusPos = lockedFocus
					end
				end
				local halfH, halfXZ = 8, 10
				if focusPart and focusPart:IsA('BasePart') then
					halfH = math.clamp(focusPart.Size.Y * 0.5, 2, 40)
					halfXZ = math.clamp(math.max(focusPart.Size.X, focusPart.Size.Z) * 0.5, 2, 40)
				end
				local headTop = diveHeadTopBoss(mob)
				local bigBoss = headTop
				-- Head-top nuke bosses: XZ ring only, no added hover (stops up/down hop).
				if headTop then
					halfH = 0
					if focusPart and focusPart:IsA('BasePart') then
						halfXZ = math.clamp(math.max(focusPart.Size.X, focusPart.Size.Z) * 0.4, 3, 10)
					else
						halfXZ = 6
					end
				end
				-- GetBoundingBox removed — stalled Event Dive farm thread on Potassium.
				-- Final Y clamp to engage lock — stops void teleports when parts fling.
				if lockedFocus and math.abs(focusPos.Y - lockedFocus.Y) > 45 then
					focusPos = Vector3.new(focusPos.X, lockedFocus.Y, focusPos.Z)
				end
				if lockedFocus and (focusPos - lockedFocus).Magnitude > 120 then
					focusPos = lockedFocus
				end
				local reach = diveGetWeaponReach()
				local budget = diveHoverBudget(false)
				local flat = Vector3.new(myPos.X - focusPos.X, 0, myPos.Z - focusPos.Z)
				local dir = flat.Magnitude > 1 and flat.Unit
					or Vector3.new(math.cos(diveYaw), 0, math.sin(diveYaw))
				-- Prefer Farm height slider (via diveFarmAboveStuds). Blade budget
				-- must NOT raise Y when Auto farm height is off.
				local hover = diveFarmAboveStuds()
				if diveAutoHeightOn() and halfH > 12 then
					hover = math.max(hover, math.min(math.max(budget, 3), math.max(4, halfH - 1)))
				end
				if pullIn and not headTop then
					diveYaw += 0.65
					dir = Vector3.new(math.cos(diveYaw), 0, math.sin(diveYaw))
					if diveAutoHeightOn() then
						hover = math.max(hover, math.clamp(reach * 0.72, 5, 40))
					end
				end
				local standoff = math.clamp(budget * 0.4, 3.5, 14)
				if halfXZ > 16 then
					standoff = math.max(3.5, math.min(standoff, halfXZ * 0.35))
				end
				if pullIn and not headTop then
					standoff = math.clamp(reach * 0.42, 6, 16)
				end
				local lookPos = focusPos
				-- Big event bosses: XZ ring only; Y comes from stickyFightY lock.
				if bigBoss then
					hover = diveFarmAboveStuds()
					standoff = math.clamp(math.min(budget * 0.35, 4.5), 2.5, 5.5)
					if focusPart and focusPart:IsA('BasePart') then
						lookPos = focusPart.Position
					end
					if lockedFocus then
						focusPos = Vector3.new(focusPos.X, lockedFocus.Y, focusPos.Z)
					end
				end
				-- Do not scale hover down to fit blade length — that fought the slider.
				local stickY = focusPos.Y + hover
				if bigBoss and lockedFocus then
					stickY = lockedFocus.Y
				end
				local stick = Vector3.new(
					focusPos.X + dir.X * standoff,
					stickY,
					focusPos.Z + dir.Z * standoff
				)
				if lockedFocus and (stick - lockedFocus).Magnitude > 160 then
					stick = Vector3.new(
						lockedFocus.X + dir.X * standoff,
						stickY,
						lockedFocus.Z + dir.Z * standoff
					)
				end
				return stick, lookPos, focusPart
			end

			local function diveHoverAt(worldPos)
				local h = diveHoverBudget(false)
				return Vector3.new(worldPos.X, worldPos.Y + h, worldPos.Z)
			end

			-- Same motion model as AutoFarm stepToward / tweenTo (keepGoalY).
			local function diveStepToward(hrp, goalPos, speed, lookAt, clampOpts)
				if not hrp or not hrp.Parent or not goalPos then
					return false
				end
				local refY = (diveLastCluster and diveLastCluster.Y) or hrp.Position.Y
				goalPos = diveClampGoal(goalPos, diveLastCluster or hrp.Position, clampOpts or {
					yRef = refY,
					yMin = refY - 4,
					yMax = refY + 4,
				})
				if speed < 1 then
					speed = 1
				end
				local pos = hrp.Position
				local flatGoal = goalPos
				local delta = flatGoal - pos
				local dist = delta.Magnitude
				local function aimFrom(from)
					if typeof(lookAt) == 'Vector3' and (lookAt - from).Magnitude > 0.05 then
						return lookAt
					end
					return Vector3.new(from.X, from.Y - DIVE_HOVER, from.Z)
				end
				if dist <= DIVE_ARRIVE then
					diveWriteCFrame(hrp, flatGoal, aimFrom(flatGoal))
					pcall(function()
						lockReplicationFocus(getMyCharacterModel())
					end)
					task.wait()
					return true
				end
				local dt = task.wait()
				if dt <= 0 then
					dt = 1 / 60
				end
				local step = math.min(dist, speed * dt)
				if delta.Magnitude < 1e-4 then
					return false
				end
				local dir = delta.Unit
				local maxYStep = math.max(step, speed * dt)
				local nextPos = pos + dir * step
				local yDelta = math.clamp(flatGoal.Y - pos.Y, -maxYStep, maxYStep)
				nextPos = Vector3.new(nextPos.X, pos.Y + yDelta, nextPos.Z)
				diveWriteCFrame(hrp, nextPos, aimFrom(nextPos))
				return false
			end

			local function diveTweenTo(hrp, goalPos, speed, lookAt)
				if not hrp or not goalPos then
					return false
				end
				if (goalPos - hrp.Position).Magnitude > 520 or math.abs(goalPos.Y - hrp.Position.Y) > 220 then
					diveDebug('tween-reject', string.format('d=%.0f dy=%.0f', (goalPos - hrp.Position).Magnitude, goalPos.Y - hrp.Position.Y))
					return false
				end
				local deadline = os.clock() + 5
				while stillActive() and os.clock() < deadline do
					if not hrp or not hrp.Parent then
						return false
					end
					if diveStepToward(hrp, goalPos, speed or DIVE_TWEEN_SPEED, lookAt) then
						return true
					end
				end
				return false
			end

			local function diveBlinkTo(hrp, goalPos, lookAt)
				if not stillActive() or not hrp or not hrp.Parent or not goalPos then
					return false
				end
				local anchor = diveLastCluster or hrp.Position
				goalPos = diveClampGoal(goalPos, anchor, {
					yRef = anchor.Y,
					yPad = DIVE_SAFE_Y,
					allowUnder = true,
					flatMax = DIVE_MAX_BLINK,
				})
				local dist = (goalPos - hrp.Position).Magnitude
				if dist > DIVE_MAX_BLINK then
					diveDebug('blink-reject', string.format('d=%.0f max=%.0f', dist, DIVE_MAX_BLINK))
					return diveStepToward(hrp, goalPos, DIVE_TWEEN_SPEED * 1.5, lookAt)
				end
				local look = typeof(lookAt) == 'Vector3' and lookAt
					or Vector3.new(goalPos.X, goalPos.Y - DIVE_HOVER, goalPos.Z)
				diveWriteCFrame(hrp, goalPos, look)
				pcall(function()
					lockReplicationFocus(getMyCharacterModel())
				end)
				task.wait(0.06)
				return stillActive() and hrp.Parent ~= nil
			end

			local function diveNearestMob(fromPos)
				local mobsRoot = workspace:FindFirstChild('Mobs')
				if not mobsRoot or not fromPos then
					return nil
				end
				pcall(cacheMobRealPositions, fromPos)
				local best, bestD = nil, math.huge
				local bestSil, bestSilD, bestSilPos = nil, math.huge, nil
				for _, mob in ipairs(mobsRoot:GetChildren()) do
					if diveMobGone(mob) or diveShouldSkipMob(mob) or isDiveFinished(mob) then
						continue
					end
					local root = getMobRoot(mob)
					if not root then
						continue
					end
					local cand = diveMobWorldPos(mob, root, fromPos) or root.Position
					local cached = mobRealCF[mob]
					if typeof(cached) == 'CFrame' then
						local live = root.Position
						if (live - cached.Position).Magnitude > 80 then
							cand = cached.Position
						end
					end
					local dx = cand.X - fromPos.X
					local dz = cand.Z - fromPos.Z
					local flat = math.sqrt(dx * dx + dz * dz)
					-- Prefer flat XZ so Y-fling doesn't hide nearby silhouettes.
					if flat > 520 then
						continue
					end
					-- On zoned floors, prefer targets deeper in the pad (away from boss).
					local zone = diveFarmZone()
					if zone then
						local boss = diveBossSpawnPos(zone)
						if boss then
							local bx = cand.X - boss.X
							local bz = cand.Z - boss.Z
							local away = math.sqrt(bx * bx + bz * bz)
							flat = flat - math.min(away, 900) * 0.2
						end
					end
					if not diveMobStreamed(mob) then
						-- Remember silhouette for streaming; do not engage yet.
						if flat < bestSilD then
							bestSil, bestSilD, bestSilPos = mob, flat, cand
						end
						continue
					end
					if flat < bestD then
						best, bestD = mob, flat
					end
				end
				if best then
					return best
				end
				-- No streamed mobs: push replication toward nearest silhouette.
				if bestSilPos then
					getgenv().SB2DivePendingStream = bestSilPos
					diveDebug('wait-stream', string.format('%s d=%.0f', tostring(bestSil and bestSil.Name), bestSilD))
				end
				return nil
			end

			local function diveTickHeals()
				local hp = diveHealthFrac()
				local element = detectEventElement()
				if hp <= DIVE_HP_PANIC then
					diveFleeing = true
					if hp <= DIVE_HP_PANIC then
						diveMendingUntil = 0
						diveMendingPos = nil
					end
					tryCastEventHeal(hp <= DIVE_HP_PANIC and 'panic' or 'low-hp', hp)
				elseif hp >= DIVE_HP_RETURN then
					diveFleeing = false
				end
				if diveFleeing then
					-- Stay under until ~max HP; keep casting heals the whole time.
					tryCastEventHeal('under', hp)
				elseif element == 'poison' or diveHpTrendingDown() then
					tryCastEventHeal('poison', hp)
				elseif element == 'fire' then
					tryCastEventHeal('fire', hp)
				end
			end

			local function diveKillUntilDead(myPart, mob)
				if not mob or not mob.Parent or diveMobGone(mob) or diveShouldSkipMob(mob) or isDiveFinished(mob) then
					if mob and diveMobGone(mob) then
						markDiveFinished(mob)
					end
					return
				end
				if not diveMobStreamed(mob) then
					local root0 = getMobRoot(mob)
					local streamPos = root0 and root0.Position or nil
					if streamPos then
						diveFocusStream(streamPos)
						diveDebug('unstreamed', mob.Name)
					end
					diveFinishedUntil[mob] = os.clock() + 0.45
					return
				end
				local root = getMobRoot(mob)
				if not root then
					-- Root not streamed yet — soft defer, don't blacklist long.
					diveFinishedUntil[mob] = os.clock() + 0.35
					return
				end
				diveStickMob = mob
				diveStickRoot = root
				setDiveNoclip(true)
				diveDebug('target', mob.Name)

				-- Seed / keep a real-world lock on the HITBOX (not just root).
				pcall(cacheMobRealPositions, myPart.Position)
				local _, hitFocus = diveFindHitFocus(mob, root)
				local atkCF = getMobAttackCFrame(mob, root, myPart.Position)
				local cached = mobRealCF[mob]
				local engagePos = atkCF.Position
				if typeof(cached) == 'CFrame' then
					engagePos = cached.Position
				end
				local function flatNear(p, maxD)
					if not p then
						return false
					end
					local dx = p.X - myPart.Position.X
					local dz = p.Z - myPart.Position.Z
					return math.sqrt(dx * dx + dz * dz) < (maxD or 320)
				end
				local function withGoodY(p)
					if not p then
						return nil
					end
					local y = p.Y
					-- Salvage Y when client flings the root under the map / skybox.
					if math.abs(y - myPart.Position.Y) > 120 then
						if typeof(cached) == 'CFrame' and math.abs(cached.Position.Y - myPart.Position.Y) < 120 then
							y = cached.Position.Y
						elseif diveLastCluster and math.abs(diveLastCluster.Y - myPart.Position.Y) < 120 then
							y = diveLastCluster.Y
						else
							y = myPart.Position.Y
						end
					end
					return Vector3.new(p.X, y, p.Z)
				end
				if hitFocus and flatNear(hitFocus) then
					engagePos = withGoodY(hitFocus)
					mobRealCF[mob] = CFrame.new(engagePos)
				elseif flatNear(root.Position) then
					engagePos = withGoodY(root.Position)
					mobRealCF[mob] = CFrame.new(engagePos)
				elseif typeof(cached) == 'CFrame' and flatNear(cached.Position) then
					engagePos = withGoodY(cached.Position)
				elseif flatNear(atkCF.Position) then
					engagePos = withGoodY(atkCF.Position)
					mobRealCF[mob] = CFrame.new(engagePos)
				else
					-- Last resort: flatten XZ to arena Y (client BB/Y-fling used to
					-- soft-skip forever — nickb910 stuck on "target" only).
					local raw = root.Position
					if typeof(cached) == 'CFrame' then
						raw = cached.Position
					elseif hitFocus then
						raw = hitFocus
					elseif atkCF then
						raw = atkCF.Position
					end
					local flat = Vector3.new(raw.X, myPart.Position.Y, raw.Z)
					local dx = flat.X - myPart.Position.X
					local dz = flat.Z - myPart.Position.Z
					local flatDist = math.sqrt(dx * dx + dz * dz)
					if flatDist < 120 and flatDist > 0.5 then
						engagePos = flat
						mobRealCF[mob] = CFrame.new(engagePos)
						diveDebug('engage-flat', string.format('%s d=%.0f', mob.Name, flatDist))
					else
						diveDebug('bad-engage', string.format('%s flat=%.0f', mob.Name, flatDist))
						diveFinishedUntil[mob] = os.clock() + 0.6
						return
					end
				end
				local lockedPos = engagePos
				diveLastCluster = lockedPos
				local lockedFloorY = lockedPos.Y
				local stickyFightY = lockedPos.Y
				local stickyAbove = diveFarmAboveStuds()
				local bossAim = lockedPos
				local engagePlaneY = myPart.Position.Y
				local engageHp = diveHealthFrac()
				local _, fightY, floorY, aimAt = diveFightHeights(mob, root, engagePlaneY)
				if fightY and floorY and aimAt then
					stickyFightY = fightY
					stickyAbove = diveFarmAboveStuds()
					lockedFloorY = floorY
					bossAim = aimAt
					lockedPos = Vector3.new(lockedPos.X, stickyFightY, lockedPos.Z)
					diveLastCluster = lockedPos
					mobRealCF[mob] = CFrame.new(lockedPos)
				end
				if engageHp >= DIVE_HP_RETURN then
					diveFleeing = false
				end

				-- Arena tile floor (for under-map heal) vs boss feet (for fighting).
				local isBigBossEngage = diveHeadTopBoss(mob)
				local arenaFloorY = lockedFloorY
				pcall(function()
					local cf = diveReturnCF or getgenv().SB2DiveReturnCF
					if typeof(cf) == 'CFrame' then
						arenaFloorY = math.min(arenaFloorY, cf.Position.Y)
					end
				end)
				if isBigBossEngage then
					-- Boss feet sit above the visible arena tiles — dig from tile floor.
					arenaFloorY = math.min(arenaFloorY, lockedFloorY - 10)
				end
				local fleeDepth = diveFleeUnderDepth(isBigBossEngage)
				local underHoldY = arenaFloorY - fleeDepth
				if isBigBossEngage then
					diveDebug(
						'boss-heights',
						string.format(
							'fight=%.0f feet=%.0f arena=%.0f under=%.0f aim=%.0f',
							stickyFightY,
							lockedFloorY,
							arenaFloorY,
							underHoldY,
							(typeof(bossAim) == 'Vector3' and bossAim.Y) or stickyFightY
						)
					)
				end

				-- Approach — first tp only; snap Y even when already close on XZ.
				local pullIn = false
				local approachY = stickyFightY
				local approach = Vector3.new(lockedPos.X, approachY, lockedPos.Z)
				local lookFocus = bossAim
				local approachClamp = {
					yRef = approachY,
					yMin = approachY - 12,
					yMax = approachY + (isBigBossEngage and 10 or 2),
				}
				local dist0 = (myPart.Position - approach).Magnitude
				diveDebug(
					'approach',
					string.format(
						'd=%.0f blade=%.1f approachY=%.0f fightY=%.0f feet=%.0f',
						dist0,
						diveGetWeaponReach(),
						approachY,
						stickyFightY,
						lockedFloorY
					)
				)
				if dist0 > DIVE_APPROACH_MAX then
					diveDebug('skip-far', string.format('d=%.0f', dist0))
					diveFinishedUntil[mob] = os.clock() + 0.6
					return
				end
				-- Tween to mob — no upfront snap (was dumping you on arena floor at feet).
				if dist0 > DIVE_ARRIVE + 2 then
					local approachT0 = os.clock()
					while stillActive() and (myPart.Position - approach).Magnitude > DIVE_ARRIVE + 2 do
						if os.clock() - approachT0 > 12 then
							diveDebug('approach-timeout', string.format('d=%.0f', (myPart.Position - approach).Magnitude))
							break
						end
						diveStepToward(myPart, approach, DIVE_TWEEN_SPEED * DIVE_APPROACH_SPEED_MULT, lookFocus, approachClamp)
					end
				end
				if stillActive() and (myPart.Position - approach).Magnitude > DIVE_ARRIVE then
					diveSnapTo(myPart, approach, lookFocus, approachClamp)
				end
				if not stillActive() then
					return
				end
				-- Don't blacklist streaming silhouettes (isDeadMob true with no Health yet).
				if diveMobGone(mob) then
					markDiveFinished(mob)
					diveDebug('abort-early', mob.Name)
					return
				end
				task.wait(0.03)

				local killStarted = os.clock()
				local lastHit = 0
				local missingRootSince = nil
				local lastHp = diveGetMobHealth(mob)
				local lastHpDropAt = os.clock()
				local lastDbgAt = 0
				local runawayStrikes = 0
				local lastDodgeAt = 0
				local wasNukeFlee = false
				local voidRescues = 0
				local isBigBoss = isBigBossEngage
				local lastTrustAt = 0
				local lastMoveAt = 0
				local fleeClamp = {
					floorY = arenaFloorY,
					allowUnder = true,
					flatMax = DIVE_FLEE_RING + 6,
					yRef = underHoldY,
					yMin = underHoldY - 2,
					yMax = underHoldY + 2,
				}
				local fightClamp = {
					yRef = stickyFightY,
					yMin = stickyFightY - 2,
					yMax = stickyFightY + 2,
				}
				diveClearHoldConns()

				while stillActive()
					and mob.Parent
					and not diveMobGone(mob)
					and (os.clock() - killStarted) < DIVE_KILL_TIMEOUT
				do
					myPart = getMyBringPart()
					if not myPart or not myPart.Parent then
						task.wait(0.15)
						continue
					end
					pcall(function()
						myPart.Anchored = false
					end)
					setDiveNoclip(true)
					diveTickHeals()

					local hpFrac = diveHealthFrac()
					if hpFrac <= DIVE_HP_PANIC then
						diveFleeing = true
					elseif hpFrac <= DIVE_HP_FLEE then
						if engageHp > DIVE_HP_FLEE then
							diveFleeing = true
						elseif (os.clock() - killStarted) > DIVE_SURFACE_FLEE_SEC then
							diveFleeing = true
						end
					elseif hpFrac >= DIVE_HP_RETURN then
						diveFleeing = false
					end
					local underNow = myPart.Position.Y < (arenaFloorY - 20)
					getgenv().SB2DiveUnderMap = underNow == true or diveFleeing == true
					local nukeFleeEarly = os.clock() < diveNukeUntil
					local panicEarly = hpFrac <= DIVE_HP_PANIC
					local fleeingEarly = diveFleeing or panicEarly or nukeFleeEarly

					-- Void / map-edge guard — skip while under map or fleeing (was yanking back up).
					if not underNow and not fleeingEarly then
						local dx = myPart.Position.X - lockedPos.X
						local dz = myPart.Position.Z - lockedPos.Z
						local flatOff = math.sqrt(dx * dx + dz * dz)
						local yOff = math.abs(myPart.Position.Y - stickyFightY)
						if flatOff > DIVE_SAFE_FLAT + 20 or yOff > DIVE_SAFE_Y + 50 then
							voidRescues += 1
							if voidRescues > 3 then
								diveDebug('void-abort', string.format('flat=%.0f y=%.0f', flatOff, yOff))
								break
							end
							local safe = diveClampGoal(
								Vector3.new(lockedPos.X, stickyFightY, lockedPos.Z),
								lockedPos,
								{ yRef = stickyFightY, yPad = 6 }
							)
							diveDebug('void-rescue', string.format('flat=%.0f yOff=%.0f', flatOff, yOff))
							diveWriteCFrame(myPart, safe, lockedPos, { clamp = fightClamp })
							pcall(function()
								lockReplicationFocus(getMyCharacterModel())
							end)
							task.wait(0.08)
							continue
						end
						voidRescues = 0
					end

					-- Near-max HP: force surface (don't stay under forever).
					if hpFrac >= DIVE_HP_RETURN then
						diveFleeing = false
						diveNukeUntil = 0
						diveNukeAnchor = nil
					end

					-- Extreme skybox only — not while fleeing under.
					if not fleeingEarly and not underNow and myPart.Position.Y > stickyFightY + 80 then
						local rescue = diveClampGoal(
							Vector3.new(lockedPos.X, stickyFightY, lockedPos.Z),
							lockedPos,
							{ yRef = stickyFightY, yPad = 6 }
						)
						diveStepToward(myPart, rescue, DIVE_TWEEN_SPEED * 1.4, lockedPos)
						task.wait(0.06)
						continue
					end

					local panic = panicEarly
					local nukeCharge, nukeWhy = nil, nil
					-- Don't scan telegraphs every frame while under — huge lag.
					if not underNow and (os.clock() - (diveTeleCache.at or 0)) >= 0.15 then
						nukeCharge, nukeWhy = detectBossNukeCharge(myPart.Position, mob)
					end
					if nukeCharge then
						if os.clock() >= diveNukeUntil then
							diveNukeAnchor = nil
						end
						diveNukeUntil = os.clock() + DIVE_NUKE_HOLD
						diveDebug('nuke-charge', tostring(nukeWhy))
					end
					local nukeFlee = os.clock() < diveNukeUntil
					if wasNukeFlee and not nukeFlee and not panic then
						diveNukeCooldownUntil = os.clock() + DIVE_NUKE_COOLDOWN
						diveNukeAnchor = nil
						diveDebug('nuke-return', 'back to stick')
					end
					wasNukeFlee = nukeFlee
					local fleeing = diveFleeing or panic or nukeFlee
					if not fleeing then
						diveNukeAnchor = nil
					end
					local holdingMend = not panic
						and os.clock() < diveMendingUntil
						and typeof(diveMendingPos) == 'Vector3'

					-- Side dodges — nuke bosses only (workspace telegraph scan is expensive).
					local dodgePos, needDash, dashDir, chargeThreat = nil, false, nil, false
					if isNukeBossMob(mob) and not fleeing and not underNow then
						dodgePos, needDash, dashDir, chargeThreat = telegraphEscape(myPart.Position, lockedPos)
					end
					if chargeThreat and isNukeBossMob(mob) and os.clock() >= diveNukeCooldownUntil then
						if os.clock() >= diveNukeUntil then
							diveNukeAnchor = nil
						end
						diveNukeUntil = math.max(diveNukeUntil, os.clock() + DIVE_NUKE_HOLD)
						nukeFlee = true
						fleeing = true
						wasNukeFlee = true
					end
					if dodgePos and not nukeFlee and not panic and (os.clock() - lastDodgeAt) >= 0.45 then
						local flatMove = Vector3.new(dodgePos.X - myPart.Position.X, 0, dodgePos.Z - myPart.Position.Z)
						if flatMove.Magnitude >= 7 then
							lastDodgeAt = os.clock()
							local dest = clampNearCluster(
								Vector3.new(dodgePos.X, stickyFightY, dodgePos.Z),
								lockedPos,
								DIVE_DODGE_RING
							)
							diveDebug('dodge', string.format('dash=%s d=%.0f', tostring(needDash), flatMove.Magnitude))
							diveStepToward(myPart, dest, DIVE_TWEEN_SPEED * 1.15, lockedPos)
							task.wait(0.05)
							continue
						end
					end

					-- Low HP (<=25%) / charge nuke: hold under-map, spam heals until ~max HP.
					if fleeing then
						diveFocusStream(lockedPos)
						tryCastEventHeal('under', hpFrac)
						if not diveNukeAnchor or math.abs((diveNukeAnchor.Y or 0) - underHoldY) > 4 then
							local ring = DIVE_FLEE_RING
							diveNukeAnchor = diveClampGoal(
								Vector3.new(
									lockedPos.X + math.cos(diveYaw) * ring,
									underHoldY,
									lockedPos.Z + math.sin(diveYaw) * ring
								),
								lockedPos,
								fleeClamp
							)
						end
						local under = diveNukeAnchor
						if holdingMend and typeof(diveMendingPos) == 'Vector3' then
							under = diveClampGoal(
								Vector3.new(diveMendingPos.X, underHoldY, diveMendingPos.Z),
								lockedPos,
								fleeClamp
							)
						end
						local tag = nukeFlee and 'nuke-under' or (panic and 'panic-under' or 'flee-under')
						if not underNow or math.abs(myPart.Position.Y - under.Y) > 3 then
							diveDebug(tag, string.format(
								'hp=%.0f%% y=%.0f arena=%.0f fight=%.0f',
								hpFrac * 100,
								under.Y,
								arenaFloorY,
								stickyFightY
							))
						end
						-- Hold under with flee clamp only — never fight-step (pulls Y back up).
						diveWriteCFrame(myPart, under, lockedPos, { clamp = fleeClamp, allowVerticalVel = true })
						pcall(function()
							lockReplicationFocus(getMyCharacterModel())
						end)
						task.wait(0.08)
						continue
					end

					-- Healed to max while still under — snap back to boss feet fight height.
					if not fleeing and hpFrac >= DIVE_HP_RETURN and underNow then
						diveNukeAnchor = nil
						local up = Vector3.new(lockedPos.X, stickyFightY, lockedPos.Z)
						diveSnapTo(myPart, up, bossAim or lockedPos, fightClamp)
						task.wait(0.06)
						continue
					end

					local liveRoot = getMobRoot(mob)
					if not liveRoot then
						missingRootSince = missingRootSince or os.clock()
						if (os.clock() - missingRootSince) > 0.9 then
							diveDebug('lost-root', mob.Name)
							break
						end
						local holdPos = diveComputeFightPos(mob, root, myPart.Position, lockedPos, pullIn)
						diveStepToward(myPart, holdPos or diveHoverAt(lockedPos), DIVE_TWEEN_SPEED, lockedPos)
						continue
					end
					missingRootSince = nil
					diveStickRoot = liveRoot

					-- Farm height slider → sticky Y every frame (don't wait on track interval).
					do
						local aboveNow = diveFarmAboveStuds()
						if math.abs(aboveNow - stickyAbove) > 0.05 then
							stickyFightY = stickyFightY - stickyAbove + aboveNow
							stickyAbove = aboveNow
							lockedPos = Vector3.new(lockedPos.X, stickyFightY, lockedPos.Z)
							fightClamp.yRef = stickyFightY
							fightClamp.yMin = stickyFightY - 2
							fightClamp.yMax = stickyFightY + 2
						end
					end

					if (os.clock() - lastTrustAt) >= (isBigBoss and DIVE_BOSS_TRACK_INTERVAL or 0.3) then
						lastTrustAt = os.clock()
						local trust = diveTrustMobPos(mob, liveRoot, myPart.Position, lockedPos)
						local headTopHold = isBigBoss and diveHeadTopBoss(mob)
						local trackAlpha = isBigBoss and (headTopHold and 0.38 or 0.62) or 0.15
						local trackMax = isBigBoss and 140 or 45
						if (trust - lockedPos).Magnitude < trackMax then
							lockedPos = Vector3.new(
								lockedPos.X + (trust.X - lockedPos.X) * trackAlpha,
								stickyFightY,
								lockedPos.Z + (trust.Z - lockedPos.Z) * trackAlpha
							)
						end
						if isBigBoss then
							local _, newFY, newFloor, newAim = diveFightHeights(mob, liveRoot, nil)
							local aboveNow = diveFarmAboveStuds()
							-- Slider changes apply immediately; bbox jitter still deadbanded.
							if newFY then
								local topNow = newFY - aboveNow
								local topSticky = stickyFightY - stickyAbove
								if math.abs(aboveNow - stickyAbove) > 0.05 then
									stickyFightY = newFY
									stickyAbove = aboveNow
								elseif math.abs(topNow - topSticky) > 5 then
									stickyFightY = newFY
									stickyAbove = aboveNow
									lockedFloorY = newFloor or lockedFloorY
									bossAim = newAim or bossAim
								end
								lockedPos = Vector3.new(lockedPos.X, stickyFightY, lockedPos.Z)
								fightClamp.yRef = stickyFightY
								fightClamp.yMin = stickyFightY - 2
								fightClamp.yMax = stickyFightY + 2
							end
						else
							-- Keep Y = mobTop + Farm height; slider always wins.
							local _, newFY = diveFightHeights(mob, liveRoot, nil)
							local aboveNow = diveFarmAboveStuds()
							if newFY then
								local topNow = newFY - aboveNow
								local topSticky = stickyFightY - stickyAbove
								if math.abs(aboveNow - stickyAbove) > 0.05 then
									stickyFightY = newFY
									stickyAbove = aboveNow
								elseif math.abs(topNow - topSticky) > 4 then
									stickyFightY = newFY
									stickyAbove = aboveNow
								end
								lockedPos = Vector3.new(lockedPos.X, stickyFightY, lockedPos.Z)
								fightClamp.yRef = stickyFightY
								fightClamp.yMin = stickyFightY - 2
								fightClamp.yMax = stickyFightY + 2
							end
						end
						--#region agent log
						pcall(function()
							local now = os.clock()
							if (now - (getgenv().SB2DbgStickyLogAt or 0)) < 0.9 then
								return
							end
							getgenv().SB2DbgStickyLogAt = now
							local line = game:GetService('HttpService'):JSONEncode({
								sessionId = '7e9135',
								runId = 'height-fix',
								hypothesisId = 'H-h1,H-h2',
								location = 'diveStickyY',
								message = 'sticky',
								data = {
									stickyY = math.floor(stickyFightY * 10 + 0.5) / 10,
									above = math.floor(stickyAbove * 10 + 0.5) / 10,
									posY = math.floor(myPart.Position.Y * 10 + 0.5) / 10,
									slider = diveOptNumber('DiveFarmHeight', -999),
									auto = diveAutoHeightOn(),
								},
								timestamp = math.floor(os.clock() * 1000),
							})
							if type(appendfile) == 'function' then
								appendfile('debug-7e9135.log', line .. '\n')
							end
						end)
						--#endregion
						diveLastCluster = lockedPos
					end

					-- If HP isn't dropping, orbit on the blade ring (not into the mesh).
					local noDmgFor = os.clock() - lastHpDropAt
					pullIn = (not isBigBoss)
						and noDmgFor > 1.4
						and (os.clock() - killStarted) > 1.2

					local stickPos, aimAt
					local headTopHold = isBigBoss and diveHeadTopBoss(mob)
					if isBigBoss then
						if headTopHold then
							-- Head/crown hold — Atheon, Deity, Aeganatos (no orbit jitter).
							stickPos = Vector3.new(lockedPos.X, stickyFightY, lockedPos.Z)
						else
							diveYaw += 0.025
							local ring = 4.5
							stickPos = Vector3.new(
								lockedPos.X + math.cos(diveYaw) * ring,
								stickyFightY,
								lockedPos.Z + math.sin(diveYaw) * ring
							)
						end
						aimAt = bossAim or lockedPos
					else
						stickPos, aimAt = diveComputeFightPos(mob, liveRoot, myPart.Position, lockedPos, pullIn)
						if not stickPos then
							stickPos = lockedPos
							aimAt = lockedPos
						end
						-- Always pin Y to Farm-height lock — XZ orbit only from computeFightPos.
						stickPos = Vector3.new(stickPos.X, stickyFightY, stickPos.Z)
					end
					-- Pin fight Y at feet-line lock; look-at stays on boss body center.
					stickPos = diveClampGoal(stickPos, lockedPos, fightClamp)
					stickPos = Vector3.new(stickPos.X, stickyFightY, stickPos.Z)
					if not aimAt then
						aimAt = bossAim or lockedPos
					end
					local flatNow = Vector3.new(myPart.Position.X - stickPos.X, 0, myPart.Position.Z - stickPos.Z)
					local distNow = flatNow.Magnitude
					local runawayLimit = isBigBoss and (DIVE_SAFE_FLAT + 95) or (DIVE_SAFE_FLAT + 30)
					if distNow > runawayLimit then
						runawayStrikes += 1
						diveDebug('runaway-snap', string.format('d=%.0f', distNow))
						local safe = diveClampGoal(
							Vector3.new(lockedPos.X, stickyFightY, lockedPos.Z),
							lockedPos,
							{ yRef = stickyFightY, yPad = 6 }
						)
						diveStepToward(myPart, safe, DIVE_TWEEN_SPEED * DIVE_DASH_CHASE_MULT, lockedPos)
						if runawayStrikes >= 3 then
							break
						end
					else
						runawayStrikes = 0
						local posDelta = (myPart.Position - stickPos).Magnitude
						local moveThresh = isBigBoss and (headTopHold and DIVE_BOSS_MOVE_THRESH or 4) or 2
						local yThresh = isBigBoss and (headTopHold and DIVE_BOSS_Y_THRESH or 3.5) or 3.5
						if posDelta > moveThresh or math.abs(myPart.Position.Y - stickyFightY) > yThresh then
							local chaseSpeed = DIVE_TWEEN_SPEED
							if isBigBoss and distNow > 14 then
								chaseSpeed = DIVE_TWEEN_SPEED * DIVE_DASH_CHASE_MULT
							end
							if isBigBoss and distNow > DIVE_DASH_BLINK_FLAT then
								diveWriteCFrame(myPart, stickPos, aimAt, { clamp = fightClamp, force = true })
							else
								diveStepToward(myPart, stickPos, chaseSpeed, aimAt, fightClamp)
							end
							lastMoveAt = os.clock()
						else
							-- On station: kill residual vertical velocity so we don't bob.
							pcall(function()
								local v = myPart.AssemblyLinearVelocity
								myPart.AssemblyLinearVelocity = Vector3.new(v.X, 0, v.Z)
								if diveLinVel then
									local lv = diveLinVel.VectorVelocity
									diveLinVel.VectorVelocity = Vector3.new(lv.X, 0, lv.Z)
								end
							end)
						end
						--#region agent log
						do
							local y = myPart.Position.Y
							local bag = getgenv().SB2DbgBobBag
							if type(bag) ~= 'table' then
								bag = { t0 = os.clock(), ymin = y, ymax = y, n = 0 }
								getgenv().SB2DbgBobBag = bag
							end
							bag.n = (bag.n or 0) + 1
							if y < bag.ymin then
								bag.ymin = y
							end
							if y > bag.ymax then
								bag.ymax = y
							end
							if (os.clock() - bag.t0) >= 1 then
								pcall(function()
									local lvY = diveLinVel and diveLinVel.VectorVelocity.Y or 0
									local line = game:GetService('HttpService'):JSONEncode({
										sessionId = '7e9135',
										runId = 'bob-verify',
										hypothesisId = 'H-bob',
										location = 'diveFightLoop',
										message = 'yRange1s',
										data = {
											yRange = math.floor((bag.ymax - bag.ymin) * 100 + 0.5) / 100,
											ymin = math.floor(bag.ymin * 10 + 0.5) / 10,
											ymax = math.floor(bag.ymax * 10 + 0.5) / 10,
											stickY = math.floor(stickyFightY * 10 + 0.5) / 10,
											posY = math.floor(y * 10 + 0.5) / 10,
											lvY = math.floor(lvY * 10 + 0.5) / 10,
											vy = math.floor(myPart.AssemblyLinearVelocity.Y * 10 + 0.5) / 10,
											station = posDelta <= moveThresh,
											n = bag.n,
										},
										timestamp = math.floor(os.clock() * 1000),
									})
									if type(appendfile) == 'function' then
										appendfile('debug-7e9135.log', line .. '\n')
									end
								end)
								getgenv().SB2DbgBobBag = { t0 = os.clock(), ymin = y, ymax = y, n = 0 }
							end
						end
						--#endregion
					end

					local hpNow = diveGetMobHealth(mob)
					if type(hpNow) == 'number' and type(lastHp) == 'number' and hpNow < lastHp - 0.25 then
						lastHp = hpNow
						lastHpDropAt = os.clock()
					elseif type(hpNow) == 'number' then
						lastHp = hpNow
					end
					-- Still alive but no damage after orbit attempts — soft skip, keep cache.
					if noDmgFor > 7 and (os.clock() - killStarted) > 8 then
						diveDebug('stale-hp', mob.Name)
						diveFinishedUntil[mob] = os.clock() + 0.5
						return
					end

					if not fleeing and (os.clock() - lastHit) >= DIVE_HIT_DELAY then
						lastHit = os.clock()
						local attackName = nil
						if isToggleOn('AutoSkill') then
							pcall(castSelectedSupportSkill)
							pcall(function()
								attackName = ensureSkillWindow()
							end)
						end
						pcall(fireMobAttack, mob, attackName)
					end

					if os.clock() - lastDbgAt > 1 then
						lastDbgAt = os.clock()
						local hitD = aimAt and (aimAt - myPart.Position).Magnitude or -1
						diveDebug(
							'fight',
							string.format(
								'hp=%s d=%.0f hitD=%.0f pull=%s',
								tostring(hpNow),
								distNow,
								hitD,
								tostring(pullIn)
							)
						)
					end

					if os.clock() - lastDiveStreamAt > 1.4 then
						lastDiveStreamAt = os.clock()
						diveFocusStream(lockedPos)
					end

					task.wait(headTopHold and 0.08 or 0.045)
				end

				diveDebug('done', string.format('%s dead=%s', tostring(mob.Name), tostring(isDeadMob(mob))))
				markDiveFinished(mob)
			end

			pcall(function()
				local mobsRoot = workspace:FindFirstChild('Mobs')
				if not mobsRoot then
					return
				end
				diveMobsFolderConns[#diveMobsFolderConns + 1] = mobsRoot.ChildAdded:Connect(function()
					-- New stream-ins are picked by the nearest loop automatically.
				end)
				diveMobsFolderConns[#diveMobsFolderConns + 1] = mobsRoot.ChildRemoved:Connect(function(child)
					if child == diveStickMob then
						markDiveFinished(child)
					end
				end)
			end)

			-- Toggle watchdog only (farm work is the AutoFarm-style thread).
			getgenv().SB2DiveFarmConn = RunService.Heartbeat:Connect(function()
				if not isToggleOn('DiveFarm') then
					stopDiveFarm(true)
					return
				end
				for _, plr in ipairs(Players:GetPlayers()) do
					if plr ~= LocalPlayer and not isOwnAlt(plr) then
						pcall(function()
							if Toggles.DiveFarm and Toggles.DiveFarm.SetValue then
								Toggles.DiveFarm:SetValue(false)
							end
						end)
						stopDiveFarm(true)
						Library:Notify(('Event vacuum off — %s here'):format(plr.DisplayName or plr.Name), 4)
						return
					end
				end
				if isToggleOn('CombatAnchor') or getgenv().SB2CombatAnchorOn == true then
					getgenv().SB2CombatAnchorOn = false
					pcall(function()
						if Toggles.CombatAnchor and Toggles.CombatAnchor.SetValue then
							Toggles.CombatAnchor:SetValue(false)
						end
					end)
					applyCombatAnchor(false)
					pcall(function()
						local hrp = getMyBringPart()
						if hrp then
							hrp.Anchored = false
						end
					end)
				end
			end)

			getgenv().SB2DiveFarmThread = task.spawn(function()
				local ok, err = pcall(function()
					Library:Notify('Event vacuum — AutoFarm-style tween → kill → next', 5)
					local reach0 = diveGetWeaponReach()
					Library:Notify(
						string.format('Event dive blade reach %.1f -> hover budget %.1f', reach0, diveHoverBudget(false)),
						4
					)
					while stillActive() do
						local myPart = getMyBringPart()
						if not myPart then
							task.wait(0.15)
							continue
						end
						if not isLocalAlive() then
							task.wait(0.2)
							continue
						end
						setDiveNoclip(true)
						pcall(cacheMobRealPositions, myPart.Position)
						local target = diveNearestMob(myPart.Position)
						if target then
							local killOk, killErr = pcall(diveKillUntilDead, myPart, target)
							if not killOk then
								diveDebug('kill-err', tostring(killErr))
								pcall(function()
									writefile(
										'PlayerTools/_dive_err_' .. tostring(LocalPlayer.Name) .. '.txt',
										tostring(killErr) .. '\n' .. tostring(getgenv().SB2DiveLastDebug)
									)
								end)
								task.wait(0.2)
							end
						else
							-- No mob in pad — roam the labyrinth (don't freeze on the boss edge).
							local dest = nil
							if diveFarmZone() then
								local needNew = not diveRoamGoal
									or os.clock() >= diveRoamUntil
									or (diveRoamGoal - myPart.Position).Magnitude < 22
								if needNew then
									diveRoamGoal = diveRoamFarmPos(myPart)
									diveRoamUntil = os.clock() + 3.5
								end
								dest = diveRoamGoal
								getgenv().SB2DivePendingStream = nil
							else
								dest = diveIdleHoverPos(myPart)
							end
							if dest then
								pcall(function()
									diveStepToward(myPart, dest, DIVE_TWEEN_SPEED, dest, {
										yRef = dest.Y,
										yMin = dest.Y - 4,
										yMax = dest.Y + 4,
										noClamp = true,
									})
								end)
								if math.abs(myPart.Position.Y - dest.Y) > 2 then
									pcall(function()
										local cf = CFrame.new(dest) * (myPart.CFrame - myPart.CFrame.Position)
										myPart.CFrame = cf
										diveLinVel.VectorVelocity = Vector3.zero
									end)
								end
							end
							local pending = getgenv().SB2DivePendingStream
							local streamAt = (typeof(pending) == 'Vector3' and pending)
								or diveLastCluster
								or myPart.Position
							if diveFarmZone() and typeof(streamAt) == 'Vector3' and not divePosInFarmZone(streamAt) then
								streamAt = diveFarmZoneCenter(myPart.Position.Y) or myPart.Position
							end
							if os.clock() - lastDiveStreamAt > 0.45 then
								lastDiveStreamAt = os.clock()
								diveFocusStream(streamAt)
							end
							task.wait(0.05)
						end
					end
				end)
				if not ok then
					warn('[PlayerTools] event vacuum error: ', err)
					pcall(function()
						writefile(
							'PlayerTools/_dive_err_' .. tostring(LocalPlayer.Name) .. '.txt',
							'thread: ' .. tostring(err)
						)
					end)
					diveDebug('thread-err', tostring(err))
				end
				if getgenv().SB2DiveFarmThread == coroutine.running() then
					getgenv().SB2DiveFarmThread = nil
				end
			end)

			-- If the farm thread dies while the toggle stays on, restart it.
			task.spawn(function()
				while getgenv()[CONFIG.GenvKey] do
					task.wait(1.25)
					if not isToggleOn('DiveFarm') then
						continue
					end
					if getgenv().SB2DiveFarmOn == true and getgenv().SB2DiveFarmThread == nil then
						diveDebug('thread-restart', 'DiveFarmOn but thread nil')
						pcall(startDiveFarm)
					end
				end
			end)
		end

		FarmBox:AddToggle('DiveFarm', {
			Text = 'Event vacuum (hover farm)',
			Default = false,
			Tooltip = 'AutoFarm-style vacuum. On F5 Desolate Dunes: farms the labyrinth only and stays out of the boss room. Noclip + fly while on. Auto-off when a non-alt joins.',
		}):OnChanged(function(value)
			if not value then
				stopDiveFarm(true)
				return
			end
			startDiveFarm()
			pcall(function()
				local zone = diveFarmZone()
				if zone then
					Library:Notify(
						('Event vacuum on — %s only (avoiding boss room)'):format(zone.label or 'farm zone'),
						6
					)
				else
					Library:Notify('Event vacuum on — noclip + fly. Off restores normal movement.', 6)
				end
			end)
		end)

		FarmBox:AddToggle('DiveAutoHeight', {
			Text = 'Auto farm height',
			Default = false,
			Tooltip = 'ON: raises Farm height to at least ~blade reach (never lowers your slider). OFF: exact Farm height slider only.',
		}):OnChanged(function()
			if isToggleOn('DiveFarm') then
				local hrp = getMyBringPart()
				local dest = diveIdleHoverPos(hrp)
				if hrp and dest then
					pcall(function()
						local cf = CFrame.new(dest) * (hrp.CFrame - hrp.CFrame.Position)
						hrp.CFrame = cf
						diveLinVel.VectorVelocity = Vector3.zero
					end)
				end
			end
		end)

		FarmBox:AddSlider('DiveFarmHeight', {
			Text = 'Farm height (vs mob top)',
			Default = 12,
			Min = -40,
			Max = 80,
			Rounding = 0,
			Tooltip = 'Studs relative to mob top. 0 = on top, positive = above, negative = lower into the mob. Auto farm height (if on) only raises this, never lowers. Saved outside profiles.',
		}):OnChanged(function()
			if type(getgenv().SB2PersistCombatPrefs) == 'function' then
				pcall(getgenv().SB2PersistCombatPrefs)
			end
			--#region agent log
			pcall(function()
				local line = game:GetService('HttpService'):JSONEncode({
					sessionId = '7e9135',
					runId = 'height-fix',
					hypothesisId = 'H-h1',
					location = 'DiveFarmHeight.OnChanged',
					message = 'slider',
					data = {
						slider = diveOptNumber('DiveFarmHeight', -999),
						above = diveFarmAboveStuds(),
						auto = diveAutoHeightOn(),
					},
					timestamp = math.floor(os.clock() * 1000),
				})
				if type(appendfile) == 'function' then
					appendfile('debug-7e9135.log', line .. '\n')
				end
			end)
			--#endregion
			if isToggleOn('DiveFarm') then
				local hrp = getMyBringPart()
				-- Idle preview only (fight loop applies sticky Y from slider live).
				if not (getgenv().SB2DiveFarmOn and diveStickRoot and diveStickRoot.Parent) then
					local dest = diveIdleHoverPos(hrp)
					if hrp and dest then
						pcall(function()
							local cf = CFrame.new(dest) * (hrp.CFrame - hrp.CFrame.Position)
							hrp.CFrame = cf
							diveLinVel.VectorVelocity = Vector3.zero
						end)
					end
				end
			end
		end)

		FarmBox:AddSlider('DiveFleeDepth', {
			Text = 'Flee depth (under floor)',
			Default = 38,
			Min = 10,
			Max = 120,
			Rounding = 0,
			Tooltip = 'How far under the arena floor to drop when avoiding death / healing. Saved outside profiles.',
		}):OnChanged(function()
			if type(getgenv().SB2PersistCombatPrefs) == 'function' then
				pcall(getgenv().SB2PersistCombatPrefs)
			end
		end)

		FarmBox:AddSlider('DiveFleeDepthBoss', {
			Text = 'Flee depth (bosses)',
			Default = 58,
			Min = 10,
			Max = 140,
			Rounding = 0,
			Tooltip = 'Under-floor depth for big / head-top bosses (uses the larger of this and Flee depth). Saved outside profiles.',
		}):OnChanged(function()
			if type(getgenv().SB2PersistCombatPrefs) == 'function' then
				pcall(getgenv().SB2PersistCombatPrefs)
			end
		end)

		-- Apply dive height/flee ASAP (SaveManager persist helpers may not exist yet).
		task.defer(function()
			pcall(function()
				if type(isfile) ~= 'function' or type(readfile) ~= 'function' then
					return
				end
				if not isfile(COMBAT_PREFS_PATH) then
					return
				end
				local ok, data = pcall(function()
					return game:GetService('HttpService'):JSONDecode(readfile(COMBAT_PREFS_PATH))
				end)
				if not ok or type(data) ~= 'table' then
					return
				end
				for _, key in ipairs({ 'DiveFarmHeight', 'DiveFleeDepth', 'DiveFleeDepthBoss' }) do
					local n = tonumber(data[key])
					local opt = Options and Options[key]
					if n ~= nil and type(opt) == 'table' and type(opt.SetValue) == 'function' then
						pcall(function()
							opt:SetValue(n)
						end)
					end
				end
				--#region agent log
				pcall(function()
					local line = game:GetService('HttpService'):JSONEncode({
						sessionId = '7e9135',
						runId = 'flee-prefs',
						hypothesisId = 'H-race',
						location = 'CombatBox:earlyApplyDivePrefs',
						message = 'early apply dive prefs',
						data = {
							fileFlee = data.DiveFleeDepth,
							fileBoss = data.DiveFleeDepthBoss,
							fileH = data.DiveFarmHeight,
							liveFlee = Options.DiveFleeDepth and Options.DiveFleeDepth.Value,
							liveBoss = Options.DiveFleeDepthBoss and Options.DiveFleeDepthBoss.Value,
						},
						timestamp = math.floor(os.clock() * 1000),
					})
					if type(appendfile) == 'function' then
						appendfile('debug-7e9135.log', line .. '\n')
					end
				end)
				--#endregion
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
			local defaultFarmSupport = table.find(farmSupport, 'Cursed Enhancement') and 'Cursed Enhancement' or farmSupport[1]
			local defaultFarmHeal = table.find(farmHeal, 'Heal') and 'Heal' or farmHeal[2]
			FarmBox:AddDropdown('FarmSkillName', {
				Text = 'Dive weapon skill',
				Values = farmSkills,
				Default = defaultFarmSkill,
				AllowNull = false,
				Searchable = true,
				Tooltip = 'Weapon skill used while Event dive is on.',
			})
			FarmBox:AddDropdown('FarmSupportSkillName', {
				Text = 'Dive support skills',
				Values = farmSupport,
				Default = defaultFarmSupport and { defaultFarmSupport } or {},
				Multi = true,
				AllowNull = true,
				Searchable = true,
				Tooltip = 'Multi-select. Cast order = pick order. Cursed Enhancement always first when ready. Under map: heals first.',
			})
			pcall(function()
				Options.FarmSupportSkillName:OnChanged(function(value)
					syncMultiSkillOrder('SB2FarmSupportSkillOrder', collectMultiSkillMap(value))
					if type(getgenv().SB2PersistCombatPrefs) == 'function' then
						pcall(getgenv().SB2PersistCombatPrefs)
					end
				end)
			end)
			FarmBox:AddDropdown('FarmHealSkillName', {
				Text = 'Dive heal (burst)',
				Values = farmHeal,
				Default = defaultFarmHeal or 'Heal',
				AllowNull = false,
				Searchable = true,
				Tooltip = 'Heal — one-shot HP dump. Used on poison, fire, or low HP.',
			})
			local defaultFarmMend = table.find(farmHeal, 'Mending Spirit') and 'Mending Spirit' or 'Mending Spirit'
			FarmBox:AddDropdown('FarmMendSkillName', {
				Text = 'Dive heal (AoE)',
				Values = farmHeal,
				Default = defaultFarmMend,
				AllowNull = false,
				Searchable = true,
				Tooltip = 'Mending Spirit — HoT. Stay in the circle until it ends.',
			})
			pcall(function()
				local function persistFarmSkill()
					if type(getgenv().SB2PersistCombatPrefs) == 'function' then
						pcall(getgenv().SB2PersistCombatPrefs)
					end
				end
				if Options.FarmSkillName and Options.FarmSkillName.OnChanged then
					Options.FarmSkillName:OnChanged(persistFarmSkill)
				end
				if Options.FarmHealSkillName and Options.FarmHealSkillName.OnChanged then
					Options.FarmHealSkillName:OnChanged(persistFarmSkill)
				end
				if Options.FarmMendSkillName and Options.FarmMendSkillName.OnChanged then
					Options.FarmMendSkillName:OnChanged(persistFarmSkill)
				end
			end)
			pcall(function()
				refreshSkillDropdown(false)
			end)
		end

		-- Anyone else joining → kill combat so you don't look blatant / get Secure API'd.
		local function stopCombatRuntime(unanchor)
			getgenv().SB2AutoAttackOn = false
			getgenv().SB2CombatAnchorOn = false
			local aa = getgenv().SB2AutoAttackConn
			if aa then
				pcall(function()
					aa:Disconnect()
				end)
				getgenv().SB2AutoAttackConn = nil
			end
			local anc = getgenv().SB2CombatAnchorConn
			if anc then
				pcall(function()
					anc:Disconnect()
				end)
				getgenv().SB2CombatAnchorConn = nil
			end
			if unanchor ~= false then
				getgenv().SB2AnchorHoldUntil = 0
				pcall(applyCombatAnchor, false)
			end
		end
		getgenv().SB2StopCombatRuntime = stopCombatRuntime

		local disableCombatForPlayerJoin = function(joiner)
			if not joiner or joiner == LocalPlayer or isOwnAlt(joiner) then
				return
			end
			-- Always kill Event dive — blatant while strangers are here.
			local diveWasOn = false
			pcall(function()
				local dive = Toggles.DiveFarm
				if type(dive) == 'table' and dive.Value == true then
					diveWasOn = true
					if type(dive.SetValue) == 'function' then
						dive:SetValue(false)
					end
				end
			end)
			if getgenv().SB2DiveFarmOn or diveWasOn then
				pcall(function()
					if type(stopDiveFarm) == 'function' then
						stopDiveFarm(true)
					else
						getgenv().SB2DiveFarmOn = false
						local th = getgenv().SB2DiveFarmThread
						if th then
							pcall(task.cancel, th)
						end
						getgenv().SB2DiveFarmThread = nil
					end
				end)
				pcall(function()
					Library:Notify(('Event vacuum off — %s joined'):format(joiner.DisplayName or joiner.Name), 4)
				end)
			end
			-- Always turn off the combat trio when a stranger joins.
			-- Resume stays ON so we re-arm + TP once the server is empty again.
			local changed = false
			for _, name in ipairs({ 'AutoAttack', 'AutoSkill', 'CombatAnchor' }) do
				local toggle = Toggles[name]
				if type(toggle) == 'table' and toggle.Value == true and type(toggle.SetValue) == 'function' then
					pcall(function()
						toggle:SetValue(false)
					end)
					changed = true
				end
			end
			getgenv().SB2AutoAttackOn = false
			getgenv().SB2AutoSkillOn = false
			getgenv().SB2CombatAnchorOn = false
			stopCombatRuntime(true)
			if changed then
				pcall(function()
					Library:Notify(('Combat off — %s joined'):format(joiner.DisplayName or joiner.Name), 4)
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
			getgenv().SB2CombatJoinDisableConn = safeConnect(Players.PlayerAdded, disableCombatForPlayerJoin)
			-- Already-populated servers: shut combat/dive down if a stranger is here.
			task.defer(function()
				for _, plr in ipairs(Players:GetPlayers()) do
					if plr ~= LocalPlayer and not isOwnAlt(plr) then
						disableCombatForPlayerJoin(plr)
						break
					end
				end
			end)
		end

		-- Keep toggle UI in sync with live combat. SaveManager/display glitches can
		-- show Default=false while AutoAttack/Anchor connections are still running.
		task.spawn(function()
			while getgenv()[CONFIG.GenvKey] do
				task.wait(2)
				if getgenv().SB2ConfigLoading then
					continue
				end
				pcall(function()
					local diving = isToggleOn('DiveFarm') or getgenv().SB2DiveFarmOn == true
					if diving then
						getgenv().SB2CombatAnchorOn = false
					end
					local pairsOn = {
						AutoAttack = getgenv().SB2AutoAttackOn == true,
						AutoSkill = getgenv().SB2AutoSkillOn == true,
						CombatAnchor = (not diving) and getgenv().SB2CombatAnchorOn == true,
					}
					for name, want in pairs(pairsOn) do
						local toggle = Toggles[name]
						if type(toggle) ~= 'table' then
							continue
						end
						if want and toggle.Value ~= true and type(toggle.SetValue) == 'function' then
							toggle:SetValue(true)
						elseif want and toggle.Value == true and type(toggle.Display) == 'function' then
							toggle:Display()
						end
					end
					local looksWiped = getgenv().SB2ProfileUiLooksWiped
					local reapply = getgenv().SB2ReapplyProfileUi
					if type(looksWiped) == 'function' and looksWiped() and type(reapply) == 'function' then
						local lastAt = getgenv().SB2LastProfileReapplyAt or 0
						if os.clock() - lastAt > 15 then
							getgenv().SB2LastProfileReapplyAt = os.clock()
							reapply('menu reset while still in-game')
						end
					end
				end)
			end
		end)

		do
			local skillValues = getAvailableSkills()
			local supportValues = getAvailableSupportSkills()
			-- Fresh UI / no profile: none. SaveManager still restores a saved skill after load.
			local defaultSkill = '(none)'
			CombatBox:AddDropdown('SkillName', {
				Text = 'Skill (held weapon)',
				Values = skillValues,
				Default = defaultSkill,
				AllowNull = false,
				Searchable = true,
			})
			CombatBox:AddDropdown('SupportSkillName', {
				Text = 'Support skills (buffs)',
				Values = supportValues,
				Default = {},
				Multi = true,
				AllowNull = true,
				Searchable = true,
				Tooltip = 'Multi-select anytime buffs. Order = selection order. Cursed Enhancement always first when ready. Under map: heals first.',
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
					if type(getgenv().SB2PersistCombatPrefs) == 'function' then
						getgenv().SB2PersistCombatPrefs()
						return
					end
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
					local map = collectMultiSkillMap(value)
					local order = syncMultiSkillOrder('SB2SupportSkillOrder', map)
					rememberPickedSkills(nil, order)
				end)
			end)
			CombatBox:AddToggle('SupportSkill', {
				Text = 'Auto support skill',
				Default = false,
				Tooltip = 'Cast the support buff (CE etc.) on its cooldown while Auto skill is on. Saved with your autoload profile.',
			})
			CombatBox:AddToggle('SupportBossOnly', {
				Text = 'Support only on bosses',
				Default = false,
				Tooltip = 'Only cast support near bosses / event elites (Aeganatos, Saurus, Meta Figure, DJ Reaper). Off = cast whenever Auto support is on. Saved with your autoload profile.',
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
			local isAlt = getgenv().SB2IsOwnAlt or isOwnAlt
			for _, plr in ipairs(Players:GetPlayers()) do
				if plr ~= LocalPlayer and not isAlt(plr) then
					return true
				end
			end
			return false
		end

		local function countNonAltPlayers()
			local isAlt = getgenv().SB2IsOwnAlt or isOwnAlt
			local n = 0
			for _, plr in ipairs(Players:GetPlayers()) do
				if plr ~= LocalPlayer and not isAlt(plr) then
					n += 1
				end
			end
			return n
		end

		local function setCombatTrio(enabled)
			enabled = enabled == true
			local diving = isToggleOn('DiveFarm') or getgenv().SB2DiveFarmOn == true
			task.spawn(function()
				for _, name in ipairs(COMBAT_TRIO) do
					-- Event dive owns movement — never force Anchor on while diving.
					if name == 'CombatAnchor' and (diving or (enabled and (isToggleOn('DiveFarm') or getgenv().SB2DiveFarmOn == true))) then
						pcall(function()
							local toggle = Toggles.CombatAnchor
							if type(toggle) == 'table' and type(toggle.SetValue) == 'function' then
								if toggle.Value == true then
									toggle:SetValue(false)
								end
							end
						end)
						getgenv().SB2CombatAnchorOn = false
						pcall(function()
							if type(applyCombatAnchor) == 'function' then
								applyCombatAnchor(false)
							end
						end)
						continue
					end
					local toggle = Toggles[name]
					if type(toggle) == 'table' and type(toggle.SetValue) == 'function' then
						pcall(function()
							-- Linoria skips OnChanged if the value is unchanged, so
							-- combat loops never start after autoload paints the toggle.
							-- Yield between flips so a deferred false cannot win the race.
							if toggle.Value == enabled then
								toggle:SetValue(not enabled)
								task.wait()
							end
							toggle:SetValue(enabled)
						end)
					end
				end
				getgenv().SB2AutoAttackOn = enabled
				getgenv().SB2AutoSkillOn = enabled
				if diving or isToggleOn('DiveFarm') or getgenv().SB2DiveFarmOn == true then
					getgenv().SB2CombatAnchorOn = false
					pcall(function()
						if type(applyCombatAnchor) == 'function' then
							applyCombatAnchor(false)
						end
					end)
				else
					getgenv().SB2CombatAnchorOn = enabled
				end
				if not enabled then
					pcall(function()
						if type(applyCombatAnchor) == 'function' then
							applyCombatAnchor(false)
						end
					end)
				end
			end)
		end

		local function armCombatTrioIfSolo()
			if otherPlayersPresent() then
				return false
			end
			setCombatTrio(true)
			return true
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
			local pid = game.PlaceId
			for _, rec in ipairs(store.waypoints) do
				if type(rec) == 'table' and type(rec.name) == 'string' and string.lower(rec.name) == lname then
					local wpPlace = tonumber(rec.placeId)
					-- Never use a waypoint saved on a different floor (saurus on F2 = void TP).
					if wpPlace ~= nil and wpPlace ~= pid then
						return nil
					end
					return rec
				end
			end
			return nil
		end

		local function destIsBossRouteWp(pos)
			if typeof(pos) ~= 'Vector3' then
				return false
			end
			local store = getgenv().SB2Waypoints and getgenv().SB2Waypoints.store
			if not (store and type(store.waypoints) == 'table') then
				return false
			end
			local keys = { 'warlord', 'hunter', 'limor', 'radioactive', 'radio', 'experiment' }
			for _, rec in ipairs(store.waypoints) do
				if type(rec) == 'table' and type(rec.name) == 'string' then
					local n = string.lower(rec.name)
					local hit = false
					for _, k in ipairs(keys) do
						if n:find(k, 1, true) then
							hit = true
							break
						end
					end
					if hit then
						local p = Vector3.new(tonumber(rec.x) or 0, tonumber(rec.y) or 0, tonumber(rec.z) or 0)
						if (pos - p).Magnitude <= 22 then
							return true
						end
					end
				end
			end
			return false
		end

		local function applyCharacterCFrame(cf)
			-- Hard gate: kills zombie boss-route / resume TP loops after soft-reload.
			local gate = getgenv().SB2TpGate
			if type(gate) == 'table' and gate.block == true then
				return false, 'tp blocked'
			end
			-- Never TP into the void — every alt ended up dealing 0 damage out of range.
			if typeof(cf) == 'CFrame' and cf.Position.Y < -20 then
				-- #region agent log
				if type(getgenv().SB2DbgFling) == 'function' then
					pcall(getgenv().SB2DbgFling, 'A', 'applyCharacterCFrame', 'tp_void_reject', {
						y = cf.Position.Y,
						x = cf.Position.X,
						z = cf.Position.Z,
					})
				end
				-- #endregion
				return false, 'void destination'
			end
			-- Zombie boss-route loops ignore the new toggle. Never CFrame onto boss pads
			-- unless the route is actually wanted (or Resume is using that pad).
			if getgenv().SB2BossRouteWanted ~= true and not isToggleOn('SoloCombatResume') then
				local pos = nil
				pcall(function()
					pos = cf.Position
				end)
				if pos and destIsBossRouteWp(pos) then
					return false, 'boss route off'
				end
			end
			-- Never open an unanchor window here — gravity + unstreamed floor = into the ground.
			getgenv().SB2AnchorHoldUntil = 0
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
				if model.PivotTo then
					model:PivotTo(cf)
				else
					hrp.CFrame = cf
				end
				hrp.AssemblyLinearVelocity = Vector3.zero
				hrp.AssemblyAngularVelocity = Vector3.zero
				-- Stay unanchored — pinTeleportCFrame soft-holds so server gets the TP.
				if type(getgenv().SB2SetAnchorLockCF) == 'function' then
					getgenv().SB2SetAnchorLockCF(cf)
				else
					getgenv().SB2AnchorLockCF = cf
				end
			end)
			-- Hold destination for ~1s so Combat Anchor / Heartbeat cannot lag behind gravity.
			if type(pinTeleportCFrame) == 'function' then
				pinTeleportCFrame(cf, 1.0)
			elseif type(getgenv().SB2PinTeleportCFrame) == 'function' then
				getgenv().SB2PinTeleportCFrame(cf, 1.0)
			end
			for _ = 1, 8 do
				RunService.Heartbeat:Wait()
				pcall(function()
					hrp.Anchored = false
					if (hrp.Position - cf.Position).Magnitude > 4 then
						if model.PivotTo then
							model:PivotTo(cf)
						else
							hrp.CFrame = cf
						end
					end
					hrp.AssemblyLinearVelocity = Vector3.zero
					hrp.AssemblyAngularVelocity = Vector3.zero
				end)
				if (hrp.Position - cf.Position).Magnitude <= 8 then
					break
				end
			end
			lockReplicationFocus(model)
			pcall(function()
				LocalPlayer:RequestStreamAroundAsync(cf.Position, 48)
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
				-- Do NOT call SB2WaypointsTeleportNamed here — that can TeleportService
				-- you to another floor while Resume is merely trying to stand somewhere.
				return false, 'waypoint not on this floor'
			end
			local wpPlace = tonumber(wp.placeId)
			if wpPlace and wpPlace ~= game.PlaceId then
				return false, 'waypoint is on another floor'
			end
			local cf = CFrame.new(tonumber(wp.x) or 0, tonumber(wp.y) or 0, tonumber(wp.z) or 0)
			return applyCharacterCFrame(cf)
		end

		local lastSoloResumeAt = 0
		-- force = ignore Resume toggle being off (profile restore / arm).
		-- TP still requires no non-alt players, except the explicit "Resume now" button.
		local function resumeSoloCombat(reason, force)
			if getgenv().SB2AutoBlockHopping and game.PlaceId == 542351431 then
				return
			end
			if not force and not isToggleOn('SoloCombatResume') then
				return
			end
			local allowBusyTp = reason == 'button'
			local function serverHasStrangers()
				return otherPlayersPresent() == true
			end
			if not allowBusyTp and serverHasStrangers() then
				-- Do NOT force Auto skill / attack / Anchor back on while strangers are here.
				-- Resume toggle stays on; PlayerRemoving → empty will re-arm + TP.
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
			task.wait(0.05)
			-- Re-check: Players list can be empty for a frame during load/hop.
			if not allowBusyTp and serverHasStrangers() then
				return
			end
			local okTp, errTp = teleportSoloWaypoint()
			-- applyCharacterCFrame already pins + anchors; do not holdCombatAnchor (unanchors).
			setCombatTrio(true)
			pcall(function()
				if okTp then
					Library:Notify('Solo — teleported, then combat/anchor', 4)
				elseif tostring(errTp or ''):find('floor', 1, true) then
					Library:Notify('Solo — combat on (saurus waypoint is F11-only; no cross-floor TP)', 5)
				else
					Library:Notify(
						('Solo — combat on (%s)'):format(tostring(errTp or reason or 'no waypoint')),
						4
					)
				end
			end)
		end

		-- Auto-block runtime lives in Infinite Yield plugin AutoBlock.iy.
		-- PlayerTools only writes PlayerTools/autoblock + syncs the IY owner.
		local AutoBlock = (function()
			local statusText = 'off'
			local paintFn

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
				statusText = tostring(text or 'off')
				if type(paintFn) == 'function' then
					pcall(paintFn)
				end
			end

			local function syncIy(on, silent, opts)
				opts = type(opts) == 'table' and opts or {}
				on = on == true
				silent = silent == true
				getgenv().SB2AutoBlockWanted = on
				-- Always update user intent when syncing from the Solo toggle.
				if opts.userChoice == true or opts.clearUser == true or on == false then
					getgenv().SB2AutoBlockUserWanted = on == true
				end
				writeAutoblockFile(on)
				if type(getgenv().SB2SetAutoBlock) == 'function' then
					pcall(getgenv().SB2SetAutoBlock, on, true, {
						persist = true,
						userChoice = true,
						armPresent = on == true,
					})
				elseif on and not silent then
					Library:Notify('Install IY plugin AutoBlock.iy — PlayerTools no longer runs auto-block', 6)
				end
				if getgenv().SB2AutoBlockIyOwner == true then
					setAutoStatus(on and ((getgenv().SB2AutoBlockStatus or 'watching') .. ' · IY') or 'off · IY')
				else
					setAutoStatus(on and 'on (need AutoBlock.iy)' or 'off')
				end
				return on
			end

			local function afterConfig()
				if not getgenv().SB2SoloBlockProfileReady then
					return
				end
				local toggleOn = false
				pcall(function()
					local t = Toggles.AutoBlockJoin
					toggleOn = type(t) == 'table' and t.Value == true
				end)
				local fileOn = autoblockFileOn()
				local profileBlock = false
				pcall(function()
					local last = getgenv().SB2LastSoloBlock
					profileBlock = type(last) == 'table' and last.AutoBlockJoin == true
				end)
				local on = toggleOn or fileOn or profileBlock
				if profileBlock and not toggleOn then
					pcall(function()
						local t = Toggles.AutoBlockJoin
						if type(t) == 'table' and type(t.SetValue) == 'function' then
							t:SetValue(true)
						end
					end)
				end
				if on then
					syncIy(true, true)
					if type(getgenv().SB2ArmAutoBlockTimers) == 'function' then
						pcall(getgenv().SB2ArmAutoBlockTimers, 0)
					end
				elseif getgenv().SB2SoloBlockAppliedOnce then
					local fsf = getgenv().SB2FreshServerFinder
					local freshOn = type(fsf) == 'table' and fsf.active == true
					if not freshOn then
						syncIy(false, true)
					end
				else
					setAutoStatus(getgenv().SB2AutoBlockIyOwner and 'off · IY' or 'off')
				end
			end

			getgenv().SB2AutoBlockAfterConfig = afterConfig
			-- Never own SB2SetAutoBlock here — AutoBlock.iy must keep it.

			return {
				fileOn = autoblockFileOn,
				writeFile = writeAutoblockFile,
				setStatus = setAutoStatus,
				sync = syncIy,
				armPresent = function()
					if type(getgenv().SB2ArmAutoBlockTimers) == 'function' then
						pcall(getgenv().SB2ArmAutoBlockTimers, 0)
					end
				end,
				startTimer = function() end,
				cancelTimer = function() end,
				cancelAll = function()
					if type(getgenv().SB2SetAutoBlock) == 'function' then
						pcall(getgenv().SB2SetAutoBlock, false)
					end
				end,
				clearHop = function() end,
				afterConfig = afterConfig,
				status = function()
					return statusText
				end,
				setPaint = function(fn)
					paintFn = fn
					getgenv().SB2AutoBlockPaint = fn
				end,
				wait = 15,
				testWait = 5,
			}
		end)()

		local SoloBox = FarmTab:AddRightGroupbox('Solo resume')
		assert(SoloBox, 'Solo resume groupbox nil')
		SoloBox:AddToggle('SoloCombatResume', {
			Text = 'Resume',
			Default = false,
			Tooltip = 'When a stranger joins: Auto skill / Auto attack / Anchor / Event dive turn OFF. Resume stays on — when only you/alts remain, TP to WP and turn combat back on. Saved with your profile.',
		}):OnChanged(function(value)
			-- Autoload Default=false must not wipe the sidecar / leave Resume off after profile load.
			if getgenv().SB2ConfigLoading then
				if value == true then
					if type(writefile) == 'function' then
						pcall(writefile, SOLO_RESUME_PATH, 'true')
					end
					getgenv().SB2ResumeAfterConfig = true
					getgenv().SB2StickyResumeWanted = true
					if not otherPlayersPresent() then
						setCombatTrio(true)
					end
					-- Config path used to skip TP entirely — schedule once loading settles.
					task.delay(2.0, function()
						if type(getgenv().SB2ResumeSoloCombat) == 'function' then
							pcall(getgenv().SB2ResumeSoloCombat, 'toggle-load', true)
						end
					end)
				elseif getgenv().SB2StickyResumeWanted == true then
					-- Profile said ON; ignore Default=false / late SaveManager paints.
					task.defer(function()
						local t = Toggles.SoloCombatResume
						if type(t) == 'table' and type(t.SetValue) == 'function' and t.Value ~= true then
							getgenv().SB2ConfigLoading = true
							pcall(function()
								t:SetValue(true)
							end)
							getgenv().SB2ConfigLoading = false
						end
					end)
				end
				return
			end
			if type(writefile) == 'function' then
				pcall(writefile, SOLO_RESUME_PATH, value and 'true' or 'false')
			end
			if not value then
				-- Real user off — stop all resume forcing so this stays a normal toggle.
				getgenv().SB2StickyResumeWanted = false
				getgenv().SB2ForceResumeWanted = false
				getgenv().SB2ResumeAssertUntil = 0
				getgenv().SB2ResumeGuardUntil = 0
				getgenv().SB2ResumeAfterConfig = false
				getgenv().SB2SoloBootTpGen = (tonumber(getgenv().SB2SoloBootTpGen) or 0) + 1
				local last = getgenv().SB2LastSoloBlock
				if type(last) == 'table' then
					last.SoloCombatResume = false
				end
				local profile = getgenv().SB2LastProfileToggles
				if type(profile) == 'table' then
					profile.SoloCombatResume = false
				end
				-- Resume owns the combat trio — turn them off with it.
				setCombatTrio(false)
				Library:Notify('Resume off — Auto skill / Auto attack / Combat Anchor off', 3)
				return
			end
			getgenv().SB2StickyResumeWanted = true
			getgenv().SB2ForceResumeWanted = false
			getgenv().SB2ResumeAssertUntil = 0
			-- Allow intentional Resume TPs after a boss-route hard-stop.
			getgenv().SB2TpGate = getgenv().SB2TpGate or {}
			getgenv().SB2TpGate.block = false
			if otherPlayersPresent() then
				-- Don't arm combat while strangers are here — wait for empty.
				Library:Notify('Resume on — combat stays off until only you/alts remain, then TP', 4)
				return
			end
			setCombatTrio(true)
			task.spawn(function()
				resumeSoloCombat('toggle', true)
			end)
		end)
		-- Only block SaveManager false-paints during profile load — never lock the
		-- toggle for minutes (that made Resume feel like a stuck ON button).
		do
			local t = Toggles.SoloCombatResume
			if type(t) == 'table' and type(t.SetValue) == 'function' and not t._sb2ResumeGuard then
				t._sb2ResumeGuard = true
				local origSet = t.SetValue
				t.SetValue = function(self, value)
					if getgenv().SB2ConfigLoading == true
						and getgenv().SB2StickyResumeWanted == true
						and value ~= true
					then
						value = true
					end
					return origSet(self, value)
				end
			end
		end

		local function assertResumeOn(reason)
			-- Restore Resume when sticky/force says ON. Soft during load; also for a
			-- post-load grace (AssertUntil / GuardUntil) so profile apply still works
			-- after SB2ConfigLoading flips false.
			if getgenv().SB2StickyResumeWanted ~= true and getgenv().SB2ForceResumeWanted ~= true then
				return false
			end
			local untilT = math.max(
				tonumber(getgenv().SB2ResumeAssertUntil) or 0,
				tonumber(getgenv().SB2ResumeGuardUntil) or 0
			)
			local allow = getgenv().SB2ConfigLoading == true
				or getgenv().SB2ForceResumeWanted == true
				or os.clock() < untilT
			if not allow then
				return false
			end
			local t = Toggles.SoloCombatResume
			if type(t) ~= 'table' or type(t.SetValue) ~= 'function' then
				return false
			end
			if t.Value == true then
				return true
			end
			getgenv().SB2ConfigLoading = true
			pcall(function()
				t:SetValue(true)
			end)
			getgenv().SB2ConfigLoading = false
			if type(writefile) == 'function' then
				pcall(writefile, SOLO_RESUME_PATH, 'true')
			end
			return t.Value == true
		end
		getgenv().SB2AssertResumeOn = assertResumeOn

		-- Brief post-load nudge only (not a forever ON lock).
		task.spawn(function()
			local gen = (tonumber(getgenv().SB2ResumeAssertGen) or 0) + 1
			getgenv().SB2ResumeAssertGen = gen
			local untilT = os.clock() + 12
			while getgenv()[CONFIG.GenvKey] and getgenv().SB2ResumeAssertGen == gen and os.clock() < untilT do
				if getgenv().SB2ConfigLoading == true and getgenv().SB2StickyResumeWanted == true then
					pcall(assertResumeOn, 'watchdog')
				end
				if getgenv().SB2ConfigLoading == true then
					local since = tonumber(getgenv().SB2ConfigLoadingSince) or 0
					if since <= 0 then
						getgenv().SB2ConfigLoadingSince = os.clock()
					elseif os.clock() - since > 8 then
						getgenv().SB2ConfigLoading = false
						getgenv().SB2ConfigLoadingSince = 0
					end
				else
					getgenv().SB2ConfigLoadingSince = 0
				end
				task.wait(0.75)
			end
		end)
		SoloBox:AddButton('Resume now (TP then anchor)', function()
			task.spawn(function()
				resumeSoloCombat('button', true)
			end)
		end)
		SoloBox:AddToggle('AutoBlockJoin', {
			Text = 'Auto block (IY plugin)',
			Default = false,
			Tooltip = 'Writes PlayerTools/autoblock and syncs Infinite Yield plugin AutoBlock.iy. Install that plugin — PlayerTools no longer runs block/hop itself. Saved with your profile.',
		}):OnChanged(function(value)
			if getgenv().SB2ConfigLoading then
				-- File/state already written by AutoBlock.iy / profile apply — do not re-sync (toast spam).
				return
			end
			getgenv().SB2SoloBlockAppliedOnce = true
			AutoBlock.sync(value == true, true, { userChoice = true })
			Library:Notify(
				value and 'Auto block on — handled by AutoBlock.iy' or 'Auto block off',
				4
			)
		end)
		local autoBlockLabel = SoloBox:AddLabel(AutoBlock.status())
		AutoBlock.setPaint(function()
			pcall(function()
				local text = AutoBlock.status()
				if getgenv().SB2AutoBlockIyOwner ~= true then
					if getgenv().SB2AutoBlockWanted == true then
						text = 'on (need AutoBlock.iy)'
					else
						text = 'off'
					end
				elseif getgenv().SB2AutoBlockStatus then
					text = tostring(getgenv().SB2AutoBlockStatus) .. ' · IY'
				elseif getgenv().SB2AutoBlockWanted == true then
					text = 'watching · IY'
				end
				if autoBlockLabel and type(autoBlockLabel.SetText) == 'function' then
					autoBlockLabel:SetText(text)
				elseif autoBlockLabel then
					autoBlockLabel.Text = text
				end
			end)
		end)
		SoloBox:AddButton('Arm auto-block now', function()
			getgenv().SB2ConfigLoading = false
			getgenv().SB2SoloBlockProfileReady = true
			pcall(function()
				local t = Toggles.AutoBlockJoin
				if type(t) == 'table' and type(t.SetValue) == 'function' then
					t:SetValue(true)
				end
			end)
			AutoBlock.sync(true, false)
			AutoBlock.armPresent()
			if getgenv().SB2AutoBlockIyOwner ~= true then
				Library:Notify('Install IY plugin AutoBlock.iy first', 5)
			else
				Library:Notify('Auto block armed via IY', 4)
			end
		end)
		SoloBox:AddButton('IY abarm (present)', function()
			AutoBlock.sync(true, true)
			AutoBlock.armPresent()
			Library:Notify('Told IY to arm everyone already here', 4)
		end)

		-- Own IIFE: fresh-finder locals were tipping the Solo/Combat 200-register limit.
		;(function()
		local freshFinderLabel
		local freshFinderBusy = false
		local freshFinderSyncing = false
		local FRESH_FINDER_MAX_HOPS = 60
		local HttpService = game:GetService('HttpService')

		local function paintFreshFinder(text)
			if freshFinderLabel and type(freshFinderLabel.SetText) == 'function' then
				freshFinderLabel:SetText(tostring(text or 'Fresh finder: off'))
			elseif freshFinderLabel then
				freshFinderLabel.Text = tostring(text or 'Fresh finder: off')
			end
		end

		local function syncFreshFinderToggle(on)
			local t = Toggles and Toggles.FreshServerFinder
			if type(t) ~= 'table' or type(t.SetValue) ~= 'function' then
				return
			end
			local want = on == true
			if t.Value == want then
				return
			end
			freshFinderSyncing = true
			pcall(function()
				t:SetValue(want)
			end)
			freshFinderSyncing = false
		end

		local function readFreshFinderState()
			local fsf = getgenv().SB2FreshServerFinder
			if type(fsf) == 'table' then
				return fsf
			end
			if type(isfile) == 'function' and type(readfile) == 'function' then
				local ok, exists = pcall(isfile, FRESH_FINDER_PATH)
				if ok and exists then
					local okRead, body = pcall(readfile, FRESH_FINDER_PATH)
					if okRead and type(body) == 'string' and body ~= '' then
						local okJson, data = pcall(function()
							return HttpService:JSONDecode(body)
						end)
						if okJson and type(data) == 'table' then
							getgenv().SB2FreshServerFinder = data
							return data
						end
					end
				end
			end
			return nil
		end

		local function writeFreshFinderState(data)
			data = type(data) == 'table' and data or { active = false }
			getgenv().SB2FreshServerFinder = data
			if type(writefile) == 'function' then
				pcall(function()
					if type(makefolder) == 'function' and type(isfolder) == 'function' and not isfolder('PlayerTools') then
						makefolder('PlayerTools')
					end
				end)
				local okJson, body = pcall(function()
					return HttpService:JSONEncode(data)
				end)
				if okJson and type(body) == 'string' then
					pcall(writefile, FRESH_FINDER_PATH, body)
				end
			end
		end
		getgenv().SB2WriteFreshServerFinder = writeFreshFinderState

		do
			local hopBusy = false
			getgenv().SB2HopCurrentFloorNow = function(reason)
				if type(getgenv().SB2StartFreshServerHop) == 'function' then
					local okCall, okHop = pcall(getgenv().SB2StartFreshServerHop, reason)
					if okCall and okHop ~= false then
						return true
					end
				end
				if hopBusy then
					return false
				end
				local state = readFreshFinderState()
				if type(state) ~= 'table' or state.active ~= true then
					return false
				end
				local hopPlace = tonumber(game.PlaceId) or game.PlaceId
				state.placeId = hopPlace
				state.hops = (tonumber(state.hops) or 0) + 1
				state.tried = type(state.tried) == 'table' and state.tried or {}
				writeFreshFinderState(state)
				if type(getgenv().SB2PlayerToolsArmTeleport) == 'function' then
					pcall(getgenv().SB2PlayerToolsArmTeleport)
				end
				getgenv().SB2AutoBlockHopping = true
				hopBusy = true
				paintFreshFinder(tostring(reason or 'hopping…'))
				Library:Notify(tostring(reason or 'Fresh finder — hopping this floor…'), 5)
				task.spawn(function()
					local TeleportService = game:GetService('TeleportService')
					local teleported = false
					local okReserve, code = pcall(function()
						return TeleportService:ReserveServer(hopPlace)
					end)
					if okReserve and type(code) == 'string' and code ~= '' then
						teleported = pcall(function()
							TeleportService:TeleportToPrivateServer(hopPlace, code, { LocalPlayer })
						end)
					end
					if not teleported then
						pcall(function()
							TeleportService:Teleport(hopPlace, LocalPlayer)
						end)
					end
					task.delay(2, function()
						hopBusy = false
					end)
				end)
				return true
			end
		end

		local function countStrangerPlayers()
			local list = {}
			for _, plr in ipairs(Players:GetPlayers()) do
				if plr ~= LocalPlayer and not isOwnAlt(plr) then
					list[#list + 1] = plr
				end
			end
			return #list, list
		end

		local function stopFreshServerFinder(msg)
			freshFinderBusy = false
			paintFreshFinder('Fresh finder: off')
			syncFreshFinderToggle(false)
			if type(getgenv().SB2StopFreshServerFinder) == 'function' then
				pcall(getgenv().SB2StopFreshServerFinder, msg)
			else
				writeFreshFinderState({
					active = false,
					placeId = game.PlaceId,
					tried = {},
					hops = 0,
				})
				getgenv().SB2AutoBlockHopping = nil
				if msg then
					Library:Notify(msg, 6)
				end
			end
		end

		local function freshServerFinderTick()
			if freshFinderBusy then
				return
			end
			local tickGen = getgenv().SB2FreshFinderCancelGen or 0
			local state = readFreshFinderState()
			if type(state) ~= 'table' or state.active ~= true then
				paintFreshFinder('Fresh finder: off')
				return
			end
			freshFinderBusy = true
			task.spawn(function()
				task.wait(0.5)
				if (getgenv().SB2FreshFinderCancelGen or 0) ~= tickGen then
					freshFinderBusy = false
					return
				end
				state = readFreshFinderState()
				if type(state) ~= 'table' or state.active ~= true then
					freshFinderBusy = false
					paintFreshFinder('Fresh finder: off')
					return
				end
				local wantPlace = tonumber(state.placeId) or game.PlaceId
				if game.PlaceId ~= wantPlace then
					stopFreshServerFinder('Fresh finder stopped — wrong floor')
					freshFinderBusy = false
					return
				end
				if (getgenv().SB2FreshFinderCancelGen or 0) ~= tickGen then
					freshFinderBusy = false
					return
				end
				local hops = tonumber(state.hops) or 0
				if hops >= FRESH_FINDER_MAX_HOPS then
					stopFreshServerFinder('Fresh finder stopped — hop limit')
					freshFinderBusy = false
					return
				end
				local n, strangers = countStrangerPlayers()
				if n <= 0 then
					-- Don't stop mid-landing / mid-stream — wait for a stable empty.
					local landedUntil = tonumber(getgenv().SB2FreshJustLandedUntil) or 0
					if os.clock() < landedUntil then
						paintFreshFinder('Fresh finder: landing…')
						freshFinderBusy = false
						return
					end
					local emptySince = tonumber(getgenv().SB2FreshEmptySince) or 0
					if emptySince <= 0 then
						getgenv().SB2FreshEmptySince = os.clock()
						paintFreshFinder('Fresh finder: checking empty…')
						freshFinderBusy = false
						return
					end
					if (os.clock() - emptySince) < 4 then
						freshFinderBusy = false
						return
					end
					getgenv().SB2FreshEmptySince = nil
					stopFreshServerFinder('Empty server found on this floor')
					freshFinderBusy = false
					return
				end
				getgenv().SB2FreshEmptySince = nil
				-- Everyone here already blocked → hop (same as AutoBlock).
				local actionable = n
				local skip = getgenv().SB2AutoBlockSkipUntil
				if type(skip) == 'table' then
					actionable = 0
					for _, plr in ipairs(strangers) do
						local untilT = skip[plr.UserId]
						if not (type(untilT) == 'number' and os.clock() < untilT) then
							actionable += 1
						end
					end
				end
				if actionable <= 0 then
					paintFreshFinder(('Fresh finder: %d blocked — hopping…'):format(n))
					if type(getgenv().SB2HopFreshIfNoUnblocked) == 'function' then
						pcall(getgenv().SB2HopFreshIfNoUnblocked, 'all present already blocked — hopping…')
					elseif type(getgenv().SB2HopCurrentFloorNow) == 'function' then
						pcall(getgenv().SB2HopCurrentFloorNow, 'all present already blocked — hopping…')
					elseif type(getgenv().SB2StartFreshServerHop) == 'function' then
						pcall(getgenv().SB2StartFreshServerHop, 'all present already blocked — hopping…')
					end
					freshFinderBusy = false
					return
				end
				paintFreshFinder(('Fresh finder: %d here — blocking… hop %d'):format(actionable, hops))
				if type(getgenv().SB2ArmAutoBlockTimers) == 'function' then
					pcall(getgenv().SB2ArmAutoBlockTimers, 0)
				elseif getgenv().SB2AutoBlockIyOwner ~= true then
					Library:Notify('Install AutoBlock.iy for fresh server finder', 6)
					stopFreshServerFinder('Fresh finder stopped — need AutoBlock.iy')
				end
				freshFinderBusy = false
			end)
		end
		getgenv().SB2FreshServerFinderTick = freshServerFinderTick

		-- Fresh finder always hops the floor you are on (no floor picker).
		do
			local HARD = {
				[542351431] = 'F1 Virhst Woodlands',
				[548231754] = 'F2 Redveil Grove',
				[555980327] = 'F3 Avalanche Expanse',
				[572487908] = 'F4 Hidden Wilds',
				[580239979] = 'F5 Desolate Dunes',
				[566212942] = 'F6 Helmfirth',
				[582198062] = 'F7 Entoloma Gloomlands',
				[548878321] = 'F8 Blooming Plateau',
				[573267292] = "F9 Va' Rok",
				[2659143505] = 'F10 Transylvania',
				[5287433115] = 'F11 Hypersiddia',
				[6144637080] = 'F12 Sector - 235',
			}
			local function currentFloorLabel()
				local pid = tonumber(game.PlaceId) or game.PlaceId
				return HARD[pid] or ('Current floor (' .. tostring(pid) .. ')')
			end
			-- Keep AutoBlock pref locked to this place whenever finder runs.
			pcall(function()
				if type(getgenv().SB2WriteFreshServerFinder) == 'function' then
					local fsf = readFreshFinderState() or {}
					if type(fsf) == 'table' and fsf.active == true then
						fsf.placeId = game.PlaceId
						fsf.placeName = 'Current floor'
						pcall(getgenv().SB2WriteFreshServerFinder, fsf)
					end
				end
			end)
			SoloBox:AddLabel('Fresh finder floor: ' .. currentFloorLabel() .. ' (always this place)')
		end

		local function startFreshServerFinder()
			if getgenv().SB2AutoBlockIyOwner ~= true then
				Library:Notify('Install IY plugin AutoBlock.iy first', 6)
				return false
			end
			-- Always hop THIS floor.
			local targetPlace = tonumber(game.PlaceId) or game.PlaceId
			local targetName = 'Current floor'
			getgenv().SB2FreshBlockRetries = {}
			getgenv().SB2FreshFinderCancelGen = (getgenv().SB2FreshFinderCancelGen or 0) + 1
			writeFreshFinderState({
				active = true,
				placeId = targetPlace,
				placeName = targetName,
				tried = { [tostring(game.JobId or '')] = true },
				hops = 0,
				started = os.time(),
			})
			paintFreshFinder('Fresh finder: starting on this floor…')
			syncFreshFinderToggle(true)
			Library:Notify('Fresh server finder — block & hop on this floor until solo', 7)
			if type(getgenv().SB2ArmAutoBlockTimers) == 'function' then
				pcall(getgenv().SB2ArmAutoBlockTimers, 0)
			end
			task.defer(freshServerFinderTick)
			-- If everyone already blocked / hop exports missing, hop immediately.
			task.delay(1.2, function()
				local state = readFreshFinderState()
				if type(state) ~= 'table' or state.active ~= true then
					return
				end
				local n, strangers = countStrangerPlayers()
				if n <= 0 then
					return
				end
				local actionable = n
				local skip = getgenv().SB2AutoBlockSkipUntil
				if type(skip) == 'table' then
					actionable = 0
					for _, plr in ipairs(strangers) do
						local untilT = skip[plr.UserId]
						if not (type(untilT) == 'number' and os.clock() < untilT) then
							actionable += 1
						end
					end
				end
				if actionable <= 0 and type(getgenv().SB2HopCurrentFloorNow) == 'function' then
					pcall(getgenv().SB2HopCurrentFloorNow, 'finder — all blocked, hopping…')
				end
			end)
			-- Keep ticking while finder runs (AutoBlock may lack hop exports).
			task.spawn(function()
				local gen = getgenv().SB2FreshFinderCancelGen or 0
				for _ = 1, 120 do
					task.wait(3)
					if (getgenv().SB2FreshFinderCancelGen or 0) ~= gen then
						return
					end
					local state = readFreshFinderState()
					if type(state) ~= 'table' or state.active ~= true then
						return
					end
					pcall(freshServerFinderTick)
				end
			end)
			return true
		end

		local freshFinderDefault = false
		do
			local st = readFreshFinderState()
			freshFinderDefault = type(st) == 'table' and st.active == true
		end
		freshFinderLabel = SoloBox:AddLabel(freshFinderDefault and 'Fresh finder: on' or 'Fresh finder: off')
		SoloBox:AddToggle('FreshServerFinder', {
			Text = 'Fresh server finder',
			Default = freshFinderDefault,
			Tooltip = 'Block & hop on this floor until the server is empty (you + alts only). Needs AutoBlock.iy.',
		}):OnChanged(function(value)
			if freshFinderSyncing then
				return
			end
			if value then
				task.spawn(function()
					if startFreshServerFinder() == false then
						syncFreshFinderToggle(false)
					end
				end)
			else
				stopFreshServerFinder('Fresh server finder stopped')
			end
		end)
		end)()

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
			Tooltip = 'Click a name in the WP pill to select it, or pick it here. Used when only you / your alts remain.',
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

		-- Multi-boss waypoint route (F12: warlord → hunter → limor → radioactive).
		-- Kill each, then wait at the first-killed boss for respawn (~90s) to sync the loop.
		-- Own IIFE: bare do/end still burns the Combat/Solo 200-local budget.
		;(function()
			local BOSS_ROUTE_RESPAWN_SEC = 90
			-- Global gen survives soft-reload / nested IIFEs so OFF always kills zombie loops.
			getgenv().SB2BossRouteGen = tonumber(getgenv().SB2BossRouteGen) or 0
			local bossRouteToken = 0
			local bossRouteLabel = BossBox:AddLabel('Boss WP route: off')

			local function paintBossRoute(text)
				pcall(function()
					if bossRouteLabel.SetText then
						bossRouteLabel:SetText(tostring(text))
					elseif bossRouteLabel.Text ~= nil then
						bossRouteLabel.Text = tostring(text)
					end
				end)
			end

			local function bossRouteAlive(token, myGen)
				if token ~= bossRouteToken then
					return false
				end
				if (tonumber(getgenv().SB2BossRouteGen) or 0) ~= myGen then
					return false
				end
				return isToggleOn('BossWaypointRoute')
			end

			-- Preferred kill order; waypoint names are matched by substring (your WPs: warlord/hunter/limor/radioactive shit).
			local BOSS_ROUTE_DEFS = {
				{ order = 1, keys = { 'warlord' }, hints = { 'Warlord' } },
				{ order = 2, keys = { 'hunter' }, hints = { 'Hunter' } },
				{ order = 3, keys = { 'limor' }, hints = { 'Limor the Devourer', 'Limor' } },
				{
					order = 4,
					keys = { 'radioactive', 'radio', 'experiment' },
					hints = { 'Radioactive Experiment' },
				},
			}

			local function wpKeyHit(wpName, keys)
				local n = string.lower(tostring(wpName or ''))
				for _, k in ipairs(keys) do
					if n:find(k, 1, true) then
						return true
					end
				end
				return false
			end

			local function collectBossRouteStops()
				local found = {}
				local names = listSoloWaypoints()
				for _, wpName in ipairs(names) do
					if wpName ~= WP_NONE then
						local rec = findSoloWaypointRec(wpName)
						-- Skip under-map WPs (e.g. limor saved at Y=-337) — they zero damage.
						if rec and (tonumber(rec.y) or 0) >= -20 then
							for _, def in ipairs(BOSS_ROUTE_DEFS) do
								if wpKeyHit(wpName, def.keys) and not found[def.order] then
									found[def.order] = {
										order = def.order,
										wpName = wpName,
										hints = def.hints,
									}
									break
								end
							end
						elseif rec and (tonumber(rec.y) or 0) < -20 then
							-- #region agent log
							if type(getgenv().SB2DbgFling) == 'function' then
								pcall(getgenv().SB2DbgFling, 'A', 'collectBossRouteStops', 'boss_wp_void_skip', {
									name = wpName,
									y = tonumber(rec.y),
								})
							end
							-- #endregion
						end
					end
				end
				local stops = {}
				for i = 1, #BOSS_ROUTE_DEFS do
					if found[i] then
						stops[#stops + 1] = found[i]
					end
				end
				return stops
			end

			local function mobMatchesBossHints(mob, hints)
				if not mob then
					return false
				end
				local raw = string.lower(tostring(mob.Name or ''))
				local key = normBossKey(mob.Name)
				for _, h in ipairs(hints) do
					local hl = string.lower(tostring(h))
					local hk = normBossKey(h)
					if raw == hl or key == hk then
						return true
					end
					if #hk >= 4 and (key:find(hk, 1, true) or hk:find(key, 1, true)) then
						return true
					end
					if #hl >= 4 and raw:find(hl, 1, true) then
						return true
					end
				end
				return false
			end

			local function findAliveBossForHints(hints)
				local mobs = workspace:FindFirstChild('Mobs')
				if not mobs then
					return nil
				end
				for _, mob in ipairs(mobs:GetChildren()) do
					if mobMatchesBossHints(mob, hints) and not isDeadMob(mob) then
						return mob
					end
				end
				return nil
			end

			local function teleportBossRouteWp(wpName)
				if getgenv().SB2BossRouteWanted ~= true or not isToggleOn('BossWaypointRoute') then
					return false, 'boss route off'
				end
				local gate = getgenv().SB2TpGate
				if type(gate) == 'table' and gate.block == true then
					return false, 'tp blocked'
				end
				local wp = findSoloWaypointRec(wpName)
				if not wp then
					return false, 'missing waypoint'
				end
				local wy = tonumber(wp.y) or 0
				if wy < -20 then
					-- #region agent log
					if type(getgenv().SB2DbgFling) == 'function' then
						pcall(getgenv().SB2DbgFling, 'A', 'teleportBossRouteWp', 'boss_tp_void_wp', {
							name = wpName,
							y = wy,
						})
					end
					-- #endregion
					return false, 'void waypoint — re-save ' .. tostring(wpName)
				end
				local setter = getgenv().SB2WaypointsSetSelected
				if type(setter) == 'function' then
					pcall(setter, wpName, true)
				end
				if Options.SoloResumeWaypoint and type(Options.SoloResumeWaypoint.SetValue) == 'function' then
					pcall(function()
						Options.SoloResumeWaypoint:SetValue(wpName)
					end)
				end
				local cf = CFrame.new(tonumber(wp.x) or 0, wy, tonumber(wp.z) or 0)
				return applyCharacterCFrame(cf)
			end

			local function stopBossRoute(reason)
				bossRouteToken += 1
				getgenv().SB2BossRouteGen = (tonumber(getgenv().SB2BossRouteGen) or 0) + 1
				getgenv().SB2BossRouteWanted = false
				getgenv().SB2TpGate = getgenv().SB2TpGate or {}
				getgenv().SB2TpGate.block = true
				getgenv().SB2SoloBootTpGen = (tonumber(getgenv().SB2SoloBootTpGen) or 0) + 1
				paintBossRoute(reason and ('Boss WP route: ' .. tostring(reason)) or 'Boss WP route: off')
			end

			local runBossRouteLoop

			-- Like Resume: toggle stays ON; pause combat/loop while strangers are here.
			local function pauseBossRouteForStranger(plr)
				if not isToggleOn('BossWaypointRoute') then
					return
				end
				bossRouteToken += 1
				getgenv().SB2BossRouteGen = (tonumber(getgenv().SB2BossRouteGen) or 0) + 1
				setCombatTrio(false)
				local who = plr and (plr.DisplayName or plr.Name) or 'player'
				paintBossRoute(('Boss WP route: paused — %s'):format(tostring(who)))
				Library:Notify(
					('Boss WP route paused — %s here (resumes when empty)'):format(tostring(who)),
					6
				)
			end

			local function tryResumeBossRoute(reason)
				if not isToggleOn('BossWaypointRoute') then
					return
				end
				if otherPlayersPresent() == true then
					paintBossRoute('Boss WP route: paused (waiting for empty)')
					return
				end
				local stops = collectBossRouteStops()
				if #stops < 2 then
					paintBossRoute('Boss WP route: need 2+ boss WPs on this floor')
					return
				end
				Library:Notify(('Boss WP route resume — %s'):format(tostring(reason or 'empty')), 4)
				runBossRouteLoop()
			end

			local function clearBossRouteWatchers()
				local joinConn = getgenv().SB2BossRouteJoinConn
				if joinConn then
					pcall(function()
						joinConn:Disconnect()
					end)
					getgenv().SB2BossRouteJoinConn = nil
				end
				local leaveConn = getgenv().SB2BossRouteLeaveConn
				if leaveConn then
					pcall(function()
						leaveConn:Disconnect()
					end)
					getgenv().SB2BossRouteLeaveConn = nil
				end
			end

			local function ensureBossRouteWatchers()
				clearBossRouteWatchers()
				getgenv().SB2BossRouteJoinConn = Players.PlayerAdded:Connect(function(plr)
					if not isToggleOn('BossWaypointRoute') then
						return
					end
					if not plr or plr == LocalPlayer or isOwnAlt(plr) then
						return
					end
					pauseBossRouteForStranger(plr)
				end)
				getgenv().SB2BossRouteLeaveConn = Players.PlayerRemoving:Connect(function(leaver)
					if not leaver or leaver == LocalPlayer then
						return
					end
					if not isToggleOn('BossWaypointRoute') then
						return
					end
					-- Leaving alts shouldn't matter; strangers leaving should resume.
					task.defer(function()
						task.wait(0.35)
						if not isToggleOn('BossWaypointRoute') then
							return
						end
						if otherPlayersPresent() then
							return
						end
						tryResumeBossRoute('empty')
					end)
				end)
			end

			runBossRouteLoop = function()
				bossRouteToken += 1
				local token = bossRouteToken
				getgenv().SB2BossRouteGen = (tonumber(getgenv().SB2BossRouteGen) or 0) + 1
				local myGen = getgenv().SB2BossRouteGen
				getgenv().SB2BossRouteWanted = true
				getgenv().SB2TpGate = getgenv().SB2TpGate or {}
				getgenv().SB2TpGate.block = false
				ensureBossRouteWatchers()
				task.spawn(function()
					while bossRouteAlive(token, myGen) do
						if otherPlayersPresent() == true then
							local who = nil
							for _, plr in ipairs(Players:GetPlayers()) do
								if plr ~= LocalPlayer and not isOwnAlt(plr) then
									who = plr
									break
								end
							end
							pauseBossRouteForStranger(who)
							return
						end
						local stops = collectBossRouteStops()
						if #stops < 2 then
							paintBossRoute('Boss WP route: need 2+ boss WPs on this floor')
							Library:Notify('Boss route needs warlord/hunter/limor/radioactive waypoints', 6)
							task.wait(3)
							continue
						end

						local firstKillClock = nil
						local firstStop = stops[1]

						for i, stop in ipairs(stops) do
							if not bossRouteAlive(token, myGen) then
								return
							end
							if otherPlayersPresent() == true then
								local who = nil
								for _, plr in ipairs(Players:GetPlayers()) do
									if plr ~= LocalPlayer and not isOwnAlt(plr) then
										who = plr
										break
									end
								end
								pauseBossRouteForStranger(who)
								return
							end

							paintBossRoute(('Boss route [%d/%d] → %s'):format(i, #stops, stop.wpName))
							local okTp, errTp = teleportBossRouteWp(stop.wpName)
							if not okTp then
								Library:Notify(('Boss route TP failed: %s'):format(tostring(errTp)), 5)
								task.wait(1)
								continue
							end
							-- Pin already running from applyCharacterCFrame; trio turns Anchor on without unanchor hold.
							setCombatTrio(true)

							-- Wait until this boss is alive (spawn / already up).
							paintBossRoute(('Boss route [%d/%d] waiting %s…'):format(i, #stops, stop.wpName))
							local mob = nil
							local spawnDeadline = os.clock() + 150
							while os.clock() < spawnDeadline and bossRouteAlive(token, myGen) do
								if otherPlayersPresent() == true then
									local who = nil
									for _, plr in ipairs(Players:GetPlayers()) do
										if plr ~= LocalPlayer and not isOwnAlt(plr) then
											who = plr
											break
										end
									end
									pauseBossRouteForStranger(who)
									return
								end
								mob = findAliveBossForHints(stop.hints)
								if mob then
									break
								end
								task.wait(0.35)
							end
							if not mob then
								paintBossRoute(('Boss route: no %s — skip'):format(stop.wpName))
								task.wait(0.5)
								continue
							end

							paintBossRoute(('Boss route [%d/%d] fighting %s'):format(i, #stops, mob.Name))
							Library:Notify(('Boss route — %s'):format(tostring(mob.Name)), 4)
							-- Stay until dead / despawned.
							while bossRouteAlive(token, myGen) do
								if otherPlayersPresent() == true then
									local who = nil
									for _, plr in ipairs(Players:GetPlayers()) do
										if plr ~= LocalPlayer and not isOwnAlt(plr) then
											who = plr
											break
										end
									end
									pauseBossRouteForStranger(who)
									return
								end
								if not mob or not mob.Parent or isDeadMob(mob) then
									break
								end
								-- Re-acquire if instance swapped.
								local alive = findAliveBossForHints(stop.hints)
								if not alive then
									break
								end
								mob = alive
								task.wait(0.25)
							end

							local killAt = os.clock()
							if not firstKillClock then
								firstKillClock = killAt
								firstStop = stop
							end
							paintBossRoute(('Boss route: killed %s'):format(stop.wpName))
							task.wait(0.45)
						end

						if not bossRouteAlive(token, myGen) then
							return
						end

						-- After the last kill: sit on the first-killed boss pad until its respawn window.
						if firstKillClock and firstStop then
							teleportBossRouteWp(firstStop.wpName)
							setCombatTrio(true)
							local readyAt = firstKillClock + BOSS_ROUTE_RESPAWN_SEC
							while bossRouteAlive(token, myGen) do
								if otherPlayersPresent() == true then
									local who = nil
									for _, plr in ipairs(Players:GetPlayers()) do
										if plr ~= LocalPlayer and not isOwnAlt(plr) then
											who = plr
											break
										end
									end
									pauseBossRouteForStranger(who)
									return
								end
								local left = readyAt - os.clock()
								if left <= 0 or findAliveBossForHints(firstStop.hints) then
									break
								end
								paintBossRoute(
									('Boss route: wait @ %s — %ds (sync respawn)'):format(
										firstStop.wpName,
										math.max(0, math.ceil(left))
									)
								)
								task.wait(0.5)
							end
						end
					end
					if not isToggleOn('BossWaypointRoute') then
						paintBossRoute('Boss WP route: off')
					end
				end)
			end

			BossBox:AddToggle('BossWaypointRoute', {
				Text = 'Boss WP route (multi)',
				Default = false,
				Tooltip = 'Cycles floor boss waypoints (warlord→hunter→limor→radioactive). Next WP only after kill. After last kill, waits ~90s at the first-killed boss. Like Resume: pauses if a non-alt joins, resumes when empty.',
			}):OnChanged(function(on)
				if on then
					local stops = collectBossRouteStops()
					if #stops < 2 then
						Library:Notify('Need 2+ boss waypoints on this floor (warlord/hunter/limor/radioactive)', 7)
						task.defer(function()
							if Toggles.BossWaypointRoute then
								Toggles.BossWaypointRoute:SetValue(false)
							end
						end)
						return
					end
					ensureBossRouteWatchers()
					if otherPlayersPresent() == true then
						-- Same as Resume: stay ON, wait for empty.
						paintBossRoute('Boss WP route: paused (waiting for empty)')
						Library:Notify('Boss WP route on — paused until only you/alts remain', 5)
						return
					end
					Library:Notify(('Boss WP route on — %d stops'):format(#stops), 5)
					runBossRouteLoop()
				else
					stopBossRoute('off')
					clearBossRouteWatchers()
					-- Always disarm combat on route OFF. Leaving trio on (because Resume
					-- was still true) made OFF look like the route kept running.
					setCombatTrio(false)
				end
			end)
			getgenv().SB2StopBossWaypointRoute = function(reason)
				-- Always bump gen even when toggle is already false (OnChanged won't fire).
				stopBossRoute(reason or 'stopped')
				clearBossRouteWatchers()
				setCombatTrio(false)
				pcall(function()
					local toggle = Toggles.BossWaypointRoute
					if type(toggle) == 'table' and type(toggle.SetValue) == 'function' and toggle.Value == true then
						toggle:SetValue(false)
					end
				end)
			end
			-- HiveMind / MCP can't see Starlight's local Toggles — use this helper.
			getgenv().SB2SetBossWaypointRoute = function(enabled)
				local toggle = Toggles.BossWaypointRoute
				enabled = enabled == true
				if not enabled then
					-- Force-stop first so already-false toggles still kill zombie loops.
					stopBossRoute('off')
					clearBossRouteWatchers()
					setCombatTrio(false)
				end
				if type(toggle) ~= 'table' or type(toggle.SetValue) ~= 'function' then
					return false
				end
				pcall(function()
					if toggle.Value == enabled then
						if enabled then
							toggle:SetValue(false)
							task.wait()
							toggle:SetValue(true)
						end
						return
					end
					toggle:SetValue(enabled)
				end)
				return true
			end
		end)()

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
			-- Seed userid cache so renamed display names still count as alts.
			for _, plr in ipairs(Players:GetPlayers()) do
				pcall(isOwnAlt, plr)
			end
			getgenv().SB2CombatSoloResumeConn = safeConnect(Players.PlayerRemoving, function(leaver)
				if not leaver or leaver == LocalPlayer then
					return
				end
				-- Leaving alts should not block resume; strangers leaving should resume
				-- once only alts (or nobody) remain.
				task.defer(function()
					task.wait(0.35)
					if otherPlayersPresent() then
						return
					end
					resumeSoloCombat('empty')
				end)
			end)
			-- Boot already-solo: PlayerRemoving never fires, so schedule WP TPs.
			task.spawn(function()
				local gen = (tonumber(getgenv().SB2SoloBootTpGen) or 0) + 1
				getgenv().SB2SoloBootTpGen = gen
				local startAt = os.clock()
				for _, at in ipairs({ 2.0, 4.0, 7.0, 12.0, 18.0 }) do
					if getgenv().SB2SoloBootTpGen ~= gen then
						return
					end
					local left = at - (os.clock() - startAt)
					if left > 0 then
						task.wait(left)
					end
					if not isToggleOn('SoloCombatResume') and getgenv().SB2StickyResumeWanted ~= true then
						continue
					end
					if otherPlayersPresent() then
						continue
					end
					local name = currentSoloWaypoint()
					if not name then
						continue
					end
					local wp = findSoloWaypointRec(name)
					local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild('HumanoidRootPart')
					if wp and hrp then
						local target = Vector3.new(tonumber(wp.x) or 0, tonumber(wp.y) or 0, tonumber(wp.z) or 0)
						if (hrp.Position - target).Magnitude <= 40 then
							return
						end
					end
					resumeSoloCombat('boot', true)
				end
			end)
			pcall(function()
				local prevAdd = getgenv().SB2CombatAltSeedConn
				if prevAdd then
					prevAdd:Disconnect()
				end
				getgenv().SB2CombatAltSeedConn = Players.PlayerAdded:Connect(function(plr)
					pcall(isOwnAlt, plr)
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

		-- Nested IIFE: Combat chunk is at Luau's 200-local limit; boss combo needs its own budget.
		;(function()
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

		local function isMobFrozen(mob)
			if not mob or not mob.Parent then
				return false
			end
			local okCs, tagged = pcall(function()
				return game:GetService('CollectionService'):HasTag(mob, 'Stunned')
			end)
			if okCs and tagged then
				return true
			end
			if mob:GetAttribute('Stunned') == true
				or mob:GetAttribute('SystemFrozen') == true
				or mob:GetAttribute('Frozen') == true
			then
				return true
			end
			local hum = mob:FindFirstChildOfClass('Humanoid')
			if hum
				and (
					hum:GetAttribute('Stunned') == true
					or hum:GetAttribute('SystemFrozen') == true
				)
			then
				return true
			end
			return false
		end

		-- Measured freeze hold times (Stunned tag). Cast windup is separate (~2s).
		-- After a freeze cycle (WB + ES stack), game applies a ~30s global freeze CD.
		local COMBO_FREEZE_HOLD = {
			['Water Blast'] = 7,
			['Everfrost'] = 10,
			['Everfrost Strike'] = 10,
			['Water Domain'] = 7,
		}
		local COMBO_FREEZE_GCD = 30

		local function comboFreezeHold(skillName)
			return COMBO_FREEZE_HOLD[skillName] or nil
		end

		local function isComboFreezeSkill(skillName)
			return comboFreezeHold(skillName) ~= nil
		end

		-- Shared freeze window for stacking WB → ES, then GCD before the next freeze.
		local freezeState = {
			untilClock = 0, -- os.clock when current freeze hold should end
			gcdUntil = 0, -- os.clock when next freeze cast is allowed
			lastSkill = nil,
		}

		local function noteFreezeCast(skillName)
			local hold = comboFreezeHold(skillName)
			if not hold then
				return
			end
			local now = os.clock()
			-- Stacking extends (does not shorten) the active freeze window.
			freezeState.untilClock = math.max(freezeState.untilClock, now + hold)
			freezeState.lastSkill = skillName
			-- Global freeze CD: 30s AFTER the freeze window ends (updated when ES stacks).
			freezeState.gcdUntil = freezeState.untilClock + COMBO_FREEZE_GCD
		end

		local comboBusy = false
		local comboSeen = {}
		local comboToken = 0

		local function resolveSkillsService()
			local skills = getGameSkillsService()
			if skills then
				return skills
			end
			local cached = getgenv().SB2SkillsServiceCache
			if type(cached) == 'table' and type(cached.UseSkill) == 'function' then
				return cached
			end
			if type(getgc) == 'function' then
				for _, v in ipairs(getgc(true)) do
					if type(v) == 'table'
						and type(rawget(v, 'UseSkill')) == 'function'
						and rawget(v, 'usingSkill') ~= nil
					then
						getgenv().SB2SkillsServiceCache = v
						return v
					end
				end
			end
			return nil
		end

		-- Game GetCooldown: >=0 ready, <0 seconds remaining. Plain fn (no self).
		local function comboGameCooldown(skillName)
			local skills = resolveSkillsService()
			if not skills or type(skills.GetCooldown) ~= 'function' then
				return nil
			end
			local ok, cd = pcall(skills.GetCooldown, skillName)
			if ok and type(cd) == 'number' then
				return cd
			end
			return nil
		end

		local function playComboSkillEffect(skillName)
			local svc = RequiredServices or getgenv().SB2RequiredServices
			if type(svc) ~= 'table' then
				return
			end
			if svc.SkillEffects and type(svc.SkillEffects.DoEffect) == 'function' then
				pcall(svc.SkillEffects.DoEffect, skillName)
			elseif svc.Graphics and type(svc.Graphics.DoEffect) == 'function' then
				pcall(svc.Graphics.DoEffect, skillName)
			end
		end

		local function waitForBossStun(mob, token, timeoutSec)
			local deadline = os.clock() + (timeoutSec or 2.5)
			while os.clock() < deadline and token == comboToken do
				if isMobFrozen(mob) then
					return true
				end
				if not mob or not mob.Parent or isDeadMob(mob) then
					return false
				end
				task.wait(0.1)
			end
			return isMobFrozen(mob)
		end

		-- Wait out the freeze TIMER (hold length), not just until Stunned flickers off.
		-- Also waits if the boss is still tagged after the expected end.
		local function waitWhileBossFrozen(mob, token, holdSec, fromClock)
			local expectedEnd = (type(fromClock) == 'number' and fromClock or os.clock())
				+ math.max(1, holdSec or 7)
			-- Prefer shared stack window if it ends later (WB+ES overlap).
			if freezeState.untilClock > expectedEnd then
				expectedEnd = freezeState.untilClock
			end
			while token == comboToken and isToggleOn('BossComboEnable') do
				if not mob or not mob.Parent or isDeadMob(mob) then
					return false
				end
				local now = os.clock()
				local stillTagged = isMobFrozen(mob)
				if now >= expectedEnd and not stillTagged then
					return true
				end
				-- Timer done but tag lingering — keep polling until it drops (cap +4s).
				if now >= expectedEnd + 4 and stillTagged then
					return true
				end
				local remain = expectedEnd - now
				if remain > 0.45 then
					task.wait(math.min(0.45, remain - 0.2))
				else
					task.wait(0.12)
				end
			end
			return isMobFrozen(mob)
		end

		local function waitFreezeGcd(token)
			while token == comboToken and isToggleOn('BossComboEnable') do
				local remain = freezeState.gcdUntil - os.clock()
				if remain <= 0 then
					return true
				end
				task.wait(math.min(0.5, math.max(0.15, remain)))
			end
			return false
		end

		local function fireComboSkill(skillName)
			if type(skillName) ~= 'string' or skillName == '' then
				return false, 1.5
			end
			local info = getSkillInfo(skillName)
			-- Freeze skills have no Duration in DB — cast windup before the hold starts.
			local hold = comboFreezeHold(skillName)
			local dur = (info.duration and info.duration > 0) and info.duration or 1.5
			if hold then
				dur = math.max(dur, 2.0)
				-- Do not cast a freeze while the global freeze GCD is still cooling
				-- (except the initial stack: skill2 is allowed while freeze window is active).
				local now = os.clock()
				if freezeState.gcdUntil > now and now >= freezeState.untilClock then
					return false, dur
				end
			end
			syncSkillCdFromGame(skillName)
			local cdBefore = comboGameCooldown(skillName)
			if cdBefore and cdBefore < 0 then
				return false, dur
			end
			if not isSkillReady(skillName) then
				return false, dur
			end
			if gameSkillCanCast(skillName) == false then
				return false, dur
			end
			getgenv().SB2SkillActiveName = skillName
			getgenv().SB2SkillActiveUntil = time() + math.max(0.8, dur)

			-- Prefer local Skills.UseSkill — that path runs SkillEffects.DoEffect (VFX).
			-- pcall success alone is NOT enough: UseSkill no-ops while on CD and still returns.
			local skills = resolveSkillsService()
			local ok = false
			local via = 'none'
			if skills and type(skills.UseSkill) == 'function' then
				pcall(skills.UseSkill, skillName)
				local cdAfter = comboGameCooldown(skillName)
				if cdAfter and cdAfter < 0 and (not cdBefore or cdBefore >= 0) then
					ok = true
					via = 'UseSkill'
				elseif skills.usingSkill == skillName then
					ok = true
					via = 'usingSkill'
				end
			end
			if not ok then
				local remoteOk = fireUseSkill(skillName, info, {
					muteFor = dur + 0.2,
					silentFail = true,
					ignoreGap = true,
				}) == true
				if remoteOk then
					-- Remote-only skips the local handler VFX — play DoEffect ourselves.
					playComboSkillEffect(skillName)
					ok = true
					via = 'remote+DoEffect'
				end
			end
			if ok then
				local cd = info.cooldown or 2
				markSkillUsed(skillName, cd)
				lastAnySkillCastAt = os.clock()
				if hold then
					noteFreezeCast(skillName)
				end
			end
			if not ok then
				getgenv().SB2SkillActiveUntil = 0
				getgenv().SB2SkillActiveName = nil
			end
			return ok == true, dur
		end

		local function maintainBossFreeze(mob, skill2, token)
			-- After the opening WB+ES stack:
			-- 1) wait out the remaining freeze timer (ES ~10s),
			-- 2) wait the 30s global freeze GCD,
			-- 3) re-cast skill2 and wait ITS full hold before repeating.
			local hold = comboFreezeHold(skill2) or 10
			while token == comboToken and isToggleOn('BossComboEnable') do
				if not mob or not mob.Parent or isDeadMob(mob) then
					break
				end
				local now = os.clock()
				-- Still inside an active freeze window — wait the timer out fully.
				if now < freezeState.untilClock or isMobFrozen(mob) then
					local remain = math.max(0.5, freezeState.untilClock - now)
					waitWhileBossFrozen(mob, token, remain, now)
					-- Ensure we don't leave early while still tagged.
					while token == comboToken
						and isToggleOn('BossComboEnable')
						and isMobFrozen(mob)
						and os.clock() < freezeState.untilClock + 2
					do
						task.wait(0.15)
					end
				else
					-- Freeze ended — honor global 30s freeze CD before next freeze.
					if freezeState.gcdUntil > os.clock() then
						waitFreezeGcd(token)
					end
					if token ~= comboToken or not isToggleOn('BossComboEnable') then
						break
					end
					syncSkillCdFromGame(skill2)
					local gameCd = comboGameCooldown(skill2)
					if gameCd and gameCd < 0 then
						task.wait(math.clamp(-gameCd, 0.2, 1.0))
					elseif isSkillReady(skill2) and gameSkillCanCast(skill2) ~= false then
						local castAt = os.clock()
						local ok = fireComboSkill(skill2)
						if ok then
							-- noteFreezeCast already set untilClock = castAt+hold and new GCD.
							waitForBossStun(mob, token, 2.5)
							waitWhileBossFrozen(mob, token, hold, castAt)
						else
							task.wait(0.35)
						end
					else
						task.wait(0.25)
					end
				end
			end
		end

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
			freezeState.untilClock = 0
			freezeState.gcdUntil = 0
			freezeState.lastSkill = nil
			Library:Notify(('Boss combo — %s'):format(tostring(mob.Name)), 8, true)
			task.spawn(function()
				local okRun, errRun = pcall(function()
					local deadline = os.clock() + 3.5
					local ok1, dur1 = false, 1.5
					local cast1At = nil
					while os.clock() < deadline and token == comboToken do
						ok1, dur1 = fireComboSkill(skill1)
						if ok1 then
							cast1At = os.clock()
							break
						end
						task.wait(0.12)
					end
					if not ok1 then
						Library:Notify('Boss combo: ' .. tostring(skill1) .. ' failed', 8, true)
						return
					end
					local hold1 = comboFreezeHold(tostring(skill1))
					if hold1 then
						-- Wait for stun, then hold most of WB (~7s) before stacking ES.
						waitForBossStun(mob, token, math.max(1.5, tonumber(dur1) or 2))
						waitWhileBossFrozen(mob, token, math.max(1, hold1 - 1.5), cast1At)
					else
						task.wait(math.max(1.2, tonumber(dur1) or 1.5))
					end
					if token ~= comboToken or not isToggleOn('BossComboEnable') then
						return
					end
					local cast2At = os.clock()
					local ok2, dur2 = fireComboSkill(skill2)
					if not ok2 then
						task.wait(0.35)
						ok2, dur2 = fireComboSkill(skill2)
						cast2At = os.clock()
					end
					local hold2 = comboFreezeHold(tostring(skill2))
					if ok2 and hold2 then
						waitForBossStun(mob, token, math.max(1.5, tonumber(dur2) or 2))
						-- Skill 3 during ES freeze, then wait out the FULL ES timer (~10s).
						if token == comboToken and isToggleOn('BossComboEnable') then
							local ok3 = fireComboSkill(skill3)
							if not ok3 then
								task.wait(0.35)
								fireComboSkill(skill3)
							end
						end
						waitWhileBossFrozen(mob, token, hold2, cast2At)
					else
						task.wait(math.max(0.8, (tonumber(dur2) or 1.5) * 0.65))
						if token == comboToken and isToggleOn('BossComboEnable') then
							local ok3 = fireComboSkill(skill3)
							if not ok3 then
								task.wait(0.35)
								fireComboSkill(skill3)
							end
						end
					end
					if token ~= comboToken or not isToggleOn('BossComboEnable') then
						return
					end
					-- Re-freeze on skill2 after full hold + 30s global freeze GCD.
					if type(skill2) == 'string' and skill2 ~= '' then
						maintainBossFreeze(mob, skill2, token)
					end
				end)
				comboBusy = false
				getgenv().SB2BossComboLock = false
				if not okRun then
					Library:Notify('Boss combo error: ' .. tostring(errRun), 8, true)
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

		local ComboBox = BossTab:AddRightGroupbox('Boss combo')
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
			Text = 'Second (overlap + re-freeze)',
			Values = comboSkills,
			Default = pickDefaultSkill(comboSkills, 'Everfrost Strike'),
			AllowNull = false,
			Searchable = true,
			Tooltip = 'Cast after skill 1. WB ~7s then ES ~10s (waits full ES hold). Then 30s global freeze CD before re-cast.',
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
			Tooltip = 'WB (~7s) → ES (~10s, wait full hold) → skill 3 during ES → 30s freeze GCD → re-freeze with skill 2.',
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
		end)()
	end)()

	-- Inventory tab (stations / remote upgrade).
	;(function()
		if type(getgenv().SB2InvFilterCleanup) == 'function' then
			pcall(getgenv().SB2InvFilterCleanup)
		end
		-- Restore GetInventoryData if a prior session left a hook installed.
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

		-- Top-right: hide unlocked inventory tiles (show Locked attribute only).
		local FilterBox = InvTab:AddRightGroupbox('View filter')
		assert(FilterBox, 'View filter groupbox nil')
		do
			local inventoryUI = RequiredServices and RequiredServices.InventoryUI
			local originalGet = nil
			if inventoryUI and type(inventoryUI.GetInventoryData) == 'function' then
				originalGet = getgenv().SB2OrigGetInventoryData
				if type(originalGet) ~= 'function' then
					originalGet = inventoryUI.GetInventoryData
					getgenv().SB2OrigGetInventoryData = originalGet
				end
			end

			local function isInventoryItemLocked(entry)
				if type(entry) ~= 'table' then
					return false
				end
				if entry.Locked == true or entry.locked == true then
					return true
				end
				local it = entry.item or entry.Item
				if typeof(it) ~= 'Instance' then
					return false
				end
				if it:GetAttribute('Locked') == true then
					return true
				end
				local ch = it:FindFirstChild('Locked')
				if ch then
					if ch:IsA('BoolValue') then
						return ch.Value == true
					end
					-- Non-bool Locked child still marks locked in this game.
					return true
				end
				return false
			end

			local function filterLockedOnly(data)
				if type(data) ~= 'table' then
					return data
				end
				local out = table.create(#data)
				for i = 1, #data do
					local entry = data[i]
					if isInventoryItemLocked(entry) then
						out[#out + 1] = entry
					end
				end
				return out
			end

			local function rebuildInventoryList()
				local ui = RequiredServices and RequiredServices.UI
				local im = ui and ui.InventoryMenu
				if im and type(im.BuildInv) == 'function' then
					pcall(im.BuildInv)
					return true
				end
				return false
			end

			local function restoreDataHook()
				if inventoryUI and type(originalGet) == 'function' then
					pcall(function()
						inventoryUI.GetInventoryData = originalGet
					end)
				end
				getgenv().SB2InvLockedOnlyHooked = false
			end

			local function installDataHook()
				if not inventoryUI or type(originalGet) ~= 'function' then
					return false
				end
				inventoryUI.GetInventoryData = function(...)
					local data = originalGet(...)
					if isToggleOn('InvShowLockedOnly') then
						return filterLockedOnly(data)
					end
					return data
				end
				getgenv().SB2InvLockedOnlyHooked = true
				return true
			end

			getgenv().SB2InvFilterCleanup = function()
				restoreDataHook()
			end

			FilterBox:AddLabel('Hides every unlocked tile in the in-game inventory grid.')
			FilterBox:AddToggle('InvShowLockedOnly', {
				Text = 'Show locked items only',
				Default = false,
				Tooltip = 'Filters GetInventoryData so unlocked gear is hidden. Turn off to restore the full list.',
			}):OnChanged(function(on)
				if on then
					if not installDataHook() then
						Library:Notify('Inventory filter unavailable (InventoryUI missing)', 5)
						task.defer(function()
							if Toggles.InvShowLockedOnly then
								Toggles.InvShowLockedOnly:SetValue(false)
							end
						end)
						return
					end
				else
					restoreDataHook()
				end
				local rebuilt = rebuildInventoryList()
				Library:Notify(
					on and (rebuilt and 'Showing locked items only' or 'Filter on — reopen inventory to refresh')
						or (rebuilt and 'Full inventory restored' or 'Filter off — reopen inventory to refresh'),
					5
				)
			end)
			FilterBox:AddButton('Refresh inventory list', function()
				if isToggleOn('InvShowLockedOnly') then
					installDataHook()
				end
				if rebuildInventoryList() then
					Library:Notify('Inventory list rebuilt', 3)
				else
					Library:Notify('Open your inventory once, then try again', 5)
				end
			end)
		end

		-- Weapon visual modifier (held CharacterItems tools — client view only).
		local WeaponModBox = InvTab:AddRightGroupbox('Weapon modifier')
		assert(WeaponModBox, 'Weapon modifier groupbox nil')
		do
			local HttpService = game:GetService('HttpService')
			local RunService = game:GetService('RunService')
			local ReplicatedStorage = game:GetService('ReplicatedStorage')
			local PhysicsService = game:GetService('PhysicsService')
			local function flattenOpt(value)
				local fn = getgenv().SB2FlattenOptionValue
				if type(fn) == 'function' then
					local ok, out = pcall(fn, value)
					if ok and out ~= nil then
						return out
					end
				end
				if type(value) == 'string' then
					return value
				end
				if type(value) == 'table' then
					if type(value[1]) == 'string' then
						return value[1]
					end
					for k, on in pairs(value) do
						if on == true and type(k) == 'string' then
							return k
						end
					end
				end
				return tostring(value or '')
			end
			local WEAPON_MOD_ATTR = '_SB2WeaponModVis'
			local WEAPON_MOD_ORIG = '_SB2WeaponModOrig'

			if type(getgenv().SB2WeaponModCleanup) == 'function' then
				pcall(getgenv().SB2WeaponModCleanup)
			end
			-- Drop older live Sakura overlay hook if still attached.
			pcall(function()
				local c = getgenv()._SB2VisualSwordConn
				if c then
					c:Disconnect()
				end
				getgenv()._SB2VisualSwordConn = nil
			end)

			local lookCache = getgenv().SB2WeaponLookCache
			if type(lookCache) ~= 'table' then
				lookCache = {}
				getgenv().SB2WeaponLookCache = lookCache
			end
			-- Keep any prior Sakura clone as a named look.
			if getgenv()._SB2SakuraToolClone and typeof(getgenv()._SB2SakuraToolClone) == 'Instance' then
				lookCache['Sakura Dreams'] = getgenv()._SB2SakuraToolClone
			end

			local defaults = {
				Enabled = false,
				Target = 'Right',
				Mode = 'Edit current',
				Look = '(none)',
				Anchor = 'Auto',
				ColorOn = false,
				ColorR = 255,
				ColorG = 255,
				ColorB = 255,
				Scale = 1,
				ScaleX = 1,
				ScaleY = 1,
				ScaleZ = 1,
				RotX = 0,
				RotY = 0,
				RotZ = 0,
				OffX = 0,
				OffY = 0,
				OffZ = 0,
				Transparency = 0,
				AnimEnabled = false,
				AnimPack = '(default)',
			}
			local state = getgenv().SB2WeaponModState
			if type(state) ~= 'table' then
				state = {}
				getgenv().SB2WeaponModState = state
			end
			for k, v in pairs(defaults) do
				if state[k] == nil then
					state[k] = v
				end
			end

			local function readPrefsFile()
				if type(isfile) ~= 'function' or type(readfile) ~= 'function' then
					return nil
				end
				local ok, exists = pcall(isfile, WEAPON_MOD_PATH)
				if not ok or not exists then
					return nil
				end
				local okRead, body = pcall(readfile, WEAPON_MOD_PATH)
				if not okRead or type(body) ~= 'string' or body == '' then
					return nil
				end
				local okDecode, decoded = pcall(function()
					return HttpService:JSONDecode(body)
				end)
				if okDecode and type(decoded) == 'table' then
					return decoded
				end
				return nil
			end

			local function persistPrefs()
				if type(writefile) ~= 'function' then
					return
				end
				local payload = {}
				for k in pairs(defaults) do
					payload[k] = state[k]
				end
				pcall(function()
					if type(makefolder) == 'function' and type(isfolder) == 'function' then
						if not isfolder(CONFIG.ConfigFolder) then
							makefolder(CONFIG.ConfigFolder)
						end
					end
					writefile(WEAPON_MOD_PATH, HttpService:JSONEncode(payload))
				end)
			end

			do
				local saved = readPrefsFile()
				if type(saved) == 'table' then
					for k, v in pairs(saved) do
						if defaults[k] ~= nil then
							state[k] = v
						end
					end
				end
				-- Boot kill sets this so reload never auto-spawns a ghost (ragdoll risk).
				if state._AnimSkipAutoApply == true then
					state.AnimEnabled = false
				end
			end

			local function localUid()
				local lp = Players.LocalPlayer
				return lp and tostring(lp.UserId) or nil
			end

			local function getWeaponFolder(hand)
				local uid = localUid()
				local root = workspace:FindFirstChild('CharacterItems')
				root = root and uid and root:FindFirstChild(uid)
				if not root then
					return nil
				end
				if hand == 'Left' then
					return root:FindFirstChild('LeftWeapon')
				end
				return root:FindFirstChild('RightWeapon')
			end

			local function targetHands()
				local t = state.Target
				if t == 'Left' then
					return { 'Left' }
				end
				if t == 'Both' then
					return { 'Right', 'Left' }
				end
				return { 'Right' }
			end

			local function isOverlayJunk(inst)
				if not inst then
					return true
				end
				if inst:GetAttribute(WEAPON_MOD_ATTR) or inst:GetAttribute('_SB2SakuraVis') then
					return true
				end
				local n = tostring(inst.Name)
				if string.find(n, 'WeaponMod_', 1, true) or string.find(n, 'SakuraVis', 1, true) then
					return true
				end
				return false
			end

			local function clearOverlay(tool)
				if not tool then
					return
				end
				for _, c in ipairs(tool:GetChildren()) do
					if isOverlayJunk(c) then
						c:Destroy()
					end
				end
			end

			local function sanitizeLookTool(lookTool)
				if typeof(lookTool) ~= 'Instance' then
					return lookTool
				end
				for _, c in ipairs(lookTool:GetChildren()) do
					if isOverlayJunk(c) then
						c:Destroy()
					end
				end
				for _, d in ipairs(lookTool:GetDescendants()) do
					if d:IsA('BasePart') then
						d:SetAttribute(WEAPON_MOD_ATTR, nil)
						d:SetAttribute('_SB2SakuraVis', nil)
						d:SetAttribute(WEAPON_MOD_ORIG, nil)
						if d.Transparency >= 1 then
							d.Transparency = 0
						end
						d.LocalTransparencyModifier = 0
					end
				end
				return lookTool
			end

			-- Scrub polluted captures (overlay-of-overlay clones).
			for name, look in pairs(lookCache) do
				if typeof(look) == 'Instance' then
					sanitizeLookTool(look)
				elseif look == nil then
					lookCache[name] = nil
				end
			end
			getgenv().SB2WeaponLookCache = lookCache

			local function syncStateFromUi()
				local T = Toggles
				local O = Options
				if type(T) == 'table' and type(T.WeaponModEnabled) == 'table' then
					state.Enabled = T.WeaponModEnabled.Value == true
				end
				if type(T) == 'table' and type(T.WeaponModColorOn) == 'table' then
					state.ColorOn = T.WeaponModColorOn.Value == true
				end
				local function opt(name)
					return type(O) == 'table' and O[name] or nil
				end
				local function setStr(key, optName, fallback)
					local o = opt(optName)
					if not o then
						return
					end
					local v = flattenOpt(o.Value)
					if type(v) == 'string' and v ~= '' then
						state[key] = v
					elseif fallback then
						state[key] = fallback
					end
				end
				local function setNum(key, optName)
					local o = opt(optName)
					if not o then
						return
					end
					local n = tonumber(o.Value)
					if n ~= nil then
						state[key] = n
					end
				end
				setStr('Target', 'WeaponModTarget', 'Right')
				setStr('Mode', 'WeaponModMode', 'Edit current')
				setStr('Look', 'WeaponModLook', '(none)')
				setStr('Anchor', 'WeaponModAnchor', 'Auto')
				setNum('ColorR', 'WeaponModColorR')
				setNum('ColorG', 'WeaponModColorG')
				setNum('ColorB', 'WeaponModColorB')
				setNum('Scale', 'WeaponModScale')
				setNum('ScaleX', 'WeaponModScaleX')
				setNum('ScaleY', 'WeaponModScaleY')
				setNum('ScaleZ', 'WeaponModScaleZ')
				setNum('RotX', 'WeaponModRotX')
				setNum('RotY', 'WeaponModRotY')
				setNum('RotZ', 'WeaponModRotZ')
				setNum('OffX', 'WeaponModOffX')
				setNum('OffY', 'WeaponModOffY')
				setNum('OffZ', 'WeaponModOffZ')
				setNum('Transparency', 'WeaponModTransparency')
			end

			local function rememberOrig(part)
				if part:GetAttribute(WEAPON_MOD_ORIG) then
					return
				end
				local ok, payload = pcall(function()
					return HttpService:JSONEncode({
						Size = { part.Size.X, part.Size.Y, part.Size.Z },
						Color = { part.Color.R, part.Color.G, part.Color.B },
						Transparency = part.Transparency,
						LocalTransparencyModifier = part.LocalTransparencyModifier,
					})
				end)
				if ok and type(payload) == 'string' then
					part:SetAttribute(WEAPON_MOD_ORIG, payload)
				end
			end

			local function restoreOrig(part)
				local raw = part:GetAttribute(WEAPON_MOD_ORIG)
				if type(raw) ~= 'string' then
					return
				end
				local ok, data = pcall(function()
					return HttpService:JSONDecode(raw)
				end)
				if not ok or type(data) ~= 'table' then
					return
				end
				if type(data.Size) == 'table' and #data.Size >= 3 then
					part.Size = Vector3.new(data.Size[1], data.Size[2], data.Size[3])
				end
				if type(data.Color) == 'table' and #data.Color >= 3 then
					part.Color = Color3.new(data.Color[1], data.Color[2], data.Color[3])
				end
				if type(data.Transparency) == 'number' then
					part.Transparency = data.Transparency
				end
				if type(data.LocalTransparencyModifier) == 'number' then
					part.LocalTransparencyModifier = data.LocalTransparencyModifier
				end
				part:SetAttribute(WEAPON_MOD_ORIG, nil)
			end

			local function restoreWelds(tool)
				local map = getgenv().SB2WeaponModWeldBase
				if type(map) ~= 'table' or not tool then
					return
				end
				for _, d in ipairs(tool:GetDescendants()) do
					if not d:IsA('BasePart') then
						continue
					end
					for _, w in ipairs(d:GetChildren()) do
						if w:IsA('Weld') and typeof(map[w]) == 'CFrame' then
							w.C0 = map[w]
							map[w] = nil
							w:SetAttribute('_SB2ModBaseC0', nil)
							w:SetAttribute('_SB2ModHasBase', nil)
						end
					end
				end
			end

			local function restoreWeapon(folder)
				if not folder then
					return
				end
				local tool = folder:FindFirstChild('Tool')
				if not tool then
					return
				end
				-- Restore Size/Color from ORIG *before* clearing attrs. Clearing first
				-- left scaled meshes stuck (ground-beam / flat sword).
				for _, d in ipairs(tool:GetDescendants()) do
					if d:IsA('BasePart') then
						restoreOrig(d)
					end
				end
				restoreWelds(tool)
				clearOverlay(tool)
				for _, d in ipairs(tool:GetDescendants()) do
					if d:IsA('BasePart') then
						d:SetAttribute(WEAPON_MOD_ORIG, nil)
						d:SetAttribute(WEAPON_MOD_ATTR, nil)
						d:SetAttribute('_SB2SakuraVis', nil)
						if not isOverlayJunk(d) then
							d.LocalTransparencyModifier = 0
						end
					end
				end
			end

			local function resetWeaponModSliders()
				state.Scale = 1
				state.ScaleX = 1
				state.ScaleY = 1
				state.ScaleZ = 1
				state.RotX = 0
				state.RotY = 0
				state.RotZ = 0
				state.OffX = 0
				state.OffY = 0
				state.OffZ = 0
				state.Transparency = 0
				state.ColorOn = false
				state.Mode = 'Edit current'
				local function setOpt(name, value)
					local o = Options[name]
					if type(o) == 'table' and type(o.SetValue) == 'function' then
						pcall(function()
							o:SetValue(value)
						end)
					end
				end
				setOpt('WeaponModScale', 1)
				setOpt('WeaponModScaleX', 1)
				setOpt('WeaponModScaleY', 1)
				setOpt('WeaponModScaleZ', 1)
				setOpt('WeaponModRotX', 0)
				setOpt('WeaponModRotY', 0)
				setOpt('WeaponModRotZ', 0)
				setOpt('WeaponModOffX', 0)
				setOpt('WeaponModOffY', 0)
				setOpt('WeaponModOffZ', 0)
				setOpt('WeaponModTransparency', 0)
				setOpt('WeaponModMode', 'Edit current')
				pcall(function()
					if Toggles.WeaponModColorOn and type(Toggles.WeaponModColorOn.SetValue) == 'function' then
						Toggles.WeaponModColorOn:SetValue(false)
					end
				end)
			end

			local function hardResetHeldVisuals()
				-- Stop heartbeat/queue from painting slider values back on.
				state.SuppressUntil = os.clock() + 12
				state.Enabled = false
				pcall(function()
					if Toggles.WeaponModEnabled and type(Toggles.WeaponModEnabled.SetValue) == 'function' then
						Toggles.WeaponModEnabled:SetValue(false)
					end
				end)
				resetWeaponModSliders()
				getgenv()._SB2SakuraVisualWanted = false
				pcall(function()
					local c = getgenv()._SB2VisualSwordConn
					if c then
						c:Disconnect()
					end
					getgenv()._SB2VisualSwordConn = nil
				end)
				persistPrefs()

				-- NEVER Destroy(Tool). Server will not recreate it while still
				-- "equipped" — that left Handle-only grips and ground-beam meshes.
				for _, hand in ipairs({ 'Right', 'Left' }) do
					local folder = getWeaponFolder(hand)
					if not folder then
						continue
					end
					for _, ch in ipairs(folder:GetChildren()) do
						if isOverlayJunk(ch) then
							pcall(function()
								ch:Destroy()
							end)
						end
					end
					restoreWeapon(folder)
				end
				-- Welds already restored; drop the base map so a later enable
				-- re-captures clean C0 values.
				getgenv().SB2WeaponModWeldBase = {}
				Library:Notify('Held visuals reset (modifier off, sizes/welds restored — no Tool destroy)', 6)
			end

			local function weldC1Of(part)
				for _, d in ipairs(part:GetChildren()) do
					if d:IsA('Weld') then
						return d.C1
					end
				end
				return nil
			end

			local function handleSpaceCF(part)
				local c1 = weldC1Of(part)
				if not c1 then
					return CFrame.new()
				end
				return c1:Inverse()
			end

			local function pickAnchor(tool, handle)
				local mode = state.Anchor
				if mode == 'Handle' and handle then
					return handle
				end
				if mode == 'Blade' then
					local b = tool:FindFirstChild('Blade')
					if b and b:IsA('BasePart') then
						return b
					end
				end
				if mode == 'Plane' then
					for _, n in ipairs({ 'Plane.001', 'Plane', 'Mesh' }) do
						local p = tool:FindFirstChild(n)
						if p and p:IsA('BasePart') then
							return p
						end
					end
				end
				-- Auto: prefer Blade (hitbox), else first MeshPart, else Handle.
				local blade = tool:FindFirstChild('Blade')
				if blade and blade:IsA('BasePart') then
					return blade
				end
				for _, d in ipairs(tool:GetDescendants()) do
					if d:IsA('MeshPart') then
						return d
					end
				end
				return handle
			end

			local function transformCF()
				local rx = math.rad(tonumber(state.RotX) or 0)
				local ry = math.rad(tonumber(state.RotY) or 0)
				local rz = math.rad(tonumber(state.RotZ) or 0)
				local ox = tonumber(state.OffX) or 0
				local oy = tonumber(state.OffY) or 0
				local oz = tonumber(state.OffZ) or 0
				return CFrame.new(ox, oy, oz) * CFrame.Angles(rx, ry, rz)
			end

			local function scaleVec()
				local u = tonumber(state.Scale) or 1
				return Vector3.new(
					u * (tonumber(state.ScaleX) or 1),
					u * (tonumber(state.ScaleY) or 1),
					u * (tonumber(state.ScaleZ) or 1)
				)
			end

			local function tintColor()
				return Color3.fromRGB(
					math.clamp(math.floor(tonumber(state.ColorR) or 255), 0, 255),
					math.clamp(math.floor(tonumber(state.ColorG) or 255), 0, 255),
					math.clamp(math.floor(tonumber(state.ColorB) or 255), 0, 255)
				)
			end

			local function applyEditCurrent(tool)
				local sc = scaleVec()
				local tint = tintColor()
				local tf = transformCF()
				local tr = tonumber(state.Transparency) or 0
				for _, d in ipairs(tool:GetDescendants()) do
					if d:IsA('BasePart') and not d:GetAttribute(WEAPON_MOD_ATTR) then
						rememberOrig(d)
						local orig = d:GetAttribute(WEAPON_MOD_ORIG)
						local baseSize = d.Size
						if type(orig) == 'string' then
							local ok, data = pcall(function()
								return HttpService:JSONDecode(orig)
							end)
							if ok and type(data) == 'table' and type(data.Size) == 'table' then
								baseSize = Vector3.new(data.Size[1], data.Size[2], data.Size[3])
							end
						end
						d.Size = Vector3.new(baseSize.X * sc.X, baseSize.Y * sc.Y, baseSize.Z * sc.Z)
						if state.ColorOn == true then
							d.Color = tint
						end
						d.Transparency = math.clamp(tr, 0, 1)
						d.LocalTransparencyModifier = 0
						-- Nudge weld C0 on parts welded to Handle for rot/offset.
						for _, w in ipairs(d:GetChildren()) do
							if w:IsA('Weld') and w.Part0 and w.Part0.Name == 'Handle' then
								if not w:GetAttribute('_SB2ModBaseC0') then
									w:SetAttribute('_SB2ModBaseC0', tostring(w.C0))
									w:SetAttribute('_SB2ModHasBase', true)
									-- store via genv map (attributes can't hold CFrame)
									local map = getgenv().SB2WeaponModWeldBase
									if type(map) ~= 'table' then
										map = {}
										getgenv().SB2WeaponModWeldBase = map
									end
									map[w] = w.C0
								end
								local map = getgenv().SB2WeaponModWeldBase
								local base = map and map[w]
								if typeof(base) == 'CFrame' then
									w.C0 = base * tf
								end
							end
						end
					end
				end
			end

			local function axisAlignFor(anchor, lookBlade)
				-- Map look blade long-axis onto anchor long-axis.
				if not anchor or not lookBlade then
					return CFrame.new()
				end
				local function longAxis(size)
					if size.X >= size.Y and size.X >= size.Z then
						return Vector3.new(1, 0, 0)
					end
					if size.Y >= size.X and size.Y >= size.Z then
						return Vector3.new(0, 1, 0)
					end
					return Vector3.new(0, 0, 1)
				end
				local from = longAxis(lookBlade.Size)
				local to = longAxis(anchor.Size)
				if from:Dot(to) > 0.99 then
					return CFrame.new()
				end
				-- Common katana(+Z) → primordial Blade(+X)
				if math.abs(from.Z) > 0.9 and math.abs(to.X) > 0.9 then
					return CFrame.Angles(0, math.pi / 2, 0)
				end
				-- Common katana(+Z) → Plane(+Y)
				if math.abs(from.Z) > 0.9 and math.abs(to.Y) > 0.9 then
					return CFrame.Angles(math.pi / 2, 0, 0)
				end
				-- Mesh along +X onto Plane +Y
				if math.abs(from.X) > 0.9 and math.abs(to.Y) > 0.9 then
					return CFrame.Angles(0, 0, -math.pi / 2)
				end
				return CFrame.new()
			end

			local function applyOverlay(tool, handle, lookTool)
				clearOverlay(tool)
				lookTool = sanitizeLookTool(lookTool)
				if typeof(lookTool) ~= 'Instance' then
					return
				end
				local anchor = pickAnchor(tool, handle)
				if not anchor then
					return
				end
				-- Hide native meshes (keep hitbox parts present).
				for _, d in ipairs(tool:GetDescendants()) do
					if d:IsA('BasePart') and not isOverlayJunk(d) then
						rememberOrig(d)
						d.Transparency = 1
						d.LocalTransparencyModifier = 1
					elseif (d:IsA('Decal') or d:IsA('Texture')) and not (d.Parent and isOverlayJunk(d.Parent)) then
						pcall(function()
							d.Transparency = 1
						end)
					end
				end

				local lookBlade = lookTool:FindFirstChild('Blade')
				local align = axisAlignFor(anchor, lookBlade)
				local lookRootCF = lookBlade and handleSpaceCF(lookBlade) or CFrame.new()
				local sc = scaleVec()
				local tint = tintColor()
				local tf = transformCF()
				local tr = tonumber(state.Transparency) or 0

				for _, src in ipairs(lookTool:GetChildren()) do
					if not src:IsA('BasePart') or isOverlayJunk(src) then
						continue
					end
					if src.Name == 'Blade' then
						continue
					end
					local part = src:Clone()
					for _, d in ipairs(part:GetDescendants()) do
						if d:IsA('Weld') or d:IsA('Motor6D') or d:IsA('WeldConstraint') then
							d:Destroy()
						end
					end
					part:SetAttribute(WEAPON_MOD_ATTR, true)
					part:SetAttribute(WEAPON_MOD_ORIG, nil)
					part.Name = 'WeaponMod_' .. src.Name:gsub('[^%w]', '_')
					part.Anchored = false
					part.CanCollide = false
					part.CanTouch = false
					part.CanQuery = false
					part.Massless = true
					local base = src.Size
					part.Size = Vector3.new(base.X * sc.X, base.Y * sc.Y, base.Z * sc.Z)
					if state.ColorOn == true then
						part.Color = tint
					end
					part.Transparency = math.clamp(tr, 0, 1)
					part.LocalTransparencyModifier = 0
					part.Parent = tool

					local rel = lookRootCF:ToObjectSpace(handleSpaceCF(src))
					local w = Instance.new('Weld')
					w.Name = 'WeaponModWeld'
					w.Part0 = anchor
					w.Part1 = part
					w.C0 = tf * align * rel
					w.C1 = CFrame.new()
					w.Parent = part
				end
			end

			local function applyToFolder(folder)
				if not folder then
					return false
				end
				local tool = folder:FindFirstChild('Tool')
				local handle = folder:FindFirstChild('Handle')
				if not tool then
					return false
				end
				if state.Mode == 'Overlay look' then
					local lookName = state.Look
					if type(lookName) ~= 'string' or lookName == '' or lookName == '(none)' then
						return false
					end
					local look = lookCache[lookName]
					if typeof(look) ~= 'Instance' then
						return false
					end
					sanitizeLookTool(look)
					applyOverlay(tool, handle, look)
					return true
				end
				-- Edit current
				clearOverlay(tool)
				applyEditCurrent(tool)
				return true
			end

			local function applyAll()
				syncStateFromUi()
				if (tonumber(state.SuppressUntil) or 0) > os.clock() then
					return
				end
				persistPrefs()
				if state.Enabled ~= true then
					for _, hand in ipairs({ 'Right', 'Left' }) do
						restoreWeapon(getWeaponFolder(hand))
					end
					return
				end
				for _, hand in ipairs(targetHands()) do
					applyToFolder(getWeaponFolder(hand))
				end
			end

			local function captureEquippedLook()
				local folder = getWeaponFolder('Right') or getWeaponFolder('Left')
				if not folder or not folder:FindFirstChild('Tool') then
					Library:Notify('No held weapon to capture', 4)
					return nil
				end
				-- Capture clean native meshes only (never overlay stacks).
				restoreWeapon(folder)
				local inv = folder:FindFirstChild('InventoryID')
				local id = inv and inv.Value
				local name = 'Captured'
				local profile = getLiveProfile and getLiveProfile() or nil
				if not profile then
					local lp = Players.LocalPlayer
					profile = lp and ReplicatedStorage:FindFirstChild('Profiles') and ReplicatedStorage.Profiles:FindFirstChild(lp.Name)
				end
				if profile and id then
					local invFolder = profile:FindFirstChild('Inventory')
					if invFolder then
						for _, it in ipairs(invFolder:GetChildren()) do
							if it:IsA('IntValue') and it.Value == id then
								name = it.Name
								break
							end
						end
					end
				end
				local clone = folder.Tool:Clone()
				clone.Name = 'WeaponLook_' .. name
				for _, d in ipairs(clone:GetDescendants()) do
					if d:IsA('Script') or d:IsA('LocalScript') then
						d:Destroy()
					end
				end
				sanitizeLookTool(clone)
				lookCache[name] = clone
				if name == 'Sakura Dreams' then
					getgenv()._SB2SakuraToolClone = clone
				end
				getgenv().SB2WeaponLookCache = lookCache
				-- Re-apply mods after capture restored the native look.
				if state.Enabled == true then
					task.defer(applyAll)
				end
				return name
			end

			local function lookDropdownValues()
				local values = { '(none)' }
				local names = {}
				for n in pairs(lookCache) do
					if type(n) == 'string' and n ~= '' then
						names[#names + 1] = n
					end
				end
				table.sort(names)
				for _, n in ipairs(names) do
					values[#values + 1] = n
				end
				return values
			end

			local function stateSig()
				return table.concat({
					tostring(state.Enabled),
					tostring(state.Mode),
					tostring(state.Look),
					tostring(state.Anchor),
					tostring(state.ColorOn),
					tostring(state.ColorR),
					tostring(state.ColorG),
					tostring(state.ColorB),
					tostring(state.Scale),
					tostring(state.ScaleX),
					tostring(state.ScaleY),
					tostring(state.ScaleZ),
					tostring(state.RotX),
					tostring(state.RotY),
					tostring(state.RotZ),
					tostring(state.OffX),
					tostring(state.OffY),
					tostring(state.OffZ),
					tostring(state.Transparency),
					tostring(state.Target),
				}, '|')
			end

			local applyQueued = false
			local lastSigApplied = ''
			local function queueApply()
				persistPrefs()
				if applyQueued then
					return
				end
				applyQueued = true
				task.defer(function()
					applyQueued = false
					applyAll()
					lastSigApplied = stateSig()
				end)
			end

			local conn = getgenv().SB2WeaponModConn
			if conn then
				pcall(function()
					conn:Disconnect()
				end)
			end
			local lastApply = 0
			getgenv().SB2WeaponModConn = RunService.Heartbeat:Connect(function()
				if (tonumber(state.SuppressUntil) or 0) > os.clock() then
					return
				end
				syncStateFromUi()
				if state.Enabled ~= true then
					return
				end
				local gui = getgenv().SB2PlayerToolsGui
				if not (gui and gui.Parent) then
					return
				end
				local now = os.clock()
				if now - lastApply < 0.2 then
					return
				end
				lastApply = now
				local sig = stateSig()
				local need = sig ~= lastSigApplied
				for _, hand in ipairs(targetHands()) do
					local folder = getWeaponFolder(hand)
					local tool = folder and folder:FindFirstChild('Tool')
					if not tool then
						continue
					end
					if state.Mode == 'Overlay look' then
						local has = false
						for _, c in ipairs(tool:GetChildren()) do
							if c:GetAttribute(WEAPON_MOD_ATTR) then
								has = true
								break
							end
						end
						if need or not has then
							applyToFolder(folder)
							lastSigApplied = sig
						else
							for _, d in ipairs(tool:GetDescendants()) do
								if d:IsA('BasePart') and not d:GetAttribute(WEAPON_MOD_ATTR) then
									if d.Transparency < 1 then
										d.Transparency = 1
									end
								end
							end
						end
					elseif need then
						applyToFolder(folder)
						lastSigApplied = sig
					end
				end
			end)

			getgenv().SB2WeaponModCleanup = function()
				state.Enabled = false
				state.AnimEnabled = false
				local c = getgenv().SB2WeaponModConn
				if c then
					pcall(function()
						c:Disconnect()
					end)
				end
				getgenv().SB2WeaponModConn = nil
				pcall(function()
					local ac = getgenv()._SB2AnimCharConn
					if ac then
						ac:Disconnect()
					end
					getgenv()._SB2AnimCharConn = nil
				end)
				for _, hand in ipairs({ 'Right', 'Left' }) do
					restoreWeapon(getWeaponFolder(hand))
				end
				if type(getgenv().SB2AnimSwapStop) == 'function' then
					pcall(getgenv().SB2AnimSwapStop)
				end
			end
			getgenv().SB2WeaponModApply = applyAll
			getgenv().SB2WeaponModCapture = captureEquippedLook

			----------------------------------------------------------------------
			-- Client-only animation pack swapper (local ghost clone — others keep
			-- seeing your real/server anims; no AnimSettings / shop remotes).
			----------------------------------------------------------------------
			do
				local LOCO_SLOT = {
					Idle = { 'idle' },
					Running = { 'run', 'walk' },
					Jump = { 'jump' },
					Fall = { 'fall' },
				}
				-- Database.Animations junk that is NOT a usable style pack.
				local ANIM_PACK_BLOCKLIST = {
					dagger = true,
					daggers = true,
					misc = true,
					swordshield = true,
				}
				-- Combat-only styles (no Animate.Packs loco) → use this loco fallback.
				local COMBAT_STYLE_LOCO = {
					TeaCup = 'Unarmed',
				}

				local function getLiveCharacter()
					local lp = Players.LocalPlayer
					if not lp then
						return nil
					end
					local folder = workspace:FindFirstChild('Characters')
					local named = folder and folder:FindFirstChild(lp.Name)
					if named then
						return named
					end
					return lp.Character
				end

				local function packHasLoco(folder)
					if not folder then
						return false
					end
					local idle = folder:FindFirstChild('Idle')
					local run = folder:FindFirstChild('Running')
					return idle
						and idle:IsA('Animation')
						and type(idle.AnimationId) == 'string'
						and idle.AnimationId ~= ''
						and run
						and run:IsA('Animation')
						and type(run.AnimationId) == 'string'
						and run.AnimationId ~= ''
				end

				local function combatUsable(folder)
					if not folder then
						return false
					end
					local swing = folder:FindFirstChild('Swing1')
					return swing
						and swing:IsA('Animation')
						and type(swing.AnimationId) == 'string'
						and swing.AnimationId ~= ''
				end

				local function animPackNames()
					local values = { '(default)' }
					local seen = { ['(default)'] = true }
					local function add(name)
						if type(name) ~= 'string' or name == '' or seen[name] then
							return
						end
						if ANIM_PACK_BLOCKLIST[string.lower(name)] then
							return
						end
						seen[name] = true
						values[#values + 1] = name
					end
					-- Animate.Packs with real Idle+Running.
					local char = getLiveCharacter()
					local packs = char and char:FindFirstChild('Animate')
					packs = packs and packs:FindFirstChild('Packs')
					if packs then
						for _, p in ipairs(packs:GetChildren()) do
							if packHasLoco(p) then
								add(p.Name)
							end
						end
					end
					-- Combat-only styles (e.g. TeaCup) from Database.Animations.
					local db = ReplicatedStorage:FindFirstChild('Database')
					db = db and db:FindFirstChild('Animations')
					if db then
						for styleName in pairs(COMBAT_STYLE_LOCO) do
							if combatUsable(db:FindFirstChild(styleName)) then
								add(styleName)
							end
						end
					end
					table.sort(values, function(a, b)
						if a == '(default)' then
							return true
						end
						if b == '(default)' then
							return false
						end
						return a:lower() < b:lower()
					end)
					return values
				end

				local function findPackFolder(packName)
					if type(packName) ~= 'string' or packName == '' or packName == '(default)' then
						return nil, nil
					end
					if ANIM_PACK_BLOCKLIST[string.lower(packName)] then
						return nil, nil
					end
					local char = getLiveCharacter()
					local packs = char
						and char:FindFirstChild('Animate')
						and char.Animate:FindFirstChild('Packs')
					local locoName = COMBAT_STYLE_LOCO[packName] or packName
					local loco = packs and packs:FindFirstChild(locoName)
					if loco and not packHasLoco(loco) then
						loco = nil
					end
					-- If combat style's preferred loco missing, try Unarmed then SingleSword.
					if not loco and packs and COMBAT_STYLE_LOCO[packName] then
						for _, alt in ipairs({ 'Unarmed', 'SingleSword', 'Katana' }) do
							local f = packs:FindFirstChild(alt)
							if packHasLoco(f) then
								loco = f
								break
							end
						end
					end
					local db = ReplicatedStorage:FindFirstChild('Database')
					db = db and db:FindFirstChild('Animations')
					local combat = db and db:FindFirstChild(packName)
					if not combatUsable(combat) then
						combat = nil
					end
					if not combat and db then
						local fallbacks = {
							SwissSabre = { 'Rapier' },
							Rapier = { 'SwissSabre' },
							Samurai = { 'Katana', 'Ninja' },
							Ninja = { 'Ninja', 'Katana' },
							Katana = { 'Katana', 'Ninja' },
							Noble = { 'Noble', 'SingleSword' },
							SingleSword = { 'SingleSword', 'Noble' },
							Reaper = { 'Reaper', 'Scythe' },
							Scythe = { 'Scythe', 'Reaper' },
							Vigilante = { 'Vigilante', 'DualWield' },
							DualWield = { 'DualWield', 'Vigilante' },
							Swiftstrike = { 'Swiftstrike', 'Spear' },
							Spear = { 'Spear', 'Swiftstrike' },
							Berserker = { 'Berserker', '2HSword' },
							['2HSword'] = { '2HSword', 'Berserker' },
							TeaCup = { 'TeaCup' },
						}
						for _, alt in ipairs(fallbacks[packName] or { packName }) do
							local f = db:FindFirstChild(alt)
							if combatUsable(f) then
								combat = f
								break
							end
						end
					end
					return loco, combat
				end

				local function setLtmTree(root, value)
					if not root then
						return
					end
					for _, d in ipairs(root:GetDescendants()) do
						if d:IsA('BasePart') then
							d.LocalTransparencyModifier = value
						end
					end
					if root:IsA('BasePart') then
						root.LocalTransparencyModifier = value
					end
				end

				local function clearGhost()
					local g = getgenv()._SB2AnimGhost
					if type(g) ~= 'table' then
						getgenv()._SB2AnimGhost = nil
						return
					end
					pcall(function()
						if g.hb then
							g.hb:Disconnect()
						end
					end)
					pcall(function()
						if g.played then
							g.played:Disconnect()
						end
					end)
					pcall(function()
						if g.weaponFolder and g.weaponFolder.Parent then
							g.weaponFolder:Destroy()
						end
					end)
					pcall(function()
						if g.clone and g.clone.Parent then
							g.clone:Destroy()
						end
					end)
					pcall(function()
						if g.world and g.world.Parent then
							g.world:Destroy()
						end
					end)
					-- Restore local transparency on real body / weapons.
					pcall(function()
						setLtmTree(g.real, 0)
					end)
					local uid = localUid()
					local items = workspace:FindFirstChild('CharacterItems')
					items = items and uid and items:FindFirstChild(uid)
					if items then
						setLtmTree(items, 0)
					end
					getgenv()._SB2AnimGhost = nil
				end

				local function applyLocoToAnimate(animate, locoPack)
					if not animate or not locoPack then
						return
					end
					for srcName, slots in pairs(LOCO_SLOT) do
						local src = locoPack:FindFirstChild(srcName)
						if not (src and src:IsA('Animation') and src.AnimationId ~= '') then
							continue
						end
						for _, slotName in ipairs(slots) do
							local slot = animate:FindFirstChild(slotName)
							if not slot then
								continue
							end
							for _, child in ipairs(slot:GetChildren()) do
								if child:IsA('Animation') then
									child.AnimationId = src.AnimationId
								end
							end
						end
					end
				end

				local function buildCombatRemap(combatPack)
					local map = {}
					if not combatPack then
						return map
					end
					local db = ReplicatedStorage:FindFirstChild('Database')
					db = db and db:FindFirstChild('Animations')
					if not db then
						return map
					end
					local targets = {}
					for _, a in ipairs(combatPack:GetChildren()) do
						if a:IsA('Animation')
							and type(a.AnimationId) == 'string'
							and a.AnimationId ~= ''
						then
							targets[a.Name] = a.AnimationId
						end
					end
					-- TeaCup (etc.) often only ships Swing1 — reuse it for Swing2/3/4.
					local swingFallback = targets.Swing1
						or targets.Swing2
						or targets.Swing3
						or targets.Swing4
					if swingFallback then
						for _, n in ipairs({ 'Swing1', 'Swing2', 'Swing3', 'Swing4' }) do
							if not targets[n] then
								targets[n] = swingFallback
							end
						end
					end
					if not next(targets) then
						return map
					end
					for _, folder in ipairs(db:GetChildren()) do
						if ANIM_PACK_BLOCKLIST[string.lower(folder.Name)] then
							continue
						end
						if folder == combatPack then
							continue
						end
						for _, a in ipairs(folder:GetChildren()) do
							if a:IsA('Animation')
								and type(a.AnimationId) == 'string'
								and a.AnimationId ~= ''
								and targets[a.Name]
							then
								map[a.AnimationId] = targets[a.Name]
							end
						end
					end
					return map
				end

				local function stripScripts(model)
					for _, d in ipairs(model:GetDescendants()) do
						if d:IsA('BaseScript') or d:IsA('LocalScript') or d:IsA('Script') then
							d:Destroy()
						end
					end
				end

				-- Ghost must NEVER collide/physically interact with the real character.
				-- Clone keeps Motor6D "Handle" → live CharacterItems.Handle; that weld
				-- yeets/ragdolls you the moment Combat Anchor is off.
				local GHOST_COL_GROUP = 'SB2AnimGhost'
				pcall(function()
					PhysicsService:RegisterCollisionGroup(GHOST_COL_GROUP)
				end)
				pcall(function()
					local groups = { 'Default', 'Players', 'Mobs', 'MobsNoCollision', GHOST_COL_GROUP }
					local okList, listed = pcall(function()
						return PhysicsService:GetRegisteredCollisionGroups()
					end)
					if okList and type(listed) == 'table' then
						for _, g in ipairs(listed) do
							local name = type(g) == 'table' and (g.name or g.Name) or g
							if type(name) == 'string' then
								groups[#groups + 1] = name
							end
						end
					end
					local seen = {}
					for _, other in ipairs(groups) do
						if not seen[other] then
							seen[other] = true
							pcall(function()
								PhysicsService:CollisionGroupSetCollidable(GHOST_COL_GROUP, other, false)
							end)
						end
					end
				end)

				local function enforceGhostPart(part)
					if not part or not part:IsA('BasePart') then
						return
					end
					part.CanCollide = false
					part.CanTouch = false
					part.CanQuery = false
					part.Massless = true
					part.AssemblyLinearVelocity = Vector3.zero
					part.AssemblyAngularVelocity = Vector3.zero
					pcall(function()
						part.CollisionGroup = GHOST_COL_GROUP
					end)
				end

				local function enforceGhostPhysics(model)
					if not model then
						return
					end
					for _, d in ipairs(model:GetDescendants()) do
						if d:IsA('BasePart') then
							enforceGhostPart(d)
						end
					end
					if model:IsA('BasePart') then
						enforceGhostPart(model)
					end
				end

				-- Destroy joints that still point at the LIVE character / CharacterItems.
				local function breakExternalConstraints(model, allowRoots)
					if not model then
						return
					end
					local function allowed(part)
						if not part then
							return true
						end
						if part:IsDescendantOf(model) then
							return true
						end
						if type(allowRoots) == 'table' then
							for _, root in ipairs(allowRoots) do
								if root and part:IsDescendantOf(root) then
									return true
								end
							end
						end
						return false
					end
					local kill = {}
					for _, d in ipairs(model:GetDescendants()) do
						if d:IsA('Motor6D') or d:IsA('Weld') or d:IsA('WeldConstraint') then
							if not allowed(d.Part0) or not allowed(d.Part1) then
								kill[#kill + 1] = d
							elseif d:IsA('Motor6D') and d.Name == 'Handle' then
								-- SB2 tool grip Motor6D — clone keeps Part1 on live CharacterItems.
								kill[#kill + 1] = d
							end
						elseif d:IsA('RigidConstraint')
							or d:IsA('SpringConstraint')
							or d:IsA('BallSocketConstraint')
							or d:IsA('HingeConstraint')
							or d:IsA('PrismaticConstraint')
							or d:IsA('CylindricalConstraint')
						then
							local a0, a1 = d.Attachment0, d.Attachment1
							local p0 = a0 and a0.Parent
							local p1 = a1 and a1.Parent
							if (p0 and not allowed(p0)) or (p1 and not allowed(p1)) then
								kill[#kill + 1] = d
							end
						end
					end
					for _, d in ipairs(kill) do
						pcall(function()
							d:Destroy()
						end)
					end
				end

				local function sanitizeGhostPhysics(model, opts)
					opts = opts or {}
					if not model then
						return
					end
					breakExternalConstraints(model, opts.allowRoots)
					enforceGhostPhysics(model)
					for _, d in ipairs(model:GetDescendants()) do
						if d:IsA('BodyMover') or d:IsA('BaseScript') then
							pcall(function()
								d:Destroy()
							end)
						end
					end
					local hum = model:FindFirstChildOfClass('Humanoid')
					if hum then
						-- Freeze the state machine so it cannot ragdoll or restore CanCollide.
						pcall(function()
							hum.EvaluateStateMachine = false
						end)
						hum.AutoRotate = false
						hum.WalkSpeed = 0
						hum.JumpPower = 0
						hum.JumpHeight = 0
						hum.HipHeight = 0
						hum.PlatformStand = true
						hum.Sit = false
						pcall(function()
							hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
							hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
							hum:SetStateEnabled(Enum.HumanoidStateType.Physics, false)
							hum:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
							hum:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
							hum:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
						end)
						if opts.initHum then
							pcall(function()
								hum:ChangeState(Enum.HumanoidStateType.Running)
							end)
						end
					end
					-- Anchor only the root. Limbs stay free so Motor6D tracks can pose them;
					-- WorldModel + broken external joints keep forces out of the live world.
					local root = model:FindFirstChild('HumanoidRootPart') or model.PrimaryPart
					if root and root:IsA('BasePart') then
						root.Anchored = true
						enforceGhostPart(root)
					end
				end

				local function ensureGhost(packName)
					-- #region agent log
					if type(getgenv().SB2DbgFling) == 'function' then
						getgenv().SB2DbgFling('A', 'ensureGhost:enter', 'ensureGhost called', {
							pack = tostring(packName),
						})
					end
					-- #endregion
					clearGhost()
					local real = getLiveCharacter()
					if not real then
						return false
					end
					local hrp = real:FindFirstChild('HumanoidRootPart') or real.PrimaryPart
					local hum = real:FindFirstChildOfClass('Humanoid')
					if not hrp or not hum then
						return false
					end
					local loco, combat = findPackFolder(packName)
					if not loco then
						Library:Notify('Not a locomotion pack: ' .. tostring(packName), 4)
						return false
					end

					-- WorldModel under CurrentCamera = local render + isolated physics
					-- (joints cannot couple into the live character / CharacterItems).
					local cam = workspace.CurrentCamera
					if not cam then
						return false
					end
					-- Kill leftovers from older ghost builds (pre-WorldModel).
					for _, name in ipairs({
						'_SB2AnimGhostWorld',
						'_SB2AnimGhostChar',
						'_SB2AnimGhostWeapons',
					}) do
						local orphan = cam:FindFirstChild(name)
						if orphan then
							pcall(function()
								orphan:Destroy()
							end)
						end
					end
					local world = Instance.new('WorldModel')
					world.Name = '_SB2AnimGhostWorld'
					world.Parent = cam

					real.Archivable = true
					local clone = real:Clone()
					real.Archivable = false
					-- CRITICAL: while Parent is still nil, destroy grip motors that still
					-- point at live CharacterItems.Handle. Parenting with that weld =
					-- instant ragdoll on reload.
					do
						local kill = {}
						for _, d in ipairs(clone:GetDescendants()) do
							if d:IsA('Motor6D') or d:IsA('Weld') or d:IsA('WeldConstraint') then
								if d.Name == 'Handle'
									or d.Name == 'GhostGrip'
									or (d.Part1 and d.Part1.Name == 'Handle' and not d.Part1:IsDescendantOf(clone))
									or (d.Part0 and not d.Part0:IsDescendantOf(clone))
									or (d.Part1 and not d.Part1:IsDescendantOf(clone))
								then
									kill[#kill + 1] = d
								end
							end
						end
						for _, d in ipairs(kill) do
							d:Destroy()
						end
					end
					stripScripts(clone)
					breakExternalConstraints(clone)
					sanitizeGhostPhysics(clone, { initHum = true })
					clone.Name = '_SB2AnimGhostChar'
					clone.Parent = world
					breakExternalConstraints(clone)
					sanitizeGhostPhysics(clone, { initHum = true })
					-- Belt: kill any Handle motor that reappeared on parent.
					do
						local kill = {}
						for _, d in ipairs(clone:GetDescendants()) do
							if d:IsA('Motor6D') and (d.Name == 'Handle' or d.Name == 'GhostGrip') then
								kill[#kill + 1] = d
							elseif (d:IsA('Motor6D') or d:IsA('Weld'))
								and (
									(d.Part0 and not d.Part0:IsDescendantOf(clone) and not d.Part0:IsDescendantOf(world))
									or (d.Part1 and not d.Part1:IsDescendantOf(clone) and not d.Part1:IsDescendantOf(world))
								)
							then
								kill[#kill + 1] = d
							end
						end
						for _, d in ipairs(kill) do
							d:Destroy()
						end
					end
					local cloneHum = clone:FindFirstChildOfClass('Humanoid')
					local cloneHrp = clone:FindFirstChild('HumanoidRootPart') or clone.PrimaryPart
					if cloneHum then
						cloneHum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
						pcall(function()
							cloneHum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
						end)
						pcall(function()
							cloneHum.EvaluateStateMachine = false
						end)
						cloneHum.PlatformStand = true
					end
					if cloneHrp then
						cloneHrp.Anchored = true
						enforceGhostPart(cloneHrp)
					end
					-- Hide real body + held weapons locally; others still see the real ones.
					setLtmTree(real, 1)
					local uid = localUid()
					local items = workspace:FindFirstChild('CharacterItems')
					items = items and uid and items:FindFirstChild(uid)
					if items then
						setLtmTree(items, 1)
					end

					local animate = clone:FindFirstChild('Animate')
					if animate then
						applyLocoToAnimate(animate, loco)
					end

					-- Prefer AnimationController so a Humanoid isn't driving physics.
					local animHost = clone:FindFirstChildOfClass('AnimationController')
					if not animHost then
						animHost = Instance.new('AnimationController')
						animHost.Name = '_SB2AnimController'
						animHost.Parent = clone
					end
					local animator = animHost:FindFirstChildOfClass('Animator')
					if not animator then
						local fromHum = cloneHum and cloneHum:FindFirstChildOfClass('Animator')
						if fromHum then
							fromHum.Parent = animHost
							animator = fromHum
						else
							animator = Instance.new('Animator')
							animator.Parent = animHost
						end
					end

					local remap = buildCombatRemap(combat)
					local tracks = {}
					local function stopTracks(fade)
						for _, tr in ipairs(tracks) do
							pcall(function()
								tr:Stop(fade or 0.1)
							end)
						end
						for i = #tracks, 1, -1 do
							tracks[i] = nil
						end
					end
					local function playLoco(kind, fade)
						if not animator then
							return
						end
						local src = loco:FindFirstChild(kind) or loco:FindFirstChild('Idle')
						if not (src and src:IsA('Animation') and src.AnimationId ~= '') then
							return
						end
						stopTracks(fade or 0.1)
						local anim = Instance.new('Animation')
						anim.AnimationId = src.AnimationId
						local ok, track = pcall(function()
							return animator:LoadAnimation(anim)
						end)
						anim:Destroy()
						if not ok or not track then
							return
						end
						track.Looped = kind == 'Idle' or kind == 'Running'
						if kind == 'Idle' then
							track.Priority = Enum.AnimationPriority.Idle
						elseif kind == 'Running' then
							track.Priority = Enum.AnimationPriority.Movement
						else
							track.Priority = Enum.AnimationPriority.Action
						end
						pcall(function()
							track:Play(fade or 0.12)
						end)
						tracks[#tracks + 1] = track
						return track
					end

					playLoco('Idle', 0.05)

					-- Mirror real AnimationPlayed → ghost with combat remap (swings etc.).
					local realAnimator = hum:FindFirstChildOfClass('Animator') or hum
					local playedConn = nil
					if realAnimator and typeof(realAnimator.AnimationPlayed) == 'RBXScriptSignal' then
						playedConn = realAnimator.AnimationPlayed:Connect(function(track)
							if getgenv().SB2WeaponModState and getgenv().SB2WeaponModState.AnimEnabled ~= true then
								return
							end
							local a = track and track.Animation
							local id = a and a.AnimationId
							if type(id) ~= 'string' then
								return
							end
							local useId = remap[id] or id
							local name = a and a.Name or ''
							if name == 'Idle'
								or name == 'Animation1'
								or name == 'Animation2'
								or name == 'WalkAnim'
								or name == 'RunAnim'
								or name == 'JumpAnim'
								or name == 'FallAnim'
							then
								return
							end
							if not animator then
								return
							end
							local anim = Instance.new('Animation')
							anim.AnimationId = useId
							local ok, ghostTrack = pcall(function()
								return animator:LoadAnimation(anim)
							end)
							anim:Destroy()
							if ok and ghostTrack then
								ghostTrack.Priority = Enum.AnimationPriority.Action4
								pcall(function()
									ghostTrack:Play(0.05)
									ghostTrack.Looped = track.Looped == true
								end)
							end
						end)
					end

					-- Weapon visuals welded to the ghost the same way SB2 grips work:
					-- Motor6D on Hand, Part0=RightGrip/LeftGrip, Part1=Handle, copy C0/C1.
					local weaponFolder = Instance.new('Folder')
					weaponFolder.Name = '_SB2AnimGhostWeapons'
					weaponFolder.Parent = world
					local ghostGrips = {} -- { handName = { motor, handle, invId } }
					local function clearGhostGrips()
						for _, info in pairs(ghostGrips) do
							pcall(function()
								if info.motor then
									info.motor:Destroy()
								end
							end)
						end
						table.clear(ghostGrips)
						for _, c in ipairs(weaponFolder:GetChildren()) do
							c:Destroy()
						end
						-- Orphan grip motors (GhostGrip + leftover Handle → live items).
						for _, handName in ipairs({ 'RightHand', 'LeftHand' }) do
							local hand = clone:FindFirstChild(handName)
							if hand then
								for _, ch in ipairs(hand:GetChildren()) do
									if ch:IsA('Motor6D')
										and (ch.Name == 'GhostGrip' or ch.Name == 'Handle')
									then
										ch:Destroy()
									end
								end
							end
						end
						breakExternalConstraints(clone, { weaponFolder })
					end
					local function findRealGripMotor(liveChar, handlePart, preferRight)
						if not liveChar or not handlePart then
							return nil
						end
						local handName = preferRight and 'RightHand' or 'LeftHand'
						local hand = liveChar:FindFirstChild(handName)
						if hand then
							for _, ch in ipairs(hand:GetChildren()) do
								if ch:IsA('Motor6D') and ch.Part1 == handlePart then
									return ch
								end
							end
						end
						for _, d in ipairs(liveChar:GetDescendants()) do
							if d:IsA('Motor6D') and d.Part1 == handlePart then
								return d
							end
						end
						return nil
					end
					local function sanitizeWeaponTree(root)
						for _, d in ipairs(root:GetDescendants()) do
							if d:IsA('BaseScript') then
								d:Destroy()
							elseif d:IsA('BasePart') then
								enforceGhostPart(d)
								d.Anchored = false
								d.LocalTransparencyModifier = 0
							end
						end
						if root:IsA('BasePart') then
							enforceGhostPart(root)
							root.Anchored = false
							root.LocalTransparencyModifier = 0
						end
					end
					local function refreshWeapons(liveChar, itemsRoot)
						if not itemsRoot or not clone then
							return
						end
						local needRebuild = false
						for _, handName in ipairs({ 'RightWeapon', 'LeftWeapon' }) do
							local folder = itemsRoot:FindFirstChild(handName)
							local handle = folder and folder:FindFirstChild('Handle')
							local tool = folder and folder:FindFirstChild('Tool')
							local inv = folder and folder:FindFirstChild('InventoryID')
							local invId = inv and tostring(inv.Value)
								or (handle and tostring(handle:GetAttribute('InventoryID') or handle.Size))
								or ''
							local prev = ghostGrips[handName]
							if not handle or not tool then
								if prev then
									needRebuild = true
								end
							elseif not prev or prev.invId ~= invId or not prev.motor or not prev.motor.Parent or not prev.handle or not prev.handle.Parent then
								needRebuild = true
							end
						end
						if not needRebuild and next(ghostGrips) then
							return
						end
						clearGhostGrips()
						for _, handName in ipairs({ 'RightWeapon', 'LeftWeapon' }) do
							local folder = itemsRoot:FindFirstChild(handName)
							local tool = folder and folder:FindFirstChild('Tool')
							local handle = folder and folder:FindFirstChild('Handle')
							if not (tool and handle and handle:IsA('BasePart')) then
								continue
							end
							local isRight = handName == 'RightWeapon'
							local gripName = isRight and 'RightGrip' or 'LeftGrip'
							local handNameRbx = isRight and 'RightHand' or 'LeftHand'
							local ghostHand = clone:FindFirstChild(handNameRbx)
							local ghostGrip = clone:FindFirstChild(gripName)
							if not ghostGrip and ghostHand then
								-- RightGrip is often a tiny Part parented to the character root.
								ghostGrip = ghostHand
							end
							if not ghostHand or not ghostGrip then
								continue
							end

							local hClone = handle:Clone()
							sanitizeWeaponTree(hClone)
							hClone.Name = 'Handle'
							hClone.Parent = weaponFolder

							local tClone = tool:Clone()
							sanitizeWeaponTree(tClone)
							tClone.Parent = weaponFolder
							-- Tool welds often reference the ORIGINAL Handle (outside clone tree).
							for _, w in ipairs(tClone:GetDescendants()) do
								if w:IsA('Weld') or w:IsA('Motor6D') or w:IsA('WeldConstraint') then
									if w.Part0 == handle or (w.Part0 and w.Part0.Name == 'Handle') then
										w.Part0 = hClone
									end
									if w.Part1 == handle or (w.Part1 and w.Part1.Name == 'Handle') then
										w.Part1 = hClone
									end
								end
							end

							local realMotor = findRealGripMotor(liveChar, handle, isRight)
							local m = Instance.new('Motor6D')
							m.Name = 'GhostGrip'
							m.Part0 = ghostGrip
							m.Part1 = hClone
							if realMotor then
								m.C0 = realMotor.C0
								m.C1 = realMotor.C1
							else
								-- Fallback: match live Handle relative to grip/hand.
								-- Motor6D: Part1.CFrame = Part0.CFrame * C0 * C1:Inverse()
								local liveAnchor = liveChar:FindFirstChild(gripName)
									or liveChar:FindFirstChild(handNameRbx)
								if liveAnchor then
									m.C0 = CFrame.new()
									m.C1 = liveAnchor.CFrame:ToObjectSpace(handle.CFrame):Inverse()
								end
							end
							m.Parent = ghostHand

							local inv = folder:FindFirstChild('InventoryID')
							local invKey = ''
							if inv then
								invKey = tostring(inv.Value)
							else
								invKey = tostring(handle:GetAttribute('InventoryID') or handle.Size)
							end
							ghostGrips[handName] = {
								motor = m,
								handle = hClone,
								invId = invKey,
							}
						end
						breakExternalConstraints(clone, { weaponFolder })
						enforceGhostPhysics(weaponFolder)
					end
					pcall(refreshWeapons, real, items)

					local lastWeaponRefresh = 0
					local lastHumSanitize = 0
					local lastJointBreak = 0
					local hb = RunService.RenderStepped:Connect(function()
						if state.AnimEnabled ~= true then
							return
						end
						local live = getLiveCharacter()
						local liveHrp = live and (live:FindFirstChild('HumanoidRootPart') or live.PrimaryPart)
						local liveHum = live and live:FindFirstChildOfClass('Humanoid')
						if not live or not liveHrp or not clone or not clone.Parent or not cloneHrp then
							return
						end
						-- Humanoid re-enables CanCollide on limbs; strip it EVERY frame or
						-- turning Combat Anchor off flings you into the ghost overlap.
						enforceGhostPhysics(clone)
						if weaponFolder then
							enforceGhostPhysics(weaponFolder)
						end
						cloneHrp.Anchored = true
						cloneHrp.CFrame = liveHrp.CFrame
						-- Keep real hidden if the game resets LTM.
						setLtmTree(live, 1)
						local uid2 = localUid()
						local items2 = workspace:FindFirstChild('CharacterItems')
						items2 = items2 and uid2 and items2:FindFirstChild(uid2)
						if items2 then
							setLtmTree(items2, 1)
						end
						-- Keep ghost grip C0/C1 matched to live (game can tweak grip each equip).
						for handName, info in pairs(ghostGrips) do
							local folder = items2 and items2:FindFirstChild(handName)
							local liveHandle = folder and folder:FindFirstChild('Handle')
							if info.motor and info.motor.Parent and liveHandle then
								local realMotor = findRealGripMotor(live, liveHandle, handName == 'RightWeapon')
								if realMotor then
									info.motor.C0 = realMotor.C0
									info.motor.C1 = realMotor.C1
								end
								-- Never retarget Part1 to the LIVE handle.
								if info.motor.Part1 ~= info.handle then
									info.motor.Part1 = info.handle
								end
								if not info.motor.Part0 then
									local gripName = handName == 'RightWeapon' and 'RightGrip' or 'LeftGrip'
									info.motor.Part0 = clone:FindFirstChild(gripName)
										or clone:FindFirstChild(handName == 'RightWeapon' and 'RightHand' or 'LeftHand')
								end
							end
						end
						local now = os.clock()
						if now - lastJointBreak > 0.25 then
							lastJointBreak = now
							breakExternalConstraints(clone, { weaponFolder })
						end
						if now - lastHumSanitize > 1 then
							lastHumSanitize = now
							sanitizeGhostPhysics(clone, { allowRoots = { weaponFolder } })
							if weaponFolder then
								sanitizeGhostPhysics(weaponFolder, { allowRoots = { clone } })
							end
						end
						if now - lastWeaponRefresh > 2 then
							lastWeaponRefresh = now
							items = items2
							pcall(refreshWeapons, live, items2)
						end
						-- Drive loco from REAL humanoid state (clone Humanoid never updates).
						local want = 'Idle'
						local speed = liveHrp.AssemblyLinearVelocity.Magnitude
						local stateId = liveHum and liveHum:GetState()
						if stateId == Enum.HumanoidStateType.Jumping then
							want = 'Jump'
						elseif stateId == Enum.HumanoidStateType.Freefall then
							want = 'Fall'
						elseif speed > 1.5 then
							want = 'Running'
						end
						if getgenv()._SB2AnimGhostWant ~= want then
							getgenv()._SB2AnimGhostWant = want
							playLoco(want, 0.12)
						end
					end)

					getgenv()._SB2AnimGhost = {
						clone = clone,
						real = real,
						hb = hb,
						played = playedConn,
						weaponFolder = weaponFolder,
						world = world,
						pack = packName,
					}
					return true
				end

				local function stopAnimSwap()
					clearGhost()
					getgenv()._SB2AnimGhostWant = nil
				end

				local function applyAnimSwap()
					if state.AnimEnabled ~= true or state.AnimPack == '(default)' or state.AnimPack == nil or state.AnimPack == '' then
						stopAnimSwap()
						return
					end
					if ANIM_PACK_BLOCKLIST[string.lower(tostring(state.AnimPack))] then
						Library:Notify(tostring(state.AnimPack) .. ' is not a locomotion pack', 4)
						state.AnimPack = '(default)'
						persistPrefs()
						stopAnimSwap()
						return
					end
					local ok = ensureGhost(state.AnimPack)
					if ok then
						Library:Notify('Client anim pack: ' .. tostring(state.AnimPack) .. ' (only you see it)', 4)
					end
				end

				getgenv().SB2AnimSwapStop = stopAnimSwap
				getgenv().SB2AnimSwapApply = applyAnimSwap

				-- Re-apply after respawn.
				pcall(function()
					local old = getgenv()._SB2AnimCharConn
					if old then
						old:Disconnect()
					end
				end)
				local lp = Players.LocalPlayer
				if lp then
					getgenv()._SB2AnimCharConn = lp.CharacterAdded:Connect(function()
						task.wait(1.2)
						if state.AnimEnabled == true then
							applyAnimSwap()
						end
					end)
				end

				WeaponModBox:AddLabel(
					'Animation swapper — loco packs + TeaCup (Unarmed walk + teacup swings). Client ghost; others keep normal anims.'
				)
				WeaponModBox:AddToggle('WeaponModAnimEnabled', {
					Text = 'Client anim pack',
					Default = state.AnimEnabled == true,
					Tooltip = 'Local-only clone with Idle/Run/Jump/Fall + remapped swings. No shop/remote.',
				}):OnChanged(function(on)
					state.AnimEnabled = on == true
					persistPrefs()
					if state.AnimEnabled then
						applyAnimSwap()
					else
						stopAnimSwap()
						Library:Notify('Client anim pack off', 3)
					end
				end)
				WeaponModBox:AddDropdown('WeaponModAnimPack', {
					Text = 'Anim pack',
					Values = animPackNames(),
					Default = (function()
						local cur = state.AnimPack or '(default)'
						if ANIM_PACK_BLOCKLIST[string.lower(tostring(cur))] then
							return '(default)'
						end
						return cur
					end)(),
					Tooltip = 'Locomotion packs (Reaper, Ninja, …) plus TeaCup. Dagger/Misc/SwordShield stay out.',
				}):OnChanged(function(v)
					state.AnimPack = flattenOpt(v) or '(default)'
					persistPrefs()
					if state.AnimEnabled == true then
						applyAnimSwap()
					end
				end)
				WeaponModBox:AddButton('Refresh anim pack list', function()
					local values = animPackNames()
					if Options.WeaponModAnimPack and Options.WeaponModAnimPack.SetValues then
						pcall(function()
							Options.WeaponModAnimPack:SetValues(values)
						end)
					end
					Library:Notify('Anim packs: ' .. tostring(#values - 1), 3)
				end)
				WeaponModBox:AddButton('Re-apply client anim', function()
					if state.AnimEnabled ~= true then
						Library:Notify('Enable Client anim pack first', 3)
						return
					end
					applyAnimSwap()
				end)

				-- Do NOT auto-spawn ghost after reload — that ragdolled on every soft load.
				-- Re-enable via the Client anim pack toggle or Re-apply button.
				task.defer(function()
					if state._AnimSkipAutoApply == true then
						state._AnimSkipAutoApply = nil
						state.AnimEnabled = false
						persistPrefs()
						if Options.WeaponModAnimEnabled
							and type(Options.WeaponModAnimEnabled.SetValue) == 'function'
						then
							pcall(function()
								Options.WeaponModAnimEnabled:SetValue(false)
							end)
						end
						return
					end
					if state.AnimEnabled == true and state.AnimPack and state.AnimPack ~= '(default)' then
						if ANIM_PACK_BLOCKLIST[string.lower(tostring(state.AnimPack))] then
							state.AnimPack = '(default)'
							persistPrefs()
							return
						end
						task.wait(1.25)
						if state.AnimEnabled == true then
							applyAnimSwap()
						end
					end
				end)
			end

			WeaponModBox:AddLabel('Client-only look for held swords (CharacterItems). Stats stay on the real equip. Overlay = capture a DIFFERENT sword first (Edit current = tint/scale this one).')
			WeaponModBox:AddToggle('WeaponModEnabled', {
				Text = 'Enable weapon modifier',
				Default = state.Enabled == true,
				Tooltip = 'Applies color / size / rotation / overlay to your held weapon model.',
			}):OnChanged(function(on)
				state.Enabled = on == true
				queueApply()
			end)
			WeaponModBox:AddDropdown('WeaponModTarget', {
				Text = 'Target hand',
				Values = { 'Right', 'Left', 'Both' },
				Default = state.Target or 'Right',
			}):OnChanged(function(v)
				state.Target = flattenOpt(v) or 'Right'
				queueApply()
			end)
			WeaponModBox:AddDropdown('WeaponModMode', {
				Text = 'Mode',
				Values = { 'Edit current', 'Overlay look' },
				Default = state.Mode or 'Edit current',
				Tooltip = 'Edit current = tint/scale the real mesh. Overlay look = hide it and show a captured weapon mesh.',
			}):OnChanged(function(v)
				state.Mode = flattenOpt(v) or 'Edit current'
				queueApply()
			end)
			WeaponModBox:AddDropdown('WeaponModLook', {
				Text = 'Overlay look',
				Values = lookDropdownValues(),
				Default = state.Look or '(none)',
				Tooltip = 'Capture an equipped sword first, then pick it here for Overlay mode.',
			}):OnChanged(function(v)
				state.Look = flattenOpt(v) or '(none)'
				queueApply()
			end)
			WeaponModBox:AddDropdown('WeaponModAnchor', {
				Text = 'Overlay anchor',
				Values = { 'Auto', 'Blade', 'Handle', 'Plane' },
				Default = state.Anchor or 'Auto',
				Tooltip = 'What the overlay welds to. Auto prefers Blade (hitbox) so visuals line up with the blue box.',
			}):OnChanged(function(v)
				state.Anchor = flattenOpt(v) or 'Auto'
				queueApply()
			end)
			WeaponModBox:AddButton('Capture equipped look', function()
				local name = captureEquippedLook()
				if not name then
					return
				end
				state.Look = name
				if Options.WeaponModLook and Options.WeaponModLook.SetValues then
					pcall(function()
						Options.WeaponModLook:SetValues(lookDropdownValues())
					end)
				end
				if Options.WeaponModLook and Options.WeaponModLook.SetValue then
					pcall(function()
						Options.WeaponModLook:SetValue(name)
					end)
				end
				Library:Notify('Captured look: ' .. name, 4)
				queueApply()
			end)
			WeaponModBox:AddButton('Apply now', function()
				applyAll()
				Library:Notify('Weapon modifier applied', 3)
			end)
			WeaponModBox:AddButton('Reset held visuals', function()
				hardResetHeldVisuals()
			end)

			WeaponModBox:AddToggle('WeaponModColorOn', {
				Text = 'Tint color',
				Default = state.ColorOn == true,
			}):OnChanged(function(on)
				state.ColorOn = on == true
				queueApply()
			end)
			WeaponModBox:AddSlider('WeaponModColorR', {
				Text = 'Tint R',
				Default = tonumber(state.ColorR) or 255,
				Min = 0,
				Max = 255,
				Rounding = 0,
			}):OnChanged(function(v)
				state.ColorR = v
				queueApply()
			end)
			WeaponModBox:AddSlider('WeaponModColorG', {
				Text = 'Tint G',
				Default = tonumber(state.ColorG) or 255,
				Min = 0,
				Max = 255,
				Rounding = 0,
			}):OnChanged(function(v)
				state.ColorG = v
				queueApply()
			end)
			WeaponModBox:AddSlider('WeaponModColorB', {
				Text = 'Tint B',
				Default = tonumber(state.ColorB) or 255,
				Min = 0,
				Max = 255,
				Rounding = 0,
			}):OnChanged(function(v)
				state.ColorB = v
				queueApply()
			end)

			WeaponModBox:AddSlider('WeaponModScale', {
				Text = 'Scale (uniform)',
				Default = tonumber(state.Scale) or 1,
				Min = 0.25,
				Max = 3,
				Rounding = 2,
			}):OnChanged(function(v)
				state.Scale = v
				queueApply()
			end)
			WeaponModBox:AddSlider('WeaponModScaleX', {
				Text = 'Scale X (shape)',
				Default = tonumber(state.ScaleX) or 1,
				Min = 0.25,
				Max = 3,
				Rounding = 2,
			}):OnChanged(function(v)
				state.ScaleX = v
				queueApply()
			end)
			WeaponModBox:AddSlider('WeaponModScaleY', {
				Text = 'Scale Y (shape)',
				Default = tonumber(state.ScaleY) or 1,
				Min = 0.25,
				Max = 3,
				Rounding = 2,
			}):OnChanged(function(v)
				state.ScaleY = v
				queueApply()
			end)
			WeaponModBox:AddSlider('WeaponModScaleZ', {
				Text = 'Scale Z (shape)',
				Default = tonumber(state.ScaleZ) or 1,
				Min = 0.25,
				Max = 3,
				Rounding = 2,
			}):OnChanged(function(v)
				state.ScaleZ = v
				queueApply()
			end)

			WeaponModBox:AddSlider('WeaponModRotX', {
				Text = 'Rotation X°',
				Default = tonumber(state.RotX) or 0,
				Min = -180,
				Max = 180,
				Rounding = 0,
			}):OnChanged(function(v)
				state.RotX = v
				queueApply()
			end)
			WeaponModBox:AddSlider('WeaponModRotY', {
				Text = 'Rotation Y°',
				Default = tonumber(state.RotY) or 0,
				Min = -180,
				Max = 180,
				Rounding = 0,
			}):OnChanged(function(v)
				state.RotY = v
				queueApply()
			end)
			WeaponModBox:AddSlider('WeaponModRotZ', {
				Text = 'Rotation Z°',
				Default = tonumber(state.RotZ) or 0,
				Min = -180,
				Max = 180,
				Rounding = 0,
			}):OnChanged(function(v)
				state.RotZ = v
				queueApply()
			end)

			WeaponModBox:AddSlider('WeaponModOffX', {
				Text = 'Align X',
				Default = tonumber(state.OffX) or 0,
				Min = -10,
				Max = 10,
				Rounding = 2,
			}):OnChanged(function(v)
				state.OffX = v
				queueApply()
			end)
			WeaponModBox:AddSlider('WeaponModOffY', {
				Text = 'Align Y',
				Default = tonumber(state.OffY) or 0,
				Min = -10,
				Max = 10,
				Rounding = 2,
			}):OnChanged(function(v)
				state.OffY = v
				queueApply()
			end)
			WeaponModBox:AddSlider('WeaponModOffZ', {
				Text = 'Align Z',
				Default = tonumber(state.OffZ) or 0,
				Min = -10,
				Max = 10,
				Rounding = 2,
			}):OnChanged(function(v)
				state.OffZ = v
				queueApply()
			end)

			WeaponModBox:AddSlider('WeaponModTransparency', {
				Text = 'Transparency',
				Default = tonumber(state.Transparency) or 0,
				Min = 0,
				Max = 1,
				Rounding = 2,
			}):OnChanged(function(v)
				state.Transparency = v
				queueApply()
			end)

			-- Re-apply after UI defaults settle if it was left enabled.
			task.defer(function()
				if state.Enabled == true then
					applyAll()
				end
			end)
		end

		-- Stations + remote upgrade (CardinalUI Upgrade remote / openUpgrade).
		local StationsBox = InvTab:AddLeftGroupbox('Stations')
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

		local UpgradeBox = InvTab:AddLeftGroupbox('Remote upgrade')
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

		local function getUpgradeItemQuery()
			local q = Options.RemoteUpgradeQuery and Options.RemoteUpgradeQuery.Value or ''
			if type(q) ~= 'string' then
				return ''
			end
			return (q:match('^%s*(.-)%s*$') or '')
		end

		local upgradeLabelMap = {} -- dropdown label -> item Name
		local upgradeLabels = {}
		local upgradeSearchToken = 0

		local function refreshUpgradeNameList(query, silent)
			table.clear(upgradeLabelMap)
			table.clear(upgradeLabels)
			query = string.lower(tostring(query or ''):gsub('^%s+', ''):gsub('%s+$', ''))
			local inv = getInventoryFolder()
			local best = {} -- name -> { rarity, upgrade, maxUp }
			if inv then
				for _, item in ipairs(inv:GetChildren()) do
					if query == '' or string.find(string.lower(item.Name), query, 1, true) then
						local okUp, rarity, upgrade, maxUp = canUpgradeItem(item)
						if okUp then
							local rec = best[item.Name]
							if not rec or upgrade < rec.upgrade then
								best[item.Name] = {
									rarity = rarity,
									upgrade = upgrade,
									maxUp = maxUp,
								}
							end
						end
					end
				end
			end
			local names = {}
			for name in pairs(best) do
				names[#names + 1] = name
			end
			table.sort(names)
			local cap = query == '' and 80 or 120
			for i, name in ipairs(names) do
				if i > cap then
					break
				end
				local rec = best[name]
				local label = ('%s  +%d/%d  %s'):format(
					name,
					rec.upgrade,
					rec.maxUp,
					tostring(rec.rarity or '')
				)
				upgradeLabelMap[label] = name
				upgradeLabels[#upgradeLabels + 1] = label
			end
			if Options.RemoteUpgradeItem then
				Options.RemoteUpgradeItem:SetValues(upgradeLabels)
				local cur = Options.RemoteUpgradeItem.Value
				if cur and not upgradeLabelMap[cur] then
					if #upgradeLabels == 1 then
						Options.RemoteUpgradeItem:SetValue(upgradeLabels[1])
					else
						Options.RemoteUpgradeItem:SetValue(nil)
					end
				elseif not cur and #upgradeLabels == 1 then
					Options.RemoteUpgradeItem:SetValue(upgradeLabels[1])
				end
			end
			if not silent then
				Library:Notify(('Upgrade matches: %d names'):format(#upgradeLabels))
			end
		end

		local function resolveRemoteUpgradeItem(preferUpgradable)
			local label = Options.RemoteUpgradeItem and Options.RemoteUpgradeItem.Value
			local nameOnly = label and upgradeLabelMap[label]
			if not nameOnly or nameOnly == '' then
				return nil
			end
			local inv = getInventoryFolder()
			if not inv then
				return nil
			end
			-- Exact name only — pick first upgradable copy (or any copy).
			for _, item in ipairs(inv:GetChildren()) do
				if item.Name == nameOnly then
					if preferUpgradable then
						if canUpgradeItem(item) then
							return item
						end
					else
						return item
					end
				end
			end
			if preferUpgradable then
				for _, item in ipairs(inv:GetChildren()) do
					if item.Name == nameOnly then
						return item
					end
				end
			end
			return nil
		end

		UpgradeBox:AddInput('RemoteUpgradeQuery', {
			Text = 'Name contains',
			Default = '',
			Placeholder = 'e.g. Alaric',
			Finished = false,
			ClearTextOnFocus = false,
			AllowEmpty = true,
			Tooltip = 'Filters the item dropdown — pick the full name there.',
			Callback = function(value)
				upgradeSearchToken += 1
				local token = upgradeSearchToken
				task.delay(0.12, function()
					if token == upgradeSearchToken then
						refreshUpgradeNameList(value, true)
					end
				end)
			end,
		})

		UpgradeBox:AddDropdown('RemoteUpgradeItem', {
			Text = 'Equipment',
			Values = {},
			Default = nil,
			AllowNull = true,
			Searchable = true,
			Tooltip = 'Pick the exact inventory item to upgrade.',
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

		UpgradeBox:AddButton('Refresh list', function()
			refreshUpgradeNameList(getUpgradeItemQuery(), false)
		end)

		task.defer(function()
			refreshUpgradeNameList('', true)
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

			local item = resolveRemoteUpgradeItem(true)
			if not item or not item.Parent then
				Library:Notify('Pick an equipment from the dropdown (search filter above)')
				refreshUpgradeNameList(getUpgradeItemQuery(), true)
				return
			end

			local okUp, rarity, upgrade, maxUp = canUpgradeItem(item)
			if not okUp then
				Library:Notify('That item cannot be upgraded further')
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

		local DismantleBox = InvTab:AddLeftGroupbox('Remote dismantle')
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
	end)()

	-- ── Items: snapshot Database.Items so a patch only shows NEW names ──
	-- Own function scope (not bare `do`) — outer UI chunk is near Luau's 200-register
	-- limit; sharing that budget made TagWiki/`okTag` fail to compile.
	;(function()
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
			-- Prefer Decal Icon (image). CashShop chests also have AssetId = product id.
			local icon = folder:FindFirstChild('Icon')
			if icon and icon:IsA('Decal') then
				local fromDecal = extractAssetId(icon.Texture)
				if fromDecal then
					return fromDecal
				end
			end
			local aid = folder:FindFirstChild('AssetId')
			if aid and aid:IsA('ValueBase') and tostring(aid.Value) ~= '' then
				return tostring(aid.Value)
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

		-- Standard 6-aura CashShop chests use fixed drop rates by display slot.
		local CHEST_SLOT_PROBS = {
			[6] = { '4%', '9%', '14%', '19%', '23%', '28%' },
		}

		local function wikiRarityTag(rarity)
			local r = tostring(rarity or ''):gsub('^%s+', ''):gsub('%s+$', '')
			if r == '' then
				return ''
			end
			if r == 'Uncomon' then
				r = 'Uncommon'
			end
			return '{{' .. r .. '}}'
		end

		local function readUiChestChances()
			local map = {}
			local ok, list = pcall(function()
				return game.Players.LocalPlayer.PlayerGui.CardinalUI.PlayerUI.MainFrame.TabFrames.CashShop.ChestDetails.List
			end)
			if not ok or not list then
				return map
			end
			for _, child in ipairs(list:GetChildren()) do
				if child:IsA('GuiObject') then
					local chance = child:FindFirstChild('Chance')
					if chance and (chance:IsA('TextLabel') or chance:IsA('TextButton')) then
						local txt = tostring(chance.Text or ''):gsub('^%s+', ''):gsub('%s+$', '')
						if txt ~= '' then
							map[child.Name] = txt
						end
					end
				end
			end
			return map
		end

		local function uiChancesMatchChest(rows, uiChances)
			if not uiChances or #rows == 0 then
				return false
			end
			for _, row in ipairs(rows) do
				if not uiChances[row.name] then
					return false
				end
			end
			return true
		end

		local function chanceForChestRow(row, total, uiChances)
			if uiChances and uiChances[row.name] then
				return uiChances[row.name]
			end
			local bySlot = CHEST_SLOT_PROBS[total]
			if bySlot and row.slot >= 1 and row.slot <= #bySlot then
				return bySlot[row.slot]
			end
			return ''
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
					local itemFolder = getItemFolder(child.Name)
					rows[#rows + 1] = {
						name = child.Name,
						slot = tonumber(child.Value) or 0,
						iconId = iconIdOf(itemFolder),
						rarity = tostring(valueOf(itemFolder, 'Rarity') or ''),
					}
				end
			end
			table.sort(rows, function(a, b)
				if a.slot ~= b.slot then
					return a.slot < b.slot
				end
				return a.name < b.name
			end)
			local uiChances = readUiChestChances()
			if not uiChancesMatchChest(rows, uiChances) then
				uiChances = nil
			end
			local total = #rows
			for _, row in ipairs(rows) do
				row.chance = chanceForChestRow(row, total, uiChances)
			end
			return rows
		end

		local function wikiCommaNumber(n)
			n = tonumber(n)
			if not n then
				return ''
			end
			local neg = n < 0
			n = math.floor(math.abs(n) + 0.5)
			local s = tostring(n)
			while true do
				local nextS, k = s:gsub('^(-?%d+)(%d%d%d)', '%1,%2')
				s = nextS
				if k == 0 then
					break
				end
			end
			return neg and ('-' .. s) or s
		end

		local function wikiNormRarity(rarity)
			local r = tostring(rarity or ''):gsub('^%s+', ''):gsub('%s+$', '')
			if r == 'Uncomon' then
				r = 'Uncommon'
			end
			return r
		end

		local function wikiRarityCategory(rarity)
			local r = wikiNormRarity(rarity)
			local map = {
				Tribute = 'Tributes',
				Legendary = 'Legendaries',
				Rare = 'Rares',
				Uncommon = 'Uncommons',
				Common = 'Commons',
				Exotic = 'Exotics',
			}
			return map[r] or (r ~= '' and (r .. 's') or 'Items')
		end

		local function wikiPctFromValue(v)
			local n = tonumber(v)
			if not n then
				return nil
			end
			-- Crit/buffs may be stored as 36 or 0.36.
			local pct = n
			if math.abs(n) <= 1.0001 then
				pct = n * 100
			end
			if math.abs(pct - math.floor(pct + 0.5)) < 0.05 then
				return math.floor(pct + 0.5)
			end
			return tonumber(string.format('%.1f', pct))
		end

		local function wikiWeaponTypeLabel(folder, stats)
			local classVal = tostring(valueOf(folder, 'Class') or '')
			local statsClass = tostring(stats and stats.Class or '')
			if classVal == '1HSword' then
				return statsClass ~= '' and ('1H ' .. statsClass) or '1H Sword'
			end
			if classVal == '2HSword' then
				return statsClass ~= '' and ('2H ' .. statsClass) or '2H Sword'
			end
			if statsClass ~= '' then
				return statsClass
			end
			if classVal ~= '' then
				return classVal
			end
			return 'Weapon'
		end

		local function wikiOverviewWeaponWord(folder, stats)
			local statsClass = tostring(stats and stats.Class or '')
			if statsClass ~= '' then
				return statsClass
			end
			local label = wikiWeaponTypeLabel(folder, stats)
			return label:gsub('^1H%s+', ''):gsub('^2H%s+', '')
		end

		local function wikiBuffAbilityLines(buffs)
			local rows = {}
			for bname, bval in pairs(buffs or {}) do
				rows[#rows + 1] = { bname, bval }
			end
			table.sort(rows, function(a, b)
				return a[1] < b[1]
			end)
			local healthPct = nil
			local staminaPct = nil
			local other = {}
			for _, row in ipairs(rows) do
				local key = row[1]
				local pct = wikiPctFromValue(row[2])
				if key == 'HealthRegeneration' then
					healthPct = pct
				elseif key == 'StaminaRegeneration' then
					staminaPct = pct
				elseif pct ~= nil then
					other[#other + 1] = { key = key, pct = pct }
				else
					other[#other + 1] = { key = key, raw = row[2] }
				end
			end
			local abilities = {}
			local prose = {}
			if healthPct ~= nil and staminaPct ~= nil and healthPct == staminaPct then
				-- Same % — one combined ability line (wiki style).
				abilities[#abilities + 1] = ('*+%s%%Health & Stamina Regeneration'):format(tostring(healthPct))
				prose[#prose + 1] = ('a %s%% buff to both Stamina and Health Regeneration'):format(tostring(healthPct))
			else
				if healthPct ~= nil then
					abilities[#abilities + 1] = ('*+%s%% Health Regeneration'):format(tostring(healthPct))
					prose[#prose + 1] = ('a %s%% buff to Health Regeneration'):format(tostring(healthPct))
				end
				if staminaPct ~= nil then
					abilities[#abilities + 1] = ('*+%s%% Stamina Regeneration'):format(tostring(staminaPct))
					prose[#prose + 1] = ('a %s%% buff to Stamina Regeneration'):format(tostring(staminaPct))
				end
			end
			for _, row in ipairs(other) do
				local label = prettyStatName(row.key)
				if row.pct ~= nil then
					abilities[#abilities + 1] = ('*+%s%% %s'):format(tostring(row.pct), label)
					prose[#prose + 1] = ('a %s%% buff to %s'):format(tostring(row.pct), label)
				else
					abilities[#abilities + 1] = ('*%s: %s'):format(label, tostring(row.raw))
					prose[#prose + 1] = ('%s (%s)'):format(label, tostring(row.raw))
				end
			end
			return abilities, prose
		end

		local function dumpWikiItem(name)
			local folder = getItemFolder(name)
			if not folder then
				return name .. '\n(not in Database.Items)'
			end
			local kind = itemKind(folder)
			local stats = readValueMap(folder:FindFirstChild('Stats'))
			local rarity = wikiNormRarity(valueOf(folder, 'Rarity'))
			local level = tonumber(valueOf(folder, 'Level')) or tonumber(stats.Level)
			local damage = tonumber(stats.Damage)
			if damage == nil then
				damage = tonumber(valueOf(folder, 'Damage'))
			end
			local crit = tonumber(stats.Critical)
			if crit == nil then
				crit = tonumber(valueOf(folder, 'Critical'))
			end
			local defense = tonumber(stats.Defense)
			if defense == nil then
				defense = tonumber(valueOf(folder, 'Defense'))
			end
			local buffs = readValueMap(folder:FindFirstChild('Buffs'))
			local typeLabel = wikiWeaponTypeLabel(folder, stats)
			if kind == 'Armor' then
				typeLabel = 'Armor'
			elseif kind == 'Shield' then
				typeLabel = 'Shield'
			elseif kind == 'Accessory' then
				typeLabel = 'Accessory'
			elseif kind == 'Aura' then
				typeLabel = 'Aura'
			end
			local overviewWord = wikiOverviewWeaponWord(folder, stats)
			if kind ~= 'Weapon' then
				overviewWord = typeLabel
			end

			local critPct = wikiPctFromValue(crit)
			local dmgText = damage and wikiCommaNumber(damage) or ''
			local upgDmgText = damage and wikiCommaNumber(damage * 2) or ''
			local abilities, buffProse = wikiBuffAbilityLines(buffs)
			local fileName = name .. '.png'

			local lines = {
				'{{ItemID}}',
				string.format(
					'{{Item infobox|name=%s|image=%s|type=%s|rarity=%s|level=%s|dmg=%s|crit=%s',
					name,
					fileName,
					typeLabel,
					rarity,
					level and tostring(level) or '',
					dmgText,
					critPct and (tostring(critPct) .. '%') or ''
				),
			}
			if #abilities == 0 then
				lines[#lines + 1] = '|abilities='
			elseif #abilities == 1 then
				-- Same-stat combined (or single buff): one |abilities= line.
				lines[#lines + 1] = '|abilities=' .. abilities[1]
			else
				-- Different stats: each ability on its own line so * bullets render.
				lines[#lines + 1] = '|abilities=' .. abilities[1]
				for i = 2, #abilities do
					lines[#lines + 1] = abilities[i]
				end
			end
			lines[#lines + 1] = '|obtain=[[]]'
			lines[#lines + 1] = '|image = <gallery>'
			lines[#lines + 1] = fileName .. ' | Icon'
			lines[#lines + 1] = ' | In-game'
			lines[#lines + 1] = ''
			lines[#lines + 1] = '</gallery>}}'
			lines[#lines + 1] = '==Overview=='

			local overview = ("'''{{PAGENAME}}''' is a %s"):format(wikiRarityTag(rarity))
			if level then
				overview = overview .. (' level %d'):format(level)
			end
			overview = overview .. (' %s, dropped by [[???]] in [[]].'):format(overviewWord)
			if critPct then
				overview = overview .. (' It has a %s%% critical chance'):format(tostring(critPct))
				if dmgText ~= '' then
					overview = overview .. (' and does %s damage.'):format(dmgText)
				else
					overview = overview .. '.'
				end
			elseif dmgText ~= '' then
				overview = overview .. (' It does %s damage.'):format(dmgText)
			end
			if dmgText ~= '' and upgDmgText ~= '' then
				overview = overview .. (' When upgraded to +20, it does %s damage.'):format(upgDmgText)
			end
			if #buffProse == 1 then
				overview = overview .. (' In addition, it grants the user %s.'):format(buffProse[1])
			elseif #buffProse > 1 then
				overview = overview
					.. (' In addition, it grants the user %s.'):format(table.concat(buffProse, ', '))
			end
			lines[#lines + 1] = overview
			lines[#lines + 1] = ''
			lines[#lines + 1] = "The drop rate for this item is '''???'''."
			lines[#lines + 1] = '[[Category:' .. wikiRarityCategory(rarity) .. ']]'
			return table.concat(lines, '\n')
		end

		local function dumpWikiChest(chestName)
			local shop = getCashShop()
			local folder = shop and shop:FindFirstChild(chestName)
			if not folder then
				return chestName .. '\n(not in Database.CashShop)'
			end
			local rows = readChestContents(folder)
			if #rows == 0 then
				return chestName .. '\n(no auras in Items folder)'
			end

			-- Wiki pages list auras alphabetically inside XnAurasBox.
			local wikiRows = {}
			for i, row in ipairs(rows) do
				wikiRows[i] = row
			end
			table.sort(wikiRows, function(a, b)
				return a.name < b.name
			end)

			local n = #wikiRows
			local lines = {}
			local price = valueOf(folder, 'Price')
			if price ~= nil and tostring(price) ~= '' then
				lines[#lines + 1] = ('**Chest Price: %s R$**'):format(tostring(price))
				lines[#lines + 1] = ''
			end
			lines[#lines + 1] = '{{X' .. n .. 'AurasBox'
			lines[#lines + 1] = '|chesticon= '
			lines[#lines + 1] = chestName .. '.png'
			for i, row in ipairs(wikiRows) do
				local rarityBit = wikiRarityTag(row.rarity)
				local prob = row.chance ~= '' and row.chance or '?'
				lines[#lines + 1] = string.format(
					'|icon%d=%s|name%d=%s|rarity%d=%s|prob%d=%s',
					i,
					row.name .. '.png',
					i,
					row.name,
					i,
					rarityBit,
					i,
					prob
				)
			end
			lines[#lines + 1] = '}}'
			return table.concat(lines, '\n')
		end

		local function dumpWikiChestPage(chestName)
			local shop = getCashShop()
			local folder = shop and shop:FindFirstChild(chestName)
			if not folder then
				return chestName .. '\n(not in Database.CashShop)'
			end
			local rows = readChestContents(folder)
			if #rows == 0 then
				return chestName .. '\n(no auras in Items folder)'
			end

			-- Gallery pages list auras reverse slot order (higher chance first).
			local wikiRows = {}
			for i, row in ipairs(rows) do
				wikiRows[i] = row
			end
			table.sort(wikiRows, function(a, b)
				if a.slot ~= b.slot then
					return a.slot > b.slot
				end
				return a.name < b.name
			end)

			local lines = {
				('[[File:%s.png|center|thumb]]'):format(chestName),
				'{| class="fandom-table" style="text-align:center;"',
				'!Aura',
				'!Image',
				'!In-game Effect',
			}
			for _, row in ipairs(wikiRows) do
				lines[#lines + 1] = '|-'
				lines[#lines + 1] = '{{Aura Gallery'
				lines[#lines + 1] = '| title = ' .. row.name
				lines[#lines + 1] = '| icon = ' .. row.name .. '.png'
				lines[#lines + 1] = '| image1 = '
				lines[#lines + 1] = '| image2 = '
				lines[#lines + 1] = '}}'
			end
			lines[#lines + 1] = '|}'
			lines[#lines + 1] = '==Trivia=='
			lines[#lines + 1] = ''
			lines[#lines + 1] = '[[Category:Burst Store]]'
			lines[#lines + 1] = '[[Category:Aura]]'
			lines[#lines + 1] = '[[Category:Accessory]]'
			lines[#lines + 1] = '[[Category:Robux]]'
			lines[#lines + 1] = '[[Category:Items]]'
			lines[#lines + 1] = '[[Category:Accessories]]'
			lines[#lines + 1] = '[[Category:Chest]]'
			lines[#lines + 1] = '[[Category:Event]]'
			lines[#lines + 1] = '[[Category:Event Aura]]'
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

		local WikiTab = Window:AddTab('Wiki', 'book')
		local wikiBoxes = {}
		local function hardenWikiBox(box)
			if type(box) ~= 'table' then
				return box
			end
			-- Obsidian bug: collapsed Holder can stay unclipped with Container still
			-- Visible, so sibling section content stacks on top of each other.
			pcall(function()
				if box.Holder and box.Holder:IsA('GuiObject') then
					box.Holder.ClipsDescendants = true
				end
			end)
			if not box._sb2CollapseHardened then
				box._sb2CollapseHardened = true
				local oldResize = box.Resize
				if type(oldResize) == 'function' then
					box.Resize = function(self, ...)
						local results = table.pack(oldResize(self, ...))
						pcall(function()
							if self.Container then
								self.Container.Visible = not self.Collapsed
							end
							if self.Holder and self.Holder:IsA('GuiObject') then
								self.Holder.ClipsDescendants = true
							end
						end)
						return table.unpack(results, 1, results.n)
					end
				end
				local oldSet = box.SetCollapsed
				if type(oldSet) == 'function' then
					box.SetCollapsed = function(self, collapsed, ...)
						local results = table.pack(oldSet(self, collapsed, ...))
						pcall(function()
							if self.Container then
								self.Container.Visible = not self.Collapsed
							end
							if self.Holder and self.Holder:IsA('GuiObject') then
								self.Holder.ClipsDescendants = true
							end
						end)
						return table.unpack(results, 1, results.n)
					end
				end
			end
			return box
		end
		local function registerWikiBox(box)
			box = hardenWikiBox(box)
			if type(box) == 'table' then
				wikiBoxes[#wikiBoxes + 1] = box
			end
			return box
		end
		local function wikiGroupbox(side, name)
			-- Build expanded first; collapse after all Wiki content exists.
			local box
			if side == 'right' then
				box = WikiTab:AddRightGroupbox(name)
			else
				box = WikiTab:AddLeftGroupbox(name)
			end
			return registerWikiBox(box)
		end
		local function collapseAllWikiBoxes()
			for _, box in ipairs(wikiBoxes) do
				pcall(function()
					hardenWikiBox(box)
					if type(box.SetCollapsed) == 'function' then
						box:SetCollapsed(true)
					else
						box.Collapsed = true
						if box.Container then
							box.Container.Visible = false
						end
						if type(box.Resize) == 'function' then
							box:Resize()
						end
					end
				end)
			end
			pcall(function()
				if type(WikiTab.RefreshSides) == 'function' then
					WikiTab:RefreshSides()
				end
			end)
		end
		local DiffBox = wikiGroupbox('left', 'New since snapshot')
		local SearchBox = wikiGroupbox('right', 'Search Database.Items')
		local ChestBox = wikiGroupbox('right', 'Aura chests')
		assert(DiffBox, 'Wiki groupbox nil')
		local ItemsTab = WikiTab -- TagWiki / older modules still expect ItemsTab

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

		DiffBox:AddButton('Copy IDs: all new', function()
			if #lastAdded == 0 then
				Library:Notify('No new names — Scan first')
				return
			end
			local ids = {}
			local missing = 0
			for _, name in ipairs(lastAdded) do
				local folder = getItemFolder(name)
				-- Prefer icon asset id (wiki); fall back to Database Items.ID.
				local id = iconIdOf(folder)
				if (not id or id == '') and folder then
					local raw = valueOf(folder, 'ID')
					if raw ~= nil and tostring(raw) ~= '' then
						id = tostring(raw)
					end
				end
				if id and tostring(id) ~= '' then
					ids[#ids + 1] = tostring(id)
				else
					missing += 1
				end
			end
			if #ids == 0 then
				Library:Notify('No IDs found on new items')
				return
			end
			if copyText(table.concat(ids, '\n')) then
				local msg = ('Copied %d IDs'):format(#ids)
				if missing > 0 then
					msg = msg .. (' (%d missing)'):format(missing)
				end
				Library:Notify(msg)
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

		local chestDetail = ChestBox:AddLabel('Scan to load robux shop aura chests.')
		local chestStatusLabel = ChestBox:AddLabel(' ')

		local function showChestDetail(name)
			if type(name) ~= 'string' or name == '' or name == NONE then
				setLabel(chestDetail, 'Scan to load robux shop aura chests.')
				return
			end
			local shop = getCashShop()
			local folder = shop and shop:FindFirstChild(name)
			local rows = readChestContents(folder)
			setLabel(chestDetail, ('%s — %d auras'):format(name, #rows))
		end

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
			if query == '' then
				for _, name in ipairs(allAuraChests) do
					hits[#hits + 1] = name
				end
			else
				for _, name in ipairs(allAuraChests) do
					if chestMatchesQuery(name, query) then
						hits[#hits + 1] = name
						if #hits >= 80 then
							break
						end
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
					setLabel(chestDetail, ('%d aura chests — pick one'):format(#hits))
				else
					setLabel(chestDetail, ('%d match "%s"'):format(#hits, query))
				end
			end
			setLabel(chestStatusLabel, ('Live %d aura chests in CashShop'):format(#allAuraChests))
		end

		local function refreshAuraChests(notify)
			allAuraChests = listAuraChests()
			applyChestSearch(currentChestQuery(), true)
			if #allAuraChests > 0 and (not Options.AuraChestList or not Options.AuraChestList.Value or Options.AuraChestList.Value == NONE) then
				pcall(function()
					Options.AuraChestList:SetValue(allAuraChests[1])
				end)
				showChestDetail(allAuraChests[1])
			end
			if notify then
				Library:Notify(('Scanned %d aura chests'):format(#allAuraChests))
			end
		end

		ChestBox:AddButton('Scan chests', function()
			refreshAuraChests(true)
		end)

		ChestBox:AddDropdown('AuraChestList', {
			Text = 'All aura chests',
			Values = { NONE },
			AllowNull = true,
			Searchable = true,
		}):OnChanged(function(name)
			showChestDetail(name)
		end)

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

		ChestBox:AddButton('Copy wiki: this chest', function()
			local name = Options.AuraChestList and Options.AuraChestList.Value
			if type(name) ~= 'string' or name == '' or name == NONE then
				Library:Notify('Pick an aura chest first')
				return
			end
			copyWiki(dumpWikiChest(name))
		end)

		ChestBox:AddButton('Chest page copy', function()
			local name = Options.AuraChestList and Options.AuraChestList.Value
			if type(name) ~= 'string' or name == '' or name == NONE then
				Library:Notify('Pick an aura chest first')
				return
			end
			copyWiki(dumpWikiChestPage(name))
		end)

		ChestBox:AddButton('Copy IDs: this chest', function()
			local name = Options.AuraChestList and Options.AuraChestList.Value
			if type(name) ~= 'string' or name == '' or name == NONE then
				Library:Notify('Pick an aura chest first')
				return
			end
			local shop = getCashShop()
			local folder = shop and shop:FindFirstChild(name)
			if not folder then
				Library:Notify('Chest not in CashShop')
				return
			end
			local lines = {}
			local chestIcon = iconIdOf(folder)
			lines[#lines + 1] = 'Chest icon: ' .. (chestIcon or '(missing)')
			local rows = readChestContents(folder)
			table.sort(rows, function(a, b)
				return a.name < b.name
			end)
			local found = chestIcon and 1 or 0
			for _, row in ipairs(rows) do
				local id = row.iconId
				if id and tostring(id) ~= '' then
					found += 1
					lines[#lines + 1] = row.name .. ': ' .. tostring(id)
				else
					lines[#lines + 1] = row.name .. ': (missing)'
				end
			end
			if found == 0 then
				Library:Notify('No icon IDs found on this chest')
				return
			end
			if copyText(table.concat(lines, '\n')) then
				Library:Notify(('Copied %d icon IDs'):format(found))
			else
				Library:Notify('Clipboard unavailable')
			end
		end)


		-- Cosmetic tags wiki (loaded module — Luau 200-local limit)
		local function loadTagWiki()
			local paths = { 'PlayerTools/TagWiki.lua', 'TagWiki.lua' }
			for _, p in ipairs(paths) do
				if type(readfile) == 'function' and type(isfile) == 'function' and isfile(p) then
					local okRead, src = pcall(readfile, p)
					if okRead and type(src) == 'string' and src ~= '' then
						local fn, err = (loadstring or load)(src, p)
						if fn then
							local okRun, result = pcall(fn)
							if okRun and type(result) == 'function' then
								return result
							end
						else
							warn('[TagWiki] compile failed: ', err)
						end
					end
				end
			end
			return nil
		end
		local tagInit = loadTagWiki()
		if tagInit then
			local okTag, tagErr = pcall(tagInit, {
				ensureItemsFolder = ensureItemsFolder,
				copyText = copyText,
				setLabel = setLabel,
				setDropdown = setDropdown,
				ItemsTab = ItemsTab,
				WikiTab = WikiTab,
				registerWikiBox = registerWikiBox,
				Library = Library,
				Options = Options,
				HttpService = HttpService,
				NONE = NONE,
				SEARCH_HINT = SEARCH_HINT,
				TAGS_KNOWN_PATH = TAGS_KNOWN_PATH,
				WIKI_TAGS_DUMP_PATH = WIKI_TAGS_DUMP_PATH,
				LocalPlayer = LocalPlayer,
			})
			if not okTag then
				warn('[TagWiki] init failed: ', tagErr)
				pcall(function()
					writefile('PlayerTools/_pt_load_err.txt', 'TagWiki init: ' .. tostring(tagErr))
				end)
			end
		end

		-- Titling: preview SpecialAlias / CosmeticTags on any nameplate
		local function loadTitling()
			local paths = { 'PlayerTools/Titling.lua', 'Titling.lua' }
			for _, p in ipairs(paths) do
				if type(readfile) == 'function' and type(isfile) == 'function' and isfile(p) then
					local okRead, src = pcall(readfile, p)
					if okRead and type(src) == 'string' and src ~= '' then
						local fn, err = (loadstring or load)(src, p)
						if fn then
							local okRun, result = pcall(fn)
							if okRun and type(result) == 'function' then
								return result
							end
						else
							warn('[Titling] compile failed: ', err)
						end
					end
				end
			end
			return nil
		end
		local titlingInit = loadTitling()
		if titlingInit then
			local okTitle, titleErr = pcall(titlingInit, {
				WikiTab = WikiTab,
				ItemsTab = ItemsTab,
				Library = Library,
				Options = Options,
				LocalPlayer = LocalPlayer,
				NONE = NONE,
				setDropdown = setDropdown,
				registerWikiBox = registerWikiBox,
			})
			if not okTitle then
				warn('[Titling] init failed: ', titleErr)
			end
		end

		-- Collapse after TagWiki + Titling finish so AbsoluteContentSize is final,
		-- then force Container.Visible sync (see hardenWikiBox).
		task.defer(function()
			task.wait(0.05)
			collapseAllWikiBoxes()
			task.wait(0.1)
			collapseAllWikiBoxes()
		end)

		-- Quiet baseline so the first Scan after a real patch is a real diff.
		task.defer(function()
			refreshAuraChests(false)
			local _, knownCount = loadKnownSet()
			if knownCount == 0 then
				runScan(false)
			else
				setLabel(statusLabel, ('Known snapshot: %d items. Scan after a drop.'):format(knownCount))
			end
		end)
	end)()

	-- ── HiveMind (multi-client commander via shared workspace files) ──
	-- Own function scope — same 200-register rule as Combat / Inventory / Items.
	;(function()
		local function loadHive()
			-- Reuse a live Hive across PlayerTools soft reloads — re-loadstring was
			-- spamming offline/online + zombie purge on every UI rebuild.
			local existing = getgenv().SB2Hive
			if type(existing) == 'table'
				and type(existing.start) == 'function'
				and type(existing.isAlive) == 'function'
				and existing.isAlive()
				and existing._orderRev == 6
			then
				return existing
			end
			pcall(function()
				local old = getgenv().SB2Hive
				if type(old) == 'table' and type(old.stop) == 'function' and old.isAlive and old.isAlive() then
					old.stop({ leave = false })
				end
			end)
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
			local hiveOptedIn = false
			if type(Hive.fileOptedIn) == 'function' then
				hiveOptedIn = Hive.fileOptedIn() == true
			end
			HiveBox:AddToggle('HiveEnabled', {
				Text = 'Join hive',
				Default = hiveOptedIn,
				Tooltip = 'Off until you turn it on. Heartbeat / orders only run while Join hive is on.',
			}):OnChanged(function(on)
				if type(Hive.writeOptedIn) == 'function' then
					Hive.writeOptedIn(on == true)
				end
				if on then
					pcall(function()
						Hive.start()
						if Hive.role == 'idle' then
							Hive.becomeWorker()
						end
					end)
				else
					pcall(function()
						Hive.stop({ leave = true })
					end)
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

			local webhookUrl, webhookOn, webhookPing = '', false, ''
			if type(Hive.getTributeWebhook) == 'function' then
				webhookUrl, webhookOn, webhookPing = Hive.getTributeWebhook()
			end
			local function readHiveOptString(name)
				local o = Options and Options[name]
				if type(o) ~= 'table' then
					return ''
				end
				local v = o.Value
				if type(v) == 'string' then
					return v
				end
				if type(v) == 'number' then
					return tostring(v)
				end
				-- Ataraxia stores toggles in Options too — never treat bool as a URL.
				return ''
			end
			HiveBox:AddLabel(
				'Tribute alerts are per Roblox account. Each person sets their own webhook + Discord ID (Developer Mode → Copy User ID).'
			)
			-- Input idx must differ from the toggle — Ataraxia also puts toggles in Options,
			-- so a shared name made Test webhook read Value==true ("need a url: true").
			HiveBox:AddInput('HiveTributeWebhookUrl', {
				Text = 'Your Discord webhook URL',
				Default = webhookUrl or '',
				Placeholder = 'https://discord.com/api/webhooks/...',
				Finished = false,
				ClearTextOnFocus = false,
				Callback = function(value)
					local on = Toggles.HiveTributeWebhook and Toggles.HiveTributeWebhook.Value
					local ping = readHiveOptString('HiveTributePing')
					if type(Hive.setTributeWebhook) == 'function' then
						Hive.setTributeWebhook(tostring(value or ''), on == true, tostring(ping or ''), { quiet = true })
					end
				end,
			})
			HiveBox:AddInput('HiveTributePing', {
				Text = 'Your Discord user ID (who to ping)',
				Default = webhookPing or '',
				Placeholder = 'numbers only — leave blank for no ping',
				Finished = false,
				ClearTextOnFocus = false,
				Callback = function(value)
					local on = Toggles.HiveTributeWebhook and Toggles.HiveTributeWebhook.Value
					local url = readHiveOptString('HiveTributeWebhookUrl')
					if type(Hive.setTributeWebhook) == 'function' then
						Hive.setTributeWebhook(tostring(url or ''), on == true, tostring(value or ''), { quiet = true })
					end
				end,
			})
			HiveBox:AddToggle('HiveTributeWebhook', {
				Text = 'Webhook: Tribute drops',
				Default = webhookOn == true,
				Tooltip = 'Posts when THIS Roblox account gets a Tribute. Config is per-userId under hive/.',
			}):OnChanged(function(on)
				local url = readHiveOptString('HiveTributeWebhookUrl')
				local ping = readHiveOptString('HiveTributePing')
				if type(Hive.setTributeWebhook) == 'function' then
					Hive.setTributeWebhook(tostring(url or ''), on == true, tostring(ping or ''))
				elseif type(Hive.setTributeWebhookEnabled) == 'function' then
					Hive.setTributeWebhookEnabled(on == true)
				end
			end)
			HiveBox:AddButton('Test webhook', function()
				local url = readHiveOptString('HiveTributeWebhookUrl')
				local ping = readHiveOptString('HiveTributePing')
				if type(Hive.testTributeWebhook) == 'function' then
					Hive.testTributeWebhook(tostring(url or ''), tostring(ping or ''))
				else
					Library:Notify('Reload HiveMind for test webhook')
				end
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
				local skill
				pcall(function()
					skill = flattenOptionValue(Options.SkillName and Options.SkillName.Value)
				end)
				Hive.issue('combat_on', { skill = skill })
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
			do
				local resumeDefault = false
				pcall(function()
					resumeDefault = Toggles.SoloCombatResume and Toggles.SoloCombatResume.Value == true
				end)
				OrdersBox:AddToggle('HiveResumeAll', {
					Text = 'Resume (all clients)',
					Default = resumeDefault,
					Tooltip = 'Turns Solo resume ON/OFF on every hive client (including this one).',
				}):OnChanged(function(value)
					pcall(function()
						if type(getgenv().SB2SetSoloResume) == 'function' then
							getgenv().SB2SetSoloResume(value == true)
						elseif Toggles.SoloCombatResume and Toggles.SoloCombatResume.SetValue then
							Toggles.SoloCombatResume:SetValue(value == true)
						end
					end)
					if value then
						Hive.issue('solo_resume', { on = true })
					else
						Hive.issue('solo_resume_off', { on = false })
					end
					refreshHiveLabels()
				end)

				local bossDefault = false
				pcall(function()
					bossDefault = Toggles.BossWaypointRoute and Toggles.BossWaypointRoute.Value == true
				end)
				OrdersBox:AddToggle('HiveBossRouteAll', {
					Text = 'Boss WP route (all clients)',
					Default = bossDefault,
					Tooltip = 'Turns Boss WP route ON/OFF on every hive client (including this one).',
				}):OnChanged(function(value)
					pcall(function()
						if type(getgenv().SB2SetBossWaypointRoute) == 'function' then
							getgenv().SB2SetBossWaypointRoute(value == true)
						else
							local t = Toggles.BossWaypointRoute
							if type(t) == 'table' and type(t.SetValue) == 'function' then
								if t.Value == value then
									t:SetValue(not value)
									task.wait()
								end
								t:SetValue(value == true)
							end
						end
					end)
					if value then
						Hive.issue('boss_route_on', {})
					else
						Hive.issue('boss_route_off', {})
					end
					refreshHiveLabels()
				end)
			end

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
				Default = false,
				Tooltip = 'Saved with your autoload profile — stays off after reinject if you leave it off.',
			}):OnChanged(function(on)
				Hive.setAcceptHiveTrades(on == true)
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
	end)()

	local Settings = Window:AddTab('Settings', 'settings')
	local Menu = Settings:AddLeftGroupbox('Script')

	pcall(function()
		local home = Library.Tabs and Library.Tabs.Home
		if home and type(home.Show) == 'function' then
			home:Show()
		end
		if type(repairObsidianTabCanvas) == 'function' then
			repairObsidianTabCanvas()
		end
	end)

	-- Home keybind vs AutoFarm (End).
	HomeBox:AddLabel('Menu keybind'):AddKeyPicker('MenuKeybind', { Default = 'Home', NoUI = true })
	Library.ToggleKeybind = Options.MenuKeybind

	HomeBox:AddButton('Hide menu (same as keybind)', function()
		if type(getgenv().SB2HidePlayerToolsMenu) == 'function' then
			getgenv().SB2HidePlayerToolsMenu()
		elseif type(Library.Toggle) == 'function' then
			Library:Toggle()
		end
	end)

	HomeBox:AddButton('Tile Roblox windows', function()
		if type(getgenv().SB2TileRobloxWindows) == 'function' then
			getgenv().SB2TileRobloxWindows()
		end
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

	local afkStatus = HomeBox:AddLabel(antiafkStatusText())
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

	HomeBox:AddToggle('AntiAFK', {
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

	HomeBox:AddToggle('HideGameplayPaused', {
		Text = 'Hide gameplay paused screen',
		Default = getgenv().SB2HideGameplayPaused ~= false,
		Tooltip = 'Hides Roblox streaming "Gameplay paused" overlay. Does not stop streaming itself — only the full-screen notice.',
	}):OnChanged(function(value)
		getgenv().SB2HideGameplayPaused = value == true
		if value then
			if type(getgenv().SB2HideGameplayPausedUi) == 'function' then
				getgenv().SB2HideGameplayPausedUi()
			end
		elseif type(getgenv().SB2SetGameplayPausedUi) == 'function' then
			getgenv().SB2SetGameplayPausedUi(true)
		end
	end)

	HomeBox:AddToggle('FarmFps', {
		Text = 'Farm FPS (potato graphics)',
		Default = getgenv().SB2FarmFpsOn ~= false,
		Tooltip = 'Quality 1 + no global shadows + no bloom/blur. Skill clone janitor always runs separately. Turn off on the main if you want pretty graphics.',
	}):OnChanged(function(value)
		if value then
			if type(getgenv().SB2StartFarmFps) == 'function' then
				getgenv().SB2StartFarmFps()
			else
				getgenv().SB2FarmFpsOn = true
			end
		elseif type(getgenv().SB2StopFarmFps) == 'function' then
			getgenv().SB2StopFarmFps()
		else
			getgenv().SB2FarmFpsOn = false
		end
	end)

	Menu:AddButton('Test notification', function()
		Library:Notify(
			table.concat({
				'Test notification',
				'White outline · flash · timer bar',
				'If you see this, toasts are working',
			}, '\n'),
			8,
			true
		)
	end)
	Menu:AddToggle('AutoSkipLoading', {
		Text = 'Rejoin if stuck loading',
		Default = LoadSkip.fileOn(),
		Tooltip = 'IY plugin StuckLoadRejoin.iy: if the session loading screen stays up >15s, hop back to this server. Same overlay checks as before. Keep Autoexecute on.',
	}):OnChanged(function(value)
		if LoadSkip.sync then
			LoadSkip.sync(value == true, true)
		else
			LoadSkip.writeFile(value == true)
			getgenv().SB2AutoSkipLoad = value == true
		end
	end)
	Menu:AddButton('Rejoin stuck loading now', function()
		if LoadSkip.overlayUp() then
			LoadSkip.rejoin('settings')
			Library:Notify('Rejoining via StuckLoadRejoin.iy — keep Autoexecute on.', 6)
		elseif getgenv().SB2StuckLoadIyOwner ~= true then
			Library:Notify('Install IY plugin StuckLoadRejoin.iy first', 5)
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
		if isToggleOn('ViewPlayerStream') then
			Toggles.ViewPlayerStream:SetValue(false)
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
		if type(getgenv().SB2WeaponModCleanup) == 'function' then
			pcall(getgenv().SB2WeaponModCleanup)
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
		disableObsidianUiAnimations()
		pcall(repairObsidianTabCanvas)
		if type(getgenv().SB2RefreshAllDropdownDisplays) == 'function' then
			task.defer(getgenv().SB2RefreshAllDropdownDisplays)
		end
	end)

	pcall(function()
		local smSource = httpGet(CONFIG.UIRepo .. 'addons/SaveManager.lua')
		-- Obsidian defers every control; a hitch can apply them late (or never),
		-- so the menu looks like the profile never loaded while combat keeps running.
		smSource = smSource:gsub(
			'task%.defer%(Parser%.Load, Option%.idx, Option%)',
			'Parser.Load(Option.idx, Option)'
		)
		-- Fallback if Obsidian reformats whitespace.
		if smSource:find('task.defer(Parser.Load', 1, true) then
			smSource = smSource:gsub(
				'task%.defer%s*%(%s*Parser%.Load%s*,%s*Option%.idx%s*,%s*Option%s*%)',
				'Parser.Load(Option.idx, Option)'
			)
		end
		local SaveManager = compile(smSource)()
		SaveManager:SetLibrary(Library)
		SaveManager:SetFolder(CONFIG.ConfigFolder)
		SaveManager:IgnoreThemeSettings()
		SaveManager:SetIgnoreIndexes({
			'AntiAFK',
			'AutoSkipLoading',
			'HiveEnabled',
			'HiveCommander',
			-- HiveAcceptTrades is profile-saved (was ignored → always Default=true after reinject).
			'HiveCrystalType',
			'HiveCrystalAmount',
			-- Owned by combat_prefs.json — survive profile switch / autoload.
			'DiveFarmHeight',
			'DiveFleeDepth',
			'DiveFleeDepthBoss',
			'SkillName',
			'SupportSkillName',
			'FarmSkillName',
			'FarmSupportSkillName',
			'FarmHealSkillName',
			'FarmMendSkillName',
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
		local lastProfileToggles = {}
		local lastProfileDropdowns = {}
		local PROFILE_SKIP = {
			AntiAFK = true,
			AutoSkipLoading = true,
			HiveEnabled = true,
			HiveCommander = true,
			HiveCrystalType = true,
			HiveCrystalAmount = true,
			-- combat_prefs.json owns these across profiles
			DiveFarmHeight = true,
			DiveFleeDepth = true,
			DiveFleeDepthBoss = true,
			SkillName = true,
			SupportSkillName = true,
			FarmSkillName = true,
			FarmSupportSkillName = true,
			FarmHealSkillName = true,
			FarmMendSkillName = true,
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
			local collectMap = getgenv().SB2CollectMultiSkillMap
			local syncOrder = getgenv().SB2SyncMultiSkillOrder
			local last = getgenv().SB2LastCombatOptions
			if type(last) == 'table' and (idx == 'SkillName' or idx == 'SupportSkillName') then
				local remembered = last[idx]
				if type(remembered) == 'table' and type(collectMap) == 'function' then
					local map = collectMap(remembered)
					if next(map) then
						return remembered
					end
				elseif type(remembered) == 'string' and remembered ~= '' then
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
			if opt.Multi and type(collectMap) == 'function' and type(syncOrder) == 'function' then
				local map = collectMap(value)
				if not next(map) then
					return nil
				end
				local orderKey = (idx == 'FarmSupportSkillName') and 'SB2FarmSupportSkillOrder'
					or 'SB2SupportSkillOrder'
				return syncOrder(orderKey, map)
			end
			return flattenOptionValue(value)
		end
		local function readCombatSkillsSidecar()
			if type(isfile) ~= 'function' or type(readfile) ~= 'function' then
				return nil
			end
			local merged = {}
			local function mergeFile(path)
				local ok, exists = pcall(isfile, path)
				if not ok or not exists then
					return
				end
				local okRead, body = pcall(readfile, path)
				if not okRead or type(body) ~= 'string' or body == '' then
					return
				end
				local okDecode, decoded = pcall(function()
					return HttpServiceSM:JSONDecode(body)
				end)
				if okDecode and type(decoded) == 'table' then
					for k, v in pairs(decoded) do
						merged[k] = v
					end
				end
			end
			-- Legacy file first, then combat_prefs overlays.
			mergeFile(COMBAT_SKILLS_PATH)
			mergeFile(COMBAT_PREFS_PATH)
			if not next(merged) then
				return nil
			end
			return merged
		end

		local function captureCombatPrefsFromUi()
			local data = {}
			for idx in pairs(COMBAT_PREFS_INDEXES) do
				local opt = Options and Options[idx]
				if type(opt) ~= 'table' then
					continue
				end
				if opt.Type == 'Slider' or (type(opt.Min) == 'number' and type(opt.Max) == 'number') then
					local n = tonumber(opt.Value)
					if n ~= nil then
						data[idx] = n
					end
				elseif opt.Multi then
					local collectMap = getgenv().SB2CollectMultiSkillMap
					local syncOrder = getgenv().SB2SyncMultiSkillOrder
					local map = type(collectMap) == 'function' and collectMap(opt.Value) or {}
					local orderKey = (idx == 'FarmSupportSkillName') and 'SB2FarmSupportSkillOrder'
						or 'SB2SupportSkillOrder'
					local order = type(syncOrder) == 'function' and syncOrder(orderKey, map) or {}
					data[idx] = order
					if idx == 'SupportSkillName' then
						data.SupportSkillOrder = order
					elseif idx == 'FarmSupportSkillName' then
						data.FarmSupportSkillOrder = order
					end
				else
					local flat = flattenOptionValue(opt.Value)
					if flat ~= nil and flat ~= '' then
						data[idx] = flat
					end
				end
			end
			return data
		end

		local function writeCombatSkillsSidecar(skill, support)
			if type(writefile) ~= 'function' then
				return
			end
			pcall(function()
				local data = captureCombatPrefsFromUi()
				if skill ~= nil then
					data.SkillName = skill
				end
				if support ~= nil then
					data.SupportSkillName = support
				end
				local encoded = HttpServiceSM:JSONEncode(data)
				writefile(COMBAT_PREFS_PATH, encoded)
				-- Keep legacy path in sync for older boot paths.
				writefile(
					COMBAT_SKILLS_PATH,
					HttpServiceSM:JSONEncode({
						SkillName = data.SkillName,
						SupportSkillName = data.SupportSkillName,
					})
				)
			end)
		end

		local function applyCombatPrefsFromSidecar()
			local sidecar = readCombatSkillsSidecar()
			if type(sidecar) ~= 'table' then
				return false
			end
			local wasLoading = getgenv().SB2ConfigLoading == true
			getgenv().SB2ConfigLoading = true
			local applied = {}
			for idx in pairs(COMBAT_PREFS_INDEXES) do
				local want = sidecar[idx]
				if want == nil then
					continue
				end
				local opt = Options and Options[idx]
				if type(opt) ~= 'table' or type(opt.SetValue) ~= 'function' then
					continue
				end
				if opt.Type == 'Slider' or (type(opt.Min) == 'number' and type(opt.Max) == 'number') then
					local n = tonumber(want)
					if n ~= nil then
						pcall(function()
							opt:SetValue(n)
						end)
						applied[idx] = n
					end
				else
					pcall(ensureDropdownHasValue, opt, want)
					applied[idx] = want
				end
			end
			if type(sidecar.SupportSkillOrder) == 'table' then
				getgenv().SB2SupportSkillOrder = sidecar.SupportSkillOrder
			end
			if type(sidecar.FarmSupportSkillOrder) == 'table' then
				getgenv().SB2FarmSupportSkillOrder = sidecar.FarmSupportSkillOrder
			end
			if sidecar.SkillName then
				lastCombatOptions.SkillName = sidecar.SkillName
				getgenv().SB2HonorSavedCombatSkill = true
				if sidecar.SkillName ~= '(none)' then
					getgenv().SB2UserPickedCombatSkill = true
				end
			end
			if sidecar.SupportSkillName ~= nil then
				lastCombatOptions.SupportSkillName = sidecar.SupportSkillName
			end
			getgenv().SB2LastCombatOptions = lastCombatOptions
			--#region agent log
			pcall(function()
				local line = HttpServiceSM:JSONEncode({
					sessionId = '7e9135',
					runId = 'flee-prefs',
					hypothesisId = 'H-apply',
					location = 'applyCombatPrefsFromSidecar',
					message = 'applied combat prefs',
					data = {
						fileFlee = sidecar.DiveFleeDepth,
						fileBoss = sidecar.DiveFleeDepthBoss,
						appliedFlee = applied.DiveFleeDepth,
						appliedBoss = applied.DiveFleeDepthBoss,
						liveFlee = Options.DiveFleeDepth and Options.DiveFleeDepth.Value,
						liveBoss = Options.DiveFleeDepthBoss and Options.DiveFleeDepthBoss.Value,
					},
					timestamp = math.floor(os.clock() * 1000),
				})
				if type(appendfile) == 'function' then
					appendfile('debug-7e9135.log', line .. '\n')
				end
			end)
			--#endregion
			if not wasLoading then
				getgenv().SB2ConfigLoading = false
			end
			return true
		end
		getgenv().SB2PersistCombatPrefs = function()
			-- Always force-save dive height/flee, even during autoload - otherwise OnChanged
			-- during SetValue is dropped and the next launch resets to slider Defaults.
			pcall(function()
				local data = readCombatSkillsSidecar() or {}
				for idx in pairs({
					DiveFarmHeight = true,
					DiveFleeDepth = true,
					DiveFleeDepthBoss = true,
				}) do
					local opt = Options and Options[idx]
					local n = opt and tonumber(opt.Value)
					if n ~= nil then
						data[idx] = n
					end
				end
				if type(writefile) == 'function' then
					writefile(COMBAT_PREFS_PATH, HttpServiceSM:JSONEncode(data))
				end
				--#region agent log
				pcall(function()
					local line = HttpServiceSM:JSONEncode({
						sessionId = '7e9135',
						runId = 'flee-prefs',
						hypothesisId = 'H-persist',
						location = 'SB2PersistCombatPrefs',
						message = 'force-saved dive prefs',
						data = {
							loading = getgenv().SB2ConfigLoading == true,
							DiveFleeDepth = data.DiveFleeDepth,
							DiveFleeDepthBoss = data.DiveFleeDepthBoss,
							DiveFarmHeight = data.DiveFarmHeight,
						},
						timestamp = math.floor(os.clock() * 1000),
					})
					if type(appendfile) == 'function' then
						appendfile('debug-7e9135.log', line .. '\n')
					end
				end)
				--#endregion
			end)
			if getgenv().SB2ConfigLoading then
				return
			end
			writeCombatSkillsSidecar(nil, nil)
		end
		getgenv().SB2ApplyCombatPrefs = applyCombatPrefsFromSidecar

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
			local isMulti = idx == 'SupportSkillName' or idx == 'FarmSupportSkillName'
			for _, obj in ipairs(objects) do
				if type(obj) == 'table' and obj.type == 'Dropdown' and obj.idx == idx then
					obj.value = value
					obj.multi = isMulti
					return
				end
			end
			objects[#objects + 1] = {
				type = 'Dropdown',
				idx = idx,
				value = value,
				multi = isMulti,
			}
		end
		local function ensureDropdownHasValue(opt, value)
			if type(opt) ~= 'table' or value == nil then
				return
			end
			local collectMap = getgenv().SB2CollectMultiSkillMap
			local syncOrder = getgenv().SB2SyncMultiSkillOrder
			if opt.Multi and type(collectMap) == 'function' then
				local map = collectMap(value)
				local values = opt.Values
				if type(values) == 'table' then
					local nextValues = {}
					local seen = {}
					for _, v in ipairs(values) do
						if v and not seen[v] then
							seen[v] = true
							nextValues[#nextValues + 1] = v
						end
					end
					for name in pairs(map) do
						if not seen[name] then
							seen[name] = true
							nextValues[#nextValues + 1] = name
						end
					end
					pcall(function()
						opt:SetValues(nextValues)
					end)
				end
				pcall(function()
					opt:SetValue(map)
				end)
				if type(syncOrder) == 'function' then
					local orderKey = (opt == Options.FarmSupportSkillName) and 'SB2FarmSupportSkillOrder'
						or 'SB2SupportSkillOrder'
					syncOrder(orderKey, map)
				end
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
		local function profileToggleTruthy(value)
			if value == true or value == 1 then
				return true
			end
			if type(value) == 'string' then
				local s = string.lower((value:gsub('%s+', '')))
				return s == 'true' or s == '1' or s == 'on' or s == 'yes'
			end
			return false
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
				if type(obj.idx) == 'string' and PROFILE_SKIP[obj.idx] then
					continue
				end
				if obj.type == 'Toggle' then
					local on = profileToggleTruthy(obj.value)
					lastProfileToggles[obj.idx] = on
					if obj.idx == 'SoloCombatResume' then
						lastSoloBlock.SoloCombatResume = on
					elseif obj.idx == 'AutoBlockJoin' then
						lastSoloBlock.AutoBlockJoin = on
					end
				elseif obj.type == 'Dropdown' then
					local flat = flattenOptionValue(obj.value)
					if flat ~= nil then
						lastProfileDropdowns[obj.idx] = flat
					end
					if obj.idx == 'SkillName' or obj.idx == 'SupportSkillName' or obj.idx == 'SoloResumeWaypoint' then
						if flat ~= nil then
							lastCombatOptions[obj.idx] = flat
						end
					end
				end
			end
			-- Sidecars are written on every Resume / Auto block toggle — they win over
			-- a stale autoload JSON until autosave catches up (and when Overwrite was skipped).
			local fileBlock = readAutoblockFileWanted()
			if fileBlock ~= nil then
				lastSoloBlock.AutoBlockJoin = fileBlock
				lastProfileToggles.AutoBlockJoin = fileBlock
			elseif lastSoloBlock.AutoBlockJoin == nil and lastProfileToggles.AutoBlockJoin ~= nil then
				lastSoloBlock.AutoBlockJoin = lastProfileToggles.AutoBlockJoin == true
			end
			local fileSolo = readSoloResumeFileWanted()
			if fileSolo ~= nil then
				lastSoloBlock.SoloCombatResume = fileSolo
				lastProfileToggles.SoloCombatResume = fileSolo
			elseif lastSoloBlock.SoloCombatResume == nil and lastProfileToggles.SoloCombatResume ~= nil then
				lastSoloBlock.SoloCombatResume = lastProfileToggles.SoloCombatResume == true
			elseif lastSoloBlock.SoloCombatResume == nil
				and type(lastCombatOptions.SoloResumeWaypoint) == 'string'
				and lastCombatOptions.SoloResumeWaypoint ~= ''
				and lastCombatOptions.SoloResumeWaypoint ~= '(none)'
			then
				-- Saved waypoint with no sidecar yet — assume Resume should come back on.
				lastSoloBlock.SoloCombatResume = true
				writeSoloResumeFile(true)
			end
			if lastSoloBlock.SoloCombatResume == true then
				writeSoloResumeFile(true)
			elseif lastSoloBlock.SoloCombatResume == false then
				writeSoloResumeFile(false)
			end
			if lastSoloBlock.AutoBlockJoin == true then
				if type(writefile) == 'function' then
					pcall(writefile, AUTOBLOCK_PATH, 'true')
				end
			elseif lastSoloBlock.AutoBlockJoin == false then
				if type(writefile) == 'function' then
					pcall(writefile, AUTOBLOCK_PATH, 'false')
				end
			end
			local sidecar = readCombatSkillsSidecar()
			if type(sidecar) == 'table' then
				-- Sidecar always wins for profile-independent skill picks.
				if sidecar.SkillName ~= nil then
					lastCombatOptions.SkillName = sidecar.SkillName
				end
				if sidecar.SupportSkillName ~= nil then
					lastCombatOptions.SupportSkillName = sidecar.SupportSkillName
				end
			end
			getgenv().SB2LastCombatOptions = lastCombatOptions
			getgenv().SB2LastSoloBlock = {
				SoloCombatResume = lastSoloBlock.SoloCombatResume,
				AutoBlockJoin = lastSoloBlock.AutoBlockJoin,
			}
			getgenv().SB2LastProfileToggles = lastProfileToggles
			getgenv().SB2LastProfileDropdowns = lastProfileDropdowns
			if lastSoloBlock.SoloCombatResume == true then
				getgenv().SB2StickyResumeWanted = true
				getgenv().SB2ForceResumeWanted = true
				getgenv().SB2ResumeGuardUntil = os.clock() + 45
			elseif lastSoloBlock.SoloCombatResume == false then
				getgenv().SB2StickyResumeWanted = false
				getgenv().SB2ForceResumeWanted = false
				getgenv().SB2ResumeGuardUntil = 0
			end
		end
		local function profileUiLooksWiped()
			local wantOn, nowOff = 0, 0
			for idx, want in pairs(lastProfileToggles) do
				if want == true then
					wantOn += 1
					local toggle = Toggles[idx]
					if type(toggle) == 'table' and toggle.Value ~= true then
						nowOff += 1
					end
				end
			end
			if wantOn < 3 then
				return false
			end
			return nowOff >= math.max(3, math.floor(wantOn * 0.6))
		end
		local function applySavedProfileUi(reason)
			if Library.Unloaded and getgenv().SB2PlayerToolsGui and getgenv().SB2PlayerToolsGui.Parent then
				Library.Unloaded = false
			end
			getgenv().SB2ConfigLoading = true
			for idx, want in pairs(lastProfileToggles) do
				local toggle = Toggles[idx]
				if type(toggle) ~= 'table' or type(toggle.SetValue) ~= 'function' then
					continue
				end
				if toggle.Value ~= want then
					pcall(function()
						toggle:SetValue(want == true)
					end)
				elseif want == true and type(toggle.Display) == 'function' then
					pcall(function()
						toggle:Display()
					end)
				end
			end
			for idx, value in pairs(lastProfileDropdowns) do
				if COMBAT_PREFS_INDEXES[idx] then
					continue
				end
				pcall(ensureDropdownHasValue, Options[idx], value)
			end
			pcall(applyCombatPrefsFromSidecar)
			task.delay(0.5, function()
				getgenv().SB2ConfigLoading = false
				pcall(applyCombatPrefsFromSidecar)
				if getgenv().SB2ResumeAfterConfig or lastSoloBlock.SoloCombatResume == true then
					getgenv().SB2ResumeAfterConfig = nil
					if not otherPlayersPresent() then
						setCombatTrio(true)
					else
						setCombatTrio(false)
					end
					-- Wait for Players list to populate — early empty list caused TP into crowded servers.
					task.delay(1.25, function()
						if lastSoloBlock.SoloCombatResume ~= true and not isToggleOn('SoloCombatResume') then
							return
						end
						local resumeFn = getgenv().SB2ResumeSoloCombat
						if type(resumeFn) == 'function' then
							pcall(resumeFn, 'profile', true)
						end
					end)
				end
			end)
			if reason then
				pcall(function()
					Library:Notify('Restored profile UI — ' .. tostring(reason), 5)
				end)
			end
		end
		getgenv().SB2ProfileUiLooksWiped = profileUiLooksWiped
		getgenv().SB2ReapplyProfileUi = applySavedProfileUi
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
			-- Skills / dive height / flee depth: always from combat_prefs sidecar.
			pcall(applyCombatPrefsFromSidecar)
			pcall(function()
				local skill = lastCombatOptions.SkillName
				if skill and Options.SkillName then
					getgenv().SB2HonorSavedCombatSkill = true
					if skill ~= '(none)' then
						getgenv().SB2UserPickedCombatSkill = true
					end
				end
			end)
			pcall(function()
				local wanted = soloWanted == true
					or lastProfileToggles.SoloCombatResume == true
					or lastSoloBlock.SoloCombatResume == true
					or readSoloResumeFileWanted() == true
					or getgenv().SB2StickyResumeWanted == true
					or getgenv().SB2ForceResumeWanted == true
				if wanted then
					soloWanted = true
					lastSoloBlock.SoloCombatResume = true
					getgenv().SB2StickyResumeWanted = true
					getgenv().SB2ForceResumeWanted = true
					getgenv().SB2ResumeAssertUntil = os.clock() + 180
					getgenv().SB2ResumeGuardUntil = os.clock() + 45
					-- Always SetValue(true) — do NOT only call AssertResumeOn.
					-- AssertResumeOn used to no-op when ConfigLoading was already false,
					-- which left Resume off after profile load.
					if Toggles.SoloCombatResume and type(Toggles.SoloCombatResume.SetValue) == 'function' then
						local t = Toggles.SoloCombatResume
						getgenv().SB2ConfigLoading = true
						pcall(function()
							t:SetValue(true)
						end)
						getgenv().SB2ConfigLoading = false
						writeSoloResumeFile(true)
					end
					if type(getgenv().SB2AssertResumeOn) == 'function' then
						pcall(getgenv().SB2AssertResumeOn, 'profile')
					end
				elseif soloWanted == false and Toggles.SoloCombatResume and type(Toggles.SoloCombatResume.SetValue) == 'function' then
					getgenv().SB2StickyResumeWanted = false
					getgenv().SB2ForceResumeWanted = false
					getgenv().SB2ResumeAssertUntil = 0
					getgenv().SB2ResumeGuardUntil = 0
					local t = Toggles.SoloCombatResume
					t:SetValue(false)
					writeSoloResumeFile(false)
				end
			end)
			pcall(function()
				if blockWanted ~= nil and Toggles.AutoBlockJoin and type(Toggles.AutoBlockJoin.SetValue) == 'function' then
					local t = Toggles.AutoBlockJoin
					getgenv().SB2ConfigLoading = true
					pcall(function()
						t:SetValue(blockWanted == true)
					end)
					getgenv().SB2ConfigLoading = false
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
			-- Resume toggle is not enough — also restore Auto skill / attack / Anchor
			-- when the server is solo. Never force combat on while strangers are here.
			if soloWanted == true then
				task.spawn(function()
					if otherPlayersPresent() then
						setCombatTrio(false)
						return
					end
					for _, name in ipairs({ 'AutoAttack', 'AutoSkill', 'CombatAnchor' }) do
						local want = lastProfileToggles[name]
						if want == nil then
							want = true
						end
						local toggle = Toggles[name]
						if want == true and type(toggle) == 'table' and type(toggle.SetValue) == 'function' then
							pcall(function()
								if toggle.Value == true then
									toggle:SetValue(false)
									task.wait()
								end
								toggle:SetValue(true)
							end)
						end
					end
					setCombatTrio(true)
				end)
				if getgenv().SB2ConfigLoading then
					getgenv().SB2ResumeAfterConfig = true
				else
					if otherPlayersPresent() then
						setCombatTrio(false)
					else
						setCombatTrio(true)
					end
					task.delay(1.25, function()
						local resumeFn = getgenv().SB2ResumeSoloCombat
						if type(resumeFn) == 'function' then
							pcall(resumeFn, 'profile', true)
						end
					end)
				end
			end
		end
		local function scheduleSoloBlockApply()
			local function run()
				applySavedProfileUi()
				applySoloBlockFromProfile()
				pcall(applyCombatPrefsFromSidecar)
			end
			task.defer(run)
			task.delay(0.15, run)
			task.delay(0.5, run)
			task.delay(1.25, run)
			task.delay(2.5, function()
				getgenv().SB2ConfigLoading = false
				run()
				if lastSoloBlock.SoloCombatResume == true then
					getgenv().SB2ResumeAfterConfig = nil
					if otherPlayersPresent() then
						setCombatTrio(false)
					else
						setCombatTrio(true)
					end
					task.delay(1.0, function()
						local resumeFn = getgenv().SB2ResumeSoloCombat
						if type(resumeFn) == 'function' then
							pcall(resumeFn, 'profile', true)
						end
					end)
				end
			end)
			-- Late SaveManager / join-disable races: assert combat + TP again after settle.
			task.delay(4, function()
				if lastSoloBlock.SoloCombatResume == true or isToggleOn('SoloCombatResume') then
					pcall(function()
						local t = Toggles.SoloCombatResume
						if type(t) == 'table' and type(t.SetValue) == 'function' and t.Value ~= true then
							t:SetValue(true)
							writeSoloResumeFile(true)
						end
					end)
					if otherPlayersPresent() then
						setCombatTrio(false)
					else
						setCombatTrio(true)
					end
					local resumeFn = getgenv().SB2ResumeSoloCombat
					if type(resumeFn) == 'function' then
						pcall(resumeFn, 'settle4', true)
					end
				end
			end)
			task.delay(6, function()
				if lastSoloBlock.SoloCombatResume == true or lastProfileToggles.SoloCombatResume == true then
					pcall(function()
						local t = Toggles.SoloCombatResume
						if type(t) == 'table' and type(t.SetValue) == 'function' and t.Value ~= true then
							getgenv().SB2ConfigLoading = true
							t:SetValue(true)
							getgenv().SB2ConfigLoading = false
							writeSoloResumeFile(true)
						end
					end)
					if otherPlayersPresent() then
						setCombatTrio(false)
					else
						setCombatTrio(true)
					end
					local resumeFn = getgenv().SB2ResumeSoloCombat
					if type(resumeFn) == 'function' then
						pcall(resumeFn, 'settle6', true)
					end
				end
			end)
			-- Keep hammering Resume ON — SaveManager can paint Default=false late.
			task.spawn(function()
				local deadline = os.clock() + 45
				while os.clock() < deadline and getgenv()[CONFIG.GenvKey] do
					if getgenv().SB2StickyResumeWanted == true
						or getgenv().SB2ForceResumeWanted == true
						or lastSoloBlock.SoloCombatResume == true
						or lastProfileToggles.SoloCombatResume == true
					then
						local t = Toggles.SoloCombatResume
						if type(t) == 'table' and type(t.SetValue) == 'function' and t.Value ~= true then
							getgenv().SB2ConfigLoading = true
							pcall(function()
								t:SetValue(true)
							end)
							getgenv().SB2ConfigLoading = false
							writeSoloResumeFile(true)
							if not otherPlayersPresent() then
								setCombatTrio(true)
							end
						end
					end
					task.wait(0.35)
				end
			end)
		end
		getgenv().SB2ApplySoloBlockFromProfile = applySoloBlockFromProfile

		getgenv().SB2RefreshPlayerTools = function()
			getgenv().SB2ConfigLoading = false
			getgenv().SB2SoloBlockProfileReady = true
			if getgenv().SB2PlayerToolsManualUnload == true then
				return
			end
			if type(repairObsidianTabCanvas) == 'function' then
				pcall(repairObsidianTabCanvas)
			end
			local gui = getgenv().SB2PlayerToolsGui or (Library and Library.ScreenGui)
			if typeof(gui) == 'Instance' and not gui.Parent then
				-- Hard reparent (no protect_gui) — same hosts as ensurePlayerToolsGuiParent.
				pcall(function()
					local host = nil
					if type(gethui) == 'function' then
						local okH, h = pcall(gethui)
						if okH then
							host = h
						end
					end
					local cg = game:FindService('CoreGui') or game:GetService('CoreGui')
					gui.Parent = host or cg or (cg and cg:FindFirstChild('RobloxGui'))
					gui.Enabled = true
				end)
				if not gui.Parent then
					pcall(ensurePlayerToolsGuiParent, gui)
				end
			end
			gui = getgenv().SB2PlayerToolsGui or (Library and Library.ScreenGui)
			if typeof(gui) ~= 'Instance' or not gui.Parent then
				-- Do NOT clear the session flag here — that made floor hops look like
				-- an unload. Ask the keeper / next execute for a full rebuild.
				warn('[PlayerTools] refresh: UI not parented — will rebuild on next keeper tick')
				pcall(function()
					game:GetService('StarterGui'):SetCore('SendNotification', {
						Title = 'PlayerTools',
						Text = 'UI detaching after floor hop — recovering…',
						Duration = 5,
					})
				end)
				return
			end
			getgenv().SB2PlayerTools = true
			getgenv().SB2PlayerToolsGui = gui
			Library.ScreenGui = gui
			if getgenv().SB2PlayerToolsLibrary == nil then
				getgenv().SB2PlayerToolsLibrary = Library
			end
			pcall(function()
				getgenv().SB2MenuHopGraceUntil = os.clock() + 25
				getgenv().SB2UiKeeperQuietUntil = os.clock() + 25
				getgenv().SB2MenuWantOpen = true
				getgenv().SB2UiOrphanFails = 0
				forceShowWindow(true)
			end)
			if type(getgenv().SB2RefreshAllDropdownDisplays) == 'function' then
				pcall(getgenv().SB2RefreshAllDropdownDisplays)
			end
			pcall(function()
				local keep = getgenv().SB2PlayerToolsGui
				local libGui = Library and Library.ScreenGui
				local function sweep(parent)
					if not parent then
						return
					end
					for _, gui in ipairs(parent:GetChildren()) do
						if gui:IsA('ScreenGui') and gui ~= keep and gui ~= libGui then
							if gui:GetAttribute('SB2PlayerTools') == true or gui.Name == 'SB2PlayerTools' then
								pcall(function()
									gui:Destroy()
								end)
							end
						end
					end
				end
				local lp = game:GetService('Players').LocalPlayer
				if lp then
					sweep(lp:FindFirstChild('PlayerGui'))
				end
				sweep(game:GetService('CoreGui'))
				if type(gethui) == 'function' then
					sweep(gethui())
				end
			end)
			-- Re-read autoload JSON on refresh — previously skipped Load and left Resume off.
			pcall(function()
				local name = select(1, SaveManager:GetAutoloadConfig())
				name = trimConfigName(name)
				if name == '' or name == 'none' or not configExists(name) then
					local shared = joinPath(joinPath(CONFIG.ConfigFolder, 'settings'), 'autoload.txt')
					if type(isfile) == 'function' and isfile(shared) then
						local okShared, bodyShared = pcall(readfile, shared)
						if okShared then
							name = trimConfigName(bodyShared)
						end
					end
				end
				if name ~= '' and name ~= 'none' and configExists(name) then
					local path = autoloadConfigJsonPath(name)
					local okRead, body = pcall(readfile, path)
					if okRead and type(body) == 'string' then
						getgenv().SB2ConfigLoading = true
						rememberSoloBlockFromJSON(body)
						getgenv().SB2ConfigLoading = false
					end
				end
			end)
			pcall(applySoloBlockFromProfile)
			if lastSoloBlock.SoloCombatResume == true or getgenv().SB2StickyResumeWanted == true then
				getgenv().SB2StickyResumeWanted = true
				getgenv().SB2ForceResumeWanted = true
				getgenv().SB2ResumeGuardUntil = os.clock() + 45
				pcall(function()
					local t = Toggles.SoloCombatResume
					if type(t) == 'table' and type(t.SetValue) == 'function' then
						getgenv().SB2ConfigLoading = true
						t:SetValue(true)
						getgenv().SB2ConfigLoading = false
						writeSoloResumeFile(true)
					end
				end)
				if otherPlayersPresent() then
					setCombatTrio(false)
				else
					setCombatTrio(true)
				end
			end
			local blockWanted = lastSoloBlock.AutoBlockJoin
			if blockWanted == nil then
				blockWanted = readAutoblockFileWanted()
			end
			if blockWanted == true then
				getgenv().SB2AutoBlockWanted = true
				pcall(function()
					local t = Toggles.AutoBlockJoin
					if type(t) == 'table' and type(t.SetValue) == 'function' then
						t:SetValue(true)
					end
				end)
				if type(getgenv().SB2SetAutoBlock) == 'function' then
					pcall(getgenv().SB2SetAutoBlock, true)
				end
				if type(getgenv().SB2ArmAutoBlockTimers) == 'function' then
					pcall(getgenv().SB2ArmAutoBlockTimers, 0)
				end
			end
			pcall(function()
				Library:Notify('PlayerTools refreshed — same menu, auto-block re-armed', 5)
			end)
			pcall(function()
				game:GetService('StarterGui'):SetCore('SendNotification', {
					Title = 'Player Tools',
					Text = 'Refreshed — no new menu. Home still toggles.',
					Duration = 6,
				})
			end)
		end

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
				if profileUiLooksWiped() then
					for _, obj in ipairs(decoded.objects) do
						if type(obj) ~= 'table' or type(obj.idx) ~= 'string' then
							continue
						end
						if obj.type == 'Toggle' and lastProfileToggles[obj.idx] ~= nil then
							obj.value = lastProfileToggles[obj.idx] == true
						elseif obj.type == 'Dropdown' and lastProfileDropdowns[obj.idx] ~= nil then
							obj.value = lastProfileDropdowns[obj.idx]
						end
					end
				end
				local solo = readToggleWanted('SoloCombatResume')
				local block = readToggleWanted('AutoBlockJoin')
				local wp = readDropdownWanted('SoloResumeWaypoint')
				if profileUiLooksWiped() then
					if lastProfileToggles.SoloCombatResume ~= nil then
						solo = lastProfileToggles.SoloCombatResume == true
					end
					if lastProfileToggles.AutoBlockJoin ~= nil then
						block = lastProfileToggles.AutoBlockJoin == true
					end
					if lastProfileDropdowns.SoloResumeWaypoint then
						wp = lastProfileDropdowns.SoloResumeWaypoint
					end
				end
				upsertToggleInObjects(decoded.objects, 'SoloCombatResume', solo)
				upsertToggleInObjects(decoded.objects, 'AutoBlockJoin', block)
				upsertDropdownInObjects(decoded.objects, 'SoloResumeWaypoint', wp)
				do
					local kept = {}
					for _, obj in ipairs(decoded.objects) do
						if type(obj) == 'table' and type(obj.idx) == 'string' and COMBAT_PREFS_INDEXES[obj.idx] then
							continue
						end
						kept[#kept + 1] = obj
					end
					decoded.objects = kept
				end
				lastSoloBlock.SoloCombatResume = solo
				lastSoloBlock.AutoBlockJoin = block
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
				writeCombatSkillsSidecar(nil, nil)
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
					local wp = readDropdownWanted('SoloResumeWaypoint')
					if profileUiLooksWiped() then
						if lastProfileToggles.SoloCombatResume ~= nil then
							solo = lastProfileToggles.SoloCombatResume == true
						end
						if lastProfileToggles.AutoBlockJoin ~= nil then
							block = lastProfileToggles.AutoBlockJoin == true
						end
						if lastProfileDropdowns.SoloResumeWaypoint then
							wp = lastProfileDropdowns.SoloResumeWaypoint
						end
						for _, obj in ipairs(decoded.objects) do
							if type(obj) ~= 'table' or type(obj.idx) ~= 'string' then
								continue
							end
							if COMBAT_PREFS_INDEXES[obj.idx] then
								continue
							end
							if obj.type == 'Toggle' and lastProfileToggles[obj.idx] ~= nil then
								obj.value = lastProfileToggles[obj.idx] == true
							elseif obj.type == 'Dropdown' and lastProfileDropdowns[obj.idx] ~= nil then
								obj.value = lastProfileDropdowns[obj.idx]
							end
						end
					end
					upsertToggleInObjects(decoded.objects, 'SoloCombatResume', solo)
					upsertToggleInObjects(decoded.objects, 'AutoBlockJoin', block)
					upsertDropdownInObjects(decoded.objects, 'SoloResumeWaypoint', wp)
					do
						local kept = {}
						for _, obj in ipairs(decoded.objects) do
							if type(obj) == 'table' and type(obj.idx) == 'string' and COMBAT_PREFS_INDEXES[obj.idx] then
								continue
							end
							kept[#kept + 1] = obj
						end
						decoded.objects = kept
					end
					pcall(writefile, AUTOBLOCK_PATH, block and 'true' or 'false')
					writeSoloResumeFile(solo)
					writeCombatSkillsSidecar(nil, nil)
					local okEncode, patched = pcall(function()
						return HttpServiceSM:JSONEncode(decoded)
					end)
					if okEncode and type(patched) == 'string' then
						pcall(writefile, path, patched)
					end
					lastSoloBlock.SoloCombatResume = solo
					lastSoloBlock.AutoBlockJoin = block
					lastCombatOptions.SoloResumeWaypoint = wp
					pcall(function()
						Library:Notify(
							('Saved %q (solo=%s block=%s; skills/height in combat_prefs)'):format(
								name,
								tostring(solo),
								tostring(block)
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
				pcall(applyCombatPrefsFromSidecar)
				-- Direct assert after Parser.Load — do not rely only on deferred apply.
				if lastSoloBlock.SoloCombatResume == true then
					getgenv().SB2StickyResumeWanted = true
					getgenv().SB2ForceResumeWanted = true
					getgenv().SB2ResumeGuardUntil = os.clock() + 45
					pcall(function()
						local t = Toggles.SoloCombatResume
						if type(t) == 'table' and type(t.SetValue) == 'function' then
							t:SetValue(true)
							writeSoloResumeFile(true)
						end
					end)
				end
				scheduleSoloBlockApply()
				return okLoad, errLoad
			end
		end

		-- Some Obsidian builds load via LoadConfig / Load without LoadJSON.
		if type(SaveManager.LoadConfig) == 'function' then
			local origLoadConfig = SaveManager.LoadConfig
			SaveManager.LoadConfig = function(self, configName, ...)
				local name = trimConfigName(configName)
				local path = autoloadConfigJsonPath(name)
				if type(readfile) == 'function' and type(isfile) == 'function' then
					local okExists, exists = pcall(isfile, path)
					if okExists and exists then
						local okRead, body = pcall(readfile, path)
						if okRead and type(body) == 'string' then
							getgenv().SB2ConfigLoading = true
							rememberSoloBlockFromJSON(body)
						end
					end
				end
				local okLoad, errLoad = origLoadConfig(self, configName, ...)
				pcall(applyCombatPrefsFromSidecar)
				scheduleSoloBlockApply()
				return okLoad, errLoad
			end
		end

		SaveManager:BuildConfigSection(Settings)
		Settings:AddLabel('Autoload is per account. Profiles are shared — Set as autoload only changes this client.')
		Settings:AddLabel('Autosave: toggles you flip are written to your autoload profile (debounced). No need to smash Overwrite after every change.')
		Settings:AddLabel('Resume / Auto block also use sidecars. Farm height, flee depth, and skills save in combat_prefs.json (survive profile switch).')

		do
			local UpdateBox = Settings:AddRightGroupbox('GitHub updates')
			UpdateBox:AddLabel('Neuublue-style feed from NickB926/playertools. Friends run bootstrap once; Check/Apply pulls new files.')
			local updateStatus = UpdateBox:AddLabel('Update: not checked')
			local function setUpdateLabel(text)
				pcall(function()
					if updateStatus.SetText then
						updateStatus:SetText(text)
					elseif updateStatus.Text ~= nil then
						updateStatus.Text = text
					end
				end)
			end
			local function loadUpdater()
				if type(getgenv().SB2PlayerToolsUpdater) == 'table' then
					return getgenv().SB2PlayerToolsUpdater
				end
				if type(readfile) == 'function' and type(isfile) == 'function' and isfile('PlayerTools/Updater.lua') then
					local ok, src = pcall(readfile, 'PlayerTools/Updater.lua')
					if ok and type(src) == 'string' then
						local fn = (loadstring or load)(src, 'PlayerTools/Updater.lua')
						if fn then
							local okRun, result = pcall(fn)
							if okRun and type(result) == 'table' then
								return result
							end
						end
					end
				end
				return nil
			end
			UpdateBox:AddButton('Check for updates', function()
				local U = loadUpdater()
				if not U or type(U.check) ~= 'function' then
					Library:Notify('Updater.lua missing — run bootstrap or publish first', 6)
					return
				end
				local info = U.check()
				if not info or not info.ok then
					setUpdateLabel('Update: check failed — ' .. tostring(info and info.error))
					Library:Notify('Update check failed (repo private/offline?)', 6)
					return
				end
				if info.needsUpdate then
					setUpdateLabel(('Update: %s → %s available'):format(tostring(info.localVersion), tostring(info.remoteVersion)))
					Library:Notify(('Update available: %s'):format(tostring(info.remoteVersion)), 6)
				else
					setUpdateLabel(('Update: on %s (latest)'):format(tostring(info.remoteVersion)))
					Library:Notify('Already up to date', 4)
				end
			end)
			UpdateBox:AddButton('Apply update now', function()
				local U = loadUpdater()
				if not U or type(U.apply) ~= 'function' then
					Library:Notify('Updater.lua missing', 5)
					return
				end
				task.spawn(function()
					local ok = U.apply({
						force = true,
						notify = function(msg)
							Library:Notify(tostring(msg), 5)
							setUpdateLabel(tostring(msg))
						end,
					})
					if ok then
						Library:Notify('Update applied — reload PlayerTools', 7)
					end
				end)
			end)
		end
		SaveManager:LoadAutoloadConfig()

		-- Hard guarantee: resolve autoload name, re-apply JSON (esp. Resume), even if
		-- SaveManager skipped LoadJSON or painted Default=false after.
		local function resolveAutoloadName()
			local name = select(1, SaveManager:GetAutoloadConfig())
			name = trimConfigName(name)
			if name ~= '' and name ~= 'none' and configExists(name) then
				return name
			end
			-- Fall back to shared settings/autoload.txt
			if type(readfile) == 'function' and type(isfile) == 'function' then
				local shared = joinPath(joinPath(CONFIG.ConfigFolder, 'settings'), 'autoload.txt')
				local okExists, exists = pcall(isfile, shared)
				if okExists and exists then
					local okRead, body = pcall(readfile, shared)
					if okRead then
						name = trimConfigName(body)
						if name ~= '' and name ~= 'none' and configExists(name) then
							return name
						end
					end
				end
			end
			return nil
		end

		local function forceAutoloadProfile(reason)
			local name = resolveAutoloadName()
			if not name then
				return false
			end
			local path = autoloadConfigJsonPath(name)
			if type(readfile) ~= 'function' or not isfile(path) then
				return false
			end
			local okRead, body = pcall(readfile, path)
			if not okRead or type(body) ~= 'string' then
				return false
			end
			-- Do NOT call LoadConfig/LoadJSON again — that re-races Default=false after
			-- LoadAutoloadConfig already painted. Only remember + assert Resume/block.
			getgenv().SB2ConfigLoading = true
			rememberSoloBlockFromJSON(body)
			scheduleSoloBlockApply()
			if lastSoloBlock.SoloCombatResume == true or lastProfileToggles.SoloCombatResume == true then
				getgenv().SB2StickyResumeWanted = true
				getgenv().SB2ForceResumeWanted = true
				getgenv().SB2ResumeAssertUntil = os.clock() + 180
				getgenv().SB2ResumeGuardUntil = getgenv().SB2ResumeAssertUntil
				pcall(function()
					local t = Toggles.SoloCombatResume
					if type(t) == 'table' and type(t.SetValue) == 'function' then
						getgenv().SB2ConfigLoading = true
						t:SetValue(true)
						getgenv().SB2ConfigLoading = false
						writeSoloResumeFile(true)
					end
				end)
				if type(getgenv().SB2AssertResumeOn) == 'function' then
					pcall(getgenv().SB2AssertResumeOn, reason or 'autoload')
				end
				if otherPlayersPresent() then
					setCombatTrio(false)
				else
					setCombatTrio(true)
				end
				task.delay(1.0, function()
					local resumeFn = getgenv().SB2ResumeSoloCombat
					if type(resumeFn) == 'function' then
						pcall(resumeFn, reason or 'autoload', true)
					end
				end)
			end
			getgenv().SB2ConfigLoading = false
			getgenv().SB2ConfigLoadingSince = 0
			if reason == 'boot' then
				pcall(function()
					Library:Notify(
						('Autoload %s — Resume %s (ui=%s)'):format(
							name,
							tostring(lastSoloBlock.SoloCombatResume == true),
							tostring(Toggles.SoloCombatResume and Toggles.SoloCombatResume.Value == true)
						),
						5
					)
				end)
			end
			return true
		end

		pcall(forceAutoloadProfile, 'boot')
		task.defer(function()
			forceAutoloadProfile('defer')
		end)
		task.delay(0.75, function()
			forceAutoloadProfile('delay075')
		end)
		task.delay(2.0, function()
			forceAutoloadProfile('delay2')
		end)
		task.delay(5.0, function()
			forceAutoloadProfile('delay5')
		end)
		task.delay(12.0, function()
			forceAutoloadProfile('delay12')
		end)
		task.delay(20.0, function()
			if type(getgenv().SB2AssertResumeOn) == 'function' then
				pcall(getgenv().SB2AssertResumeOn, 'delay20')
			end
		end)

		-- Per-account profile + debounced autosave so OFF stays OFF after reinject.
		do
			local autosaveEnabled = false
			local autosaveToken = 0
			local lastAutosaveAt = 0
			local hookedAutosave = false

			local function defaultAccountProfileName()
				return 'account_' .. autoloadAccountKey()
			end

			local function ensureAccountAutoload()
				local name = resolveAutoloadName()
				if name then
					return name
				end
				local key = defaultAccountProfileName()
				getgenv().SB2ConfigLoading = true
				pcall(function()
					SaveManager:Save(key)
				end)
				pcall(function()
					SaveManager:SaveAutoloadConfig(key)
				end)
				getgenv().SB2ConfigLoading = false
				return key
			end

			local function runAutosave(reason)
				if getgenv().SB2ConfigLoading == true then
					return false
				end
				if getgenv().SB2PlayerToolsManualUnload == true then
					return false
				end
				local name = ensureAccountAutoload()
				if not name or name == '' or name == 'none' then
					return false
				end
				local okSave = false
				pcall(function()
					okSave = SaveManager:Save(name) == true
				end)
				if okSave then
					lastAutosaveAt = os.clock()
					-- Keep in-memory last toggles aligned with what we just wrote.
					pcall(function()
						for idx, toggle in pairs(Toggles or {}) do
							if type(idx) == 'string' and type(toggle) == 'table' and not PROFILE_SKIP[idx] then
								lastProfileToggles[idx] = toggle.Value == true
							end
						end
					end)
				end
				return okSave
			end

			local function scheduleAutosave(reason)
				if not autosaveEnabled then
					return
				end
				if getgenv().SB2ConfigLoading == true then
					return
				end
				autosaveToken += 1
				local token = autosaveToken
				task.delay(1.4, function()
					if token ~= autosaveToken then
						return
					end
					if getgenv().SB2ConfigLoading == true then
						return
					end
					pcall(runAutosave, reason or 'change')
				end)
			end

			getgenv().SB2ScheduleProfileAutosave = scheduleAutosave
			getgenv().SB2EnsureAccountAutoload = ensureAccountAutoload

			local function hookAutosaveListeners()
				if hookedAutosave then
					return
				end
				hookedAutosave = true
				pcall(function()
					for idx, toggle in pairs(Toggles or {}) do
						if type(toggle) == 'table' and type(toggle.OnChanged) == 'function' then
							toggle:OnChanged(function()
								scheduleAutosave('toggle:' .. tostring(idx))
							end)
						end
					end
				end)
				pcall(function()
					for idx, opt in pairs(Options or {}) do
						if type(idx) == 'string' and string.find(idx, 'SaveManager', 1, true) then
							continue
						end
						if type(opt) == 'table' and type(opt.OnChanged) == 'function' then
							opt:OnChanged(function()
								scheduleAutosave('option:' .. tostring(idx))
							end)
						end
					end
				end)
			end

			-- After boot settle: create account profile if missing, then arm autosave.
			task.delay(3.5, function()
				pcall(ensureAccountAutoload)
				autosaveEnabled = true
				hookAutosaveListeners()
			end)
			-- Catch late-created toggles (hive/orders etc.).
			task.delay(8, function()
				hookedAutosave = false
				hookAutosaveListeners()
			end)
		end

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
		if type(getgenv().SB2ApplyCombatPrefs) == 'function' then
			pcall(getgenv().SB2ApplyCombatPrefs)
		end
		-- Do not force-prefer weapon skill over a just-loaded profile skill.
		if not getgenv().SB2HonorSavedCombatSkill and type(getgenv().SB2PreferWeaponCombatSkill) == 'function' then
			pcall(getgenv().SB2PreferWeaponCombatSkill, false)
		end
	end)
	task.delay(0.15, function()
		if type(getgenv().SB2ApplyCombatPrefs) == 'function' then
			pcall(getgenv().SB2ApplyCombatPrefs)
		end
		if not getgenv().SB2HonorSavedCombatSkill and type(getgenv().SB2PreferWeaponCombatSkill) == 'function' then
			pcall(getgenv().SB2PreferWeaponCombatSkill, false)
		end
	end)
	task.delay(0.75, function()
		if type(getgenv().SB2ApplyCombatPrefs) == 'function' then
			pcall(getgenv().SB2ApplyCombatPrefs)
		end
		if not getgenv().SB2HonorSavedCombatSkill and type(getgenv().SB2PreferWeaponCombatSkill) == 'function' then
			pcall(getgenv().SB2PreferWeaponCombatSkill, false)
		end
	end)
	task.delay(2.0, function()
		if type(getgenv().SB2ApplyCombatPrefs) == 'function' then
			pcall(getgenv().SB2ApplyCombatPrefs)
		end
	end)
	task.delay(1.0, function()
		if type(getgenv().SB2ApplySoloBlockFromProfile) == 'function' then
			getgenv().SB2ApplySoloBlockFromProfile()
		end
	end)
	task.defer(function()
		task.wait(2.5)
		local fsf = getgenv().SB2FreshServerFinder
		if type(fsf) ~= 'table' or fsf.active ~= true then
			return
		end
		local tickFn = getgenv().SB2FreshServerFinderTick
		if type(tickFn) == 'function' then
			pcall(tickFn)
		end
	end)

	-- Custom Cardinal chat focuses on click, but `/` is eaten by TextChatService
	-- (Roblox's hidden chat bar). Steal focus back onto the in-game box.
	;(function()
		local UIS = game:GetService('UserInputService')
		local PlayersSvc = game:GetService('Players')
		local prev = getgenv().SB2ChatSlashFixConn
		if prev then
			pcall(function()
				prev:Disconnect()
			end)
		end

		local function findCardinalChatBox()
			local lp = PlayersSvc.LocalPlayer
			local pg = lp and lp:FindFirstChild('PlayerGui')
			if not pg then
				return nil
			end
			local chat = nil
			local cardinal = pg:FindFirstChild('CardinalUI')
			local playerUI = cardinal and cardinal:FindFirstChild('PlayerUI')
			chat = playerUI and playerUI:FindFirstChild('Chat')
			if not chat then
				local ok, found = pcall(function()
					return pg:FindFirstChild('Chat', true)
				end)
				if ok then
					chat = found
				end
			end
			if not chat then
				return nil
			end
			local fallback = nil
			for _, d in ipairs(chat:GetDescendants()) do
				if d:IsA('TextBox') then
					local ph = string.lower(tostring(d.PlaceholderText or ''))
					if ph:find('chat', 1, true) or ph:find('message', 1, true) then
						return d
					end
					fallback = fallback or d
				end
			end
			return fallback
		end

		local function isRobloxChatBox(box)
			if not box then
				return false
			end
			local core = box:FindFirstAncestorOfClass('CoreGui')
			if not core then
				return false
			end
			local n = string.lower(box.Name .. ' ' .. tostring(box.PlaceholderText or ''))
			if n:find('chat', 1, true) or n:find('experience', 1, true) then
				return true
			end
			local p = box.Parent
			while p and p ~= core do
				local pn = string.lower(p.Name)
				if pn:find('chat', 1, true) or pn:find('experiencechat', 1, true) then
					return true
				end
				p = p.Parent
			end
			return false
		end

		pcall(function()
			local tcs = game:GetService('TextChatService')
			local cfg = tcs:FindFirstChildOfClass('ChatInputBarConfiguration')
			if cfg then
				-- Keep TCS channels for send; just stop `/` opening the hidden bar.
				if cfg.KeyboardKeyCode ~= nil then
					cfg.KeyboardKeyCode = Enum.KeyCode.Unknown
				end
			end
		end)

		getgenv().SB2ChatSlashFixConn = UIS.InputBegan:Connect(function(input)
			if getgenv().SB2ChatSlashFix == false then
				return
			end
			if input.UserInputType ~= Enum.UserInputType.Keyboard then
				return
			end
			if input.KeyCode ~= Enum.KeyCode.Slash then
				return
			end
			task.defer(function()
				task.wait()
				local box = findCardinalChatBox()
				if not box then
					return
				end
				local focused = UIS:GetFocusedTextBox()
				if focused == box then
					return
				end
				if focused and not isRobloxChatBox(focused) then
					-- IY / Starlight / inventory search — leave it.
					return
				end
				pcall(function()
					box:CaptureFocus()
				end)
			end)
		end)
	end)()

	if not getgenv().SB2PlayerToolsLoadedNotify then
		getgenv().SB2PlayerToolsLoadedNotify = true
		task.delay(26, function()
			if getgenv().SB2PlayerTools == true then
				warn('[PlayerTools] loaded (Home toggles menu)')
			end
			getgenv().SB2PlayerToolsLoadedNotify = nil
		end)
	end
end)

getgenv().SB2PlayerToolsLoading = false

if not ok then
	getgenv()[CONFIG.GenvKey] = false
	getgenv()[LIBRARY_KEY] = nil
	getgenv().SB2PlayerToolsLoading = false
	getgenv().SB2PlayerToolsInstance = nil
	pcall(function()
		writefile('PlayerTools/_mcp_status.txt', 'PlayerTools FAILED: ' .. tostring(err))
	end)
	notify('Player Tools FAILED', tostring(err))
else
	-- Floor hops / soft-refresh races were clearing SB2PlayerTools while the
	-- ScreenGui stayed alive — that kills the reparent watchdog. Re-assert.
	if not getgenv().SB2PlayerToolsManualUnload then
		getgenv()[CONFIG.GenvKey] = true
		if getgenv()[LIBRARY_KEY] == nil and type(getgenv().Library) == 'table' then
			getgenv()[LIBRARY_KEY] = getgenv().Library
		end
		getgenv().SB2UiKeeperQuietUntil = os.clock() + 25
	end
	pcall(function()
		writefile('PlayerTools/_mcp_status.txt', 'PlayerTools OK')
	end)
end
-- SB2_PLAYERTOOLS_EOF
