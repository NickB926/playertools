--[[
	Atheon arena skills via Shadow Step (80 studs / 0.25s CD, MoveDirection else LookVector):
	- Nuke: dash out of the slam cylinder, then back in after impact.
	- FireDash: when he dashes away, dash toward his landing spot.
]]
getgenv().SB2AtheonNukeDashBuild = 'atheon-shadow-v5r'

return function(env)
	env = env or {}
	local CombatBox = env.CombatBox
	local RunService = env.RunService or game:GetService('RunService')
	local LocalPlayer = env.LocalPlayer or game:GetService('Players').LocalPlayer
	local Toggles = env.Toggles or Toggles
	local isToggleOn = env.isToggleOn
	local isLocalAlive = env.isLocalAlive
	local getMyCharacterModel = env.getMyCharacterModel
	local CollectionService = game:GetService('CollectionService')
	local ReplicatedStorage = game:GetService('ReplicatedStorage')

	if type(isToggleOn) ~= 'function' then
		isToggleOn = function(name)
			local toggle = type(Toggles) == 'table' and Toggles[name]
			if type(toggle) == 'table' then
				return toggle.Value == true
			end
			return getgenv()['SB2' .. tostring(name) .. 'On'] == true
		end
	end
	if type(isLocalAlive) ~= 'function' then
		isLocalAlive = function()
			local char = LocalPlayer.Character
			local hum = char and char:FindFirstChildOfClass('Humanoid')
			return hum ~= nil and hum.Health > 0
		end
	end
	if type(getMyCharacterModel) ~= 'function' then
		getMyCharacterModel = function()
			return LocalPlayer.Character
		end
	end

	local SKILL_NAME = 'Shadow Step'
	local FALLBACK_SKILL = 'Spirit Dash'
	local SCAN_GAP = 0.03
	local HUGE_SPAN = 70
	local GROW_SPAN = 50
	local RETURN_CLEAR = 1.2
	local RETURN_MAX = 5.5
	local AFTER_CD = 2.2
	local DASH_LOCK = 0.55
	local CHASE_NEAR = 14
	local CHASE_CD = 0.35
	local CHASE_BUSY = 0.55
	local BOSS_DASH_MIN = 22
	local NUKE_NEAR = 110
	local NUKE_SAFE = 150
	local NUKE_AWAY_DASHES = 2
	local NUKE_DEFAULT_LIFE = 3
	local NUKE_LAND_PAD = 0.85
	local STEP_DIST = 80
	local DASH_MIN = 70
	local CLOSE_OK = 3
	local WALK_STOP = 3
	local MAX_APPROACH_DASH = 4

	local state = {
		phase = 'idle',
		returnPos = nil,
		awayDir = nil,
		center = nil,
		sawAt = 0,
		dashAt = 0,
		backAt = 0,
		busyUntil = 0,
		lastScan = 0,
		lastFailAt = 0,
		lastChaseAt = 0,
		lastChaseKey = nil,
		lastBossPos = nil,
		lastBossAt = 0,
		casting = false,
		usedHook = false,
		hadTelegraph = false,
		nukeUntil = 0,
		handledNukeAt = 0,
		awayHops = 0,
		seenBoss = false,
		wentHome = false,
		liveBoss = false,
		lastApproachAt = 0,
		nukeInterrupt = false,
		holdIdleUntil = 0,
		missingBossSince = 0,
		arenaMid = nil,
		samples = {},
		seenFlames = {},
	}

	local function normKey(text)
		return (string.gsub(string.lower(tostring(text or '')), '[%p%s]+', ''))
	end

	local function isAtheonName(text)
		local key = normKey(text)
		if key == '' then
			return false
		end
		if string.find(key, 'atheon', 1, true) then
			return true
		end
		-- WD bar title is exactly "Kindled". "Nautilus Arcwave [Kindled]" must not match.
		return key == 'kindled'
	end

	local function skillSelfIsAtheon(self)
		if type(self) ~= 'table' then
			return false
		end
		local ok, name = pcall(function()
			local inst = self.Base and self.Base.Instance
			return inst and inst.Name
		end)
		return ok and isAtheonName(name)
	end


	local function mobLooksAtheon(mob)
		if not mob or not mob.Parent then
			return false
		end
		if isAtheonName(mob.Name) then
			return true
		end
		local plate = mob:FindFirstChild('Nameplate')
		local label = plate and plate:FindFirstChildWhichIsA('TextLabel', true)
		return label ~= nil and isAtheonName(label.Text)
	end

	local function mobAlive(mob)
		if typeof(mob) ~= 'Instance' or not mob.Parent then
			return false
		end
		local hum = mob:FindFirstChildOfClass('Humanoid')
		if hum and hum.Health <= 0 then
			return false
		end
		local ent = mob:FindFirstChild('Entity')
		if ent then
			local hp = ent:FindFirstChild('Health') or ent:FindFirstChild('HP')
			if hp and typeof(hp.Value) == 'number' and hp.Value <= 0 then
				return false
			end
		end
		return true
	end

	local function findAtheon()
		local folder = workspace:FindFirstChild('Mobs')
		if folder then
			for _, mob in ipairs(folder:GetChildren()) do
				if mobLooksAtheon(mob) and mobAlive(mob) then
					return mob
				end
			end
		end
		return nil
	end

	-- Strict caster check. Only falls back to "is Atheon near the skill" when the
	-- skill object has no readable caster. Other mobs' slams / dashes are ignored.
	local function skillFromAtheon(self)
		if skillSelfIsAtheon(self) then
			return true
		end
		local hasCaster = false
		pcall(function()
			local inst = self.Base and self.Base.Instance
			hasCaster = typeof(inst) == 'Instance'
		end)
		if hasCaster then
			return false
		end
		local mobs = workspace:FindFirstChild('Mobs')
		local atheon
		if mobs then
			for _, mob in ipairs(mobs:GetChildren()) do
				if mobLooksAtheon(mob) then
					atheon = mob
					break
				end
			end
		end
		return atheon ~= nil
	end

	local function mobRootPos(mob)
		if typeof(mob) ~= 'Instance' then
			return nil
		end
		local hrp = mob:FindFirstChild('HumanoidRootPart')
		if hrp and hrp:IsA('BasePart') then
			return hrp.Position
		end
		local ok, pivot = pcall(function()
			return mob:GetPivot()
		end)
		if ok and typeof(pivot) == 'CFrame' then
			return pivot.Position
		end
		return nil
	end

	local function playerParts()
		local model = getMyCharacterModel() or LocalPlayer.Character
		if not model then
			return nil, nil, nil
		end
		local hrp = model:FindFirstChild('HumanoidRootPart')
		local hum = model:FindFirstChildOfClass('Humanoid')
		if not hrp or not hrp:IsA('BasePart') then
			return nil, nil, nil
		end
		return model, hrp, hum
	end

	local function creditRequirementVisible()
		local ok, visible = pcall(function()
			local pg = LocalPlayer:FindFirstChild('PlayerGui')
			local hud = pg
				and pg:FindFirstChild('CardinalUI')
				and pg.CardinalUI:FindFirstChild('PlayerUI')
				and pg.CardinalUI.PlayerUI:FindFirstChild('HUD')
			local frame = hud and hud:FindFirstChild('CreditFrame')
			if not frame or frame.Visible ~= true then
				return false
			end
			local name = frame:FindFirstChild('MobName')
			local dmg = frame:FindFirstChild('CurrentDamage')
			local blob = string.lower(tostring(name and name.Text) .. ' ' .. tostring(dmg and dmg.Text))
			if string.find(blob, 'atheon', 1, true) then
				return true
			end
			return string.find(blob, '%d') ~= nil
		end)
		return ok and visible == true
	end

	local function trackingAtheon()
		local ok, mob = pcall(function()
			local v = LocalPlayer:FindFirstChild('TrackingMob')
			return v and v.Value
		end)
		return ok and typeof(mob) == 'Instance' and mobLooksAtheon(mob)
	end

	-- Credit / TrackingMob stay on for the whole fight. They are not distance.
	-- Only treat credit as "close enough" when Atheon himself is already in melee.
	local function inCreditRange(hrp, atheon)
		if typeof(hrp) == 'Instance' then
			local boss = mobRootPos(atheon)
			if typeof(boss) == 'Vector3' then
				local toBoss = Vector3.new(hrp.Position.X - boss.X, 0, hrp.Position.Z - boss.Z).Magnitude
				if toBoss > CLOSE_OK then
					return false
				end
			end
		end
		return creditRequirementVisible() or trackingAtheon()
	end

	local function ownsSkill(skillName)
		local profile = ReplicatedStorage:FindFirstChild('Profiles')
		profile = profile and profile:FindFirstChild(LocalPlayer.Name)
		local skills = profile and profile:FindFirstChild('Skills')
		return skills ~= nil and skills:FindFirstChild(skillName) ~= nil
	end

	local function pickSkill()
		if ownsSkill(SKILL_NAME) then
			return SKILL_NAME
		end
		if ownsSkill(FALLBACK_SKILL) then
			return FALLBACK_SKILL
		end
		return SKILL_NAME
	end

	local function faceMove(hrp, hum, dir)
		local flat = Vector3.new(dir.X, 0, dir.Z)
		if flat.Magnitude < 0.05 then
			flat = Vector3.new(0, 0, -1)
		else
			flat = flat.Unit
		end
		pcall(function()
			hrp.Anchored = false
		end)
		pcall(function()
			hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + flat)
		end)
		if hum then
			pcall(function()
				hum:Move(flat, false)
			end)
		end
		return flat
	end

	local function resolveSkills()
		local svc = getgenv().SB2RequiredServices
		if type(svc) == 'table' and type(svc.Skills) == 'table' then
			return svc.Skills
		end
		local cached = getgenv().SB2SkillsServiceCache
		if type(cached) == 'table' and type(cached.UseSkill) == 'function' then
			return cached
		end
		return nil
	end

	local function markUsed(skillName)
		if type(getgenv().SB2SkillCdUntil) ~= 'table' then
			getgenv().SB2SkillCdUntil = {}
		end
		getgenv().SB2SkillCdUntil[skillName] = time() + 0.3
		getgenv().SB2LastAtheonDash = { skill = skillName, at = os.clock() }
	end

	local function findShadowStepFx()
		local cached = getgenv().SB2ShadowStepFx
		if type(cached) == 'table' and type(cached.new) == 'function' then
			return cached
		end
		if type(getgc) ~= 'function' then
			return nil
		end
		for _, v in ipairs(getgc(true)) do
			if type(v) == 'table'
				and rawget(v, 'Distance') == 80
				and rawget(v, 'Steps') == 3
				and type(rawget(v, 'TeleportSequence')) == 'function'
				and type(rawget(v, 'new')) == 'function'
			then
				getgenv().SB2ShadowStepFx = v
				return v
			end
		end
		return nil
	end

	local function castDash(skillName, hrp)
		local before = hrp and hrp.Position
		local skills = resolveSkills()
		if skills and type(skills.UseSkill) == 'function' then
			pcall(function()
				skills:UseSkill(skillName)
			end)
			pcall(skills.UseSkill, skillName)
		end
		local ev = ReplicatedStorage:FindFirstChild('Event')
		if ev then
			pcall(function()
				ev:FireServer('Skills', { 'UseSkill', skillName })
			end)
		end
		-- The real skill teleports after a server round-trip plus its own 0.15s sequence,
		-- so give it time before deciding it failed. Checking instantly made the backup
		-- below fire on top of the real cast: two teleports per hop, ignoring the cooldown.
		local function movedSince()
			if typeof(before) ~= 'Vector3' or not hrp or not hrp.Parent then
				return false
			end
			local delta = Vector3.new(hrp.Position.X - before.X, 0, hrp.Position.Z - before.Z)
			return delta.Magnitude >= 18
		end
		local moved = movedSince()
		local waitUntil = os.clock() + 0.4
		while not moved and os.clock() < waitUntil do
			task.wait()
			moved = movedSince()
		end
		if not moved and skillName == SKILL_NAME then
			local fx = findShadowStepFx()
			local model = hrp and hrp.Parent
			if fx and model then
				pcall(fx.new, model)
				moved = true
			end
		end
		markUsed(skillName)
		return moved or skills ~= nil or ev ~= nil
	end

	local function partIsLane(part)
		local sx, sy, sz = part.Size.X, part.Size.Y, part.Size.Z
		local wide = math.max(sx, sz)
		local thin = math.min(sx, sz)
		return thin > 1 and (wide / thin) > 2.4 and sy < 12
	end

	local function partLooksNuke(part)
		if not part or not part:IsA('BasePart') or not part.Parent then
			return false
		end
		if part.Transparency >= 0.995 then
			return false
		end
		local n = string.lower(tostring(part.Name))
		if n == 'humanoidrootpart' or n == 'torso' or n == 'head' then
			return false
		end
		local named = n == 'circle'
			or n == 'effecthitbox'
			or string.find(n, 'fillin', 1, true)
			or string.find(n, 'enemyskillhitbox', 1, true)
			or string.find(n, 'nuke', 1, true)
			or string.find(n, 'smash', 1, true)
			or string.find(n, 'slam', 1, true)
			or string.find(n, 'shockwave', 1, true)
			or string.find(n, 'lavagyzer', 1, true)
			or string.find(n, 'lavasmash', 1, true)
		local tagged = false
		pcall(function()
			tagged = CollectionService:HasTag(part, 'EnemySkillHitbox')
				or CollectionService:HasTag(part, 'FillIn')
		end)
		if not named and not tagged then
			return false
		end
		if partIsLane(part) then
			return false
		end
		return true
	end

	local function partGrowing(part)
		local s = part.Size
		local mx = math.max(s.X, s.Y, s.Z)
		local vol = s.X * s.Y * s.Z
		local now = os.clock()
		local prev = state.samples[part]
		state.samples[part] = { t = now, mx = mx, vol = vol }
		if not prev then
			return false, mx
		end
		local dt = now - (prev.t or now)
		if dt <= 0 or dt > 1.6 then
			return false, mx
		end
		if vol >= (prev.vol or 0) * 1.18 and vol > 40 and mx >= 4 then
			return true, mx
		end
		if mx >= (prev.mx or 0) + 2.5 and mx >= 8 then
			return true, mx
		end
		return false, mx
	end

	local function considerPart(part, origin, into, opts)
		opts = opts or {}
		if not partLooksNuke(part) then
			return
		end
		local wide = math.max(part.Size.X, part.Size.Z)
		local growing, mx = partGrowing(part)
		if not growing and wide < HUGE_SPAN then
			return
		end
		if growing and wide < GROW_SPAN and mx < GROW_SPAN then
			return
		end
		local dx = part.Position.X - origin.X
		local dz = part.Position.Z - origin.Z
		local rad = math.max(8, wide * 0.5)
		local near = opts.watch and 220 or (rad + 12)
		if (dx * dx + dz * dz) > (near * near) then
			return
		end
		into[#into + 1] = {
			part = part,
			center = part.Position,
			radius = rad,
			growing = growing,
			wide = wide,
		}
	end

	local function collectNukes(origin, opts)
		opts = opts or {}
		local hits = {}
		for _, child in ipairs(workspace:GetChildren()) do
			local n = string.lower(tostring(child.Name))
			if n == 'circle' or n == 'effecthitbox' then
				if child:IsA('BasePart') then
					considerPart(child, origin, hits, opts)
				end
			elseif n == 'effects' or n == 'spelltelegraphs' then
				local count = 0
				for _, d in ipairs(child:GetDescendants()) do
					count += 1
					if count > 80 then
						break
					end
					if d:IsA('BasePart') then
						considerPart(d, origin, hits, opts)
					end
				end
			end
		end
		pcall(function()
			for _, tag in ipairs({ 'EnemySkillHitbox', 'FillIn' }) do
				local tagged = CollectionService:GetTagged(tag)
				for i = 1, math.min(#tagged, 40) do
					local inst = tagged[i]
					if inst:IsA('BasePart') then
						considerPart(inst, origin, hits, opts)
					end
				end
			end
		end)
		return hits
	end

	local function bestNuke(origin, opts)
		local hits = collectNukes(origin, opts)
		local best = nil
		for i = 1, #hits do
			local hit = hits[i]
			if not best or hit.wide > best.wide then
				best = hit
			end
		end
		return best
	end

	local function setBusy(untilT)
		state.busyUntil = untilT
		getgenv().SB2AtheonNukeDashBusyUntil = untilT
	end

	local function notifyOnce(msg)
		local now = os.clock()
		if now - (state.lastFailAt or 0) < 6 then
			return
		end
		state.lastFailAt = now
		local Library = rawget(getgenv(), 'Library')
		if type(Library) == 'table' and type(Library.Notify) == 'function' then
			pcall(Library.Notify, msg, 4)
		else
			warn('[AtheonNukeDash] ' .. msg)
		end
	end

	-- Wave defense belongs to AutoFloorDodge (it teleports 165 studs out of the nuke there).
	-- Shadow Step only acts outside wave defense (manual grinding), or in wave defense when
	-- the auto dodge is off. The skill hooks still record the nuke timing everywhere.
	local function autoDodgeOwnsAtheon()
		return workspace:FindFirstChild('WaveDefenseStuff') ~= nil and getgenv().SB2AutoFloorDodgeOn == true
	end

	-- The skill hooks fire on every Atheon nuke whether or not the feature is on,
	-- so every path that moves the player checks the toggle itself.
	local function shadowStepEnabled()
		local toggle = type(Toggles) == 'table' and Toggles.AtheonNukeDash
		if type(toggle) == 'table' then
			return toggle.Value == true
		end
		local ok, on = pcall(isToggleOn, 'AtheonNukeDash')
		if ok and on == true then
			return true
		end
		return getgenv().SB2AtheonNukeDashOn == true
	end

	local function dashToward(hrp, hum, dir, skillName, instant)
		if not shadowStepEnabled() or autoDodgeOwnsAtheon() then
			return false
		end
		faceMove(hrp, hum, dir)
		if not instant then
			task.wait()
			faceMove(hrp, hum, dir)
		end
		return castDash(skillName, hrp)
	end

	local function distFromCenter(hrp, center)
		if typeof(center) ~= 'Vector3' or not hrp then
			return 0
		end
		return Vector3.new(hrp.Position.X - center.X, 0, hrp.Position.Z - center.Z).Magnitude
	end

	-- Nuke escape only. Chase/close still uses DASH_MIN=70.
	local function dashOutOfNuke(hrp, hum, away, center, skillName)
		local hops = 0
		local any = false
		while hops < 3 do
			-- Stop as soon as we're outside the blast. (Credit UI is up the whole
			-- fight, so it must not force extra hops.)
			if distFromCenter(hrp, center) >= NUKE_SAFE then
				break
			end
			local ok = dashToward(hrp, hum, away, skillName, hops == 0)
			hops += 1
			any = any or ok
			if hops < 3 then
				task.wait(0.26)
			end
		end
		state.awayHops = hops
		return any
	end

	local function nukeAwayDir(hrp, center, atheon)
		local away = Vector3.new(hrp.Position.X - center.X, 0, hrp.Position.Z - center.Z)
		if away.Magnitude < 1 then
			local bossPos = mobRootPos(atheon)
			if bossPos then
				away = Vector3.new(hrp.Position.X - bossPos.X, 0, hrp.Position.Z - bossPos.Z)
			end
		end
		if away.Magnitude < 0.2 then
			local look = hrp.CFrame.LookVector
			away = Vector3.new(look.X, 0, look.Z)
		end
		if away.Magnitude < 0.05 then
			return Vector3.new(0, 0, -1)
		end
		return away.Unit
	end

	local function beginNukeAway(center, life, fromHook)
		if not shadowStepEnabled() or autoDodgeOwnsAtheon() then
			return false
		end
		if state.phase == 'away' then
			return false
		end
		local at = tonumber(getgenv().SB2AtheonNukeAt) or 0
		if at > 0 and at == state.handledNukeAt then
			return false
		end
		local _, hrp, hum = playerParts()
		if not hrp then
			return false
		end
		if typeof(center) ~= 'Vector3' then
			center = getgenv().SB2AtheonNukeGoal
		end
		if typeof(center) ~= 'Vector3' then
			return false
		end
		local inside = Vector3.new(hrp.Position.X - center.X, 0, hrp.Position.Z - center.Z).Magnitude
		if inside > NUKE_NEAR then
			-- Already outside the slam. Mark it handled so it doesn't re-fire.
			state.handledNukeAt = at > 0 and at or os.clock()
			return false
		end
		local atheon = findAtheon()
		local skillName = pickSkill()
		state.nukeInterrupt = true
		state.casting = false
		state.returnPos = hrp.Position
		state.awayDir = nukeAwayDir(hrp, center, atheon)
		state.center = center
		state.sawAt = os.clock()
		state.usedHook = fromHook == true
		state.hadTelegraph = false
		state.handledNukeAt = at > 0 and at or os.clock()
		state.nukeUntil = os.clock() + (tonumber(life) or NUKE_DEFAULT_LIFE) * 1.35 + NUKE_LAND_PAD
		if not ownsSkill(skillName) then
			notifyOnce('Atheon nuke dash needs Shadow Step (or Spirit Dash) owned.')
			state.phase = 'cooldown'
			state.backAt = os.clock()
			setBusy(os.clock() + 1)
			return false
		end
		state.phase = 'away'
		state.awayHops = 0
		state.dashAt = os.clock()
		state.casting = true
		setBusy(os.clock() + RETURN_MAX + 0.4)
		task.spawn(function()
			local ok = dashOutOfNuke(hrp, hum, state.awayDir, center, skillName)
			state.casting = false
			state.nukeInterrupt = false
			if ok then
				state.dashAt = os.clock()
				getgenv().SB2AtheonNukeDashLast = {
					why = fromHook and 'out-hook' or 'out',
					hops = state.awayHops,
					dist = distFromCenter(hrp, center),
					at = state.dashAt,
				}
			else
				state.phase = 'idle'
				setBusy(0)
				notifyOnce('Shadow Step failed — check stamina / cooldown.')
			end
		end)
		return true
	end

	local function flatTo(fromPos, dest)
		local flat = Vector3.new(dest.X - fromPos.X, 0, dest.Z - fromPos.Z)
		return flat.Magnitude, flat
	end

	local function arenaMiddle(y)
		local saved = getgenv().SB2AtheonArenaMid
		if typeof(saved) == 'Vector3' then
			state.arenaMid = saved
			return Vector3.new(saved.X, y or saved.Y, saved.Z)
		end
		if typeof(state.arenaMid) == 'Vector3' then
			return Vector3.new(state.arenaMid.X, y or state.arenaMid.Y, state.arenaMid.Z)
		end
		-- Player-confirmed Atheon realm pad center (not the huge room mesh).
		local mid = Vector3.new(834.5, y or 797.4, 317.4)
		state.arenaMid = mid
		getgenv().SB2AtheonArenaMid = mid
		return mid
	end

	local function getControls()
		local cached = getgenv().SB2AtheonControls
		if type(cached) == 'table' and type(cached.moveFunction) == 'function' then
			return cached
		end
		local ok, pm = pcall(function()
			local scripts = LocalPlayer:FindFirstChild('PlayerScripts')
			local mod = scripts and scripts:FindFirstChild('PlayerModule')
			return mod and require(mod)
		end)
		if ok and type(pm) == 'table' and type(pm.GetControls) == 'function' then
			local ctrl = pm:GetControls()
			if type(ctrl) == 'table' then
				getgenv().SB2AtheonControls = ctrl
				return ctrl
			end
		end
		if type(getgc) == 'function' then
			for _, v in ipairs(getgc(true)) do
				if type(v) == 'table'
					and type(rawget(v, 'moveFunction')) == 'function'
					and rawget(v, 'activeController') ~= nil
				then
					getgenv().SB2AtheonControls = v
					return v
				end
			end
		end
		return nil
	end

	local function setControlMove(worldDir)
		local ctrl = getControls()
		local ac = ctrl and ctrl.activeController
		local vec = worldDir
		local cam = workspace.CurrentCamera
		if ac and ac.moveVectorIsCameraRelative ~= false and cam then
			local localDir = cam.CFrame:VectorToObjectSpace(Vector3.new(worldDir.X, 0, worldDir.Z))
			localDir = Vector3.new(localDir.X, 0, localDir.Z)
			if localDir.Magnitude > 0.05 then
				vec = localDir.Unit
			else
				vec = Vector3.zero
			end
		end
		if ac then
			ac.moveVector = vec
		end
		if ctrl then
			ctrl.inputMoveVector = vec
		end
		return ctrl
	end

	local function clearControlMove(hum)
		local ctrl = getControls()
		local ac = ctrl and ctrl.activeController
		if ac then
			ac.moveVector = Vector3.zero
		end
		if ctrl then
			ctrl.inputMoveVector = Vector3.zero
		end
		if hum then
			pcall(function()
				hum:Move(Vector3.zero, false)
			end)
		end
	end

	local function walkToward(hrp, hum, dest, opts)
		opts = opts or {}
		if not hum or not hrp then
			return
		end
		pcall(function()
			hrp.Anchored = false
		end)
		pcall(function()
			hum.AutoRotate = true
			hum.PlatformStand = false
			hum.Sit = false
		end)
		pcall(function()
			if hum:GetState() == Enum.HumanoidStateType.Freefall then
				hum:ChangeState(Enum.HumanoidStateType.Running)
			end
		end)
		local dist0 = select(1, flatTo(hrp.Position, dest))
		local spd = math.max(8, tonumber(hum.WalkSpeed) or 16)
		local deadline = os.clock() + math.clamp(dist0 / spd + 0.85, 0.45, 5)
		-- Drive PlayerModule moveVector so the real walk cycle plays.
		-- Humanoid:Move gets overwritten next render, and MoveTo skates.
		while os.clock() < deadline do
			local remain, flat = flatTo(hrp.Position, dest)
			if remain <= WALK_STOP then
				break
			end
			if state.nukeInterrupt then
				break
			end
			if opts.stopIfCredit and inCreditRange() then
				break
			end
			if remain > dist0 + 6 then
				break
			end
			setControlMove(flat.Unit)
			task.wait()
		end
		clearControlMove(hum)
	end

	local function approachTarget(hrp, hum, dest, skillName, opts)
		opts = opts or {}
		if typeof(dest) ~= 'Vector3' or not hrp then
			return false
		end
		if opts.stopIfCredit and inCreditRange() then
			return true
		end
		if state.nukeInterrupt then
			return false
		end
		local dashes = 0
		while dashes < MAX_APPROACH_DASH do
			local remain, flat = flatTo(hrp.Position, dest)
			if remain <= WALK_STOP then
				return true
			end
			if state.nukeInterrupt then
				return false
			end
			if opts.stopIfCredit and inCreditRange() then
				return true
			end
			if remain >= DASH_MIN then
				dashToward(hrp, hum, flat, skillName)
				dashes += 1
				task.wait(0.22)
			else
				walkToward(hrp, hum, dest, opts)
				return true
			end
		end
		local remain = select(1, flatTo(hrp.Position, dest))
		if remain > WALK_STOP and remain < DASH_MIN then
			walkToward(hrp, hum, dest, opts)
		end
		return true
	end

	local function tryCloseGap(hrp, hum, atheon, skillName, now, force)
		if state.phase ~= 'idle' or state.casting then
			return false
		end
		if not force and now - (state.lastApproachAt or 0) < 0.85 then
			return false
		end
		local dest = mobRootPos(atheon)
		if typeof(dest) ~= 'Vector3' then
			return false
		end
		if inCreditRange(hrp, atheon) then
			return false
		end
		local remain = select(1, flatTo(hrp.Position, dest))
		if remain <= WALK_STOP then
			return false
		end
		state.lastApproachAt = now
		state.casting = true
		setBusy(now + 3)
		task.spawn(function()
			-- Shadow Step only on spawn; otherwise just walk in. Nuke / Fire Dash
			-- are the only reasons to step mid-fight.
			if force and remain >= DASH_MIN then
				approachTarget(hrp, hum, dest, skillName)
			else
				walkToward(hrp, hum, dest)
			end
			state.casting = false
			getgenv().SB2AtheonNukeDashLast = { why = 'close', at = os.clock() }
			setBusy(0)
		end)
		return true
	end

	local function installSmashHook()
		if type(getgc) ~= 'function' then
			return false
		end
		local smash
		for _, v in ipairs(getgc(true)) do
			if type(v) == 'table'
				and type(rawget(v, 'Replicating')) == 'function'
				and type(rawget(v, 'JumpEnemy')) == 'function'
				and type(rawget(v, 'CreateImpact')) == 'function'
			then
				smash = v
				break
			end
		end
		if not smash then
			return false
		end
		local origRep = getgenv().SB2AtheonSmashOrigRep or getgenv().SB2AtheonSmashOldRep
		local origImpact = getgenv().SB2AtheonSmashOrigImpact or getgenv().SB2AtheonSmashOldImpact
		if type(origRep) ~= 'function' then
			origRep = smash.Replicating
		end
		if type(origImpact) ~= 'function' then
			origImpact = smash.CreateImpact
		end
		getgenv().SB2AtheonSmashOrigRep = origRep
		getgenv().SB2AtheonSmashOrigImpact = origImpact
		getgenv().SB2AtheonSmashOldRep = origRep
		getgenv().SB2AtheonSmashOldImpact = origImpact
		smash.Replicating = function(self, surface, lifetime, jumpHeight, lastCF)
			local life = tonumber(lifetime) or 0
			if typeof(surface) == 'Vector3'
				and skillFromAtheon(self)
				and life >= 2
				and life <= 4
			then
				getgenv().SB2AtheonNukeGoal = surface
				getgenv().SB2AtheonNukeLife = life
				getgenv().SB2AtheonNukeAt = os.clock()
				getgenv().SB2AtheonNukeImpactAt = 0
				task.defer(function()
					pcall(beginNukeAway, surface, life, true)
				end)
			end
			return origRep(self, surface, lifetime, jumpHeight, lastCF)
		end
		smash.CreateImpact = function(self, ...)
			local result = origImpact(self, ...)
			-- Fall tween finishes inside CreateImpact — this is the land, not the windup.
			getgenv().SB2AtheonNukeImpactAt = os.clock()
			return result
		end
		getgenv().SB2AtheonSmashHooked = true
		return true
	end

	local function hookedNukeCenter(now)
		local at = tonumber(getgenv().SB2AtheonNukeAt) or 0
		local center = getgenv().SB2AtheonNukeGoal
		if typeof(center) ~= 'Vector3' or at <= 0 then
			return nil
		end
		if at == state.handledNukeAt then
			return nil
		end
		local life = tonumber(getgenv().SB2AtheonNukeLife) or NUKE_DEFAULT_LIFE
		local impactAt = tonumber(getgenv().SB2AtheonNukeImpactAt) or 0
		if impactAt > at then
			return nil
		end
		if (now - at) > life then
			return nil
		end
		return center, life
	end

	local function destKey(pos)
		if typeof(pos) ~= 'Vector3' then
			return nil
		end
		return string.format('%.0f,%.0f', pos.X, pos.Z)
	end

	local function findFireDashMod()
		if type(getgc) == 'function' then
			for _, v in ipairs(getgc(true)) do
				if type(v) == 'table'
					and type(rawget(v, 'Replicating')) == 'function'
					and type(rawget(v, 'Dash')) == 'function'
					and type(rawget(v, 'CreateFlames')) == 'function'
					and type(rawget(v, 'FlamesOffset')) == 'number'
				then
					return v
				end
			end
		end
		local ok, mod = pcall(function()
			local cc = ReplicatedStorage:FindFirstChild('CardinalClient')
			local floors = cc
				and cc:FindFirstChild('MainModule')
				and cc.MainModule:FindFirstChild('Services')
				and cc.MainModule.Services:FindFirstChild('EnemySkills')
				and cc.MainModule.Services.EnemySkills:FindFirstChild('Skills')
				and cc.MainModule.Services.EnemySkills.Skills:FindFirstChild('Floors')
			local atheon = floors
				and floors:FindFirstChild('Floor 12')
				and floors['Floor 12']:FindFirstChild('Atheon')
			local scriptMod = atheon and atheon:FindFirstChild('FireDash')
			if not scriptMod then
				return nil
			end
			local envRequire = type(getrenv) == 'function' and getrenv() and getrenv().require
			if type(envRequire) == 'function' then
				return envRequire(scriptMod)
			end
			return nil
		end)
		if ok and type(mod) == 'table' then
			return mod
		end
		return nil
	end

	local function installFireDashHook()
		local mod = findFireDashMod()
		if type(mod) ~= 'table' or type(mod.Replicating) ~= 'function' then
			return false
		end
		local old = getgenv().SB2AtheonFireDashOrigRep or getgenv().SB2AtheonFireDashOldRep
		if type(old) ~= 'function' then
			old = mod.Replicating
		end
		getgenv().SB2AtheonFireDashOrigRep = old
		getgenv().SB2AtheonFireDashOldRep = old
		local wrapped = function(self, surface, focus, endCF, speed, width)
			local dest = typeof(endCF) == 'CFrame' and endCF.Position
				or typeof(focus) == 'Vector3' and focus
			local from = typeof(surface) == 'Vector3' and surface or nil
			local span = (typeof(dest) == 'Vector3' and typeof(from) == 'Vector3')
				and Vector3.new(dest.X - from.X, 0, dest.Z - from.Z).Magnitude
				or 0
			if typeof(dest) == 'Vector3'
				and skillFromAtheon(self)
				and span >= 40
			then
				getgenv().SB2AtheonFireDashGoal = dest
				getgenv().SB2AtheonFireDashFrom = from
				getgenv().SB2AtheonFireDashAt = os.clock()
			end
			return old(self, surface, focus, endCF, speed, width)
		end
		if type(newcclosure) == 'function' then
			wrapped = newcclosure(wrapped)
		end
		mod.Replicating = wrapped
		getgenv().SB2AtheonFireDashHooked = true
		return true
	end

	local function hookedFireDashDest(now)
		local at = tonumber(getgenv().SB2AtheonFireDashAt) or 0
		local dest = getgenv().SB2AtheonFireDashGoal
		if typeof(dest) == 'Vector3' and (now - at) <= 2.2 then
			return dest, 'hook'
		end
		return nil
	end

	local function flameTrailDest(now)
		local best, bestLen = nil, 0
		for _, child in ipairs(workspace:GetChildren()) do
			if child:IsA('BasePart') then
				local n = child.Name
				if (n == 'Flames' or n == 'CorruptedFlames') and not state.seenFlames[child] then
					local len = child.Size.Z
					if len >= 18 and len > bestLen then
						best = child
						bestLen = len
					end
				end
			end
		end
		if not best then
			return nil
		end
		state.seenFlames[best] = now
		local dest = best.Position + best.CFrame.LookVector * (best.Size.Z * 0.5)
		return Vector3.new(dest.X, dest.Y, dest.Z), 'flames'
	end

	local function bossHopDest(atheon, now)
		local pos = mobRootPos(atheon)
		if typeof(pos) ~= 'Vector3' then
			return nil
		end
		local prev = state.lastBossPos
		local prevAt = state.lastBossAt or 0
		state.lastBossPos = pos
		state.lastBossAt = now
		if typeof(prev) ~= 'Vector3' then
			return nil
		end
		local dt = now - prevAt
		if dt <= 0 or dt > 0.35 then
			return nil
		end
		local move = Vector3.new(pos.X - prev.X, 0, pos.Z - prev.Z)
		if move.Magnitude < BOSS_DASH_MIN then
			return nil
		end
		return pos, 'boss-hop'
	end

	local function tryChaseDash(hrp, hum, atheon, skillName, now)
		if state.phase ~= 'idle' or state.casting then
			return false
		end
		if now - (state.lastChaseAt or 0) < CHASE_CD then
			return false
		end
		-- Only a real FireDash hook. Flames / boss hops false-trigger random hops.
		local dest, why = hookedFireDashDest(now)
		if typeof(dest) ~= 'Vector3' then
			return false
		end
		local liveDash = why == 'hook'
		if (not liveDash) and now < (state.holdIdleUntil or 0) then
			return false
		end
		local key = destKey(dest)
		if key and key == state.lastChaseKey and (now - (state.lastChaseAt or 0)) < 2.5 then
			return false
		end
		local remain = select(1, flatTo(hrp.Position, dest))
		if remain <= CLOSE_OK then
			return false
		end
		-- Fresh Fire Dash leaves from your feet. Chase the landing even if he is
		-- still next to you and dest is far from his current position.
		if not liveDash then
			local bossPos = mobRootPos(atheon)
			if typeof(bossPos) == 'Vector3' then
				local toBoss = select(1, flatTo(hrp.Position, bossPos))
				if toBoss <= CLOSE_OK then
					return false
				end
				if inCreditRange(hrp, atheon) and toBoss < DASH_MIN then
					return false
				end
			elseif inCreditRange(hrp, atheon) then
				return false
			end
		end
		if not ownsSkill(skillName) then
			return false
		end
		state.lastChaseKey = key
		state.lastChaseAt = now
		state.casting = true
		setBusy(now + 2.5)
		task.spawn(function()
			approachTarget(hrp, hum, dest, skillName)
			state.casting = false
			getgenv().SB2AtheonNukeDashLast = {
				why = 'chase-' .. tostring(why),
				at = os.clock(),
			}
			setBusy(os.clock() + CHASE_BUSY)
		end)
		return true
	end

	local function stopLoop()
		local conn = getgenv().SB2AtheonNukeDashConn
		if conn then
			pcall(function()
				conn:Disconnect()
			end)
			getgenv().SB2AtheonNukeDashConn = nil
		end
		getgenv().SB2AtheonNukeDashOn = false
		setBusy(0)
		state.phase = 'idle'
	end

	local function toggleWanted()
		local toggle = type(Toggles) == 'table' and Toggles.AtheonNukeDash
		if type(toggle) == 'table' then
			return toggle.Value == true
		end
		return getgenv().SB2AtheonNukeDashOn == true
	end

	local function tick()
		if not toggleWanted() then
			stopLoop()
			return
		end
		if not isLocalAlive() or autoDodgeOwnsAtheon() then
			return
		end
		local now = os.clock()
		local _, hrp, hum = playerParts()
		if not hrp then
			return
		end

		local hookCenter, hookLife = hookedNukeCenter(now)
		if hookCenter and state.phase ~= 'away' then
			if beginNukeAway(hookCenter, hookLife, true) then
				return
			end
		end

		if now - state.lastScan < SCAN_GAP and state.phase == 'idle' then
			return
		end
		state.lastScan = now

		local atheon = findAtheon()
		local justSpawned = false
		if atheon then
			justSpawned = state.liveBoss ~= true
			state.liveBoss = true
			state.seenBoss = true
			state.wentHome = false
			state.missingBossSince = 0
			if justSpawned then
				state.holdIdleUntil = 0
			end
		else
			state.liveBoss = false
			if (state.missingBossSince or 0) == 0 then
				state.missingBossSince = now
			end
		end
		if not atheon then
			local mid = arenaMiddle(hrp.Position.Y)
			local fromMid = select(1, flatTo(hrp.Position, mid))
			local goneLongEnough = (now - (state.missingBossSince or now)) >= 0.7
			local needHome = state.phase == 'idle'
				and state.seenBoss
				and goneLongEnough
				and fromMid > CLOSE_OK
				and (not state.wentHome or fromMid > 40)
			if needHome then
				if state.casting then
					return
				end
				state.casting = true
				state.wentHome = true
				local homeAt = now
				setBusy(now + 4)
				task.spawn(function()
					-- Home is the pad, not Atheon. Credit still up from the kill must not cancel it.
					approachTarget(hrp, hum, mid, pickSkill())
					local fireAt = tonumber(getgenv().SB2AtheonFireDashAt) or 0
					if fireAt <= homeAt then
						getgenv().SB2AtheonFireDashAt = 0
					end
					state.holdIdleUntil = os.clock() + 0.4
					state.casting = false
					getgenv().SB2AtheonNukeDashLast = { why = 'home', at = os.clock() }
					setBusy(0)
				end)
				return
			end
			if state.phase == 'idle' then
				return
			end
		end

		if state.casting then
			return
		end

		local skillName = pickSkill()
		if state.phase == 'idle' then
			if not atheon then
				return
			end
			if tryChaseDash(hrp, hum, atheon, skillName, now) then
				return
			end
			if tryCloseGap(hrp, hum, atheon, skillName, now, justSpawned) then
				return
			end
			return
		end

		if state.phase == 'away' then
			local watchOrigin = state.center
			if typeof(watchOrigin) ~= 'Vector3' then
				watchOrigin = mobRootPos(atheon) or hrp.Position
			end
			local nuke = bestNuke(watchOrigin, { watch = true })
			if nuke then
				state.sawAt = now
				state.center = nuke.center
				state.hadTelegraph = true
			end
			local impactSoon = tonumber(getgenv().SB2AtheonNukeImpactAt) or 0
			if (state.awayHops or 0) < 3
				and impactSoon <= (state.dashAt or 0)
				and distFromCenter(hrp, state.center) < NUKE_SAFE
			then
				state.casting = true
				task.spawn(function()
					dashToward(hrp, hum, state.awayDir or hrp.CFrame.LookVector, skillName)
					state.awayHops = (state.awayHops or 0) + 1
					state.casting = false
				end)
				return
			end
			local waited = now - (state.dashAt or now)
			local impactAt = tonumber(getgenv().SB2AtheonNukeImpactAt) or 0
			local landed = impactAt > (state.sawAt or 0) and (now - impactAt) >= NUKE_LAND_PAD
			local heldLongEnough = state.nukeUntil and now >= state.nukeUntil
			local clear = (not state.usedHook)
				and state.hadTelegraph
				and (not nuke)
				and (now - (state.sawAt or now) >= RETURN_CLEAR)
			-- Hook slams can land late. Stay out until impact + pad, not just lifetime.
			local canReturn = waited >= RETURN_MAX
			if state.usedHook then
				canReturn = canReturn or (waited >= 2.2 and landed)
			else
				canReturn = canReturn or (waited >= 1.0 and (landed or heldLongEnough or clear))
			end
			if canReturn then
				local dest = mobRootPos(atheon)
				if typeof(dest) ~= 'Vector3' then
					dest = state.returnPos
				end
				if typeof(dest) ~= 'Vector3' then
					dest = arenaMiddle(hrp.Position.Y)
				end
				state.casting = true
				task.spawn(function()
					approachTarget(hrp, hum, dest, skillName)
					local fireAt = tonumber(getgenv().SB2AtheonFireDashAt) or 0
					if fireAt <= (state.dashAt or 0) then
						getgenv().SB2AtheonFireDashAt = 0
					end
					state.holdIdleUntil = os.clock() + 0.4
					state.casting = false
					state.phase = 'cooldown'
					state.backAt = os.clock()
					setBusy(os.clock() + AFTER_CD)
					getgenv().SB2AtheonNukeDashLast = {
						why = 'back',
						at = state.backAt,
					}
				end)
			end
			return
		end

		if state.phase == 'cooldown' then
			if now - (state.backAt or 0) >= AFTER_CD then
				state.phase = 'idle'
				state.returnPos = nil
				state.awayDir = nil
				state.center = nil
				state.awayHops = 0
				setBusy(0)
			end
		end
	end

	local function startLoop()
		if type(Toggles) == 'table' and Toggles.AtheonNukeDash and not isToggleOn('AtheonNukeDash') then
			stopLoop()
			return
		end
		getgenv().SB2AtheonNukeDashOn = true
		local prev = getgenv().SB2AtheonNukeDashConn
		if prev then
			pcall(function()
				prev:Disconnect()
			end)
			getgenv().SB2AtheonNukeDashConn = nil
		end
		getgenv().SB2AtheonNukeDashConn = RunService.Heartbeat:Connect(function()
			tick()
		end)
	end

	local existing = type(Toggles) == 'table' and Toggles.AtheonNukeDash
	if not existing and CombatBox and type(CombatBox.AddToggle) == 'function' then
		CombatBox:AddToggle('AtheonNukeDash', {
			Text = 'Atheon Shadow Step',
			Default = false,
			Tooltip = 'Nuke: Shadow Step out of the slam, then back in after it hits. Fire dash: Shadow Step toward where Atheon lands.',
		}):OnChanged(function(value)
			getgenv().SB2AtheonNukeDashOn = value == true
			if not value then
				stopLoop()
				return
			end
			startLoop()
		end)
		existing = type(Toggles) == 'table' and Toggles.AtheonNukeDash
	end
	if (existing and existing.Value == true) or isToggleOn('AtheonNukeDash') or getgenv().SB2AtheonNukeDashOn == true then
		startLoop()
	end
	pcall(installFireDashHook)
	pcall(installSmashHook)
	if (tonumber(getgenv().SB2AtheonNukeAt) or 0) > 0
		or typeof(getgenv().SB2AtheonNukeGoal) == 'Vector3'
		or typeof(getgenv().SB2AtheonArenaMid) == 'Vector3'
		or type(getgenv().SB2AtheonNukeDashLast) == 'table'
	then
		state.seenBoss = true
	end
	getgenv().SB2StartAtheonNukeDash = startLoop
	getgenv().SB2StopAtheonNukeDash = stopLoop
end
