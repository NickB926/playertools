--!nocheck
--!nolint
--[[
	HitFxLite.lua — PlayerTools module. Two optional, local-only lag cuts:

	  SB2SetHitFxLite(on)  hides hit sparks (workspace.HitEffects) and turns the game's own
	                       damage-number setting off while on (restored when turned off).
	  SB2SetMapFxLite(on)  turns off the map's static particles / beams / trails that exist
	                       when it is switched on (torches, smoke, glow strips). Anything
	                       spawned later (attacks, warnings, skills) is never touched, nor are
	                       players, mobs or boss attack folders. Restored when turned off.

	Nothing is destroyed; the game keeps running its code. SB2HitFxLiteStop() undoes both.
]]

local BUILD = 'hitfxlite-v1'
local g = getgenv()
if type(g.SB2HitFxLiteStop) == 'function' then
	pcall(g.SB2HitFxLiteStop)
end

local Players = game:GetService('Players')
local RS = game:GetService('ReplicatedStorage')
local CLEAR = NumberSequence.new(1)

local H = { on = false, conns = {}, dmgWas = nil }
local M = { on = false, saved = {} }
g.SB2HitFxLiteBuild = BUILD

-- ── hit sparks + damage numbers ─────────────────────────────────────────────

local function dmgFlag()
	local lp = Players.LocalPlayer
	local profiles = RS:FindFirstChild('Profiles')
	local prof = lp and profiles and profiles:FindFirstChild(lp.Name)
	local settings = prof and prof:FindFirstChild('Settings')
	local f = settings and settings:FindFirstChild('DamageIndicators')
	return (f and f:IsA('BoolValue')) and f or nil
end

local function hideHit(d)
	pcall(function()
		if d:IsA('ParticleEmitter') then
			d.Enabled = false
			d.Transparency = CLEAR
		elseif d:IsA('Beam') or d:IsA('Trail') then
			d.Enabled = false
		elseif d:IsA('Light') then
			d.Enabled = false
		elseif d:IsA('BillboardGui') or d:IsA('SurfaceGui') then
			d.Enabled = false
		elseif d:IsA('BasePart') then
			d.LocalTransparencyModifier = 1
			d.CastShadow = false
		elseif d:IsA('Sound') then
			-- leave sounds alone
		end
	end)
end

local function watchHitFolder(folder)
	for _, d in ipairs(folder:GetDescendants()) do
		hideHit(d)
	end
	H.conns[#H.conns + 1] = folder.DescendantAdded:Connect(function(d)
		if H.on then
			hideHit(d)
		end
	end)
end

local function hitStart()
	if H.on then
		return
	end
	H.on = true
	g.SB2HitFxLiteOn = true
	local f = dmgFlag()
	if f then
		H.dmgWas = f.Value
		f.Value = false
		-- The game may write it back from the server; keep it off while we're on.
		H.conns[#H.conns + 1] = f.Changed:Connect(function()
			if H.on and f.Value ~= false then
				f.Value = false
			end
		end)
	end
	local he = workspace:FindFirstChild('HitEffects')
	if he then
		watchHitFolder(he)
	end
	H.conns[#H.conns + 1] = workspace.ChildAdded:Connect(function(ch)
		if H.on and ch.Name == 'HitEffects' then
			watchHitFolder(ch)
		end
	end)
end

local function hitStop()
	if not H.on then
		return
	end
	H.on = false
	g.SB2HitFxLiteOn = false
	for _, c in ipairs(H.conns) do
		pcall(function()
			c:Disconnect()
		end)
	end
	H.conns = {}
	local f = dmgFlag()
	if f and H.dmgWas ~= nil then
		pcall(function()
			f.Value = H.dmgWas
		end)
	end
	H.dmgWas = nil
	-- Sparks already hidden fade out on their own.
end

-- ── static map particles / beams / trails ───────────────────────────────────

-- Never touch these top-level workspace children (or anything under them).
local MAP_SKIP = {
	Characters = true, Mobs = true, Camera = true, HitEffects = true, Terrain = true,
	RedLightningLaserEffects = true, RedLightningEffects = true,
	RedLightningDiscEffects = true, RedGroundSpikes = true,
	Circle = true, EffectHitbox = true, Box = true, DarknerOrb = true,
}

local function mapStart()
	if M.on then
		return 0
	end
	M.on = true
	g.SB2MapFxLiteOn = true
	local players = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			players[p.Character] = true
		end
	end
	local n = 0
	for _, top in ipairs(workspace:GetChildren()) do
		if MAP_SKIP[top.Name] or players[top] or top:IsA('Camera') or top:IsA('Terrain') then
			continue
		end
		if top:FindFirstChildOfClass('Humanoid') then
			continue
		end
		for _, d in ipairs(top:GetDescendants()) do
			local cls = d.ClassName
			if (cls == 'ParticleEmitter' or cls == 'Beam' or cls == 'Trail'
				or cls == 'Fire' or cls == 'Smoke' or cls == 'Sparkles')
				and not d:FindFirstAncestor('LavaHazardRegion')
				and not d:FindFirstAncestor('WaveDefenseRifts')
			then
				if d.Enabled then
					local ok = pcall(function()
						d.Enabled = false
					end)
					if ok then
						M.saved[#M.saved + 1] = d
						n += 1
					end
				end
			end
		end
	end
	return n
end

local function mapStop()
	if not M.on then
		return
	end
	M.on = false
	g.SB2MapFxLiteOn = false
	for _, d in ipairs(M.saved) do
		pcall(function()
			if d.Parent then
				d.Enabled = true
			end
		end)
	end
	M.saved = {}
end

g.SB2SetHitFxLite = function(on)
	if on then
		hitStart()
	else
		hitStop()
	end
	return H.on
end
g.SB2SetMapFxLite = function(on)
	if on then
		return mapStart()
	end
	mapStop()
	return 0
end
g.SB2HitFxLiteStop = function()
	hitStop()
	mapStop()
end

return g.SB2SetHitFxLite
