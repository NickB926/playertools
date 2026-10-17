--[[
	Split from PlayerTools_Obsidian.lua (Luau 200-local register cap).
]]
getgenv().SB2AutoFloorDodgeBuild = 'floor-dodge-v10'

return function(env)
	local CombatBox = env.CombatBox
	local RunService = env.RunService
	local LocalPlayer = env.LocalPlayer
	local Toggles = env.Toggles
	local isToggleOn = env.isToggleOn
	local isLocalAlive = env.isLocalAlive
	local getMyCharacterModel = env.getMyCharacterModel
	assert(CombatBox, 'AutoFloorDodge: CombatBox required')

	local BEAM_SKIP_ROOT = {
		Model = true,
		Floors = true,
		Terrain = true,
		Characters = true,
		CharacterItems = true,
		Camera = true,
		WaveDefenseStuff = true,
		SB2WaveKillTargetVis = true,
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
		for _, child in ipairs(workspace:GetChildren()) do
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

	local LAVA_CLEARANCE = 32
	local BOSS_CLEARANCE = 80
	local AEGANATOS_CLEARANCE = 300
	local WENDIGO_BEHIND = 60
	local lavaStandY = nil
	local lavaSeenUntil = 0
	local lavaScanAt = 0
	local bossSeenUntil = 0
	local bossScanAt = 0
	local bossClearanceHeld = nil
	local BOSS_NEEDLES = { 'aegor', 'vaelith', 'rubricatus', 'nythrane', 'aeganatos' }

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
					or t == 'lava'
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
		if region and region:IsA('BasePart') then
			if region.Transparency < 0.85 or #region:GetChildren() > 0 then
				return true
			end
		end
		for _, c in ipairs(workspace:GetChildren()) do
			local n = string.lower(c.Name)
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

	local function floorLavaActive(now)
		if now - lavaScanAt >= 0.25 then
			lavaScanAt = now
			if uiSaysFloorLava() or worldSaysFloorLava() then
				lavaSeenUntil = now + 1
			end
		end
		return now < lavaSeenUntil
	end

	pcall(function()
		local bosses = game:GetService('ReplicatedStorage')
			.CardinalClient.MainModule.Services.EnemySkills.Skills['Wave Defense'].Bosses
		for _, c in ipairs(bosses:GetChildren()) do
			local first = string.lower(tostring(c.Name)):match('^[%a\']+')
			if first and #first >= 4 then
				BOSS_NEEDLES[#BOSS_NEEDLES + 1] = first
			end
		end
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

	local function mobIsBoss(mob)
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
		local ent = mob:FindFirstChild('Entity')
		if mobFlag(mob, 'Boss') or mobFlag(ent, 'Boss') or mobFlag(mob, 'IsBoss') or mobFlag(ent, 'IsBoss') or mobFlag(ent, 'Miniboss') then
			return true
		end
		local beh = mob:GetAttribute('EnemyBehavior') or (ent and ent:GetAttribute('EnemyBehavior'))
		if type(beh) == 'string' and string.find(string.lower(beh), 'boss', 1, true) then
			return true
		end
		local diff = ent and ent:FindFirstChild('Difficulty')
		if diff and typeof(diff.Value) == 'string' and string.find(string.lower(diff.Value), 'boss', 1, true) then
			return true
		end
		return false
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
		for _, child in ipairs(bars:GetChildren()) do
			if child:IsA('GuiObject') and child.Visible then
				return true
			end
		end
		return false
	end

	local function mobBossClearance(mob)
		if not mobIsBoss(mob) then
			return nil
		end
		local key = string.gsub(string.lower(tostring(mob.Name)), '[%p%s]+', '')
		if string.find(key, 'aeganatos', 1, true) then
			return AEGANATOS_CLEARANCE
		end
		local plate = mob:FindFirstChild('Nameplate')
		local label = plate and plate:FindFirstChildWhichIsA('TextLabel', true)
		if label and string.find(string.gsub(string.lower(tostring(label.Text)), '[%p%s]+', ''), 'aeganatos', 1, true) then
			return AEGANATOS_CLEARANCE
		end
		return BOSS_CLEARANCE
	end

	local function bossHoverActive(now)
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
			if not best and bossBarActive() then
				best = BOSS_CLEARANCE
			end
			if best then
				bossClearanceHeld = best
				bossSeenUntil = now + 1.2
			end
		end
		if now < bossSeenUntil then
			return bossClearanceHeld or BOSS_CLEARANCE
		end
		bossClearanceHeld = nil
		return nil
	end

	local function groundYAt(hrp)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local ignore = { hrp.Parent }
		params.FilterDescendantsInstances = ignore
		local origin = Vector3.new(hrp.Position.X, hrp.Position.Y + 8, hrp.Position.Z)
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

	local function writeHeldCF(hrp, dest, lookAt)
		local flat
		if typeof(lookAt) == 'Vector3' then
			flat = Vector3.new(lookAt.X - dest.X, 0, lookAt.Z - dest.Z)
		else
			local lv = hrp.CFrame.LookVector
			flat = Vector3.new(lv.X, 0, lv.Z)
		end
		local cf = flat.Magnitude >= 0.08 and CFrame.lookAt(dest, dest + flat.Unit) or CFrame.new(dest)
		hrp.AssemblyLinearVelocity = Vector3.zero
		hrp.AssemblyAngularVelocity = Vector3.zero
		hrp.CFrame = cf
		if type(getgenv().SB2MoveCharacter) == 'function' then
			getgenv().SB2MoveCharacter(cf, 0.12)
		end
		if type(getgenv().SB2SetAnchorLockCF) == 'function' then
			getgenv().SB2SetAnchorLockCF(cf)
		elseif getgenv().SB2CombatAnchorOn == true then
			getgenv().SB2AnchorLockCF = cf
		end
		local pin = getgenv().SB2TpPinCFrame
		local pinNear = typeof(pin) == 'CFrame' and (pin.Position - cf.Position).Magnitude < 3
		if not pinNear and type(getgenv().SB2PinTeleportCFrame) == 'function' then
			getgenv().SB2PinTeleportCFrame(cf, 8)
		end
	end

	local hoverGroundY = nil

	local function clearLavaHover()
		getgenv().SB2LavaHoverY = nil
		lavaStandY = nil
		hoverGroundY = nil
		lavaSeenUntil = 0
		bossSeenUntil = 0
		bossClearanceHeld = nil
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

	local function startAutoFloorDodgeLoop()
		getgenv().SB2AutoFloorDodgeOn = true
		local prev = getgenv().SB2AutoFloorDodgeConn
		if prev then
			pcall(function()
				prev:Disconnect()
			end)
			getgenv().SB2AutoFloorDodgeConn = nil
		end
		local lastStep = 0
		getgenv().SB2AutoFloorDodgeConn = RunService.Heartbeat:Connect(function()
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
				getgenv().SB2WendigoHold = nil
				return
			end
			-- Event dive fight loop already sidesteps circles (same scanner).
			-- Floor-is-lava still hovers here so dive cannot plant you in the floor.
			local nowPre = os.clock()
			local lavaNow = floorLavaActive(nowPre)
			local bossNow = bossHoverActive(nowPre)
			local orbEarly = darknerOrbCenter()
			local wendigoNow = refreshWendigo(nowPre)
			if not lavaNow and not bossNow and not orbEarly and not wendigoNow and getgenv().SB2DiveFarmOn == true and isToggleOn('DiveFarm') then
				return
			end
			if getgenv().SB2DiveUnderMap == true and not lavaNow and not bossNow and not orbEarly and not wendigoNow then
				return
			end
			if not isLocalAlive() then
				return
			end
			local model = getMyCharacterModel() or LocalPlayer.Character
			local hrp = model and model:FindFirstChild('HumanoidRootPart')
			if not hrp or not hrp:IsA('BasePart') then
				return
			end
			if wendigoNow then
				local pos, look = mobFlatLook(wendigoNow)
				if pos and look then
					local dx = hrp.Position.X - pos.X
					local dz = hrp.Position.Z - pos.Z
					if (dx * dx + dz * dz) <= (800 * 800) then
						getgenv().SB2DarknerOrbXZ = nil
						local y = lavaStandY or hrp.Position.Y
						if lavaStandY ~= nil or getgenv().SB2LavaHoverY ~= nil then
							clearLavaHover()
						end
						local dest = Vector3.new(pos.X - look.X * WENDIGO_BEHIND, y, pos.Z - look.Z * WENDIGO_BEHIND)
						getgenv().SB2WendigoHold = dest
						writeHeldCF(hrp, dest, pos)
						return
					end
				end
			end
			getgenv().SB2WendigoHold = nil
			local orb = darknerOrbCenter()
			if orb then
				local dx = hrp.Position.X - orb.X
				local dz = hrp.Position.Z - orb.Z
				if (dx * dx + dz * dz) <= (220 * 220) then
					getgenv().SB2DarknerOrbXZ = Vector3.new(orb.X, 0, orb.Z)
					local y = lavaStandY or hrp.Position.Y
					if lavaStandY ~= nil or getgenv().SB2LavaHoverY ~= nil then
						clearLavaHover()
					end
					writeHeldCF(hrp, Vector3.new(orb.X, y, orb.Z))
					return
				end
			end
			getgenv().SB2DarknerOrbXZ = nil
			local now = os.clock()
			local clearance = bossNow or (lavaNow and LAVA_CLEARANCE or nil)
			if clearance then
				if lavaStandY == nil then
					lavaStandY = hrp.Position.Y
					hoverGroundY = groundYAt(hrp) or (lavaStandY - 3)
				end
				local hoverY = hoverGroundY + clearance
				getgenv().SB2LavaHoverY = hoverY
				writeHeldCF(hrp, Vector3.new(hrp.Position.X, hoverY, hrp.Position.Z))
				return
			elseif lavaStandY ~= nil then
				local dropY = lavaStandY
				clearLavaHover()
				writeHeldCF(hrp, Vector3.new(hrp.Position.X, dropY, hrp.Position.Z))
				return
			end
			local goal = beamDodgeGoal(hrp.Position)
			if not goal then
				local findGoal = getgenv().SB2FindFloorCircleDodgeGoal
				if type(findGoal) == 'function' then
					goal = findGoal(hrp.Position, hrp.Position.Y, nil)
				end
			end
			if not goal then
				return
			end
			if now - lastStep < 0.22 then
				return
			end
			local flatMove = Vector3.new(goal.X - hrp.Position.X, 0, goal.Z - hrp.Position.Z)
			if flatMove.Magnitude < 2.5 then
				return
			end
			lastStep = now
			pcall(function()
				local dest = Vector3.new(goal.X, hrp.Position.Y, goal.Z)
				local lv = hrp.CFrame.LookVector
				local keep = Vector3.new(lv.X, 0, lv.Z)
				local cf = keep.Magnitude >= 0.08 and CFrame.lookAt(dest, dest + keep.Unit)
					or CFrame.new(dest)
				local moved = false
				if type(getgenv().SB2MoveCharacter) == 'function' then
					getgenv().SB2MoveCharacter(cf, 0.35)
					moved = true
				end
				if not moved then
					hrp.Anchored = false
					hrp.CFrame = cf
					local v = hrp.AssemblyLinearVelocity
					hrp.AssemblyLinearVelocity = Vector3.new(v.X * 0.15, v.Y, v.Z * 0.15)
				end
				if type(getgenv().SB2SetAnchorLockCF) == 'function' then
					getgenv().SB2SetAnchorLockCF(cf)
				elseif typeof(getgenv().SB2AnchorLockCF) == 'CFrame' or getgenv().SB2CombatAnchorOn == true then
					getgenv().SB2AnchorLockCF = cf
				end
				if type(getgenv().SB2BeginAnchorReplicate) == 'function' then
					getgenv().SB2BeginAnchorReplicate(0.35)
				end
			end)
		end)
	end

	CombatBox:AddToggle('AutoFloorDodge', {
		Text = 'Auto dodge floor circles',
		Default = true,
		Tooltip = 'Sidestep floor circles and attack beams. Floor is Lava lifts you 30 studs. A wave boss lifts you 80 studs until it dies. Aeganatos lifts you 300. Darkner orb keeps you in its center. Enraged Wendigo holds you 60 studs behind it until it dies.',
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
			clearLavaHover()
			getgenv().SB2DarknerOrbXZ = nil
			getgenv().SB2WendigoHold = nil
			return
		end
		startAutoFloorDodgeLoop()
	end)
	task.defer(function()
		local t = Toggles.AutoFloorDodge
		if type(t) == 'table' and t.Value == true and getgenv().SB2AutoFloorDodgeConn == nil then
			startAutoFloorDodgeLoop()
		end
	end)
end
