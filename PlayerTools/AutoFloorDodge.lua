--[[
	Split from PlayerTools_Obsidian.lua (Luau 200-local register cap).
]]
getgenv().SB2AutoFloorDodgeBuild = 'floor-dodge-v4'

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
			if dist >= half + 3 then
				return
			end
			local push = (half + 8) - dist
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
	local lavaStandY = nil
	local lavaSeenUntil = 0
	local lavaScanAt = 0

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

	local function writeHeldCF(hrp, dest)
		local lv = hrp.CFrame.LookVector
		local flat = Vector3.new(lv.X, 0, lv.Z)
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
	end

	local function clearLavaHover()
		getgenv().SB2LavaHoverY = nil
		lavaStandY = nil
		lavaSeenUntil = 0
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
				return
			end
			-- Event dive fight loop already sidesteps circles (same scanner).
			-- Floor-is-lava still hovers here so dive cannot plant you in the floor.
			local lavaNow = floorLavaActive(os.clock())
			if not lavaNow and getgenv().SB2DiveFarmOn == true and isToggleOn('DiveFarm') then
				return
			end
			if getgenv().SB2DiveUnderMap == true and not lavaNow then
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
			local now = os.clock()
			if lavaNow then
				if lavaStandY == nil then
					lavaStandY = hrp.Position.Y
				end
				local gy = groundYAt(hrp) or (lavaStandY - 3)
				local hoverY = gy + LAVA_CLEARANCE
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
		Tooltip = 'Sidestep floor circles and attack beams. Floor is Lava lifts you 30 studs, then drops you when the wave ends. Map light shafts are ignored.',
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
