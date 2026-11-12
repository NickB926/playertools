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
