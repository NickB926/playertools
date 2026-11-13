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

local BUILD = 'auto-between-v22'
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
--   Saurus (Elite, wave 23): as soon as he has spawned.
--   Elite boss waves (ELITE_BOSS_WAVES below): as soon as the wave's boss(es) have spawned.
--   Vaelith, the Riftborn (any wave, also after the Rift wave's own reset): as soon as he has spawned.
--   Rubricatus: once he has finished spawning (stopped descending), plus a delay (2s).
-- Sent once per wave on the command bar's own remote, so the bar is never opened.
-- To add more waves later: add another branch in step() that calls fire() when its moment comes.
---------------------------------------------------------------------------
local RESET_MOBS_USER_ID = 475975042 -- Pyrixl
if LocalPlayer.UserId == RESET_MOBS_USER_ID then
	local okReset, errReset = pcall(function()
		local RESET_COMMAND = 'ResetMobs;@all'
		local LOG_PATH = 'PlayerTools/_resetmobs_log_' .. ACCT .. '.txt'
		-- keep the log from growing forever: past 300 KB, keep only the newest 100 KB
		pcall(function()
			if isfile(LOG_PATH) then
				local text = readfile(LOG_PATH)
				if #text > 300000 then
					local tail = string.sub(text, #text - 100000)
					writefile(LOG_PATH, string.sub(tail, (string.find(tail, '\n', 1, true) or 0) + 1))
				end
			end
		end)
		if settings.resetMobs == nil then
			-- one switch now; stays off only if every old per-wave switch had been turned off
			local anyOld, anyOn = false, false
			for _, key in ipairs({ 'resetThunder', 'resetRub', 'resetRift', 'resetBob', 'resetWisp', 'resetSaurus', 'resetEliteBosses' }) do
				if settings[key] ~= nil then
					anyOld = true
					anyOn = anyOn or settings[key] == true
				end
			end
			settings.resetMobs = (not anyOld) or anyOn
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
		ModBox:AddToggle('ABResetMobs', {
			Text = 'Auto ResetMobs',
			Default = settings.resetMobs == true,
			Tooltip = 'Sends ' .. RESET_COMMAND .. ' by itself on: the thunder, Rift, Bob and Wisp waves, Saurus (Elite 23), the Elite boss waves (38-98), Vaelith and Rubricatus.',
		}):OnChanged(function(v)
			settings.resetMobs = v == true
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
		local bossSeenAt = nil -- first boss seen on an Elite boss wave
		-- Vaelith has his own once-per-wave guard: he shows up after the Rift wave's reset was already sent.
		local vaelithFiredWave = G.SB2AutoResetFiredVaelith
		if vaelithFiredWave ~= wave then
			vaelithFiredWave = nil
			G.SB2AutoResetFiredVaelith = nil
		end
		-- Elite boss waves: wave -> the bosses to reset (name part, lower case; "^" = name starts with;
		-- and how many of them). Other mobs on the wave are ignored. Every time one of them newly
		-- appears the command is sent (again), so bosses that spawn late get their own reset; bosses that
		-- appear within BOSS_BATCH seconds of each other share one. "delay" = extra seconds before sending.
		local ELITE_BOSS_WAVES = {
			[38] = { { 'atheon', 1 } },
			[42] = { { 'tworz', 1 } },
			[44] = { { 'eternal blossom knight', 1 } },
			[48] = { { 'azeis', 1 } },
			[50] = { { 'aegor', 1 } },
			[54] = { { 'the waiter', 1 } }, -- the boss here is The Waiter (Rapapouillie is an ordinary mob, also on 60/62)
			[57] = { { 'meatball', 1 } },
			[61] = { { 'ramseis', 1 } },
			[66] = { { 'kraken', 1 } },
			[69] = { { 'leviathan', 1 } },
			[73] = { { 'aeganatos', 1 } },
			[75] = { { 'nythrane', 1 }, delay = 2 },
			[79] = { { 'magnor', 1 } },
			[82] = { { 'bulswick', 1 } },
			[83] = { { 'egnor', 1 } },
			[84] = { { 'cucurbita', 1 } },
			[85] = { { 'headless horseman', 1 } },
			[86] = { { 'wendigo', 1 } },
			[87] = { { 'dracula', 1 } },
			[89] = { { 'baal', 1 }, { 'magnor', 1 } },
			[90] = { { 'cucurbita', 1 }, { 'grim, the overseer', 1 } },
			[91] = { { 'egnor', 1 }, { '^ka, the', 1 }, { '^da, the', 1 }, { '^ra, the', 1 }, { '^za, the', 1 }, { '^wa, the', 1 } }, -- Egnor + the F11 minis
			[92] = { { 'saurus, the', 1 }, { 'headless horseman', 1 } },
			[93] = { { 'wendigo', 1 }, { 'radioactive', 1 }, { 'warlord', 1 } },
			[94] = { { 'uriotol', 1 }, { 'duality reaper', 1 } },
			[95] = { { 'dracula', 1 }, { 'rekindled', 2 } },
			[96] = { { 'atheon', 3 } },
			[97] = { { 'corrupted atheon', 1 } },
			[98] = { { 'dracula', 1 }, { 'headless horseman', 1 } },
		}
		local BOSS_BATCH = 1
		local bossNewAt = nil -- when a not-yet-reset boss was first seen
		local bossMissNoted = false
		-- how many of each boss on this wave already had a reset sent (kept across a reload)
		local bossCovered = {}
		-- The boss mobs themselves that already had a reset sent. Counting by instance, not by how
		-- many are alive at once: on wave 96 the 3rd Atheon showed up after one of the first two had
		-- died, the alive count never got past 2, and it was never reset.
		local bossInst = setmetatable({}, { __mode = 'k' })
		if type(G.SB2AutoResetBossCovered) == 'table' and G.SB2AutoResetBossCovered.wave == wave then
			bossCovered = G.SB2AutoResetBossCovered.counts or {}
			bossInst = G.SB2AutoResetBossCovered.inst or bossInst
		else
			G.SB2AutoResetBossCovered = nil
		end
		local bobNotes = 0

		-- Every wave's mobs go to the log when the wave ends, so "what was wave N?" has an answer.
		local seenNames, seenOrder, seenEnv = {}, {}, nil
		local function onWaveChanged()
			local now = workspace:GetAttribute('Wave')
			if now == wave then
				return
			end
			if wave ~= nil and #seenOrder > 0 then
				resetLog(('summary: wave %s (%s%s, lasted %.0fs) had: %s'):format(
					tostring(wave),
					tostring(workspace:GetAttribute('WaveDefenseMode') or '?'),
					seenEnv and (', ' .. seenEnv .. ' wave') or '',
					os.clock() - waveAt,
					table.concat(seenOrder, ' + ')
				))
			end
			seenNames, seenOrder, seenEnv = {}, {}, nil
			wave = now
			waveAt = os.clock()
			strikeAt = nil
			vaelithFiredWave = nil
			G.SB2AutoResetFiredVaelith = nil
			bossSeenAt = nil
			bossNewAt = nil
			bossCovered = {}
			bossInst = setmetatable({}, { __mode = 'k' })
			G.SB2AutoResetBossCovered = nil
			bossMissNoted = false
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
		local function waveMobNames()
			local mobs = workspace:FindFirstChild('Mobs')
			local names = {}
			if mobs then
				for _, mob in ipairs(mobs:GetChildren()) do
					if mob.Name ~= 'Reward Chest' and mob:GetAttribute('Died') ~= true then
						names[#names + 1] = mob.Name
					end
				end
			end
			return names
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

		-- "Saurus, the All-Seeing" (not Reptasaurus), alive.
		local function findSaurus()
			local mobs = workspace:FindFirstChild('Mobs')
			if not mobs then
				return nil
			end
			for _, mob in ipairs(mobs:GetChildren()) do
				if string.sub(string.lower(tostring(mob.Name)), 1, 6) == 'saurus' and mob:GetAttribute('Died') ~= true then
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

		local function findVaelith()
			local mobs = workspace:FindFirstChild('Mobs')
			if not mobs then
				return nil
			end
			for _, mob in ipairs(mobs:GetChildren()) do
				if string.sub(string.lower(tostring(mob.Name)), 1, 7) == 'vaelith' and mob:GetAttribute('Died') ~= true then
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
			if wave ~= nil then
				for _, name in ipairs(waveMobNames()) do
					if not seenNames[name] and #seenOrder < 30 then
						seenNames[name] = true
						seenOrder[#seenOrder + 1] = name
					end
				end
				local env = workspace:GetAttribute('WaveDefenseEnvironment')
				if env == 'Tempest' or env == 'Rift' or env == 'Bob' or env == 'Wisp' then
					seenEnv = env
				end
			end
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
			-- Elite boss waves. (Above the "already sent this wave" stop: late bosses get their own send.)
			local bossSpec = ELITE_BOSS_WAVES[wave]
			local envNow = workspace:GetAttribute('WaveDefenseEnvironment')
			local specialEnv = envNow == 'Tempest' or envNow == 'Rift' or envNow == 'Bob' or envNow == 'Wisp'
			if bossSpec and not specialEnv and workspace:GetAttribute('WaveDefenseMode') == 'Elite' then
				local names = waveMobNames()
				local aliveMobs = {}
				do
					local mobsF = workspace:FindFirstChild('Mobs')
					for _, mob in ipairs(mobsF and mobsF:GetChildren() or {}) do
						if mob.Name ~= 'Reward Chest' and mob:GetAttribute('Died') ~= true then
							aliveMobs[#aliveMobs + 1] = mob
						end
					end
				end
				local counts, fresh, freshInst, anyIn = {}, {}, {}, false
				for i, need in ipairs(bossSpec) do
					local pat, prefix = need[1], false
					if string.sub(pat, 1, 1) == '^' then
						pat, prefix = string.sub(pat, 2), true
					end
					local covered = bossCovered[i] or 0
					local n = covered
					for _, mob in ipairs(aliveMobs) do
						local low = string.lower(mob.Name)
						local hit
						if prefix then
							hit = string.sub(low, 1, #pat) == pat
						else
							hit = string.find(low, pat, 1, true) ~= nil
						end
						if hit then
							anyIn = true
							if not bossInst[mob] and n < need[2] then
								n += 1
								fresh[#fresh + 1] = mob.Name
								freshInst[#freshInst + 1] = mob
							end
						end
					end
					counts[i] = n
				end
				if settings.resetMobs ~= true then
					setResetStatus('boss wave — off')
				elseif #fresh == 0 then
					bossNewAt = nil
					if next(bossCovered) ~= nil then
						setResetStatus(('sent on wave %s — watching for more bosses'):format(tostring(wave)))
					else
						setResetStatus('boss wave — waiting for the boss')
						if not anyIn and not bossMissNoted and #names > 0 and now - waveAt >= 25 then
							bossMissNoted = true
							resetLog('boss wave: expected boss not seen after 25s; alive: ' .. table.concat(names, ' + '))
						end
					end
				else
					bossSeenAt = bossSeenAt or now
					bossNewAt = bossNewAt or now
					-- single-boss waves send at once; with several bosses wait a moment so close spawns share a send
					local wait = (tonumber(bossSpec.delay) or 0) + ((#bossSpec > 1 or bossSpec[1][2] > 1) and BOSS_BATCH or 0)
					if now - bossNewAt < wait then
						setResetStatus(('boss wave — sending in %.1fs'):format(wait - (now - bossNewAt)))
					else
						for i, n in ipairs(counts) do
							bossCovered[i] = math.max(bossCovered[i] or 0, n)
						end
						for _, mob in ipairs(freshInst) do
							bossInst[mob] = true
						end
						G.SB2AutoResetBossCovered = { wave = wave, counts = bossCovered, inst = bossInst }
						bossNewAt = nil
						fire('Elite boss wave', ('%.1fs into the wave, for: %s'):format(now - waveAt, table.concat(fresh, ' + ')))
					end
				end
				return
			end

			-- Vaelith: checked before the "already sent this wave" stop, on purpose.
			if settings.resetMobs == true and vaelithFiredWave ~= wave and findVaelith() then
				vaelithFiredWave = wave
				G.SB2AutoResetFiredVaelith = wave
				fire('Vaelith', ('%.1fs into the wave'):format(now - waveAt))
				return
			end
			if firedWave == wave then
				setResetStatus(('sent on wave %s'):format(tostring(wave)))
				return
			end

			-- Saurus: Elite, wave 23.
			if wave == 23 and workspace:GetAttribute('WaveDefenseMode') == 'Elite' then
				if settings.resetMobs ~= true then
					setResetStatus('Saurus wave — off')
				elseif not findSaurus() then
					setResetStatus('Saurus wave — waiting for Saurus')
				else
					fire('Saurus', ('%.1fs into the wave'):format(now - waveAt))
				end
				return
			end


			-- Thunder wave.
			if workspace:GetAttribute('WaveDefenseEnvironment') == 'Tempest' then
				if settings.resetMobs ~= true then
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
				if settings.resetMobs ~= true then
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
				if settings.resetMobs ~= true then
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
				if settings.resetMobs ~= true then
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
				if settings.resetMobs ~= true then
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
