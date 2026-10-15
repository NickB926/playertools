--[[
	Split from PlayerTools_Obsidian.lua (Luau 200-local register cap).
]]
getgenv().SB2AutoFloorDodgeBuild = 'floor-dodge-v2'

return function(env)
	local CombatBox = env.CombatBox
	local RunService = env.RunService
	local LocalPlayer = env.LocalPlayer
	local Toggles = env.Toggles
	local isToggleOn = env.isToggleOn
	local isLocalAlive = env.isLocalAlive
	local getMyCharacterModel = env.getMyCharacterModel
	assert(CombatBox, 'AutoFloorDodge: CombatBox required')
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
				return
			end
			-- Event dive fight loop already sidesteps circles (same scanner).
			if getgenv().SB2DiveFarmOn == true and isToggleOn('DiveFarm') then
				return
			end
			if getgenv().SB2DiveUnderMap == true then
				return
			end
			if not isLocalAlive() then
				return
			end
			local findGoal = getgenv().SB2FindFloorCircleDodgeGoal
			if type(findGoal) ~= 'function' then
				return
			end
			local model = getMyCharacterModel() or LocalPlayer.Character
			local hrp = model and model:FindFirstChild('HumanoidRootPart')
			if not hrp or not hrp:IsA('BasePart') then
				return
			end
			local now = os.clock()
			local goal = findGoal(hrp.Position, hrp.Position.Y, nil)
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
		Default = false,
		Tooltip = 'Sidestep red/purple floor telegraphs (SpellTelegraphs, workspace.Circle, etc.). Works in dungeons, bosses, and events — not only Event dive. Event dive uses the same detector when its farm loop is on.',
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
