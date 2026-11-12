--[[
	Split from PlayerTools_Obsidian.lua (Luau 200-local register cap).
]]
getgenv().SB2AutoFloorDodgeBuild = 'ground-dodge-v1'

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
			if not beam:IsA('Beam') or beam.Enabled ~= true or beam.Width0 < 3 then
				return
			end
			local a0, a1 = beam.Attachment0, beam.Attachment1
			if not a0 or not a1 then
				return
			end
			local dist, px, pz = segDistXZ(origin, a0.WorldPosition, a1.WorldPosition)
			local half = beam.Width0 * 0.5
			-- Land well past the beam. 150ms+ ping replicates the jump late, and the
			-- hit circle is wider than the visible beam, so 8 studs still got clipped.
			local clear = 26
			if dist >= half + 16 then
				return
			end
			local push = (half + clear) - dist
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
		local function considerPart(d)
			if not d or not d:IsA('BasePart') then
				return
			end
			if d.Transparency >= 0.995 then
				return
			end
			local n = string.lower(tostring(d.Name or ''))
			local pn = d.Parent and string.lower(tostring(d.Parent.Name or '')) or ''
			local blob = n .. ' ' .. pn
			local meteor = string.find(blob, 'meteor', 1, true)
				or string.find(blob, 'fireball', 1, true)
				or string.find(blob, 'rock', 1, true)
				or string.find(blob, 'boulder', 1, true)
			local floorSlam = string.find(blob, 'smash', 1, true)
				or string.find(blob, 'slam', 1, true)
				or string.find(blob, 'strike', 1, true)
				or string.find(blob, 'gyzer', 1, true)
				or string.find(blob, 'geyser', 1, true)
			if not meteor and not floorSlam then
				return
			end
			local flat = flatXZ(d.Position)
			local near = (flat - playerFlat).Magnitude
			if near > 95 then
				return
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
					considerPart(d)
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
		local sky = wdSkyThreatDodgeGoal(hrp.Position, y)
		if sky then
			return sky
		end
		local tele = telegraphDodgeGoal(hrp.Position, y)
		if tele then
			return tele
		end
		local findGoal = getgenv().SB2FindFloorCircleDodgeGoal
		if type(findGoal) == 'function' then
			local g = findGoal(hrp.Position, y, nil)
			if g then
				return flattenDodgeY(g, y)
			end
		end
		local beam = beamDodgeGoal(hrp.Position)
		if beam then
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
			if mobIsDead(mob) then
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
		if not mob or mobIsDead(mob) then
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

	local function uiSaysFloorLava()
		local pg = LocalPlayer:FindFirstChild('PlayerGui')
		if not pg then
			return false
		end
		local n = 0
		for _, d in ipairs(pg:GetDescendants()) do
			n += 1
			if n > 3500 then
				break
			end
			if d:IsA('TextLabel') or d:IsA('TextButton') then
				local full = d:GetFullName()
				if string.find(full, 'CashShop', 1, true)
					or string.find(full, 'InventoryFrame', 1, true)
					or string.find(full, 'Quests', 1, true)
				then
					continue
				end
				local t = string.lower(tostring(d.Text or ''))
				if string.find(t, 'floor is lava', 1, true)
					or string.find(t, 'floorislava', 1, true)
					or string.find(t, 'lava wave', 1, true)
				then
					return true
				end
			end
		end
		return false
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

	local function worldSaysFloorLava()
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
			or textIsBob(mob.Name)
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
		local p = mobStrikePos(mob)
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
		local ignore = { hrp.Parent }
		params.FilterDescendantsInstances = ignore
		local origin = Vector3.new(wx, wy + 8, wz)
		for _ = 1, 5 do
			local hit = workspace:Raycast(origin, Vector3.new(0, -500, 0), params)
			if not hit then
				break
			end
			if not partIsFireOrb(hit.Instance) then
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
		local liftY = dest.Y - hrp.Position.Y
		local airborne = humAirborne(hrp) and not lavaLock and not bobLock and not rubLock
			and forceY ~= true and liftY <= 2
		if airborne then
			dest = Vector3.new(dest.X, hrp.Position.Y, dest.Z)
			skipPin = true
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
			hrp.AssemblyLinearVelocity = Vector3.new(v.X * 0.2, v.Y, v.Z * 0.2)
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
		local rising = false
		for i = 1, n do
			if rubricatusPillarRising(pillars[i]) then
				rising = true
				break
			end
		end
		if n > rubricatusPillarCount or rising then
			if rubricatusNukeStartedAt == 0 then
				rubricatusNukeStartedAt = nowPre
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

	local function rubricatusGeneralDodgeGoal(hrpPos, fightY, bossMob, now)
		local keepFlat = bossMob and lastRubricatusFlat or nil
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
		local inset = math.clamp(entry.halfW * 0.3, 1.2, PILLAR_BEHIND_OFFSET)
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
			and (playerFlat - entry.flat).Magnitude <= math.max(entry.halfW * 0.65, 2.5)
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
		if not bossMob then
			rubricatusCoverPart = nil
			rubricatusCoverGoalFlat = nil
			return nil
		end
		local bossFlat = rubricatusBossFlat(bossMob)
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
		local coverY = rubricatusCoverY(pick, fightY)
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

	-- writeHeldCF zeros velocity while leaving Freefall. Near the floor that parks you
	-- until WASD sets MoveDirection. Plant on the ground instead of waiting for W.
	local function unstickIdleFreefall(hrp)
		if getgenv().SB2BobEscapeActive == true then
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
		local st = hum:GetState()
		if st ~= Enum.HumanoidStateType.Freefall and st ~= Enum.HumanoidStateType.Jumping then
			return
		end
		local vel = hrp.AssemblyLinearVelocity
		if math.abs(vel.Y) > 6 or vel.Magnitude > 12 then
			return
		end
		local gy = groundYAt(hrp)
		if not gy then
			return
		end
		local standY = gy + humanoidHip(hrp) + hrp.Size.Y * 0.5 + 0.15
		local above = hrp.Position.Y - standY
		if above > 14 then
			return
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
		hrp.AssemblyLinearVelocity = Vector3.new(0, -2, 0)
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
		if typeof(bobEscapeFlat) == 'Vector3' then
			return Vector3.new(bobEscapeFlat.X, holdY, bobEscapeFlat.Z)
		end
		local center = waveDefenseRiftsCenterFlat()
		if not center then
			center = Vector3.new(hrp.Position.X, 0, hrp.Position.Z)
		end
		local away = Vector3.new(hrp.Position.X - center.X, 0, hrp.Position.Z - center.Z)
		local bob = findBobMob()
		local bobP = bob and mobStrikePos(bob)
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
		bobEscapeFlat = Vector3.new(
			center.X + away.X * BOB_SIDE_OFFSET,
			0,
			center.Z + away.Z * BOB_SIDE_OFFSET
		)
		return Vector3.new(bobEscapeFlat.X, holdY, bobEscapeFlat.Z)
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
			if clear > bestClear + 2 or (math.abs(clear - bestClear) <= 2 and travel < bestTravel) then
				bestClear = clear
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
		return writeHeldCF(hrp, dest, lookAt, minMove, true, false)
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
		if now - lastStepAt < 0.12 then
			return lastStepAt
		end
		local y = hrp.Position.Y
		local goal = vaelithMissileDodgeGoal(hrp.Position)
		if not goal then
			goal = tempestLightningDodgeGoal(hrp.Position)
		end
		if not goal then
			goal = resolveFloorDodgeGoal(hrp, y)
		end
		if goal and sidestepOnGround(hrp, goal, nil, 1.6) then
			return now
		end
		if dropHoverToGround(hrp) then
			return now
		end
		unstickIdleFreefall(hrp)
		return lastStepAt
	end

	local function startAutoFloorDodgeLoop()
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
			if not isLocalAlive() then
				return
			end
			local model = getMyCharacterModel() or LocalPlayer.Character
			local hrp = model and model:FindFirstChild('HumanoidRootPart')
			if not hrp or not hrp:IsA('BasePart') then
				return
			end
			lastStep = tickGroundDodge(hrp, nowPre, lastStep)
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

	local existing = type(Toggles) == 'table' and Toggles.AutoFloorDodge
	if not existing then
		CombatBox:AddToggle('AutoFloorDodge', {
			Text = 'Auto dodge floor circles',
			Default = false,
			Tooltip = 'Sidestep beams, floor circles, and other attacks on the ground. No air hover or 4-spot hop.',
		}):OnChanged(function(value)
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
	getgenv().SB2StopAutoFloorDodgeLoop = stopAutoFloorDodgeLoop
	getgenv().SB2RubricatusPillarCoverGoal = rubricatusPillarCoverGoal
	getgenv().SB2RubricatusNukeTelegraph = rubricatusSpawnedPillarsNear
	getgenv().SB2RubricatusSnapToCover = rubricatusSnapToCover
	getgenv().SB2RubricatusInCoverWindow = rubricatusInCoverWindow
	getgenv().SB2WaveDefenseRiftHopGoal = waveDefenseRiftHopGoal

	-- Rubricatus fight recorder: survives server hops (module reloads each server) so a nuke
	-- death can be read back from PlayerTools/_rub_fight_log.txt afterwards.
	do
		local RUB_LOG_PATH = 'PlayerTools/_rub_fight_log.txt'
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
		local DEATH_LOG_PATH = 'PlayerTools/_death_log.txt'
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
					if not isfile(DEATH_LOG_PATH) or #readfile(DEATH_LOG_PATH) > 500000 then
						writefile(DEATH_LOG_PATH, '')
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
			local EQUIP_LOG_PATH = 'PlayerTools/_equip_log.txt'
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
end
