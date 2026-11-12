--[[
	AutoBetween — friend installer (one file).
	Run this once in your executor. It writes everything AutoBetween needs into
	workspace/PlayerTools/ and starts it. After that it reloads itself after
	teleports (Between runs) from workspace/PlayerTools/AutoBetween.lua.

	Your own alts: put their names (one per line) in workspace/PlayerTools/whitelist.txt,
	otherwise AutoBetween waits while they are in the server.
]]
if not game:IsLoaded() then game.Loaded:Wait() end
if type(writefile) ~= 'function' or type(readfile) ~= 'function' then
	error('[AutoBetween] your executor needs writefile/readfile')
end
pcall(makefolder, 'PlayerTools')
local FILES = {}
FILES['AutoBetween.lua'] = [=[
--[[
	AutoBetween.lua — standalone Between auto-runner.
	  • Creates the Between party and starts a run as soon as possible (any floor / lobby),
	    chains the next run when one ends, restarts after a wipe.
	  • PlayerTools' auto dodge (AutoFloorDodge.lua).
	  • Whitelist: while a player who is not on the whitelist (built-in list + whitelist.txt)
	    is in the server, it starts nothing and the dodge stays off.
	  • Pyrixl only: sends the mod command ResetMobs;@all by itself on the thunder (Tempest)
	    wave, the Rift wave, the Bob wave, the Wisp wave and on Rubricatus (see "Auto ResetMobs" below).
	Needs in workspace/PlayerTools: AtaraxiaLibrary.lua, BetweenParty.lua, AutoFloorDodge.lua.
	Autoload: autoexec/02_autobetween.lua (every account except NickB926, which runs PlayerTools).
]]

local BUILD = 'auto-between-v14'
local G = getgenv()
local compile = loadstring or load

if not game:IsLoaded() then
	game.Loaded:Wait()
end
local Players = game:GetService('Players')
local RunService = game:GetService('RunService')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local HttpService = game:GetService('HttpService')
local LocalPlayer = Players.LocalPlayer
while not LocalPlayer do
	task.wait()
	LocalPlayer = Players.LocalPlayer
end

-- Never beside PlayerTools (it has its own copies of all of this).
do
	local ptGui = G.SB2PlayerToolsGui
	if (typeof(ptGui) == 'Instance' and ptGui.Parent ~= nil) or G.SB2PlayerToolsLoading == true then
		warn('[AutoBetween] PlayerTools is running on this account — not loading')
		return
	end
end

-- Reload: tear the previous copy down first.
if type(G.SB2AutoBetweenUnload) == 'function' then
	pcall(G.SB2AutoBetweenUnload)
end
G.SB2AutoBetweenLoaded = true
G.SB2AutoBetweenBuild = BUILD

-- Per-account files (several accounts share this PC's workspace).
local ACCT = string.lower(tostring(LocalPlayer.Name)):gsub('[^%w_]', '')
G.SB2AcctFileTag = ACCT
local SETTINGS_PATH = 'PlayerTools/autobetween_' .. ACCT .. '.json'

local function readJson(path)
	local ok, data = pcall(function()
		return HttpService:JSONDecode(readfile(path))
	end)
	return ok and type(data) == 'table' and data or nil
end
local settings = readJson(SETTINGS_PATH) or {}
if settings.autoStart == nil then
	settings.autoStart = true
end
if type(settings.difficulty) ~= 'string' then
	settings.difficulty = 'Auto'
end
if settings.autoload == nil then
	settings.autoload = true
end
local function saveSettings()
	pcall(writefile, SETTINGS_PATH, HttpService:JSONEncode(settings))
end
saveSettings()

local conns = {}
local function track(c)
	conns[#conns + 1] = c
	return c
end
local alive = true

---------------------------------------------------------------------------
-- Whitelist (same rules as PlayerTools: built-in UserIds + PlayerTools/whitelist.txt)
---------------------------------------------------------------------------
local isOwnAlt, listStrangers
do
	local BUILTIN_WHITELIST = {
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
		[1099119770] = true, -- aormai
		[9551801] = true, -- GreyGhosta
	}

	local extra = {}
	local pending = {}
	local function isOwnAltId(uid)
		uid = tonumber(uid)
		return uid ~= nil and (BUILTIN_WHITELIST[uid] == true or extra[uid] == true)
	end
	G.SB2IsOwnAltId = isOwnAltId
	function isOwnAlt(plr)
		if not plr then
			return false
		end
		if plr == LocalPlayer then
			return true
		end
		if isOwnAltId(plr.UserId) then
			return true
		end
		local stub = string.lower(tostring(plr.Name)):match('^roblox_user_(%d+)$')
		return stub ~= nil and isOwnAltId(tonumber(stub))
	end
	G.SB2IsOwnAlt = isOwnAlt
	local function addToken(token)
		token = tostring(token or ''):gsub('^%s+', ''):gsub('%s+$', ''):gsub('^@', '')
		if token == '' then
			return
		end
		local id = tonumber(token)
		if id then
			extra[id] = true
			return
		end
		for _, plr in ipairs(Players:GetPlayers()) do
			if string.lower(plr.Name) == string.lower(token) or string.lower(plr.DisplayName) == string.lower(token) then
				extra[plr.UserId] = true
				return
			end
		end
		local ok, uid = pcall(function()
			return Players:GetUserIdFromNameAsync(token)
		end)
		if ok and tonumber(uid) then
			extra[tonumber(uid)] = true
		else
			pending[string.lower(token)] = true
		end
	end
	task.spawn(function()
		local ok, body = pcall(readfile, 'PlayerTools/whitelist.txt')
		if not ok or type(body) ~= 'string' then
			return
		end
		body = body:gsub('\0', '')
		if body:byte(1) == 239 then
			body = body:sub(4)
		end
		for raw in body:gmatch('[^\r\n]+') do
			local line = raw:gsub('#.*', ''):gsub('^%s+', ''):gsub('%s+$', '')
			if line ~= '' then
				for token in line:gmatch('[^,;%s]+') do
					addToken(token)
				end
			end
		end
	end)
	track(Players.PlayerAdded:Connect(function(plr)
		if pending[string.lower(plr.Name)] or pending[string.lower(plr.DisplayName)] then
			extra[plr.UserId] = true
		end
	end))
	function listStrangers()
		local out = {}
		for _, plr in ipairs(Players:GetPlayers()) do
			if not isOwnAlt(plr) then
				out[#out + 1] = plr
			end
		end
		return out
	end
	G.SB2ListStrangerPlayers = listStrangers
	G.SB2OtherPlayersPresent = function()
		return #listStrangers() > 0
	end
end

---------------------------------------------------------------------------
-- Character helpers the dodge expects from PlayerTools (trimmed versions)
---------------------------------------------------------------------------
local function getMyCharacterModel()
	return LocalPlayer.Character
end
local function getMyBringPart()
	local c = LocalPlayer.Character
	return c and (c:FindFirstChild('HumanoidRootPart') or c:FindFirstChild('UpperTorso'))
end
local function isLocalAlive()
	local c = LocalPlayer.Character
	local h = c and c:FindFirstChildOfClass('Humanoid')
	return h ~= nil and h.Health > 0
end
local Library -- set below
local function isToggleOn(name)
	local t = Library and Library.Toggles and Library.Toggles[name]
	return type(t) == 'table' and t.Value == true
end

G.SB2WaveDefensePlace = tostring(game.PlaceId) == '121252145396212'
G.SB2SetAnchorLockCF = function() end
G.SB2BeginAnchorReplicate = function() end

do
	-- Hover hold: a zero LinearVelocity on the root cancels gravity while the dodge has you in the air.
	pcall(function()
		if type(G.SB2NoCollideStop) == 'function' then
			G.SB2NoCollideStop()
		end
	end)
	pcall(function()
		if G.SB2DiveLinVel then
			G.SB2DiveLinVel:Destroy()
		end
	end)
	local lv = Instance.new('LinearVelocity')
	lv.Name = 'SB2DiveLinVel'
	lv.MaxForce = 1e5
	lv.VectorVelocity = Vector3.zero
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	G.SB2DiveLinVel = lv
	G.SB2DiveEnsureFlyAttachment = function(hrp)
		if not hrp then
			return nil
		end
		local att = hrp:FindFirstChild('SB2FlyAtt')
		if not att then
			att = Instance.new('Attachment')
			att.Name = 'SB2FlyAtt'
			att.Parent = hrp
		end
		return att
	end
	G.SB2DiveBlinkTeleport = function(hrp, dest, lookAt)
		if not hrp or not hrp.Parent or typeof(dest) ~= 'Vector3' then
			return false
		end
		pcall(function()
			hrp.Anchored = false
			hrp.AssemblyLinearVelocity = Vector3.zero
			hrp.AssemblyAngularVelocity = Vector3.zero
			local cf = CFrame.new(dest)
			if typeof(lookAt) == 'Vector3' then
				local flat = Vector3.new(lookAt.X - dest.X, 0, lookAt.Z - dest.Z)
				if flat.Magnitude >= 0.08 then
					cf = CFrame.lookAt(dest, dest + flat.Unit)
				end
			end
			hrp.CFrame = cf
			lv.VectorVelocity = Vector3.zero
			lv.Attachment0 = G.SB2DiveEnsureFlyAttachment(hrp)
			lv.Parent = hrp
			G.SB2DivePinPos = dest
		end)
		return true
	end
	-- The hover hold must only be on while the dodge actually has you in the air. Left on
	-- (dodge switched off mid-hover, or a lift that ended), it fights your walking.
	track(RunService.Heartbeat:Connect(function()
		if lv.Parent == nil then
			return
		end
		local dodgeOn = G.SB2AutoFloorDodgeOn == true
		local airAt = tonumber(G.SB2DodgeAirAt) or -math.huge
		if not dodgeOn or os.clock() - airAt > 1 then
			lv.Parent = nil
			lv.Attachment0 = nil
		end
	end))
	G.SB2DiveResetHold = function(pos)
		if typeof(pos) == 'Vector3' then
			G.SB2DivePinPos = pos
		end
	end
	local function upright(cf)
		local p = cf.Position
		local lk = cf.LookVector
		local flat = Vector3.new(lk.X, 0, lk.Z)
		return flat.Magnitude > 0.05 and CFrame.lookAt(p, p + flat.Unit) or CFrame.new(p)
	end
	local pinGen = 0
	local function pinTeleportCFrame(cf, seconds)
		if typeof(cf) ~= 'CFrame' then
			return
		end
		cf = upright(cf)
		local model = LocalPlayer.Character
		local hrp = getMyBringPart()
		if not model or not hrp then
			return
		end
		if G.SB2TpPinActive == true and typeof(G.SB2TpPinCFrame) == 'CFrame'
			and (G.SB2TpPinCFrame.Position - cf.Position).Magnitude < 5
		then
			G.SB2TpPinCFrame = cf
			return
		end
		pinGen += 1
		local gen = pinGen
		G.SB2TpPinActive = true
		G.SB2TpPinCFrame = cf
		local untilT = os.clock() + math.max(0.25, tonumber(seconds) or 0.9)
		pcall(function()
			hrp.Anchored = false
			hrp.AssemblyLinearVelocity = Vector3.zero
			hrp.AssemblyAngularVelocity = Vector3.zero
			model:PivotTo(cf)
		end)
		task.spawn(function()
			while pinGen == gen and os.clock() < untilT and alive do
				RunService.Heartbeat:Wait()
				local root = getMyBringPart()
				local hum = model:FindFirstChildOfClass('Humanoid')
				if not root then
					continue
				end
				local st = hum and hum:GetState()
				if st == Enum.HumanoidStateType.Jumping then
					break
				end
				pcall(function()
					local target = G.SB2TpPinCFrame or cf
					root.AssemblyLinearVelocity = Vector3.zero
					root.AssemblyAngularVelocity = Vector3.zero
					if (root.Position - target.Position).Magnitude > 0.6 then
						model:PivotTo(target)
					end
				end)
			end
			if pinGen == gen then
				G.SB2TpPinActive = false
				G.SB2TpPinCFrame = nil
			end
		end)
	end
	G.SB2PinTeleportCFrame = pinTeleportCFrame
	G.SB2MoveCharacter = function(cf, seconds)
		if typeof(cf) ~= 'CFrame' then
			return
		end
		local hrp = getMyBringPart()
		if not hrp then
			return
		end
		if (hrp.Position - cf.Position).Magnitude < 6 then
			return
		end
		pinTeleportCFrame(cf, tonumber(seconds) or 0.55)
	end
end

---------------------------------------------------------------------------
-- Floor circle / telegraph finders (lifted from PlayerTools' event-dive code)
---------------------------------------------------------------------------
do
	local DIVE_CIRCLE_DODGE = true
	local DIVE_TELE_NEAR = 160
	local DIVE_TELE_CACHE_SEC = 0.9
	local DIVE_DODGE_RING = 38
	local DIVE_IGNORE_WS = {
		Camera = true, Terrain = true, Characters = true, Mobs = true, Baseplate = true,
		['AntiFall-Maze'] = true, SweepingStrike = true, Bat = true, ActiveBats = true,
		Trail = true, SoulLightning = true, Meteor = true, Soul = true, Whirlpool = true,
		Lava = true, Indicator = true, Lines = true, Circle = true, EffectHitbox = true,
		Skill = true, SummonPortal = true, TreeEffect = true, CharacterItems = true,
	}
	local diveDashed = setmetatable({}, { __mode = 'k' })
	local diveSeenAt = setmetatable({}, { __mode = 'k' })
	local divePartSample = setmetatable({}, { __mode = 'k' })
	local diveTeleCache = { at = 0, hits = {}, origin = nil, nearR = 0 }
	local diveAoeGoal = nil
	local diveCircleScanAt = 0
	local diveLastCluster = nil
	local diveYaw = (((tonumber(LocalPlayer.UserId) or 1) % 12) / 12) * math.pi * 2
	local function clampNearCluster(pos)
		return pos
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
					local cap = 60
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

		-- True only on real FillIn growth (anim/fresh names caused constant under↔up Y flicker).
		-- Floor circle / telegraph discs (DungeonLootr-style gap find), throttled for Event dive.
		local function diveAvoidFloorCircles(hrpPos, fightY, cluster)
			if not DIVE_CIRCLE_DODGE or typeof(hrpPos) ~= 'Vector3' then
				return nil
			end
			local lavaPinY = typeof(getgenv().SB2LavaFightY) == 'number' and getgenv().SB2LavaFightY
				or typeof(getgenv().SB2LavaHoverY) == 'number' and getgenv().SB2LavaHoverY
			if lavaPinY then
				fightY = lavaPinY
			end
			local now = os.clock()
			local diveFarmActive = getgenv().SB2DiveFarmOn == true
				and type(isToggleOn) == 'function'
				and isToggleOn('DiveFarm')
			local scanAt = diveFarmActive and diveCircleScanAt
				or (tonumber(getgenv().SB2FloorDodgeScanAt) or 0)
			local cachedGoal = diveFarmActive and diveAoeGoal or getgenv().SB2FloorDodgeGoal
			if (now - scanAt) < 0.12 then
				if typeof(cachedGoal) == 'Vector3' and not getgenv().SB2DiveUnderMap then
					return Vector3.new(cachedGoal.X, fightY or cachedGoal.Y, cachedGoal.Z)
				end
				return nil
			end
			if diveFarmActive then
				diveCircleScanAt = now
			else
				getgenv().SB2FloorDodgeScanAt = now
			end
			local char = getMyCharacterModel() or LocalPlayer.Character
			if not char then
				return nil
			end
			local me = hrpPos
			local circles = {}
			local function namedDanger(n)
				n = string.lower(tostring(n or ''))
				-- Meatball / BallsBarrage markers: AutoFloorDodge lifts Y. A 6-stud XZ sidestep stays in the ball.
				if n == 'indicatororb' or string.find(n, 'meatball', 1, true) then
					return false
				end
				return string.find(n, 'circle', 1, true)
					or string.find(n, 'ring', 1, true)
					or string.find(n, 'aoe', 1, true)
					or string.find(n, 'telegraph', 1, true)
					or string.find(n, 'indicator', 1, true)
					or string.find(n, 'strike', 1, true)
					or string.find(n, 'smash', 1, true)
					or string.find(n, 'slam', 1, true)
					or string.find(n, 'meteor', 1, true)
					or string.find(n, 'nova', 1, true)
					or string.find(n, 'hitbox', 1, true)
					or string.find(n, 'lightning', 1, true)
			end
			local function underTelegraphFolder(part)
				local p = part
				for _ = 1, 8 do
					if not p then
						return false
					end
					local n = string.lower(tostring(p.Name or ''))
					if n == 'spelltelegraphs' or n == 'telegraphs' or n == 'telegraph_root' then
						return true
					end
					p = p.Parent
				end
				return false
			end
			local function addPart(part)
				if not part or not part:IsA('BasePart') or part == workspace.Terrain then
					return
				end
				if part.Transparency >= 0.995 then
					return
				end
				if part:IsDescendantOf(char) then
					return
				end
				local pos, size = part.Position, part.Size
				local dx, dz = pos.X - me.X, pos.Z - me.Z
				if (dx * dx + dz * dz) > 14400 then
					return
				end
				local col = part.Color
				local hot = col
					and (
						(col.R > 0.5 and col.G < 0.5 and col.B < 0.48)
						or (col.R > 0.65 and col.G > 0.35 and col.B < 0.4)
						or (col.R > 0.45 and col.B > 0.45 and col.G < 0.4)
						or (col.R > 0.7 and col.B > 0.55)
					)
				local sx, sy, sz = size.X, size.Y, size.Z
				local thick = math.min(sx, sy, sz)
				local span = math.max(sx, sy, sz)
				-- The arena floor is a huge disc. Attack markers are not.
				if span > 80 then
					return
				end
				local flat = thick < 8 and span >= 5
				local neon = part.Material == Enum.Material.Neon or part.Material == Enum.Material.ForceField
				local short = #tostring(part.Name) <= 2
				local fillIn = string.find(string.lower(tostring(part.Name)), 'fillin', 1, true) ~= nil
				local disc = flat and (hot or neon or (not part.CanCollide and span >= 8) or fillIn)
				if not (
					namedDanger(part.Name)
					or underTelegraphFolder(part)
					or (hot and flat)
					or (short and disc)
					or fillIn
				) then
					return
				end
				circles[#circles + 1] = { x = pos.X, z = pos.Z, r = math.max(6, span * 0.5) }
			end
			local function scan(root, cap)
				if not root then
					return
				end
				local n = 0
				for _, d in ipairs(root:GetDescendants()) do
					n += 1
					if n > (cap or 120) then
						break
					end
					addPart(d)
				end
			end
			local st = workspace:FindFirstChild('SpellTelegraphs')
			if st then
				for _, ch in ipairs(st:GetChildren()) do
					addPart(ch)
				end
				scan(st, 180)
			end
			scan(workspace:FindFirstChild('Effects'), 140)
			scan(workspace:FindFirstChild('Indicator'), 80)
			scan(workspace:FindFirstChild('Lines'), 60)
			scan(workspace:FindFirstChild('Circle'), 40)
			scan(workspace:FindFirstChild('Telegraphs'), 120)
			for _, ch in ipairs(workspace:GetChildren()) do
				if ch:IsA('BasePart') then
					addPart(ch)
				end
			end
			pcall(function()
				local CS = game:GetService('CollectionService')
				local tags = { 'FillIn', 'EnemySkillHitbox' }
				for ti = 1, #tags do
					local tagged = CS:GetTagged(tags[ti])
					for i = 1, math.min(#tagged, 48) do
						local inst = tagged[i]
						if inst:IsA('BasePart') then
							addPart(inst)
						end
					end
				end
			end)
			if #circles == 0 then
				if diveFarmActive then
					diveAoeGoal = nil
				else
					getgenv().SB2FloorDodgeGoal = nil
				end
				return nil
			end
			local function covered(x, z, pad)
				pad = pad or 3
				for i = 1, #circles do
					local c = circles[i]
					local fx, fz = x - c.x, z - c.z
					local need = c.r + pad
					if fx * fx + fz * fz < need * need then
						return true
					end
				end
				return false
			end
			local FLOOR_DODGE_INSIDE_PAD = 2.5
			local FLOOR_DODGE_LEAD_PAD = 16
			local function circleThreatPad(pad)
				for i = 1, #circles do
					local c = circles[i]
					local fx, fz = me.X - c.x, me.Z - c.z
					local need = c.r + pad
					if fx * fx + fz * fz < need * need then
						return true
					end
				end
				return false
			end
			if not circleThreatPad(FLOOR_DODGE_LEAD_PAD) then
				if diveFarmActive then
					diveAoeGoal = nil
				else
					getgenv().SB2FloorDodgeGoal = nil
				end
				return nil
			end
			local best, bestD = nil, nil
			local function tryAt(x, z)
				if covered(x, z, 3) then
					return
				end
				local dx, dz = x - me.X, z - me.Z
				local d = dx * dx + dz * dz
				if not bestD or d < bestD then
					bestD = d
					best = Vector3.new(x, fightY or me.Y, z)
				end
			end
			for i = 1, #circles do
				local c = circles[i]
				local fx, fz = me.X - c.x, me.Z - c.z
				local mag = math.sqrt(fx * fx + fz * fz)
				local ux, uz = 1, 0
				if mag > 0.4 then
					ux, uz = fx / mag, fz / mag
				end
				tryAt(c.x + ux * (c.r + 8), c.z + uz * (c.r + 8))
			end
			for i = 0, 15 do
				local a = i / 16 * math.pi * 2
				tryAt(me.X + math.cos(a) * 14, me.Z + math.sin(a) * 14)
				tryAt(me.X + math.cos(a) * 24, me.Z + math.sin(a) * 24)
			end
			if not best then
				return nil
			end
			if cluster then
				best = clampNearCluster(best, cluster, DIVE_DODGE_RING)
			end
			local stickyGoal = diveFarmActive and diveAoeGoal or getgenv().SB2FloorDodgeGoal
			if typeof(stickyGoal) == 'Vector3' and not covered(stickyGoal.X, stickyGoal.Z, FLOOR_DODGE_INSIDE_PAD) then
				local dx = stickyGoal.X - best.X
				local dz = stickyGoal.Z - best.Z
				if (dx * dx + dz * dz) < 36 then
					best = Vector3.new(stickyGoal.X, fightY or stickyGoal.Y, stickyGoal.Z)
				end
			end
			if diveFarmActive then
				diveAoeGoal = best
			else
				getgenv().SB2FloorDodgeGoal = best
			end
			return best
		end

		getgenv().SB2FindFloorCircleDodgeGoal = function(hrpPos, fightY, cluster)
			return diveAvoidFloorCircles(hrpPos, fightY, cluster)
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
		getgenv().SB2TelegraphEscape = telegraphEscape

end

---------------------------------------------------------------------------
-- GUI
---------------------------------------------------------------------------
do
	local src = readfile('PlayerTools/AtaraxiaLibrary.lua')
	G.Library = nil
	Library = assert(compile(src, 'AtaraxiaLibrary.lua'), 'AtaraxiaLibrary.lua failed to compile')()
	assert(Library and Library.CreateWindow, 'Ataraxia library failed to initialize')
	G.SB2AutoBetweenLibrary = Library
	Library.Animations = type(Library.Animations) == 'table' and Library.Animations or {}
	Library.Animations.TabSwitch = false
	Library.Animations.Dropdown = false
end

local Window = Library:CreateWindow({
	Title = 'Auto Between',
	Footer = BUILD .. '  ·  ' .. LocalPlayer.Name,
	Folder = 'AutoBetween',
	Size = UDim2.fromOffset(620, 420),
	MinSize = Vector2.new(560, 360),
	Resizable = true,
	OnUnload = function()
		if type(G.SB2AutoBetweenUnload) == 'function' then
			pcall(G.SB2AutoBetweenUnload, true)
		end
	end,
})
local MainTab = Window:AddTab('Main', 'swords')
local RunBox = MainTab:AddLeftGroupbox('Between')
local DodgeBox = MainTab:AddRightGroupbox('Dodge')

local DIFFS = { 'Auto', 'Normal', 'Hard', 'Elite' }
RunBox:AddToggle('ABAutoStart', {
	Text = 'Auto start Between runs',
	Default = settings.autoStart == true,
	Tooltip = 'Makes the Between party right away everywhere (kicks anyone not on the whitelist). Outside a run it starts 60s later; in a run the next one starts after Rubricatus dies and the reward chest is collected.',
}):OnChanged(function(v)
	settings.autoStart = v == true
	saveSettings()
end)
RunBox:AddDropdown('ABDifficulty', {
	Text = 'Difficulty',
	Values = DIFFS,
	Default = table.find(DIFFS, settings.difficulty) and settings.difficulty or 'Auto',
	AllowNull = false,
	Tooltip = 'Auto = Elite while you have Elite keys, otherwise Hard.',
}):OnChanged(function(v)
	if type(v) == 'table' then
		v = next(v)
	end
	if table.find(DIFFS, v) then
		settings.difficulty = v
		saveSettings()
	end
end)
local statusLabel = RunBox:AddLabel('Status: starting…')
local whoLabel = RunBox:AddLabel('Whitelist: checking…')
RunBox:AddToggle('ABAutoload', {
	Text = 'Autoload on this account',
	Default = settings.autoload == true,
	Tooltip = 'Off: this account stops loading Auto Between on join (the others keep it).',
}):OnChanged(function(v)
	settings.autoload = v == true
	saveSettings()
end)

local function setStatus(t)
	if statusLabel and statusLabel.SetText then
		pcall(statusLabel.SetText, statusLabel, 'Status: ' .. tostring(t))
	end
end

---------------------------------------------------------------------------
-- BetweenParty (party + start + chain + wipe restart), driven by fake controls
---------------------------------------------------------------------------
local strangersHere = false
local function chosenDifficulty()
	local o = Library.Options.ABDifficulty
	local v = o and o.Value
	if type(v) == 'table' then
		v = next(v)
	end
	return table.find(DIFFS, v) and v or 'Auto'
end
local fakeToggles = {
	BetweenAutoChain = { Value = false },
	BetweenFollowFriend = { Value = false },
	BetweenAutoDifficulty = { Value = true },
	BetweenEliteFirst = { Value = true },
	BetweenPrivate = { Value = false },
}
local fakeOptions = {
	BetweenDifficulty = { Value = 'Hard' },
}
G.SB2BetweenChestWaitCap = math.huge
local function syncFakeControls()
	local d = chosenDifficulty()
	fakeToggles.BetweenAutoDifficulty.Value = d == 'Auto'
	fakeOptions.BetweenDifficulty.Value = d == 'Auto' and 'Hard' or d
	-- In a run, BetweenParty chains the next one (after wave 100 / on a wipe). Outside a run,
	-- this script's own loop starts it, so the two never fire at the same time.
	-- In a run, BetweenParty starts the next one after Rubricatus dies and the reward chest
	-- is gone (no time cap here), or right away on a wipe. Outside a run this script's own
	-- loop owns starting (60s on the floor first).
	fakeToggles.BetweenAutoChain.Value = settings.autoStart == true
		and workspace:FindFirstChild('WaveDefenseStuff') ~= nil
end
syncFakeControls()

do
	local dummyBox = setmetatable({}, {
		__index = function()
			return function()
				return setmetatable({}, { __index = function() return function(self) return self end end })
			end
		end,
	})
	local fn = assert(compile(readfile('PlayerTools/BetweenParty.lua'), 'BetweenParty.lua'))
	local factory = fn()
	factory({
		WdBox = dummyBox,
		Library = Library,
		LocalPlayer = LocalPlayer,
		Players = Players,
		ReplicatedStorage = ReplicatedStorage,
		Options = fakeOptions,
		Toggles = fakeToggles,
		reloadLogicOnly = true,
	})
end

---------------------------------------------------------------------------
-- Auto dodge
---------------------------------------------------------------------------
do
	local fn = assert(compile(readfile('PlayerTools/AutoFloorDodge.lua'), 'AutoFloorDodge.lua'))
	local factory = fn()
	local ok, err = pcall(factory, {
		CombatBox = DodgeBox,
		RunService = RunService,
		LocalPlayer = LocalPlayer,
		Toggles = Library.Toggles,
		isToggleOn = isToggleOn,
		isLocalAlive = isLocalAlive,
		getMyCharacterModel = getMyCharacterModel,
	})
	if not ok then
		warn('[AutoBetween] dodge failed to load: ' .. tostring(err))
		DodgeBox:AddLabel('Dodge failed to load: ' .. tostring(err))
	end
end
do
	local okNc, errNc = pcall(function()
		local fn = assert(compile(readfile('PlayerTools/NoPlayerCollide.lua'), 'NoPlayerCollide.lua'))
		fn()({ Box = DodgeBox, Toggles = Library.Toggles })
	end)
	if not okNc then
		warn('[AutoBetween] no-collide failed: ' .. tostring(errNc))
	end
end
DodgeBox:AddLabel('Both turn off while someone not on the whitelist is in the server, and back on when they leave.')

---------------------------------------------------------------------------
-- Main loop: whitelist pause + start runs ASAP
---------------------------------------------------------------------------
local BETWEEN_RUN_PLACE_IDS = { [540240728] = true, [78945654064532] = true, [580239979] = true }
local function inRun()
	return workspace:FindFirstChild('WaveDefenseStuff') ~= nil and BETWEEN_RUN_PLACE_IDS[tonumber(game.PlaceId)] == true
end
local START_COOLDOWN = 20
local FLOOR_WAIT = 60
local floorSince = nil
local kickedAt = {}
local publicAt = 0
local lastStartAt = -math.huge
local starting = false
local dodgeWasOn = false
local lastErr = nil

local function strangerNames(list)
	local n = {}
	for i = 1, math.min(#list, 3) do
		n[i] = list[i].Name
	end
	return table.concat(n, ', ') .. (#list > 3 and (' +' .. (#list - 3)) or '')
end

local function tick()
	local list = listStrangers()
	local was = strangersHere
	strangersHere = #list > 0
	syncFakeControls()
	if whoLabel and whoLabel.SetText then
		pcall(whoLabel.SetText, whoLabel, strangersHere and ('Whitelist: dodge paused — ' .. strangerNames(list))
			or 'Whitelist: only whitelisted players here')
	end
	local dodge = Library.Toggles.AutoFloorDodge
	if strangersHere and not was then
		G.SB2StrangerCombatLock = true
		if type(dodge) == 'table' and dodge.Value == true then
			dodgeWasOn = true
			pcall(dodge.SetValue, dodge, false)
		end
		Library:Notify('Dodge paused (not on whitelist): ' .. strangerNames(list), 4)
	elseif strangersHere and type(dodge) == 'table' and dodge.Value == true then
		-- Someone turned it on (or it came back on) while a stranger is here: off again.
		dodgeWasOn = true
		pcall(dodge.SetValue, dodge, false)
	elseif was and not strangersHere then
		G.SB2StrangerCombatLock = false
		if dodgeWasOn and type(dodge) == 'table' and dodge.Value ~= true then
			G.SB2DodgeAutoSetting = true
			pcall(dodge.SetValue, dodge, true)
			G.SB2DodgeAutoSetting = false
		end
		dodgeWasOn = false
		Library:Notify('Dodge resumed', 3)
	end

	if settings.autoStart ~= true then
		floorSince = nil
		setStatus('auto start off')
		return
	end
	local now = os.clock()
	local mode = type(G.SB2BetweenChainMode) == 'function' and G.SB2BetweenChainMode() or fakeOptions.BetweenDifficulty.Value
	local state = type(G.SB2BetweenPartyState) == 'function' and G.SB2BetweenPartyState() or nil
	local running = inRun()

	-- Host: kick anyone in the party who is not on the whitelist.
	if state and state.leader then
		pcall(function()
			local party = ReplicatedStorage.LobbyParties:FindFirstChild(tostring(LocalPlayer:GetAttribute('PartyID')))
			if not party then
				return
			end
			for key in pairs(party:GetAttributes()) do
				local uid = tonumber(key)
				if uid and uid ~= LocalPlayer.UserId then
					local plr = Players:GetPlayerByUserId(uid)
					if plr and not isOwnAlt(plr) and now - (kickedAt[uid] or 0) > 2 then
						kickedAt[uid] = now
						ReplicatedStorage.Event:FireServer('UniqueFloorTypes', { 'Parties', 'KickMember', plr })
						Library:Notify('Kicked ' .. plr.Name .. ' from the party (not on whitelist)', 3)
					end
				end
			end
		end)
	end

	-- Host: keep the party Public (ToggleStatus flips Public <-> Private).
	if state and state.leader and state.status ~= nil and tostring(state.status) ~= 'Public'
		and now - publicAt > 1.5
	then
		publicAt = now
		pcall(function()
			ReplicatedStorage.Event:FireServer('UniqueFloorTypes', { 'Parties', 'ToggleStatus' })
		end)
	end

	if starting then
		return
	end

	-- 1. Party first, everywhere (floors, the Between lobby, and during a run so the next one is ready).
	if not state then
		floorSince = nil
		if LocalPlayer:GetAttribute('PartyID') ~= nil then
			setStatus('in another party — leave it and the Between party gets made')
			return
		end
		local left = START_COOLDOWN - (now - lastStartAt)
		if left > 0 then
			setStatus(lastErr and ('making party failed (%s) — retry in %ds'):format(lastErr, math.ceil(left))
				or ('making party… (%ds)'):format(math.ceil(left)))
			return
		end
		starting = true
		lastStartAt = now
		setStatus('making ' .. tostring(mode) .. ' party…')
		task.spawn(function()
			local pok, ok, err = pcall(G.SB2BetweenStartRun, { keepLobbySettings = false, mode = mode, start = false })
			starting = false
			lastErr = (not pok and ('error: ' .. tostring(ok))) or (not ok and tostring(err or 'failed')) or nil
			if lastErr then
				warn('[AutoBetween] party ' .. lastErr)
			else
				lastStartAt = -math.huge
			end
		end)
		return
	end
	if not state.leader then
		floorSince = nil
		setStatus("in someone else's Between party")
		return
	end

	-- 2. In a run: BetweenParty starts the next one after Rubricatus dies and the chest is collected.
	if running then
		floorSince = nil
		local chest = G.SB2BetweenChainSawRub == true and ' — Rubricatus dead, waiting for the chest' or ''
		setStatus(('in run — %s wave %s · party ready%s'):format(tostring(workspace:GetAttribute('WaveDefenseMode') or '?'),
			tostring(workspace:GetAttribute('Wave') or '?'), chest))
		return
	end

	-- 3. Not in a run (another floor / the Between lobby): party is up, start 60s later.
	floorSince = floorSince or now
	local wait = FLOOR_WAIT - (now - floorSince)
	if wait > 0 then
		setStatus(('party ready (%s) — starting in %ds'):format(tostring(state.mode or mode), math.ceil(wait)))
		return
	end
	local left = START_COOLDOWN - (now - lastStartAt)
	if left > 0 then
		setStatus(lastErr and ('last start failed (%s) — retry in %ds'):format(lastErr, math.ceil(left))
			or ('started — checking again in %ds'):format(math.ceil(left)))
		return
	end
	starting = true
	lastStartAt = now
	setStatus('starting ' .. tostring(mode) .. ' run…')
	task.spawn(function()
		local pok, ok, err = pcall(G.SB2BetweenStartRun, { keepLobbySettings = false, mode = mode })
		starting = false
		lastErr = (not pok and ('error: ' .. tostring(ok))) or (not ok and tostring(err or 'failed')) or nil
		if lastErr then
			warn('[AutoBetween] start ' .. lastErr)
		end
	end)
end

do
	local token = {}
	G.SB2AutoBetweenToken = token
	task.spawn(function()
		task.wait(2)
		while alive and G.SB2AutoBetweenToken == token do
			local ok, err = pcall(tick)
			if not ok then
				warn('[AutoBetween] ' .. tostring(err))
			end
			task.wait(1)
		end
	end)
end

---------------------------------------------------------------------------
-- Auto ResetMobs (Pyrixl only — needs the mod command bar rank)
--   Thunder (Tempest) wave: once the dialogue at the bottom is gone and lightning is striking.
--   Rift wave: as soon as the Rifts of Chaos have spawned.
--   Bob wave: as soon as its first mob has spawned.
--   Wisp wave ("Seek those with a binding light"): mobs spawned and 2s after the dialogue has closed.
--   Rubricatus: once he has finished spawning (stopped descending), plus a delay (2s).
-- Sent once per wave on the command bar's own remote, so the bar is never opened.
-- To add more waves later: add another branch in step() that calls fire() when its moment comes.
---------------------------------------------------------------------------
local RESET_MOBS_USER_ID = 475975042 -- Pyrixl
if LocalPlayer.UserId == RESET_MOBS_USER_ID then
	local okReset, errReset = pcall(function()
		local RESET_COMMAND = 'ResetMobs;@all'
		local LOG_PATH = 'PlayerTools/_resetmobs_log_' .. ACCT .. '.txt'
		if settings.resetThunder == nil then
			settings.resetThunder = true
		end
		if settings.resetRub == nil then
			settings.resetRub = true
		end
		if settings.resetRift == nil then
			settings.resetRift = true
		end
		if settings.resetBob == nil then
			settings.resetBob = true
		end
		if settings.resetWisp == nil then
			settings.resetWisp = true
		end
		if type(settings.resetRubDelay) ~= 'number' then
			settings.resetRubDelay = 2
		end
		saveSettings()

		-- Same call the command bar makes when you press Enter.
		local function runCommand(text)
			if G.SB2AutoResetDryRun == true then
				return true
			end
			return pcall(function()
				ReplicatedStorage.Event:FireServer('NewAdministrator', { 'RunCommand', text })
			end)
		end

		local ModBox = MainTab:AddLeftGroupbox('Auto ResetMobs')
		ModBox:AddToggle('ABResetThunder', {
			Text = 'On the thunder wave',
			Default = settings.resetThunder == true,
			Tooltip = 'Tempest wave: sends ' .. RESET_COMMAND .. ' once the dialogue at the bottom is gone and the lightning has started.',
		}):OnChanged(function(v)
			settings.resetThunder = v == true
			saveSettings()
		end)
		ModBox:AddToggle('ABResetRift', {
			Text = 'On the Rift wave',
			Default = settings.resetRift == true,
			Tooltip = 'Rift wave: sends ' .. RESET_COMMAND .. ' as soon as the Rifts of Chaos have spawned.',
		}):OnChanged(function(v)
			settings.resetRift = v == true
			saveSettings()
		end)
		ModBox:AddToggle('ABResetBob', {
			Text = 'On the Bob wave',
			Default = settings.resetBob == true,
			Tooltip = 'Bob wave: sends ' .. RESET_COMMAND .. ' as soon as its first mob has spawned.',
		}):OnChanged(function(v)
			settings.resetBob = v == true
			saveSettings()
		end)
		ModBox:AddToggle('ABResetWisp', {
			Text = 'On the Wisp wave',
			Default = settings.resetWisp == true,
			Tooltip = 'Wisp wave ("Seek those with a binding light"): sends ' .. RESET_COMMAND .. ' 2 seconds after the dialogue at the bottom has closed (mobs must have spawned).',
		}):OnChanged(function(v)
			settings.resetWisp = v == true
			saveSettings()
		end)
		ModBox:AddToggle('ABResetRub', {
			Text = 'On Rubricatus',
			Default = settings.resetRub == true,
			Tooltip = 'Sends ' .. RESET_COMMAND .. ' after Rubricatus has fully spawned, plus the delay below.',
		}):OnChanged(function(v)
			settings.resetRub = v == true
			saveSettings()
		end)
		ModBox:AddSlider('ABResetRubDelay', {
			Text = 'Rubricatus: seconds after spawn',
			Default = settings.resetRubDelay,
			Min = 0,
			Max = 10,
			Rounding = 1,
		}):OnChanged(function(v)
			if type(v) == 'number' then
				settings.resetRubDelay = v
				saveSettings()
			end
		end)
		local resetLabel = ModBox:AddLabel('ResetMobs: starting…')
		ModBox:AddButton('Send ' .. RESET_COMMAND .. ' now', function()
			local ok = runCommand(RESET_COMMAND)
			Library:Notify(ok and ('Sent ' .. RESET_COMMAND) or 'ResetMobs failed to send', 3)
		end)

		local lastStatus = nil
		local function setResetStatus(t)
			if t ~= lastStatus and resetLabel and resetLabel.SetText then
				lastStatus = t
				pcall(resetLabel.SetText, resetLabel, 'ResetMobs: ' .. tostring(t))
			end
		end
		local function resetLog(line)
			pcall(function()
				local stamp = os.date('%Y-%m-%d %H:%M:%S')
				local text = ('%s wave=%s %s\n'):format(stamp, tostring(workspace:GetAttribute('Wave')), line)
				if type(appendfile) == 'function' and isfile(LOG_PATH) then
					appendfile(LOG_PATH, text)
				else
					writefile(LOG_PATH, text)
				end
			end)
		end

		local wave = workspace:GetAttribute('Wave')
		local waveAt = os.clock()
		-- Wave this was already sent on (kept in getgenv so a reload mid-wave does not send twice).
		local firedWave = G.SB2AutoResetFiredWave
		if firedWave ~= wave then
			firedWave = nil
			G.SB2AutoResetFiredWave = nil
		end
		local strikeAt = nil -- first lightning strike seen this wave
		local dialogueGoneAt = nil -- since when the bottom dialogue has been hidden
		local dialogueSeenWave = nil -- wave on which the bottom dialogue was last showing
		local WISP_DELAY = 2 -- seconds after the dialogue closes
		local rubMob, rubSeenAt, rubLastPos, rubStillAt, rubReadyAt = nil, nil, nil, nil, nil
		local riftSeenAt = nil -- first Rift of Chaos seen this wave
		local bobNotes = 0

		local function onWaveChanged()
			local now = workspace:GetAttribute('Wave')
			if now == wave then
				return
			end
			wave = now
			waveAt = os.clock()
			strikeAt = nil
			riftSeenAt = nil
			bobNotes = 0
			firedWave = nil
			G.SB2AutoResetFiredWave = nil
			rubMob, rubSeenAt, rubLastPos, rubStillAt, rubReadyAt = nil, nil, nil, nil, nil
		end
		track(workspace:GetAttributeChangedSignal('Wave'):Connect(onWaveChanged))

		-- Bob / Wisp wave notes: what appears during them goes to the log (first 40 things per wave).
		local NOTE_ENVS = { Bob = true, Wisp = true }
		local function bobNote(kind, inst)
			local env = workspace:GetAttribute('WaveDefenseEnvironment')
			if bobNotes < 40 and inst.Name ~= 'DamageText' and NOTE_ENVS[env] then
				bobNotes += 1
				resetLog(('%s-wave %s %s "%s" %.1fs into the wave'):format(tostring(env), kind, inst.ClassName, inst.Name, os.clock() - waveAt))
			end
		end
		do
			local mobsFolder = workspace:FindFirstChild('Mobs')
			if mobsFolder then
				track(mobsFolder.ChildAdded:Connect(function(inst)
					bobNote('mob', inst)
				end))
			end
		end

		-- A Tempest lightning strike is the TempestStrike skill's "VFX" part dropped into workspace.
		track(workspace.ChildAdded:Connect(function(inst)
			bobNote('workspace', inst)
			if strikeAt == nil and inst.Name == 'VFX' and inst:FindFirstChild('StrikeSFX') ~= nil then
				strikeAt = os.clock()
			end
		end))

		local function dialogueShowing()
			local ok, vis = pcall(function()
				return LocalPlayer.PlayerGui.CardinalUI.PlayerUI.Popups.EnemyDialogue.Visible
			end)
			return ok and vis == true
		end

		-- The Rifts of Chaos are mobs named "Rift", one per spawn point in WaveDefenseRifts.
		local function countMobsNamed(name)
			local mobs = workspace:FindFirstChild('Mobs')
			local n = 0
			if mobs then
				for _, mob in ipairs(mobs:GetChildren()) do
					if mob.Name == name and mob:GetAttribute('Died') ~= true then
						n += 1
					end
				end
			end
			return n
		end
		local function countRifts()
			return countMobsNamed('Rift')
		end
		local function countWaveMobs()
			local mobs = workspace:FindFirstChild('Mobs')
			local n = 0
			if mobs then
				for _, mob in ipairs(mobs:GetChildren()) do
					if mob.Name ~= 'Reward Chest' and mob:GetAttribute('Died') ~= true then
						n += 1
					end
				end
			end
			return n
		end
		local function countBobs()
			local mobs = workspace:FindFirstChild('Mobs')
			local n = 0
			if mobs then
				for _, mob in ipairs(mobs:GetChildren()) do
					if string.find(string.lower(mob.Name), 'bob', 1, true) and mob:GetAttribute('Died') ~= true then
						n += 1
					end
				end
			end
			return n
		end
		local function riftsExpected()
			local ok, n = pcall(function()
				return #workspace.WaveDefenseStuff.WaveDefenseRifts:GetChildren()
			end)
			return ok and n > 0 and n or 4
		end

		local function findRubricatus()
			local mobs = workspace:FindFirstChild('Mobs')
			if not mobs then
				return nil
			end
			for _, mob in ipairs(mobs:GetChildren()) do
				if string.find(string.lower(tostring(mob.Name)), 'rubricatus', 1, true)
					and mob:GetAttribute('Died') ~= true
				then
					local entity = mob:FindFirstChild('Entity')
					local health = entity and entity:FindFirstChild('Health')
					local ok, hp = pcall(function()
						return health.Value
					end)
					if health and ok and type(hp) == 'number' and hp > 0 then
						return mob
					end
				end
			end
			return nil
		end

		local function fire(why, detail)
			firedWave = wave
			G.SB2AutoResetFiredWave = wave
			local ok, err = runCommand(RESET_COMMAND)
			local dry = G.SB2AutoResetDryRun == true and ' (dry run, not sent)' or ''
			resetLog(('%s %s%s%s'):format(ok and 'SENT' or ('FAILED ' .. tostring(err)), why, detail and (' ' .. detail) or '', dry))
			Library:Notify(ok and ('ResetMobs sent — ' .. why .. dry) or ('ResetMobs failed — ' .. tostring(err)), 4)
		end

		local function step()
			local now = os.clock()
			onWaveChanged()
			if dialogueShowing() then
				dialogueGoneAt = nil
				dialogueSeenWave = wave
			elseif not dialogueGoneAt then
				dialogueGoneAt = now
			end
			if wave == nil or not inRun() then
				setResetStatus('not in a run')
				return
			end
			if firedWave == wave then
				setResetStatus(('sent on wave %s'):format(tostring(wave)))
				return
			end

			-- Thunder wave.
			if workspace:GetAttribute('WaveDefenseEnvironment') == 'Tempest' then
				if settings.resetThunder ~= true then
					setResetStatus('thunder wave — off')
				elseif not strikeAt or now - waveAt < 1 then
					setResetStatus('thunder wave — waiting for lightning')
				elseif not dialogueGoneAt or now - dialogueGoneAt < 0.5 then
					-- 0.5s: the dialogue blinks off for a moment between two lines.
					setResetStatus('thunder wave — waiting for the dialogue to close')
				else
					fire('thunder wave', ('%.1fs into the wave, %.1fs after first strike'):format(now - waveAt, now - strikeAt))
				end
				return
			end

			-- Rift wave.
			if workspace:GetAttribute('WaveDefenseEnvironment') == 'Rift' then
				local n = countRifts()
				if settings.resetRift ~= true then
					setResetStatus('Rift wave — off')
				elseif n == 0 then
					setResetStatus('Rift wave — waiting for the rifts')
				else
					riftSeenAt = riftSeenAt or now
					-- All of them in, or 1.5s after the first one if some never show up.
					if n >= riftsExpected() or now - riftSeenAt >= 1.5 then
						fire('Rift wave', ('%d rifts, %.1fs into the wave'):format(n, now - waveAt))
					else
						setResetStatus(('Rift wave — %d rifts spawned'):format(n))
					end
				end
				return
			end

			-- Bob wave.
			if workspace:GetAttribute('WaveDefenseEnvironment') == 'Bob' then
				if settings.resetBob ~= true then
					setResetStatus('Bob wave — off')
				elseif countBobs() == 0 and countWaveMobs() == 0 then
					setResetStatus('Bob wave — waiting for the mobs')
				else
					fire('Bob wave', ('%.1fs into the wave'):format(now - waveAt))
				end
				return
			end

			-- Wisp wave.
			if workspace:GetAttribute('WaveDefenseEnvironment') == 'Wisp' then
				if settings.resetWisp ~= true then
					setResetStatus('Wisp wave — off')
				elseif countWaveMobs() == 0 then
					setResetStatus('Wisp wave — waiting for the mobs')
				elseif dialogueSeenWave ~= wave and now - waveAt < 20 then
					setResetStatus('Wisp wave — waiting for the dialogue')
				elseif not dialogueGoneAt then
					setResetStatus('Wisp wave — waiting for the dialogue to close')
				elseif now - dialogueGoneAt < WISP_DELAY then
					setResetStatus(('Wisp wave — sending in %.1fs'):format(WISP_DELAY - (now - dialogueGoneAt)))
				else
					fire('Wisp wave', ('%.1fs into the wave, %.1fs after the dialogue closed'):format(now - waveAt, now - dialogueGoneAt))
				end
				return
			end

			-- Rubricatus.
			local rub = findRubricatus()
			if rub then
				if settings.resetRub ~= true then
					setResetStatus('Rubricatus — off')
					return
				end
				if rub ~= rubMob then
					rubMob, rubSeenAt, rubLastPos, rubStillAt, rubReadyAt = rub, now, nil, nil, nil
				end
				if not rubReadyAt then
					-- He drops in from above: spawned = he has stopped moving for half a second.
					local root = rub:FindFirstChild('HumanoidRootPart') or rub.PrimaryPart
					local pos = root and root.Position
					if pos then
						if rubLastPos and (pos - rubLastPos).Magnitude < 0.2 then
							rubStillAt = rubStillAt or now
						else
							rubStillAt = nil
						end
						rubLastPos = pos
					end
					if rubStillAt and now - rubStillAt >= 0.5 then
						rubReadyAt = rubStillAt
					elseif now - rubSeenAt >= 6 then
						rubReadyAt = now -- never settled: stop waiting
					else
						setResetStatus('Rubricatus — spawning')
						return
					end
				end
				local delay = tonumber(settings.resetRubDelay) or 2
				local left = delay - (now - rubReadyAt)
				if left > 0 then
					setResetStatus(('Rubricatus spawned — sending in %.1fs'):format(left))
				else
					fire('Rubricatus', ('%.1fs after he appeared, %.1fs after he settled'):format(now - rubSeenAt, now - rubReadyAt))
				end
				return
			end

			setResetStatus(('wave %s — waiting for a special wave / Rubricatus'):format(tostring(wave)))
		end

		local token = {}
		G.SB2AutoResetToken = token
		task.spawn(function()
			while alive and G.SB2AutoResetToken == token do
				local ok, err = pcall(step)
				if not ok then
					warn('[AutoBetween] ResetMobs: ' .. tostring(err))
				end
				task.wait(0.1)
			end
		end)
	end)
	if not okReset then
		warn('[AutoBetween] auto ResetMobs failed to load: ' .. tostring(errReset))
	end
end

---------------------------------------------------------------------------
-- Keep across teleports + unload
---------------------------------------------------------------------------
pcall(function()
	local q = queue_on_teleport or (syn and syn.queue_on_teleport)
	if type(q) == 'function' then
		q([[
			if not game:IsLoaded() then game.Loaded:Wait() end
			task.wait(3)
			if getgenv().SB2AutoBetweenLoaded then return end
			if isfile('PlayerTools/AutoBetween.lua') then
				local fn = (loadstring or load)(readfile('PlayerTools/AutoBetween.lua'), 'AutoBetween.lua')
				if fn then task.spawn(fn) end
			end
		]])
	end
end)

G.SB2AutoBetweenUnload = function(fromWindow)
	alive = false
	G.SB2AutoBetweenToken = nil
	G.SB2AutoResetToken = nil
	G.SB2AutoBetweenLoaded = nil
	G.SB2AutoBetweenUnload = nil
	pcall(function()
		fakeToggles.BetweenAutoChain.Value = false
	end)
	pcall(function()
		if G.SB2BetweenAutoChainConn then
			G.SB2BetweenAutoChainConn:Disconnect()
			G.SB2BetweenAutoChainConn = nil
		end
	end)
	pcall(function()
		if type(G.SB2StopAutoFloorDodgeLoop) == 'function' then
			G.SB2StopAutoFloorDodgeLoop()
		end
		G.SB2DodgeAutoToken = nil
	end)
	pcall(function()
		if G.SB2DiveLinVel then
			G.SB2DiveLinVel:Destroy()
			G.SB2DiveLinVel = nil
		end
	end)
	for _, c in ipairs(conns) do
		pcall(function()
			c:Disconnect()
		end)
	end
	if not fromWindow then
		pcall(function()
			Library:Unload()
		end)
	end
end

-- Party menu refresh: the game only redraws the party panel when you click its buttons, so
-- after we change Public / difficulty / make the party by remote it kept showing "Private / Normal".
-- Redraw it from the real party every couple of seconds (only while you're in a party).
task.spawn(function()
	local Parties
	pcall(function()
		Parties = require(ReplicatedStorage.CardinalClient.MainModule.Services.UI.Locations.Parties)
	end)
	if type(Parties) ~= 'table' then
		return
	end
	local lastSig
	while alive do
		pcall(function()
			local party = Parties.GetLocalParty and Parties.GetLocalParty()
			if party then
				local sig = tostring(party:GetAttribute('Status')) .. '|' .. tostring(party:GetAttribute('Mode')) .. '|' .. party.Name
				-- redraw when the party changed, or every few seconds anyway (cheap)
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

Library:Notify('Auto Between loaded (' .. LocalPlayer.Name .. ')', 4)
warn('[AutoBetween] loaded ' .. BUILD)
]=]
FILES['BetweenParty.lua'] = [=[
--[[
	The Between (Wave Defense party lobby) — create party, set mode/status, start run.
	Split from PlayerTools_Obsidian.lua (register / size).
]]
getgenv().SB2BetweenPartyBuild = 'follow-friend-v25-no-solo-wipe'

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

	-- Anyone else in this run still alive? (Run servers only hold the run's own players.)
	-- "Pay to revive?" shows as soon as YOU are out of lives, even while the others keep going;
	-- restarting then dragged the whole party out of a live run (e.g. dying to Rubricatus at wave 100).
	local function othersStillAlive()
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr ~= LocalPlayer then
				local hum = plr.Character and plr.Character:FindFirstChildOfClass('Humanoid')
				if hum and hum.Health > 0 then
					return true
				end
			end
		end
		return false
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
			elseif payToReviveVisible() and othersStillAlive() then
				-- Only you are out: the run goes on without you. Don't start a new one.
				local now = os.clock()
				if now - (tonumber(getgenv().SB2SoloWipeLogAt) or 0) > 30 then
					getgenv().SB2SoloWipeLogAt = now
					chainLog('out of lives but teammates still alive - not restarting')
				end
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
]=]
FILES['AutoFloorDodge.lua'] = [=[
--[[
	Split from PlayerTools_Obsidian.lua (Luau 200-local register cap).
]]
	getgenv().SB2AutoFloorDodgeBuild = 'ground-dodge-v66-corrupted-nuke'

-- Per-account file names for the standalone AutoBetween (several accounts on one PC).
-- Global, not a local: the factory below is at Luau's 200-local limit.
getgenv().SB2AcctPath = function(p)
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

return function(env)
	local CombatBox = env.CombatBox
	local RunService = env.RunService
	local LocalPlayer = env.LocalPlayer
	local Toggles = env.Toggles
	local isToggleOn = env.isToggleOn
	local isLocalAlive = env.isLocalAlive
	local getMyCharacterModel = env.getMyCharacterModel
	assert(CombatBox, 'AutoFloorDodge: CombatBox required')
	if type(isToggleOn) == 'function' then
		getgenv().SB2IsToggleOn = isToggleOn
	end

	local BEAM_SKIP_ROOT = {
		Model = true,
		Floors = true,
		Terrain = true,
		Characters = true,
		CharacterItems = true,
		Camera = true,
		WaveDefenseStuff = true,
		SB2WaveKillTargetVis = true,
		-- Mob death flashes (~75-150 parts each) pile up on busy waves and ate the scan budget.
		HighlightModel = true,
	}

	local function segDistXZ(origin, a, b)
		local abx, abz = b.X - a.X, b.Z - a.Z
		local apx, apz = origin.X - a.X, origin.Z - a.Z
		local ab2 = abx * abx + abz * abz
		local t = 0
		if ab2 > 1 then
			t = math.clamp((apx * abx + apz * abz) / ab2, 0, 1)
		end
		local cx, cz = a.X + abx * t, a.Z + abz * t
		local dx, dz = origin.X - cx, origin.Z - cz
		local dist = math.sqrt(dx * dx + dz * dz)
		local len = math.sqrt(ab2)
		local px, pz = -abz, abx
		if len > 0.5 then
			px, pz = px / len, pz / len
		else
			px, pz = 1, 0
		end
		if dx * px + dz * pz < 0 then
			px, pz = -px, -pz
		end
		return dist, px, pz
	end

	-- Attack beams only. Map light shafts live under Workspace.Model / Terrain.
	local function beamDodgeGoal(origin)
		if typeof(origin) ~= 'Vector3' then
			return nil
		end
		local best, bestPush = nil, nil
		local function consider(beam)
			if not beam:IsA('Beam') or beam.Enabled ~= true or beam.Width0 < 3 or beam.Width0 > 12 then
				return
			end
			local myModel = LocalPlayer.Character
			if myModel and beam:IsDescendantOf(myModel) then
				return
			end
			local a0, a1 = beam.Attachment0, beam.Attachment1
			if not a0 or not a1 then
				return
			end
			local dist, px, pz = segDistXZ(origin, a0.WorldPosition, a1.WorldPosition)
			local half = beam.Width0 * 0.5
			-- Just clear the beam. A wide cone used to march you to the rim.
			local clear = 8
			if dist >= half + 4 then
				return
			end
			local push = math.min(12, (half + clear) - dist)
			if push < 1 then
				return
			end
			if not bestPush or push > bestPush then
				bestPush = push
				best = Vector3.new(origin.X + px * push, origin.Y, origin.Z + pz * push)
			end
		end
		local scanned = 0
		-- Newest children first: attack beams are spawned last, so a full budget still reaches them.
		local roots = workspace:GetChildren()
		for i = #roots, 1, -1 do
			local child = roots[i]
			if BEAM_SKIP_ROOT[child.Name] then
				continue
			end
			if child:IsA('Beam') then
				consider(child)
			end
			for _, d in ipairs(child:GetDescendants()) do
				scanned += 1
				if scanned > 2500 then
					break
				end
				consider(d)
			end
			if scanned > 2500 then
				break
			end
		end
		return best
	end

	-- Rubricatus line attacks, read straight from the game's own client code:
	--  * RedLightningLaser: aimed once at where you stood when it starts charging; 1s charge then
	--    1s of 8% ticks to anything within ~12.4 studs of that line (dead in ~1s if you stay).
	--  * RedLightningDiscs: 3 discs thrown at the spot you were in (Model attribute LockedTarget),
	--    25% each to anything within ~6 studs of their flight path.
	-- Neither tracks you, so getting off the line is a full dodge. This works for EVERY hold the
	-- dodge uses (ground, hover-160, final lift, low-HP lift): writeHeldCF / resetHold route
	-- their spot through SB2RedLaser.escape, and a Heartbeat safety net moves you if a branch
	-- that never asks still has you on a live line. Kept in getgenv() (Luau 200-local cap).
	do
		local RL = getgenv().SB2RedLaser
		if type(RL) == 'table' and type(RL.conns) == 'table' then
			for _, c in ipairs(RL.conns) do
				pcall(function()
					c:Disconnect()
				end)
			end
		end
		RL = { lasers = {}, conns = {}, last = nil }
		getgenv().SB2RedLaser = RL
		local CHARGE, FIRE, FADE_PAD = 1, 1, 0.35
		local RANGE = 250
		local LASER_CLEAR = 26 -- 12.4 hit radius + body + margin
		local DISC_CLEAR = 15 -- 6.35 hit radius + body + margin
		local function rubHrp(near)
			local mobs = workspace:FindFirstChild('Mobs')
			if not mobs then
				return nil
			end
			local best, bestD = nil, nil
			for _, m in ipairs(mobs:GetChildren()) do
				if string.find(string.lower(m.Name), 'rubricatus', 1, true) then
					local r = m:FindFirstChild('HumanoidRootPart') or m.PrimaryPart
					if r then
						local d = near and (r.Position - near).Magnitude or 0
						if not bestD or d < bestD then
							best, bestD = r, d
						end
					end
				end
			end
			return best
		end
		local function add(origin, target, why)
			if typeof(origin) ~= 'Vector3' or typeof(target) ~= 'Vector3' then
				return
			end
			local v = target - origin
			if v.Magnitude < 0.05 then
				return
			end
			local now = os.clock()
			for _, l in ipairs(RL.lasers) do
				if now - l.t0 < 0.4 and (l.origin - origin).Magnitude < 20 and l.dir:Dot(v.Unit) > 0.97 then
					return
				end
			end
			RL.lasers[#RL.lasers + 1] = {
				origin = origin,
				dir = v.Unit,
				t0 = now,
				untilT = now + CHARGE + FIRE + FADE_PAD,
			}
			local logFn = getgenv().SB2DodgeLog
			if type(logFn) == 'function' then
				pcall(logFn, 'red-laser', why, target)
			end
		end
		local function segDist(p, a, b)
			local ab = b - a
			local len2 = ab:Dot(ab)
			local t = len2 > 0.01 and math.clamp((p - a):Dot(ab) / len2, 0, 1) or 0
			return (p - (a + ab * t)).Magnitude
		end
		-- Big telegraphed ground nukes (Atheon-style): a tall 'Circle' cylinder (~170 wide,
		-- 150 tall) plus a flat 'EffectHitbox' disc, ~1s before a 100% hit. The floor-circle
		-- finder skips anything over 80 studs (floor decor), so these are tracked here.
		RL.circles = {}
		local BIG_NUKE_SPAN = 100
		local BIG_NUKE_MARGIN = 16
		-- Only the exact wave-86 nuke shape. v45-v47 also matched Bob's attack boxes (300-370
		-- wide) and other 120-155 circles, and the safety net then teleported you around the
		-- arena at hover height (and out of Bob's perch) straight into his shards.
		--   Circle (tall cylinder): ~170 wide, >=100 tall, round
		--   EffectHitbox (its floor disc): ~170 wide, flat, round
		--   Box (the wall that comes with it): ~50 long, ~0 thick, >=100 tall
		local function bigNukeThreat(part)
			if not part.Parent or not part:IsA('BasePart') then
				return nil
			end
			if getgenv().SB2BobEscapeActive == true then
				return nil -- Bob perch owns positioning
			end
			local sz = part.Size
			local span = math.max(sz.X, sz.Z)
			local thin = math.min(sz.X, sz.Z)
			local round = math.abs(sz.X - sz.Z) <= span * 0.1
			if part.Name == 'Box' then
				if span < 40 or span > 60 or thin > 1 or sz.Y < 100 then
					return nil
				end
				local axis = sz.X >= sz.Z and part.CFrame.RightVector or part.CFrame.LookVector
				local c = part.Position
				return { a = c - axis * (span * 0.5), b = c + axis * (span * 0.5), clear = 14, flat = true }
			end
			-- Corrupted Atheon (Elite WD wave 97): same slam, 209 wide, Circle only 50 tall,
			-- lands 3s after it appears for 100% HP. v65 ignored it (span > 185) and you stood still.
			local corrupted = span >= 195 and span <= 225
			if (span < 160 or span > 185) and not corrupted or not round then
				return nil
			end
			if part.Name == 'Circle' and sz.Y < (corrupted and 40 or 100) then
				return nil
			end
			if part.Name == 'EffectHitbox' and sz.Y > 5 then
				return nil
			end
			-- The slam keeps growing after it appears: the Atheon fight showed it reaches ~150 studs
			-- from the centre (AtheonNukeDash NUKE_SAFE). Wave 86 killed you 116 out of a 170 circle.
			return { a = part.Position, b = part.Position, clear = math.max(span * 0.5 + BIG_NUKE_MARGIN, corrupted and 185 or 165), flat = true }
		end
		RL.bigNukeThreat = bigNukeThreat
		-- Every live line threat as { a, b, clear }.
		function RL.threats(now)
			now = now or os.clock()
			local out = {}
			for part in pairs(RL.circles) do
				local t = part.Parent and bigNukeThreat(part)
				if t then
					out[#out + 1] = t
				elseif not part.Parent then
					RL.circles[part] = nil
				end
			end
			local live = {}
			for _, l in ipairs(RL.lasers) do
				if now < l.untilT then
					live[#live + 1] = l
					out[#out + 1] = { a = l.origin, b = l.origin + l.dir * RANGE, clear = LASER_CLEAR }
				end
			end
			RL.lasers = live
			for _, f in ipairs(workspace:GetChildren()) do
				if f.Name == 'RedLightningDiscEffects' then
					for _, m in ipairs(f:GetChildren()) do
						local tgt = m:GetAttribute('LockedTarget')
						if typeof(tgt) == 'Vector3' then
							local ok, piv = pcall(m.GetPivot, m)
							local from = ok and piv.Position or tgt
							out[#out + 1] = { a = from, b = tgt, clear = DISC_CLEAR }
						end
					end
				end
			end
			return out
		end
		function RL.active(now)
			return RL.threats(now)
		end
		local function hitBy(p, threats)
			for _, t in ipairs(threats) do
				local q = p
				if t.flat then
					-- Ground nukes hit the whole column: compare on the floor plane only.
					q = Vector3.new(p.X, t.a.Y, p.Z)
				end
				if segDist(q, t.a, t.b) < t.clear - 2 then
					return true
				end
			end
			return false
		end
		RL.hitBy = hitBy
		local function arenaMid()
			local wd = workspace:FindFirstChild('WaveDefenseStuff')
			local o = wd and wd:FindFirstChild('WaveDefenseOrigin')
			return (o and o:IsA('BasePart')) and o.Position or nil
		end
		-- Returns a safe spot at pos.Y, or nil when pos is already clear.
		function RL.escape(pos, center)
			if typeof(pos) ~= 'Vector3' then
				return nil
			end
			-- Behind a nuke pillar the 100% blast matters more than a 25% disc; lasers can't
			-- reach you there anyway (they need line of sight). Stay in cover.
			if typeof(getgenv().SB2RubricatusCoverPos) == 'Vector3' then
				return nil
			end
			local threats = RL.threats()
			if #threats == 0 or not hitBy(pos, threats) then
				return nil
			end
			local now = os.clock()
			local last = RL.last
			if last and now - last.t < 3 and (Vector3.new(last.from.X - pos.X, 0, last.from.Z - pos.Z)).Magnitude < 40 then
				local c = Vector3.new(last.to.X, pos.Y, last.to.Z)
				if not hitBy(c, threats) then
					return c
				end
			end
			local mid = arenaMid()
			local best, bestScore = nil, nil
			for _, dist in ipairs({ 18, 28, 40, 56, 75, 95, 115, 135, 155 }) do
				for i = 0, 15 do
					local ang = i * math.pi / 8
					local c = Vector3.new(pos.X + math.cos(ang) * dist, pos.Y, pos.Z + math.sin(ang) * dist)
					if not hitBy(c, threats) then
						local score = -dist
						if mid then
							local off = Vector3.new(c.X - mid.X, 0, c.Z - mid.Z).Magnitude
							if off > 150 then
								score -= (off - 150) * 2
							end
						end
						if typeof(center) == 'Vector3' then
							score -= Vector3.new(c.X - center.X, 0, c.Z - center.Z).Magnitude * 0.1
						end
						if not bestScore or score > bestScore then
							best, bestScore = c, score
						end
					end
				end
				if best then
					break
				end
			end
			if best then
				RL.last = { from = pos, to = best, t = now }
			end
			return best
		end
		local RS = game:GetService('ReplicatedStorage')
		local rep = RS:FindFirstChild('ReplicateSkill')
		if rep then
			RL.conns[#RL.conns + 1] = rep.OnClientEvent:Connect(function(mob, phase, skill, a, b)
				if skill ~= 'RedLightningLaser' or phase ~= 'Initial' then
					return
				end
				local target = typeof(b) == 'Vector3' and b or (typeof(a) == 'Vector3' and a or nil)
				local origin = (typeof(a) == 'Vector3' and typeof(b) == 'Vector3') and a or nil
				if not origin and typeof(mob) == 'Instance' then
					local r = mob:FindFirstChild('HumanoidRootPart')
					origin = r and r.Position or mob:GetPivot().Position
				end
				add(origin, target, 'event')
			end)
		end
		RL.conns[#RL.conns + 1] = workspace.ChildAdded:Connect(function(ch)
			if ch.Name ~= 'RedLightningLaserEffects' then
				return
			end
			local char = LocalPlayer.Character
			local me = char and char:FindFirstChild('HumanoidRootPart')
			if not me then
				return
			end
			local r = rubHrp(me.Position)
			if r then
				add(r.Position, me.Position, 'folder')
			end
		end)
		RL.conns[#RL.conns + 1] = workspace.ChildAdded:Connect(function(ch)
			local n = ch.Name
			if (n == 'Circle' or n == 'EffectHitbox' or n == 'Box') and ch:IsA('BasePart') then
				RL.circles[ch] = true
				task.delay(6, function()
					RL.circles[ch] = nil
				end)
				if bigNukeThreat(ch) then
					local logFn = getgenv().SB2DodgeLog
					if type(logFn) == 'function' then
						pcall(logFn, 'big-nuke', n .. ' ' .. math.floor(math.max(ch.Size.X, ch.Size.Z)), ch.Position)
					end
				end
			end
		end)
		-- Blackout waves: a light orb (attribute LightDuration, light Range = that value) whose
		-- light shrinks over time; outside it you take ~5% HP every tick (killed you at the high
		-- hover spot, 106 studs above it). Keep every hold inside the light.
		local orbCache = { at = -1, part = nil, orb = nil }
		local function findBlackoutOrb()
			local now = os.clock()
			if now - orbCache.at < 1 and (orbCache.part == nil or orbCache.part.Parent ~= nil) then
				return orbCache.part, orbCache.orb
			end
			orbCache.at, orbCache.part, orbCache.orb = now, nil, nil
			local function check(inst)
				if inst:GetAttribute('LightDuration') == nil and inst.Name ~= 'DarknerOrb' then
					return nil
				end
				local p = inst:FindFirstChild('Part')
				if not (p and p:IsA('BasePart')) then
					p = inst:IsA('BasePart') and inst or (inst:IsA('Model') and inst.PrimaryPart) or inst:FindFirstChildWhichIsA('BasePart', true)
				end
				return p
			end
			local roots = { workspace }
			local wds = workspace:FindFirstChild('WaveDefenseStuff')
			if wds then
				roots[#roots + 1] = wds
			end
			for _, root in ipairs(roots) do
				for _, ch in ipairs(root:GetChildren()) do
					local p = check(ch)
					if p then
						orbCache.part, orbCache.orb = p, ch
						return p, ch
					end
				end
			end
			return nil
		end
		RL.findBlackoutOrb = findBlackoutOrb
		-- Returns the closest spot inside the orb light, or nil when pos is already inside.
		function RL.blackoutClamp(pos)
			if typeof(pos) ~= 'Vector3' then
				return nil
			end
			local part, orb = findBlackoutOrb()
			if not part then
				return nil
			end
			local light = part:FindFirstChildWhichIsA('Light')
			local r = (light and tonumber(light.Range)) or tonumber(orb and orb:GetAttribute('LightDuration')) or 20
			local safe = math.max(6, r * 0.7)
			-- Sideways only: the orb sits low, and a 3D pull dragged you down into the floor
			-- every frame (then the floor pushed you back up = rapid up/down jitter).
			local d = Vector3.new(pos.X - part.Position.X, 0, pos.Z - part.Position.Z)
			local m = d.Magnitude
			if m <= safe then
				return nil
			end
			local out = part.Position + d.Unit * safe
			return Vector3.new(out.X, pos.Y, out.Z)
		end
		-- Safety net for any branch that holds you without asking: if you are on a live line,
		-- move off it now and repoint the dive pin there too.
		RL.conns[#RL.conns + 1] = game:GetService('RunService').Heartbeat:Connect(function()
			if #RL.lasers == 0 and next(RL.circles) == nil and not workspace:FindFirstChild('RedLightningDiscEffects') and not findBlackoutOrb() then
				return
			end
			if getgenv().SB2AutoFloorDodgeOn ~= true then
				return
			end
			local char = LocalPlayer.Character
			local hrp = char and char:FindFirstChild('HumanoidRootPart')
			if not hrp then
				return
			end
			local out = RL.escape(hrp.Position, nil)
			if not out then
				out = RL.blackoutClamp(hrp.Position)
			end
			if out then
				pcall(function()
					hrp.CFrame = CFrame.new(out) * (hrp.CFrame - hrp.CFrame.Position)
					hrp.AssemblyLinearVelocity = Vector3.zero
				end)
				if typeof(getgenv().SB2DivePinPos) == 'Vector3' then
					local pin = getgenv().SB2DivePinPos
					getgenv().SB2DivePinPos = Vector3.new(out.X, pin.Y, out.Z)
				end
				local now = os.clock()
				if now - (RL.lastLogAt or 0) > 0.5 then
					RL.lastLogAt = now
					local logFn = getgenv().SB2DodgeLog
					if type(logFn) == 'function' then
						pcall(logFn, 'line-escape', 'laser/disc/nuke', out)
					end
				end
			end
		end)
	end

	local function flatXZ(v)
		return Vector3.new(v.X, 0, v.Z)
	end

	local function flattenDodgeY(goal, y)
		if typeof(goal) ~= 'Vector3' or typeof(y) ~= 'number' then
			return goal
		end
		return Vector3.new(goal.X, y, goal.Z)
	end

	-- Meteors / falling floor AOEs (WD + Between): predict landing XZ and sidestep early.
	local function wdSkyThreatDodgeGoal(hrpPos, fightY)
		if typeof(hrpPos) ~= 'Vector3' then
			return nil
		end
		local playerFlat = flatXZ(hrpPos)
		local threats = {}
		local scanned = 0
		local nearestWhy, nearestD = nil, math.huge
		local chars = workspace:FindFirstChild('Characters')
		local charItems = workspace:FindFirstChild('CharacterItems')
		local function considerPart(d, fromTelegraph)
			if not d or not d:IsA('BasePart') then
				return
			end
			if d.Transparency >= 0.995 then
				return
			end
			-- Your own skill FX / weapons and map decor are never incoming attacks.
			if (chars and d:IsDescendantOf(chars)) or (charItems and d:IsDescendantOf(charItems)) then
				return
			end
			local n = string.lower(tostring(d.Name or ''))
			local pn = d.Parent and string.lower(tostring(d.Parent.Name or '')) or ''
			local blob = n .. ' ' .. pn
			local meteor = string.find(blob, 'meteor', 1, true)
				or string.find(blob, 'fireball', 1, true)
				or string.find(blob, 'firey', 1, true)
				or string.find(blob, 'fireorb', 1, true)
				or string.find(blob, 'rock', 1, true)
				or string.find(blob, 'boulder', 1, true)
			local s = d.Size
			local span0 = math.max(s.X, s.Y, s.Z)
			local minS = math.min(s.X, s.Y, s.Z)
			local redBall = d.Material == Enum.Material.Neon
				and span0 >= 6 and minS >= 4 and (span0 / math.max(minS, 0.05)) <= 1.8
				and d.Color.R > 0.75 and d.Color.G < 0.6 and d.Color.B < 0.4
			local floorSlam = string.find(blob, 'smash', 1, true)
				or string.find(blob, 'slam', 1, true)
				or string.find(blob, 'strike', 1, true)
				or string.find(blob, 'gyzer', 1, true)
				or string.find(blob, 'geyser', 1, true)
			if not meteor and not floorSlam and not redBall then
				return
			end
			-- Outside the telegraph folders only something actually moving is a threat:
			-- static rocks / red decor / leftover "strike" parts kept you sidestepping off mobs.
			local vel = d.AssemblyLinearVelocity
			local moving = vel.Y < -4 or vel.Magnitude > 8
			if not fromTelegraph then
				if floorSlam and not (meteor or redBall) then
					return
				end
				if not moving then
					return
				end
			end
			local flat = flatXZ(d.Position)
			local near = (flat - playerFlat).Magnitude
			if near > 95 then
				return
			end
			if near < nearestD then
				nearestD = near
				nearestWhy = d:GetFullName()
			end
			local land = flat
			local vy = d.AssemblyLinearVelocity.Y
			if vy < -2 and d.Position.Y > hrpPos.Y - 8 then
				local t = (d.Position.Y - hrpPos.Y) / math.max(-vy, 6)
				t = math.clamp(t, 0, 2.8)
				land = flat + flatXZ(d.AssemblyLinearVelocity) * t
			end
			local span = math.max(d.Size.X, d.Size.Y, d.Size.Z)
			threats[#threats + 1] = {
				flat = land,
				radius = math.max(16, span * 0.55 + (meteor and 14 or 10)),
			}
		end
		local roots = {
			workspace:FindFirstChild('SpellTelegraphs'),
			workspace:FindFirstChild('Effects'),
			workspace:FindFirstChild('Indicator'),
			workspace:FindFirstChild('Telegraphs'),
		}
		for ri = 1, #roots do
			local root = roots[ri]
			if root then
				for _, d in ipairs(root:GetDescendants()) do
					scanned += 1
					if scanned > 900 then
						break
					end
					considerPart(d, true)
				end
			end
		end
		-- Red fireballs spawn as workspace parts, not telegraph markers.
		for _, ch in ipairs(workspace:GetChildren()) do
			if BEAM_SKIP_ROOT[ch.Name] then
				continue
			end
			considerPart(ch, false)
			if ch:IsA('Model') or ch:IsA('Folder') then
				for _, d in ipairs(ch:GetChildren()) do
					considerPart(d, false)
				end
			end
		end
		if #threats == 0 then
			return nil
		end
		local bestGoal, bestScore = nil, -1e9
		for i = 0, 23 do
			local ang = i * math.pi * 2 / 24
			local dir = Vector3.new(math.cos(ang), 0, math.sin(ang))
			for _, dist in ipairs({ 10, 18, 26, 34 }) do
				local cand = playerFlat + dir * dist
				local score = dist
				for j = 1, #threats do
					local t = threats[j]
					score = math.min(score, (cand - t.flat).Magnitude - t.radius)
				end
				if score > bestScore then
					bestScore = score
					bestGoal = Vector3.new(cand.X, fightY or hrpPos.Y, cand.Z)
				end
			end
		end
		if bestScore > 1.5 and bestGoal then
			getgenv().SB2DodgeWhyDetail = nearestWhy
			return bestGoal
		end
		return nil
	end

	local function telegraphDodgeGoal(hrpPos, fightY)
		local fn = getgenv().SB2TelegraphEscape
		if type(fn) ~= 'function' then
			return nil
		end
		local ok, pos = pcall(fn, hrpPos, nil)
		if ok and typeof(pos) == 'Vector3' then
			return Vector3.new(pos.X, fightY or pos.Y, pos.Z)
		end
		return nil
	end

	local function resolveFloorDodgeGoal(hrp, fightY)
		local y = fightY or hrp.Position.Y
		local laserOut = getgenv().SB2RedLaser and getgenv().SB2RedLaser.escape(hrp.Position, nil)
		if laserOut then
			getgenv().SB2DodgeWhy = 'red-laser'
			return Vector3.new(laserOut.X, y, laserOut.Z)
		end
		local sky = wdSkyThreatDodgeGoal(hrp.Position, y)
		if sky then
			getgenv().SB2DodgeWhy = 'sky'
			return sky
		end
		getgenv().SB2DodgeWhyDetail = nil
		local tele = telegraphDodgeGoal(hrp.Position, y)
		if tele then
			getgenv().SB2DodgeWhy = 'telegraph'
			return tele
		end
		local findGoal = getgenv().SB2FindFloorCircleDodgeGoal
		if type(findGoal) == 'function' then
			local g = findGoal(hrp.Position, y, nil)
			if g then
				getgenv().SB2DodgeWhy = 'circle'
				return flattenDodgeY(g, y)
			end
		end
		local beam = beamDodgeGoal(hrp.Position)
		if beam then
			getgenv().SB2DodgeWhy = 'beam'
			return Vector3.new(beam.X, y, beam.Z)
		end
		return nil
	end

	-- Non-WD lava fallback (ground + offset). WD uses WD_LAVA_FIGHT_Y (probed 2144).
	local LAVA_CLEARANCE = 32
	local WD_LAVA_FLOOR_Y = 28
	local WD_LAVA_FIGHT_Y = 173
	local BOSS_CLEARANCE = 120
	-- Sentinel: boss-hover branch uses mob head-top Y (not floor + studs).
	local AEGANATOS_CLEARANCE = 3
	local AEGANATOS_HEAD_ABOVE = 16
	local WENDIGO_BEHIND = 150
	-- Y300 above center still sat in Bob's column. Park higher and fully outside the ring.
	-- World Y400 streamed the map; 360 + 280 studs off-center stays loaded and off-arena.
	local BOB_HOLD_Y = 360
	local BOB_SIDE_OFFSET = 280
	local BOB_HOLD_GRACE = 8
	local VAELITH_MISSILE_CLEAR = 12
	local VAELITH_MISSILE_MAX_PUSH = 18
	local VAELITH_MISSILE_WARN = 90
	local VAELITH_MISSILE_GRACE = 9
	local vaelithMissileParts = {}
	local vaelithMissileCount = 0
	local vaelithSeenUntil = 0
	local vaelithMobCached = nil
	local vaelithMobCachedAt = 0
	local bobAnchorY = nil
	local bobHoldY = nil
	local bobSeenUntil = 0
	local bobEscapeFlat = nil
	-- Rift spawns sit ~137 studs from center, right at the server hit limit; leaning 7 studs
	-- toward one rift at a time brings each into reach in turn.
	local RIFT_HOP_LEAN = 7
	-- Waves 1–99: snap onto each of the 4 portal spawns. 102 sat inside the ring
	-- and a 0.12s MoveCharacter lerp ate the teleport (looked parked).
	-- Hover Y130 (floor 28 + 102). Spawns are ~137 from center.
	local PACK_HOP_LEAN = 132
	local RIFT_HOP_INTERVAL = 0.22
	local riftHopIndex = 0
	local riftHopAt = 0
	local rubricatusNukeUntil = 0
	local rubricatusPillarCount = 0
	local rubricatusCoverPart = nil
	local rubricatusCoverGoalFlat = nil
	local rubricatusTeleScanAt = 0
	local rubricatusTeleCached = false
	local rubricatusThreatScanAt = 0
	local rubricatusThreatCache = nil
	local rubricatusNukeStartedAt = 0
	-- Hard nuke detonates ~10s after pillars, often AFTER they vanish. 8s released
	-- you into the 100% blast; 11.5% still chips you if you stand outside the model.
	local RUBRICATUS_NUKE_HOLD = 11
	local RUBRICATUS_NUKE_AFTER = 4.5
	local RUBRICATUS_NUKE_MAX = 15
	local RUBRICATUS_ENGAGE = 10
	-- 13x46x13 nuke models: stand INSIDE the footprint. 2.5 behind halfW sat 9
	-- studs out and still ate 11.5%.
	local PILLAR_BEHIND_OFFSET = 2
	local PILLAR_SHADOW_MARGIN = 1.8
	local PILLAR_BASE_CLEAR = 1
	local PILLAR_TOP_CLEAR = 8
	local RUBRICATUS_DODGE_CLEAR = 14
	local RUBRICATUS_DODGE_MAX_PUSH = 56
	-- After death the 90s survive phase parks at Y300. Only armed while we actually
	-- saw him — leftover FX names must not steal Wendigo / other waves.
	local RUBRICATUS_LEFTOVER_GRACE = 92
	local RUBRICATUS_KEEP_RANGE = 70
	local rubricatusSeenUntil = 0
	local lastRubricatusFlat = nil
	local lavaStandY = nil
	local lavaFightY = nil
	local lavaSeenUntil = 0
	local lavaScanAt = 0
	local lavaClearAt = 0
	local LAVA_ACTIVE_HOLD = 0.45
	local bossSeenUntil = 0
	local bossScanAt = 0
	local bossClearanceHeld = nil
	local aeganatosStandY = nil
	local aeganatosYRefreshAt = 0
	local AEGANATOS_Y_DEADBAND = 2.25
	local BOSS_NEEDLES = {
		'aegor',
		'vaelith',
		'rubricatus',
		'nythrane',
		'aeganatos',
		'kraken',
		'countdracula',
		'dracula',
		'enragedwendigo',
		'wendigo',
		'terrorincarnat',
		'headlesshorseman',
		'alphawerewolf',
		'cucurbita',
		'bulswick',
		'egnor',
		'magnor',
		'atheon',
		'overseer',
		'deity',
		'vyroth',
		'panku',
		'grim',
		'meatball',
		'abomination',
	}

	local function isWdLavaArena(groundY)
		if workspace:FindFirstChild('WaveDefenseStuff') then
			return true
		end
		if tonumber(game.PlaceId) == 78945654064532 then
			return true
		end
		if typeof(groundY) == 'number' then
			if math.abs(groundY - WD_LAVA_FLOOR_Y) <= 12 then
				return true
			end
			-- LavaHazardRegion mesh sits slightly above the 28 floor plane.
			if math.abs(groundY - 29.726560592651368) <= 6 then
				return true
			end
		end
		return false
	end

	local function resolveLavaFightY(hrp, groundY)
		if isWdLavaArena(groundY) then
			return WD_LAVA_FIGHT_Y
		end
		return hrp.Position.Y
	end

	-- Lava: stay at fight hover Y; floor circles / beams only move XZ.
	local function lavaCircleSidestep(hrp, hoverY)
		return resolveFloorDodgeGoal(hrp, hoverY)
	end

	local function textIsAeganatos(text)
		local key = string.gsub(string.lower(tostring(text or '')), '[%p%s]+', '')
		return string.find(key, 'aeganatos', 1, true) ~= nil
			or string.find(key, 'aegatanos', 1, true) ~= nil
			or string.find(key, 'sunkensovereign', 1, true) ~= nil
	end

	local function nameWantsAirHover(name)
		local key = string.gsub(string.lower(tostring(name or '')), '[%p%s]+', '')
		if key == '' then
			return false
		end
		if string.find(key, 'grim', 1, true)
			or string.find(key, 'overseer', 1, true)
			or string.find(key, 'rubricatus', 1, true)
			or string.find(key, 'rekindled', 1, true)
		then
			return false
		end
		-- Atheon bar title is exactly "Kindled". Variant tags like
		-- "Nautilus Arcwave [Kindled]" must not steal +120 hover.
		return string.find(key, 'atheon', 1, true) ~= nil
			or string.find(key, 'deity', 1, true) ~= nil
			or key == 'kindled'
			or string.find(key, 'terror', 1, true) ~= nil
			or string.find(key, 'vyroth', 1, true) ~= nil
			or string.find(key, 'panku', 1, true) ~= nil
	end

	-- Atheon slam is a ~155x50 cylinder on the arena. XZ sidestep cannot leave it; go over the rim.
	-- Meatball / BallsBarrage: airborne sphere. XZ sidestep stays inside; lift over and hold.
	-- Lane boxes (30x5x100) stay XZ-only. Hold the lift after the part despawns so impact still clears.
	local function wdHugeCircleLiftY(hrp)
		if not hrp then
			return nil
		end
		local px, pz = hrp.Position.X, hrp.Position.Z
		local best = nil
		local meatHold = false
		local myModel = hrp.Parent
		local function nameIsMeatBall(n)
			n = string.lower(tostring(n or ''))
			if n == '' then
				return false
			end
			return string.find(n, 'meatball', 1, true) ~= nil
				or string.find(n, 'abomination', 1, true) ~= nil
				or n == 'indicatororb'
				or n == 'ball'
				or string.find(n, 'ballsbarrage', 1, true) ~= nil
				or string.find(n, 'fireyorb', 1, true) ~= nil
		end
		local function partLooksAirBall(part)
			if not part or not part:IsA('BasePart') then
				return false
			end
			if nameIsMeatBall(part.Name) then
				return true
			end
			local sx, sy, sz = part.Size.X, part.Size.Y, part.Size.Z
			local span = math.max(sx, sy, sz)
			local minS = math.min(sx, sy, sz)
			return span >= 12 and minS >= 10 and (span / minS) <= 1.35
		end
		local function bump(part, isMeat)
			if not part or not part:IsA('BasePart') or part.Transparency >= 0.995 then
				return
			end
			if myModel and part:IsDescendantOf(myModel) then
				return
			end
			local wide = math.max(part.Size.X, part.Size.Z)
			local tall = part.Size.Y
			local span = math.max(wide, tall)
			if isMeat then
				local pn = string.lower(tostring(part.Name))
				if pn == 'ball' and span < 5 and part.AssemblyLinearVelocity.Magnitude < 8 then
					return
				end
			end
			local dx = part.Position.X - px
			local dz = part.Position.Z - pz
			local rad = math.max(isMeat and 14 or 8, span * 0.55) + (isMeat and 22 or 0)
			local near = dx * dx + dz * dz <= rad * rad
			if not near and isMeat then
				local vx = part.AssemblyLinearVelocity.X
				local vz = part.AssemblyLinearVelocity.Z
				local v2 = vx * vx + vz * vz
				if v2 > 36 then
					local t = math.clamp(-(dx * vx + dz * vz) / v2, 0, 1.15)
					local ax = part.Position.X + vx * t - px
					local az = part.Position.Z + vz * t - pz
					near = ax * ax + az * az <= rad * rad
				end
			end
			if not near then
				return
			end
			local top = part.Position.Y + tall * 0.5 + (isMeat and 18 or 24)
			if isMeat then
				top = math.max(top, WD_LAVA_FLOOR_Y + 80)
				meatHold = true
			elseif wide >= 90 then
				top = math.max(top, WD_LAVA_FLOOR_Y + BOSS_CLEARANCE)
			end
			if not best or top > best then
				best = top
			end
		end
		for _, ch in ipairs(workspace:GetChildren()) do
			if not ch:IsA('BasePart') then
				continue
			end
			local n = string.lower(tostring(ch.Name))
			if n == 'circle' or n == 'effecthitbox' then
				local wide = math.max(ch.Size.X, ch.Size.Z)
				local thin = math.min(ch.Size.X, ch.Size.Z)
				if wide >= 70 and not (thin > 1 and (wide / thin) > 2.4 and ch.Size.Y < 12) then
					bump(ch, false)
				end
			elseif partLooksAirBall(ch) then
				bump(ch, true)
			end
		end
		pcall(function()
			local tagged = game:GetService('CollectionService'):GetTagged('Ball')
			for i = 1, math.min(#tagged, 40) do
				bump(tagged[i], true)
			end
		end)
		local function scanRoot(root, cap)
			if not root then
				return
			end
			local n = 0
			for _, d in ipairs(root:GetDescendants()) do
				n += 1
				if n > cap then
					break
				end
				if d:IsA('BasePart') and partLooksAirBall(d) then
					bump(d, true)
				end
			end
		end
		scanRoot(workspace:FindFirstChild('Effects'), 160)
		scanRoot(workspace:FindFirstChild('SpellTelegraphs'), 120)
		scanRoot(workspace:FindFirstChild('Indicator'), 80)
		scanRoot(workspace:FindFirstChild('HitEffects'), 80)
		local mobs = workspace:FindFirstChild('Mobs')
		if mobs then
			for _, mob in ipairs(mobs:GetChildren()) do
				if nameIsMeatBall(mob.Name) then
					local biggest, span = nil, 0
					for _, p in ipairs(mob:GetDescendants()) do
						if p:IsA('BasePart') then
							local s = math.max(p.Size.X, p.Size.Y, p.Size.Z)
							if s > span then
								biggest, span = p, s
							end
						end
					end
					if biggest then
						bump(biggest, true)
					end
				end
			end
		end
		local now = os.clock()
		if best then
			getgenv().SB2SlamHoldY = best
			getgenv().SB2SlamHoldUntil = now + (meatHold and 1.6 or 1.4)
			getgenv().SB2MeatballLift = meatHold or nil
			return best
		end
		if now < (tonumber(getgenv().SB2SlamHoldUntil) or 0) then
			return tonumber(getgenv().SB2SlamHoldY)
		end
		getgenv().SB2MeatballLift = nil
		return nil
	end

	local function findAeganatosMob()
		local folder = workspace:FindFirstChild('Mobs')
		if not folder then
			return nil
		end
		for _, mob in ipairs(folder:GetChildren()) do
			if getgenv().SB2AFD_mobIsDead(mob) then
				continue
			end
			if textIsAeganatos(mob.Name) then
				return mob
			end
			local plate = mob:FindFirstChild('Nameplate')
			local label = plate and plate:FindFirstChildWhichIsA('TextLabel', true)
			if label and textIsAeganatos(label.Text) then
				return mob
			end
		end
		return nil
	end

	local function aeganatosHeadTopY(mob)
		if not mob or getgenv().SB2AFD_mobIsDead(mob) then
			return nil
		end
		local topY = nil
		local function bump(part)
			if part and part:IsA('BasePart') then
				local pTop = part.Position.Y + part.Size.Y * 0.5
				topY = topY and math.max(topY, pTop) or pTop
			end
		end
		bump(mob:FindFirstChild('Body'))
		bump(mob:FindFirstChild('HumanoidRootPart'))
		for _, name in ipairs({ 'Crown', 'Head', 'FakeHead', 'UpperTorso', 'Torso', 'Hitbox' }) do
			bump(mob:FindFirstChild(name))
			local ent = mob:FindFirstChild('Entity')
			if ent then
				bump(ent:FindFirstChild(name))
			end
		end
		local root = mob:FindFirstChild('HumanoidRootPart') or mob:FindFirstChildWhichIsA('BasePart')
		if not topY and root then
			topY = root.Position.Y + math.max(12, root.Size.Y * 0.5 + 8)
		end
		if not topY then
			return nil
		end
		return topY + AEGANATOS_HEAD_ABOVE
	end

	local function refreshAeganatosHoverY()
		local mob = findAeganatosMob()
		if not mob then
			return typeof(aeganatosStandY) == 'number' and aeganatosStandY or nil
		end
		local y = aeganatosHeadTopY(mob)
		if not y then
			return aeganatosStandY
		end
		local now = os.clock()
		if typeof(aeganatosStandY) == 'number' then
			local dy = y - aeganatosStandY
			if math.abs(dy) < AEGANATOS_Y_DEADBAND and now - aeganatosYRefreshAt < 0.5 then
				return aeganatosStandY
			end
			if math.abs(dy) < AEGANATOS_Y_DEADBAND then
				return aeganatosStandY
			end
		end
		aeganatosStandY = y
		aeganatosYRefreshAt = now
		getgenv().SB2AeganatosFightY = y
		return aeganatosStandY
	end

	local uiSaysFloorLava
	do
		local LAVA_UI_SKIP = {
			InventoryFrame = true, CashShop = true, Quests = true,
			SB2PlayerTools = true, SB2ThemePicker = true, Blessings = true, NPCDialogue = true,
		}
		-- Text labels outside the big menus, kept up to date by events. Scanning all of PlayerGui
		-- here was 41k objects (32k inventory tiles once the inventory tab was opened), 4x a second.
		local lavaLabels = {}
		local lavaLabelsReady = false
		local function lavaLabelSkipped(d, pg)
			local p = d
			while p and p ~= pg do
				if LAVA_UI_SKIP[p.Name] then
					return true
				end
				p = p.Parent
			end
			return false
		end
		local function lavaLabelAdd(d, pg)
			if (d:IsA('TextLabel') or d:IsA('TextButton')) and not lavaLabelSkipped(d, pg) then
				lavaLabels[d] = true
			end
		end
		local function lavaLabelsInit(pg)
			lavaLabelsReady = true
			for _, key in ipairs({ 'SB2AfdLavaLblAdd', 'SB2AfdLavaLblRem' }) do
				local c = getgenv()[key]
				if c then
					pcall(function()
						c:Disconnect()
					end)
				end
			end
			for _, d in ipairs(pg:GetDescendants()) do
				lavaLabelAdd(d, pg)
			end
			getgenv().SB2AfdLavaLblAdd = pg.DescendantAdded:Connect(function(d)
				lavaLabelAdd(d, pg)
			end)
			getgenv().SB2AfdLavaLblRem = pg.DescendantRemoving:Connect(function(d)
				lavaLabels[d] = nil
			end)
		end
		function uiSaysFloorLava()
			local pg = LocalPlayer:FindFirstChild('PlayerGui')
			if not pg then
				return false
			end
			if not lavaLabelsReady then
				lavaLabelsInit(pg)
			end
			for d in pairs(lavaLabels) do
				local t = string.lower(d.Text)
				if string.find(t, 'lava', 1, true)
					and (string.find(t, 'floor is lava', 1, true)
						or string.find(t, 'floorislava', 1, true)
						or string.find(t, 'lava wave', 1, true))
				then
					return true
				end
			end
			return false
		end
	end

	local function partIsFireOrb(part)
		if not part:IsA('BasePart') or part.Transparency > 0.6 then
			return false
		end
		local s = part.Size
		if math.max(s.X, s.Y, s.Z) < 8 then
			return false
		end
		local c = part.Color
		return part.Material == Enum.Material.Neon and c.R > 0.8 and c.G < 0.55 and c.B < 0.3
	end

	local worldSaysFloorLava
	do
		local lavaWorldDirty, lavaWorldSweepAt, lavaWorldLast = true, 0, false
		do
			local prevC = getgenv().SB2AfdLavaDirtyConn
			if prevC then
				pcall(function()
					prevC:Disconnect()
				end)
			end
			getgenv().SB2AfdLavaDirtyConn = workspace.ChildAdded:Connect(function(c)
				local n = string.lower(c.Name)
				if n == 'lava' or string.find(n, 'firey', 1, true) or c:IsA('Model') or c:IsA('Folder')
					or (c:IsA('BasePart') and c.Material == Enum.Material.Neon)
				then
					lavaWorldDirty = true
				end
			end)
		end
		local worldSaysFloorLavaFull
		function worldSaysFloorLava()
			-- Sweep all of workspace only when something new was added, or once a second
			-- (fire orbs can light up in place). It was ~8ms, 4x a second, in big maps.
			local wd = workspace:FindFirstChild('WaveDefenseStuff')
			local region = wd and wd:FindFirstChild('LavaHazardRegion')
			if region and region:IsA('BasePart') then
				local active = region.Transparency < 0.55
					or (#region:GetChildren() > 0 and region:GetAttribute('Active') == true)
				if active then
					return true
				end
			end
			local now = os.clock()
			if lavaWorldDirty or lavaWorldLast or now - lavaWorldSweepAt >= 1 then
				lavaWorldDirty = false
				lavaWorldSweepAt = now
				lavaWorldLast = worldSaysFloorLavaFull()
			end
			return lavaWorldLast
		end
		worldSaysFloorLavaFull = function()
			local wd = workspace:FindFirstChild('WaveDefenseStuff')
			local region = wd and wd:FindFirstChild('LavaHazardRegion')
			-- Inactive placeholder parts exist in WD hub/arena — only treat as lava when visible/active.
			if region and region:IsA('BasePart') then
				local active = region.Transparency < 0.55
					or (#region:GetChildren() > 0 and region:GetAttribute('Active') == true)
				if active then
					return true
				end
			end
			for _, c in ipairs(workspace:GetChildren()) do
				local n = string.lower(c.Name)
				-- Rubricatus leftover discs / slam boxes are red neon; they are not floor-is-lava.
				if string.find(n, 'lightning', 1, true) or string.find(n, 'disc', 1, true)
					or n == 'box' or n == 'effecthitbox' or n == 'circle'
				then
					continue
				end
				if c ~= region and (n == 'lava' or n == 'fireyorb' or string.find(n, 'firey', 1, true)) then
					return true
				end
				if c:IsA('BasePart') and partIsFireOrb(c) then
					return true
				end
				if c:IsA('Model') or c:IsA('Folder') then
					for _, d in ipairs(c:GetChildren()) do
						if d:IsA('BasePart') and partIsFireOrb(d) then
							return true
						end
						if string.lower(d.Name) == 'fireyorb' or string.lower(d.Name) == 'lava' then
							return true
						end
					end
				end
			end
			return false
		end
	end

	local function isWdWaveInstance()
		return workspace:FindFirstChild('WaveDefenseStuff') ~= nil
			or tonumber(game.PlaceId) == 78945654064532
			or tonumber(game.PlaceId) == 540240728
	end

	local function inWdDodgeContext()
		if workspace:FindFirstChild('WaveDefenseStuff') then
			return true
		end
		if getgenv().SB2WaveDefensePlace == true then
			return true
		end
		local pid = tonumber(game.PlaceId)
		return pid == 78945654064532 or pid == 540240728 or pid == 580239979
	end

	local function floorLavaActive(now)
		if now - lavaScanAt >= 0.25 then
			lavaScanAt = now
			if uiSaysFloorLava() or worldSaysFloorLava() then
				lavaSeenUntil = now + LAVA_ACTIVE_HOLD
			end
		end
		return now < lavaSeenUntil
	end

	pcall(function()
		local wd = game:GetService('ReplicatedStorage')
			.CardinalClient.MainModule.Services.EnemySkills.Skills['Wave Defense']
		local function ingestBossFolder(folder)
			if not folder then
				return
			end
			for _, c in ipairs(folder:GetChildren()) do
				local first = string.lower(tostring(c.Name)):match('^[%a\']+')
				if first and #first >= 4 then
					BOSS_NEEDLES[#BOSS_NEEDLES + 1] = first
				end
			end
		end
		ingestBossFolder(wd:FindFirstChild('Bosses'))
		ingestBossFolder(wd:FindFirstChild('Minibosses'))
	end)

	local function mobFlag(inst, name)
		if not inst then
			return false
		end
		if inst:GetAttribute(name) == true then
			return true
		end
		local child = inst:FindFirstChild(name)
		if not child then
			return false
		end
		if child:IsA('BoolValue') then
			return child.Value == true
		end
		if child:IsA('Folder') or child:IsA('Configuration') then
			return true
		end
		return false
	end

	local function mobIsDead(mob)
		if not mob or not mob.Parent then
			return true
		end
		if mob:GetAttribute('Died') == true then
			return true
		end
		local ent = mob:FindFirstChild('Entity')
		if ent and ent:GetAttribute('Died') == true then
			return true
		end
		local hp = ent and ent:FindFirstChild('Health')
		if hp and typeof(hp.Value) == 'number' and hp.Value > 0 then
			return false
		end
		local hum = mob:FindFirstChildOfClass('Humanoid')
		if hum and hum.Health <= 0 then
			return true
		end
		if hp and typeof(hp.Value) == 'number' and hp.Value <= 0 then
			return true
		end
		return false
	end
	getgenv().SB2AFD_mobIsDead = mobIsDead -- used by code above its definition

	local function bossNameMatch(text)
		local lower = string.lower(tostring(text or ''))
		if lower == '' then
			return false
		end
		local key = string.gsub(lower, '[%p%s]+', '')
		for i = 1, #BOSS_NEEDLES do
			if string.find(key, BOSS_NEEDLES[i], 1, true) then
				return true
			end
		end
		return string.find(lower, 'boss', 1, true) ~= nil
	end

	local function mobIsNamedWdBoss(mob)
		if mobIsDead(mob) then
			return false
		end
		local lower = string.lower(tostring(mob.Name))
		if string.find(lower, 'chest', 1, true) or string.find(lower, 'reward', 1, true) then
			return false
		end
		if bossNameMatch(mob.Name) then
			return true
		end
		local plate = mob:FindFirstChild('Nameplate')
		if plate then
			local label = plate:FindFirstChildWhichIsA('TextLabel', true)
			if label and bossNameMatch(label.Text) then
				return true
			end
		end
		local key = string.gsub(lower, '[%p%s]+', '')
		if string.find(key, 'rubricatus', 1, true) then
			return true
		end
		return false
	end

	local function mobIsBoss(mob)
		if not mobIsNamedWdBoss(mob) then
			return false
		end
		local ent = mob:FindFirstChild('Entity')
		if mobFlag(mob, 'Boss') or mobFlag(ent, 'Boss') or mobFlag(mob, 'IsBoss') or mobFlag(ent, 'IsBoss') then
			return true
		end
		return true
	end

	local wendigoMob = nil
	local wendigoScanAt = 0

	local function isEnragedWendigo(mob)
		if mobIsDead(mob) then
			return false
		end
		local lower = string.lower(tostring(mob.Name))
		if string.find(lower, 'chest', 1, true) or string.find(lower, 'reward', 1, true) then
			return false
		end
		local key = string.gsub(lower, '[%p%s]+', '')
		if string.find(key, 'enragedwendigo', 1, true) then
			return true
		end
		if not string.find(key, 'wendigo', 1, true) then
			return false
		end
		local function marked(inst)
			if not inst then
				return false
			end
			if inst:GetAttribute('Enraged') == true then
				return true
			end
			local variant = inst:GetAttribute('Variant') or inst:GetAttribute('EnemyBehavior')
			return type(variant) == 'string' and string.find(string.lower(variant), 'enraged', 1, true) ~= nil
		end
		return marked(mob) or marked(mob:FindFirstChild('Entity'))
	end

	local function findEnragedWendigo()
		local folder = workspace:FindFirstChild('Mobs')
		if not folder then
			return nil
		end
		for _, mob in ipairs(folder:GetChildren()) do
			if isEnragedWendigo(mob) then
				return mob
			end
		end
		return nil
	end

	local function refreshWendigo(now)
		if wendigoMob and (not wendigoMob.Parent or not isEnragedWendigo(wendigoMob)) then
			wendigoMob = nil
		end
		if not wendigoMob or now - wendigoScanAt >= 0.2 then
			wendigoScanAt = now
			wendigoMob = findEnragedWendigo()
		end
		return wendigoMob
	end

	local function mobFlatLook(mob)
		local part = mob:FindFirstChild('HumanoidRootPart')
		if not (part and part:IsA('BasePart')) then
			part = mob.PrimaryPart
		end
		local cf = nil
		if part and part:IsA('BasePart') then
			cf = part.CFrame
		else
			local ok, pivot = pcall(function()
				return mob:GetPivot()
			end)
			if ok and typeof(pivot) == 'CFrame' then
				cf = pivot
			end
		end
		if not cf then
			return nil, nil
		end
		local flat = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
		if flat.Magnitude < 0.05 then
			flat = Vector3.new(0, 0, -1)
		else
			flat = flat.Unit
		end
		return cf.Position, flat
	end

	local function bossBarActive()
		local pg = LocalPlayer:FindFirstChild('PlayerGui')
		if not pg then
			return false
		end
		local bars = pg:FindFirstChild('BossHealthBars', true)
		if not bars then
			return false
		end
		for _, desc in ipairs(bars:GetDescendants()) do
			if desc:IsA('TextLabel') and desc.Visible then
				local t = tostring(desc.Text or '')
				if t ~= '' and bossNameMatch(t) then
					return true
				end
			end
		end
		return false
	end

	local function bossBarAeganatosActive()
		local pg = LocalPlayer:FindFirstChild('PlayerGui')
		if not pg then
			return false
		end
		local bars = pg:FindFirstChild('BossHealthBars', true)
		if not bars then
			return false
		end
		for _, desc in ipairs(bars:GetDescendants()) do
			if desc:IsA('TextLabel') and desc.Visible and textIsAeganatos(desc.Text) then
				return true
			end
		end
		return false
	end

	local function mobBossClearance(mob)
		if not mobIsNamedWdBoss(mob) then
			return nil
		end
		local key = string.gsub(string.lower(tostring(mob.Name)), '[%p%s]+', '')
		if textIsAeganatos(mob.Name) then
			return AEGANATOS_CLEARANCE
		end
		if string.find(key, 'rubricatus', 1, true)
			or string.find(key, 'grim', 1, true)
			or string.find(key, 'overseer', 1, true)
			or string.find(key, 'wendigo', 1, true)
			or getgenv().SB2AFD_textIsBob(mob.Name)
		then
			return nil
		end
		local plate = mob:FindFirstChild('Nameplate')
		local label = plate and plate:FindFirstChildWhichIsA('TextLabel', true)
		if nameWantsAirHover(mob.Name) or (label and nameWantsAirHover(label.Text)) then
			return BOSS_CLEARANCE
		end
		if label and textIsAeganatos(label.Text) then
			return AEGANATOS_CLEARANCE
		end
		local p = getgenv().SB2AFD_mobStrikePos(mob)
		-- Floor bosses (Nythrane / Aegor ~Y30–50): 4-spot hop at fight height, not +120.
		if p and p.Y <= 60 then
			return nil
		end
		-- Named floor minibosses (Egnor / Ka / Nythrane / Cucurbita) keep 4-spot hop.
		return nil
	end

	local function bossHoverActive(now)
		-- +120 boss hover is WD-only — on story floors it launched spawns into the sky.
		if not inWdDodgeContext() then
			bossClearanceHeld = nil
			return nil
		end
		-- WD lava floor: lava branch owns Y173 — do not stack +80 boss clearance on top.
		if isWdWaveInstance() and floorLavaActive(now) then
			bossClearanceHeld = nil
			return nil
		end
		if now - bossScanAt >= 0.2 then
			bossScanAt = now
			local folder = workspace:FindFirstChild('Mobs')
			local best = nil
			if folder then
				for _, mob in ipairs(folder:GetChildren()) do
					local clearance = mobBossClearance(mob)
					if clearance and (not best or clearance > best) then
						best = clearance
					end
				end
			end
			if not best then
				-- NameLabel only. Variant/Health leftovers (e.g. Variant=Atheon on Wendigo)
				-- used to steal +120 and freeze the 4-spot hop.
				local pg = LocalPlayer:FindFirstChild('PlayerGui')
				local bars = pg and pg:FindFirstChild('BossHealthBars', true)
				if bars then
					for _, desc in ipairs(bars:GetDescendants()) do
						if desc:IsA('TextLabel') and desc.Visible then
							local nm = string.lower(tostring(desc.Name))
							if nm == 'variant' or nm == 'health' or nm == 'healthlabel' then
								continue
							end
							if textIsAeganatos(desc.Text) then
								best = AEGANATOS_CLEARANCE
								break
							elseif nameWantsAirHover(desc.Text) then
								best = BOSS_CLEARANCE
								break
							end
						end
					end
				end
			end
			if best then
				bossClearanceHeld = best
				bossSeenUntil = now + 1.2
			else
				bossClearanceHeld = nil
				bossSeenUntil = 0
			end
		end
		if now < bossSeenUntil and bossClearanceHeld then
			return bossClearanceHeld
		end
		bossClearanceHeld = nil
		return nil
	end

	local function groundYAtPos(wx, wy, wz, hrp)
		if typeof(wx) ~= 'number' or typeof(wy) ~= 'number' or typeof(wz) ~= 'number' or not hrp then
			return nil
		end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		-- Mobs are not floor: a boss under you made "the floor" its head (low-HP lift went to Y235).
		local ignore = { hrp.Parent, workspace:FindFirstChild('Mobs') }
		params.FilterDescendantsInstances = ignore
		local origin = Vector3.new(wx, wy + 8, wz)
		for _ = 1, 5 do
			local hit = workspace:Raycast(origin, Vector3.new(0, -500, 0), params)
			if not hit then
				break
			end
			-- Skip non-solid parts: WaveDefenseStuff.LavaHazardRegion sits ~2 studs over the real
			-- floor, so every "stand on the floor" held you hovering at Y~32.
			if not partIsFireOrb(hit.Instance) and hit.Instance.CanCollide then
				return hit.Position.Y
			end
			ignore[#ignore + 1] = hit.Instance
			params.FilterDescendantsInstances = ignore
			origin = hit.Position - Vector3.new(0, 1, 0)
		end
		return nil
	end

	local function groundYAt(hrp)
		return groundYAtPos(hrp.Position.X, hrp.Position.Y, hrp.Position.Z, hrp)
	end

	local function humanoidHip(hrp)
		local hum = hrp and hrp.Parent and hrp.Parent:FindFirstChildOfClass('Humanoid')
		if hum and type(hum.HipHeight) == 'number' then
			return hum.HipHeight
		end
		return 3
	end

	local function darknerOrbStandY(hrp, orbPos)
		if not hrp or typeof(orbPos) ~= 'Vector3' then
			return hrp and hrp.Position.Y
		end
		local gy = groundYAtPos(orbPos.X, orbPos.Y + 40, orbPos.Z, hrp)
		if not gy then
			gy = groundYAt(hrp)
		end
		if not gy and typeof(hoverGroundY) == 'number' then
			gy = hoverGroundY
		end
		if gy then
			return gy + humanoidHip(hrp)
		end
		return hrp.Position.Y
	end

	local function humAirborne(hrp)
		local hum = hrp and hrp.Parent and hrp.Parent:FindFirstChildOfClass('Humanoid')
		local fn = getgenv().SB2HumJumpOrFall
		if type(fn) == 'function' then
			return fn(hum) == true
		end
		if not hum then
			return false
		end
		local st = hum:GetState()
		return st == Enum.HumanoidStateType.Jumping or st == Enum.HumanoidStateType.Freefall
	end

	-- workspace.Barriers.Roof is an invisible collidable block over the whole arena starting
	-- at ~Y 170. Anything held above it ends up inside it and the physics shoves you back out
	-- (logs showed you bouncing between Y 360 and Y 168). Keep every air hold under it.
	do
		local cache = {}
		getgenv().SB2AFD_roofClamp = function(pos)
			if typeof(pos) ~= 'Vector3' or not workspace:FindFirstChild('WaveDefenseStuff') then
				return pos
			end
			local barriers = workspace:FindFirstChild('Barriers')
			if not barriers then
				return pos
			end
			local key = math.floor(pos.X / 10) .. ':' .. math.floor(pos.Z / 10)
			local now = os.clock()
			local c = cache[key]
			local ceil
			if c and now - c.at < 30 then
				ceil = c.y
			else
				local params = RaycastParams.new()
				params.FilterType = Enum.RaycastFilterType.Include
				params.FilterDescendantsInstances = { barriers }
				local ok, hit = pcall(function()
					return workspace:Raycast(Vector3.new(pos.X, WD_LAVA_FLOOR_Y + 6, pos.Z), Vector3.new(0, 2000, 0), params)
				end)
				ceil = (ok and hit) and hit.Position.Y or false
				cache[key] = { at = now, y = ceil }
			end
			if ceil and pos.Y > ceil - 8 then
				return Vector3.new(pos.X, ceil - 8, pos.Z)
			end
			return pos
		end
	end

	local function writeHeldCF(hrp, dest, lookAt, minMove, skipPin, forceY)
		minMove = tonumber(minMove) or 0
		local lavaLock = getgenv().SB2LavaEscapeActive == true
			and typeof(getgenv().SB2LavaFightY) == 'number'
		local bobLock = getgenv().SB2BobEscapeActive == true and typeof(getgenv().SB2BobHoldY) == 'number'
		local rubLock = getgenv().SB2RubricatusSurviveActive == true
			and typeof(getgenv().SB2RubricatusSurviveY) == 'number'
		-- Ground dodge: never climb. forceY is only for dropping leftover hover.
		if forceY ~= true then
			dest = Vector3.new(dest.X, hrp.Position.Y, dest.Z)
			skipPin = true
		end
		dest = getgenv().SB2AFD_roofClamp(dest)
		-- Never hold a spot sitting on a live Rubricatus laser / disc line (any dodge mode).
		local lineOut = getgenv().SB2RedLaser and getgenv().SB2RedLaser.escape(dest, nil)
		if lineOut then
			dest = Vector3.new(lineOut.X, dest.Y, lineOut.Z)
		end
		local liftY = dest.Y - hrp.Position.Y
		local airborne = humAirborne(hrp) and not lavaLock and not bobLock and not rubLock
			and forceY ~= true and liftY <= 2
		if airborne then
			dest = Vector3.new(dest.X, hrp.Position.Y, dest.Z)
			skipPin = true
		end
		-- Blackout: never hold outside the orb light (it drains 5% a tick out there).
		local boOut = getgenv().SB2RedLaser and getgenv().SB2RedLaser.blackoutClamp
			and getgenv().SB2RedLaser.blackoutClamp(dest)
		if boOut then
			dest = boOut
			airborne = false
		end
		if skipPin ~= true then
			local dx = math.abs(dest.X - hrp.Position.X)
			local dz = math.abs(dest.Z - hrp.Position.Z)
			local dy = math.abs(dest.Y - hrp.Position.Y)
			-- Hover nudges should not start an 8s TP pin (pin vs gravity = Y bob).
			if dx < 0.55 and dz < 0.55 and dy < 2.8 then
				skipPin = true
			end
		end
		if minMove > 0 then
			local dx = dest.X - hrp.Position.X
			local dy = dest.Y - hrp.Position.Y
			local dz = dest.Z - hrp.Position.Z
			if (dx * dx + dy * dy + dz * dz) < (minMove * minMove) then
				return false
			end
		end
		local flat
		if typeof(lookAt) == 'Vector3' then
			flat = Vector3.new(lookAt.X - dest.X, 0, lookAt.Z - dest.Z)
		else
			local lv = hrp.CFrame.LookVector
			flat = Vector3.new(lv.X, 0, lv.Z)
		end
		local cf = flat.Magnitude >= 0.08 and CFrame.lookAt(dest, dest + flat.Unit) or CFrame.new(dest)
		if airborne then
			hrp.Anchored = false
			hrp.CFrame = cf
			local v = hrp.AssemblyLinearVelocity
			-- A hit's upward speed is not a jump. Keep the sidestep, drop the launch.
			hrp.AssemblyLinearVelocity = Vector3.new(v.X * 0.2, 0, v.Z * 0.2)
			return true
		end
		hrp.AssemblyLinearVelocity = Vector3.zero
		hrp.AssemblyAngularVelocity = Vector3.zero
		hrp.CFrame = cf
		-- forceY hops are 4-spot teleports. A 0.12s MoveCharacter lerp canceled
		-- the snap when the hop interval was also 0.12s.
		if forceY ~= true and type(getgenv().SB2MoveCharacter) == 'function' then
			getgenv().SB2MoveCharacter(cf, 0.12)
		end
		if type(getgenv().SB2SetAnchorLockCF) == 'function' then
			getgenv().SB2SetAnchorLockCF(cf)
		elseif getgenv().SB2CombatAnchorOn == true then
			getgenv().SB2AnchorLockCF = cf
		end
		local pin = getgenv().SB2TpPinCFrame
		local pinNear = typeof(pin) == 'CFrame' and (pin.Position - cf.Position).Magnitude < 3
		if skipPin ~= true and not pinNear and type(getgenv().SB2PinTeleportCFrame) == 'function' then
			getgenv().SB2PinTeleportCFrame(cf, 8)
		end
		return true
	end

	local hoverGroundY = nil

	local function clearLavaHover()
		getgenv().SB2LavaHoverY = nil
		lavaStandY = nil
		hoverGroundY = nil
		lavaSeenUntil = 0
		bossSeenUntil = 0
		bossClearanceHeld = nil
		aeganatosStandY = nil
		aeganatosYRefreshAt = 0
		getgenv().SB2AeganatosFightY = nil
		lavaFightY = nil
		getgenv().SB2LavaFightY = nil
		bobAnchorY = nil
		bobHoldY = nil
		bobSeenUntil = 0
		bobEscapeFlat = nil
		getgenv().SB2BobHoldY = nil
		getgenv().SB2BobEscapeActive = false
		getgenv().SB2LavaEscapeActive = false
		getgenv().SB2RubricatusSurviveActive = false
		getgenv().SB2RubricatusSurviveY = nil
		getgenv().SB2RubricatusSurviveFlat = nil
	end

	local function clearWdDodgeHoverState()
		clearLavaHover()
		lavaClearAt = 0
		getgenv().SB2WdRiftHopGoal = nil
		getgenv().SB2WdRiftHopActive = false
		getgenv().SB2DarknerOrbXZ = nil
		getgenv().SB2DarknerOrbStandY = nil
		getgenv().SB2WendigoHold = nil
		getgenv().SB2FloorDodgeGoal = nil
		getgenv().SB2FloorDodgeScanAt = 0
	end
	getgenv().SB2ClearWdDodgeHoverState = clearWdDodgeHoverState

	local function findRubricatusMob()
		local folder = workspace:FindFirstChild('Mobs')
		if not folder then
			return nil
		end
		for _, mob in ipairs(folder:GetChildren()) do
			if mobIsDead(mob) then
				continue
			end
			local key = string.gsub(string.lower(tostring(mob.Name)), '[%p%s]+', '')
			if string.find(key, 'rubricatus', 1, true) then
				return mob
			end
			local plate = mob:FindFirstChild('Nameplate')
			local label = plate and plate:FindFirstChildWhichIsA('TextLabel', true)
			if label then
				local tkey = string.gsub(string.lower(tostring(label.Text)), '[%p%s]+', '')
				if string.find(tkey, 'rubricatus', 1, true) then
					return mob
				end
			end
		end
		return nil
	end

	-- 0% bar / Health.Value: he stays in Mobs for the 90s survive. Do not keep melee.
	local function rubricatusAtZeroHp(mob)
		if not mob then
			return false
		end
		local ent = mob:FindFirstChild('Entity')
		local h = ent and ent:FindFirstChild('Health')
		if h then
			local cur, maxV
			pcall(function()
				cur = h.Value
				if typeof(h.MaxValue) == 'number' and h.MaxValue > 0 then
					maxV = h.MaxValue
				end
			end)
			if type(cur) == 'number' then
				if cur <= 0 then
					return true
				end
				if type(maxV) == 'number' and maxV > 0 and (cur / maxV) <= 0.005 then
					return true
				end
			end
		end
		local plate = mob:FindFirstChild('Nameplate')
		if plate then
			for _, d in ipairs(plate:GetDescendants()) do
				if d:IsA('TextLabel') or d:IsA('TextButton') then
					local t = string.lower(tostring(d.Text or ''))
					if string.find(t, '^0%%') or string.find(t, '[^%d]0%%') then
						return true
					end
					if string.find(t, '^0%s*/') then
						return true
					end
				end
			end
		end
		return false
	end

	local function rubricatusHasLeftoverFx()
		-- Only Rubricatus disc leftovers. Lava/tempest Circle + EffectHitbox must
		-- not pin you to the floor or they steal the Y173 lava hover.
		for _, ch in ipairs(workspace:GetChildren()) do
			local n = string.lower(tostring(ch.Name))
			if string.find(n, 'redlightning', 1, true) then
				return true
			end
		end
		return false
	end

	local function rubricatusBossFlat(mob)
		if not mob then
			return nil, nil
		end
		local root = mob:FindFirstChild('HumanoidRootPart') or mob:FindFirstChildWhichIsA('BasePart', true)
		if not root then
			return nil, nil
		end
		return flatXZ(root.Position), root.Position.Y
	end

	-- Nuke cover, two layouts seen live:
	--   Model 'Pillar' (~13x46x13) rising from the floor ~115 studs out (current).
	--   Part 'Part' ~3x3 across, 80-290 long (older).
	-- Arena decoration MeshParts are also named 'Pillar'; they are not Models, so they never match.
	local function isRubricatusNukeCoverPart(inst)
		if inst.Parent ~= workspace then
			return false
		end
		if inst.Name == 'Pillar' and inst:IsA('Model') then
			local ok, _, bsize = pcall(inst.GetBoundingBox, inst)
			if not ok or typeof(bsize) ~= 'Vector3' then
				return false
			end
			local wide = math.max(bsize.X, bsize.Z)
			local thin = math.min(bsize.X, bsize.Z)
			-- Live nuke pillars are ~13x46x13. Skip map decoration Models named Pillar.
			return wide <= 22 and thin >= 8 and bsize.Y >= 18 and bsize.Y <= 80
		end
		if inst.Name ~= 'Part' or not inst:IsA('BasePart') then
			return false
		end
		local s = inst.Size
		local dims = { s.X, s.Y, s.Z }
		table.sort(dims)
		return dims[3] >= 70 and dims[2] <= 6
	end

	local function rubricatusCoverShape(inst)
		local cf, size
		if inst:IsA('Model') then
			local ok, bcf, bsize = pcall(inst.GetBoundingBox, inst)
			if not ok then
				return nil
			end
			cf, size = bcf, bsize
		else
			cf, size = inst.CFrame, inst.Size
		end
		local dims = { size.X, size.Y, size.Z }
		table.sort(dims)
		local halfY = math.abs(cf.RightVector.Y) * size.X * 0.5
			+ math.abs(cf.UpVector.Y) * size.Y * 0.5
			+ math.abs(cf.LookVector.Y) * size.Z * 0.5
		local pos = cf.Position
		return {
			part = inst,
			flat = flatXZ(pos),
			pos = pos,
			size = size,
			halfW = dims[2] * 0.5,
			bottom = pos.Y - halfY,
			top = pos.Y + halfY,
			spawned = true,
		}
	end

	local function collectRubricatusPillars(centerFlat, radius)
		centerFlat = flatXZ(centerFlat)
		radius = tonumber(radius) or 520
		local out = {}
		for _, child in ipairs(workspace:GetChildren()) do
			if isRubricatusNukeCoverPart(child) then
				local entry = rubricatusCoverShape(child)
				if entry and (entry.flat - centerFlat).Magnitude <= radius then
					out[#out + 1] = entry
				end
			end
		end
		return out
	end

	local function rubricatusSpawnedPillarsNear(hrpPos)
		return #collectRubricatusPillars(hrpPos, 480) > 0
	end

	local function rubricatusPillarRising(entry)
		local inst = entry and entry.part
		if not inst then
			return false
		end
		local part = inst:IsA('BasePart') and inst or inst:FindFirstChildWhichIsA('BasePart', true)
		if not part then
			return false
		end
		return part.AssemblyLinearVelocity.Y > 4
	end

	local function rubricatusReleaseCover()
		local cover = getgenv().SB2RubricatusCoverPos
		if typeof(cover) == 'Vector3' then
			getgenv().SB2RubCoverExit = cover
		end
		rubricatusNukeUntil = 0
		rubricatusNukeStartedAt = 0
		getgenv().SB2RubricatusNukeUntil = 0
		getgenv().SB2RubricatusCoverPos = nil
		rubricatusCoverPart = nil
		rubricatusCoverGoalFlat = nil
		if typeof(cover) == 'Vector3' and typeof(getgenv().SB2DivePinPos) == 'Vector3' then
			local pin = getgenv().SB2DivePinPos
			if (pin - cover).Magnitude < 4 then
				getgenv().SB2DivePinPos = nil
			end
		end
	end

	-- Cover starts when NEW pillars rise. Hold through despawn: Hard's blast hits after they vanish.
	local function rubricatusInCoverWindow(nowPre, hrpPos)
		local pillars = collectRubricatusPillars(hrpPos or Vector3.zero, 480)
		local n = #pillars
		-- The 7 pillars rise once and then stand for the whole fight, and boss attacks knock
		-- them around. Counting them / their velocity kept "the nuke is coming" on with no
		-- nuke, freezing you in cover while discs hit you. Only a pillar still coming up out
		-- of the floor (bottom below floor level) means a nuke was just cast.
		local rising = false
		for i = 1, n do
			if pillars[i].bottom < WD_LAVA_FLOOR_Y - 6 then
				rising = true
				break
			end
		end
		-- The nuke's own blast effect: once it has gone off, leave cover.
		if not getgenv().SB2RubNukeHook then
			getgenv().SB2RubNukeHook = workspace.Terrain.ChildAdded:Connect(function(ch)
				if not ch:IsA('Attachment') then
					return
				end
				task.defer(function()
					local s = ch:FindFirstChildWhichIsA('Sound')
					if s and string.find(tostring(s.SoundId), '132218659554859', 1, true) then
						getgenv().SB2RubNukeBoomAt = os.clock()
						local logFn = getgenv().SB2DodgeLog
						if type(logFn) == 'function' then
							logFn('rub-nuke-boom', nil, ch.WorldPosition)
						end
					end
				end)
			end)
		end
		local boomAt = tonumber(getgenv().SB2RubNukeBoomAt) or -1e9
		if rubricatusNukeStartedAt > 0 and boomAt >= rubricatusNukeStartedAt and nowPre - boomAt > 1 then
			rising = false
			rubricatusNukeUntil = 0
			rubricatusNukeStartedAt = 0
			getgenv().SB2RubricatusNukeUntil = 0
		end
		if rising then
			if rubricatusNukeStartedAt == 0 then
				rubricatusNukeStartedAt = nowPre
				getgenv().SB2RubNukeT0 = nowPre
				local logFn = getgenv().SB2DodgeLog
				if type(logFn) == 'function' then
					logFn('rub-nuke-cast', nil, hrpPos)
				end
			end
			rubricatusNukeUntil = nowPre + RUBRICATUS_NUKE_HOLD
			getgenv().SB2RubricatusNukeUntil = rubricatusNukeUntil
			rubricatusCoverPart = nil
		elseif n == 0 and rubricatusNukeStartedAt > 0 then
			rubricatusNukeUntil = math.max(rubricatusNukeUntil, nowPre + RUBRICATUS_NUKE_AFTER)
			getgenv().SB2RubricatusNukeUntil = rubricatusNukeUntil
			rubricatusNukeStartedAt = 0
		end
		if rubricatusNukeStartedAt > 0 and nowPre - rubricatusNukeStartedAt > RUBRICATUS_NUKE_MAX then
			rubricatusNukeUntil = math.min(rubricatusNukeUntil, nowPre + RUBRICATUS_NUKE_AFTER)
			rubricatusNukeStartedAt = 0
		end
		rubricatusPillarCount = n
		local active = nowPre < rubricatusNukeUntil
		if not active and (typeof(getgenv().SB2RubricatusCoverPos) == 'Vector3' or rubricatusCoverPart) then
			rubricatusReleaseCover()
		end
		return active
	end

	local function rubricatusSnapToCover(hrp, dest, lookAt)
		if typeof(dest) ~= 'Vector3' then
			return false
		end
		local flat = Vector3.new(dest.X - hrp.Position.X, 0, dest.Z - hrp.Position.Z)
		local look = typeof(lookAt) == 'Vector3' and lookAt or nil
		-- Collision stays ON: turning it off locally is the likely reason the blast went through
		-- the pillar in v14. The hold re-pins you every tick; on release you are walked out (no pop-up).
		-- Dive blink was sending you 150 studs off the pillar. Stay on writeHeldCF.
		writeHeldCF(hrp, dest, look, 0, true, true)
		getgenv().SB2RubricatusCoverPos = dest
		getgenv().SB2RubricatusOwnedChase = true
		return true
	end

	local function rubricatusIsRedPart(part)
		if not part:IsA('BasePart') or part.Transparency > 0.92 then
			return false
		end
		local c = part.Color
		return c.R > 0.52 and c.G < 0.52 and c.B < 0.58
	end

	local function rubricatusLaserLinePush(part, origin)
		local s = part.Size
		local long = math.max(s.X, s.Y, s.Z)
		if long < 8 then
			return nil, 0
		end
		local cf = part.CFrame
		local axis = cf.LookVector
		if s.X >= s.Y and s.X >= s.Z then
			axis = cf.RightVector
		elseif s.Y >= s.X and s.Y >= s.Z then
			axis = cf.UpVector
		end
		axis = Vector3.new(axis.X, 0, axis.Z)
		if axis.Magnitude < 0.06 then
			return nil, 0
		end
		axis = axis.Unit
		local half = long * 0.5
		local cen = Vector3.new(part.Position.X, origin.Y, part.Position.Z)
		local a = cen - axis * half
		local b = cen + axis * half
		local dist, px, pz = segDistXZ(origin, a, b)
		local thick = math.min(s.X, s.Y, s.Z) * 0.5 + 16
		if dist >= thick + 8 then
			return nil, 0
		end
		local push = (thick + RUBRICATUS_DODGE_CLEAR) - dist
		push = math.clamp(push, 0, RUBRICATUS_DODGE_MAX_PUSH)
		if push < 2 then
			return nil, 0
		end
		return Vector3.new(origin.X + px * push, origin.Y, origin.Z + pz * push), push
	end

	local function rubricatusBoxPush(part, origin)
		if not part or not part:IsA('BasePart') then
			return nil, 0
		end
		local rel = part.CFrame:PointToObjectSpace(origin)
		local hx = part.Size.X * 0.5 + 8
		local hz = part.Size.Z * 0.5 + 8
		if math.abs(rel.X) > hx or math.abs(rel.Z) > hz then
			return nil, 0
		end
		local outX = hx - math.abs(rel.X)
		local outZ = hz - math.abs(rel.Z)
		local localPush
		if outX <= outZ then
			localPush = Vector3.new((rel.X >= 0 and 1 or -1) * (outX + 6), 0, 0)
		else
			localPush = Vector3.new(0, 0, (rel.Z >= 0 and 1 or -1) * (outZ + 6))
		end
		local world = part.CFrame:VectorToWorldSpace(localPush)
		local flat = Vector3.new(world.X, 0, world.Z)
		if flat.Magnitude < 0.05 then
			return nil, 0
		end
		local push = math.clamp(flat.Magnitude, 2.5, RUBRICATUS_DODGE_MAX_PUSH)
		local dir = flat.Unit
		return Vector3.new(origin.X + dir.X * push, origin.Y, origin.Z + dir.Z * push), push
	end

	local function rubricatusLimitStep(hrpPos, goal, fightY, keepFlat)
		if typeof(goal) ~= 'Vector3' then
			return nil
		end
		local dx = goal.X - hrpPos.X
		local dz = goal.Z - hrpPos.Z
		local m = math.sqrt(dx * dx + dz * dz)
		if m < 0.05 then
			return nil
		end
		if m > RUBRICATUS_DODGE_MAX_PUSH then
			local s = RUBRICATUS_DODGE_MAX_PUSH / m
			dx *= s
			dz *= s
		end
		local dest = Vector3.new(hrpPos.X + dx, fightY, hrpPos.Z + dz)
		if typeof(keepFlat) == 'Vector3' then
			local away = Vector3.new(dest.X - keepFlat.X, 0, dest.Z - keepFlat.Z)
			if away.Magnitude > RUBRICATUS_KEEP_RANGE then
				away = away.Unit * RUBRICATUS_KEEP_RANGE
				dest = Vector3.new(keepFlat.X + away.X, fightY, keepFlat.Z + away.Z)
			end
		end
		return dest
	end

	local function rubricatusArenaBeam(beam)
		if not beam:IsA('Beam') or beam.Enabled ~= true then
			return false
		end
		if beam.Width0 < 0.12 then
			return false
		end
		local n = string.lower(tostring(beam.Name))
		if string.find(n, 'lightning', 1, true)
			or string.find(n, 'crimson', 1, true)
			or string.find(n, 'red', 1, true)
			or string.find(n, 'laser', 1, true)
			or string.find(n, 'beam', 1, true)
			or string.find(n, 'slash', 1, true)
			or string.find(n, 'rift', 1, true)
		then
			return true
		end
		if beam.Width0 >= 0.85 then
			return true
		end
		local a0, a1 = beam.Attachment0, beam.Attachment1
		if a0 and a1 then
			local span = (a0.WorldPosition - a1.WorldPosition).Magnitude
			if span >= 60 then
				return true
			end
		end
		return false
	end

	local function rubricatusCollectThreats(hrpPos)
		local threats = {}
		local playerFlat = flatXZ(hrpPos)
		local char = getMyCharacterModel() or LocalPlayer.Character
		-- Map light shafts (Workspace.Model) and red mob body parts read as lasers / telegraphs
		-- and shoved you 16 studs every few frames. Mob children only count when named like an attack.
		local candidates = {}
		local scanned = 0
		local roots = workspace:GetChildren()
		for i = #roots, 1, -1 do
			local root = roots[i]
			if BEAM_SKIP_ROOT[root.Name] or root == char then
				continue
			end
			local fromMobs = root.Name == 'Mobs'
			if not fromMobs then
				candidates[#candidates + 1] = root
			end
			for _, d in ipairs(root:GetDescendants()) do
				scanned += 1
				if scanned > 6500 then
					break
				end
				if fromMobs then
					local n = string.lower(d.Name)
					local pn = d.Parent and string.lower(tostring(d.Parent.Name)) or ''
					if not (
						string.find(n, 'lightning', 1, true)
						or string.find(n, 'laser', 1, true)
						or string.find(n, 'disc', 1, true)
						or string.find(n, 'circle', 1, true)
						or string.find(n, 'slam', 1, true)
						or string.find(n, 'swing', 1, true)
						or string.find(n, 'hitbox', 1, true)
						or string.find(n, 'warning', 1, true)
						or string.find(pn, 'disc', 1, true)
						or string.find(pn, 'lightning', 1, true)
					) then
						continue
					end
				end
				candidates[#candidates + 1] = d
			end
			if scanned > 6500 then
				break
			end
		end
		for _, d in ipairs(candidates) do
			if rubricatusArenaBeam(d) then
				threats[#threats + 1] = { kind = 'beam', beam = d }
			end
			if not d:IsA('BasePart') then
				continue
			end
			local n = string.lower(d.Name)
			if isRubricatusNukeCoverPart(d) or (d.Parent and d.Parent ~= workspace and isRubricatusNukeCoverPart(d.Parent)) then
				continue
			end
			local flat = flatXZ(d.Position)
			local near = (flat - playerFlat).Magnitude
			local falling = n == 'fallingpointedstone'
				or n == 'stonefragment'
				or string.find(n, 'pointedstone', 1, true)
				or string.find(n, 'falling', 1, true)
				or string.find(n, 'rock', 1, true)
				or string.find(n, 'boulder', 1, true)
				or string.find(n, 'stone', 1, true)
				or d:IsA('WedgePart')
			if falling and d.Position.Y > hrpPos.Y - 30 and near < 72 then
				local land = flat
				local vy = d.AssemblyLinearVelocity.Y
				if vy < -2 and d.Position.Y > hrpPos.Y then
					local t = (d.Position.Y - hrpPos.Y) / math.max(-vy, 6)
					t = math.clamp(t, 0, 2.5)
					land = flat + flatXZ(d.AssemblyLinearVelocity) * t
				end
				threats[#threats + 1] = {
					kind = 'point',
					flat = land,
					radius = math.max(18, math.max(d.Size.X, d.Size.Z) * 0.55 + 12),
				}
				continue
			end
			local pn = d.Parent and string.lower(tostring(d.Parent.Name)) or ''
			local spanXZ = math.max(d.Size.X, d.Size.Z)
			local isLightning = string.find(n, 'lightning', 1, true)
				or string.find(n, 'stomp', 1, true)
				or string.find(pn, 'lightning', 1, true)
				or string.find(pn, 'stomp', 1, true)
			local roundish = math.abs(d.Size.X - d.Size.Z) <= math.max(6, spanXZ * 0.2)
			if isLightning or n == 'circle' or (n == 'effecthitbox' and roundish and spanXZ >= 28) then
				if near < 160 then
					threats[#threats + 1] = {
						kind = 'point',
						flat = flat,
						radius = math.clamp(spanXZ * 0.5 + 20, 22, 72),
					}
				end
				continue
			end
			if n == 'box' or (n == 'effecthitbox' and spanXZ >= 18) then
				threats[#threats + 1] = { kind = 'box', part = d }
				continue
			end
			local icicle = string.find(n, 'spike', 1, true)
				or string.find(n, 'icicle', 1, true)
				or string.find(n, 'disc', 1, true)
				or string.find(pn, 'disc', 1, true)
				or n == 'effecthitbox'
			if icicle and near < 120 then
				threats[#threats + 1] = {
					kind = 'point',
					flat = flat,
					radius = math.clamp(spanXZ * 0.5 + 14, 16, 56),
				}
				continue
			end
			if rubricatusIsRedPart(d) then
				local long = math.max(d.Size.X, d.Size.Y, d.Size.Z)
				local thin = math.min(d.Size.X, d.Size.Y, d.Size.Z)
				if long >= 14 and thin <= 12 and (d.Material == Enum.Material.Neon or long >= 36) then
					threats[#threats + 1] = { kind = 'line', part = d }
				elseif near < 150 then
					local warn = n == 'fill'
						or string.find(n, 'warning', 1, true)
						or string.find(n, 'ring', 1, true)
						or (d.Parent and d.Parent.Name == 'RedGroundWarning')
					if warn or long >= 6 then
						threats[#threats + 1] = {
							kind = 'point',
							flat = flat,
							radius = math.min(24, math.max(14, long * 0.25 + spanXZ * 0.2 + 8)),
						}
					end
				end
			end
		end
		return threats
	end

	local function rubricatusThreatsCached(hrpPos, now)
		if now - rubricatusThreatScanAt >= 0.08 then
			rubricatusThreatScanAt = now
			rubricatusThreatCache = rubricatusCollectThreats(hrpPos)
		end
		return rubricatusThreatCache or {}
	end

	local function rubricatusResolveThreats(hrpPos, fightY, threats)
		local origin = Vector3.new(hrpPos.X, fightY, hrpPos.Z)
		local playerFlat = flatXZ(origin)
		if #threats == 0 then
			return nil
		end
		local lastDir = getgenv().SB2RubricatusLastDir
		if typeof(lastDir) ~= 'Vector3' then
			lastDir = nil
		end
		local function minClear(x, z)
			local best = 80
			local here = Vector3.new(x, fightY, z)
			for i = 1, #threats do
				local t = threats[i]
				local d = 80
				if t.kind == 'point' and t.flat then
					local dx, dz = x - t.flat.X, z - t.flat.Z
					d = math.sqrt(dx * dx + dz * dz) - t.radius
				elseif t.kind == 'beam' and t.beam then
					local a0, a1 = t.beam.Attachment0, t.beam.Attachment1
					if a0 and a1 then
						local dist = segDistXZ(here, a0.WorldPosition, a1.WorldPosition)
						d = dist - (math.max(t.beam.Width0 * 0.5, 1.2) + 8)
					end
				elseif t.kind == 'line' and t.part then
					local _, push = rubricatusLaserLinePush(t.part, here)
					if push and push > 0 then
						d = -push
					else
						d = 12
					end
				elseif t.kind == 'box' and t.part then
					local rel = t.part.CFrame:PointToObjectSpace(here)
					local hx = t.part.Size.X * 0.5 + 8
					local hz = t.part.Size.Z * 0.5 + 8
					local ox = math.abs(rel.X) - hx
					local oz = math.abs(rel.Z) - hz
					if ox >= 0 or oz >= 0 then
						d = math.max(ox, 0) + math.max(oz, 0)
					else
						d = math.max(ox, oz)
					end
				end
				if d < best then
					best = d
				end
			end
			return best
		end
		local hereClear = minClear(playerFlat.X, playerFlat.Z)
		if hereClear >= 6 then
			getgenv().SB2RubricatusLastDir = nil
			return nil
		end
		local bestSafe, bestScore = nil, -1e9
		for i = 0, 23 do
			local ang = i * math.pi * 2 / 24
			local ux, uz = math.cos(ang), math.sin(ang)
			local reversePen = 0
			if lastDir then
				local dot = ux * lastDir.X + uz * lastDir.Z
				if dot < -0.12 then
					reversePen = 28
				else
					reversePen = -8 * math.max(0, dot)
				end
			end
			for di = 1, 6 do
				local dist = 10 + di * 10
				local cx = playerFlat.X + ux * dist
				local cz = playerFlat.Z + uz * dist
				local clear = minClear(cx, cz)
				local score = clear * 4 + dist * 0.12 - reversePen
				if clear > hereClear + 1.5 and score > bestScore then
					bestScore = score
					bestSafe = Vector3.new(cx, fightY, cz)
				end
			end
		end
		if not bestSafe or bestScore < -1e8 then
			return nil
		end
		local mv = Vector3.new(bestSafe.X - playerFlat.X, 0, bestSafe.Z - playerFlat.Z)
		if mv.Magnitude > 0.25 then
			getgenv().SB2RubricatusLastDir = mv.Unit
		end
		return bestSafe
	end

	-- Rubricatus melee swings / slam. Each one spawns a "Box" hitbox tagged "<Mob> Attack" or
	-- "<Mob> Slam". The hit lands after the Box's Lifetime (Attack) or 0.3 / AttackSpeed (Slam).
	-- The general threat scan only polls, and the pillar cover window skipped it entirely,
	-- so swings were landing. This tracks boxes the moment they spawn and steps out over
	-- the nearest edge. Lives in a do-block + getgenv(): this function is at Luau's
	-- 200-local cap, so it must not add a top-level local.
	do
	local RubSwing = { boxes = {} }
	getgenv().SB2RubSwing = RubSwing
	do
		local CS = game:GetService('CollectionService')
		local function track(part, slam)
			if typeof(part) ~= 'Instance' or not part:IsA('BasePart') or part.Name ~= 'Box' then
				return
			end
			if RubSwing.boxes[part] then
				return
			end
			RubSwing.boxes[part] = { born = os.clock(), slam = slam == true }
		end
		for _, old in ipairs(getgenv().SB2RubSwingConns or {}) do
			pcall(function()
				old:Disconnect()
			end)
		end
		local conns = {}
		local function hookTag(tag, slam)
			conns[#conns + 1] = CS:GetInstanceAddedSignal(tag):Connect(function(inst)
				track(inst, slam)
			end)
			for _, inst in ipairs(CS:GetTagged(tag)) do
				track(inst, slam)
			end
		end
		hookTag('Rubricatus Attack', false)
		hookTag('Rubricatus Slam', true)
		-- Fallback if the boss name / tag differs: any Box tagged "... Attack" / "... Slam"
		-- or carrying an AttackState attribute.
		conns[#conns + 1] = workspace.ChildAdded:Connect(function(inst)
			if inst.Name ~= 'Box' or not inst:IsA('BasePart') then
				return
			end
			task.defer(function()
				if RubSwing.boxes[inst] or not inst.Parent then
					return
				end
				local kind = nil
				pcall(function()
					for _, t in ipairs(inst:GetTags()) do
						local lt = string.lower(t)
						if string.sub(lt, -7) == ' attack' then
							kind = 'attack'
						elseif string.sub(lt, -5) == ' slam' then
							kind = 'slam'
						end
					end
				end)
				if kind or inst:GetAttribute('AttackState') ~= nil then
					track(inst, kind == 'slam')
				end
			end)
		end)
		getgenv().SB2RubSwingConns = conns
	end

	-- Live boxes (purges finished ones) and an "is this spot inside any box" test.
	function RubSwing.live(now)
		local list = {}
		for part, e in pairs(RubSwing.boxes) do
			local speed = tonumber(part:GetAttribute('AttackSpeed')) or 1
			local life = tonumber(part:GetAttribute('Lifetime'))
			local hitIn = e.slam and (0.3 / math.max(speed, 0.1)) or (life or 0.9)
			if not part.Parent or now > e.born + hitIn + 0.45 then
				RubSwing.boxes[part] = nil
			else
				list[#list + 1] = part
			end
		end
		return list
	end

	function RubSwing.insideAny(list, x, z, margin)
		for i = 1, #list do
			local p = list[i]
			local rel = p.CFrame:PointToObjectSpace(Vector3.new(x, p.Position.Y, z))
			if math.abs(rel.X) <= p.Size.X * 0.5 + margin and math.abs(rel.Z) <= p.Size.Z * 0.5 + margin then
				return p
			end
		end
		return nil
	end

	function RubSwing.blocks(pos, now)
		if typeof(pos) ~= 'Vector3' then
			return false
		end
		return RubSwing.insideAny(RubSwing.live(now), pos.X, pos.Z, 3) ~= nil
	end

	-- Exit spot when standing in a live box, else nil. `prefer` (cover spot) biases the pick.
	function RubSwing.escape(hrpPos, fightY, now, prefer)
		local list = RubSwing.live(now)
		if #list == 0 or not RubSwing.insideAny(list, hrpPos.X, hrpPos.Z, 4) then
			return nil
		end
		local best, bestScore = nil, math.huge
		local function consider(x, z)
			if RubSwing.insideAny(list, x, z, 3) then
				return
			end
			local dx, dz = x - hrpPos.X, z - hrpPos.Z
			local score = math.sqrt(dx * dx + dz * dz)
			if typeof(prefer) == 'Vector3' then
				local px, pz = x - prefer.X, z - prefer.Z
				score += 0.6 * math.sqrt(px * px + pz * pz)
			end
			if score < bestScore then
				best, bestScore = Vector3.new(x, fightY, z), score
			end
		end
		for i = 1, #list do
			local p = list[i]
			local rel = p.CFrame:PointToObjectSpace(Vector3.new(hrpPos.X, p.Position.Y, hrpPos.Z))
			local hx, hz = p.Size.X * 0.5, p.Size.Z * 0.5
			if math.abs(rel.X) <= hx + 4 and math.abs(rel.Z) <= hz + 4 then
				for _, side in ipairs({
					Vector3.new(hx + 9, 0, rel.Z),
					Vector3.new(-(hx + 9), 0, rel.Z),
					Vector3.new(rel.X, 0, hz + 9),
					Vector3.new(rel.X, 0, -(hz + 9)),
				}) do
					local w = p.CFrame:PointToWorldSpace(Vector3.new(side.X, 0, side.Z))
					consider(w.X, w.Z)
				end
			end
		end
		if not best then
			-- Overlapping boxes: ring search for the nearest clear spot.
			for di = 2, 10 do
				for a = 0, 23 do
					local ang = a * math.pi / 12
					consider(hrpPos.X + math.cos(ang) * di * 10, hrpPos.Z + math.sin(ang) * di * 10)
				end
				if best then
					break
				end
			end
		end
		return best
	end
	end

	local function rubricatusGeneralDodgeGoal(hrpPos, fightY, bossMob, now)
		local keepFlat = bossMob and lastRubricatusFlat or nil
		local laserOut = getgenv().SB2RedLaser and getgenv().SB2RedLaser.escape(hrpPos, nil)
		if laserOut then
			return rubricatusLimitStep(hrpPos, Vector3.new(laserOut.X, fightY, laserOut.Z), fightY, nil)
		end
		local threats = rubricatusThreatsCached(hrpPos, now or os.clock())
		local resolved = rubricatusResolveThreats(hrpPos, fightY, threats)
		if resolved then
			return rubricatusLimitStep(hrpPos, resolved, fightY, nil)
		end
		local findGoal = getgenv().SB2FindFloorCircleDodgeGoal
		if type(findGoal) == 'function' then
			local g = findGoal(hrpPos, fightY, nil)
			if g then
				return rubricatusLimitStep(hrpPos, Vector3.new(g.X, fightY, g.Z), fightY, keepFlat)
			end
		end
		local beam = beamDodgeGoal(hrpPos)
		if beam then
			return rubricatusLimitStep(hrpPos, Vector3.new(beam.X, fightY, beam.Z), fightY, keepFlat)
		end
		return nil
	end

	-- Rubricatus has to be fought on the floor; any leftover hover height is dropped.
	local function rubricatusFightY(hrp)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local ignore = { hrp.Parent }
		local mobs = workspace:FindFirstChild('Mobs')
		if mobs then
			table.insert(ignore, mobs)
		end
		params.FilterDescendantsInstances = ignore
		params.RespectCanCollide = true
		local standOff = humanoidHip(hrp) + hrp.Size.Y * 0.5
		local hit = workspace:Raycast(hrp.Position + Vector3.new(0, 8, 0), Vector3.new(0, -600, 0), params)
		if hit then
			return hit.Position.Y + standOff
		end
		local wd = workspace:FindFirstChild('WaveDefenseStuff')
		local origin = wd and wd:FindFirstChild('WaveDefenseOrigin')
		if origin and origin:IsA('BasePart') then
			return origin.Position.Y + origin.Size.Y * 0.5 + standOff
		end
		return hrp.Position.Y
	end

	local function rubricatusStandBehind(entry, bossFlat, fightY)
		local ph = entry.flat
		local bh = ph - bossFlat
		local bhMag = bh.Magnitude
		if bhMag < 2 then
			return Vector3.new(ph.X, fightY, ph.Z)
		end
		-- Stand just OUTSIDE the pillar's back face, not inside it. Inside its body the hold got
		-- shoved up onto the top (exposed above it: one-shot at wave 100 Elite), and a ray that
		-- starts inside a part never hits that part, so the pillar may not count as cover at all.
		local inset = entry.halfW + PILLAR_BEHIND_OFFSET + 1.5
		local stand = ph + (bh / bhMag) * inset
		return Vector3.new(stand.X, fightY, stand.Z)
	end

	-- Shadowed = the boss→player line passes through the pillar body, with the pillar between.
	local function rubricatusShadowedBy(bossFlat, playerFlat, entry)
		local seg = playerFlat - bossFlat
		local len = seg.Magnitude
		if len < 2 then
			return false
		end
		local dir = seg / len
		local t = (entry.flat - bossFlat):Dot(dir)
		if t <= 0 or t >= len then
			return false
		end
		local perp = (entry.flat - (bossFlat + dir * t)).Magnitude
		return perp <= math.max(entry.halfW - PILLAR_SHADOW_MARGIN, 1.2)
			and (playerFlat - entry.flat).Magnitude <= entry.halfW + PILLAR_BEHIND_OFFSET + 4
	end

	-- Above the pillar top the boss still sees you, so cover height must sit inside its span.
	local function rubricatusCoverY(entry, currentY)
		local lo = entry.bottom + PILLAR_BASE_CLEAR
		local hi = entry.top - PILLAR_TOP_CLEAR
		if hi < lo then
			return (entry.bottom + entry.top) * 0.5
		end
		return math.clamp(currentY, lo, hi)
	end

	local function rubricatusPillarCoverGoal(hrpPos, fightY, bossMob)
		bossMob = bossMob or findRubricatusMob()
		-- He can die with a nuke still charging: hide from where he last stood.
		local deadFlat = (not bossMob) and typeof(lastRubricatusFlat) == 'Vector3' and lastRubricatusFlat or nil
		if not bossMob and not deadFlat then
			rubricatusCoverPart = nil
			rubricatusCoverGoalFlat = nil
			return nil
		end
		local bossFlat = deadFlat or rubricatusBossFlat(bossMob)
		if not bossFlat then
			return nil
		end
		fightY = tonumber(fightY) or hrpPos.Y
		local playerFlat = flatXZ(hrpPos)
		local pillars = collectRubricatusPillars(playerFlat, 480)
		if #pillars == 0 then
			rubricatusCoverPart = nil
			rubricatusCoverGoalFlat = nil
			return nil
		end

		-- Prefer the nearest pillar to you. Locked far leftovers sent you 150 studs off.
		local pick = nil
		if rubricatusCoverPart then
			for i = 1, #pillars do
				if pillars[i].part == rubricatusCoverPart then
					local lockedDist = (pillars[i].flat - playerFlat).Magnitude
					local nearer = false
					for j = 1, #pillars do
						if (pillars[j].flat - playerFlat).Magnitude + 12 < lockedDist then
							nearer = true
							break
						end
					end
					if not nearer then
						pick = pillars[i]
					end
					break
				end
			end
		end
		if not pick then
			local bestRun = nil
			for i = 1, #pillars do
				local run = (pillars[i].flat - playerFlat).Magnitude
				if not bestRun or run < bestRun then
					bestRun = run
					pick = pillars[i]
				end
			end
		end
		if not pick then
			rubricatusCoverPart = nil
			rubricatusCoverGoalFlat = nil
			return nil
		end
		rubricatusCoverPart = pick.part
		-- The blast goes off at floor level (Y~27). At the pillar's base (v14) it killed you; high
		-- inside it (Y~68, v13) you took nothing. Sit at the middle of the pillar's height.
		local coverY = rubricatusCoverY(pick, (pick.bottom + pick.top) * 0.5)
		if rubricatusShadowedBy(bossFlat, playerFlat, pick) and math.abs(hrpPos.Y - coverY) < 4 then
			rubricatusCoverGoalFlat = playerFlat
			return Vector3.new(hrpPos.X, coverY, hrpPos.Z)
		end
		local stand = rubricatusStandBehind(pick, bossFlat, coverY)
		if not stand then
			return nil
		end
		if (flatXZ(stand) - pick.flat).Magnitude > 18 then
			stand = Vector3.new(pick.flat.X, coverY, pick.flat.Z)
		end
		rubricatusCoverGoalFlat = flatXZ(stand)
		return stand
	end

	local function rubricatusReengageGoal(hrpPos, fightY, bossMob)
		local bossFlat = rubricatusBossFlat(bossMob)
		if not bossFlat then
			return nil
		end
		local away = Vector3.new(hrpPos.X - bossFlat.X, 0, hrpPos.Z - bossFlat.Z)
		if away.Magnitude <= 16 then
			return nil
		end
		if away.Magnitude < 0.05 then
			away = Vector3.new(0, 0, -1)
		else
			away = away.Unit
		end
		return Vector3.new(bossFlat.X + away.X * RUBRICATUS_ENGAGE, fightY, bossFlat.Z + away.Z * RUBRICATUS_ENGAGE)
	end

	local function waveDefenseRiftsCenterFlat()
		local wd = workspace:FindFirstChild('WaveDefenseStuff')
		local rifts = wd and wd:FindFirstChild('WaveDefenseRifts')
		if not rifts then
			return nil
		end
		local sx, sz, n = 0, 0, 0
		for _, child in ipairs(rifts:GetChildren()) do
			if child:IsA('BasePart') and child.Name == 'Spawn' then
				sx += child.Position.X
				sz += child.Position.Z
				n += 1
			end
		end
		if n < 4 then
			return nil
		end
		return Vector3.new(sx / n, 0, sz / n)
	end

	local function waveDefenseSpecialUiState()
		local incoming = false
		local active = false
		local pg = LocalPlayer:FindFirstChild('PlayerGui')
		if not pg then
			return incoming, active
		end
		local scanned = 0
		for _, d in ipairs(pg:GetDescendants()) do
			scanned += 1
			if scanned > 3200 then
				break
			end
			if not (d:IsA('TextLabel') or d:IsA('TextButton')) or not d.Visible then
				continue
			end
			local t = string.lower(tostring(d.Text or ''):gsub('%s+', ' '))
			if t == '' then
				continue
			end
			if string.find(t, 'incoming special wave', 1, true) then
				incoming = true
			end
			if string.find(t, 'wave key', 1, true)
				or string.find(t, 'wave skip', 1, true)
				or string.find(t, 'wave defense booster', 1, true)
				or string.find(t, 'preview specialalias', 1, true)
				or #t > 48
			then
				continue
			end
			if (string.find(t, 'special wave', 1, true) or string.find(t, 'rift wave', 1, true))
				and not string.find(t, 'incoming', 1, true)
			then
				active = true
			end
		end
		return incoming, active
	end

	local function waveDefenseRiftsPortalsOpen()
		local wd = workspace:FindFirstChild('WaveDefenseStuff')
		local rifts = wd and wd:FindFirstChild('WaveDefenseRifts')
		if not rifts then
			return false
		end
		for _, child in ipairs(rifts:GetChildren()) do
			if child.Name ~= 'Spawn' then
				return true
			end
		end
		for _, d in ipairs(rifts:GetDescendants()) do
			if not d:IsA('BasePart') then
				continue
			end
			if d.Name == 'Spawn' and d.Transparency >= 0.98 then
				continue
			end
			if d.Transparency < 0.88 then
				return true
			end
		end
		return false
	end

	local function waveDefenseRiftMobsAlive()
		local mobs = workspace:FindFirstChild('Mobs')
		if not mobs then
			return false
		end
		for _, mob in ipairs(mobs:GetChildren()) do
			if mob.Name == 'Rift' and not mob:FindFirstChild('Died') then
				local hum = mob:FindFirstChildOfClass('Humanoid')
				if not hum or hum.Health > 0 then
					return true
				end
			end
		end
		return false
	end

	local function waveDefenseRiftsActive()
		if not isWdWaveInstance() then
			return false
		end
		if not waveDefenseRiftsCenterFlat() then
			return false
		end
		if waveDefenseRiftMobsAlive() then
			return true
		end
		local incoming, uiActive = waveDefenseSpecialUiState()
		if incoming then
			return false
		end
		local cd = workspace:GetAttribute('WaveCountdown')
		if incoming ~= true and typeof(cd) == 'number' and cd > 0 and not uiActive then
			-- Between waves — not the 4-rift special yet.
			return false
		end
		local portals = waveDefenseRiftsPortalsOpen()
		if uiActive or portals then
			return true
		end
		-- UI strings change; four Spawn anchors + active WD run is enough to hop.
		if typeof(cd) ~= 'number' or cd <= 0 then
			return true
		end
		return false
	end

	local function waveDefenseRiftSpawnDirs(center)
		local wd = workspace:FindFirstChild('WaveDefenseStuff')
		local rifts = wd and wd:FindFirstChild('WaveDefenseRifts')
		if not rifts then
			return nil
		end
		local dirs = {}
		for _, child in ipairs(rifts:GetChildren()) do
			if child:IsA('BasePart') and child.Name == 'Spawn' then
				local flat = Vector3.new(child.Position.X - center.X, 0, child.Position.Z - center.Z)
				if flat.Magnitude > 1 then
					dirs[#dirs + 1] = flat.Unit
				end
			end
		end
		-- Stable clockwise order so the cycle sweeps around instead of jumping across.
		table.sort(dirs, function(a, b)
			return math.atan2(a.Z, a.X) < math.atan2(b.Z, b.X)
		end)
		return #dirs > 0 and dirs or nil
	end

	local function waveDefenseRiftHopGoal(fightY, now, lean)
		local center = waveDefenseRiftsCenterFlat()
		if not center then
			return nil
		end
		local dirs = waveDefenseRiftSpawnDirs(center)
		if not dirs then
			return nil
		end
		local n = #dirs
		riftHopIndex = (math.floor(now / RIFT_HOP_INTERVAL) % n) + 1
		riftHopAt = now
		local dir = dirs[math.clamp(riftHopIndex, 1, n)]
		local dist = tonumber(lean) or RIFT_HOP_LEAN
		return Vector3.new(center.X + dir.X * dist, fightY, center.Z + dir.Z * dist)
	end

	local function wdCurrentWave()
		local v = workspace:GetAttribute('Wave')
		if typeof(v) == 'number' and v >= 1 then
			return math.floor(v)
		end
		local wd = workspace:FindFirstChild('WaveDefenseStuff')
		if wd then
			v = wd:GetAttribute('Wave') or wd:GetAttribute('WaveNumber') or wd:GetAttribute('CurrentWave')
			if typeof(v) == 'number' and v >= 1 then
				return math.floor(v)
			end
		end
		return nil
	end

	local function wdArenaFightY(hrp)
		if typeof(getgenv().SB2LavaFightY) == 'number' then
			return getgenv().SB2LavaFightY
		end
		if hrp then
			return math.clamp(hrp.Position.Y, WD_LAVA_FLOOR_Y + 4, WD_LAVA_FLOOR_Y + 18)
		end
		return WD_LAVA_FLOOR_Y + 8
	end

	local function textIsBob(text)
		local key = string.gsub(string.lower(tostring(text or '')), '[%p%s]+', '')
		if key == '' then
			return false
		end
		if key == 'bob' then
			return true
		end
		-- Nameplate often arrives before Entity.Health replicates (0 HP = false dead).
		return string.sub(key, 1, 3) == 'bob' and string.find(key, 'bobbin', 1, true) == nil
	end
	getgenv().SB2AFD_textIsBob = textIsBob -- used by code above its definition

	local function bobMobAlive(mob)
		if not mob or not mob.Parent then
			return false
		end
		if mob:GetAttribute('Died') == true then
			return false
		end
		local ent = mob:FindFirstChild('Entity')
		if ent and ent:GetAttribute('Died') == true then
			return false
		end
		local hum = mob:FindFirstChildOfClass('Humanoid')
		if hum and hum.Health <= 0 then
			return false
		end
		return true
	end

	local function findBobMob()
		local folder = workspace:FindFirstChild('Mobs')
		if not folder then
			return nil
		end
		for _, name in ipairs({ 'Bob', 'BOB' }) do
			local direct = folder:FindFirstChild(name)
			if direct and bobMobAlive(direct) then
				return direct
			end
		end
		for _, mob in ipairs(folder:GetChildren()) do
			if not bobMobAlive(mob) then
				continue
			end
			if textIsBob(mob.Name) then
				return mob
			end
			local plate = mob:FindFirstChild('Nameplate')
			local label = plate and plate:FindFirstChildWhichIsA('TextLabel', true)
			if label and textIsBob(label.Text) then
				return mob
			end
		end
		return nil
	end

	local function bossBarBobActive()
		local pg = LocalPlayer:FindFirstChild('PlayerGui')
		if not pg then
			return false
		end
		local bars = pg:FindFirstChild('BossHealthBars', true)
		if not bars then
			return false
		end
		for _, desc in ipairs(bars:GetDescendants()) do
			if desc:IsA('TextLabel') and desc.Visible and textIsBob(desc.Text) then
				return true
			end
		end
		return false
	end

	-- Air holds (lava, Bob, boss hover) park at arena center so killaura reaches the whole wave.
	-- A sidestep pauses recentering briefly so the dodge is not undone the next tick.
	-- Leftover ledge / rim mobs: walk onto them with writeHeldCF (never event-dive blink).
	local AIR_DODGE_HOLD = 1.5
	local AIR_RECENTER_MIN = 4
	local STRIKE_REACH = 20
	local STRIKE_ABOVE = 6
	local STRIKE_STEP = 48
	local STRIKE_Y_SLACK = 16
	local airDodgeUntil = 0
	local strikeBossPos = nil

	local function noteAirDodge(now)
		airDodgeUntil = (now or os.clock()) + AIR_DODGE_HOLD
	end

	-- Normal jumps/falls must never be recentered (snapping mid-air = jitter + slow fall).
	-- Only a body parked well above the floor, not falling, with no move input, counts.
	local AIR_STUCK_MIN_HEIGHT = 12
	local AIR_STUCK_MAX_VY = 3

	local function airStuckHovering(hrp)
		local hum = hrp.Parent and hrp.Parent:FindFirstChildOfClass('Humanoid')
		if hum and hum.MoveDirection.Magnitude > 0.1 then
			return false
		end
		if math.abs(hrp.AssemblyLinearVelocity.Y) > AIR_STUCK_MAX_VY then
			return false
		end
		local gy = groundYAt(hrp)
		if not gy then
			return false
		end
		return hrp.Position.Y - gy - humanoidHip(hrp) - hrp.Size.Y * 0.5 >= AIR_STUCK_MIN_HEIGHT
	end

	-- Hit knockups look like a jump (Freefall + upward speed). The old check ignored
	-- anything faster than a small hop, so normal attacks carried you into the air.
	-- Lava, Bob's perch, and Rubricatus cover still own Y.
	local function unstickIdleFreefall(hrp)
		if getgenv().SB2BobEscapeActive == true then
			return
		end
		if getgenv().SB2RubricatusSurviveActive == true or typeof(getgenv().SB2RubricatusCoverPos) == 'Vector3' then
			return
		end
		local fightY = getgenv().SB2LavaFightY
		if getgenv().SB2LavaEscapeActive == true and typeof(fightY) == 'number' and hrp.Position.Y > fightY - 20 then
			return
		end
		local hum = hrp.Parent and hrp.Parent:FindFirstChildOfClass('Humanoid')
		if not hum then
			return
		end
		local vel = hrp.AssemblyLinearVelocity
		local gy = groundYAt(hrp)
		if not gy then
			return
		end
		local standY = gy + humanoidHip(hrp) + hrp.Size.Y * 0.5 + 0.15
		local above = hrp.Position.Y - standY
		if above <= 2.5 and vel.Y <= 8 then
			return
		end
		for _, d in ipairs(hrp:GetChildren()) do
			local cls = d.ClassName
			if cls == 'BodyVelocity' and d.Velocity.Y > 0 then
				d.Velocity = Vector3.new(d.Velocity.X, 0, d.Velocity.Z)
			elseif cls == 'LinearVelocity' and d.VectorVelocity.Y > 0 then
				d.VectorVelocity = Vector3.new(d.VectorVelocity.X, 0, d.VectorVelocity.Z)
			elseif cls == 'VectorForce' and d.Force.Y > 0 then
				d.Force = Vector3.new(d.Force.X, 0, d.Force.Z)
			end
		end
		getgenv().SB2AnchorLockCF = nil
		local look = hrp.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		local dest = Vector3.new(hrp.Position.X, standY, hrp.Position.Z)
		if flat.Magnitude >= 0.08 then
			hrp.CFrame = CFrame.lookAt(dest, dest + flat.Unit)
		else
			hrp.CFrame = CFrame.new(dest)
		end
		hrp.AssemblyLinearVelocity = Vector3.zero
		hrp.AssemblyAngularVelocity = Vector3.zero
		pcall(function()
			hum:ChangeState(Enum.HumanoidStateType.Landed)
		end)
		pcall(function()
			hum:ChangeState(Enum.HumanoidStateType.Running)
		end)
	end

	local function mobStrikePos(mob)
		if not mob or mobIsDead(mob) then
			return nil
		end
		local part = mob:FindFirstChild('HumanoidRootPart')
		if not (part and part:IsA('BasePart')) then
			part = mob.PrimaryPart
		end
		if not (part and part:IsA('BasePart')) then
			part = mob:FindFirstChildWhichIsA('BasePart')
		end
		if part and part:IsA('BasePart') then
			return part.Position
		end
		return nil
	end
	getgenv().SB2AFD_mobStrikePos = mobStrikePos -- used by code above its definition

	local function refreshStrikeBossPos(hrp)
		strikeBossPos = nil
		getgenv().SB2StrikeBossPos = nil
		if not hrp then
			return nil
		end
		local folder = workspace:FindFirstChild('Mobs')
		if not folder then
			return nil
		end
		local meleeSq = STRIKE_REACH * STRIKE_REACH
		local tracked = getgenv().SB2WaveKillTargetTracked
		local inMelee = false
		local bestP, bestD = nil, nil
		local trackedP = nil
		local highP, highY = nil, nil
		local namedP, namedD = nil, nil
		for _, mob in ipairs(folder:GetChildren()) do
			if mobIsDead(mob) then
				continue
			end
			local n = string.lower(tostring(mob.Name))
			if string.find(n, 'chest', 1, true) or string.find(n, 'reward', 1, true) then
				continue
			end
			local p = mobStrikePos(mob)
			if not p then
				continue
			end
			local named = mobIsNamedWdBoss(mob) or textIsBob(mob.Name)
			local fightY = p.Y + STRIKE_ABOVE
			local plate = mob:FindFirstChild('Nameplate')
			local label = plate and plate:FindFirstChildWhichIsA('TextLabel', true)
			local flying = nameWantsAirHover(mob.Name)
				or (label and nameWantsAirHover(label.Text))
				or (named and p.Y > 60 and not textIsBob(mob.Name))
			if flying then
				fightY = math.max(
					aeganatosHeadTopY(mob) or (p.Y + 24),
					WD_LAVA_FLOOR_Y + BOSS_CLEARANCE
				)
			end
			local stand = Vector3.new(p.X, fightY, p.Z)
			local dx = p.X - hrp.Position.X
			local dz = p.Z - hrp.Position.Z
			local dy = math.abs(fightY - hrp.Position.Y)
			local dsq = dx * dx + dz * dz
			if flying then
				if not highY or fightY > highY then
					highP, highY = stand, fightY
				end
			elseif named then
				if not namedD or dsq < namedD then
					namedP, namedD = stand, dsq
				end
			elseif dsq <= meleeSq and dy <= STRIKE_Y_SLACK then
				inMelee = true
			else
				if not bestD or dsq < bestD then
					bestP, bestD = stand, dsq
				end
			end
			if mob == tracked then
				trackedP = stand
			end
		end
		-- Flying nuke bosses first, then floor bosses like Grim (do not hover Y168).
		local pick = highP or namedP
		if not pick and not inMelee then
			pick = trackedP or bestP
		end
		strikeBossPos = pick
		getgenv().SB2StrikeBossPos = pick
		return pick
	end

	local function airHoldXZ(hrp)
		local here = Vector3.new(hrp.Position.X, 0, hrp.Position.Z)
		if os.clock() < airDodgeUntil then
			return here
		end
		if getgenv().SB2DiveFarmOn == true and isToggleOn('DiveFarm') then
			return here
		end
		if not inWdDodgeContext() then
			return here
		end
		if getgenv().SB2BobEscapeActive == true and typeof(bobEscapeFlat) == 'Vector3' then
			return bobEscapeFlat
		end
		local strike = strikeBossPos
		if typeof(strike) == 'Vector3' then
			local flat = Vector3.new(strike.X, 0, strike.Z)
			if (flat - here).Magnitude >= 6 then
				return flat
			end
			return here
		end
		local center = waveDefenseRiftsCenterFlat()
		if not center or (center - here).Magnitude < AIR_RECENTER_MIN then
			return here
		end
		return center
	end

	local function lavaLiftHold(hrp, holdY, fresh)
		if not hrp or typeof(holdY) ~= 'number' then
			return
		end
		getgenv().SB2LavaEscapeActive = true
		getgenv().SB2LavaFightY = holdY
		getgenv().SB2LavaHoverY = holdY
		local xz = airHoldXZ(hrp)
		local dy = holdY - hrp.Position.Y
		if fresh and dy > 48 then
			local blinkFn = getgenv().SB2DiveBlinkTeleport
			if type(blinkFn) == 'function' then
				pcall(function()
					blinkFn(hrp, Vector3.new(xz.X, holdY, xz.Z), nil)
				end)
			end
		end
		writeHeldCF(hrp, Vector3.new(xz.X, holdY, xz.Z), nil, 0, true)
		getgenv().SB2DivePinPos = Vector3.new(xz.X, holdY, xz.Z)
		if type(getgenv().SB2BeginAnchorReplicate) == 'function' then
			pcall(getgenv().SB2BeginAnchorReplicate, 0.35)
		end
	end

	local function bobEscapeDest(hrp, holdY)
		local bob = findBobMob()
		local bobP = bob and mobStrikePos(bob)
		-- His body is ~200 studs across. If he walks onto the perch, flip to the far side.
		if typeof(bobEscapeFlat) == 'Vector3' then
			local keep = true
			if bobP then
				local dx = bobEscapeFlat.X - bobP.X
				local dz = bobEscapeFlat.Z - bobP.Z
				keep = (dx * dx + dz * dz) > (170 * 170)
			end
			if keep then
				return getgenv().SB2AFD_roofClamp(Vector3.new(bobEscapeFlat.X, holdY, bobEscapeFlat.Z))
			end
			bobEscapeFlat = nil
		end
		local center = waveDefenseRiftsCenterFlat()
		if not center then
			center = Vector3.new(hrp.Position.X, 0, hrp.Position.Z)
		end
		local away = Vector3.new(hrp.Position.X - center.X, 0, hrp.Position.Z - center.Z)
		if bobP then
			local fromBob = Vector3.new(center.X - bobP.X, 0, center.Z - bobP.Z)
			if fromBob.Magnitude >= 4 then
				away = fromBob
			end
		end
		if away.Magnitude < 4 then
			away = Vector3.new(1, 0, 0)
		else
			away = away.Unit
		end
		-- The arena is walled in by huge invisible collidable blocks (workspace.Barriers). 280 out
		-- at Y 360 put you INSIDE them, and the physics kept ejecting you at 500-20,000 studs/s
		-- until your root part was deleted. Pull the perch in until it is clear of every wall
		-- (the Roof block covers the whole arena from ~Y 170 up, so it is ignored like before).
		local offset = BOB_SIDE_OFFSET
		local barriers = workspace:FindFirstChild('Barriers')
		if barriers then
			local walls = {}
			for _, part in ipairs(barriers:GetDescendants()) do
				if part:IsA('BasePart') and part.CanCollide and part.Name ~= 'Roof' then
					walls[#walls + 1] = part
				end
			end
			if #walls > 0 then
				local params = OverlapParams.new()
				params.FilterType = Enum.RaycastFilterType.Include
				params.FilterDescendantsInstances = walls
				while offset > 60 do
					local probe = Vector3.new(center.X + away.X * offset, holdY, center.Z + away.Z * offset)
					-- 30-stud box: room for the character plus a margin from the wall face.
					local ok, hits = pcall(function()
						return workspace:GetPartBoundsInBox(CFrame.new(probe), Vector3.new(30, 30, 30), params)
					end)
					if ok and type(hits) == 'table' and #hits == 0 then
						break
					end
					offset -= 20
				end
			end
		end
		bobEscapeFlat = Vector3.new(
			center.X + away.X * offset,
			0,
			center.Z + away.Z * offset
		)
		return getgenv().SB2AFD_roofClamp(Vector3.new(bobEscapeFlat.X, holdY, bobEscapeFlat.Z))
	end

	local function bobLiftWarp(hrp, holdY, fresh)
		if not hrp or typeof(holdY) ~= 'number' then
			return
		end
		local dest = bobEscapeDest(hrp, holdY)
		getgenv().SB2BobHoldY = holdY
		getgenv().SB2DivePinPos = dest
		local blinkFn = getgenv().SB2DiveBlinkTeleport
		if fresh and type(blinkFn) == 'function' then
			pcall(function()
				blinkFn(hrp, dest, dest)
			end)
		end
		writeHeldCF(hrp, dest, nil, 0, true, true)
		if type(getgenv().SB2BeginAnchorReplicate) == 'function' then
			pcall(getgenv().SB2BeginAnchorReplicate, 0.35)
		end
	end

	local function mobNameIsVaelith(name)
		local key = string.gsub(string.lower(tostring(name or '')), '[%p%s]+', '')
		return string.find(key, 'vaelith', 1, true) ~= nil
	end

	local function findVaelithMob()
		local now = os.clock()
		if now - vaelithMobCachedAt < 0.2 then
			if vaelithMobCached and vaelithMobCached.Parent and not mobIsDead(vaelithMobCached) then
				return vaelithMobCached
			end
		end
		vaelithMobCached = nil
		vaelithMobCachedAt = now
		if not workspace:FindFirstChild('WaveDefenseStuff') then
			return nil
		end
		local folder = workspace:FindFirstChild('Mobs')
		if not folder then
			return nil
		end
		for _, mob in ipairs(folder:GetChildren()) do
			if mobIsDead(mob) then
				continue
			end
			if mobNameIsVaelith(mob.Name) then
				vaelithMobCached = mob
				return mob
			end
			local plate = mob:FindFirstChild('Nameplate')
			local label = plate and plate:FindFirstChildWhichIsA('TextLabel', true)
			if label and mobNameIsVaelith(label.Text) then
				vaelithMobCached = mob
				return mob
			end
		end
		return nil
	end

	local function vaelithFightActive()
		return findVaelithMob() ~= nil
	end

	local function noteVaelithSeen()
		if findVaelithMob() then
			vaelithSeenUntil = os.clock() + VAELITH_MISSILE_GRACE
			return true
		end
		return os.clock() < vaelithSeenUntil
	end

	local function vaelithMissileContext()
		if noteVaelithSeen() then
			return true
		end
		if workspace:GetAttribute('WaveDefenseEnvironment') == 'Vaelith' then
			return true
		end
		return vaelithMissileCount > 0
	end

	local function partLooksVaelithMissile(part)
		if not part or not part:IsA('BasePart') then
			return false
		end
		local parent = part.Parent
		while parent and parent ~= workspace do
			local n = string.lower(tostring(parent.Name))
			if string.find(n, 'riftdetonation', 1, true)
				or n == 'rift'
				or n == 'explosion'
				or string.find(n, 'missile', 1, true)
			then
				return true
			end
			parent = parent.Parent
		end
		local s = part.Size
		local cube = math.abs(s.X - s.Y) < 0.2 and math.abs(s.Y - s.Z) < 0.2
		local mx = math.max(s.X, s.Y, s.Z)
		if cube and mx >= 1.85 and mx <= 2.45 and vaelithMissileContext() then
			return true
		end
		return false
	end

	local function unregisterVaelithMissile(part)
		if vaelithMissileParts[part] then
			vaelithMissileParts[part] = nil
			vaelithMissileCount = math.max(0, vaelithMissileCount - 1)
		end
	end

	local function registerVaelithMissile(part)
		if not part or vaelithMissileParts[part] then
			return
		end
		if not part:IsA('BasePart') then
			return
		end
		vaelithMissileParts[part] = true
		vaelithMissileCount += 1
		part.Destroying:Connect(function()
			unregisterVaelithMissile(part)
		end)
	end

	local function maybeRegisterVaelithMissile(inst)
		if inst:IsA('BasePart') then
			if partLooksVaelithMissile(inst) then
				registerVaelithMissile(inst)
			end
			return
		end
		if inst:IsA('Model') then
			local n = string.lower(tostring(inst.Name))
			if n == 'rift' or n == 'explosion' or string.find(n, 'riftdetonation', 1, true) then
				local p = inst.PrimaryPart or inst:FindFirstChildWhichIsA('BasePart')
				if p then
					registerVaelithMissile(p)
				end
			end
		end
	end

	local function seedVaelithMissiles()
		if not vaelithMissileContext() then
			return
		end
		local wd = workspace:FindFirstChild('WaveDefenseStuff')
		if wd then
			for _, inst in ipairs(wd:GetDescendants()) do
				maybeRegisterVaelithMissile(inst)
			end
		end
		for _, inst in ipairs(workspace:GetChildren()) do
			maybeRegisterVaelithMissile(inst)
			if inst:IsA('Model') and (inst.Name == 'Rift' or inst.Name == 'Explosion') then
				for _, ch in ipairs(inst:GetChildren()) do
					maybeRegisterVaelithMissile(ch)
				end
			end
		end
	end

	do
		local prev = getgenv().SB2VaelithMissileAddConn
		if prev then
			pcall(function()
				prev:Disconnect()
			end)
		end
		getgenv().SB2VaelithMissileAddConn = workspace.DescendantAdded:Connect(function(inst)
			maybeRegisterVaelithMissile(inst)
		end)
		task.defer(seedVaelithMissiles)
	end

	local VAELITH_ENGAGE_REACH = 7
	local VAELITH_REENGAGE_PAD = 4

	local function vaelithReengageGoal(hrp, mob)
		if not hrp or not mob then
			return nil
		end
		local pos, look = mobFlatLook(mob)
		if not pos or not look then
			return nil
		end
		local flatToBoss = Vector3.new(hrp.Position.X - pos.X, 0, hrp.Position.Z - pos.Z)
		if flatToBoss.Magnitude <= VAELITH_ENGAGE_REACH + VAELITH_REENGAGE_PAD then
			return nil
		end
		return Vector3.new(
			pos.X - look.X * VAELITH_ENGAGE_REACH,
			wdArenaFightY(hrp),
			pos.Z - look.Z * VAELITH_ENGAGE_REACH
		), pos
	end

	local function vaelithMissileDodgeGoal(hrpPos)
		if typeof(hrpPos) ~= 'Vector3' then
			return nil
		end
		-- Replaced by SB2DodgeModes.vaelithEscape (times the dodge to the orb's lock-on).
		-- The orbs are tweened, so their velocity always reads 0 and this pushed you at random.
		if getgenv().SB2DodgeOldVaelith ~= true then
			getgenv().SB2VaelithMissileGoal = nil
			getgenv().SB2VaelithMissileThreat = false
			return nil
		end
		if not vaelithMissileContext() then
			getgenv().SB2VaelithMissileGoal = nil
			getgenv().SB2VaelithMissileThreat = false
			return nil
		end
		local bestGoal = nil
		local worstGap = nil
		for inst in pairs(vaelithMissileParts) do
			if not inst.Parent then
				unregisterVaelithMissile(inst)
				continue
			end
			local pos = inst.Position
			local s = inst.Size
			local mx = math.max(s.X, s.Y, s.Z)
			local threatR = math.max(10, mx * 0.5 + 8)
			local flat = Vector3.new(hrpPos.X - pos.X, 0, hrpPos.Z - pos.Z)
			local dist = flat.Magnitude
			if dist > 110 then
				continue
			end
			local vel = inst.AssemblyLinearVelocity
			local velFlat = Vector3.new(vel.X, 0, vel.Z)
			local homing = dist < 70
			if velFlat.Magnitude > 3 and dist > 0.5 then
				homing = velFlat.Unit:Dot(flat.Unit) > 0.15 or dist < 70
			end
			if not homing and dist > VAELITH_MISSILE_WARN then
				continue
			end
			local gap = dist - threatR
			if gap >= VAELITH_MISSILE_CLEAR + 6 then
				continue
			end
			local push = (threatR + VAELITH_MISSILE_CLEAR) - dist
			if push < 2.0 then
				push = 8
			end
			push = math.clamp(push, 4, VAELITH_MISSILE_MAX_PUSH)
			local dir
			if velFlat.Magnitude > 2 then
				dir = Vector3.new(-velFlat.Z, 0, velFlat.X)
				if dir.Magnitude < 0.05 then
					dir = flat.Magnitude > 0.2 and flat.Unit or Vector3.new(1, 0, 0)
				else
					dir = dir.Unit
					if flat.Magnitude > 0.2 and dir:Dot(flat.Unit) < 0 then
						dir = -dir
					end
				end
			else
				dir = flat.Magnitude > 0.2 and flat.Unit or Vector3.new(1, 0, 0)
			end
			local score = gap - (homing and 8 or 0)
			if not worstGap or score < worstGap then
				worstGap = score
				bestGoal = Vector3.new(
					hrpPos.X + dir.X * push,
					math.clamp(hrpPos.Y, WD_LAVA_FLOOR_Y + 4, WD_LAVA_FLOOR_Y + 18),
					hrpPos.Z + dir.Z * push
				)
			end
		end
		if bestGoal then
			getgenv().SB2VaelithMissileGoal = bestGoal
			getgenv().SB2VaelithMissileThreat = true
		else
			getgenv().SB2VaelithMissileGoal = nil
			getgenv().SB2VaelithMissileThreat = false
		end
		return bestGoal
	end

	local function tempestLightningDodgeGoal(hrpPos)
		if typeof(hrpPos) ~= 'Vector3' then
			return nil
		end
		if not workspace:FindFirstChild('WaveDefenseStuff') then
			return nil
		end
		-- Ordinary WD discs are not Tempest bolts. Stealing hop here froze the
		-- 4-spot cycle on every other miniboss / AOE wave.
		local env = workspace:GetAttribute('WaveDefenseEnvironment')
		if env ~= 'Tempest' then
			return nil
		end
		local now = os.clock()
		local held = getgenv().SB2LightningHoldGoal
		local circles = {}
		for _, ch in ipairs(workspace:GetChildren()) do
			if not ch:IsA('BasePart') then
				continue
			end
			local n = string.lower(tostring(ch.Name))
			if n ~= 'circle' and n ~= 'effecthitbox' then
				continue
			end
			local span = math.max(ch.Size.X, ch.Size.Z)
			-- Tempest bolts are 50-wide / 100-tall. Skip tiny discs and huge slams.
			if span < 36 or span > 80 then
				continue
			end
			if n == 'circle' and ch.Size.Y < 40 then
				continue
			end
			circles[#circles + 1] = {
				x = ch.Position.X,
				z = ch.Position.Z,
				r = span * 0.5,
			}
		end
		-- The game's own strike effect (TempestStrike.VFX) is placed where the bolt will land
		-- the moment the strike starts, so it is the earliest warning we get.
		for _, ch in ipairs(workspace:GetChildren()) do
			if ch.Name == 'VFX' and ch:IsA('BasePart') then
				local top = ch:FindFirstChild('Top')
				if top and top:FindFirstChild('LightningStrike') then
					local bottom = ch:FindFirstChild('Bottom')
					local p = (bottom and bottom:IsA('Attachment')) and bottom.WorldPosition or ch.Position
					circles[#circles + 1] = { x = p.X, z = p.Z, r = 27 }
				end
			end
		end
		-- Shared with the walk back to the middle so it never steps into a bolt circle.
		if #circles > 0 then
			getgenv().SB2TempestCircles = circles
			getgenv().SB2TempestCirclesAt = now
		end
		-- Prefer safe spots near the arena middle so killaura still reaches every rift.
		local mid = waveDefenseRiftsCenterFlat()
		local function covered(x, z, pad)
			pad = pad or 26
			for i = 1, #circles do
				local c = circles[i]
				local dx, dz = x - c.x, z - c.z
				local need = c.r + pad
				if dx * dx + dz * dz < need * need then
					return true
				end
			end
			return false
		end
		local function minClear(x, z)
			local best = 1e9
			for i = 1, #circles do
				local c = circles[i]
				local dx, dz = x - c.x, z - c.z
				local d = math.sqrt(dx * dx + dz * dz) - c.r
				if d < best then
					best = d
				end
			end
			return best
		end
		local near = #circles > 0 and covered(hrpPos.X, hrpPos.Z, 22)
		if not near then
			for i = 1, #circles do
				local c = circles[i]
				local dx, dz = hrpPos.X - c.x, hrpPos.Z - c.z
				if math.sqrt(dx * dx + dz * dz) < c.r + 36 then
					near = true
					break
				end
			end
		end
		if not near then
			local untilT = tonumber(getgenv().SB2LightningHoldUntil) or 0
			if typeof(held) == 'Vector3' and now < untilT then
				getgenv().SB2LightningGoal = held
				getgenv().SB2LightningOwnedChase = true
				return held
			end
			getgenv().SB2LightningGoal = nil
			getgenv().SB2LightningHoldGoal = nil
			return nil
		end
		local best, bestClear, bestTravel = nil, -1e9, 1e9
		local function tryAt(x, z)
			if covered(x, z, 26) then
				return
			end
			local clear = minClear(x, z)
			if clear < 26 then
				return
			end
			local travel = (x - hrpPos.X) * (x - hrpPos.X) + (z - hrpPos.Z) * (z - hrpPos.Z)
			if travel < 400 then
				return
			end
			-- Max-clearance alone always picked the far edge and walked you away from mobs.
			local score = math.min(clear, 45)
			if mid then
				local mx, mz = x - mid.X, z - mid.Z
				score -= 0.6 * math.max(0, math.sqrt(mx * mx + mz * mz) - 20)
			end
			if score > bestClear + 2 or (math.abs(score - bestClear) <= 2 and travel < bestTravel) then
				bestClear = score
				bestTravel = travel
				best = Vector3.new(x, hrpPos.Y, z)
			end
		end
		local px, pz = hrpPos.X, hrpPos.Z
		local rx, rz = 0, 0
		for i = 1, #circles do
			local c = circles[i]
			local fx, fz = px - c.x, pz - c.z
			local mag = math.sqrt(fx * fx + fz * fz)
			local ux, uz = 1, 0
			if mag > 0.25 then
				ux, uz = fx / mag, fz / mag
			end
			local push = math.max(0.2, (c.r + 34) - mag)
			rx += ux * push
			rz += uz * push
			tryAt(c.x + ux * (c.r + 30), c.z + uz * (c.r + 30))
			tryAt(c.x + ux * (c.r + 46), c.z + uz * (c.r + 46))
			tryAt(c.x + ux * (c.r + 62), c.z + uz * (c.r + 62))
		end
		local rmag = math.sqrt(rx * rx + rz * rz)
		if rmag > 0.25 then
			local ux, uz = rx / rmag, rz / rmag
			tryAt(px + ux * 48, pz + uz * 48)
			tryAt(px + ux * 68, pz + uz * 68)
			tryAt(px + ux * 88, pz + uz * 88)
		end
		for i = 0, 19 do
			local a = i / 20 * math.pi * 2
			local ca, sa = math.cos(a), math.sin(a)
			tryAt(px + ca * 40, pz + sa * 40)
			tryAt(px + ca * 58, pz + sa * 58)
			tryAt(px + ca * 76, pz + sa * 76)
			tryAt(px + ca * 94, pz + sa * 94)
		end
		if best then
			getgenv().SB2LightningHoldGoal = best
			getgenv().SB2LightningHoldUntil = now + 1.2
			getgenv().SB2LightningGoal = best
			getgenv().SB2LightningOwnedChase = true
		elseif typeof(held) == 'Vector3' and now < (tonumber(getgenv().SB2LightningHoldUntil) or 0) then
			best = held
			getgenv().SB2LightningGoal = best
			getgenv().SB2LightningOwnedChase = true
		end
		return best
	end

	local function darknerOrbCenter()
		local orb = workspace:FindFirstChild('DarknerOrb')
		if not orb or not orb.Parent then
			return nil
		end
		if orb:IsA('BasePart') then
			return orb.Position
		end
		local ok, pos = pcall(function()
			if orb:IsA('Model') or orb:IsA('PVInstance') then
				return orb:GetPivot().Position
			end
			local part = orb:FindFirstChildWhichIsA('BasePart', true)
			return part and part.Position
		end)
		if ok and typeof(pos) == 'Vector3' then
			return pos
		end
		return nil
	end

	getgenv().SB2TryPackHopSnap = function()
		return false
	end
	local function _retiredPackHopSnap()
		if not isWdWaveInstance() then
			return false
		end
		local env = workspace:GetAttribute('WaveDefenseEnvironment')
		local model = (type(getMyCharacterModel) == 'function' and getMyCharacterModel()) or LocalPlayer.Character
		local hrp = model and model:FindFirstChild('HumanoidRootPart')
		if not hrp or not hrp:IsA('BasePart') then
			return false
		end
		local orb = darknerOrbCenter()
		if env == 'Blackout' or orb then
			local flat = nil
			if orb then
				flat = Vector3.new(orb.X, 0, orb.Z)
			else
				flat = waveDefenseRiftsCenterFlat()
			end
			if not flat then
				flat = Vector3.new(hrp.Position.X, 0, hrp.Position.Z)
			end
			local standAt = Vector3.new(flat.X, WD_LAVA_FLOOR_Y + 8, flat.Z)
			local y = darknerOrbStandY(hrp, standAt)
			local dest = Vector3.new(flat.X, y, flat.Z)
			getgenv().SB2WdRiftHopGoal = nil
			getgenv().SB2WdRiftHopActive = false
			getgenv().SB2DarknerOrbXZ = flat
			getgenv().SB2DarknerOrbStandY = y
			getgenv().SB2DiveChaseGoal = nil
			getgenv().SB2DiveApproachUntil = 0
			getgenv().SB2DivePinPos = dest
			writeHeldCF(hrp, dest, nil, 0, true, true)
			return true
		end
		if env == 'Lava' then
			return false
		end
		local waveN = wdCurrentWave()
		if waveN and waveN >= 100 then
			return false
		end
		if findBobMob() then
			return false
		end
		if findRubricatusMob() then
			return false
		end
		local hop = waveDefenseRiftHopGoal(WD_LAVA_FLOOR_Y + 102, os.clock(), PACK_HOP_LEAN)
		if not hop then
			return false
		end
		getgenv().SB2WdRiftHopGoal = hop
		getgenv().SB2WdRiftHopActive = true
		getgenv().SB2DiveChaseGoal = nil
		getgenv().SB2DiveApproachUntil = 0
		getgenv().SB2DivePinPos = hop
		writeHeldCF(hrp, hop, nil, 0, true, true)
		return true
	end

	local function stopAutoFloorDodgeLoop()
		getgenv().SB2AutoFloorDodgeOn = false
		pcall(function()
			RunService:UnbindFromRenderStep('SB2PackHop')
		end)
		pcall(function()
			local beat = getgenv().SB2PackHopBeat
			if beat then
				beat:Disconnect()
			end
			getgenv().SB2PackHopBeat = nil
		end)
		local prev = getgenv().SB2AutoFloorDodgeConn
		if prev then
			pcall(function()
				prev:Disconnect()
			end)
			getgenv().SB2AutoFloorDodgeConn = nil
		end
		clearWdDodgeHoverState()
		getgenv().SB2DarknerOrbXZ = nil
		getgenv().SB2DarknerOrbStandY = nil
		getgenv().SB2WendigoHold = nil
	end

	local function sidestepOnGround(hrp, goal, lookAt, minMove)
		if typeof(goal) ~= 'Vector3' then
			return false
		end
		minMove = tonumber(minMove) or 1.6
		local dest = Vector3.new(goal.X, hrp.Position.Y, goal.Z)
		local dx = dest.X - hrp.Position.X
		local dz = dest.Z - hrp.Position.Z
		if (dx * dx + dz * dz) < (minMove * minMove) then
			return false
		end
		local moved = writeHeldCF(hrp, dest, lookAt, minMove, true, false)
		-- A one-shot CFrame gets snapped back into the circle. Hold the exit until the spike lands.
		if moved and type(getgenv().SB2PinTeleportCFrame) == 'function' then
			local lv = hrp.CFrame.LookVector
			local flat = Vector3.new(lv.X, 0, lv.Z)
			local cf = flat.Magnitude >= 0.08 and CFrame.lookAt(dest, dest + flat.Unit) or CFrame.new(dest)
			getgenv().SB2PinTeleportCFrame(cf, 0.9)
		end
		return moved
	end

	local function dropHoverToGround(hrp)
		local gy = groundYAt(hrp)
		if not gy then
			return false
		end
		local stand = gy + humanoidHip(hrp) + hrp.Size.Y * 0.5
		if hrp.Position.Y <= stand + 6 then
			return false
		end
		return writeHeldCF(hrp, Vector3.new(hrp.Position.X, stand, hrp.Position.Z), nil, 0, true, true)
	end

	local function tickGroundDodge(hrp, now, lastStepAt)
		getgenv().SB2WdRiftHopActive = false
		getgenv().SB2WdRiftHopGoal = nil
		getgenv().SB2LavaEscapeActive = false
		getgenv().SB2BobEscapeActive = false
		getgenv().SB2RubricatusSurviveActive = false
		getgenv().SB2PackHopWhy = 'ground'
		if getgenv().SB2DiveUnderMap == true then
			return lastStepAt
		end
		if getgenv().SB2DiveFarmOn == true and type(isToggleOn) == 'function' and isToggleOn('DiveFarm') then
			return lastStepAt
		end
		local modesEarly = getgenv().SB2DodgeModes
		-- Default for every wave without its own dodge: hover 160 above the floor over the middle.
		if modesEarly and modesEarly.wantsHover160 and modesEarly.wantsHover160() then
			modesEarly.hover160(hrp, now)
			return now
		end
		getgenv().SB2Hover160Pos = nil
		if modesEarly and modesEarly.projectileEscape then
			local orbOut = modesEarly.projectileEscape(hrp, now)
			if orbOut and (Vector3.new(orbOut.X - hrp.Position.X, 0, orbOut.Z - hrp.Position.Z)).Magnitude > 1.5 then
				writeHeldCF(hrp, Vector3.new(orbOut.X, hrp.Position.Y, orbOut.Z), nil, 0, true, false)
				return now
			end
		end
		if modesEarly and modesEarly.releaseHover then
			modesEarly.releaseHover(hrp)
			if modesEarly.hurtEscape(hrp, now) then
				return now
			end
		end
		local heldGoal = getgenv().SB2FloorDodgeGoal
		local offGoal = false
		if typeof(heldGoal) == 'Vector3' then
			local gx = heldGoal.X - hrp.Position.X
			local gz = heldGoal.Z - hrp.Position.Z
			offGoal = (gx * gx + gz * gz) > (4 * 4)
		end
		if not offGoal and now - lastStepAt < 0.12 then
			return lastStepAt
		end
		local y = hrp.Position.Y
		getgenv().SB2DodgeWhy = 'vaelith'
		getgenv().SB2DodgeWhyDetail = nil
		local goal = vaelithMissileDodgeGoal(hrp.Position)
		if not goal then
			getgenv().SB2DodgeWhy = 'tempest'
			goal = tempestLightningDodgeGoal(hrp.Position)
		end
		if not goal then
			goal = resolveFloorDodgeGoal(hrp, y)
		end
		-- Step out of the attack. Do not blink across the arena.
		-- Storm bolts are ~50 wide: 12-stud steps took ~0.5s to get clear and the bolt
		-- landed on you mid-escape, so storm dodges jump straight to the safe spot.
		if typeof(goal) == 'Vector3' then
			local sx = goal.X - hrp.Position.X
			local sz = goal.Z - hrp.Position.Z
			local sm = math.sqrt(sx * sx + sz * sz)
			local cap = getgenv().SB2DodgeWhy == 'tempest' and 110 or 12
			if sm > cap then
				goal = Vector3.new(hrp.Position.X + sx / sm * cap, hrp.Position.Y, hrp.Position.Z + sz / sm * cap)
			else
				goal = Vector3.new(goal.X, hrp.Position.Y, goal.Z)
			end
		end
		if goal and sidestepOnGround(hrp, goal, nil, 1.6) then
			local logFn = getgenv().SB2DodgeLog
			if type(logFn) == 'function' then
				logFn('ground:' .. tostring(getgenv().SB2DodgeWhy), getgenv().SB2DodgeWhyDetail, hrp.Position)
			end
			getgenv().SB2LastDodgeMoveAt = now
			-- Dodged right after walking back to the middle: the middle is the danger, so wait longer.
			if now - (tonumber(getgenv().SB2LastRecenterAt) or -1e9) < 0.6 then
				getgenv().SB2RecenterBackoffUntil = now + 3
			end
			return now
		end
		if dropHoverToGround(hrp) then
			return now
		end
		local modes = getgenv().SB2DodgeModes
		-- Rift special wave: cycle the four portal-leaning spots instead of sitting in the middle.
		if modes and modes.riftCycle and modes.riftCycle(hrp, now) then
			return now
		end
		if modes and modes.recenter and modes.recenter(hrp, now) then
			return now
		end
		unstickIdleFreefall(hrp)
		return lastStepAt
	end

	-- Air modes (Bob lift, Darkner orb hold, drop back to the floor) + a decision log.
	-- Own function + getgenv(): the enclosing function sits at Luau's 200-local cap
	-- (a plain do-block still spends its registers).
	;(function()
		local M = {}
		getgenv().SB2DodgeModes = M

		-- Ring buffer of every move the dodge makes, flushed to a file every couple of seconds.
		local LOG_PATH = getgenv().SB2AcctPath('PlayerTools/_dodge_log.txt')
		local lines, dirty, lastFlush, t0 = {}, false, 0, os.clock()
		-- Keep the last 300 lines from before a reload so a problem isn't wiped by reloading.
		pcall(function()
			if type(readfile) == 'function' and type(isfile) == 'function' and isfile(LOG_PATH) then
				local old = {}
				for line in string.gmatch(readfile(LOG_PATH), '[^\n]+') do
					old[#old + 1] = line
				end
				for i = math.max(1, #old - 299), #old do
					lines[#lines + 1] = old[i]
				end
				if #lines > 0 then
					lines[#lines + 1] = '---- reloaded ' .. os.date('%H:%M:%S') .. ' (times restart at 0) ----'
				end
			end
		end)
		local lastKey, lastKeyAt = nil, 0
		local function flush()
			dirty = false
			lastFlush = os.clock()
			if type(writefile) == 'function' then
				pcall(writefile, LOG_PATH, table.concat(lines, '\n'))
			end
		end
		getgenv().SB2DodgeLog = function(why, detail, pos)
			local now = os.clock()
			local key = tostring(why) .. '|' .. tostring(detail)
			if key == lastKey and now - lastKeyAt < 0.5 then
				return
			end
			lastKey, lastKeyAt = key, now
			lines[#lines + 1] = string.format(
				'%8.2f %-18s at=(%.0f,%.0f,%.0f) %s',
				now - t0,
				tostring(why),
				typeof(pos) == 'Vector3' and pos.X or 0,
				typeof(pos) == 'Vector3' and pos.Y or 0,
				typeof(pos) == 'Vector3' and pos.Z or 0,
				detail and ('<- ' .. tostring(detail)) or ''
			)
			if #lines > 600 then
				table.remove(lines, 1)
			end
			dirty = true
			if now - lastFlush > 2 then
				flush()
			end
		end
		task.spawn(function()
			while getgenv().SB2DodgeModes == M do
				task.wait(3)
				if dirty then
					flush()
				end
			end
		end)

		local function resetHold(dest)
			local lineOut = getgenv().SB2RedLaser and getgenv().SB2RedLaser.escape(dest, nil)
			if lineOut then
				dest = Vector3.new(lineOut.X, dest.Y, lineOut.Z)
			end
			local boOut = getgenv().SB2RedLaser and getgenv().SB2RedLaser.blackoutClamp
				and getgenv().SB2RedLaser.blackoutClamp(dest)
			if boOut then
				dest = boOut
			end
			getgenv().SB2DivePinPos = dest
			local reset = getgenv().SB2DiveResetHold
			if type(reset) == 'function' then
				pcall(reset, dest)
			end
		end

		-- The lava / Bob lifts use the main script's blink teleport, which parents a zero-velocity
		-- LinearVelocity (SB2DiveLinVel) to your root and never removes it unless dive farm
		-- toggles. Left on, it cancels gravity: you float in Freefall and the walk back to the
		-- middle refuses to run (it skips while airborne). Take it off whenever we are on foot.
		function M.releaseHover(hrp)
			if getgenv().SB2DiveFarmOn == true or getgenv().SB2DiveUnderMap == true then
				return false
			end
			local lv = getgenv().SB2DiveLinVel
			if lv and hrp and lv.Parent == hrp then
				pcall(function()
					lv.Parent = nil
					lv.Attachment0 = nil
					lv.VectorVelocity = Vector3.zero
				end)
				getgenv().SB2DivePinPos = nil
				getgenv().SB2DodgeLog('release-hover', nil, hrp.Position)
				return true
			end
			return false
		end

		-- Safety net for attacks no detector knows (the storm wave's ground beam hit you 1% every
		-- 0.05s for 6s while you stood still): 3+ hits inside 0.8s = move 32 studs, preferring
		-- the middle but never back onto a spot that just hurt you.
		-- SB2's real HP lives in Character.Entity.Health (value + MaxValue, ~1.3M). The
		-- Humanoid always reads 100/100, which is why v17-v20 never saw you getting hurt.
		function M.healthValue(hrp)
			local char = hrp and hrp.Parent
			local ent = char and char:FindFirstChild('Entity')
			local h = ent and ent:FindFirstChild('Health')
			if h and h:IsA('ValueBase') then
				return h
			end
			return nil
		end

		function M.hpPct(hrp)
			local h = M.healthValue(hrp)
			if h then
				local maxV = tonumber(h.MaxValue) or 0
				local v = tonumber(h.Value) or 0
				if maxV > 0 then
					return v / maxV, v
				end
			end
			local hum = hrp and hrp.Parent and hrp.Parent:FindFirstChildOfClass('Humanoid')
			if hum and hum.MaxHealth > 0 then
				return hum.Health / hum.MaxHealth, hum.Health
			end
			return nil, nil
		end

		function M.watchHurt(hrp)
			local h = M.healthValue(hrp)
			if not h then
				return nil
			end
			local st = getgenv().SB2HurtState
			if st and st.hum == h then
				return st
			end
			if st and st.conn then
				pcall(function()
					st.conn:Disconnect()
				end)
			end
			st = { hum = h, last = tonumber(h.Value) or 0, hits = {}, spots = {}, escAt = 0, spin = 0 }
			st.conn = h.Changed:Connect(function(v)
				local hp = tonumber(v)
				if not hp then
					return
				end
				-- Ignore tiny ticks (the arena's slow 2.5s chip still counts; regen never does).
				if hp < st.last - 0.5 then
					st.hits[#st.hits + 1] = os.clock()
					if #st.hits > 24 then
						table.remove(st.hits, 1)
					end
				end
				st.last = hp
			end)
			getgenv().SB2HurtState = st
			return st
		end

		function M.hurtEscape(hrp, now)
			local st = M.watchHurt(hrp)
			if not st or now - st.escAt < 1 then
				return false
			end
			local n = 0
			for i = #st.hits, 1, -1 do
				if now - st.hits[i] > 0.8 then
					break
				end
				n += 1
			end
			if n < 3 then
				return false
			end
			local here = hrp.Position
			st.spots[#st.spots + 1] = here
			if #st.spots > 4 then
				table.remove(st.spots, 1)
			end
			local mid = waveDefenseRiftsCenterFlat()
			local best, bestScore = nil, nil
			st.spin = (st.spin + 3) % 8
			for i = 0, 7 do
				local a = (i + st.spin) / 8 * math.pi * 2
				local x, z = here.X + math.cos(a) * 32, here.Z + math.sin(a) * 32
				local stand = M.floorStandY(hrp, x, z)
				if stand then
					local score = 0
					if mid then
						local dx, dz = x - mid.X, z - mid.Z
						score -= math.sqrt(dx * dx + dz * dz)
					end
					for _, s in ipairs(st.spots) do
						local sx, sz = x - s.X, z - s.Z
						if sx * sx + sz * sz < 24 * 24 then
							score -= 1000
						end
					end
					if not bestScore or score > bestScore then
						best, bestScore = Vector3.new(x, stand, z), score
					end
				end
			end
			if not best then
				return false
			end
			M.releaseHover(hrp)
			writeHeldCF(hrp, best, nil, 0, true, true)
			st.escAt = now
			table.clear(st.hits)
			getgenv().SB2LastDodgeMoveAt = now
			getgenv().SB2DodgeLog('hurt-escape', n .. ' hits in 0.8s', best)
			return true
		end

		-- Standing height on the floor under (x, z), or nil off the map.
		function M.floorStandY(hrp, x, z)
			local gy = groundYAtPos(x, hrp.Position.Y, z, hrp)
			if not gy then
				return nil
			end
			return gy + humanoidHip(hrp) + hrp.Size.Y * 0.5
		end

		-- After lava / Bob / orb: get back on the floor. True while it is moving you down.
		function M.descend(hrp, why)
			-- Only right after an air mode; normal jumps / dive-farm flight are not ours to touch.
			if os.clock() - (tonumber(getgenv().SB2DodgeAirAt) or -1e9) > 8 then
				return false
			end
			-- Normal waves hover at 160 now; don't drop to the floor just to be lifted again.
			if M.wantsHover160 and M.wantsHover160() then
				return false
			end
			M.releaseHover(hrp)
			local x, z = hrp.Position.X, hrp.Position.Z
			-- Land in the middle of the arena, not wherever the lift left you (Bob's perch is far out).
			local mid = waveDefenseRiftsCenterFlat()
			if mid and M.floorStandY(hrp, mid.X, mid.Z) then
				x, z = mid.X, mid.Z
			end
			local stand = M.floorStandY(hrp, x, z)
			if stand and (hrp.Position.Y > stand + 6 or math.abs(hrp.Position.X - x) + math.abs(hrp.Position.Z - z) > 4) then
				-- falls through to the move below
			elseif not stand then
				-- Parked off the map (Bob perch): come back over the arena first.
				if getgenv().SB2BobEscapeActive ~= true and typeof(bobEscapeFlat) ~= 'Vector3'
					and hrp.Position.Y < WD_LAVA_FLOOR_Y + 60
				then
					return false
				end
				local center = waveDefenseRiftsCenterFlat()
				if not center then
					return false
				end
				x, z = center.X, center.Z
				stand = M.floorStandY(hrp, x, z) or (WD_LAVA_FLOOR_Y + humanoidHip(hrp) + hrp.Size.Y * 0.5)
			elseif hrp.Position.Y <= stand + 6 then
				return false
			end
			local dest = Vector3.new(x, stand, z)
			getgenv().SB2LavaEscapeActive = false
			getgenv().SB2LavaFightY = nil
			getgenv().SB2LavaHoverY = nil
			getgenv().SB2BobEscapeActive = false
			getgenv().SB2BobHoldY = nil
			bobEscapeFlat = nil
			writeHeldCF(hrp, dest, nil, 0, true, true)
			resetHold(dest)
			getgenv().SB2DodgeLog(why or 'descend', nil, dest)
			-- Landed: stop treating this as a fresh air exit.
			if math.abs(hrp.Position.Y - stand) < 3 then
				getgenv().SB2DodgeAirAt = nil
			end
			return true
		end

		-- Bob: park high and well outside the arena until he is gone.
		function M.bob(hrp, fresh)
			getgenv().SB2DodgeAirAt = os.clock()
			getgenv().SB2BobEscapeActive = true
			getgenv().SB2BobHoldY = BOB_HOLD_Y
			bobHoldY = BOB_HOLD_Y
			bobLiftWarp(hrp, BOB_HOLD_Y, fresh)
			local pin = getgenv().SB2DivePinPos
			if typeof(pin) == 'Vector3' then
				resetHold(pin)
			end
			if fresh then
				getgenv().SB2DodgeLog('bob-lift', nil, pin)
			end
		end

		function M.orbPart()
			local orb = workspace:FindFirstChild('DarknerOrb')
			if not orb then
				return nil
			end
			if orb:IsA('BasePart') then
				return orb
			end
			return orb:FindFirstChildWhichIsA('BasePart', true)
		end

		-- Aeganatos: his attacks cover huge areas, so hover high above him (lava height,
		-- Y~173) and follow him around. getgenv().SB2DodgeAeganatosY overrides the height.
		function M.aeganatosMob()
			local mob = findAeganatosMob()
			if mob then
				getgenv().SB2AegSeenUntil = os.clock() + 1.5
				getgenv().SB2AegLastPos = mobStrikePos(mob) or getgenv().SB2AegLastPos
			end
			return mob
		end

		function M.aeganatos(hrp, mob, fresh)
			getgenv().SB2DodgeAirAt = os.clock()
			local p = (mob and mobStrikePos(mob)) or getgenv().SB2AegLastPos
			if typeof(p) ~= 'Vector3' then
				p = hrp.Position
			end
			-- 160 studs above him by default (his body or the floor under him, whichever is higher).
			local floorY = groundYAtPos(p.X, p.Y + 20, p.Z, hrp)
			local holdY = tonumber(getgenv().SB2DodgeAeganatosY)
				or (math.max(p.Y, floorY or p.Y) + 160)
			local head = mob and aeganatosHeadTopY(mob)
			if head and head + 20 > holdY then
				holdY = head + 20
			end
			-- Stay inside your 200-stud attack reach.
			if floorY and not getgenv().SB2DodgeAeganatosY then
				holdY = math.min(holdY, floorY + (tonumber(getgenv().SB2DodgeLowHpMaxAbove) or 160))
			end
			-- Follow him, but don't re-teleport for tiny shuffles.
			local held = getgenv().SB2AegHoldPos
			local dest = Vector3.new(p.X, holdY, p.Z)
			if typeof(held) == 'Vector3' and Vector3.new(held.X - dest.X, 0, held.Z - dest.Z).Magnitude < 6
				and math.abs(held.Y - dest.Y) < 3
			then
				dest = held
			end
			getgenv().SB2AegHoldPos = dest
			if fresh and dest.Y - hrp.Position.Y > 48 then
				local blinkFn = getgenv().SB2DiveBlinkTeleport
				if type(blinkFn) == 'function' then
					pcall(blinkFn, hrp, dest, nil)
				end
				getgenv().SB2DodgeLog('aeganatos-lift', mob and mob.Name or 'boss bar', dest)
			end
			writeHeldCF(hrp, dest, p, 0, true, true)
			getgenv().SB2DivePinPos = dest
			resetHold(dest)
		end

		-- Nythrane's PurpleFireyOrb (game code: EnemySkills...Nythrane...PurpleFireyOrb): a 15-stud
		-- "Part" with a "Burning" sound tweens in a straight line for 2s to where you stood when
		-- he fired, then explodes at 1.5s and swells to 2.5x (about a 19-stud blast). Track each
		-- orb from first sight, predict its landing point, and step 40 studs sideways if that is
		-- near you. Works on the floor and while hovering.
		local ORB_LIFE, ORB_DANGER, ORB_STEP = 2, 30, 40
		local orbSeen = setmetatable({}, { __mode = 'k' })
		local function isNythraneOrb(ch)
			if not ch:IsA('BasePart') or ch.Name ~= 'Part' then
				return false
			end
			local sz = ch.Size
			if sz.X < 12 or sz.X > 40 or math.abs(sz.X - sz.Y) > 1 or math.abs(sz.X - sz.Z) > 1 then
				return false
			end
			return ch:FindFirstChild('Burning') ~= nil
		end

		-- Vaelith's RiftDetonation orbs (game code): a ~2-stud "Part" with a Trail rises 45 studs
		-- over 2s, then curves into you over 1.5s, re-aiming at you until the last 0.5s, and hits
		-- on touch (checked on your client). Moving early does nothing; moving once it locks
		-- (about 3.0s after it appears) makes it miss. So: track each orb from first sight and
		-- jump 30 studs sideways when any orb within range reaches its lock window.
		local V_LOCK_FROM, V_LOCK_TO, V_STEP, V_RANGE = 2.85, 3.45, 30, 260
		local vOrbSeen = setmetatable({}, { __mode = 'k' })
		local function isVaelithOrb(ch)
			if not ch:IsA('BasePart') or ch.Name ~= 'Part' or not ch.Anchored then
				return false
			end
			local sz = ch.Size
			if sz.X < 1.6 or sz.X > 2.6 or math.abs(sz.X - sz.Y) > 0.2 or math.abs(sz.X - sz.Z) > 0.2 then
				return false
			end
			return ch:FindFirstChildOfClass('Trail') ~= nil
		end

		-- v55 timing (from the game's RiftDetonation code): each orb rises straight up for 2s,
		-- then curves at you for 1.5s. It keeps re-aiming at your live position (smoothed,
		-- ~15/s) for the first 1.0s of the curve, then flies to that locked point. Moving
		-- before the lock just drags the aim along with you, so: detect when each orb starts
		-- curving (its X/Z starts to change), wait for its lock, then step away right after.
		-- A volley's orbs lock 0.1s apart, so step again for each one, always the same way
		-- (never back onto a spot an earlier orb locked onto).
		local V_CURVE_LOCK, V_CURVE_END = 1.0, 1.5
		local V_SIDESTEP = 22

		function M.vaelithEscape(hrp, now)
			local here = hrp.Position
			local held = getgenv().SB2VaelEscapePos
			if typeof(held) == 'Vector3' and now >= (tonumber(getgenv().SB2VaelEscapeUntil) or 0) then
				held = nil
				getgenv().SB2VaelEscapePos = nil
			end
			local base = held or here
			local trigger = nil
			for _, ch in ipairs(workspace:GetChildren()) do
				if isVaelithOrb(ch) then
					local rec = vOrbSeen[ch]
					local pos = ch.Position
					if type(rec) ~= 'table' then
						rec = { x = pos.X, z = pos.Z, t0 = now }
						vOrbSeen[ch] = rec
					end
					if not rec.curve then
						local moved = Vector3.new(pos.X - rec.x, 0, pos.Z - rec.z).Magnitude
						if moved > 0.15 then
							rec.curve = now
						elseif now - rec.t0 > 2.4 then
							rec.curve = now -- missed the rise: treat as curving from now
						end
					end
					if rec.curve and not rec.done then
						local t = now - rec.curve
						if t >= V_CURVE_LOCK + 0.02 and t < V_CURVE_END
							and Vector3.new(pos.X - base.X, 0, pos.Z - base.Z).Magnitude < V_RANGE
						then
							rec.done = true
							trigger = trigger or ch
						elseif t >= V_CURVE_END then
							rec.done = true
						end
					end
				end
			end
			if trigger then
				local dir = getgenv().SB2VaelEscapeDir
				if typeof(dir) ~= 'Vector3' or now >= (tonumber(getgenv().SB2VaelEscapeDirUntil) or 0) then
					local o = trigger.Position
					local toMe = Vector3.new(base.X - o.X, 0, base.Z - o.Z)
					local side = toMe.Magnitude > 0.5 and Vector3.new(-toMe.Z, 0, toMe.X).Unit or Vector3.new(1, 0, 0)
					local mid = waveDefenseRiftsCenterFlat()
					dir = side
					if mid then
						local a = Vector3.new(base.X + side.X * 40, 0, base.Z + side.Z * 40)
						local b = Vector3.new(base.X - side.X * 40, 0, base.Z - side.Z * 40)
						if (b - mid).Magnitude < (a - mid).Magnitude then
							dir = -side
						end
					end
				end
				getgenv().SB2VaelEscapeDir = dir
				getgenv().SB2VaelEscapeDirUntil = now + 0.7
				local dest = Vector3.new(base.X + dir.X * V_SIDESTEP, base.Y, base.Z + dir.Z * V_SIDESTEP)
				-- Hold it until this orb has landed (0.5s after its lock).
				getgenv().SB2VaelEscapePos = dest
				getgenv().SB2VaelEscapeUntil = now + 0.55
				getgenv().SB2LastDodgeMoveAt = now
				getgenv().SB2DodgeLog('vaelith-orb', 'orb locked, step ' .. V_SIDESTEP, dest)
				return dest
			end
			return held
		end

		-- All projectile dodges in one place. Nythrane's orb dodge is off unless
		-- getgenv().SB2DodgeNythraneOrbs = true (it was dodging him too often).
		-- Rubricatus RedLightningDiscs (game code): 3 discs per throw, 25% each, no range or
		-- height limit. Each disc re-aims at you until it is released, then flies to that locked
		-- spot (written on the disc as attribute "LockedTarget") and hits anything within ~6 studs
		-- of its path. Once a disc's LockedTarget is near you, step 24 studs sideways to its path.
		local discHandled = setmetatable({}, { __mode = 'k' })
		-- Rubricatus discs (RedLightningDiscs): each disc reads your live HumanoidRootPart position
		-- at its own release (0.1s apart), then flies there; it only hurts within ~6 studs of its
		-- path. So: sidestep for EVERY new disc that locks onto you, not once per volley, and match
		-- on flat distance (up at the Rubricatus final-phase height the position the game read can
		-- differ in Y from what this loop sees). Also counts a lock on the spot we are holding.
		function M.discEscape(hrp, now)
			local here = hrp.Position
			local held = getgenv().SB2DiscEscapePos
			if typeof(held) == 'Vector3' and now >= (tonumber(getgenv().SB2DiscEscapeUntil) or 0) then
				held = nil
				getgenv().SB2DiscEscapePos = nil
			end
			local function flat(a, b)
				return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
			end
			local spots = { here }
			if typeof(held) == 'Vector3' then
				spots[#spots + 1] = held
			end
			local pin = getgenv().SB2DivePinPos
			if typeof(pin) == 'Vector3' then
				spots[#spots + 1] = pin
			end
			for _, folder in ipairs(workspace:GetChildren()) do
				if folder.Name == 'RedLightningDiscEffects' then
					for _, m in ipairs(folder:GetDescendants()) do
						local tgt = m:GetAttribute('LockedTarget')
						if typeof(tgt) == 'Vector3' and not discHandled[m] then
							local hit = false
							for _, sp in ipairs(spots) do
								if flat(tgt, sp) < 16 then
									hit = true
									break
								end
							end
							if hit then
								discHandled[m] = true
								local base = held or here
								local from = m:IsA('Model') and m:GetPivot().Position or (m:IsA('BasePart') and m.Position) or base
								local path = Vector3.new(tgt.X - from.X, 0, tgt.Z - from.Z)
								local side = path.Magnitude > 0.5 and Vector3.new(-path.Z, 0, path.X).Unit or Vector3.new(1, 0, 0)
								local mid = waveDefenseRiftsCenterFlat()
								-- Every disc still flying in this volley: don't step onto another one's target.
								local targets = {}
								for _, f2 in ipairs(workspace:GetChildren()) do
									if f2.Name == 'RedLightningDiscEffects' then
										for _, m2 in ipairs(f2:GetDescendants()) do
											local t2 = m2:GetAttribute('LockedTarget')
											if typeof(t2) == 'Vector3' then
												targets[#targets + 1] = t2
											end
										end
									end
								end
								local best, bestScore = nil, nil
								for _, r in ipairs({ 24, 40 }) do
									for _, dir in ipairs({ side, -side }) do
										local cand = Vector3.new(tgt.X + dir.X * r, base.Y, tgt.Z + dir.Z * r)
										local clear = math.huge
										for _, t2 in ipairs(targets) do
											clear = math.min(clear, flat(cand, t2))
										end
										local d = mid and (Vector3.new(cand.X, 0, cand.Z) - mid).Magnitude or 0
										-- Clear of every target first, then closest to the middle.
										local score = (clear >= 18 and 0 or 1e6) + d
										if not bestScore or score < bestScore then
											best, bestScore = cand, score
										end
									end
								end
								held = best
								getgenv().SB2DiscEscapePos = best
								getgenv().SB2DiscEscapeUntil = now + 1.2
								getgenv().SB2LastDodgeMoveAt = now
								getgenv().SB2DodgeLog('rub-disc', ('disc locked %.0f studs from you (flat)'):format(flat(tgt, here)), best)
								-- Later discs in this volley lock onto the new spot; keep scanning.
								spots[#spots + 1] = best
							end
						end
					end
				end
			end
			return held
		end

		-- Several Atheons can nuke a few seconds apart, and the hook only keeps the latest one,
		-- so remember every cast here. Each stays dangerous until its own estimated landing.
		-- Per-frame fling guard. The main loop only runs a few times a second, so a knockback
		-- at Bob's perch (Y 360) could throw you into the void between ticks (speeds of 500-3600
		-- were logged right after every Bob lift). While an air hold is pinned, snap back to the
		-- pin every physics frame if you get shoved off it or pick up absurd speed.
		do
			local RunServiceG = game:GetService('RunService')
			for _, k in ipairs({ 'SB2AfdFlingGuardStep', 'SB2AfdFlingGuardBeat' }) do
				local old = getgenv()[k]
				if old then
					pcall(function()
						old:Disconnect()
					end)
					getgenv()[k] = nil
				end
			end
			local lastLog = 0
			local function guard()
				if getgenv().SB2AutoFloorDodgeOn ~= true or not workspace:FindFirstChild('WaveDefenseStuff') then
					return
				end
				local char = LocalPlayer.Character
				local hrp = char and char:FindFirstChild('HumanoidRootPart')
				if not hrp or (type(isLocalAlive) == 'function' and not isLocalAlive()) then
					return
				end
				-- Void, every frame: below -500 Roblox deletes your HumanoidRootPart (that is a death).
				if hrp.Position.Y < WD_LAVA_FLOOR_Y - 60 then
					local mid = waveDefenseRiftsCenterFlat()
					if mid then
						local safe = Vector3.new(mid.X, WD_LAVA_FLOOR_Y + 4, mid.Z)
						local fellY = hrp.Position.Y
						pcall(function()
							hrp.AssemblyLinearVelocity = Vector3.zero
							hrp.AssemblyAngularVelocity = Vector3.zero
							hrp.CFrame = CFrame.new(safe)
						end)
						pcall(getgenv().SB2DiveResetHold or function() end, safe)
						local now = os.clock()
						if now - lastLog > 1 then
							lastLog = now
							getgenv().SB2DodgeLog('void-rescue', ('frame guard, was at Y %.0f'):format(fellY), safe)
						end
					end
					return
				end
				local airHold = getgenv().SB2BobEscapeActive == true
					or getgenv().SB2LavaEscapeActive == true
					or typeof(getgenv().SB2RubFinalPos) == 'Vector3'
				local pin = getgenv().SB2DivePinPos
				if not airHold or typeof(pin) ~= 'Vector3' then
					return
				end
				pin = getgenv().SB2AFD_roofClamp(pin)
				local v = hrp.AssemblyLinearVelocity
				local off = (hrp.Position - pin).Magnitude
				if v.Magnitude > 150 or off > 30 then
					pcall(function()
						hrp.AssemblyLinearVelocity = Vector3.zero
						hrp.AssemblyAngularVelocity = Vector3.zero
						hrp.CFrame = CFrame.new(pin) * (hrp.CFrame - hrp.CFrame.Position)
					end)
					local now = os.clock()
					if now - lastLog > 2 then
						lastLog = now
						getgenv().SB2DodgeLog('fling-guard', ('speed %.0f, %.0f off pin'):format(v.Magnitude, off), pin)
					end
				end
			end
			getgenv().SB2AfdFlingGuardStep = RunServiceG.Stepped:Connect(guard)
			getgenv().SB2AfdFlingGuardBeat = RunServiceG.Heartbeat:Connect(guard)
		end

		M.atheonNukes = M.atheonNukes or {}
		function M.atheonTrackNukes(now)
			local at = tonumber(getgenv().SB2AtheonNukeAt) or 0
			local center = getgenv().SB2AtheonNukeGoal
			local list = M.atheonNukes
			if at > 0 and typeof(center) == 'Vector3' and now - at <= 7 then
				local known = false
				for _, n in ipairs(list) do
					if n.at == at then
						known = true
						break
					end
				end
				if not known then
					local life = tonumber(getgenv().SB2AtheonNukeLife) or 3
					list[#list + 1] = { at = at, center = center, impact = at + math.max(3.7, life + 0.7) }
				end
			end
			-- The hook's real landing time belongs to whichever nuke landed last: the oldest one
			-- still waiting that is due by now.
			local landed = tonumber(getgenv().SB2AtheonNukeImpactAt) or 0
			for i = #list, 1, -1 do
				local n = list[i]
				if landed >= n.at and landed <= n.impact + 1 and not n.landed then
					local older = false
					for _, o in ipairs(list) do
						if o ~= n and not o.landed and o.at < n.at then
							older = true
							break
						end
					end
					if not older then
						n.landed = true
						n.impact = landed
					end
				end
				if now > n.impact + 0.8 or now - n.at > 7 then
					table.remove(list, i)
				end
			end
			return list
		end

		-- Corrupted Atheon's nuke: a ground-up slam column, 100% damage inside ~150 studs of its
		-- centre (height doesn't help). The Atheon Shadow Step script hooks his skill and records
		-- SB2AtheonNukeAt (cast) / SB2AtheonNukeGoal (centre) / SB2AtheonNukeImpactAt. Stand
		-- 165+ studs from EVERY nuke still to land, not just the newest (wave 96 has three Atheons).
		function M.atheonNuke(hrp, now)
			-- Wave defense only; manual grinding is the Atheon Shadow Step script's job.
			if not workspace:FindFirstChild('WaveDefenseStuff') then
				getgenv().SB2AtheonEscapePos = nil
				M.atheonNukes = {}
				return nil
			end
			local list = M.atheonTrackNukes(now)
			if #list == 0 then
				getgenv().SB2AtheonEscapePos = nil
				return nil
			end
			local want = tonumber(getgenv().SB2DodgeAtheonOut) or 165
			local function minDist(pos)
				local m = math.huge
				for _, n in ipairs(list) do
					local d = Vector3.new(pos.X - n.center.X, 0, pos.Z - n.center.Z).Magnitude
					if d < m then
						m = d
					end
				end
				return m
			end
			local here = hrp.Position
			local key = ''
			for _, n in ipairs(list) do
				key = key .. tostring(n.at) .. ';'
			end
			local held = getgenv().SB2AtheonEscapePos
			if typeof(held) == 'Vector3' and getgenv().SB2AtheonEscapeFor == key then
				return held
			end
			-- Already clear of all of them: stay put.
			if minDist(here) >= want then
				getgenv().SB2AtheonEscapePos = here
				getgenv().SB2AtheonEscapeFor = key
				return here
			end
			-- Candidates: rings around every centre, plus a grid over the arena.
			local cands = {}
			for _, n in ipairs(list) do
				for i = 0, 23 do
					local a = i * math.pi / 12
					for _, r in ipairs({ want, want + 25 }) do
						cands[#cands + 1] = Vector3.new(n.center.X + math.cos(a) * r, 0, n.center.Z + math.sin(a) * r)
					end
				end
			end
			local mid = waveDefenseRiftsCenterFlat and waveDefenseRiftsCenterFlat() or nil
			local cx, cz = mid and mid.X or here.X, mid and mid.Z or here.Z
			for gx = -200, 200, 25 do
				for gz = -200, 200, 25 do
					cands[#cands + 1] = Vector3.new(cx + gx, 0, cz + gz)
				end
			end
			local bestSafe, bestSafeTravel = nil, math.huge
			local bestAny, bestAnyMin = nil, -1
			for _, c in ipairs(cands) do
				local md = minDist(c)
				if md >= want or md > bestAnyMin then
					if M.floorStandY(hrp, c.X, c.Z) then
						local pos = Vector3.new(c.X, here.Y, c.Z)
						if md >= want then
							local travel = (Vector3.new(here.X, 0, here.Z) - c).Magnitude
							if travel < bestSafeTravel then
								bestSafe, bestSafeTravel = pos, travel
							end
						end
						if md > bestAnyMin then
							bestAny, bestAnyMin = pos, md
						end
					end
				end
			end
			local dest = bestSafe or bestAny
			if not dest then
				return nil
			end
			getgenv().SB2AtheonEscapePos = dest
			getgenv().SB2AtheonEscapeFor = key
			getgenv().SB2LastDodgeMoveAt = now
			getgenv().SB2DodgeLog('atheon-nuke', ('%d nuke(s) live, was %.0f from nearest -> %.0f%s'):format(
				#list, minDist(here), minDist(dest), bestSafe and '' or ' (best possible)'), dest)
			return dest
		end

		function M.projectileEscape(hrp, now)
			local dsc = M.discEscape(hrp, now)
			if dsc then
				return dsc
			end
			local v = M.vaelithEscape(hrp, now)
			if v then
				return v
			end
			if getgenv().SB2DodgeNythraneOrbs == true then
				return M.orbEscape(hrp, now)
			end
			return nil
		end

		function M.orbEscape(hrp, now)
			local held = getgenv().SB2OrbEscapePos
			local here = hrp.Position
			local threat = nil
			for _, ch in ipairs(workspace:GetChildren()) do
				if isNythraneOrb(ch) then
					local rec = orbSeen[ch]
					if not rec then
						rec = { p0 = ch.Position, t0 = now }
						orbSeen[ch] = rec
					end
					local age = now - rec.t0
					if age < ORB_LIFE + 0.5 then
						-- Straight line, constant speed: landing = start + velocity * remaining flight.
						local target
						if age > 0.08 then
							local v = (ch.Position - rec.p0) / age
							target = ch.Position + v * math.max(0, ORB_LIFE - age)
						else
							target = here -- just fired: assume it's aimed at you
						end
						local spot = typeof(held) == 'Vector3' and now < (tonumber(getgenv().SB2OrbEscapeUntil) or 0) and held or here
						if (target - spot).Magnitude < ORB_DANGER then
							threat = { target = target, from = rec.p0 }
							break
						end
					end
				end
			end
			if not threat then
				if typeof(held) == 'Vector3' and now < (tonumber(getgenv().SB2OrbEscapeUntil) or 0) then
					return held
				end
				getgenv().SB2OrbEscapePos = nil
				return nil
			end
			-- Step sideways to the orb's path (flat), toward the middle when there's a choice.
			local path = Vector3.new(threat.target.X - threat.from.X, 0, threat.target.Z - threat.from.Z)
			local side = path.Magnitude > 0.5 and Vector3.new(-path.Z, 0, path.X).Unit or Vector3.new(1, 0, 0)
			local mid = waveDefenseRiftsCenterFlat()
			local best, bestScore = nil, nil
			for _, dir in ipairs({ side, -side }) do
				local cand = Vector3.new(here.X + dir.X * ORB_STEP, here.Y, here.Z + dir.Z * ORB_STEP)
				local score = (cand - threat.target).Magnitude
				if mid then
					score -= 0.3 * (Vector3.new(cand.X, 0, cand.Z) - mid).Magnitude
				end
				if not bestScore or score > bestScore then
					best, bestScore = cand, score
				end
			end
			getgenv().SB2OrbEscapePos = best
			getgenv().SB2OrbEscapeUntil = now + 1.6
			getgenv().SB2LastDodgeMoveAt = now
			getgenv().SB2DodgeLog('nythrane-orb', ('landing %.0f studs from you'):format((threat.target - here).Magnitude), best)
			return best
		end

		-- Default for every wave in the arena: hover 160 studs above the floor over the middle.
		-- Waves with their own dodge (lava, Bob, orb, Aeganatos, Wendigo, Rubricatus) are handled
		-- before this in the loop; the storm and rift waves stay on the ground for their own
		-- dodges. getgenv().SB2DodgeHover160 = false turns the default hover off (ground dodging).
		-- getgenv().SB2DodgeHoverAbove changes the height.
		-- Blackout: the light is on the floor in the middle; Rubricatus: pillars/nuke need the ground.
		local GROUND_ENVS = { Tempest = true, Rift = true, Blackout = true, Rubricatus = true }
		-- Lag guard: when the connection stalls, the server keeps hitting you while your game
		-- shows nothing (then it all lands at once). On a ping spike / incoming-data stall, go up
		-- to the Bob height and stay there 4s after it clears.
		local LAG_PING_MS = 600
		local LAG_HOLD = 4
		function M.lagSpike()
			if getgenv().SB2DodgeLagGuard == false then
				return false
			end
			local now = os.clock()
			local bad, why = false, nil
			local okS, Stats = pcall(game.GetService, game, 'Stats')
			if okS and Stats then
				pcall(function()
					local item = Stats.Network.ServerStatsItem['Data Ping']
					local ms = tonumber(item:GetValue())
					if ms and ms > LAG_PING_MS then
						bad, why = true, ('ping %dms'):format(ms)
					end
				end)
			end
			if not bad then
				pcall(function()
					local rt = LocalPlayer:GetNetworkPing() * 1000
					if rt > LAG_PING_MS then
						bad, why = true, ('net ping %dms'):format(rt)
					end
				end)
			end
			if bad then
				if now - (tonumber(getgenv().SB2LagGuardUntil) or 0) > 0 then
					pcall(getgenv().SB2DodgeLog, 'lag-hover', tostring(why))
				end
				getgenv().SB2LagGuardUntil = now + LAG_HOLD
				return true
			end
			return now < (tonumber(getgenv().SB2LagGuardUntil) or 0)
		end

		-- Huge ground telegraphs (Enraged Wendigo slam: 170-stud circle + 50-wide strip, damage
		-- column ~150 tall). Walking back to the middle put you inside one. While any big
		-- EffectHitbox is on the ground, go up to the Bob height (above the column) and stay 2s
		-- after the last one is gone, whatever the wave.
		local BIG_TELEGRAPH = 60
		local bigHitboxes = setmetatable({}, { __mode = 'k' })
		if getgenv().SB2BigTelegraphConn then
			pcall(function()
				getgenv().SB2BigTelegraphConn:Disconnect()
			end)
		end
		getgenv().SB2BigTelegraphConn = workspace.DescendantAdded:Connect(function(d)
			if d.Name == 'EffectHitbox' and d:IsA('BasePart') then
				local z = d.Size
				if math.max(z.X, z.Z) >= BIG_TELEGRAPH then
					bigHitboxes[d] = true
				end
			end
		end)
		function M.bigTelegraph()
			local now = os.clock()
			local any = false
			for part in pairs(bigHitboxes) do
				if part.Parent then
					any = true
				else
					bigHitboxes[part] = nil
				end
			end
			if any then
				if now - (tonumber(getgenv().SB2BigTelegraphUntil) or 0) > 0 then
					pcall(getgenv().SB2DodgeLog, 'big-telegraph', 'hover up')
				end
				getgenv().SB2BigTelegraphUntil = now + 2
				return true
			end
			return now < (tonumber(getgenv().SB2BigTelegraphUntil) or 0)
		end

		function M.wendigoHover()
			if getgenv().SB2DodgeWendigoHover == false then
				return false
			end
			if tostring(workspace:GetAttribute('WaveDefenseEnvironment')) == 'Rubricatus' then
				return false
			end
			local ch = game:GetService('Players').LocalPlayer.Character
			local hrp = ch and ch:FindFirstChild('HumanoidRootPart')
			if not hrp or type(M.wendigoMob) ~= 'function' then
				return false
			end
			local mob = M.wendigoMob(hrp)
			if not mob or (type(M.wendigoSpecialWave) == 'function' and M.wendigoSpecialWave(mob)) then
				return false
			end
			local now = os.clock()
			if now - (tonumber(getgenv().SB2WendigoHoverLogAt) or 0) > 5 then
				getgenv().SB2WendigoHoverLogAt = now
				pcall(getgenv().SB2DodgeLog, 'wendigo-hover', tostring(mob.Name), hrp.Position)
			end
			return true
		end

		-- Enraged Wendigo slam = a 170-wide, 150-tall cylinder centred on him (reaches Bob
		-- height) plus a 50-wide strip. Keep 135+ studs sideways from him, on the far side of
		-- the arena middle, and step out of any live strip.
		function M.wendigoSafePos(hrp, dest)
			if not M.wendigoHover or not M.wendigoHover() then
				return nil
			end
			local mob = M.wendigoMob(hrp)
			if not mob then
				return nil
			end
			local ok, piv = pcall(function() return mob:GetPivot().Position end)
			if not ok or typeof(piv) ~= 'Vector3' then
				return nil
			end
			local want = tonumber(getgenv().SB2DodgeWendigoDist) or 135
			local mid = waveDefenseRiftsCenterFlat() or dest
			local w = Vector3.new(piv.X, 0, piv.Z)
			local c = Vector3.new(mid.X, 0, mid.Z)
			local away = c - w
			if away.Magnitude < 5 then
				away = Vector3.new(hrp.Position.X, 0, hrp.Position.Z) - w
			end
			if away.Magnitude < 1 then
				away = Vector3.new(1, 0, 0)
			end
			local p = c
			if (c - w).Magnitude < want then
				p = w + away.Unit * want
			end
			for part in pairs(bigHitboxes) do
				if part.Parent and part:IsA('BasePart') then
					local z = part.Size
					if math.abs(z.X - z.Z) > 20 then
						local width = math.min(z.X, z.Z)
						local cf = part.CFrame
						local axis = (z.X < z.Z) and cf.RightVector or cf.LookVector
						axis = Vector3.new(axis.X, 0, axis.Z)
						if axis.Magnitude > 0.1 then
							axis = axis.Unit
							local rel = (p - Vector3.new(cf.Position.X, 0, cf.Position.Z)):Dot(axis)
							local need = width / 2 + 25
							if math.abs(rel) < need then
								local sgn = rel >= 0 and 1 or -1
								p = p + axis * sgn * (need - math.abs(rel))
							end
						end
					end
				end
			end
			local now = os.clock()
			if now - (tonumber(getgenv().SB2WendigoSafeLogAt) or 0) > 3 then
				getgenv().SB2WendigoSafeLogAt = now
				pcall(getgenv().SB2DodgeLog, 'wendigo-distance', ('%.0f studs from it'):format((p - w).Magnitude), Vector3.new(p.X, dest.Y, p.Z))
			end
			return Vector3.new(p.X, dest.Y, p.Z)
		end

		function M.wantsHover160()
			if getgenv().SB2DodgeHover160 == false then
				return false
			end
			if getgenv().SB2DiveFarmOn == true or getgenv().SB2DiveUnderMap == true then
				return false
			end
			if not workspace:FindFirstChild('WaveDefenseStuff') or not waveDefenseRiftsCenterFlat() then
				return false
			end
			if tostring(workspace:GetAttribute('WaveDefenseEnvironment')) ~= 'Rubricatus' and M.bigTelegraph() then
				return true
			end
			-- Vaelith can show up in any arena; her orbs lock on to you up there. Ground for her.
			if findVaelithMob() then
				return false
			end
			-- Enraged Wendigo: its attacks reach the ground behind it with no telegraph, so go up
			-- to Bob height while one is alive (not in the lit-mob special waves, not Rubricatus).
			if M.wendigoHover() then
				return true
			end
			-- A Blackout wave can happen in any arena: the orb itself is the signal.
			local RLb = getgenv().SB2RedLaser
			if RLb and type(RLb.findBlackoutOrb) == 'function' and RLb.findBlackoutOrb() then
				return false
			end
			-- Only a Reward Chest left (end of run): come down so killaura can reach it. Waits 12s
			-- after the last real mob so a post-death Rubricatus nuke can't catch you on the ground.
			do
				local mobs = workspace:FindFirstChild('Mobs')
				local chest, other = false, false
				if mobs then
					for _, m in ipairs(mobs:GetChildren()) do
						local n = string.lower(m.Name)
						if string.find(n, 'chest', 1, true) or string.find(n, 'reward', 1, true) then
							chest = true
						else
							other = true
						end
					end
				end
				local now = os.clock()
				if other or not chest then
					getgenv().SB2DodgeLastRealMobAt = now
				elseif now - (tonumber(getgenv().SB2DodgeLastRealMobAt) or 0) > 12 then
					if not getgenv().SB2DodgeChestGroundLogged then
						getgenv().SB2DodgeChestGroundLogged = true
						pcall(getgenv().SB2DodgeLog, 'chest-ground', 'only reward chest left')
					end
					return false
				end
				if other then
					getgenv().SB2DodgeChestGroundLogged = nil
				end
			end
			if M.lagSpike() then
				return true
			end
			local env = workspace:GetAttribute('WaveDefenseEnvironment')
			return not GROUND_ENVS[tostring(env)]
		end

		function M.hover160(hrp, now)
			local mid = waveDefenseRiftsCenterFlat()
			if not mid then
				return false
			end
			local dest = getgenv().SB2Hover160Pos
			if typeof(dest) ~= 'Vector3' or now - (tonumber(getgenv().SB2Hover160At) or 0) > 1 then
				-- Floor under the middle (looked up from just above it, not from up here).
				local floorY = groundYAtPos(mid.X, WD_LAVA_FLOOR_Y + 40, mid.Z, hrp) or WD_LAVA_FLOOR_Y
				local y = floorY + (tonumber(getgenv().SB2DodgeHoverAbove) or 160)
				local fresh = typeof(dest) ~= 'Vector3'
				dest = Vector3.new(mid.X, y, mid.Z)
				getgenv().SB2Hover160Pos = dest
				getgenv().SB2Hover160At = now
				if fresh then
					local blinkFn = getgenv().SB2DiveBlinkTeleport
					if type(blinkFn) == 'function' and dest.Y - hrp.Position.Y > 48 then
						pcall(blinkFn, hrp, dest, nil)
					end
					getgenv().SB2DodgeLog('hover-160', tostring(workspace:GetAttribute('WaveDefenseEnvironment')), dest)
				end
			end
			getgenv().SB2DodgeAirAt = now
			local orbOut = M.projectileEscape(hrp, now)
			if orbOut then
				dest = Vector3.new(orbOut.X, dest.Y, orbOut.Z)
			else
				local wsafe = M.wendigoSafePos(hrp, dest)
				if wsafe then
					dest = wsafe
				end
			end
			-- Rubricatus red laser: aimed at this spot, so hold a point off its line until it ends.
			local laserOut = getgenv().SB2RedLaser and getgenv().SB2RedLaser.escape(dest, dest)
			if laserOut then
				dest = Vector3.new(laserOut.X, dest.Y, laserOut.Z)
				getgenv().SB2LastDodgeMoveAt = now
			end
			writeHeldCF(hrp, dest, nil, 0, true, true)
			getgenv().SB2DivePinPos = dest
			resetHold(dest)
			return true
		end

		-- Rift special wave: from the middle only 3 of the 4 portals are in reach, so cycle four
		-- spots (same height) that each lean toward one portal. Dodges still win; the cycle
		-- resumes 1s after one. getgenv().SB2DodgeRiftLean (studs toward the portal, default 20)
		-- and SB2DodgeRiftInterval (seconds per spot, default 0.35) tune it.
		function M.riftCycle(hrp, now)
			local env = workspace:GetAttribute('WaveDefenseEnvironment')
			if env ~= 'Rift' and getgenv().SB2DodgeRiftForce ~= true then
				getgenv().SB2RiftCycleIdx = nil
				return false
			end
			if now - (tonumber(getgenv().SB2LastDodgeMoveAt) or -1e9) < 1 then
				return false
			end
			local center = waveDefenseRiftsCenterFlat()
			local dirs = center and waveDefenseRiftSpawnDirs(center)
			if not dirs then
				return false
			end
			local interval = math.max(0.15, tonumber(getgenv().SB2DodgeRiftInterval) or 0.35)
			local lean = tonumber(getgenv().SB2DodgeRiftLean) or 20
			local idx = (math.floor(now / interval) % #dirs) + 1
			local stand = M.floorStandY(hrp, center.X, center.Z) or hrp.Position.Y
			local d = dirs[idx]
			local dest = Vector3.new(center.X + d.X * lean, stand, center.Z + d.Z * lean)
			local first = getgenv().SB2RiftCycleIdx == nil
			if idx ~= getgenv().SB2RiftCycleIdx or (hrp.Position - dest).Magnitude > 2 then
				local portal = Vector3.new(center.X + d.X * 137, stand, center.Z + d.Z * 137)
				M.releaseHover(hrp)
				writeHeldCF(hrp, dest, portal, 0, true, true)
				getgenv().SB2RiftCycleIdx = idx
				if first then
					getgenv().SB2DodgeLog('rift-cycle', ('%d portals, %.0f studs lean, %.2fs each'):format(#dirs, lean, interval), dest)
				end
			end
			return true
		end

		-- Rubricatus final phase: once he summons the old bosses (Aegor / Nythrane / Vaelith), or
		-- sits at 0% for the survive timer, hover ~340 studs above the arena until it's over.
		-- (World Y400 made the map stream out during Bob, so it stays a bit under that.)
		-- getgenv().SB2DodgeRubFinalAbove changes the height above the floor.
		function M.rubFinal(now)
			local folder = workspace:FindFirstChild('Mobs')
			if folder then
				local rub, rubDown, summoned = false, false, false
				for _, mob in ipairs(folder:GetChildren()) do
					local key = string.gsub(string.lower(tostring(mob.Name)), '[%p%s]+', '')
					if string.find(key, 'rubricatus', 1, true) then
						rub = true
						if getgenv().SB2AFD_mobIsDead(mob) then
							rubDown = true
						end
					elseif (string.find(key, 'aegor', 1, true) or string.find(key, 'nythrane', 1, true)
						or string.find(key, 'vaelith', 1, true)) and not getgenv().SB2AFD_mobIsDead(mob)
					then
						summoned = true
					end
				end
				if rub and (summoned or rubDown) then
					getgenv().SB2RubFinalUntil = now + 3
				end
			end
			return now < (tonumber(getgenv().SB2RubFinalUntil) or 0)
		end

		function M.rubFinalHover(hrp, now)
			getgenv().SB2DodgeAirAt = now
			local mid = waveDefenseRiftsCenterFlat()
			local x, z = mid and mid.X or hrp.Position.X, mid and mid.Z or hrp.Position.Z
			local floorY = groundYAtPos(x, math.min(hrp.Position.Y, WD_LAVA_FLOOR_Y + 40) + 20, z, hrp) or WD_LAVA_FLOOR_Y
			local dest = getgenv().SB2AFD_roofClamp(Vector3.new(x, floorY + (tonumber(getgenv().SB2DodgeRubFinalAbove) or 340), z))
			local fresh = typeof(getgenv().SB2RubFinalPos) ~= 'Vector3'
			getgenv().SB2RubFinalPos = dest
			if fresh then
				local blinkFn = getgenv().SB2DiveBlinkTeleport
				if type(blinkFn) == 'function' then
					pcall(blinkFn, hrp, dest, nil)
				end
				getgenv().SB2DodgeLog('rub-final-lift', 'summoned bosses / survive timer', dest)
			end
			local out = M.projectileEscape(hrp, now)
			if out then
				dest = getgenv().SB2AFD_roofClamp(Vector3.new(out.X, dest.Y, out.Z))
			end
			writeHeldCF(hrp, dest, nil, 0, true, true)
			getgenv().SB2DivePinPos = dest
			resetHold(dest)
		end

		-- Low HP: under 60% health, go 160+ studs above the floor and every mob and stay there
		-- until you are back to 85%. getgenv().SB2DodgeLowHpPct / SB2DodgeLowHpExitPct change
		-- the thresholds (0-1).
		function M.lowHp(hrp, now)
			local pct, hpNow = M.hpPct(hrp)
			if not pct or (hpNow or 0) <= 0 then
				getgenv().SB2LowHpActive = false
				return false
			end
			-- Lift below 80%, come back down at 95%.
			local enter = tonumber(getgenv().SB2DodgeLowHpPct) or 0.80
			local exit = math.max(enter + 0.05, tonumber(getgenv().SB2DodgeLowHpExitPct) or 0.95)
			local active = getgenv().SB2LowHpActive == true
			if not active and pct < enter then
				active = true
				getgenv().SB2LowHpPos = nil
			elseif active and pct >= exit then
				active = false
			end
			getgenv().SB2LowHpActive = active
			if not active then
				getgenv().SB2LowHpPos = nil
				return false
			end
			getgenv().SB2DodgeAirAt = now
			-- Re-measure "everything" twice a second: floor under the spot and the top of every live mob.
			local dest = getgenv().SB2LowHpPos
			if typeof(dest) ~= 'Vector3' or now - (tonumber(getgenv().SB2LowHpAt) or 0) > 0.5 then
				local mid = waveDefenseRiftsCenterFlat()
				local x, z = mid and mid.X or hrp.Position.X, mid and mid.Z or hrp.Position.Z
				-- Measure the floor from just above it, not from wherever you are hovering.
				local floorY = groundYAtPos(x, math.min(hrp.Position.Y, WD_LAVA_FLOOR_Y + 40) + 20, z, hrp) or (hrp.Position.Y - 3)
				local top = floorY
				local folder = workspace:FindFirstChild('Mobs')
				if folder then
					for _, mob in ipairs(folder:GetChildren()) do
						if not mobIsDead(mob) and mob:IsA('Model') then
							local ok, cf, size = pcall(mob.GetBoundingBox, mob)
							if ok and typeof(cf) == 'CFrame' and size.Y < 600 then
								top = math.max(top, cf.Position.Y + size.Y * 0.5)
							end
						end
					end
				end
				-- 160 over the tallest thing, but never 195+ over the floor: your attack reach is
				-- 200 studs, and a tall boss pushed the lift to 194 up (Y224) out of range.
				local cap = tonumber(getgenv().SB2DodgeLowHpMaxAbove) or 160
				local y = math.min(top + 160, floorY + cap)
				local fresh = typeof(dest) ~= 'Vector3'
				if fresh or math.abs(dest.Y - y) > 4 or Vector3.new(dest.X - x, 0, dest.Z - z).Magnitude > 4 then
					dest = Vector3.new(x, y, z)
				end
				getgenv().SB2LowHpPos = dest
				getgenv().SB2LowHpAt = now
				if fresh then
					local blinkFn = getgenv().SB2DiveBlinkTeleport
					if type(blinkFn) == 'function' then
						pcall(blinkFn, hrp, dest, nil)
					end
					getgenv().SB2DodgeLog('low-hp-lift', ('%d%% hp'):format(math.floor(pct * 100)), dest)
				end
			end
			local orbOut = M.projectileEscape(hrp, now)
			if orbOut then
				dest = Vector3.new(orbOut.X, dest.Y, orbOut.Z)
			end
			-- Rubricatus red laser: aimed at this spot, so hold a point off its line until it ends.
			local laserOut = getgenv().SB2RedLaser and getgenv().SB2RedLaser.escape(dest, dest)
			if laserOut then
				dest = Vector3.new(laserOut.X, dest.Y, laserOut.Z)
				getgenv().SB2LastDodgeMoveAt = now
			end
			writeHeldCF(hrp, dest, nil, 0, true, true)
			getgenv().SB2DivePinPos = dest
			resetHold(dest)
			return true
		end

		-- Wendigo: stand at least 120 studs behind the nearest one (opposite the way it faces).
		-- getgenv().SB2DodgeWendigoBehind overrides the distance.
		local function isWendigoMob(mob)
			if mobIsDead(mob) then
				return false
			end
			if string.find(string.lower(tostring(mob.Name)), 'wendigo', 1, true) then
				return true
			end
			local plate = mob:FindFirstChild('Nameplate')
			local label = plate and plate:FindFirstChildWhichIsA('TextLabel', true)
			return label ~= nil and string.find(string.lower(tostring(label.Text)), 'wendigo', 1, true) ~= nil
		end

		function M.wendigoMob(hrp)
			local folder = workspace:FindFirstChild('Mobs')
			if not folder then
				return nil
			end
			local best, bestD = nil, nil
			for _, mob in ipairs(folder:GetChildren()) do
				if isWendigoMob(mob) then
					local p = mobStrikePos(mob)
					if p then
						local d = (Vector3.new(p.X, 0, p.Z) - Vector3.new(hrp.Position.X, 0, hrp.Position.Z)).Magnitude
						if not bestD or d < bestD then
							best, bestD = mob, d
						end
					end
				end
			end
			if best then
				getgenv().SB2WendigoSeenUntil = os.clock() + 1.5
			end
			return best
		end

		-- Wendigo inside a special wave (Wisp / Blackout): the
		-- behind dodge would pull you off the mob you need to hit (and out of the light).
		local WENDIGO_SKIP_ENVS = { Wisp = true, Blackout = true }
		function M.wendigoSpecialWave(mob)
			if getgenv().SB2DodgeWendigoSpecialSkip == false then
				return false
			end
			local env = workspace:GetAttribute('WaveDefenseEnvironment')
			if env and WENDIGO_SKIP_ENVS[env] then
				return true
			end
			return false
		end

		function M.wendigo(hrp, mob, fresh)
			local pos, look = mobFlatLook(mob)
			if not pos then
				return false
			end
			local want = math.max(120, tonumber(getgenv().SB2DodgeWendigoBehind) or 130)
			-- Behind it; if that's off the floor, try a bit closer (never under 120), then its sides.
			local dest
			for _, dir in ipairs({ -look, Vector3.new(-look.X + look.Z, 0, -look.Z - look.X).Unit, Vector3.new(-look.X - look.Z, 0, -look.Z + look.X).Unit }) do
				for _, dist in ipairs({ want, 120 }) do
					local x, z = pos.X + dir.X * dist, pos.Z + dir.Z * dist
					local stand = M.floorStandY(hrp, x, z)
					if stand then
						dest = Vector3.new(x, stand, z)
						break
					end
				end
				if dest then
					break
				end
			end
			if not dest then
				return false
			end
			-- It turns to face you, which swings "behind" around; only move when it shifts 8+ studs.
			local held = getgenv().SB2WendigoHold
			if typeof(held) == 'Vector3' and (held - dest).Magnitude < 8 then
				dest = held
			end
			getgenv().SB2WendigoHold = dest
			M.releaseHover(hrp)
			if (hrp.Position - dest).Magnitude > 2 then
				writeHeldCF(hrp, dest, pos, 0, true, true)
				if fresh then
					getgenv().SB2DodgeLog('wendigo-behind', mob.Name, dest)
				end
			end
			return true
		end

		-- Darkner orb: stay at its center a couple of studs under it, or on top of it
		-- when under would be inside the floor.
		function M.orb(hrp, orbPos, fresh)
			getgenv().SB2DodgeAirAt = os.clock()
			local part = M.orbPart()
			local half = part and part.Size.Y * 0.5 or 2
			local body = humanoidHip(hrp) + hrp.Size.Y * 0.5
			-- Floor under the orb, looked up from above the arena (from your own height it found
			-- nothing once you were already under the map, and left you there).
			local gy = groundYAtPos(orbPos.X, math.max(orbPos.Y + half + 20, WD_LAVA_FLOOR_Y + 40), orbPos.Z, hrp)
			local floor = (gy or WD_LAVA_FLOOR_Y) + body
			local y = orbPos.Y - half - 2 - body
			-- The orb's light sphere is ~50 studs tall: "just under it" is inside the floor.
			-- Stand on the floor inside the light instead (never on top of it, never below).
			if y < floor then
				y = floor
			end
			local dest = Vector3.new(orbPos.X, y, orbPos.Z)
			getgenv().SB2DarknerOrbXZ = Vector3.new(orbPos.X, 0, orbPos.Z)
			getgenv().SB2DarknerOrbStandY = y
			if (hrp.Position - dest).Magnitude > 1.5 then
				writeHeldCF(hrp, dest, nil, 0, true, true)
				resetHold(dest)
				if fresh then
					getgenv().SB2DodgeLog('orb-hold', part and part:GetFullName() or nil, dest)
				end
			end
		end

		-- Stick to the middle: rifts sit ~137 studs out, right at killaura's reach, so drifting
		-- off-center left a far rift's mobs unhit. Walk back once nothing needs dodging.
		-- getgenv().SB2DodgeStickMiddle = false turns it off.
		local LEASH_RADIUS = 8
		local LEASH_STEP = 30
		local LEASH_PAUSE = 1.2
		local UIS = game:GetService('UserInputService')
		-- When you sit 20+ studs off the middle, write down which rule is holding you there
		-- (once every 2s per reason) so a stuck walk-back can be traced in _dodge_log.txt.
		local waitKey, waitAt = nil, 0
		local function waitWhy(d, reason, hrp, now)
			if d and d > 20 and (reason ~= waitKey or now - waitAt > 2) then
				waitKey, waitAt = reason, now
				getgenv().SB2DodgeLog('recenter-wait', string.format('%.0f off: %s', d, reason), hrp.Position)
			end
			return false
		end

		-- End of run (only the reward chest left, set by wantsHover160's chest-ground rule):
		-- killaura can't reach it from the middle (~114+ studs), so the walk-back goes to a
		-- spot 8 studs from the chest instead.
		local function chestStandFlat(center)
			if getgenv().SB2DodgeChestGroundLogged ~= true then
				return nil
			end
			local mobs = workspace:FindFirstChild('Mobs')
			if not mobs then
				return nil
			end
			for _, m in ipairs(mobs:GetChildren()) do
				local n = string.lower(m.Name)
				if string.find(n, 'reward', 1, true) and string.find(n, 'chest', 1, true) and m:GetAttribute('Died') ~= true then
					local ok, piv = pcall(function() return m:GetPivot().Position end)
					if ok and typeof(piv) == 'Vector3' then
						local to = Vector3.new(center.X - piv.X, 0, center.Z - piv.Z)
						local off = to.Magnitude > 1 and to.Unit * 8 or Vector3.new(8, 0, 0)
						return Vector3.new(piv.X + off.X, center.Y, piv.Z + off.Z)
					end
				end
			end
			return nil
		end
		M.chestStandFlat = chestStandFlat

		function M.recenter(hrp, now)
			if getgenv().SB2DodgeStickMiddle == false then
				return false
			end
			local center = waveDefenseRiftsCenterFlat()
			if not center then
				return false
			end
			local chestSpot = chestStandFlat(center)
			if chestSpot then
				center = chestSpot
			end
			local dx, dz = center.X - hrp.Position.X, center.Z - hrp.Position.Z
			local d = math.sqrt(dx * dx + dz * dz)
			if d <= LEASH_RADIUS then
				return false
			end
			if now - (tonumber(getgenv().SB2LastDodgeMoveAt) or -1e9) < LEASH_PAUSE then
				return false
			end
			if now < (tonumber(getgenv().SB2RecenterBackoffUntil) or 0) then
				return waitWhy(d, 'backoff (a dodge fired right after the last walk-back)', hrp, now)
			end
			-- Storm dodge still holding its safe spot.
			if now < (tonumber(getgenv().SB2LightningHoldUntil) or 0) then
				return waitWhy(d, 'storm safe-spot hold', hrp, now)
			end
			-- You are steering yourself.
			if UIS:GetFocusedTextBox() == nil then
				for _, k in ipairs({ Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D }) do
					if UIS:IsKeyDown(k) then
						return false
					end
				end
			end
			-- Only hold off when you are really in the air. The Humanoid flips to "Freefall"
			-- about half the time while standing on the arena floor, which blocked the walk back.
			local standHere = M.floorStandY(hrp, hrp.Position.X, hrp.Position.Z)
			if standHere and hrp.Position.Y - standHere > 8 then
				return waitWhy(d, ('in the air (%.0f up)'):format(hrp.Position.Y - standHere), hrp, now)
			end
			-- Storm wave: the walk back kept teleporting you into the next bolt's circle right
			-- after the dodge got you out. Only step to a spot clear of every live bolt
			-- (shorter steps if the full one isn't), else wait where you are.
			local circ = getgenv().SB2TempestCircles
			local live = type(circ) == 'table' and now - (tonumber(getgenv().SB2TempestCirclesAt) or -1e9) < 0.6
			local dest
			for _, try in ipairs({ LEASH_STEP, 20, 10 }) do
				local step = math.min(try, d)
				local cand = Vector3.new(hrp.Position.X + dx / d * step, hrp.Position.Y, hrp.Position.Z + dz / d * step)
				local clear = true
				if live then
					for _, c in ipairs(circ) do
						local cx, cz = cand.X - c.x, cand.Z - c.z
						local need = c.r + 28
						if cx * cx + cz * cz < need * need then
							clear = false
							break
						end
					end
				end
				if clear then
					dest = cand
					break
				end
			end
			if not dest then
				return waitWhy(d, 'storm bolts between you and the middle', hrp, now)
			end
			if not M.floorStandY(hrp, dest.X, dest.Z) then
				return waitWhy(d, 'no floor at the next step', hrp, now)
			end
			if not writeHeldCF(hrp, dest, nil, 1.6, true, false) then
				return waitWhy(d, 'move refused', hrp, now)
			end
			getgenv().SB2LastRecenterAt = now
			getgenv().SB2DodgeLog('recenter', string.format('%.0f studs off', d), dest)
			return true
		end
	end)()

	local function startAutoFloorDodgeLoop()
		local function bobThreatsAround(origin)
			local threats = {}
			local function addPart(part)
				if not part or not part:IsA('BasePart') or part.Transparency >= 0.995 then
					return
				end
				local n = string.lower(part.Name)
				local dx = part.Position.X - origin.X
				local dz = part.Position.Z - origin.Z
				if (dx * dx + dz * dz) > (220 * 220) then
					return
				end
				if string.find(n, 'circle', 1, true) or string.find(n, 'puddle', 1, true) or string.find(n, 'ring', 1, true) then
					threats[#threats + 1] = {
						c = true,
						x = part.Position.X,
						z = part.Position.Z,
						r = math.max(part.Size.X, part.Size.Z) * 0.5 + 8,
					}
				elseif n == 'box' or string.find(n, 'hitbox', 1, true) then
					local cf = part.CFrame
					local right = Vector3.new(cf.RightVector.X, 0, cf.RightVector.Z)
					local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
					if right.Magnitude < 0.05 then
						right = Vector3.new(1, 0, 0)
					else
						right = right.Unit
					end
					if look.Magnitude < 0.05 then
						look = Vector3.new(0, 0, 1)
					else
						look = look.Unit
					end
					threats[#threats + 1] = {
						c = false,
						x = part.Position.X,
						z = part.Position.Z,
						rx = right.X,
						rz = right.Z,
						lx = look.X,
						lz = look.Z,
						hx = part.Size.X * 0.5 + 8,
						hz = part.Size.Z * 0.5 + 8,
					}
				end
			end
			for _, ch in ipairs(workspace:GetChildren()) do
				if ch:IsA('BasePart') then
					addPart(ch)
				end
			end
			return threats
		end

		local function bobSpotInside(threats, x, z)
			for i = 1, #threats do
				local t = threats[i]
				local dx, dz = x - t.x, z - t.z
				if t.c then
					if dx * dx + dz * dz < t.r * t.r then
						return true
					end
				else
					local alongR = math.abs(dx * t.rx + dz * t.rz)
					local alongL = math.abs(dx * t.lx + dz * t.lz)
					if alongR < t.hx and alongL < t.hz then
						return true
					end
				end
			end
			return false
		end
		if not isToggleOn('AutoFloorDodge') then
			stopAutoFloorDodgeLoop()
			return
		end
		getgenv().SB2AutoFloorDodgeOn = true
		local prev = getgenv().SB2AutoFloorDodgeConn
		if prev then
			pcall(function()
				prev:Disconnect()
			end)
			getgenv().SB2AutoFloorDodgeConn = nil
		end
		local lastStep = 0
		local blackoutSeenUntil = 0
		local blackoutScanAt = 0
		local function isBlackout(now)
			if now - blackoutScanAt >= 0.15 then
				blackoutScanAt = now
				local env = workspace:GetAttribute('WaveDefenseEnvironment')
				if env == 'Blackout' then
					blackoutSeenUntil = now + 1.2
				end
			end
			return now < blackoutSeenUntil
		end
		getgenv().SB2AutoFloorDodgeConn = RunService.Heartbeat:Connect(function()
			local okTick, errTick = pcall(function()
			if not inWdDodgeContext()
				and (
					typeof(getgenv().SB2LavaFightY) == 'number'
					or typeof(getgenv().SB2BobHoldY) == 'number'
					or typeof(getgenv().SB2LavaHoverY) == 'number'
				)
			then
				clearWdDodgeHoverState()
			end
			if getgenv().SB2AutoFloorDodgeOn ~= true or not isToggleOn('AutoFloorDodge') then
				local conn = getgenv().SB2AutoFloorDodgeConn
				if conn then
					pcall(function()
						conn:Disconnect()
					end)
					getgenv().SB2AutoFloorDodgeConn = nil
				end
				clearLavaHover()
				getgenv().SB2DarknerOrbXZ = nil
				getgenv().SB2DarknerOrbStandY = nil
				getgenv().SB2WendigoHold = nil
				return
			end
			-- Event dive fight loop already sidesteps circles (same scanner).
			-- Floor-is-lava still hovers here so dive cannot plant you in the floor.
			local nowPre = os.clock()
			local lavaNow = floorLavaActive(nowPre)
			if not lavaNow then
				getgenv().SB2LavaEscapeActive = false
				getgenv().SB2LavaHoverY = nil
				if lavaClearAt == 0 then
					lavaClearAt = nowPre
				elseif nowPre - lavaClearAt >= 0.35 then
					lavaFightY = nil
					getgenv().SB2LavaFightY = nil
					if lavaStandY ~= nil and not findRubricatusMob() then
						lavaStandY = nil
						hoverGroundY = nil
					end
				end
			else
				lavaClearAt = 0
			end
			local bossNow = bossHoverActive(nowPre)
			if not bossNow then
				bossClearanceHeld = nil
				bossSeenUntil = 0
			end
			local orbEarly = darknerOrbCenter()
			local wendigoNow = refreshWendigo(nowPre)
			local bobNow = findBobMob()
			if bobNow then
				bobSeenUntil = nowPre + 1.5
				getgenv().SB2BobLastSeenAt = nowPre
			elseif nowPre - (tonumber(getgenv().SB2BobLastSeenAt) or -1e9) < 30
				and nowPre - (tonumber(getgenv().SB2BobLeftoverScanAt) or 0) >= 0.25
			then
				-- Bob's attack grid keeps dropping rows of circles for seconds after he dies;
				-- leaving his perch 1.5s after him put you under a row (100%). Stay up while
				-- any of his attack parts are still in the arena.
				getgenv().SB2BobLeftoverScanAt = nowPre
				for _, ch in ipairs(workspace:GetChildren()) do
					local n = ch.Name
					if n == 'Circle' or n == 'EffectHitbox' or n == 'ImpactProjectile' or n == 'Gas' then
						bobSeenUntil = math.max(bobSeenUntil, nowPre + 1.5)
						break
					end
				end
			end
			if not isLocalAlive() then
				return
			end
			local model = getMyCharacterModel() or LocalPlayer.Character
			local hrp = model and model:FindFirstChild('HumanoidRootPart')
			if not hrp or not hrp:IsA('BasePart') then
				return
			end
			-- Physics glitch guard: teleporting between holds once spiked you to -111,000 studs/s
			-- and threw you below the map (counted as a death). Cancel any absurd speed, and if you
			-- are ever far below the arena floor, put you back over the middle.
			do
				local v = hrp.AssemblyLinearVelocity
				if v.Magnitude > 250 then
					hrp.AssemblyLinearVelocity = Vector3.zero
					hrp.AssemblyAngularVelocity = Vector3.zero
					if nowPre - (tonumber(getgenv().SB2FlingLogAt) or 0) > 2 then
						getgenv().SB2FlingLogAt = nowPre
						getgenv().SB2DodgeLog('fling-stop', ('speed %.0f'):format(v.Magnitude), hrp.Position)
					end
				end
				if workspace:FindFirstChild('WaveDefenseStuff') and hrp.Position.Y < WD_LAVA_FLOOR_Y - 60 then
					local mid = waveDefenseRiftsCenterFlat()
					if mid then
						local safe = Vector3.new(mid.X, WD_LAVA_FLOOR_Y + 4, mid.Z)
						local fellY = hrp.Position.Y
						hrp.AssemblyLinearVelocity = Vector3.zero
						writeHeldCF(hrp, safe, nil, 0, true, true)
						pcall(getgenv().SB2DiveResetHold or function() end, safe)
						getgenv().SB2DodgeLog('void-rescue', ('was at Y %.0f'):format(fellY), safe)
						lastStep = nowPre
						return
					end
				end
			end
			-- Atheon nuke: get 165 studs out sideways, ahead of every other mode.
			do
				local out = getgenv().SB2DodgeModes.atheonNuke(hrp, nowPre)
				if out then
					getgenv().SB2DodgeModes.releaseHover(hrp)
					writeHeldCF(hrp, out, nil, 0, true, true)
					getgenv().SB2DivePinPos = out
					pcall(getgenv().SB2DiveResetHold or function() end, out)
					lastStep = nowPre
					return
				end
			end
			-- Rubricatus final phase: high above the map, ahead of everything else (low HP included).
			-- Except while a nuke he cast is still pending: it goes off ~10s after the cast even
			-- if he is already dead, and lifting into the open sky killed you (100%) a second
			-- before it landed. Stay in pillar cover until it has gone off, then lift.
			local rubNukePending = false
			do
				local t0 = tonumber(getgenv().SB2RubNukeT0) or -1e9
				local boom = tonumber(getgenv().SB2RubNukeBoomAt) or -1e9
				if (nowPre - t0 < 13 and boom < t0)
					or nowPre < (tonumber(getgenv().SB2RubricatusNukeUntil) or 0)
					or typeof(getgenv().SB2RubricatusCoverPos) == 'Vector3'
				then
					rubNukePending = true
				end
			end
			if rubNukePending and not findRubricatusMob() and typeof(lastRubricatusFlat) == 'Vector3' then
				local fy = rubricatusFightY(hrp)
				rubricatusInCoverWindow(nowPre, hrp.Position)
				local cover = rubricatusPillarCoverGoal(hrp.Position, fy, nil)
				if typeof(cover) ~= 'Vector3' and typeof(getgenv().SB2RubricatusCoverPos) == 'Vector3' then
					local held = getgenv().SB2RubricatusCoverPos
					cover = Vector3.new(held.X, fy, held.Z)
				end
				if typeof(cover) == 'Vector3' then
					getgenv().SB2DodgeModes.releaseHover(hrp)
					rubricatusSnapToCover(hrp, cover, nil)
					if getgenv().SB2RubDeadCoverLogged ~= getgenv().SB2RubNukeT0 then
						getgenv().SB2RubDeadCoverLogged = getgenv().SB2RubNukeT0
						getgenv().SB2DodgeLog('rub-dead-nuke-cover', 'he died mid-nuke', cover)
					end
					lastStep = nowPre
					return
				end
			end
			if not rubNukePending and getgenv().SB2DodgeModes.rubFinal(nowPre) then
				getgenv().SB2DodgeModes.rubFinalHover(hrp, nowPre)
				lastStep = nowPre
				return
			end
			getgenv().SB2RubFinalPos = nil
			-- Under 40% HP: lift 160+ studs above everything. Beats every other mode except
			-- hiding in a Rubricatus pillar while his nuke is coming (going up there is death).
			do
				local nukeCover = nowPre < (tonumber(getgenv().SB2RubricatusNukeUntil) or 0)
					and typeof(getgenv().SB2RubricatusCoverPos) == 'Vector3'
				if not nukeCover and getgenv().SB2DodgeModes.lowHp(hrp, nowPre) then
					lastStep = nowPre
					return
				end
			end
			-- Wendigo (incl. Enraged Wendigo): stay 120+ studs behind the nearest one. Checked
			-- right after low HP so no other mode can keep you next to it.
			do
				local wm = getgenv().SB2DodgeModes
				local wenMob = wm.wendigoMob(hrp)
				-- Special waves where you have to hit the lit-up mob (Wisp / Blackout): no behind dodge.
				if wenMob and wm.wendigoSpecialWave(wenMob) then
					if nowPre - (tonumber(getgenv().SB2WendigoSkipLogAt) or 0) > 5 then
						getgenv().SB2WendigoSkipLogAt = nowPre
						getgenv().SB2DodgeLog('wendigo-skip-special', tostring(workspace:GetAttribute('WaveDefenseEnvironment')), hrp.Position)
					end
					wenMob = nil
				end
				if wenMob and wm.wendigoHover and wm.wantsHover160() then
					getgenv().SB2WendigoHold = nil
					wm.hover160(hrp, nowPre)
					lastStep = nowPre
					return
				end
				if wenMob then
					local moved = wm.wendigo(hrp, wenMob, getgenv().SB2WendigoHold == nil)
					if nowPre - (tonumber(getgenv().SB2WendigoSeenLogAt) or 0) > 3 then
						getgenv().SB2WendigoSeenLogAt = nowPre
						local wp = mobStrikePos(wenMob)
						getgenv().SB2DodgeLog('wendigo-seen', ('%s %.0f studs away, holding=%s'):format(
							wenMob.Name, wp and (wp - hrp.Position).Magnitude or -1, tostring(moved)), hrp.Position)
					end
					if moved then
						lastStep = nowPre
						return
					end
				else
					getgenv().SB2WendigoHold = nil
				end
			end
			-- Floor dodge only. Lava is the one fight that stays in the air.
			-- Rubricatus stays on the floor (dodge + pillar cover). His red parts are
			-- not the lava wave. Elite flies only for the 90s after he dies.
			local bobAir = nowPre < bobSeenUntil
			if not bobAir then
				getgenv().SB2BobEscapeActive = false
				getgenv().SB2BobHoldY = nil
				bobHoldY = nil
				bobEscapeFlat = nil
			end
			local rubMob = findRubricatusMob()
			if rubMob then
				rubricatusSeenUntil = nowPre + RUBRICATUS_LEFTOVER_GRACE
				local bossFlat = rubricatusBossFlat(rubMob)
				if bossFlat then
					lastRubricatusFlat = bossFlat
				end
			end
			local rubGrace = nowPre < rubricatusSeenUntil
			local modeName = workspace:GetAttribute('WaveDefenseMode')
			local rubEliteDead = rubGrace and not rubMob
				and type(modeName) == 'string' and string.lower(modeName) == 'elite'
			if rubMob or rubGrace then
				getgenv().SB2LavaEscapeActive = false
				getgenv().SB2LavaFightY = nil
				getgenv().SB2LavaHoverY = nil
			end
			if rubEliteDead then
				local center = waveDefenseRiftsCenterFlat()
				local holdY = WD_LAVA_FLOOR_Y + (tonumber(getgenv().SB2DodgeRubFinalAbove) or 340)
				local x = center and center.X or hrp.Position.X
				local z = center and center.Z or hrp.Position.Z
				getgenv().SB2RubricatusSurviveActive = true
				getgenv().SB2RubricatusSurviveY = holdY
				writeHeldCF(hrp, Vector3.new(x, holdY, z), nil, 0, true, true)
				return
			end
			if rubMob then
				getgenv().SB2RubricatusSurviveActive = false
				getgenv().SB2RubricatusSurviveY = nil
				local fightY = rubricatusFightY(hrp)
				local coverWindow = rubricatusInCoverWindow(nowPre, hrp.Position)
				-- Nuke over: step out the side of the pillar onto the floor instead of being
				-- pushed up onto its top.
				if not coverWindow and typeof(getgenv().SB2RubCoverExit) == 'Vector3' then
					local from = getgenv().SB2RubCoverExit
					getgenv().SB2RubCoverExit = nil
					local c = waveDefenseRiftsCenterFlat() or flatXZ(hrp.Position)
					local dir = Vector3.new(c.X - from.X, 0, c.Z - from.Z)
					dir = dir.Magnitude > 0.5 and dir.Unit or Vector3.new(1, 0, 0)
					local ex, ez = from.X + dir.X * 14, from.Z + dir.Z * 14
					local stand = getgenv().SB2DodgeModes.floorStandY(hrp, ex, ez) or (WD_LAVA_FLOOR_Y + 3)
					writeHeldCF(hrp, Vector3.new(ex, stand, ez), nil, 0, true, true)
					getgenv().SB2DodgeLog('rub-cover-exit', nil, Vector3.new(ex, stand, ez))
					lastStep = nowPre
					return
				end
				-- Swings first: they land in under a second, the cover window lasts ~11s.
				local heldCover = getgenv().SB2RubricatusCoverPos
				-- Discs (25% each) - except in the last seconds before a nuke, when the pillar matters more.
				if not (coverWindow and nowPre - (tonumber(getgenv().SB2RubNukeT0) or -1e9) >= 6) then
					local dOut = getgenv().SB2DodgeModes.discEscape(hrp, nowPre)
					if dOut and Vector3.new(dOut.X - hrp.Position.X, 0, dOut.Z - hrp.Position.Z).Magnitude > 1.5 then
						writeHeldCF(hrp, Vector3.new(dOut.X, hrp.Position.Y, dOut.Z), nil, 0, true, false)
						lastStep = nowPre
						return
					end
				end
				local swingOut = getgenv().SB2RubSwing.escape(
					hrp.Position,
					fightY,
					nowPre,
					(coverWindow and typeof(heldCover) == 'Vector3') and heldCover or nil
				)
				if swingOut then
					sidestepOnGround(hrp, swingOut, nil, 0.5)
					getgenv().SB2DodgeLog('rub-swing', nil, swingOut)
					lastStep = nowPre
					getgenv().SB2RubricatusLastSwingDodge = nowPre
					getgenv().SB2LastDodgeMoveAt = nowPre
					unstickIdleFreefall(hrp)
					return
				end
				-- First 6s after the nuke is cast it has not gone off yet (it lands ~10s in):
				-- dodge his other attacks first and only head back into cover when clear.
				if coverWindow and nowPre - (tonumber(getgenv().SB2RubNukeT0) or -1e9) < 6 then
					local early = rubricatusGeneralDodgeGoal(hrp.Position, fightY, rubMob, nowPre)
					-- Short sidesteps only while the nuke charges: full 56-stud pushes every tick
					-- flung you 100+ studs a second across (and off) the arena, far from any pillar.
					if early then
						local ex, ez = early.X - hrp.Position.X, early.Z - hrp.Position.Z
						local em = math.sqrt(ex * ex + ez * ez)
						if em > 24 then
							early = Vector3.new(hrp.Position.X + ex / em * 24, early.Y, hrp.Position.Z + ez / em * 24)
						end
						local mid = waveDefenseRiftsCenterFlat()
						if mid then
							local off = Vector3.new(early.X - mid.X, 0, early.Z - mid.Z)
							if off.Magnitude > 130 then
								off = off.Unit * 130
								early = Vector3.new(mid.X + off.X, early.Y, mid.Z + off.Z)
							end
						end
					end
					if early and sidestepOnGround(hrp, early, nil, 1.6) then
						lastStep = nowPre
						getgenv().SB2DodgeLog('rub-threat-early', nil, early)
						getgenv().SB2LastDodgeMoveAt = nowPre
						unstickIdleFreefall(hrp)
						return
					end
				end
				if coverWindow then
					local cover = rubricatusPillarCoverGoal(hrp.Position, fightY, rubMob)
					if typeof(cover) ~= 'Vector3' then
						local held = getgenv().SB2RubricatusCoverPos
						if typeof(held) == 'Vector3' then
							cover = Vector3.new(held.X, fightY, held.Z)
						end
					end
					if typeof(cover) == 'Vector3' then
						-- Don't walk back into a swing that hasn't landed yet; wait it out here.
						if getgenv().SB2RubSwing.blocks(cover, nowPre) then
							unstickIdleFreefall(hrp)
							return
						end
						rubricatusSnapToCover(hrp, cover, nil)
						return
					end
				end
				getgenv().SB2DodgeModes.releaseHover(hrp)
				if getgenv().SB2DodgeModes.hurtEscape(hrp, nowPre) then
					lastStep = nowPre
					return
				end
				local rubGoal = rubricatusGeneralDodgeGoal(hrp.Position, fightY, rubMob, nowPre)
				if rubGoal and sidestepOnGround(hrp, rubGoal, nil, 1.6) then
					lastStep = nowPre
					getgenv().SB2LastDodgeMoveAt = nowPre
					getgenv().SB2DodgeLog('rub-threat', nil, rubGoal)
				elseif not rubGoal and not coverWindow and #(getgenv().SB2RedLaser and getgenv().SB2RedLaser.active() or {}) == 0 then
					-- Nothing to dodge and no nuke: walk back toward the middle like normal waves
					-- (this fight never did, so his dodges left you stranded at the edge).
					getgenv().SB2DodgeModes.recenter(hrp, nowPre)
				end
				unstickIdleFreefall(hrp)
				return
			end
			getgenv().SB2RubricatusSurviveActive = false
			getgenv().SB2RubricatusSurviveY = nil
			getgenv().SB2RubCoverExit = nil
			if rubGrace then
				lastStep = tickGroundDodge(hrp, nowPre, lastStep)
				unstickIdleFreefall(hrp)
				return
			end
			-- Bob beats lava: his perch is far above the lava anyway, and flip-flopping between
			-- the two holds (Y360 <-> Y173 every second) flung you into the void.
			if bobAir then
				-- Drop the lava hold so nothing (incl. the main script's hold loop) pins you to Y173.
				getgenv().SB2LavaEscapeActive = false
				getgenv().SB2LavaFightY = nil
				getgenv().SB2LavaHoverY = nil
				getgenv().SB2DodgeModes.bob(hrp, getgenv().SB2BobEscapeActive ~= true)
				return
			end
			if lavaNow then
				getgenv().SB2DodgeAirAt = nowPre
				local hold = resolveLavaFightY(hrp, groundYAt(hrp))
				lavaFightY = hold
				getgenv().SB2LavaEscapeActive = true
				getgenv().SB2LavaFightY = hold
				getgenv().SB2LavaHoverY = hold
				local goal = lavaCircleSidestep(hrp, hold)
				local x, z = hrp.Position.X, hrp.Position.Z
				if typeof(goal) == 'Vector3' then
					x, z = goal.X, goal.Z
				end
				writeHeldCF(hrp, Vector3.new(x, hold, z), nil, 0, true, true)
				return
			end
			local modes = getgenv().SB2DodgeModes
			-- Darkner orb wave: stay at the orb.
			if orbEarly then
				modes.orb(hrp, orbEarly, getgenv().SB2DarknerOrbXZ == nil)
				return
			end
			if typeof(getgenv().SB2DarknerOrbXZ) == 'Vector3' then
				getgenv().SB2DarknerOrbXZ = nil
				getgenv().SB2DarknerOrbStandY = nil
			end
			-- Bob: lift far off the map until he is gone (1.5s grace after he despawns).
			if bobAir then
				modes.bob(hrp, getgenv().SB2BobEscapeActive ~= true)
				return
			end
			-- Aeganatos: hover high above him (1.5s grace after he's gone or the bar hides).
			local aegMob = modes.aeganatosMob()
			if aegMob or nowPre < (tonumber(getgenv().SB2AegSeenUntil) or 0) then
				modes.aeganatos(hrp, aegMob, getgenv().SB2AegHoldPos == nil)
				return
			end
			getgenv().SB2AegHoldPos = nil
			-- Coming out of lava / Bob / orb / Aeganatos: drop to the floor before any ground dodging.
			if modes.descend(hrp, 'descend') then
				lastStep = nowPre
				return
			end
			lastStep = tickGroundDodge(hrp, nowPre, lastStep)
			unstickIdleFreefall(hrp)
			end)
			-- A crash here used to stop every dodge silently for as long as it kept happening.
			if not okTick then
				local now = os.clock()
				local msg = tostring(errTick)
				if msg ~= getgenv().SB2DodgeLastErr or now - (tonumber(getgenv().SB2DodgeLastErrAt) or 0) > 3 then
					getgenv().SB2DodgeLastErr = msg
					getgenv().SB2DodgeLastErrAt = now
					warn('[AutoFloorDodge] tick error: ' .. msg)
					local logFn = getgenv().SB2DodgeLog
					if type(logFn) == 'function' then
						pcall(logFn, 'ERROR', msg, nil)
					end
				end
			end
		end)
		pcall(function()
			RunService:UnbindFromRenderStep('SB2PackHop')
			local beat = getgenv().SB2PackHopBeat
			if beat then
				beat:Disconnect()
			end
			getgenv().SB2PackHopBeat = nil
		end)
	end

	-- Own function so this chunk stays under Luau's 200-local register cap.
	;(function()
	-- Auto-on: the dodge turns itself on whenever only whitelisted players are in the server
	-- (the whitelist rule still switches it off when someone else joins). Turning it off
	-- yourself is remembered in PlayerTools/autododge and stops the auto-on.
	local AUTO_DODGE_PATH = getgenv().SB2AcctPath('PlayerTools/autododge')
	local function autoDodgeWanted()
		local ok, body = pcall(function()
			return isfile(AUTO_DODGE_PATH) and readfile(AUTO_DODGE_PATH) or nil
		end)
		if ok and type(body) == 'string' then
			return (body:lower():gsub('%s+', '')) ~= 'false'
		end
		return getgenv().SB2FriendDefaultsOff ~= true
	end
	local function userChangedDodge(value)
		-- Ignore automatic flips: whitelist lock, profile/config load, our own auto-on.
		if getgenv().SB2StrangerCombatLock == true and value ~= true then
			return
		end
		if getgenv().SB2ConfigLoading == true or getgenv().SB2DodgeAutoSetting == true then
			return
		end
		pcall(writefile, AUTO_DODGE_PATH, value and 'true' or 'false')
	end
	local existing = type(Toggles) == 'table' and Toggles.AutoFloorDodge
	if not existing then
		CombatBox:AddToggle('AutoFloorDodge', {
			Text = 'Auto dodge floor circles',
			Default = false,
			Tooltip = 'Sidestep beams, floor circles, and other attacks on the ground. Turns itself on when only whitelisted players are in the server; switch it off to stop that (saved in PlayerTools/autododge).',
		}):OnChanged(function(value)
			userChangedDodge(value == true)
			getgenv().SB2AutoFloorDodgeOn = value == true
			local prev = getgenv().SB2AutoFloorDodgeConn
			if prev then
				pcall(function()
					prev:Disconnect()
				end)
				getgenv().SB2AutoFloorDodgeConn = nil
			end
			if not value then
				stopAutoFloorDodgeLoop()
				return
			end
			startAutoFloorDodgeLoop()
		end)
	end
	if getgenv()._SB2ReloadStartDodge == true or (existing and existing.Value == true) or isToggleOn('AutoFloorDodge') then
		startAutoFloorDodgeLoop()
	end
	-- Auto-on watcher (one per load; a reload replaces it).
	do
		local token = {}
		getgenv().SB2DodgeAutoToken = token
		task.spawn(function()
			task.wait(3)
			while getgenv().SB2DodgeAutoToken == token do
				pcall(function()
					local t = type(Toggles) == 'table' and Toggles.AutoFloorDodge
					if type(t) ~= 'table' or t.Value == true or type(t.SetValue) ~= 'function' then
						return
					end
					if not autoDodgeWanted() then
						return
					end
					if getgenv().SB2DodgeStrangerOffThisServer == true then
						return -- switched off because of a stranger: don't turn it back on here
					end
					local strangersFn = getgenv().SB2OtherPlayersPresent
					if type(strangersFn) ~= 'function' or strangersFn() then
						return -- whitelist rule: only when no non-whitelisted players are here
					end
					getgenv().SB2DodgeAutoSetting = true
					pcall(function()
						t:SetValue(true)
					end)
					getgenv().SB2DodgeAutoSetting = false
				end)
				task.wait(2)
			end
		end)
	end
	getgenv().SB2StopAutoFloorDodgeLoop = stopAutoFloorDodgeLoop
	getgenv().SB2StartAutoFloorDodgeLoop = startAutoFloorDodgeLoop
	getgenv().SB2RubricatusPillarCoverGoal = rubricatusPillarCoverGoal
	getgenv().SB2RubricatusNukeTelegraph = rubricatusSpawnedPillarsNear
	getgenv().SB2RubricatusSnapToCover = rubricatusSnapToCover
	getgenv().SB2RubricatusInCoverWindow = rubricatusInCoverWindow
	getgenv().SB2WaveDefenseRiftHopGoal = waveDefenseRiftHopGoal

	-- Rubricatus fight recorder: survives server hops (module reloads each server) so a nuke
	-- death can be read back from PlayerTools/_rub_fight_log.txt afterwards.
	do
		local RUB_LOG_PATH = getgenv().SB2AcctPath('PlayerTools/_rub_fight_log.txt')
		local token = {}
		getgenv().SB2RubLogToken = token
		task.spawn(function()
			if type(appendfile) ~= 'function' or type(writefile) ~= 'function' then
				return
			end
			local function fv(v)
				return typeof(v) == 'Vector3' and string.format('(%.1f,%.1f,%.1f)', v.X, v.Y, v.Z) or tostring(v)
			end
			local buf = {}
			local lines = 0
			local inFight = false
			local fightStart = 0
			local lastHp = nil
			local lastFlush = 0
			local addConn = nil
			local function push(line)
				if lines >= 4000 then
					return
				end
				lines += 1
				buf[#buf + 1] = string.format('%.2f ', os.clock() - fightStart) .. line
			end
			local function flush()
				if #buf > 0 then
					pcall(appendfile, RUB_LOG_PATH, table.concat(buf, '\n') .. '\n')
					buf = {}
				end
			end
			while getgenv().SB2RubLogToken == token do
				local boss = findRubricatusMob()
				local char = LocalPlayer.Character
				local hrp = char and char:FindFirstChild('HumanoidRootPart')
				local hum = char and char:FindFirstChildOfClass('Humanoid')
				if boss and hrp and not inFight then
					inFight = true
					fightStart = os.clock()
					lines = 0
					lastHp = nil
					pcall(function()
						if not isfile(RUB_LOG_PATH) or #readfile(RUB_LOG_PATH) > 600000 then
							writefile(RUB_LOG_PATH, '')
						end
					end)
					push(('=== FIGHT START %s wave=%s place=%s dodgeOn=%s build=%s'):format(
						os.date('%Y-%m-%d %H:%M:%S'), tostring(workspace:GetAttribute('Wave')),
						tostring(game.PlaceId), tostring(getgenv().SB2AutoFloorDodgeOn),
						tostring(getgenv().SB2AutoFloorDodgeBuild)))
					addConn = workspace.ChildAdded:Connect(function(child)
						task.defer(function()
							if not child.Parent then
								return
							end
							local size = child:IsA('BasePart') and child.Size
								or (child:IsA('Model') and select(2, pcall(child.GetExtentsSize, child)))
							local pos = child:IsA('BasePart') and child.Position
								or (child:IsA('Model') and select(2, pcall(child.GetPivot, child)))
							pos = typeof(pos) == 'CFrame' and pos.Position or pos
							push(('+ADD %s %s size=%s pos=%s tr=%s'):format(child.Name, child.ClassName, fv(size), fv(pos),
								child:IsA('BasePart') and string.format('%.2f', child.Transparency) or '-'))
						end)
					end)
				elseif not boss and inFight then
					inFight = false
					if addConn then
						addConn:Disconnect()
						addConn = nil
					end
					push('=== FIGHT END hp=' .. tostring(hum and math.floor(hum.Health)))
					flush()
				end
				if inFight and hrp then
					local bossRoot = boss:FindFirstChild('HumanoidRootPart') or boss.PrimaryPart
					local hp = hum and hum.Health or 0
					local tag = ''
					if lastHp and hp < lastHp - 5 then
						tag = (' DMG-%d'):format(math.floor(lastHp - hp))
					end
					lastHp = hp
					local cover = rubricatusCoverPart
					local entry = cover and cover.Parent and rubricatusCoverShape(cover)
					local coverFlat = entry and entry.flat
					local myFlat = Vector3.new(hrp.Position.X, 0, hrp.Position.Z)
					local shadow = '-'
					if entry and bossRoot then
						shadow = tostring(rubricatusShadowedBy(Vector3.new(bossRoot.Position.X, 0, bossRoot.Position.Z), myFlat, entry))
					end
					push(('hp=%d%s me=%s boss=%s win=%s pillars=%s cover=%s coverSize=%s dCover=%s shadow=%s goal=%s lava=%s'):format(
						math.floor(hp), tag, fv(hrp.Position), fv(bossRoot and bossRoot.Position),
						tostring(rubricatusInCoverWindow(os.clock(), hrp.Position)),
						tostring(rubricatusSpawnedPillarsNear(hrp.Position)),
						entry and fv(entry.pos) or '-', entry and fv(entry.size) or '-',
						coverFlat and string.format('%.1f', (myFlat - coverFlat).Magnitude) or '-',
						shadow, fv(getgenv().SB2RubricatusCoverPos), tostring(getgenv().SB2LavaFightY)))
				end
				if os.clock() - lastFlush >= 2 then
					lastFlush = os.clock()
					flush()
				end
				task.wait(0.2)
			end
			if addConn then
				addConn:Disconnect()
			end
			flush()
		end)
	end

	-- Own function scope — death-log locals were tipping the 200-register factory cap.
	local function startDeathLog()
		local DEATH_LOG_PATH = getgenv().SB2AcctPath('PlayerTools/_death_log.txt')
		local DEATH_LOG_WINDOW = 15
		local DEATH_LOG_NOISE = {
			DamageText = true,
			HealWisp = true,
			HealPulse = true,
			Heart = true,
			HighlightModel = true,
		}
		local token = {}
		getgenv().SB2DeathLogToken = token
		task.spawn(function()
			if type(appendfile) ~= 'function' or type(writefile) ~= 'function' then
				return
			end
			local function fv(v)
				return typeof(v) == 'Vector3' and string.format('(%.1f,%.1f,%.1f)', v.X, v.Y, v.Z) or tostring(v)
			end
			local ring = {}
			local recentAdds = {}
			local function push(line)
				ring[#ring + 1] = { t = os.clock(), line = line }
			end
			getgenv().SB2DeathLogNote = push
			local function prune(now)
				local keep = 1
				while keep <= #ring and now - ring[keep].t > DEATH_LOG_WINDOW do
					keep += 1
				end
				if keep > 1 then
					local nr = table.move(ring, keep, #ring, 1, {})
					ring = nr
				end
				local na = {}
				for _, a in ipairs(recentAdds) do
					if now - a.t <= 2 then
						na[#na + 1] = a
					end
				end
				recentAdds = na
			end
			local function myRoot()
				local char = LocalPlayer.Character
				return char, char and char:FindFirstChild('HumanoidRootPart')
			end
			local function nearbyAdds(pos, radius)
				local out = {}
				for _, a in ipairs(recentAdds) do
					if typeof(a.pos) == 'Vector3' and (a.pos - pos).Magnitude <= radius then
						out[#out + 1] = ('%s@%.0f'):format(a.name, (a.pos - pos).Magnitude)
					end
				end
				return #out > 0 and table.concat(out, ',') or '-'
			end
			local function nearestMobs(pos, n)
				local mobs = workspace:FindFirstChild('Mobs')
				local list = {}
				for _, m in ipairs(mobs and mobs:GetChildren() or {}) do
					if m:GetAttribute('Died') ~= true then
						local p = m.PrimaryPart or m:FindFirstChild('HumanoidRootPart')
						if p then
							list[#list + 1] = { name = m.Name, d = (p.Position - pos).Magnitude }
						end
					end
				end
				table.sort(list, function(a, b)
					return a.d < b.d
				end)
				local out = {}
				for i = 1, math.min(n, #list) do
					out[#out + 1] = ('%s@%.0f'):format(list[i].name, list[i].d)
				end
				return #out > 0 and table.concat(out, ',') or '-'
			end
			local function dump(reason)
				local char, hrp = myRoot()
				local lines = {
					('=== DEATH %s reason=%s wave=%s mode=%s lives=%s place=%s dodge=%s build=%s'):format(
						os.date('%Y-%m-%d %H:%M:%S'), reason, tostring(workspace:GetAttribute('Wave')),
						tostring(workspace:GetAttribute('WaveDefenseMode')), tostring(LocalPlayer:GetAttribute('Lives')),
						tostring(game.PlaceId), tostring(getgenv().SB2AutoFloorDodgeOn),
						tostring(getgenv().SB2AutoFloorDodgeBuild)),
				}
				local now = os.clock()
				for _, r in ipairs(ring) do
					lines[#lines + 1] = string.format('%6.2f ', r.t - now) .. r.line
				end
				lines[#lines + 1] = '=== END pos=' .. fv(hrp and hrp.Position) .. ' char=' .. tostring(char and char.Parent ~= nil)
				pcall(function()
					-- Over the cap: keep the newest ~250KB (whole entries) instead of wiping it all,
					-- which used to erase the deaths right before this one.
					if not isfile(DEATH_LOG_PATH) then
						writefile(DEATH_LOG_PATH, '')
					else
						local old = readfile(DEATH_LOG_PATH)
						if #old > 500000 then
							local tail = old:sub(-250000)
							local cut = tail:find('=== DEATH', 1, true)
							writefile(DEATH_LOG_PATH, cut and tail:sub(cut) or '')
						end
					end
				end)
				pcall(appendfile, DEATH_LOG_PATH, table.concat(lines, '\n') .. '\n\n')
				warn(('[DeathLog] saved %d lines (%s) to %s'):format(#ring, reason, DEATH_LOG_PATH))
				ring = {}
			end

			getgenv().SB2DeathLogDump = function()
				dump('manual')
			end

			local addConn = workspace.ChildAdded:Connect(function(child)
				if DEATH_LOG_NOISE[child.Name] or child == LocalPlayer.Character then
					return
				end
				task.defer(function()
					if not child.Parent then
						return
					end
					local size = child:IsA('BasePart') and child.Size
						or (child:IsA('Model') and select(2, pcall(child.GetExtentsSize, child)))
					local pos = child:IsA('BasePart') and child.Position
						or (child:IsA('Model') and select(2, pcall(child.GetPivot, child)))
					pos = typeof(pos) == 'CFrame' and pos.Position or pos
					local _, hrp = myRoot()
					local dist = (typeof(pos) == 'Vector3' and hrp) and string.format('%.0f', (pos - hrp.Position).Magnitude) or '-'
					recentAdds[#recentAdds + 1] = { t = os.clock(), name = child.Name, pos = typeof(pos) == 'Vector3' and pos or nil }
					push(('+ADD %s %s size=%s pos=%s dist=%s'):format(child.Name, child.ClassName, fv(size), fv(pos), dist))
				end)
			end)
			local mobsConn = nil
			local function hookMobs()
				local mobs = workspace:FindFirstChild('Mobs')
				if mobs and not mobsConn then
					mobsConn = mobs.ChildAdded:Connect(function(m)
						task.defer(function()
							local p = m.PrimaryPart or m:FindFirstChild('HumanoidRootPart')
							local _, hrp = myRoot()
							push(('+MOB %s dist=%s'):format(m.Name,
								(p and hrp) and string.format('%.0f', (p.Position - hrp.Position).Magnitude) or '-'))
						end)
					end)
				end
			end

			-- Weapon watcher: equip/unequip and sheathe changes go to their own file with the wave.
			local EQUIP_LOG_PATH = getgenv().SB2AcctPath('PlayerTools/_equip_log.txt')
			local function equipNote(line)
				push('EQUIP ' .. line)
				local full = ('%s wave=%s %s\n'):format(os.date('%Y-%m-%d %H:%M:%S'), tostring(workspace:GetAttribute('Wave')), line)
				pcall(function()
					if not isfile(EQUIP_LOG_PATH) or #readfile(EQUIP_LOG_PATH) > 200000 then
						writefile(EQUIP_LOG_PATH, '')
					end
					appendfile(EQUIP_LOG_PATH, full)
				end)
			end
			local equipConns = {}
			local equipHolder, equipChar = nil, nil
			local function hookEquip()
				local items = workspace:FindFirstChild('CharacterItems')
				local holder = items and items:FindFirstChild(tostring(LocalPlayer.UserId))
				local char = LocalPlayer.Character
				if holder == equipHolder and char == equipChar then
					return
				end
				for _, c in ipairs(equipConns) do
					c:Disconnect()
				end
				equipConns = {}
				equipHolder, equipChar = holder, char
				if holder then
					equipConns[#equipConns + 1] = holder.ChildAdded:Connect(function(ch)
						if ch.Name == 'RightWeapon' or ch.Name == 'LeftWeapon' then
							task.defer(function()
								equipNote(('+%s %s'):format(ch.Name, tostring(ch:GetAttribute('Name'))))
							end)
						end
					end)
					equipConns[#equipConns + 1] = holder.ChildRemoved:Connect(function(ch)
						if ch.Name == 'RightWeapon' or ch.Name == 'LeftWeapon' then
							equipNote(('-%s %s'):format(ch.Name, tostring(ch:GetAttribute('Name'))))
						end
					end)
				end
				if char then
					equipConns[#equipConns + 1] = char:GetAttributeChangedSignal('Sheathed'):Connect(function()
						equipNote('Sheathed=' .. tostring(char:GetAttribute('Sheathed')))
					end)
				end
			end

			local healthConn, watchedHealth, lastHp = nil, nil, nil
			local lastLives = LocalPlayer:GetAttribute('Lives')
			local lastChar = LocalPlayer.Character
			local deadLatched = false
			local lastDumpAt = 0
			local function onDeath(reason)
				if deadLatched or os.clock() - lastDumpAt < 4 then
					return
				end
				deadLatched = true
				lastDumpAt = os.clock()
				dump(reason)
			end
			local function hookHealth(char)
				local entity = char and char:FindFirstChild('Entity')
				local health = entity and entity:FindFirstChild('Health')
				if health == watchedHealth then
					return
				end
				if healthConn then
					healthConn:Disconnect()
					healthConn = nil
				end
				watchedHealth = health
				lastHp = health and health.Value or nil
				if not health then
					return
				end
				healthConn = health.Changed:Connect(function(v)
					local _, hrp = myRoot()
					if typeof(v) ~= 'number' then
						return
					end
					if lastHp and v < lastHp then
						local maxV = tonumber(health.MaxValue) or 0
						local pct = maxV > 0 and ((lastHp - v) / maxV * 100) or 0
						push(('HIT -%d (%.1f%%) hp=%d/%d at=%s adds=%s mobs=%s'):format(
							lastHp - v, pct, v, maxV, fv(hrp and hrp.Position),
							hrp and nearbyAdds(hrp.Position, 40) or '-', hrp and nearestMobs(hrp.Position, 3) or '-'))
					end
					lastHp = v
					if v <= 0 then
						onDeath('health0')
					end
				end)
			end

			while getgenv().SB2DeathLogToken == token do
				local now = os.clock()
				prune(now)
				hookMobs()
				hookEquip()
				local char, hrp = myRoot()
				if char ~= lastChar then
					if lastChar ~= nil then
						onDeath(char and 'respawn' or 'char-removed')
					end
					lastChar = char
				end
				hookHealth(char)
				local lives = LocalPlayer:GetAttribute('Lives')
				-- Lives also drop when a heart is spent on a revive, so this is logged, not treated as a death.
				if typeof(lives) == 'number' and typeof(lastLives) == 'number' and lives ~= lastLives then
					push(('LIVES %s -> %s'):format(lastLives, lives))
				end
				lastLives = lives
				if deadLatched and watchedHealth and watchedHealth.Value > 0 and os.clock() - lastDumpAt > 4 then
					deadLatched = false
				end
				if hrp then
					local hp = watchedHealth and watchedHealth.Value
					local maxV = watchedHealth and tonumber(watchedHealth.MaxValue)
					local bobOn = getgenv().SB2BobEscapeActive == true
					push(('hp=%s/%s me=%s vel=%s wave=%s bob=%s lava=%s rift=%s rubWin=%s floorGoal=%s mobs=%s'):format(
						tostring(hp), tostring(maxV), fv(hrp.Position), fv(hrp.AssemblyLinearVelocity),
						tostring(workspace:GetAttribute('Wave')), tostring(bobOn),
						tostring(getgenv().SB2LavaFightY), tostring(getgenv().SB2WdRiftHopActive == true),
						tostring(os.clock() < (tonumber(getgenv().SB2RubricatusNukeUntil) or 0)),
						fv(getgenv().SB2FloorDodgeGoal), nearestMobs(hrp.Position, 3)))
				end
				task.wait(0.15)
			end
			addConn:Disconnect()
			if mobsConn then
				mobsConn:Disconnect()
			end
			for _, c in ipairs(equipConns) do
				c:Disconnect()
			end
			if healthConn then
				healthConn:Disconnect()
			end
		end)
	end
	startDeathLog()

	task.defer(function()
		if isToggleOn('AutoFloorDodge') then
			startAutoFloorDodgeLoop()
			return
		end
		local t = type(Toggles) == 'table' and Toggles.AutoFloorDodge
		if type(t) == 'table' and t.Value == true then
			startAutoFloorDodgeLoop()
		elseif type(t) == 'table' then
			stopAutoFloorDodgeLoop()
		end
	end)
	end)()
end
]=]
FILES['NoPlayerCollide.lua'] = [=[
--[[
	NoPlayerCollide.lua — your character stops colliding with whitelisted players' characters
	(both accounts running it = they walk / dodge through each other). Local physics only.
	Part of the whitelist rule: while someone NOT on the whitelist is in the server it pauses
	(collisions come back) and resumes by itself when they leave.
	v4: also moves their parts into the game's own "NoCollision" collision group (which the
	"Players" group never collides with). CanCollide alone gets switched back on by their Humanoid
	inside the physics step, which is what still launched you upward now and then.
	Used by PlayerTools (Combat box) and AutoBetween (Dodge box).
]]
getgenv().SB2NoCollideBuild = 'no-collide-v4'

return function(env)
	local box = env.Box
	local Toggles = env.Toggles
	local Players = game:GetService('Players')
	local RunService = game:GetService('RunService')
	local LocalPlayer = Players.LocalPlayer
	local G = getgenv()

	local path = 'PlayerTools/nocollide'
	if type(G.SB2AcctPath) == 'function' then
		path = G.SB2AcctPath(path)
	end
	local function savedOn()
		local ok, body = pcall(function()
			return isfile(path) and readfile(path) or nil
		end)
		if ok and type(body) == 'string' then
			return (body:lower():gsub('%s+', '')) ~= 'false'
		end
		return getgenv().SB2FriendDefaultsOff ~= true
	end

	if not (type(Toggles) == 'table' and Toggles.NoWhitelistCollide) then
		box:AddToggle('NoWhitelistCollide', {
			Text = 'No collision with whitelisted players',
			Default = savedOn(),
			Tooltip = 'You pass through whitelisted players (your other accounts). Pauses while someone not on the whitelist is in the server, resumes when they leave.',
		}):OnChanged(function(v)
			pcall(writefile, path, v and 'true' or 'false')
		end)
	end

	-- Old copy (reload): restore its parts and stop it.
	if type(G.SB2NoCollideStop) == 'function' then
		pcall(G.SB2NoCollideStop)
	end

	local changed = setmetatable({}, { __mode = 'k' }) -- parts we turned off
	-- A collision group that never touches "Players" (The Between has "NoCollision").
	local NOCOLL
	pcall(function()
		local PS = game:GetService('PhysicsService')
		for _, name in ipairs({ 'NoCollision', 'MobsNoCollision' }) do
			if PS:IsCollisionGroupRegistered(name) and not PS:CollisionGroupsAreCollidable('Players', name)
				and not PS:CollisionGroupsAreCollidable('Default', name) then
				NOCOLL = name
				break
			end
		end
		if not NOCOLL then
			for _, name in ipairs({ 'NoCollision', 'MobsNoCollision' }) do
				if PS:IsCollisionGroupRegistered(name) and not PS:CollisionGroupsAreCollidable('Players', name) then
					NOCOLL = name
					break
				end
			end
		end
	end)
	local cache = {} -- [player] = { char = Model, parts = { BasePart } }
	local cacheAt = 0

	local function isWhitelisted(plr)
		local fn = G.SB2IsOwnAlt
		return type(fn) == 'function' and fn(plr) == true
	end
	local function strangers()
		local fn = G.SB2OtherPlayersPresent
		return type(fn) == 'function' and fn() == true
	end
	local function restoreAll()
		for part, orig in pairs(changed) do
			pcall(function()
				if part.Parent then
					part.CanCollide = type(orig) ~= 'table' or orig[1] == true
					part.CanTouch = type(orig) ~= 'table' or orig[2] == true
					if type(orig) == 'table' and orig[3] then
						part.CollisionGroup = orig[3]
					end
				end
			end)
			changed[part] = nil
		end
	end
	local function rebuild()
		cache = {}
		local items = workspace:FindFirstChild('CharacterItems')
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr ~= LocalPlayer and isWhitelisted(plr) then
				local parts = {}
				-- Character + their gear (weapons / armor live in workspace.CharacterItems.<UserId>).
				local roots = {}
				if plr.Character then
					roots[#roots + 1] = plr.Character
				end
				local gear = items and items:FindFirstChild(tostring(plr.UserId))
				if gear then
					roots[#roots + 1] = gear
				end
				for _, root in ipairs(roots) do
					for _, d in ipairs(root:GetDescendants()) do
						if d:IsA('BasePart') then
							parts[#parts + 1] = d
						end
					end
				end
				cache[plr] = { parts = parts, roots = roots }
			end
		end
	end

	local active = false
	local dirty = true
	local watchConns = {}
	local function watch(root)
		-- new parts (weapon swap, accessories, respawn) get picked up right away, not a second later
		watchConns[#watchConns + 1] = root.DescendantAdded:Connect(function(d)
			if d:IsA('BasePart') then
				dirty = true
			end
		end)
	end
	local watchedRoots = setmetatable({}, { __mode = 'k' })
	local function apply()
		local t = Toggles and Toggles.NoWhitelistCollide
		local want = type(t) == 'table' and t.Value == true and not strangers()
		if not want then
			if active then
				active = false
				restoreAll()
			end
			return
		end
		active = true
		local now = os.clock()
		if dirty or now - cacheAt > 0.5 then
			dirty = false
			cacheAt = now
			rebuild()
			for _, entry in pairs(cache) do
				for _, root in ipairs(entry.roots or {}) do
					if not watchedRoots[root] then
						watchedRoots[root] = true
						watch(root)
					end
				end
			end
		end
		for _, entry in pairs(cache) do
			for _, part in ipairs(entry.parts) do
				-- Humanoids turn the root/torso back on every physics step, so this runs on every step
				if part.Parent and (part.CanCollide or part.CanTouch or (NOCOLL and part.CollisionGroup ~= NOCOLL)) then
					if not changed[part] then
						changed[part] = { part.CanCollide, part.CanTouch, part.CollisionGroup } -- remember the originals
					end
					part.CanCollide = false
					part.CanTouch = false
					if NOCOLL and part.CollisionGroup ~= NOCOLL then
						part.CollisionGroup = NOCOLL
					end
				end
			end
		end
	end
	-- before physics (Stepped/PreSimulation) AND after it, so the humanoid can't sneak a step in between
	local conn = RunService.Stepped:Connect(apply)
	local conn2 = RunService.Heartbeat:Connect(apply)
	watchConns[#watchConns + 1] = Players.PlayerAdded:Connect(function()
		dirty = true
	end)

	G.SB2NoCollideStop = function()
		pcall(function()
			conn:Disconnect()
			conn2:Disconnect()
		end)
		for _, c in ipairs(watchConns) do
			pcall(function()
				c:Disconnect()
			end)
		end
		restoreAll()
		G.SB2NoCollideStop = nil
	end
end
]=]
FILES['AtaraxiaLibrary.lua'] = [=[
--[[
  PlayerTools/AtaraxiaLibrary.lua
  Obsidian-compatible Library API â†’ Roster chrome (Ataraxia)
  Returned by loadstring like deividcomsono/Obsidian Library.lua
]]

local Players = game:GetService('Players')
local UserInputService = game:GetService('UserInputService')
local RunService = game:GetService('RunService')
local Lighting = game:GetService('Lighting')
local TweenService = game:GetService('TweenService')
local TextService = game:GetService('TextService')
local GuiService = game:GetService('GuiService')
local LocalPlayer = Players.LocalPlayer

local C = {
	bg0 = Color3.fromRGB(10, 10, 10),
	bg1 = Color3.fromRGB(17, 17, 17),
	bg2 = Color3.fromRGB(26, 26, 26),
	bg3 = Color3.fromRGB(36, 36, 36),
	line = Color3.fromRGB(48, 48, 48),
	text = Color3.fromRGB(242, 242, 242),
	muted = Color3.fromRGB(138, 138, 138),
	accent = Color3.fromRGB(255, 255, 255),
	danger = Color3.fromRGB(255, 107, 107),
}

-- Built-in palettes. Default matches the classic Ataraxia chrome (unchanged).
local THEME_FILE = 'Ataraxia/theme'
local THEME_ORDER = { 'Default', 'Midnight', 'Slate', 'Warm', 'Contrast' }
local THEMES = {
	Default = {
		bg0 = Color3.fromRGB(10, 10, 10),
		bg1 = Color3.fromRGB(17, 17, 17),
		bg2 = Color3.fromRGB(26, 26, 26),
		bg3 = Color3.fromRGB(36, 36, 36),
		line = Color3.fromRGB(48, 48, 48),
		text = Color3.fromRGB(242, 242, 242),
		muted = Color3.fromRGB(138, 138, 138),
		accent = Color3.fromRGB(255, 255, 255),
		danger = Color3.fromRGB(255, 107, 107),
	},
	Midnight = {
		bg0 = Color3.fromRGB(8, 10, 16),
		bg1 = Color3.fromRGB(14, 18, 28),
		bg2 = Color3.fromRGB(22, 28, 40),
		bg3 = Color3.fromRGB(32, 40, 56),
		line = Color3.fromRGB(48, 58, 78),
		text = Color3.fromRGB(236, 242, 255),
		muted = Color3.fromRGB(130, 142, 168),
		accent = Color3.fromRGB(210, 225, 255),
		danger = Color3.fromRGB(255, 107, 107),
	},
	Slate = {
		bg0 = Color3.fromRGB(12, 13, 14),
		bg1 = Color3.fromRGB(20, 22, 24),
		bg2 = Color3.fromRGB(30, 32, 36),
		bg3 = Color3.fromRGB(42, 46, 52),
		line = Color3.fromRGB(58, 62, 70),
		text = Color3.fromRGB(236, 238, 240),
		muted = Color3.fromRGB(140, 146, 154),
		accent = Color3.fromRGB(220, 230, 240),
		danger = Color3.fromRGB(255, 107, 107),
	},
	Warm = {
		bg0 = Color3.fromRGB(12, 10, 9),
		bg1 = Color3.fromRGB(20, 17, 15),
		bg2 = Color3.fromRGB(30, 26, 22),
		bg3 = Color3.fromRGB(42, 36, 30),
		line = Color3.fromRGB(58, 50, 42),
		text = Color3.fromRGB(245, 240, 232),
		muted = Color3.fromRGB(150, 138, 124),
		accent = Color3.fromRGB(255, 236, 210),
		danger = Color3.fromRGB(255, 120, 100),
	},
	Contrast = {
		bg0 = Color3.fromRGB(0, 0, 0),
		bg1 = Color3.fromRGB(12, 12, 12),
		bg2 = Color3.fromRGB(22, 22, 22),
		bg3 = Color3.fromRGB(40, 40, 40),
		line = Color3.fromRGB(80, 80, 80),
		text = Color3.fromRGB(255, 255, 255),
		muted = Color3.fromRGB(170, 170, 170),
		accent = Color3.fromRGB(255, 255, 255),
		danger = Color3.fromRGB(255, 80, 80),
	},
}

local currentThemeName = 'Default'

local function copyThemeIntoC(theme)
	for k, v in pairs(theme) do
		C[k] = v
	end
end

local function readThemeFile()
	if type(isfile) == 'function' and type(readfile) == 'function' then
		local ok, exists = pcall(isfile, THEME_FILE)
		if ok and exists then
			local rok, body = pcall(readfile, THEME_FILE)
			if rok and type(body) == 'string' then
				local name = tostring(body):gsub('%s+', '')
				if THEMES[name] then
					return name
				end
			end
		end
	end
	return 'Default'
end

local function writeThemeFile(name)
	if type(writefile) ~= 'function' then
		return
	end
	pcall(function()
		if type(makefolder) == 'function' and type(isfolder) == 'function' and not isfolder('Ataraxia') then
			makefolder('Ataraxia')
		end
	end)
	pcall(writefile, THEME_FILE, tostring(name or 'Default'))
end

do
	local saved = readThemeFile()
	currentThemeName = saved
	copyThemeIntoC(THEMES[saved] or THEMES.Default)
end

local Library = {
	Options = {},
	Toggles = {},
	Tabs = {},
	ActiveTab = nil,
	-- Default open size vs resize floor (resize may go smaller than default).
	DefaultSize = Vector2.new(880, 560),
	MinSize = Vector2.new(560, 360),
	OriginalMinSize = Vector2.new(560, 360),
	DPIScale = 1,
	Toggled = true,
	Open = true,
	Unloaded = false,
	ShowCustomCursor = false,
	ToggleKeybind = nil,
	Backend = 'Ataraxia',
	Animations = {
		TabSwitch = false,
		Dropdown = false,
		KeyPicker = false,
	},
	Scheme = {
		Font = Enum.Font.SourceSans,
	},
	ScreenGui = nil,
	_conns = {},
	_toasts = nil,
}

local function track(conn)
	Library._conns[#Library._conns + 1] = conn
	return conn
end

local function corner(parent, r)
	local c = Instance.new('UICorner')
	c.CornerRadius = UDim.new(0, r or 4)
	c.Parent = parent
	return c
end

local function hairline(parent, _radius)
	-- Stroke on the control itself. A full-size overlay Frame (old Hairline) sits above
	-- children under ZIndexBehavior.Sibling and eats dropdown/option clicks.
	local s = Instance.new('UIStroke')
	s.Name = 'HairlineStroke'
	s.Color = C.line
	s.Thickness = 1
	s.Transparency = 0.15
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function mkLabel(parent, text, props)
	props = props or {}
	local l = Instance.new('TextLabel')
	l.BackgroundTransparency = 1
	-- SourceSansPro keeps thin glyphs (z) readable at small sizes; Gotham drops them.
	l.Font = props.font or Enum.Font.SourceSans
	l.TextSize = props.size or 14
	l.TextColor3 = props.color or C.text
	l.TextXAlignment = props.x or Enum.TextXAlignment.Left
	l.TextYAlignment = props.y or Enum.TextYAlignment.Center
	l.Text = text or ''
	l.Size = props.size2 or UDim2.new(1, 0, 0, 18)
	l.Position = props.pos or UDim2.new()
	l.TextWrapped = props.wrap == true
	l.TextTruncate = props.truncate or Enum.TextTruncate.None
	l.TextScaled = false
	l.RichText = false
	l.ZIndex = props.z or ((parent.ZIndex or 1) + 1)
	l.Parent = parent
	return l
end

function Library:GetTextBounds(_, Text, Font, Size, Width)
	local ok, bounds = pcall(function()
		return TextService:GetTextSize(
			tostring(Text or ''),
			Size or 14,
			Font or self.Scheme.Font,
			Vector2.new(Width or 1e5, 1e5)
		)
	end)
	if ok and typeof(bounds) == 'Vector2' then
		return bounds.X, bounds.Y
	end
	local t = tostring(Text or '')
	return math.max(8, #t * (Size or 14) * 0.52), (Size or 14) + 4
end

function Library:GetCustomIcon()
	return nil
end

function Library:AddContextMenu()
	return {
		Open = function() end,
		SetSize = function() end,
		Size = UDim2.new(),
		Active = false,
	}
end

function Library:PlayTabAnimation() end

function Library:Notify(text, duration)
	if type(self.IsNotifyEnabled) == 'function' and self:IsNotifyEnabled() ~= true then
		return
	end
	duration = tonumber(duration) or 5
	-- Own ScreenGui: the in-window toast holder is 40px and clips multiline text.
	local pg = LocalPlayer and LocalPlayer:FindFirstChildOfClass('PlayerGui')
	if not pg then
		warn('[Ataraxia] ' .. tostring(text))
		return
	end
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
	if not holder:FindFirstChildOfClass('UIListLayout') then
		local lay = Instance.new('UIListLayout')
		lay.SortOrder = Enum.SortOrder.LayoutOrder
		lay.Padding = UDim.new(0, 8)
		lay.Parent = holder
	end
	-- Cap stacked toasts so a notify storm cannot fill the screen.
	local existing = {}
	for _, ch in ipairs(holder:GetChildren()) do
		if ch:IsA('GuiObject') and ch.Name == 'Toast' then
			existing[#existing + 1] = ch
		end
	end
	while #existing >= 4 do
		local oldest = table.remove(existing, 1)
		pcall(function()
			oldest:Destroy()
		end)
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
	t.BackgroundColor3 = C.bg2
	t.BorderSizePixel = 0
	t.ClipsDescendants = true
	t.Parent = holder
	corner(t, 6)
	local outline = Instance.new('UIStroke')
	outline.Name = 'ToastOutline'
	outline.Color = Color3.fromRGB(255, 255, 255)
	outline.Thickness = 1
	outline.Transparency = 0
	outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	outline.Parent = t
	for i, row in ipairs(rows) do
		local l = mkLabel(t, row, {
			size = fontSize,
			size2 = UDim2.new(1, -24, 0, lineH),
			pos = UDim2.fromOffset(12, 10 + (i - 1) * lineH),
			wrap = false,
			y = Enum.TextYAlignment.Center,
		})
		l.ZIndex = (t.ZIndex or 1) + 1
	end
	local track = Instance.new('Frame')
	track.Name = 'TimeTrack'
	track.BackgroundColor3 = Color3.fromRGB(48, 48, 48)
	track.BorderSizePixel = 0
	track.Size = UDim2.new(1, -16, 0, barH)
	track.Position = UDim2.new(0, 8, 1, -(barH + 6))
	track.ZIndex = (t.ZIndex or 1) + 1
	track.Parent = t
	corner(track, 2)
	local fill = Instance.new('Frame')
	fill.Name = 'TimeFill'
	fill.BackgroundColor3 = Color3.new(1, 1, 1)
	fill.BorderSizePixel = 0
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.Parent = track
	corner(fill, 2)
	TweenService:Create(fill, TweenInfo.new(duration, Enum.EasingStyle.Linear), {
		Size = UDim2.new(0, 0, 1, 0),
	}):Play()
	local flash = Instance.new('Frame')
	flash.Name = 'Flash'
	flash.BackgroundColor3 = Color3.new(1, 1, 1)
	flash.BackgroundTransparency = 0.45
	flash.BorderSizePixel = 0
	flash.Size = UDim2.new(1, 0, 1, 0)
	flash.ZIndex = (t.ZIndex or 1) + 8
	flash.Parent = t
	corner(flash, 6)
	TweenService:Create(flash, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
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

function Library:Toggle(force)
	if force == true or force == false then
		self.Toggled = force
	else
		self.Toggled = not self.Toggled
	end
	self.Open = self.Toggled
	local main = self.ScreenGui and self.ScreenGui:FindFirstChild('Main')
	if main then
		main.Visible = self.Toggled
	end
	if self._showPill then
		self._showPill.Visible = not self.Toggled
	end
	if self.ScreenGui then
		self.ScreenGui.Enabled = true
	end
	-- Only force-show the cursor while the full menu is open.
	if self.Toggled then
		UserInputService.MouseIconEnabled = true
		pcall(function()
			UserInputService.OverrideMouseIconBehavior = Enum.OverrideMouseIconBehavior.ForceShow
		end)
	else
		pcall(function()
			UserInputService.OverrideMouseIconBehavior = Enum.OverrideMouseIconBehavior.None
		end)
	end
end

local function makeShowPill(gui, title)
	local pill = Instance.new('TextButton')
	pill.Name = 'ShowPill'
	pill.AutoButtonColor = false
	pill.Text = ''
	pill.BorderSizePixel = 0
	pill.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
	pill.BackgroundTransparency = 0.08
	pill.Size = UDim2.fromOffset(152, 48)
	pill.Position = UDim2.new(0.5, -76, 1, -72)
	pill.AnchorPoint = Vector2.new(0, 0)
	pill.Visible = false
	pill.ZIndex = 200
	pill.Parent = gui
	corner(pill, 24)
	hairline(pill, 24)

	-- Four-petal mark (no remote asset).
	local mark = Instance.new('Frame')
	mark.Name = 'Mark'
	mark.BackgroundTransparency = 1
	mark.Size = UDim2.fromOffset(22, 22)
	mark.Position = UDim2.fromOffset(14, 13)
	mark.ZIndex = 201
	mark.Parent = pill
	for i = 0, 3 do
		local petal = Instance.new('Frame')
		petal.BackgroundColor3 = C.text
		petal.BorderSizePixel = 0
		petal.Size = UDim2.fromOffset(6, 10)
		petal.AnchorPoint = Vector2.new(0.5, 1)
		petal.Position = UDim2.fromScale(0.5, 0.5)
		petal.Rotation = i * 90
		petal.ZIndex = 202
		petal.Parent = mark
		corner(petal, 3)
	end

	mkLabel(pill, tostring(title or 'Ataraxia'), {
		font = Enum.Font.SourceSansBold,
		size = 15,
		size2 = UDim2.new(1, -52, 0, 18),
		pos = UDim2.fromOffset(44, 7),
		z = 201,
	})
	mkLabel(pill, 'Tap to show', {
		font = Enum.Font.SourceSans,
		size = 12,
		color = C.muted,
		size2 = UDim2.new(1, -52, 0, 16),
		pos = UDim2.fromOffset(44, 25),
		z = 201,
	})

	local dragging, dragStart, startPos, moved = false, nil, nil, false
	pill.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = true
			moved = false
			dragStart = input.Position
			startPos = pill.Position
		end
	end)
	track(UserInputService.InputChanged:Connect(function(input)
		if not dragging then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input.UserInputType ~= Enum.UserInputType.Touch
		then
			return
		end
		local d = input.Position - dragStart
		if d.Magnitude < 6 then
			return
		end
		moved = true
		pill.Position = UDim2.new(
			startPos.X.Scale,
			startPos.X.Offset + d.X,
			startPos.Y.Scale,
			startPos.Y.Offset + d.Y
		)
	end))
	track(UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch
		then
			return
		end
		if dragging and not moved then
			Library:Toggle(true)
		end
		dragging = false
		moved = false
	end))

	Library._showPill = pill
	return pill
end

function Library:Unload()
	if self.Config then
		pcall(self.Config.Finish)
	end
	self.Unloaded = true
	for _, c in ipairs(self._conns) do
		pcall(function()
			c:Disconnect()
		end)
	end
	table.clear(self._conns)
	if self.ScreenGui then
		pcall(function()
			self.ScreenGui:Destroy()
		end)
	end
	self.ScreenGui = nil
	self._showPill = nil
	table.clear(self.Options)
	table.clear(self.Toggles)
	table.clear(self.Tabs)
	-- Anti-AFK and HideGameplayPaused stay armed across Unload so a script
	-- reload does not bring the idle kick or pause banner back.
end

---------------------------------------------------------------------------
-- Anti-AFK (Infinite Yield style) — built into every CreateWindow so games
-- do not each reimplement mute-Idled + VirtualUser. No jump / keys / camera.
---------------------------------------------------------------------------
local AntiAfk = (function()
	local api = {}
	local FILE = 'Ataraxia/antiafk'
	local remuteAt = 0
	local vuPulseAt = 0
	local rebindIdled

	local function fileDefaultOn()
		if type(isfile) == 'function' and type(readfile) == 'function' then
			local ok, exists = pcall(isfile, FILE)
			if ok and exists then
				local rok, body = pcall(readfile, FILE)
				if rok and tostring(body):lower():find('false', 1, true) then
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
			if type(makefolder) == 'function' and type(isfolder) == 'function' and not isfolder('Ataraxia') then
				makefolder('Ataraxia')
			end
		end)
		pcall(writefile, FILE, on and 'true' or 'false')
	end

	local function pulseVirtualUser(reason)
		pcall(function()
			local vu = game:GetService('VirtualUser')
			vu:CaptureController()
			vu:ClickButton2(Vector2.zero)
		end)
		getgenv().AtaraxiaAntiAfkLastPulse = os.clock()
		getgenv().AtaraxiaAntiAfkLastReason = reason or 'pulse'
	end

	-- Disable every Idled listener. getconnections() proxies are never == to the
	-- RBXScriptConnection from :Connect(), so we always re-bind ours afterward.
	local function muteIdledKick()
		if type(getconnections) ~= 'function' then
			return
		end
		pcall(function()
			for _, conn in ipairs(getconnections(LocalPlayer.Idled)) do
				pcall(function()
					if conn.Disable then
						conn:Disable()
					elseif conn.Disconnect then
						conn:Disconnect()
					end
				end)
			end
		end)
	end

	local function onIdled()
		if getgenv().AtaraxiaAntiAfkOn ~= true then
			return
		end
		pulseVirtualUser('idled')
		muteIdledKick()
		rebindIdled()
	end

	rebindIdled = function()
		local prev = getgenv().AtaraxiaAntiAfkConn
		if prev then
			pcall(function()
				prev:Disconnect()
			end)
		end
		getgenv().AtaraxiaAntiAfkConn = LocalPlayer.Idled:Connect(onIdled)
	end

	local function remuteAndRebind()
		muteIdledKick()
		rebindIdled()
	end

	function api.stop()
		getgenv().AtaraxiaAntiAfkOn = false
		local prev = getgenv().AtaraxiaAntiAfkConn
		if prev then
			pcall(function()
				prev:Disconnect()
			end)
		end
		getgenv().AtaraxiaAntiAfkConn = nil
		local pulse = getgenv().AtaraxiaAntiAfkPulse
		if pulse then
			pcall(function()
				pulse:Disconnect()
			end)
		end
		getgenv().AtaraxiaAntiAfkPulse = nil
		writeFile(false)
	end

	function api.start()
		local pulse = getgenv().AtaraxiaAntiAfkPulse
		if pulse then
			pcall(function()
				pulse:Disconnect()
			end)
		end
		getgenv().AtaraxiaAntiAfkOn = true
		writeFile(true)
		remuteAndRebind()
		getgenv().AtaraxiaAntiAfkPulse = RunService.Heartbeat:Connect(function()
			if getgenv().AtaraxiaAntiAfkOn ~= true then
				return
			end
			local now = os.clock()
			-- Remute often: engine can re-bind Idled kick listeners.
			if now - remuteAt >= 8 then
				remuteAt = now
				remuteAndRebind()
			end
			-- Backup VU click if Idled never fires (some clients stay quiet until kick).
			if now - vuPulseAt >= 540 then
				vuPulseAt = now
				pulseVirtualUser('heartbeat')
			end
		end)
		vuPulseAt = os.clock()
		remuteAt = os.clock()
	end

	function api.isOn()
		return getgenv().AtaraxiaAntiAfkOn == true
	end

	function api.ensure()
		if fileDefaultOn() then
			if not api.isOn() or not getgenv().AtaraxiaAntiAfkConn or not getgenv().AtaraxiaAntiAfkPulse then
				api.start()
			else
				remuteAndRebind()
			end
		end
	end

	return api
end)()

function Library:SetAntiAfk(on)
	if on == false then
		AntiAfk.stop()
	else
		AntiAfk.start()
	end
	return AntiAfk.isOn()
end

function Library:IsAntiAfk()
	return AntiAfk.isOn()
end

---------------------------------------------------------------------------
-- Invisicam. Games reset DevCameraOcclusionMode, so this re-applies. Opt out:
-- CreateWindow{ Invisicam = false }. Persists in Ataraxia/invisicam like Anti-AFK.
---------------------------------------------------------------------------
local Occlusion = (function()
	local api = {}
	local FILE = 'Ataraxia/invisicam'

	local function fileDefaultOn()
		if type(isfile) == 'function' and type(readfile) == 'function' then
			local ok, exists = pcall(isfile, FILE)
			if ok and exists then
				local rok, body = pcall(readfile, FILE)
				if rok and tostring(body):lower():find('false', 1, true) then
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
			if type(makefolder) == 'function' and type(isfolder) == 'function' and not isfolder('Ataraxia') then
				makefolder('Ataraxia')
			end
		end)
		pcall(writefile, FILE, on and 'true' or 'false')
	end

	local function savedMode()
		if getgenv().AtaraxiaSavedOcclusion == nil then
			pcall(function()
				getgenv().AtaraxiaSavedOcclusion = LocalPlayer.DevCameraOcclusionMode
			end)
		end
		return getgenv().AtaraxiaSavedOcclusion or Enum.DevCameraOcclusionMode.Zoom
	end

	local function apply(on)
		pcall(function()
			local want = on and Enum.DevCameraOcclusionMode.Invisicam or savedMode()
			if LocalPlayer.DevCameraOcclusionMode ~= want then
				LocalPlayer.DevCameraOcclusionMode = want
			end
		end)
	end

	function api.set(on)
		local want = on == true
		local was = getgenv().AtaraxiaInvisicamOn == true
		getgenv().AtaraxiaInvisicamOn = want
		apply(want)
		if was ~= want then
			writeFile(want)
		end
	end

	function api.isOn()
		return getgenv().AtaraxiaInvisicamOn == true
	end

	function api.tick()
		if getgenv().AtaraxiaInvisicamOn == true then
			apply(true)
		end
	end

	function api.ensure()
		if fileDefaultOn() then
			getgenv().AtaraxiaInvisicamOn = true
			apply(true)
		end
	end

	return api
end)()

function Library:SetInvisicam(on)
	if on == false then
		Occlusion.set(false)
	else
		Occlusion.set(true)
	end
	return Occlusion.isOn()
end

function Library:IsInvisicam()
	return Occlusion.isOn()
end

---------------------------------------------------------------------------
-- Max camera zoom. Games reset CameraMaxZoomDistance, so this re-applies. Opt out:
-- CreateWindow{ MaxZoom = false }. Persists in Ataraxia/maxzoom (default 3000).
---------------------------------------------------------------------------
local DEFAULT_MAX_ZOOM = 3000

local MaxZoom = (function()
	local api = {}
	local FILE = 'Ataraxia/maxzoom'

	local function clearConns()
		local packs = getgenv().AtaraxiaMaxZoomConns
		if type(packs) ~= 'table' then
			getgenv().AtaraxiaMaxZoomConns = {}
			return
		end
		for _, pack in ipairs(packs) do
			for _, c in ipairs(pack) do
				pcall(function()
					c:Disconnect()
				end)
			end
		end
		getgenv().AtaraxiaMaxZoomConns = {}
	end

	local function readPrefs()
		local on = true
		local target = DEFAULT_MAX_ZOOM
		if type(isfile) == 'function' and type(readfile) == 'function' then
			local ok, exists = pcall(isfile, FILE)
			if ok and exists then
				local rok, body = pcall(readfile, FILE)
				if rok and type(body) == 'string' then
					local trimmed = tostring(body):gsub('%s+', '')
					if trimmed:lower() == 'false' or trimmed:lower() == 'off' then
						on = false
					else
						local n = tonumber(trimmed)
						if n and n >= 0.5 then
							target = n
						end
					end
				end
			end
		end
		return on, target
	end

	local function writeFile(on, target)
		if type(writefile) ~= 'function' then
			return
		end
		pcall(function()
			if type(makefolder) == 'function' and type(isfolder) == 'function' and not isfolder('Ataraxia') then
				makefolder('Ataraxia')
			end
		end)
		if on then
			pcall(writefile, FILE, tostring(target or DEFAULT_MAX_ZOOM))
		else
			pcall(writefile, FILE, 'false')
		end
	end

	local function savedDistance()
		if getgenv().AtaraxiaSavedMaxZoom == nil then
			pcall(function()
				getgenv().AtaraxiaSavedMaxZoom = LocalPlayer.CameraMaxZoomDistance
			end)
		end
		return getgenv().AtaraxiaSavedMaxZoom or 128
	end

	local function targetDistance()
		local t = getgenv().AtaraxiaMaxZoomTarget
		if type(t) == 'number' and t >= 0.5 then
			return t
		end
		return DEFAULT_MAX_ZOOM
	end

	local function apply(on)
		pcall(function()
			local want = on and targetDistance() or savedDistance()
			if LocalPlayer.CameraMaxZoomDistance ~= want then
				LocalPlayer.CameraMaxZoomDistance = want
			end
		end)
	end

	local function bindWatch()
		clearConns()
		if getgenv().AtaraxiaMaxZoomOn ~= true then
			return
		end
		local pack = {}
		pack[#pack + 1] = LocalPlayer:GetPropertyChangedSignal('CameraMaxZoomDistance'):Connect(function()
			if getgenv().AtaraxiaMaxZoomOn ~= true then
				return
			end
			apply(true)
		end)
		getgenv().AtaraxiaMaxZoomConns = { pack }
	end

	local function ensureCharAdded()
		if getgenv().AtaraxiaMaxZoomCharAddedConn then
			return
		end
		getgenv().AtaraxiaMaxZoomCharAddedConn = LocalPlayer.CharacterAdded:Connect(function()
			if getgenv().AtaraxiaMaxZoomOn == true then
				apply(true)
			end
		end)
	end

	function api.set(on, target)
		local want = on == true
		if want and type(target) == 'number' and target >= 0.5 then
			getgenv().AtaraxiaMaxZoomTarget = target
		elseif want and getgenv().AtaraxiaMaxZoomTarget == nil then
			getgenv().AtaraxiaMaxZoomTarget = DEFAULT_MAX_ZOOM
		end
		local was = getgenv().AtaraxiaMaxZoomOn == true
		getgenv().AtaraxiaMaxZoomOn = want
		apply(want)
		if want then
			bindWatch()
			ensureCharAdded()
		else
			clearConns()
		end
		if was ~= want then
			writeFile(want, targetDistance())
		end
	end

	function api.isOn()
		return getgenv().AtaraxiaMaxZoomOn == true
	end

	function api.getTarget()
		return targetDistance()
	end

	function api.tick()
		if getgenv().AtaraxiaMaxZoomOn == true then
			apply(true)
		end
	end

	function api.ensure()
		local on, target = readPrefs()
		getgenv().AtaraxiaMaxZoomTarget = target
		if on then
			getgenv().AtaraxiaMaxZoomOn = true
			apply(true)
			bindWatch()
			ensureCharAdded()
		else
			getgenv().AtaraxiaMaxZoomOn = false
		end
	end

	return api
end)()

function Library:SetMaxZoom(on, distance)
	if on == false or on == 'off' then
		MaxZoom.set(false)
	elseif type(on) == 'number' then
		MaxZoom.set(true, on)
	elseif distance and type(distance) == 'number' then
		MaxZoom.set(on == true, distance)
	else
		MaxZoom.set(on ~= false)
	end
	return MaxZoom.isOn()
end

function Library:IsMaxZoom()
	return MaxZoom.isOn()
end

function Library:GetMaxZoomTarget()
	return MaxZoom.getTarget()
end

---------------------------------------------------------------------------
-- Fullbright (Infinite Yield loopfb). Re-applies each frame while on.
-- Opt out: CreateWindow{ Fullbright = false }. Persists in Ataraxia/fullbright.
-- IY: add PlayerTools/Ataraxia.iy or use fullbright | loopfb | unloopfb commands.
---------------------------------------------------------------------------
local Fullbright = (function()
	local api = {}
	local FILE = 'Ataraxia/fullbright'

	local function disconnectLoop()
		local conn = getgenv().AtaraxiaFullbrightConn
		if conn then
			pcall(function()
				conn:Disconnect()
			end)
		end
		getgenv().AtaraxiaFullbrightConn = nil
	end

	local function captureSaved()
		if type(getgenv().AtaraxiaSavedLighting) == 'table' then
			return
		end
		getgenv().AtaraxiaSavedLighting = {
			Brightness = Lighting.Brightness,
			ClockTime = Lighting.ClockTime,
			FogEnd = Lighting.FogEnd,
			FogStart = Lighting.FogStart,
			Ambient = Lighting.Ambient,
			OutdoorAmbient = Lighting.OutdoorAmbient,
			GlobalShadows = Lighting.GlobalShadows,
		}
	end

	local function applyBright()
		Lighting.Brightness = 2
		Lighting.ClockTime = 14
		Lighting.FogEnd = 100000
		Lighting.FogStart = 0
		Lighting.GlobalShadows = false
		Lighting.OutdoorAmbient = Color3.fromRGB(128, 128, 128)
	end

	local function restoreSaved()
		local s = getgenv().AtaraxiaSavedLighting
		if type(s) ~= 'table' then
			return
		end
		pcall(function()
			Lighting.Brightness = s.Brightness
			Lighting.ClockTime = s.ClockTime
			Lighting.FogEnd = s.FogEnd
			Lighting.FogStart = s.FogStart
			Lighting.Ambient = s.Ambient
			Lighting.OutdoorAmbient = s.OutdoorAmbient
			Lighting.GlobalShadows = s.GlobalShadows
		end)
	end

	local function readFileOn()
		if type(isfile) == 'function' and type(readfile) == 'function' then
			local ok, exists = pcall(isfile, FILE)
			if ok and exists then
				local rok, body = pcall(readfile, FILE)
				if rok and tostring(body):lower():find('true', 1, true) then
					return true
				end
			end
		end
		return false
	end

	local function writeFile(on)
		if type(writefile) ~= 'function' then
			return
		end
		pcall(function()
			if type(makefolder) == 'function' and type(isfolder) == 'function' and not isfolder('Ataraxia') then
				makefolder('Ataraxia')
			end
		end)
		pcall(writefile, FILE, on and 'true' or 'false')
	end

	local function bindLoop()
		disconnectLoop()
		if getgenv().AtaraxiaFullbrightOn ~= true then
			return
		end
		applyBright()
		getgenv().AtaraxiaFullbrightConn = RunService.RenderStepped:Connect(applyBright)
	end

	function api.set(on)
		local want = on == true
		local was = getgenv().AtaraxiaFullbrightOn == true
		if want then
			captureSaved()
			getgenv().AtaraxiaFullbrightOn = true
			bindLoop()
		else
			getgenv().AtaraxiaFullbrightOn = false
			disconnectLoop()
			restoreSaved()
		end
		if was ~= want then
			writeFile(want)
		end
	end

	function api.toggle()
		api.set(not api.isOn())
		return api.isOn()
	end

	function api.isOn()
		return getgenv().AtaraxiaFullbrightOn == true
	end

	function api.tick()
		if getgenv().AtaraxiaFullbrightOn == true then
			applyBright()
		end
	end

	function api.ensure()
		if readFileOn() then
			getgenv().AtaraxiaFullbrightOn = true
			captureSaved()
			bindLoop()
		else
			getgenv().AtaraxiaFullbrightOn = false
		end
	end

	return api
end)()

function Library:SetFullbright(on)
	if on == false or on == 'off' then
		Fullbright.set(false)
	else
		Fullbright.set(true)
	end
	return Fullbright.isOn()
end

function Library:ToggleFullbright()
	Fullbright.toggle()
	return Fullbright.isOn()
end

function Library:IsFullbright()
	return Fullbright.isOn()
end

---------------------------------------------------------------------------
-- Hide Roblox "Gameplay Paused". The engine stall is not switchable from Lua;
-- this only keeps the CoreGui banner off. Opt out: CreateWindow{ HideGameplayPaused = false }.
-- Persists in Ataraxia/nopause. Stays armed across Unload like Anti-AFK.
---------------------------------------------------------------------------
local NoPause = (function()
	local api = {}
	local FILE = 'Ataraxia/nopause'
	local NAME = 'RobloxNetworkPauseNotification'

	local function fileDefaultOn()
		if type(isfile) == 'function' and type(readfile) == 'function' then
			local ok, exists = pcall(isfile, FILE)
			if ok and exists then
				local rok, body = pcall(readfile, FILE)
				if rok and tostring(body):lower():find('false', 1, true) then
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
			if type(makefolder) == 'function' and type(isfolder) == 'function' and not isfolder('Ataraxia') then
				makefolder('Ataraxia')
			end
		end)
		pcall(writefile, FILE, on and 'true' or 'false')
	end

	local function setEngineFlag(hide)
		pcall(function()
			GuiService:SetGameplayPausedNotificationEnabled(hide ~= true)
		end)
	end

	local function silence(sg)
		if not sg then
			return
		end
		pcall(function()
			if sg:IsA('LayerCollector') then
				sg.Enabled = false
			end
			if sg:IsA('GuiObject') then
				sg.Visible = false
			end
			for _, d in ipairs(sg:GetDescendants()) do
				if d:IsA('GuiObject') then
					d.Visible = false
				end
			end
		end)
	end

	local function hookOverlay(sg)
		if not sg then
			return
		end
		silence(sg)
		if sg:GetAttribute('AtaraxiaNoPause') == true then
			return
		end
		pcall(function()
			sg:SetAttribute('AtaraxiaNoPause', true)
		end)
		local hooks = getgenv().AtaraxiaNoPauseHooks
		if type(hooks) ~= 'table' then
			hooks = {}
			getgenv().AtaraxiaNoPauseHooks = hooks
		end
		if sg:IsA('LayerCollector') then
			hooks[#hooks + 1] = sg:GetPropertyChangedSignal('Enabled'):Connect(function()
				if getgenv().AtaraxiaNoPauseOn == true and sg.Enabled then
					silence(sg)
				end
			end)
		end
		hooks[#hooks + 1] = sg.DescendantAdded:Connect(function(d)
			if getgenv().AtaraxiaNoPauseOn == true and d:IsA('GuiObject') then
				pcall(function()
					d.Visible = false
				end)
			end
		end)
	end

	local function scan()
		local ok, CoreGui = pcall(function()
			return game:GetService('CoreGui')
		end)
		if not ok or not CoreGui then
			return
		end
		pcall(function()
			hookOverlay(CoreGui:FindFirstChild(NAME))
		end)
		pcall(function()
			local rg = CoreGui:FindFirstChild('RobloxGui')
			if not rg then
				return
			end
			for _, child in ipairs(rg:GetChildren()) do
				local n = child.Name
				if n == 'NetworkPause' or n == 'CoreScripts/NetworkPause' then
					hookOverlay(child)
				end
			end
		end)
	end

	local function dropHooks()
		local hooks = getgenv().AtaraxiaNoPauseHooks
		if type(hooks) == 'table' then
			for _, c in ipairs(hooks) do
				pcall(function()
					c:Disconnect()
				end)
			end
		end
		getgenv().AtaraxiaNoPauseHooks = {}
	end

	function api.stop()
		getgenv().AtaraxiaNoPauseOn = false
		local watch = getgenv().AtaraxiaNoPauseWatch
		if watch then
			pcall(function()
				watch:Disconnect()
			end)
		end
		getgenv().AtaraxiaNoPauseWatch = nil
		local tick = getgenv().AtaraxiaNoPauseTick
		if tick then
			pcall(function()
				tick:Disconnect()
			end)
		end
		getgenv().AtaraxiaNoPauseTick = nil
		dropHooks()
		setEngineFlag(false)
		pcall(function()
			local sg = game:GetService('CoreGui'):FindFirstChild(NAME)
			if sg and sg:IsA('LayerCollector') then
				sg.Enabled = true
			end
		end)
		writeFile(false)
	end

	function api.start()
		getgenv().AtaraxiaNoPauseOn = true
		writeFile(true)
		setEngineFlag(true)
		scan()
		if not getgenv().AtaraxiaNoPauseWatch then
			local ok, CoreGui = pcall(function()
				return game:GetService('CoreGui')
			end)
			if ok and CoreGui then
				getgenv().AtaraxiaNoPauseWatch = CoreGui.ChildAdded:Connect(function(ch)
					if getgenv().AtaraxiaNoPauseOn ~= true then
						return
					end
					if ch.Name == NAME or ch.Name == 'NetworkPause' then
						hookOverlay(ch)
					end
					setEngineFlag(true)
				end)
			end
		end
		if not getgenv().AtaraxiaNoPauseTick then
			getgenv().AtaraxiaNoPauseTick = RunService.Heartbeat:Connect(function()
				if getgenv().AtaraxiaNoPauseOn ~= true then
					return
				end
				local now = os.clock()
				if now - (getgenv().AtaraxiaNoPauseScanAt or 0) < 0.35 then
					return
				end
				getgenv().AtaraxiaNoPauseScanAt = now
				setEngineFlag(true)
				pcall(function()
					local sg = game:GetService('CoreGui'):FindFirstChild(NAME)
					if sg and sg:IsA('LayerCollector') and sg.Enabled then
						silence(sg)
					end
				end)
			end)
		end
	end

	function api.isOn()
		return getgenv().AtaraxiaNoPauseOn == true
	end

	function api.ensure()
		if fileDefaultOn() then
			api.start()
		end
	end

	return api
end)()

function Library:SetHideGameplayPaused(on)
	if on == false then
		NoPause.stop()
	else
		NoPause.start()
	end
	return NoPause.isOn()
end

function Library:IsHideGameplayPaused()
	return NoPause.isOn()
end

---------------------------------------------------------------------------
-- Notification mute. Library:Notify no-ops when off.
-- Persists in Ataraxia/notifications (default on). Shared across games.
---------------------------------------------------------------------------
local NotifyPref = (function()
	local api = {}
	local FILE = 'Ataraxia/notifications'
	local enabled = true

	local function readFile()
		if type(isfile) == 'function' and type(readfile) == 'function' then
			local ok, exists = pcall(isfile, FILE)
			if ok and exists then
				local rok, body = pcall(readfile, FILE)
				if rok and tostring(body):lower():find('false', 1, true) then
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
			if type(makefolder) == 'function' and type(isfolder) == 'function' and not isfolder('Ataraxia') then
				makefolder('Ataraxia')
			end
		end)
		pcall(writefile, FILE, on and 'true' or 'false')
	end

	enabled = readFile()

	function api.isOn()
		return enabled == true
	end

	function api.set(on)
		enabled = on ~= false
		writeFile(enabled)
		return enabled
	end

	return api
end)()

function Library:SetNotifyEnabled(on)
	return NotifyPref.set(on)
end

function Library:IsNotifyEnabled()
	return NotifyPref.isOn()
end

function Library:AddNotifyToggle(box)
	if not box or type(box.AddToggle) ~= 'function' then
		return
	end
	return box:AddToggle('ATA_Notifications', {
		Text = 'Show notifications',
		Default = NotifyPref.isOn(),
		Tooltip = 'Ataraxia toasts (Library:Notify). Off is saved in Ataraxia/notifications for every game.',
	}):OnChanged(function(v)
		Library:SetNotifyEnabled(v == true)
	end)
end

function Library:AddFullbrightToggle(box)
	if not box or type(box.AddToggle) ~= 'function' then
		return
	end
	return box:AddToggle('ATA_Fullbright', {
		Text = 'Fullbright',
		Default = Fullbright.isOn(),
		Tooltip = 'IY loopfb-style lighting pin. Saved in Ataraxia/fullbright. Chat: fullbright, loopfb, unloopfb.',
	}):OnChanged(function(v)
		Library:SetFullbright(v == true)
	end)
end

function Library:SayIy(msg)
	msg = tostring(msg or '')
	if msg == '' then
		return
	end
	pcall(function()
		print('[Ataraxia] ' .. msg)
	end)
	pcall(function()
		if type(notify) == 'function' then
			notify(msg)
		end
	end)
	pcall(function()
		self:Notify(msg)
	end)
end

function Library:BuildIyPlugin()
	local lib = self
	local function fbSay(on)
		lib:SayIy('Fullbright ' .. (on and 'on' or 'off'))
	end
	local function setOn()
		lib:SetFullbright(true)
		fbSay(true)
	end
	local function setOff()
		lib:SetFullbright(false)
		fbSay(false)
	end
	return {
		['PluginName'] = 'Ataraxia',
		['PluginDescription'] = 'Shared Ataraxia chrome helpers (fullbright / loopfb). Uses PlayerTools when loaded.',
		['Commands'] = {
			['fullbright'] = {
				['ListName'] = 'fullbright',
				['Description'] = 'Enable loop fullbright (same as IY loopfb)',
				['Aliases'] = { 'fb', 'bright' },
				['Function'] = setOn,
			},
			['loopfb'] = {
				['ListName'] = 'loopfb',
				['Description'] = 'Enable loop fullbright (Ataraxia pin)',
				['Aliases'] = { 'loopfullbright' },
				['Function'] = setOn,
			},
			['fullbrightoff'] = {
				['ListName'] = 'fullbrightoff',
				['Description'] = 'Disable fullbright and restore saved lighting',
				['Aliases'] = { 'fboff', 'unfullbright' },
				['Function'] = setOff,
			},
			['unloopfb'] = {
				['ListName'] = 'unloopfb',
				['Description'] = 'Disable loop fullbright',
				['Aliases'] = { 'noloopfb' },
				['Function'] = setOff,
			},
			['fullbrighttoggle'] = {
				['ListName'] = 'fullbrighttoggle',
				['Description'] = 'Toggle fullbright on/off',
				['Aliases'] = { 'fbtoggle', 'togglefb', 'loopfbtoggle' },
				['Function'] = function()
					local on = lib:ToggleFullbright()
					fbSay(on)
				end,
			},
		},
	}
end

function Library:ListThemes()
	local out = {}
	for i, name in ipairs(THEME_ORDER) do
		out[i] = name
	end
	return out
end

function Library:GetTheme()
	return currentThemeName
end

function Library:ApplyTheme(name, silent)
	name = tostring(name or 'Default')
	if not THEMES[name] then
		name = 'Default'
	end
	local old = {}
	for k, v in pairs(C) do
		old[k] = v
	end
	currentThemeName = name
	copyThemeIntoC(THEMES[name])
	writeThemeFile(name)

	local function remap(col)
		if typeof(col) ~= 'Color3' then
			return nil
		end
		for k, v in pairs(old) do
			if col == v then
				return C[k]
			end
		end
		return nil
	end

	local gui = self.ScreenGui
	if gui then
		for _, d in ipairs(gui:GetDescendants()) do
			if d:IsA('GuiObject') then
				local nb = remap(d.BackgroundColor3)
				if nb then
					d.BackgroundColor3 = nb
				end
			end
			if d:IsA('TextLabel') or d:IsA('TextButton') or d:IsA('TextBox') then
				local nt = remap(d.TextColor3)
				if nt then
					d.TextColor3 = nt
				end
			end
			if d:IsA('UIStroke') then
				local ns = remap(d.Color)
				if ns then
					d.Color = ns
				end
			end
			if d:IsA('ScrollingFrame') then
				local ns = remap(d.ScrollBarImageColor3)
				if ns then
					d.ScrollBarImageColor3 = ns
				end
			end
		end
	end

	for _, obj in pairs(self.Toggles or {}) do
		if type(obj.Display) == 'function' then
			pcall(function()
				obj:Display()
			end)
		end
	end

	if not silent then
		self:Notify('Theme · ' .. name)
	end
	return name
end

-- Default Settings tab: Script + Profiles (+ theme). Opt out: CreateWindow{ SettingsTab = false }.
-- Optional: SettingsExtras(scriptBox, profileBox, tab), OnUnload().
function Library:BuildSettingsTab(Window, info)
	info = info or {}
	if not Window or type(Window.AddTab) ~= 'function' then
		return nil
	end
	if self.Tabs and self.Tabs.Settings then
		return self.Tabs.Settings
	end

	local tab = Window:AddTab('Settings', 'settings')
	-- Keep Settings at the bottom of the rail even if created early.
	pcall(function()
		local gui = self.ScreenGui
		local rail = gui and gui:FindFirstChild('Main')
		rail = rail and rail:FindFirstChild('Body')
		rail = rail and rail:FindFirstChild('Rail')
		rail = rail and rail:FindFirstChild('RailScroll')
		local btn = rail and rail:FindFirstChild('Settings')
		if btn then
			btn.LayoutOrder = 9999
		end
	end)

	local scriptBox = tab:AddLeftGroupbox('Script')
	scriptBox:AddLabel('Home hides/shows this window (same as PlayerTools).')
	tab.ScriptBox = scriptBox

	local profileBox = tab:AddRightGroupbox('Profiles')
	tab.ProfileBox = profileBox

	-- Script-specific rows (e.g. Auto inject) before shared chrome controls.
	if type(info.SettingsExtras) == 'function' then
		pcall(info.SettingsExtras, scriptBox, profileBox, tab)
	end

	self:AddNotifyToggle(scriptBox)
	self:AddFullbrightToggle(scriptBox)

	scriptBox:AddDropdown('ATA_Theme', {
		Text = 'Theme',
		Values = self:ListThemes(),
		Default = self:GetTheme(),
		Tooltip = 'Ataraxia chrome colors. Default is the classic look. Saved in Ataraxia/theme for every game.',
	}):OnChanged(function(v)
		local name = tostring(v or 'Default')
		if name ~= '' and name ~= self:GetTheme() then
			self:ApplyTheme(name, false)
		end
	end)

	scriptBox:AddButton('Hide menu', function()
		self:Toggle(false)
	end)
	scriptBox:AddButton('Unload', function()
		if type(info.OnUnload) == 'function' then
			pcall(info.OnUnload)
		end
		self:Unload()
	end)
	scriptBox:AddButton('Save current profile now', function()
		local ok = false
		if self.Config and type(self.Config.SaveCurrent) == 'function' then
			ok = self.Config.SaveCurrent() == true
		end
		self:Notify(ok and 'Profile saved' or 'Profile save failed')
	end)
	scriptBox:AddButton('Reset settings to defaults', function()
		if self.Config and type(self.Config.Reset) == 'function' then
			self.Config.Reset()
		end
		self:Notify('Settings reset to defaults')
	end)

	if self.Config and type(self.Config.Build) == 'function' then
		self.Config.Build(profileBox)
	end

	return tab
end

local function fireChanged(obj, value)
	for _, fn in ipairs(obj._changed or {}) do
		task.spawn(fn, value)
	end
end

local function attachOnChanged(obj)
	function obj:OnChanged(fn)
		self._changed = self._changed or {}
		self._changed[#self._changed + 1] = fn
		return self
	end
end

---------------------------------------------------------------------------
-- Controls
---------------------------------------------------------------------------
local function addToggle(box, idx, opts)
	opts = opts or {}
	local row = Instance.new('Frame')
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, -12, 0, 30)
	row.Parent = box.Container
	mkLabel(row, opts.Text or idx, {
		size = 14,
		size2 = UDim2.new(1, -54, 1, 0),
		pos = UDim2.fromOffset(0, 0),
		truncate = Enum.TextTruncate.AtEnd,
	})

	local on = opts.Default == true
	local pill = Instance.new('TextButton')
	pill.Size = UDim2.fromOffset(44, 24)
	pill.Position = UDim2.new(1, -44, 0.5, -12)
	pill.BackgroundColor3 = on and C.accent or C.bg3
	pill.Text = ''
	pill.AutoButtonColor = false
	pill.BorderSizePixel = 0
	pill.ZIndex = 5
	pill.Parent = row
	corner(pill, 12)
	local knob = Instance.new('Frame')
	knob.Size = UDim2.fromOffset(18, 18)
	knob.Position = on and UDim2.new(1, -21, 0.5, -9) or UDim2.fromOffset(3, 3)
	knob.BackgroundColor3 = on and C.bg0 or C.muted
	knob.BorderSizePixel = 0
	knob.ZIndex = 6
	knob.Parent = pill
	corner(knob, 9)

	local obj = {
		Type = 'Toggle',
		Idx = idx,
		Value = on,
		Destroyed = false,
		_changed = {},
	}
	attachOnChanged(obj)

	local function paint(v)
		obj.Value = v == true
		pill.BackgroundColor3 = obj.Value and C.accent or C.bg3
		knob.BackgroundColor3 = obj.Value and C.bg0 or C.muted
		knob.Position = obj.Value and UDim2.new(1, -21, 0.5, -9) or UDim2.fromOffset(3, 3)
	end

	function obj:SetValue(v)
		local nv = v == true
		if self.Value == nv then
			if self.Display then
				self:Display()
			end
			return
		end
		paint(nv)
		fireChanged(self, self.Value)
	end

	function obj:Display()
		paint(self.Value)
	end

	pill.MouseButton1Click:Connect(function()
		obj:SetValue(not obj.Value)
	end)

	Library.Toggles[idx] = obj
	Library.Options[idx] = obj
	box:_relayout()
	return obj
end

local function addButton(box, text, callback)
	local b = Instance.new('TextButton')
	b.Size = UDim2.new(1, -16, 0, 30)
	b.BackgroundColor3 = C.bg3
	b.Text = tostring(text or 'Button')
	b.TextColor3 = C.text
	b.Font = Enum.Font.GothamMedium
	b.TextSize = 12
	b.AutoButtonColor = false
	b.BorderSizePixel = 0
	b.Parent = box.Container
	corner(b, 4)
	hairline(b, 4)
	b.MouseButton1Click:Connect(function()
		if type(callback) == 'function' then
			task.spawn(callback)
		end
	end)
	box:_relayout()
	return b
end

local function addSlider(box, idx, opts)
	opts = opts or {}
	local minV = tonumber(opts.Min) or 0
	local maxV = tonumber(opts.Max) or 100
	local rounding = tonumber(opts.Rounding) or 0
	local value = tonumber(opts.Default) or minV
	value = math.clamp(value, minV, maxV)

	local wrap = Instance.new('Frame')
	wrap.BackgroundTransparency = 1
	wrap.Size = UDim2.new(1, -16, 0, 44)
	wrap.Parent = box.Container

	local title = mkLabel(wrap, (opts.Text or idx) .. '  ' .. tostring(value), {
		size = 12,
		size2 = UDim2.new(1, 0, 0, 16),
	})
	local trackBar = Instance.new('Frame')
	trackBar.Size = UDim2.new(1, 0, 0, 8)
	trackBar.Position = UDim2.fromOffset(0, 26)
	trackBar.BackgroundColor3 = C.bg0
	trackBar.BorderSizePixel = 0
	trackBar.Parent = wrap
	corner(trackBar, 4)
	local fill = Instance.new('Frame')
	fill.Size = UDim2.new((value - minV) / math.max(1e-6, maxV - minV), 0, 1, 0)
	fill.BackgroundColor3 = C.accent
	fill.BorderSizePixel = 0
	fill.Parent = trackBar
	corner(fill, 4)

	local obj = {
		Type = 'Slider',
		Idx = idx,
		Value = value,
		Min = minV,
		Max = maxV,
		Destroyed = false,
		_changed = {},
	}
	attachOnChanged(obj)

	local function round(v)
		if rounding <= 0 then
			return math.floor(v + 0.5)
		end
		local m = 10 ^ rounding
		return math.floor(v * m + 0.5) / m
	end

	function obj:SetValue(v)
		v = round(math.clamp(tonumber(v) or minV, minV, maxV))
		self.Value = v
		fill.Size = UDim2.new((v - minV) / math.max(1e-6, maxV - minV), 0, 1, 0)
		title.Text = (opts.Text or idx) .. '  ' .. tostring(v)
		fireChanged(self, v)
	end

	local sliding = false
	trackBar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			sliding = true
		end
	end)
	track(UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			sliding = false
		end
	end))
	track(UserInputService.InputChanged:Connect(function(input)
		if sliding and input.UserInputType == Enum.UserInputType.MouseMovement then
			local rel = math.clamp((input.Position.X - trackBar.AbsolutePosition.X) / math.max(1, trackBar.AbsoluteSize.X), 0, 1)
			obj:SetValue(minV + rel * (maxV - minV))
		end
	end))

	Library.Options[idx] = obj
	box:_relayout()
	return obj
end

local function addInput(box, idx, opts)
	opts = opts or {}
	local wrap = Instance.new('Frame')
	wrap.BackgroundTransparency = 1
	wrap.Size = UDim2.new(1, -16, 0, opts.Text and 52 or 32)
	wrap.Parent = box.Container
	local y = 0
	if opts.Text then
		mkLabel(wrap, opts.Text, { size = 12, size2 = UDim2.new(1, 0, 0, 16) })
		y = 20
	end
	local boxIn = Instance.new('TextBox')
	boxIn.Size = UDim2.new(1, 0, 0, 28)
	boxIn.Position = UDim2.fromOffset(0, y)
	boxIn.BackgroundColor3 = C.bg0
	boxIn.TextColor3 = C.text
	boxIn.PlaceholderText = opts.Placeholder or ''
	boxIn.PlaceholderColor3 = C.muted
	boxIn.Text = tostring(opts.Default or '')
	boxIn.Font = Enum.Font.GothamMedium
	boxIn.TextSize = 12
	boxIn.ClearTextOnFocus = opts.ClearTextOnFocus == true
	boxIn.TextXAlignment = Enum.TextXAlignment.Left
	boxIn.BorderSizePixel = 0
	boxIn.Parent = wrap
	corner(boxIn, 4)
	hairline(boxIn, 4)
	local pad = Instance.new('UIPadding')
	pad.PaddingLeft = UDim.new(0, 8)
	pad.Parent = boxIn

	local obj = {
		Type = 'Input',
		Idx = idx,
		Value = boxIn.Text,
		Destroyed = false,
		_changed = {},
	}
	attachOnChanged(obj)

	function obj:SetValue(v)
		v = tostring(v or '')
		if opts.AllowEmpty == false and v == '' then
			return
		end
		self.Value = v
		boxIn.Text = v
		fireChanged(self, v)
	end

	local function commit()
		local v = boxIn.Text
		if opts.Numeric then
			v = tostring(tonumber(v) or obj.Value or '')
			boxIn.Text = v
		end
		if opts.AllowEmpty == false and v == '' then
			boxIn.Text = tostring(obj.Value or '')
			return
		end
		obj.Value = v
		fireChanged(obj, v)
		if type(opts.Callback) == 'function' then
			task.spawn(opts.Callback, v)
		end
	end

	if opts.Finished then
		-- Keep Value live while typing so other buttons (e.g. Test webhook) can read
		-- the pasted URL before FocusLost commits / fires Callback.
		boxIn:GetPropertyChangedSignal('Text'):Connect(function()
			obj.Value = boxIn.Text
		end)
		boxIn.FocusLost:Connect(function(enter)
			if enter or true then
				commit()
			end
		end)
	else
		boxIn:GetPropertyChangedSignal('Text'):Connect(function()
			obj.Value = boxIn.Text
			if type(opts.Callback) == 'function' then
				task.spawn(opts.Callback, boxIn.Text)
			end
			fireChanged(obj, boxIn.Text)
		end)
	end

	Library.Options[idx] = obj
	box:_relayout()
	return obj
end

local function flattenMultiDefault(default)
	if type(default) == 'table' then
		-- map or array
		local out = {}
		local isMap = false
		for k, v in pairs(default) do
			if type(k) == 'string' and v == true then
				isMap = true
				out[k] = true
			end
		end
		if isMap then
			return out
		end
		for _, v in ipairs(default) do
			if type(v) == 'string' then
				out[v] = true
			end
		end
		return out
	elseif type(default) == 'string' and default ~= '' then
		return { [default] = true }
	end
	return {}
end

local function addDropdown(box, idx, opts)
	opts = opts or {}
	local values = {}
	for _, v in ipairs(opts.Values or {}) do
		values[#values + 1] = v
	end
	local multi = opts.Multi == true
	local value
	if multi then
		value = flattenMultiDefault(opts.Default)
	else
		value = opts.Default
		if value == nil and not opts.AllowNull and values[1] then
			value = values[1]
		end
	end

	local wrap = Instance.new('Frame')
	wrap.BackgroundTransparency = 1
	wrap.Size = UDim2.new(1, -16, 0, 54)
	wrap.ClipsDescendants = false
	wrap.Parent = box.Container
	mkLabel(wrap, opts.Text or idx, {
		size = 13,
		size2 = UDim2.new(1, 0, 0, 16),
	})

	-- Closed field: plain Frame (NOT ScrollingFrame) + label + caret
	local field = Instance.new('Frame')
	field.Name = 'Field'
	field.Size = UDim2.new(1, 0, 0, 30)
	field.Position = UDim2.fromOffset(0, 20)
	field.BackgroundColor3 = C.bg0
	field.BorderSizePixel = 0
	field.ClipsDescendants = true
	field.Parent = wrap
	corner(field, 4)
	hairline(field, 4)

	local valueLbl = mkLabel(field, '', {
		size = 14,
		size2 = UDim2.new(1, -36, 1, 0),
		pos = UDim2.fromOffset(10, 0),
		truncate = Enum.TextTruncate.AtEnd,
	})
	valueLbl.ZIndex = 2

	local caret = mkLabel(field, '▼', {
		font = Enum.Font.SourceSansBold,
		size = 12,
		color = C.muted,
		size2 = UDim2.fromOffset(24, 30),
		pos = UDim2.new(1, -28, 0, 0),
		x = Enum.TextXAlignment.Center,
	})
	caret.ZIndex = 2

	local openBtn = Instance.new('TextButton')
	openBtn.Size = UDim2.fromScale(1, 1)
	openBtn.BackgroundTransparency = 1
	openBtn.Text = ''
	openBtn.AutoButtonColor = false
	openBtn.BorderSizePixel = 0
	openBtn.ZIndex = 3
	openBtn.Parent = field

	-- Popup on ScreenGui (not Main) so Main.ClipsDescendants cannot hide items.
	local listFrame = Instance.new('ScrollingFrame')
	listFrame.Name = 'DropdownList_' .. tostring(idx)
	listFrame.Visible = false
	listFrame.BackgroundColor3 = C.bg1
	listFrame.BorderSizePixel = 0
	listFrame.ScrollBarThickness = 5
	listFrame.ScrollBarImageColor3 = C.muted
	listFrame.ScrollingDirection = Enum.ScrollingDirection.Y
	-- Manual CanvasSize in rebuild — AutomaticCanvasSize + scale-width rows collapsed to blank.
	listFrame.AutomaticCanvasSize = Enum.AutomaticSize.None
	listFrame.CanvasSize = UDim2.fromOffset(0, 0)
	listFrame.ZIndex = 2000
	listFrame.ClipsDescendants = true
	listFrame.Active = true
	listFrame.Parent = Library.ScreenGui or wrap
	corner(listFrame, 4)
	hairline(listFrame, 4)
	local listPad = Instance.new('UIPadding')
	listPad.PaddingTop = UDim.new(0, 4)
	listPad.PaddingBottom = UDim.new(0, 4)
	listPad.PaddingLeft = UDim.new(0, 4)
	listPad.PaddingRight = UDim.new(0, 4)
	listPad.Parent = listFrame
	local listLay = Instance.new('UIListLayout')
	listLay.Padding = UDim.new(0, 2)
	listLay.SortOrder = Enum.SortOrder.LayoutOrder
	listLay.Parent = listFrame

	local searchBox
	if opts.Searchable then
		searchBox = Instance.new('TextBox')
		-- Offset width — scale-X inside AutomaticCanvasSize ScrollingFrame collapses to 0.
		searchBox.Size = UDim2.fromOffset(180, 26)
		searchBox.BackgroundColor3 = C.bg0
		searchBox.TextColor3 = C.text
		searchBox.PlaceholderText = 'Filter...'
		searchBox.PlaceholderColor3 = C.muted
		searchBox.Text = ''
		searchBox.Font = Enum.Font.SourceSans
		searchBox.TextSize = 13
		searchBox.ClearTextOnFocus = false
		searchBox.BorderSizePixel = 0
		searchBox.ZIndex = 2010
		searchBox.LayoutOrder = 0
		searchBox.Parent = listFrame
		corner(searchBox, 3)
		local sp = Instance.new('UIPadding')
		sp.PaddingLeft = UDim.new(0, 8)
		sp.Parent = searchBox
	end

	local obj = {
		Type = 'Dropdown',
		Idx = idx,
		Value = value,
		Values = values,
		Multi = multi,
		Destroyed = false,
		_changed = {},
		_open = false,
		_ignoreAwayUntil = 0,
	}
	attachOnChanged(obj)

	local function displayText()
		if multi then
			local parts = {}
			for _, name in ipairs(obj.Values) do
				if type(obj.Value) == 'table' and obj.Value[name] then
					parts[#parts + 1] = name
				end
			end
			if #parts == 0 then
				return opts.AllowNull and 'None' or 'Select...'
			end
			return table.concat(parts, ', ')
		end
		if obj.Value == nil or obj.Value == '' then
			return opts.AllowNull and 'None' or 'Select...'
		end
		return tostring(obj.Value)
	end

	function obj:Display()
		valueLbl.Text = displayText()
		caret.Text = self._open and '▲' or '▼'
	end

	local function placePopup()
		if not field.Parent or not Library.ScreenGui then
			return
		end
		listFrame.Parent = Library.ScreenGui
		local fp = field.AbsolutePosition
		local fs = field.AbsoluteSize
		-- ScreenGui uses IgnoreGuiInset; AbsolutePosition is already screen-space.
		local nVals = 0
		if type(obj.Values) == 'table' then
			for _ in ipairs(obj.Values) do
				nVals += 1
			end
		end
		local maxH = math.min(220, 26 * math.min(10, math.max(1, nVals)) + (searchBox and 34 or 10))
		local width = math.max(fs.X, 180)
		local x = fp.X
		local y = fp.Y + fs.Y + 4
		-- Keep popup on-screen if field is near the bottom.
		local cam = workspace.CurrentCamera
		local vh = cam and cam.ViewportSize.Y or 800
		if y + maxH > vh - 8 then
			y = math.max(8, fp.Y - maxH - 4)
		end
		listFrame.Size = UDim2.fromOffset(width, maxH)
		listFrame.Position = UDim2.fromOffset(x, y)
		-- Keep filter/rows at offset width so they never collapse to 0.
		local innerW = math.max(width - 12, 160)
		if searchBox then
			searchBox.Size = UDim2.fromOffset(innerW, 26)
		end
		for _, ch in ipairs(listFrame:GetChildren()) do
			if ch:IsA('TextButton') then
				ch.Size = UDim2.fromOffset(innerW, 26)
			end
		end
	end

	local function closePopup()
		obj._open = false
		listFrame.Visible = false
		if Library._openDropdown == obj then
			Library._openDropdown = nil
		end
		obj:Display()
	end

	local function syncCanvas()
		local contentH = listLay.AbsoluteContentSize.Y
		if contentH < 8 then
			contentH = 0
			for _, ch in ipairs(listFrame:GetChildren()) do
				if ch:IsA('GuiObject') and not ch:IsA('UIListLayout') and not ch:IsA('UIPadding') then
					contentH += math.max(ch.AbsoluteSize.Y, 26) + 2
				end
			end
			contentH += 8
		end
		listFrame.CanvasSize = UDim2.fromOffset(0, math.max(contentH, 1))
		listFrame.CanvasPosition = Vector2.zero
		listFrame.ScrollBarThickness = contentH > (listFrame.AbsoluteSize.Y + 2) and 5 or 0
	end

	local rebuild
	local function makeRow(name, raw, order, innerW)
		local item = Instance.new('TextButton')
		item.Size = UDim2.fromOffset(innerW, 26)
		item.BackgroundColor3 = C.bg2
		item.BackgroundTransparency = 0
		item.TextColor3 = C.text
		item.Font = Enum.Font.SourceSans
		item.TextSize = 14
		item.TextXAlignment = Enum.TextXAlignment.Left
		item.AutoButtonColor = true
		item.BorderSizePixel = 0
		item.Text = '  ' .. name
		item.ZIndex = 2010
		item.Active = true
		item.LayoutOrder = order
		item.Parent = listFrame
		corner(item, 3)
		local selected = multi and type(obj.Value) == 'table' and obj.Value[name] or obj.Value == name or obj.Value == raw
		if selected then
			item.BackgroundColor3 = C.bg3
			item.Font = Enum.Font.SourceSansBold
			item.Text = '  ✓ ' .. name
		end
		item.MouseButton1Click:Connect(function()
			if multi then
				if type(obj.Value) ~= 'table' then
					obj.Value = {}
				end
				if obj.Value[name] then
					obj.Value[name] = nil
				else
					obj.Value[name] = true
				end
				obj:Display()
				rebuild()
				fireChanged(obj, obj.Value)
			else
				obj.Value = raw
				obj:Display()
				closePopup()
				fireChanged(obj, obj.Value)
			end
		end)
		return item
	end

	rebuild = function()
		for _, ch in ipairs(listFrame:GetChildren()) do
			if ch:IsA('TextButton') or (ch:IsA('TextLabel') and ch.Name == 'EmptyHint') then
				ch:Destroy()
			end
		end
		local filter = searchBox and string.lower(searchBox.Text or '') or ''
		local width = math.max(listFrame.AbsoluteSize.X, field.AbsoluteSize.X, 180)
		local innerW = math.max(width - 12, 160)
		if searchBox then
			searchBox.Size = UDim2.fromOffset(innerW, 26)
		end
		local count = 0
		local order = 1
		for _, raw in ipairs(obj.Values) do
			local name = tostring(raw)
			if filter == '' or string.find(string.lower(name), filter, 1, true) then
				count += 1
				order += 1
				makeRow(name, raw, order, innerW)
			end
		end
		-- Fallback if Values was stored as a map (Obsidian quirks).
		if count == 0 and type(obj.Values) == 'table' then
			for k, v in pairs(obj.Values) do
				local name = type(k) == 'string' and k or (type(v) == 'string' and v or nil)
				if name and (filter == '' or string.find(string.lower(name), filter, 1, true)) then
					count += 1
					order += 1
					makeRow(name, name, order, innerW)
				end
			end
		end
		if count == 0 then
			local empty = Instance.new('TextLabel')
			empty.Name = 'EmptyHint'
			empty.Size = UDim2.fromOffset(innerW, 26)
			empty.BackgroundTransparency = 1
			empty.TextColor3 = C.muted
			empty.Font = Enum.Font.SourceSans
			empty.TextSize = 13
			empty.TextXAlignment = Enum.TextXAlignment.Left
			empty.Text = filter ~= '' and '  No matches' or '  No options'
			empty.ZIndex = 2010
			empty.LayoutOrder = 1
			empty.Parent = listFrame
		end
		syncCanvas()
		task.defer(syncCanvas)
	end

	function obj:SetValues(list)
		self.Values = {}
		if type(list) == 'table' then
			local n = 0
			for _, v in ipairs(list) do
				n += 1
				self.Values[n] = v
			end
			if n == 0 then
				for k, v in pairs(list) do
					if type(k) == 'string' then
						self.Values[#self.Values + 1] = k
					elseif type(v) == 'string' then
						self.Values[#self.Values + 1] = v
					end
				end
			end
		end
		if self._open then
			rebuild()
			placePopup()
		end
		self:Display()
	end

	function obj:BuildDropdownList()
		if self._open then
			rebuild()
			placePopup()
		end
		self:Display()
	end

	function obj:SetValue(v)
		if multi then
			self.Value = flattenMultiDefault(v)
		else
			self.Value = v
		end
		self:Display()
		if self._open then
			rebuild()
		end
		fireChanged(self, self.Value)
	end

	local function toggleOpen()
		local opening = not obj._open
		if Library._openDropdown and Library._openDropdown ~= obj and type(Library._openDropdown) == 'table' then
			pcall(function()
				Library._openDropdown._open = false
				local other = Library.ScreenGui and Library.ScreenGui:FindFirstChild('DropdownList_' .. tostring(Library._openDropdown.Idx))
				if other then
					other.Visible = false
				end
				if type(Library._openDropdown.Display) == 'function' then
					Library._openDropdown:Display()
				end
			end)
		end
		obj._open = opening
		if obj._open then
			-- Ignore click-away before Visible flips — same press must not instantly close.
			obj._ignoreAwayUntil = os.clock() + 0.45
			Library._openDropdown = obj
			rebuild()
			placePopup()
			listFrame.Visible = true
			listFrame.ZIndex = 2000
			obj:Display()
		else
			closePopup()
		end
	end
	openBtn.MouseButton1Click:Connect(toggleOpen)
	if searchBox then
		searchBox:GetPropertyChangedSignal('Text'):Connect(function()
			rebuild()
		end)
	end

	-- click-away on InputEnded (InputBegan races the open click on some clients)
	track(UserInputService.InputEnded:Connect(function(input)
		if not obj._open then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch
		then
			return
		end
		if os.clock() < (obj._ignoreAwayUntil or 0) then
			return
		end
		local p = input.Position
		local inField = p.X >= field.AbsolutePosition.X
			and p.X <= field.AbsolutePosition.X + field.AbsoluteSize.X
			and p.Y >= field.AbsolutePosition.Y
			and p.Y <= field.AbsolutePosition.Y + field.AbsoluteSize.Y
		local lp = listFrame.AbsolutePosition
		local ls = listFrame.AbsoluteSize
		local inList = listFrame.Visible
			and p.X >= lp.X
			and p.X <= lp.X + ls.X
			and p.Y >= lp.Y
			and p.Y <= lp.Y + ls.Y
		if not inField and not inList then
			closePopup()
		end
	end))

	obj:Display()
	Library.Options[idx] = obj
	box:_relayout()
	return obj
end

local function addLabel(box, text)
	local row = Instance.new('Frame')
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, -16, 0, 18)
	row.Parent = box.Container
	local lab = mkLabel(row, tostring(text or ''), {
		size = 11,
		color = C.muted,
		size2 = UDim2.new(1, 0, 1, 0),
		wrap = true,
	})
	-- grow with wrap
	row.Size = UDim2.new(1, -16, 0, math.max(18, select(2, Library:GetTextBounds(nil, text, nil, 11, 240))))

	local obj = {
		Type = 'Label',
		Text = tostring(text or ''),
		Destroyed = false,
	}
	function obj:SetText(t)
		self.Text = tostring(t or '')
		lab.Text = self.Text
	end

	function obj:AddKeyPicker(idx, opts)
		opts = opts or {}
		local key = tostring(opts.Default or 'Unknown')
		local kp = Instance.new('TextButton')
		kp.Size = UDim2.fromOffset(72, 22)
		kp.Position = UDim2.new(1, -72, 0.5, -11)
		kp.BackgroundColor3 = C.bg3
		kp.Text = key
		kp.TextColor3 = C.text
		kp.Font = Enum.Font.GothamBold
		kp.TextSize = 11
		kp.AutoButtonColor = false
		kp.BorderSizePixel = 0
		kp.Visible = opts.NoUI ~= true
		kp.Parent = row
		corner(kp, 4)

		local kobj = {
			Type = 'KeyPicker',
			Idx = idx,
			Value = key,
			Destroyed = false,
			_changed = {},
		}
		attachOnChanged(kobj)
		function kobj:SetValue(v)
			self.Value = tostring(v or 'Unknown')
			kp.Text = self.Value
			fireChanged(self, self.Value)
		end

		local listening = false
		kp.MouseButton1Click:Connect(function()
			listening = true
			kp.Text = '...'
		end)
		track(UserInputService.InputBegan:Connect(function(input, gp)
			if not listening then
				return
			end
			if input.UserInputType == Enum.UserInputType.Keyboard then
				listening = false
				kobj:SetValue(input.KeyCode.Name)
			end
		end))

		Library.Options[idx] = kobj
		box:_relayout()
		return kobj
	end

	box:_relayout()
	return obj
end

---------------------------------------------------------------------------
-- Groupbox / Tab / Window
---------------------------------------------------------------------------
local function makeGroupbox(sideParent, title)
	local holder = Instance.new('Frame')
	holder.Name = title or 'Groupbox'
	holder.BackgroundColor3 = C.bg1
	holder.BorderSizePixel = 0
	holder.Size = UDim2.new(1, 0, 0, 60)
	holder.ClipsDescendants = true
	holder.Parent = sideParent
	corner(holder, 4)
	hairline(holder, 4)

	-- Clickable header (Obsidian accordion) — Wiki boxes start collapsed.
	local headBtn = Instance.new('TextButton')
	headBtn.Name = 'Header'
	headBtn.Size = UDim2.new(1, 0, 0, 36)
	headBtn.BackgroundTransparency = 1
	headBtn.Text = ''
	headBtn.AutoButtonColor = false
	headBtn.BorderSizePixel = 0
	headBtn.ZIndex = 3
	headBtn.Parent = holder

	local chevron = mkLabel(headBtn, '▼', {
		font = Enum.Font.SourceSansBold,
		size = 14,
		color = C.muted,
		size2 = UDim2.fromOffset(18, 36),
		pos = UDim2.fromOffset(10, 0),
		x = Enum.TextXAlignment.Center,
	})
	chevron.ZIndex = 4

	local head = mkLabel(headBtn, title or '', {
		font = Enum.Font.SourceSansBold,
		size = 15,
		size2 = UDim2.new(1, -40, 1, 0),
		pos = UDim2.fromOffset(32, 0),
	})
	head.ZIndex = 4

	local container = Instance.new('Frame')
	container.Name = 'Container'
	container.BackgroundTransparency = 1
	container.Position = UDim2.fromOffset(8, 38)
	container.Size = UDim2.new(1, -16, 0, 20)
	container.ZIndex = 2
	container.Parent = holder
	local lay = Instance.new('UIListLayout')
	lay.Padding = UDim.new(0, 6)
	lay.Parent = container

	local box = {
		Title = title,
		Holder = holder,
		Container = container,
		Collapsed = false,
	}

	function box:_relayout()
		if self.Collapsed then
			container.Visible = false
			chevron.Text = '▶'
			holder.Size = UDim2.new(1, 0, 0, 36)
			return
		end
		container.Visible = true
		chevron.Text = '▼'
		-- Defer: AbsoluteContentSize is often 0 the frame visibility flips.
		task.defer(function()
			if self.Collapsed or not holder.Parent then
				return
			end
			local h = lay.AbsoluteContentSize.Y
			if h < 8 then
				h = 0
				for _, ch in ipairs(container:GetChildren()) do
					if ch:IsA('GuiObject') and not ch:IsA('UIListLayout') and not ch:IsA('UIPadding') then
						h += math.max(ch.AbsoluteSize.Y, 18) + 6
					end
				end
			end
			h = math.max(h, 24)
			container.Size = UDim2.new(1, -16, 0, h)
			holder.Size = UDim2.new(1, 0, 0, h + 48)
		end)
	end

	function box:Resize()
		self:_relayout()
	end

	function box:SetCollapsed(v)
		self.Collapsed = v == true
		self:_relayout()
	end

	headBtn.MouseButton1Click:Connect(function()
		box:SetCollapsed(not box.Collapsed)
	end)

	function box:AddToggle(idx, opts)
		return addToggle(self, idx, opts)
	end
	function box:AddButton(text, cb)
		return addButton(self, text, cb)
	end
	function box:AddSlider(idx, opts)
		return addSlider(self, idx, opts)
	end
	function box:AddDropdown(idx, opts)
		return addDropdown(self, idx, opts)
	end
	function box:AddInput(idx, opts)
		return addInput(self, idx, opts)
	end
	function box:AddLabel(text)
		return addLabel(self, text)
	end

	track(lay:GetPropertyChangedSignal('AbsoluteContentSize'):Connect(function()
		box:_relayout()
	end))
	box:_relayout()
	return box
end

---------------------------------------------------------------------------
-- Account-based profiles.
-- Named files live in Ataraxia/<game>/profiles/ and are a shared list every
-- account can load. Autoload is Ataraxia/<game>/autoload/<account>.txt so a
-- save on one alt does not boot that profile on another. Each game folder is
-- its own set (Dungeon Lootr ≠ PlayerTools).
---------------------------------------------------------------------------
Library.Config = (function()
	local HttpService = game:GetService('HttpService')
	local KINDS = { Toggle = true, Slider = true, Dropdown = true, Input = true, KeyPicker = true }
	local SKIP_PREFIX = 'ATA_'
	local SAVE_DELAY = 1.5
	local api = {}
	local gameFolder = 'default'
	local skip = {}
	local suspended, dirty, saveAt = false, false, 0
	local defaults = nil
	local statusLabel = nil
	local assignedName = nil

	local function sanitize(s, fallback)
		s = tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', '')
		s = s:gsub('[^%w%._ %-]', '')
		s = s:gsub('%s+', ' ')
		if s == '' then
			return fallback or ''
		end
		if #s > 48 then
			s = s:sub(1, 48)
		end
		return s
	end

	local function accountKey()
		local name = string.lower(tostring(LocalPlayer.Name or 'unknown'))
		name = name:gsub('[^%w_%-]', '_')
		if name == '' then
			name = 'unknown'
		end
		return name
	end

	local function rootDir()
		return 'Ataraxia/' .. gameFolder
	end

	local function profileDir()
		return rootDir() .. '/profiles'
	end

	local function autoloadDir()
		return rootDir() .. '/autoload'
	end

	local function accountDir()
		return rootDir() .. '/accounts'
	end

	local function profilePath(name)
		return profileDir() .. '/' .. name .. '.json'
	end

	local function autoloadPath()
		return autoloadDir() .. '/' .. accountKey() .. '.txt'
	end

	local function accountPath()
		return accountDir() .. '/' .. accountKey() .. '.json'
	end

	local function ensureDirs()
		if type(makefolder) ~= 'function' then
			return
		end
		local function one(path)
			pcall(function()
				if type(isfolder) ~= 'function' or not isfolder(path) then
					makefolder(path)
				end
			end)
		end
		one('Ataraxia')
		one(rootDir())
		one(profileDir())
		one(autoloadDir())
		one(accountDir())
	end

	local function persistable(idx, obj)
		if type(idx) ~= 'string' or type(obj) ~= 'table' then
			return false
		end
		if skip[idx] or idx:sub(1, #SKIP_PREFIX) == SKIP_PREFIX then
			return false
		end
		return KINDS[obj.Type] == true and type(obj.SetValue) == 'function' and not obj.Destroyed
	end

	local function pack(v)
		local t = type(v)
		if t == 'boolean' or t == 'number' or t == 'string' then
			return v
		end
		if t == 'table' then
			local map = {}
			for k, on in pairs(v) do
				if type(k) == 'string' and on then
					map[k] = true
				end
			end
			return map
		end
		return nil
	end

	local function snapshot()
		local out = {}
		for idx, obj in pairs(Library.Options) do
			if persistable(idx, obj) then
				local v = pack(obj.Value)
				if v ~= nil then
					out[idx] = v
				end
			end
		end
		return out
	end

	local function writeJson(path, data)
		if type(writefile) ~= 'function' then
			return false
		end
		ensureDirs()
		local ok, encoded = pcall(function()
			return HttpService:JSONEncode(data)
		end)
		if not ok then
			return false
		end
		return pcall(writefile, path, encoded)
	end

	local function readJson(path)
		if type(isfile) ~= 'function' or type(readfile) ~= 'function' then
			return nil
		end
		local ok, exists = pcall(isfile, path)
		if not ok or not exists then
			return nil
		end
		local rok, body = pcall(readfile, path)
		if not rok then
			return nil
		end
		local dok, decoded = pcall(function()
			return HttpService:JSONDecode(body)
		end)
		if dok and type(decoded) == 'table' then
			return decoded
		end
		return nil
	end

	local function apply(data)
		if type(data) ~= 'table' then
			return 0
		end
		api.LastData = data
		-- A saved off wins over a sticky flag left from an older session.
		if data.SoloCombatResume == false then
			getgenv().SB2StickyResumeWanted = false
			getgenv().SB2ForceResumeWanted = false
			getgenv().SB2ResumeAssertUntil = 0
			getgenv().SB2ResumeGuardUntil = 0
			getgenv().SB2ResumeAfterConfig = false
		end
		suspended = true
		local notify = Library.Notify
		Library.Notify = function() end
		local n = 0
		for idx, v in pairs(data) do
			local obj = Library.Options[idx]
			if persistable(idx, obj) then
				local ok = pcall(function()
					obj:SetValue(v)
				end)
				if ok then
					n += 1
				end
			end
		end
		Library.Notify = notify
		suspended = false
		dirty = false
		return n
	end

	local function setStatus()
		if not statusLabel or not statusLabel.SetText then
			return
		end
		local mine = api.GetAutoload()
		local who = tostring(LocalPlayer.Name or '?')
		if mine and mine ~= '' then
			statusLabel:SetText(('This account (%s) autoloads  ·  %s'):format(who, mine))
		else
			statusLabel:SetText(('This account (%s)  ·  personal save, no named autoload'):format(who))
		end
	end

	function api.SetFolder(name)
		gameFolder = sanitize(name, 'default'):gsub(' ', '-'):lower()
		if gameFolder == '' then
			gameFolder = 'default'
		end
		ensureDirs()
	end

	function api.IgnoreIndexes(map)
		if type(map) ~= 'table' then
			return
		end
		for k, v in pairs(map) do
			if v then
				skip[tostring(k)] = true
			end
		end
	end

	function api.List()
		local names = {}
		local seen = {}
		if type(listfiles) == 'function' then
			local ok, files = pcall(listfiles, profileDir())
			if ok and type(files) == 'table' then
				for _, path in ipairs(files) do
					local base = tostring(path):gsub('\\', '/'):match('([^/]+)%.json$')
					if base and not seen[base] then
						seen[base] = true
						names[#names + 1] = base
					end
				end
			end
		end
		table.sort(names, function(a, b)
			return string.lower(a) < string.lower(b)
		end)
		return names
	end

	function api.GetAutoload()
		if type(isfile) ~= 'function' or type(readfile) ~= 'function' then
			return nil
		end
		local path = autoloadPath()
		local ok, exists = pcall(isfile, path)
		if not ok or not exists then
			return nil
		end
		local rok, body = pcall(readfile, path)
		if not rok then
			return nil
		end
		local name = sanitize(body, '')
		if name == '' or name == 'none' then
			return nil
		end
		local pok, has = pcall(isfile, profilePath(name))
		if pok and has then
			return name
		end
		return nil
	end

	function api.SetAutoload(name)
		ensureDirs()
		name = sanitize(name, '')
		if name == '' then
			if type(delfile) == 'function' then
				pcall(delfile, autoloadPath())
			end
			assignedName = nil
			setStatus()
			return true
		end
		if type(writefile) ~= 'function' then
			return false
		end
		local ok = pcall(writefile, autoloadPath(), name)
		if ok then
			assignedName = name
			setStatus()
		end
		return ok
	end

	function api.HasState()
		if type(isfile) ~= 'function' then
			return false
		end
		local a = api.GetAutoload()
		if a then
			return true
		end
		local ok, exists = pcall(isfile, accountPath())
		return ok and exists == true
	end

	function api.SaveProfile(name)
		name = sanitize(name, '')
		if name == '' then
			return false, 'Name a profile first'
		end
		ensureDirs()
		if not writeJson(profilePath(name), snapshot()) then
			return false, 'Write failed'
		end
		api.SetAutoload(name)
		assignedName = name
		dirty = false
		api.RefreshUI()
		return true
	end

	function api.LoadProfile(name)
		name = sanitize(name, '')
		if name == '' then
			return 0
		end
		local data = readJson(profilePath(name))
		if not data then
			return 0
		end
		local n = apply(data)
		api.SetAutoload(name)
		assignedName = name
		return n
	end

	function api.DeleteProfile(name)
		name = sanitize(name, '')
		if name == '' or type(delfile) ~= 'function' then
			return false
		end
		pcall(delfile, profilePath(name))
		if api.GetAutoload() == name then
			api.SetAutoload(nil)
		end
		if assignedName == name then
			assignedName = nil
		end
		api.RefreshUI()
		return true
	end

	function api.SaveAccount()
		ensureDirs()
		if writeJson(accountPath(), snapshot()) then
			dirty = false
			return true
		end
		return false
	end

	function api.SaveCurrent()
		local name = assignedName or api.GetAutoload()
		if name and name ~= '' then
			local ok = api.SaveProfile(name)
			return ok
		end
		return api.SaveAccount()
	end

	function api.ImportTable(data)
		return apply(data)
	end

	function api.ImportFile(path)
		local data = readJson(path)
		if not data then
			return 0
		end
		return apply(data)
	end

	function api.LoadAutoload()
		local name = api.GetAutoload()
		if name then
			assignedName = name
			local n = 0
			local data = readJson(profilePath(name))
			if data then
				n = apply(data)
			end
			setStatus()
			api.RefreshUI()
			return n
		end
		assignedName = nil
		local data = readJson(accountPath())
		local n = apply(data)
		setStatus()
		api.RefreshUI()
		return n
	end

	function api.Reset()
		if defaults then
			apply(defaults)
		end
		api.SaveCurrent()
	end

	function api.Queue()
		if suspended then
			return
		end
		dirty = true
		saveAt = os.clock() + SAVE_DELAY
	end

	function api.Tick()
		if dirty and not suspended and os.clock() >= saveAt then
			api.SaveCurrent()
		end
	end

	function api.Hook()
		defaults = defaults or snapshot()
		for idx, obj in pairs(Library.Options) do
			if persistable(idx, obj) and type(obj.OnChanged) == 'function' then
				obj:OnChanged(api.Queue)
			end
		end
	end

	function api.Finish()
		if dirty then
			api.SaveCurrent()
		end
		suspended = true
	end

	function api.RefreshUI()
		local list = Library.Options.ATA_ProfileList
		if list and type(list.SetValues) == 'function' then
			local names = api.List()
			if #names == 0 then
				names = { '(none saved)' }
			end
			pcall(function()
				list:SetValues(names)
				local cur = assignedName or api.GetAutoload() or names[1]
				if cur then
					list:SetValue(cur)
				end
			end)
		end
		setStatus()
	end

	function api.Build(box)
		if not box then
			return
		end
		statusLabel = box:AddLabel('Profiles  ·  this account')
		box:AddDropdown('ATA_ProfileList', {
			Text = 'Saved profiles',
			Values = { '(none saved)' },
			Default = '(none saved)',
			Tooltip = 'Shared list for this game. Every account can load these. Autoload is per-account.',
		})
		box:AddInput('ATA_ProfileName', {
			Text = 'Profile name',
			Default = '',
			Placeholder = 'e.g. frost farm',
			Tooltip = 'Name used when you Save. Lives in Ataraxia/<game>/profiles/.',
		})
		box:AddButton('Save profile (this account autoloads it)', function()
			local typed = Library.Options.ATA_ProfileName and tostring(Library.Options.ATA_ProfileName.Value or '') or ''
			local picked = Library.Options.ATA_ProfileList and tostring(Library.Options.ATA_ProfileList.Value or '') or ''
			local name = sanitize(typed, '')
			if name == '' and picked ~= '' and picked ~= '(none saved)' then
				name = sanitize(picked, '')
			end
			local ok, err = api.SaveProfile(name)
			if ok then
				Library:Notify(('Saved "%s"  ·  autoload for %s only'):format(name, LocalPlayer.Name))
			else
				Library:Notify(err or 'Save failed')
			end
		end)
		box:AddButton('Load selected (this account)', function()
			local picked = Library.Options.ATA_ProfileList and tostring(Library.Options.ATA_ProfileList.Value or '') or ''
			picked = sanitize(picked, '')
			if picked == '' or picked == '(none saved)' then
				Library:Notify('Pick a profile first')
				return
			end
			local n = api.LoadProfile(picked)
			Library:Notify(n > 0 and ('Loaded "%s" for %s'):format(picked, LocalPlayer.Name) or 'Load failed')
		end)
		box:AddButton('Set selected as my autoload', function()
			local picked = Library.Options.ATA_ProfileList and tostring(Library.Options.ATA_ProfileList.Value or '') or ''
			picked = sanitize(picked, '')
			if picked == '' or picked == '(none saved)' then
				Library:Notify('Pick a profile first')
				return
			end
			if api.SetAutoload(picked) then
				assignedName = picked
				Library:Notify(('Autoload "%s" for %s'):format(picked, LocalPlayer.Name))
			end
		end)
		box:AddButton('Clear my autoload', function()
			api.SetAutoload(nil)
			api.SaveAccount()
			Library:Notify(('Autoload cleared for %s'):format(LocalPlayer.Name))
		end)
		box:AddButton('Delete selected profile', function()
			local picked = Library.Options.ATA_ProfileList and tostring(Library.Options.ATA_ProfileList.Value or '') or ''
			picked = sanitize(picked, '')
			if picked == '' or picked == '(none saved)' then
				Library:Notify('Pick a profile first')
				return
			end
			api.DeleteProfile(picked)
			Library:Notify(('Deleted "%s"'):format(picked))
		end)
		box:AddLabel('Other accounts see the same list. They do not autoload until they Load / Set autoload.')
		api.RefreshUI()
	end

	return api
end)()

function Library:SetFolder(name)
	if self.Config then
		self.Config.SetFolder(name)
	end
end

function Library:CreateWindow(info)
	info = info or {}
	if type(info.Folder) == 'string' and info.Folder ~= '' then
		self:SetFolder(info.Folder)
	end
	-- Open at DefaultSize; MinSize is the resize floor (smaller than default so the grip can shrink).
	local defW = (self.DefaultSize and self.DefaultSize.X) or 880
	local defH = (self.DefaultSize and self.DefaultSize.Y) or 560
	local minW, minH = 560, 360
	if typeof(info.MinSize) == 'Vector2' then
		minW, minH = info.MinSize.X, info.MinSize.Y
	end
	local width = math.max(minW, (info.Size and info.Size.X.Offset) or defW)
	local height = math.max(minH, (info.Size and info.Size.Y.Offset) or defH)
	self.MinSize = Vector2.new(minW, minH)
	self.OriginalMinSize = self.MinSize
	self.DefaultSize = Vector2.new(defW, defH)

	if self.ScreenGui then
		pcall(function()
			self.ScreenGui:Destroy()
		end)
	end

	local gui = Instance.new('ScreenGui')
	gui.Name = 'SB2PlayerTools'
	gui:SetAttribute('SB2PlayerTools', true)
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 99998
	-- Global: nested controls (dropdown rows, open hit-target) must beat ancestor chrome.
	-- Sibling left Main/Hairline overlays above option rows so menus looked dead.
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Global
	if type(protectgui) == 'function' then
		pcall(protectgui, gui)
	end
	gui.Parent = LocalPlayer:WaitForChild('PlayerGui')
	self.ScreenGui = gui

	UserInputService.MouseIconEnabled = true
	pcall(function()
		UserInputService.OverrideMouseIconBehavior = Enum.OverrideMouseIconBehavior.ForceShow
	end)
	do
		local t = 0
		track(RunService.Heartbeat:Connect(function(dt)
			if not Library.Toggled then
				return
			end
			t += dt
			if t < 0.5 then
				return
			end
			t = 0
			UserInputService.MouseIconEnabled = true
			pcall(function()
				UserInputService.OverrideMouseIconBehavior = Enum.OverrideMouseIconBehavior.ForceShow
			end)
		end))
	end

	local toastHolder = Instance.new('Frame')
	toastHolder.BackgroundTransparency = 1
	toastHolder.Size = UDim2.fromOffset(320, 420)
	toastHolder.Position = UDim2.new(1, -336, 0, 16)
	toastHolder.ZIndex = 100
	toastHolder.Parent = gui
	Instance.new('UIListLayout', toastHolder).Padding = UDim.new(0, 6)
	self._toasts = toastHolder

	makeShowPill(gui, info.Title or 'Ataraxia')

	local main = Instance.new('Frame')
	main.Name = 'Main'
	main.Size = UDim2.fromOffset(width, height)
	main.Position = info.Position or UDim2.new(0.5, -math.floor(width / 2), 0.5, -math.floor(height / 2))
	main.BackgroundColor3 = C.bg0
	main.BorderSizePixel = 0
	main.ClipsDescendants = true
	main.Active = true
	main.Parent = gui
	corner(main, 6)
	hairline(main, 6)

	local header = Instance.new('Frame')
	header.Name = 'Header'
	header.Size = UDim2.new(1, 0, 0, 52)
	header.BackgroundColor3 = C.bg1
	header.BorderSizePixel = 0
	header.Active = true
	header.Parent = main
	local hLine = Instance.new('Frame')
	hLine.Size = UDim2.new(1, 0, 0, 1)
	hLine.Position = UDim2.new(0, 0, 1, -1)
	hLine.BackgroundColor3 = C.line
	hLine.BorderSizePixel = 0
	hLine.Parent = header

	mkLabel(header, tostring(info.Title or 'Ataraxia'), {
		font = Enum.Font.SourceSansBold,
		size = 22,
		size2 = UDim2.new(1, -120, 0, 24),
		pos = UDim2.fromOffset(16, 6),
	})
	do
		local sub = tostring(info.Footer or '')
		if sub == '' then
			sub = tostring(info.Title or 'Ataraxia') .. ' · custom chrome'
		end
		-- Never put a long quote in the chrome — tiny fonts drop glyphs.
		if #sub > 48 then
			sub = string.sub(sub, 1, 45) .. '…'
		end
		mkLabel(header, sub, {
			font = Enum.Font.SourceSans,
			size = 14,
			color = C.muted,
			size2 = UDim2.new(1, -120, 0, 16),
			pos = UDim2.fromOffset(16, 30),
		})
	end

	-- Per-script version (bottom-left): CreateWindow{ Version = "1.2.3" } or
	-- {Folder}/version.json ("version" field). Each helper shows its own stamp.
	do
		local verText = nil
		if type(info.Version) == 'string' and info.Version ~= '' then
			verText = info.Version
		else
			local folder = tostring(info.Folder or '')
			local path = nil
			if folder ~= '' and type(isfile) == 'function' and isfile(folder .. '/version.json') then
				path = folder .. '/version.json'
			end
			if path and type(readfile) == 'function' then
				local ok, body = pcall(readfile, path)
				if ok and type(body) == 'string' and body ~= '' then
					local okJ, data = pcall(function()
						return game:GetService('HttpService'):JSONDecode(body)
					end)
					if okJ and type(data) == 'table' and data.version ~= nil then
						verText = tostring(data.version)
					end
				end
			end
		end
		if verText and verText ~= '' then
			if not string.match(verText, '^[vV]') then
				verText = 'v' .. verText
			end
			local verLbl = mkLabel(main, verText, {
				font = Enum.Font.SourceSans,
				size = 12,
				color = C.muted,
				size2 = UDim2.fromOffset(160, 16),
				pos = UDim2.new(0, 10, 1, -20),
				z = 50,
			})
			verLbl.Name = 'ScriptVersion'
			self.VersionLabel = verLbl
			self.Version = verText
		end
	end

	local function chrome(text, x, danger, fn)
		local b = Instance.new('TextButton')
		b.Size = UDim2.fromOffset(28, 28)
		b.Position = UDim2.new(1, x, 0.5, -14)
		b.BackgroundColor3 = danger and Color3.fromRGB(48, 20, 20) or C.bg3
		b.Text = text
		b.TextColor3 = danger and C.danger or C.text
		b.Font = Enum.Font.SourceSansBold
		b.TextSize = 16
		b.AutoButtonColor = false
		b.BorderSizePixel = 0
		b.Parent = header
		corner(b, 4)
		hairline(b, 4)
		b.MouseButton1Click:Connect(fn)
	end
	chrome('—', -72, false, function()
		Library:Toggle()
	end)
	chrome('×', -36, true, function()
		Library:Toggle()
	end)

	local body = Instance.new('Frame')
	body.Name = 'Body'
	body.Size = UDim2.new(1, 0, 1, -52)
	body.Position = UDim2.fromOffset(0, 52)
	body.BackgroundColor3 = C.bg0
	body.BorderSizePixel = 0
	body.Parent = main

	local RAIL_W = 160
	local rail = Instance.new('Frame')
	rail.Name = 'Rail'
	rail.Size = UDim2.new(0, RAIL_W, 1, 0)
	rail.BackgroundColor3 = C.bg1
	rail.BorderSizePixel = 0
	rail.Parent = body
	local railEdge = Instance.new('Frame')
	railEdge.Size = UDim2.new(0, 1, 1, 0)
	railEdge.Position = UDim2.new(1, -1, 0, 0)
	railEdge.BackgroundColor3 = C.line
	railEdge.BorderSizePixel = 0
	railEdge.Parent = rail

	local railScroll = Instance.new('ScrollingFrame')
	railScroll.Name = 'RailScroll'
	railScroll.Size = UDim2.new(1, -8, 1, -12)
	railScroll.Position = UDim2.fromOffset(4, 8)
	railScroll.BackgroundTransparency = 1
	railScroll.BorderSizePixel = 0
	railScroll.ScrollBarThickness = 3
	railScroll.ScrollBarImageColor3 = C.bg3
	railScroll.CanvasSize = UDim2.fromOffset(0, 0)
	railScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	railScroll.Parent = rail
	local railLay = Instance.new('UIListLayout')
	railLay.Padding = UDim.new(0, 4)
	railLay.SortOrder = Enum.SortOrder.LayoutOrder
	railLay.Parent = railScroll

	local pages = Instance.new('Frame')
	pages.Name = 'Pages'
	pages.Size = UDim2.new(1, -RAIL_W, 1, 0)
	pages.Position = UDim2.fromOffset(RAIL_W, 0)
	pages.BackgroundColor3 = C.bg0
	pages.BorderSizePixel = 0
	pages.ClipsDescendants = true
	pages.Parent = body

	local dragging, dragStart, startPos = false, nil, nil
	local resizing, resizeStart, startSize = false, nil, nil
	self.MainFrame = main
	-- Resize floor (below default open size). Keep OriginalMinSize in sync.
	self.MinSize = self.MinSize or Vector2.new(560, 360)
	self.OriginalMinSize = self.MinSize

	header.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			if input.Position.X >= header.AbsolutePosition.X + header.AbsoluteSize.X - 90 then
				return
			end
			dragging = true
			resizing = false
			dragStart = input.Position
			startPos = main.Position
		end
	end)

	-- Bottom-right grip: drag to resize the window.
	local grip = Instance.new('TextButton')
	grip.Name = 'ResizeGrip'
	grip.Size = UDim2.fromOffset(22, 22)
	grip.Position = UDim2.new(1, -24, 1, -24)
	grip.BackgroundColor3 = C.bg3
	grip.BackgroundTransparency = 0.15
	grip.BorderSizePixel = 0
	grip.Text = ''
	grip.AutoButtonColor = false
	grip.ZIndex = 80
	grip.Parent = main
	corner(grip, 4)
	hairline(grip, 4)
	do
		local tip = Instance.new('TextLabel')
		tip.BackgroundTransparency = 1
		tip.Size = UDim2.fromScale(1, 1)
		tip.Text = '⋰'
		tip.TextColor3 = C.muted
		tip.Font = Enum.Font.SourceSansBold
		tip.TextSize = 16
		tip.ZIndex = 81
		tip.Parent = grip
	end
	grip.MouseEnter:Connect(function()
		grip.BackgroundTransparency = 0
		grip.BackgroundColor3 = C.bg2 or C.bg3
	end)
	grip.MouseLeave:Connect(function()
		if not resizing then
			grip.BackgroundTransparency = 0.15
			grip.BackgroundColor3 = C.bg3
		end
	end)
	grip.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		resizing = true
		dragging = false
		resizeStart = input.Position
		startSize = main.AbsoluteSize
	end)

	track(UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseMovement then
			return
		end
		if dragging then
			local d = input.Position - dragStart
			main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
		elseif resizing and resizeStart and startSize then
			local d = input.Position - resizeStart
			local min = Library.MinSize or Vector2.new(560, 360)
			local cam = workspace.CurrentCamera
			local view = cam and cam.ViewportSize or Vector2.new(1920, 1080)
			local newW = math.clamp(math.floor(startSize.X + d.X + 0.5), min.X, math.max(min.X, math.floor(view.X - 24)))
			local newH = math.clamp(math.floor(startSize.Y + d.Y + 0.5), min.Y, math.max(min.Y, math.floor(view.Y - 24)))
			main.Size = UDim2.fromOffset(newW, newH)
			local tab = Library.ActiveTab
			if tab and type(tab.RefreshSides) == 'function' then
				pcall(tab.RefreshSides, tab)
			end
		end
	end))
	track(UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = false
			resizing = false
			grip.BackgroundTransparency = 0.15
			grip.BackgroundColor3 = C.bg3
		end
	end))

	track(UserInputService.InputBegan:Connect(function(input, gp)
		if gp or Library.Unloaded then
			return
		end
		local kb = Library.ToggleKeybind
		if type(kb) == 'table' and kb.Value and input.KeyCode.Name == tostring(kb.Value) then
			Library:Toggle()
		end
	end))

	local Window = {}
	local tabOrder = 0
	function Window:AddTab(name, _icon)
		-- Same name = same tab. A second AddTab('Settings') must not spawn another rail button.
		if type(name) == 'string' and Library.Tabs[name] then
			return Library.Tabs[name]
		end
		tabOrder += 1
		local btn = Instance.new('TextButton')
		btn.Name = name
		btn.LayoutOrder = tabOrder
		btn.Size = UDim2.new(1, -4, 0, 32)
		btn.BackgroundColor3 = C.bg1
		btn.Text = name
		btn.TextColor3 = C.muted
		btn.Font = Enum.Font.SourceSans
		btn.TextSize = 15
		btn.TextXAlignment = Enum.TextXAlignment.Left
		btn.AutoButtonColor = false
		btn.BorderSizePixel = 0
		btn.Parent = railScroll
		corner(btn, 4)
		local bp = Instance.new('UIPadding')
		bp.PaddingLeft = UDim.new(0, 10)
		bp.Parent = btn

		local page = Instance.new('ScrollingFrame')
		page.Name = name
		page.Size = UDim2.fromScale(1, 1)
		page.BackgroundTransparency = 1
		page.BorderSizePixel = 0
		page.ScrollBarThickness = 6
		page.ScrollBarImageColor3 = C.bg3
		page.Visible = false
		page.CanvasSize = UDim2.fromOffset(0, 0)
		page.AutomaticCanvasSize = Enum.AutomaticSize.Y
		page.Parent = pages

		-- Offset columns (NOT scale) — scale width inside ScrollingFrame collapses to 0.
		local left = Instance.new('Frame')
		left.Name = 'Left'
		left.BackgroundTransparency = 1
		left.Position = UDim2.fromOffset(12, 12)
		left.Size = UDim2.fromOffset(340, 0)
		left.AutomaticSize = Enum.AutomaticSize.Y
		left.Parent = page
		local leftLay = Instance.new('UIListLayout')
		leftLay.Padding = UDim.new(0, 10)
		leftLay.SortOrder = Enum.SortOrder.LayoutOrder
		leftLay.Parent = left

		local right = Instance.new('Frame')
		right.Name = 'Right'
		right.BackgroundTransparency = 1
		right.Position = UDim2.fromOffset(364, 12)
		right.Size = UDim2.fromOffset(340, 0)
		right.AutomaticSize = Enum.AutomaticSize.Y
		right.Parent = page
		local rightLay = Instance.new('UIListLayout')
		rightLay.Padding = UDim.new(0, 10)
		rightLay.SortOrder = Enum.SortOrder.LayoutOrder
		rightLay.Parent = right

		local function layoutCols()
			local w = page.AbsoluteSize.X
			if w < 50 then
				return
			end
			local gap = 12
			local colW = math.max(260, math.floor((w - gap * 3) / 2))
			left.Size = UDim2.fromOffset(colW, 0)
			right.Size = UDim2.fromOffset(colW, 0)
			left.Position = UDim2.fromOffset(gap, gap)
			right.Position = UDim2.fromOffset(gap * 2 + colW, gap)
		end
		track(page:GetPropertyChangedSignal('AbsoluteSize'):Connect(layoutCols))
		task.defer(layoutCols)
		task.delay(0.15, layoutCols)
		task.delay(0.6, layoutCols)

		local tab = {
			Name = name,
			Button = btn,
			Container = page,
			Canvas = page,
		}

		function tab:Show()
			for _, t in pairs(Library.Tabs) do
				t.Container.Visible = false
				t.Button.BackgroundColor3 = C.bg1
				t.Button.TextColor3 = C.muted
				t.Button.Font = Enum.Font.SourceSans
			end
			page.Visible = true
			btn.BackgroundColor3 = C.bg3
			btn.TextColor3 = C.text
			btn.Font = Enum.Font.SourceSansBold
			Library.ActiveTab = tab
			layoutCols()
		end

		function tab:RefreshSides()
			layoutCols()
		end

		function tab:AddLeftGroupbox(title)
			return makeGroupbox(left, title)
		end
		function tab:AddRightGroupbox(title)
			return makeGroupbox(right, title)
		end

		btn.MouseButton1Click:Connect(function()
			tab:Show()
		end)

		Library.Tabs[name] = tab
		if not Library.ActiveTab then
			tab:Show()
		end
		return tab
	end

	self.Toggled = true
	self.Open = true
	-- Built-in anti-AFK for every consumer of this library (opt out: CreateWindow{ AntiAfk = false }).
	if info.AntiAfk ~= false then
		pcall(AntiAfk.ensure)
	end
	if info.Invisicam ~= false then
		pcall(Occlusion.ensure)
	end
	if info.MaxZoom ~= false then
		pcall(MaxZoom.ensure)
	end
	if info.HideGameplayPaused ~= false then
		pcall(NoPause.ensure)
	end
	if info.Fullbright ~= false then
		pcall(Fullbright.ensure)
	end
	-- Default Settings tab (Script + Profiles + theme). Opt out: SettingsTab = false.
	if info.SettingsTab ~= false then
		pcall(function()
			Library:BuildSettingsTab(Window, info)
		end)
	end
	track(RunService.Heartbeat:Connect(function()
		if Library.Config then
			pcall(Library.Config.Tick)
		end
		pcall(Occlusion.tick)
		pcall(MaxZoom.tick)
		pcall(Fullbright.tick)
	end))
	return Window
end

getgenv().AtaraxiaLibraryApi = Library

return Library
]=]
for name, body in pairs(FILES) do
	local ok, err = pcall(writefile, 'PlayerTools/' .. name, body)
	if not ok then
		warn('[AutoBetween] could not write ' .. name .. ': ' .. tostring(err))
	end
end
if not (isfile and isfile('PlayerTools/whitelist.txt')) then
	pcall(writefile, 'PlayerTools/whitelist.txt', '# one name per line: your own alts AutoBetween may run alongside\n')
end
local fn, err = (loadstring or load)(FILES['AutoBetween.lua'], 'AutoBetween.lua')
if not fn then
	error('[AutoBetween] failed to compile: ' .. tostring(err))
end
return fn()
