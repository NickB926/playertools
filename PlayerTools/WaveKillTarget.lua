--[[
	Split from PlayerTools_Obsidian.lua (Luau 200-local register cap).
]]
getgenv().SB2WaveKillBuild = 'wave-kill-phantom-v3'

return function(env)
	local WdBox = env.WdBox
	local RunService = env.RunService
	local Library = env.Library
	local LocalPlayer = env.LocalPlayer
	local Toggles = env.Toggles
	local isToggleOn = env.isToggleOn
	local getMyCharacterModel = env.getMyCharacterModel
	local getMyBringPart = env.getMyBringPart
	assert(WdBox, 'WaveKillTarget: WdBox required')
	local WAVE_KILL_HL = 'SB2WaveKillTargetHL'
	local WAVE_VIS_FOLDER = 'SB2WaveKillTargetVis'
	local WAVE_VIS_COLOR = Color3.fromRGB(80, 255, 120)
	local WAVE_VIS_OUTLINE = Color3.fromRGB(255, 220, 64)
	local WAVE_KILL_HAS_DRAWING = typeof(Drawing) == 'table' and type(Drawing.new) == 'function'
	local WAVE_CAM_NEAR = -0.2

	local function waveKillDestroyDrawing(obj)
		if not obj then
			return
		end
		pcall(function()
			obj.Visible = false
		end)
		pcall(function()
			obj:Remove()
		end)
	end

	local function waveKillCamObjectPos(worldPos)
		local cam = workspace.CurrentCamera
		if not cam then
			return nil
		end
		return cam.CFrame:PointToObjectSpace(worldPos)
	end

	local function waveKillObjectToScreen(objPos)
		local cam = workspace.CurrentCamera
		if not cam or not objPos then
			return nil
		end
		local world = cam.CFrame:PointToWorldSpace(objPos)
		local v = cam:WorldToViewportPoint(world)
		return Vector2.new(v.X, v.Y)
	end

	local function waveKillIsInFront(objPos)
		return objPos ~= nil and objPos.Z < WAVE_CAM_NEAR
	end

	local function waveKillClipSegmentToNear(p0, p1)
		if not p0 or not p1 then
			return nil
		end
		local f0, f1 = waveKillIsInFront(p0), waveKillIsInFront(p1)
		if f0 and f1 then
			return p0, p1
		end
		if f0 == f1 then
			if math.abs(p1.Z) < 1e-4 then
				return nil
			end
			local t = WAVE_CAM_NEAR / p1.Z
			if t <= 0 then
				return nil
			end
			local onNear = p1 * t
			local start = onNear * 0.15
			if start.Z >= WAVE_CAM_NEAR then
				start = Vector3.new(onNear.X, onNear.Y, WAVE_CAM_NEAR - 0.05)
			end
			return start, onNear
		end
		local denom = p1.Z - p0.Z
		if math.abs(denom) < 1e-6 then
			return nil
		end
		local t = (WAVE_CAM_NEAR - p0.Z) / denom
		local hit = p0:Lerp(p1, t)
		if f0 then
			return p0, hit
		end
		return hit, p1
	end

	local function waveKillTracerScreenPoints(fromWorld, toWorld)
		local cam = workspace.CurrentCamera
		if not cam then
			return nil
		end
		local p0 = waveKillCamObjectPos(fromWorld)
		local p1 = waveKillCamObjectPos(toWorld)
		if not p0 or not p1 then
			return nil
		end
		if not waveKillIsInFront(p0) then
			p0 = Vector3.new(0, 0, WAVE_CAM_NEAR - 0.5)
		end
		local c0, c1 = waveKillClipSegmentToNear(p0, p1)
		if not c0 or not c1 then
			return nil
		end
		return waveKillObjectToScreen(c0), waveKillObjectToScreen(c1)
	end

	local function waveKillTargetWorldPos(mob, anchor, cf)
		if anchor then
			return anchor.Position + Vector3.new(0, 2, 0)
		end
		if typeof(cf) == 'CFrame' then
			return cf.Position + Vector3.new(0, 2, 0)
		end
		return nil
	end

	local function waveKillTargetFolder()
		return workspace:FindFirstChild('Mobs')
	end

	local function waveKillIsPhantomMob(mob)
		if not mob then
			return false
		end
		if mob:GetAttribute('Variant') == 'Phantom' or mob:GetAttribute('EnemyBehavior') == 'Phantom' then
			return true
		end
		if mob:GetAttribute('Phantom') == true or mob:GetAttribute('IsPhantom') == true then
			return true
		end
		return false
	end

	local function waveKillMobHighlight(mob)
		if not mob then
			return nil
		end
		local hl = mob:FindFirstChild('Highlight')
		if hl and hl:IsA('Highlight') then
			return hl
		end
		for _, d in ipairs(mob:GetDescendants()) do
			if d:IsA('Highlight') then
				return d
			end
		end
		return nil
	end

	local function waveKillMobFrozen(mob)
		if not mob then
			return true
		end
		if mob:GetAttribute('SystemFrozen') == true then
			return true
		end
		local ent = mob:FindFirstChild('Entity')
		if ent and ent:GetAttribute('SystemFrozen') == true then
			return true
		end
		local hum = mob:FindFirstChildOfClass('Humanoid')
		if hum and hum:GetAttribute('SystemFrozen') == true then
			return true
		end
		return false
	end

	local function waveKillMobIsQueuedTarget(mob)
		if not mob or not mob:IsA('Model') then
			return false
		end
		if waveKillMobFrozen(mob) then
			return false
		end
		local hl = waveKillMobHighlight(mob)
		return hl and hl.Enabled == true
	end

	local function waveKillHighlightPriority(hl)
		if not hl or hl.Enabled ~= true then
			return nil
		end
		local outline = tonumber(hl.OutlineTransparency) or 1
		local fill = tonumber(hl.FillTransparency) or 1
		return outline * 100 + fill
	end

	local function waveKillMobAnchorPart(mob)
		if not mob then
			return nil
		end
		local p = mob:FindFirstChild('HumanoidRootPart')
			or mob:FindFirstChild('Hitbox')
			or mob:FindFirstChild('Hurtbox')
			or mob.PrimaryPart
		if p and p:IsA('BasePart') then
			return p
		end
		for _, ch in ipairs(mob:GetChildren()) do
			if ch:IsA('BasePart') then
				return ch
			end
		end
		return nil
	end

	local function findWaveKillTargetMob(origin)
		local folder = waveKillTargetFolder()
		if not folder then
			return nil
		end
		local children = folder:GetChildren()
		local candidates = {}
		local phantomWave = false
		for idx, mob in ipairs(children) do
			if waveKillMobIsQueuedTarget(mob) then
				if waveKillIsPhantomMob(mob) then
					phantomWave = true
				end
				local hl = waveKillMobHighlight(mob)
				candidates[#candidates + 1] = {
					mob = mob,
					idx = idx,
					priority = waveKillHighlightPriority(hl) or 999,
				}
			end
		end
		if #candidates == 0 then
			return nil
		end
		if #candidates == 1 then
			return candidates[1].mob
		end

		local prev = getgenv().SB2WaveKillTargetTracked
		if prev and prev.Parent then
			for _, row in ipairs(candidates) do
				if row.mob == prev then
					return prev
				end
			end
		end

		-- Phantom special waves: several models can flash Highlight at once — kill order
		-- follows spawn index + strongest outline, not distance to you.
		if phantomWave then
			table.sort(candidates, function(a, b)
				if a.priority ~= b.priority then
					return a.priority < b.priority
				end
				return a.idx < b.idx
			end)
			return candidates[1].mob
		end

		local me = origin
		if typeof(me) ~= 'Vector3' then
			local model = getMyCharacterModel() or LocalPlayer.Character
			local hrp = model and model:FindFirstChild('HumanoidRootPart')
			me = hrp and hrp.Position
		end
		if typeof(me) ~= 'Vector3' then
			table.sort(candidates, function(a, b)
				if a.priority ~= b.priority then
					return a.priority < b.priority
				end
				return a.idx < b.idx
			end)
			return candidates[1].mob
		end

		local bestRow, bestD, bestIdx = nil, nil, nil
		for _, row in ipairs(candidates) do
			local mob = row.mob
			local root = waveKillMobAnchorPart(mob)
			local pos = root and root.Position
			if not pos then
				local ok, bcf = pcall(function()
					return mob:GetBoundingBox()
				end)
				if ok and typeof(bcf) == 'CFrame' then
					pos = bcf.Position
				end
			end
			if pos then
				local dx = pos.X - me.X
				local dz = pos.Z - me.Z
				local d = dx * dx + dz * dz
				if not bestD or d < bestD or (d == bestD and row.idx < (bestIdx or 999)) then
					bestD = d
					bestRow = row
					bestIdx = row.idx
				end
			elseif not bestRow then
				bestRow = row
				bestIdx = row.idx
			end
		end
		return (bestRow and bestRow.mob) or candidates[1].mob
	end

	local function waveKillTargetVariantLabel(mob)
		if not mob then
			return ''
		end
		local v = mob:GetAttribute('Variant')
		if v == nil or v == '' then
			return ''
		end
		return ' [' .. tostring(v) .. ']'
	end

	local function destroyWaveKillVis()
		local kit = getgenv().SB2WaveKillVisKit
		if kit then
			waveKillDestroyDrawing(kit.drawLine)
			waveKillDestroyDrawing(kit.drawText)
		end
		pcall(function()
			local f = workspace:FindFirstChild(WAVE_VIS_FOLDER)
			if f then
				f:Destroy()
			end
		end)
		getgenv().SB2WaveKillVisKit = nil
		getgenv().SB2WaveKillTargetTracked = nil
	end

	local function clearLegacyWaveKillHl(mob)
		if not mob or not mob.Parent then
			return
		end
		local hl = mob:FindFirstChild(WAVE_KILL_HL)
		if hl then
			pcall(function()
				hl:Destroy()
			end)
		end
	end

	local function clearAllWaveKillTargetOverlays()
		local folder = waveKillTargetFolder()
		if folder then
			for _, mob in ipairs(folder:GetChildren()) do
				clearLegacyWaveKillHl(mob)
			end
		end
		destroyWaveKillVis()
	end

	getgenv().SB2FindWaveKillTargetMob = findWaveKillTargetMob
	getgenv().SB2ClearWaveKillTargetOverlays = clearAllWaveKillTargetOverlays

	local function ensureWaveKillVisKit()
		local kit = getgenv().SB2WaveKillVisKit
		if kit and kit.folder and kit.folder.Parent then
			return kit
		end
		local folder = Instance.new('Folder')
		folder.Name = WAVE_VIS_FOLDER
		folder.Parent = workspace

		local floater = Instance.new('Part')
		floater.Name = 'Floater'
		floater.Anchored = true
		floater.CanCollide = false
		floater.CanQuery = false
		floater.CanTouch = false
		floater.CastShadow = false
		floater.Material = Enum.Material.Neon
		floater.Color = WAVE_VIS_OUTLINE
		floater.Size = Vector3.new(6, 10, 6)
		floater.Transparency = 0.55
		floater.Parent = folder

		local box = Instance.new('BoxHandleAdornment')
		box.Name = 'HitboxBox'
		box.Adornee = floater
		box.AlwaysOnTop = true
		box.ZIndex = 12
		box.Color3 = WAVE_VIS_OUTLINE
		box.Transparency = 0.25
		box.Parent = floater

		local attMob = Instance.new('Attachment')
		attMob.Name = 'MobEnd'
		attMob.Parent = floater

		local attPlayer = Instance.new('Attachment')
		attPlayer.Name = 'PlayerEnd'
		attPlayer.Parent = floater

		local beam = Instance.new('Beam')
		beam.Name = 'Tracer'
		beam.Attachment0 = attPlayer
		beam.Attachment1 = attMob
		beam.Color = ColorSequence.new(WAVE_VIS_COLOR)
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.FaceCamera = true
		beam.Width0 = 0.35
		beam.Width1 = 0.35
		beam.Transparency = NumberSequence.new(0.15)
		beam.Enabled = false
		beam.Parent = folder

		local gui = Instance.new('BillboardGui')
		gui.Name = 'Tag'
		gui.Size = UDim2.fromOffset(220, 44)
		gui.StudsOffset = Vector3.new(0, 3.2, 0)
		gui.AlwaysOnTop = true
		gui.MaxDistance = 10000
		gui.Enabled = false
		gui.Parent = floater
		local label = Instance.new('TextLabel')
		label.BackgroundTransparency = 0.25
		label.BackgroundColor3 = Color3.new(0, 0, 0)
		label.TextColor3 = WAVE_VIS_COLOR
		label.TextStrokeColor3 = Color3.new(0, 0, 0)
		label.TextStrokeTransparency = 0.15
		label.Font = Enum.Font.GothamBold
		label.TextSize = 18
		label.Size = UDim2.fromScale(1, 1)
		label.Text = 'KILL NEXT'
		label.Parent = gui

		local chams = Instance.new('Highlight')
		chams.Name = 'Chams'
		chams.FillColor = WAVE_VIS_COLOR
		chams.OutlineColor = WAVE_VIS_OUTLINE
		chams.FillTransparency = 0.35
		chams.OutlineTransparency = 0
		chams.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		chams.Enabled = false
		chams.Parent = folder

		local drawLine, drawText = nil, nil
		if WAVE_KILL_HAS_DRAWING then
			drawLine = Drawing.new('Line')
			drawLine.Thickness = 1.5
			drawLine.Color = WAVE_VIS_COLOR
			drawLine.Transparency = 1
			drawLine.Visible = false
			drawText = Drawing.new('Text')
			drawText.Size = 16
			drawText.Center = true
			drawText.Outline = true
			drawText.Color = WAVE_VIS_OUTLINE
			drawText.Visible = false
		end

		kit = {
			folder = folder,
			floater = floater,
			box = box,
			attPlayer = attPlayer,
			attMob = attMob,
			beam = beam,
			gui = gui,
			label = label,
			chams = chams,
			drawLine = drawLine,
			drawText = drawText,
			playerAttPart = nil,
		}
		getgenv().SB2WaveKillVisKit = kit
		return kit
	end

	local function hideWaveKillVis(kit)
		if not kit then
			return
		end
		kit.beam.Enabled = false
		kit.gui.Enabled = false
		kit.chams.Enabled = false
		kit.floater.Transparency = 1
		kit.box.Transparency = 1
		if kit.drawLine then
			kit.drawLine.Visible = false
		end
		if kit.drawText then
			kit.drawText.Visible = false
		end
		if kit.playerAttPart and kit.playerAttPart.Parent then
			kit.attPlayer.Parent = kit.floater
		end
	end

	local function updateWaveKillVis(mob)
		if not mob or not mob.Parent then
			hideWaveKillVis(getgenv().SB2WaveKillVisKit)
			return
		end
		local kit = ensureWaveKillVisKit()
		local myRoot = getMyBringPart()
			or (function()
				local model = getMyCharacterModel() or LocalPlayer.Character
				return model
					and (model:FindFirstChild('HumanoidRootPart') or model:FindFirstChild('UpperTorso'))
			end)()
		local anchor = waveKillMobAnchorPart(mob)
		local cf, size = nil, nil
		if anchor then
			cf = anchor.CFrame
			size = anchor.Size
		else
			local ok, bcf, bsize = pcall(function()
				return mob:GetBoundingBox()
			end)
			if ok and typeof(bcf) == 'CFrame' and typeof(bsize) == 'Vector3' then
				cf, size = bcf, bsize
			end
		end
		if not cf then
			hideWaveKillVis(kit)
			return
		end
		size = size or Vector3.new(6, 10, 6)
		kit.floater.CFrame = cf
		kit.floater.Size = Vector3.new(
			math.clamp(size.X + 1.5, 4, 40),
			math.clamp(size.Y + 2, 6, 50),
			math.clamp(size.Z + 1.5, 4, 40)
		)
		kit.floater.Transparency = 0.5
		kit.box.Size = kit.floater.Size
		kit.box.Transparency = 0.2
		kit.chams.Adornee = mob
		kit.chams.Enabled = true
		kit.label.Text = ('KILL NEXT\n%s%s'):format(mob.Name, waveKillTargetVariantLabel(mob))
		kit.gui.Enabled = true
		local useScreenTracer = false
		if myRoot and myRoot:IsA('BasePart') then
			local fromWorld = myRoot.Position
			local toWorld = waveKillTargetWorldPos(mob, anchor, cf)
			if kit.drawLine and toWorld then
				local a, b = waveKillTracerScreenPoints(fromWorld, toWorld)
				if a and b then
					kit.drawLine.Color = WAVE_VIS_COLOR
					kit.drawLine.From = a
					kit.drawLine.To = b
					kit.drawLine.Visible = true
					useScreenTracer = true
					if kit.drawText then
						kit.drawText.Text = ('KILL NEXT · %s%s'):format(
							mob.Name,
							waveKillTargetVariantLabel(mob)
						)
						kit.drawText.Position = b
						kit.drawText.Color = WAVE_VIS_OUTLINE
						kit.drawText.Visible = true
					end
				elseif kit.drawLine then
					kit.drawLine.Visible = false
				end
			elseif kit.drawLine then
				kit.drawLine.Visible = false
			end
			if kit.drawText and not useScreenTracer then
				kit.drawText.Visible = false
			end
			if kit.playerAttPart ~= myRoot then
				kit.attPlayer.Parent = myRoot
				kit.playerAttPart = myRoot
			end
			kit.attMob.Parent = kit.floater
			kit.beam.Enabled = not useScreenTracer
		else
			kit.beam.Enabled = false
			if kit.drawLine then
				kit.drawLine.Visible = false
			end
			if kit.drawText then
				kit.drawText.Visible = false
			end
		end
	end

	local function startWaveKillTargetLoop()
		getgenv().SB2WaveKillTargetOn = true
		local prev = getgenv().SB2WaveKillTargetConn
		if prev then
			pcall(function()
				prev:Disconnect()
			end)
			getgenv().SB2WaveKillTargetConn = nil
		end
		local lastScan = 0
		getgenv().SB2WaveKillTargetConn = RunService.Heartbeat:Connect(function()
			if getgenv().SB2WaveKillTargetOn ~= true or not isToggleOn('WaveKillTarget') then
				local conn = getgenv().SB2WaveKillTargetConn
				if conn then
					pcall(function()
						conn:Disconnect()
					end)
					getgenv().SB2WaveKillTargetConn = nil
				end
				clearAllWaveKillTargetOverlays()
				return
			end
			local now = os.clock()
			local target = getgenv().SB2WaveKillTargetTracked
			if now - lastScan >= 0.12 then
				lastScan = now
				target = findWaveKillTargetMob()
				local prevMob = getgenv().SB2WaveKillTargetTracked
				if prevMob and prevMob ~= target then
					clearLegacyWaveKillHl(prevMob)
				end
				getgenv().SB2WaveKillTargetTracked = target
				if target and getgenv().SB2WaveKillTargetLastName ~= target.Name then
					getgenv().SB2WaveKillTargetLastName = target.Name
					Library:Notify(
						('Wave kill target: %s%s'):format(target.Name, waveKillTargetVariantLabel(target)),
						4
					)
				end
			end
			if target and target.Parent then
				updateWaveKillVis(target)
			else
				hideWaveKillVis(getgenv().SB2WaveKillVisKit)
			end
		end)
	end

	WdBox:AddToggle('WaveKillTarget', {
		Text = 'Highlight ordered kill (WD)',
		Default = false,
		Tooltip = 'Wave Defense special / phantom order: picks the active Highlight under Workspace.Mobs (phantoms use kill-order index + outline strength, not nearest). Skips SystemFrozen on mob/Entity/Humanoid. Tracer, chams, KILL NEXT label.',
	}):OnChanged(function(value)
		getgenv().SB2WaveKillTargetOn = value == true
		getgenv().SB2WaveKillTargetLastName = nil
		local prev = getgenv().SB2WaveKillTargetConn
		if prev then
			pcall(function()
				prev:Disconnect()
			end)
			getgenv().SB2WaveKillTargetConn = nil
		end
		if not value then
			clearAllWaveKillTargetOverlays()
			return
		end
		startWaveKillTargetLoop()
	end)
	task.defer(function()
		local t = Toggles.WaveKillTarget
		if type(t) == 'table' and t.Value == true and getgenv().SB2WaveKillTargetConn == nil then
			startWaveKillTargetLoop()
		end
	end)
end
