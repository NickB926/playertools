--!nocheck
--!nolint
--[[
	BossFxLite.lua — PlayerTools module. Cuts the lag from Rubricatus' attack effects.

	What lags is the eye candy, not the attacks: dozens of lightning Beams rebuilt every frame,
	particle bursts, glow lights, ring segments and stone shards. This hides those while
	keeping each attack visible as a simple shape:
	  kept:   laser line (RedBeam), aim warning, disc surface + hub, red ground warnings,
	          falling stones, the plain red Rubricatus laser bars
	  hidden: lightning beams, trails, particles, point lights, coronas / cores / rings,
	          impact flares and shattered-stone chunks, nuke particle burst
	v3: broken-pillar rubble (thousands of small 'Pillar' pieces from the nuke) is deleted as it
	arrives; real pillars (cover) are never touched.
	v2: the lightning beams/trails are deleted (not just unhooked) a frame after they appear,
	the spike bodies + rock shards are hidden too (their red ground warnings stay), and the
	attack scripts are told to build fewer lightning branches / redraw them less often.
	Damage checks don't use any of this (they use the attack's own maths), and the parts
	AutoFloorDodge reads (discs, laser, warnings, stones) are kept. Local-only visuals.

	getgenv().SB2SetBossFxLite(true/false), getgenv().SB2BossFxLiteStop()
]]

local BUILD = 'bossfxlite-v3'
local g = getgenv()
if type(g.SB2BossFxLiteStop) == 'function' then
	pcall(g.SB2BossFxLiteStop)
end

local S = { on = false, conns = {}, folderConns = {} }
g.SB2BossFxLiteState = S
g.SB2BossFxLiteBuild = BUILD

-- Effect folders the Rubricatus client scripts parent to workspace.
local FOLDERS = {
	RedLightningLaserEffects = true,
	RedLightningEffects = true,
	RedLightningDiscEffects = true,
	RedGroundSpikes = true,
}
-- Parts that ARE the attack: keep them visible.
local KEEP = {
	RedBeam = true,
	LockedAimWarning = true,
	RedEnergySurface = true,
	DiscHub = true,
	RedGroundWarning = true,
}
-- In the spikes / stones folder: the red ground warnings + falling stones stay; spike bodies
-- (hundreds of parts each cast), eruption bits and shards go.
local GROUND_KEEP = { RedGroundWarning = true, FallingPointedStone = true }
local CLEAR = NumberSequence.new(1)

local function keptByAncestor(inst, folder)
	local cur = inst
	while cur and cur ~= folder do
		if KEEP[cur.Name] then
			return true
		end
		cur = cur.Parent
	end
	return false
end

local function hideFx(d)
	-- Beams / trails: unhook now (invisible this frame), delete next frame. The game keeps
	-- its own references and only writes properties on them afterwards, which is harmless
	-- on a deleted object; deleting can't happen inside the parenting event itself.
	if d:IsA('Beam') or d:IsA('Trail') then
		pcall(function()
			d.Attachment0 = nil
		end)
		task.defer(function()
			pcall(function()
				d:Destroy()
			end)
		end)
	elseif d:IsA('ParticleEmitter') then
		-- Emit() bursts ignore Enabled, so make the particles invisible as well.
		pcall(function()
			d.Enabled = false
			d.Transparency = CLEAR
		end)
	elseif d:IsA('Light') then
		pcall(function()
			d.Enabled = false
		end)
	end
end

local function handle(d, folder)
	if not S.on then
		return
	end
	if d:IsA('BasePart') then
		local fluff
		if folder.Name == 'RedGroundSpikes' then
			local cur, keep = d, false
			while cur and cur ~= folder do
				if GROUND_KEEP[cur.Name] then
					keep = true
					break
				end
				cur = cur.Parent
			end
			fluff = not keep
		else
			fluff = not keptByAncestor(d, folder)
		end
		if fluff then
			-- The game animates .Transparency every frame; LocalTransparencyModifier is ours.
			d.LocalTransparencyModifier = 1
			d.CastShadow = false
		end
	else
		hideFx(d)
	end
end

local function watchFolder(folder)
	if S.folderConns[folder] then
		return
	end
	for _, d in ipairs(folder:GetDescendants()) do
		handle(d, folder)
	end
	local c1 = folder.DescendantAdded:Connect(function(d)
		handle(d, folder)
	end)
	local c2
	c2 = folder.AncestryChanged:Connect(function(_, parent)
		if not parent then
			c1:Disconnect()
			c2:Disconnect()
			S.folderConns[folder] = nil
		end
	end)
	S.folderConns[folder] = { c1, c2 }
end

local function rubricatusHere()
	local mobs = workspace:FindFirstChild('Mobs')
	if not mobs then
		return false
	end
	for _, m in ipairs(mobs:GetChildren()) do
		if string.find(string.lower(m.Name), 'rubricatus', 1, true) then
			return true
		end
	end
	return false
end

-- Nuke burst / sound attachments go into workspace.Terrain: hide their particles while
-- Rubricatus is around (checked per new attachment, so other bosses are unaffected).
local function onTerrainChild(a)
	if not S.on or not a:IsA('Attachment') or not rubricatusHere() then
		return
	end
	for _, d in ipairs(a:GetDescendants()) do
		hideFx(d)
	end
	local c
	c = a.DescendantAdded:Connect(hideFx)
	task.delay(4, function()
		c:Disconnect()
	end)
end

-- Fewer lightning branches / redraws. These settings only shape the visuals (damage
-- uses the attack's own range/angle maths). Read via script:GetAttribute by the game.
local MODULE_ATTRS = {
	RedLightningLaser = { LightningRate = 4 },
	RedLightningWave = { BranchCount = 7, LightningRate = 5 },
}
local function rubSkillsFolder()
	local ok, f = pcall(function()
		return game:GetService('ReplicatedStorage').CardinalClient.MainModule.Services.EnemySkills.Skills['Wave Defense'].Bosses
	end)
	if not ok or not f then
		return nil
	end
	for _, c in ipairs(f:GetChildren()) do
		if string.find(string.lower(c.Name), 'rubricatus', 1, true) then
			return c
		end
	end
	return nil
end
local function setModuleAttrs(on)
	local folder = rubSkillsFolder()
	if not folder then
		return
	end
	S.savedAttrs = S.savedAttrs or {}
	for modName, attrs in pairs(MODULE_ATTRS) do
		local mod = folder:FindFirstChild(modName)
		if mod then
			for k, v in pairs(attrs) do
				local key = modName .. '.' .. k
				pcall(function()
					if on then
						if S.savedAttrs[key] == nil then
							S.savedAttrs[key] = { v = mod:GetAttribute(k) }
						end
						mod:SetAttribute(k, v)
					elseif S.savedAttrs[key] then
						mod:SetAttribute(k, S.savedAttrs[key].v)
					end
				end)
			end
		end
	end
	if not on then
		S.savedAttrs = {}
	end
end

-- Pillar rubble: when the nuke breaks the pillars the server sends ~3,500 small pieces named
-- 'Pillar' in under 2s (FPS 19-20 for ~5s after). Delete them locally as they arrive, a few
-- hundred per frame. Real pillars are never touched: rising ones are 13x46x13, standing ones
-- 26x137x26 (the dodge hides behind those); anything under ~1000 studs^3 is rubble.
local RUBBLE_MAX_VOLUME = 1000
local rubbleQueue = {}
local rubbleConn = nil
local function isRubble(p)
	if not p:IsA('BasePart') then
		return false
	end
	local sz = p.Size
	return sz.X * sz.Y * sz.Z < RUBBLE_MAX_VOLUME
end
local function queueRubble(p)
	rubbleQueue[#rubbleQueue + 1] = p
	pcall(function()
		p.LocalTransparencyModifier = 1
	end)
	if rubbleConn then
		return
	end
	rubbleConn = game:GetService('RunService').Heartbeat:Connect(function()
		local n = 0
		while #rubbleQueue > 0 and n < 300 do
			local q = table.remove(rubbleQueue)
			pcall(function()
				if q.Parent then
					q:Destroy()
				end
			end)
			n += 1
		end
		if #rubbleQueue == 0 and rubbleConn then
			rubbleConn:Disconnect()
			rubbleConn = nil
		end
	end)
end
local function onPillarChild(ch)
	if ch.Name ~= 'Pillar' then
		return
	end
	if ch:IsA('BasePart') then
		if isRubble(ch) then
			queueRubble(ch)
		end
	elseif ch:IsA('Model') or ch:IsA('Folder') then
		-- Broken pillar delivered as a container of pieces.
		for _, d in ipairs(ch:GetDescendants()) do
			if isRubble(d) then
				queueRubble(d)
			end
		end
		S.conns[#S.conns + 1] = ch.DescendantAdded:Connect(function(d)
			if S.on and isRubble(d) then
				queueRubble(d)
			end
		end)
	end
end
S.rubbleStats = function()
	return #rubbleQueue
end

local function start()
	if S.on then
		return
	end
	S.on = true
	setModuleAttrs(true)
	S.conns[#S.conns + 1] = workspace.ChildAdded:Connect(function(ch)
		if S.on and ch.Name == 'Pillar' then
			onPillarChild(ch)
		end
	end)
	for _, ch in ipairs(workspace:GetChildren()) do
		if FOLDERS[ch.Name] then
			watchFolder(ch)
		end
	end
	S.conns[#S.conns + 1] = workspace.ChildAdded:Connect(function(ch)
		if FOLDERS[ch.Name] then
			watchFolder(ch)
		elseif ch:IsA('BasePart') and ch.Name == 'Part' then
			-- RubricatusLasers parts land straight in workspace: keep them (they're the
			-- attack), just stop them casting shadows.
			pcall(function()
				ch.CastShadow = false
			end)
		end
	end)
	local terrain = workspace:FindFirstChildOfClass('Terrain')
	if terrain then
		S.conns[#S.conns + 1] = terrain.ChildAdded:Connect(onTerrainChild)
	end
end

local function stop()
	S.on = false
	setModuleAttrs(false)
	for _, c in ipairs(S.conns) do
		pcall(function()
			c:Disconnect()
		end)
	end
	S.conns = {}
	for _, pair in pairs(S.folderConns) do
		for _, c in ipairs(pair) do
			pcall(function()
				c:Disconnect()
			end)
		end
	end
	S.folderConns = {}
	-- Effects already hidden expire on their own within a couple of seconds.
end

g.SB2SetBossFxLite = function(on)
	if on then
		start()
	else
		stop()
	end
	return S.on
end
g.SB2BossFxLiteStop = stop

return g.SB2SetBossFxLite
