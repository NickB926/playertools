--[[
	ForgeTools.lua — The Forge (Roblox) helper with an Ataraxia window.
	  • Auto mine   — tweens to rocks and mines them with the game's own swing.
	  • Auto sell   — tweens to Greedy Cey and sells your ores when the bag is getting full.
	  • Auto forge  — tweens to the forge, puts in your ores and plays every minigame perfectly.
	  • Auto mobs   — tweens to mobs (the Living folder) and fights them with your Weapon.
	Movement is always a tween (no long teleports — the game snaps those back).
	Needs workspace/PlayerTools/AtaraxiaLibrary.lua. Autoload: autoexec/03_forgetools.lua.
]]

local BUILD = 'forge-tools-v35'
local G = getgenv()
local compile = loadstring or load

if not game:IsLoaded() then
	game.Loaded:Wait()
end
local Players = game:GetService('Players')
local RunService = game:GetService('RunService')
local TweenService = game:GetService('TweenService')
local HttpService = game:GetService('HttpService')
local RS = game:GetService('ReplicatedStorage')
local LocalPlayer = Players.LocalPlayer

if type(G.SB2ForgeToolsUnload) == 'function' then
	pcall(G.SB2ForgeToolsUnload)
end
G.SB2ForgeToolsLoaded = true
G.SB2ForgeToolsBuild = BUILD

local alive = true
local conns = {}
local function track(c)
	conns[#conns + 1] = c
	return c
end

---------------------------------------------------------------------------
-- Game modules
---------------------------------------------------------------------------
local Knit = require(RS:WaitForChild('Shared'):WaitForChild('Packages'):WaitForChild('Knit'))
local function controller(name)
	local ok, c = pcall(Knit.GetController, name)
	return ok and c or nil
end
local function service(name)
	local ok, s = pcall(Knit.GetService, name)
	return ok and s or nil
end
local PlayerController
repeat
	PlayerController = controller('PlayerController')
	task.wait(0.5)
until PlayerController and PlayerController.Replica or not alive
local function data()
	return PlayerController and PlayerController.Replica and PlayerController.Replica.Data
end

local ORE_NAMES = {}
pcall(function()
	for _, v in pairs(require(RS.Shared.Data.Ore)) do
		if type(v) == 'table' and v.Name then
			ORE_NAMES[v.Name] = v.Rarity or 'Common'
		end
	end
end)

---------------------------------------------------------------------------
-- Settings (per account)
---------------------------------------------------------------------------
local ACCT = string.lower(tostring(LocalPlayer.Name)):gsub('[^%w_]', '')
local SETTINGS_PATH = 'PlayerTools/forgetools_' .. ACCT .. '.json'
local settings = {}
pcall(function()
	settings = HttpService:JSONDecode(readfile(SETTINGS_PATH))
end)
if type(settings) ~= 'table' then
	settings = {}
end
local defaults = {
	autoMine = false,
	mineZone = 'Any',
	skipLucky = false,
	autoSell = false,
	sellAt = 90,
	autoForge = false,
	forgeType = 'Weapon',
	forgeOres = 3,
	forgeKeep = 0,
	switchMins = 3,
	autoAcceptQuests = false,
	autoCompleteQuests = false,
	questBuy = false,
	claimBoard = false,
	autoBlock = false,
	autoMail = false,
	autoOffer = false,
	autoCodes = false,
	autoDaily = false,
	parryLead = 20,
	forgeBest = false,
	questRange = 1000,
	noBlur = false,
	combatStyle = 'Hit & run',
	autoAbyss = false,
	dodgeDist = 16,
	autoMobs = false,
	mobFilter = 'Any',
	retreatHp = 45,
	maxMobHp = 80,
	autoEquip = false,
	tweenSpeed = 55,
	autoload = true,
	focusQuest = 'Auto',
	keepOres = {},
	autoCards = false,
	cardFocus = 'Best overall',
	allowCursed = false,
}
for k, v in pairs(defaults) do
	if settings[k] == nil then
		settings[k] = v
	end
end
if settings.combatStyle == 'Float above' then
	settings.combatStyle = 'Hit & run' -- tested: mobs hit straight up, so floating doesn't protect you
end
local function save()
	pcall(writefile, SETTINGS_PATH, HttpService:JSONEncode(settings))
end
save()

---------------------------------------------------------------------------
-- Character / movement
---------------------------------------------------------------------------
local function char()
	local c = LocalPlayer.Character
	local hrp = c and c:FindFirstChild('HumanoidRootPart')
	local hum = c and c:FindFirstChildOfClass('Humanoid')
	return c, hrp, hum
end

local noclip = false
track(RunService.Stepped:Connect(function()
	if not noclip then
		return
	end
	local c = LocalPlayer.Character
	if not c then
		return
	end
	for _, p in ipairs(c:GetDescendants()) do
		if p:IsA('BasePart') and p.CanCollide then
			p.CanCollide = false
		end
	end
end))

local currentTween
local function stopTween()
	if currentTween then
		pcall(function()
			currentTween:Cancel()
		end)
		currentTween = nil
	end
	noclip = false
end

-- Tween the character to a CFrame. Returns true when it got there.
local function tweenTo(cf, opts)
	opts = opts or {}
	local _, hrp, hum = char()
	if not hrp or not hum or hum.Health <= 0 then
		return false
	end
	if typeof(cf) == 'Vector3' then
		cf = CFrame.new(cf)
	end
	local dist = (cf.Position - hrp.Position).Magnitude
	if dist < 1.5 then
		hrp.CFrame = cf
		return true
	end
	stopTween()
	noclip = true
	local speed = math.max(10, tonumber(settings.tweenSpeed) or 55)
	local tw = TweenService:Create(hrp, TweenInfo.new(dist / speed, Enum.EasingStyle.Linear), { CFrame = cf })
	currentTween = tw
	local hold = RunService.Heartbeat:Connect(function()
		if hrp.Parent then
			hrp.AssemblyLinearVelocity = Vector3.zero
		end
	end)
	tw:Play()
	local done = false
	local c2 = tw.Completed:Connect(function()
		done = true
	end)
	local deadline = os.clock() + dist / speed + 3
	while not done and alive and os.clock() < deadline do
		if opts.abort and opts.abort() then
			break
		end
		task.wait()
	end
	c2:Disconnect()
	hold:Disconnect()
	if not done then
		pcall(function()
			tw:Cancel()
		end)
	end
	currentTween = nil
	noclip = false
	return done
end

local function standNear(part, gap)
	local _, hrp = char()
	local p = part.Position
	local dir = hrp and ((hrp.Position - p) * Vector3.new(1, 0, 1)) or Vector3.new(1, 0, 0)
	dir = dir.Magnitude > 0.1 and dir.Unit or Vector3.new(1, 0, 0)
	local r = math.max(part.Size.X, part.Size.Z) / 2 + (gap or 2)
	local pos = p + dir * r
	return CFrame.lookAt(pos, Vector3.new(p.X, pos.Y, p.Z))
end

local function equip(toolName)
	local c, _, hum = char()
	if not c or not hum then
		return nil
	end
	local held = c:FindFirstChildWhichIsA('Tool')
	if held and held.Name == toolName then
		return held
	end
	local t = LocalPlayer.Backpack:FindFirstChild(toolName)
	if not t then
		return nil
	end
	hum:EquipTool(t)
	task.wait(0.3)
	return c:FindFirstChild(toolName)
end

local function swing(tool)
	local TC = controller('ToolController')
	if TC and tool then
		task.spawn(function()
			pcall(function()
				TC:ToolActivated(tool)
			end)
		end)
	end
end

---------------------------------------------------------------------------
-- Inventory helpers
---------------------------------------------------------------------------
local function oreCounts()
	local d = data()
	local out, total = {}, 0
	if not d or type(d.Inventory) ~= 'table' then
		return out, 0
	end
	local reserve = type(G.FTReserve) == 'table' and G.FTReserve or {}
	for k, v in pairs(d.Inventory) do
		if ORE_NAMES[k] and type(v) == 'number' and v > 0
			and not (type(settings.keepOres) == 'table' and settings.keepOres[k]) then
			-- Ores a quest needs delivered ("Bring Monke 30 bananite") are kept out of forging / selling.
			local n = v - (tonumber(reserve[k]) or 0)
			if n > 0 then
				out[k] = n
				total += n
			end
		end
	end
	return out, total
end

local function bagCapacity()
	local used, cap
	pcall(function()
		for _, x in ipairs(LocalPlayer.PlayerGui.Hotbar:GetDescendants()) do
			if x:IsA('TextLabel') then
				local a, b = string.match(x.Text, 'Capacity%s*%((%d+)%s*/%s*(%d+)%)')
				if a then
					used, cap = tonumber(a), tonumber(b)
				end
			end
		end
	end)
	return used, cap
end

---------------------------------------------------------------------------
-- Status
---------------------------------------------------------------------------
local _statusText = 'idle'
local statusLabel
local statusLog = {}
local lastProgress = os.clock()
local function setStatus(t)
	if t ~= _statusText then
		lastProgress = os.clock()
		statusLog[#statusLog + 1] = os.date('%H:%M:%S ') .. tostring(t)
		if #statusLog > 300 then
			table.remove(statusLog, 1)
		end
	end
	_statusText = t
	G.FTStatus = t
	if statusLabel and statusLabel.SetText then
		pcall(statusLabel.SetText, statusLabel, 'Status: ' .. t)
	end
end
local stats = { mined = 0, sold = 0, forged = 0, kills = 0 }

---------------------------------------------------------------------------
-- Mining
---------------------------------------------------------------------------
local tooStrong = {} -- rock type name -> true (pickaxe did no damage)
local MineHooks = {} -- .clear(pos) is filled in by the mob code: kill mobs around a rock first

-- Living mobs within radius of a position: count, list.
local function mobsNear(pos, radius)
	local living = workspace:FindFirstChild('Living')
	local list = {}
	if not living then
		return 0, list
	end
	for _, m in ipairs(living:GetChildren()) do
		if m:GetAttribute('IsNpc') and not Players:GetPlayerFromCharacter(m) then
			local h = m:FindFirstChildOfClass('Humanoid')
			local r = m:FindFirstChild('HumanoidRootPart') or m.PrimaryPart
			if h and r and h.Health > 0 then
				local d = (r.Position - pos).Magnitude
				if d <= radius then
					list[#list + 1] = { m = m, h = h, r = r, d = d }
				end
			end
		end
	end
	table.sort(list, function(a, b)
		return a.d < b.d
	end)
	return #list, list
end

local function rockList()
	local _, hrp = char()
	local list = {}
	local rocks = workspace:FindFirstChild('Rocks')
	if not rocks or not hrp then
		return list
	end
	for _, zone in ipairs(rocks:GetChildren()) do
		if settings.mineZone == 'Any' or settings.mineZone == zone.Name then
			for _, sp in ipairs(zone:GetChildren()) do
				local m = sp:FindFirstChildWhichIsA('Model')
				local hb = m and m:FindFirstChild('Hitbox')
				local hp = m and m:GetAttribute('Health')
				if hb and type(hp) == 'number' and hp > 0 and not tooStrong[m.Name]
					and not ((settings.skipLucky or G.FTQuestWantsOre) and string.find(m.Name, 'Lucky', 1, true))
				then
					-- Rocks with mobs around them count as much farther away, so clear ones win.
					local danger = mobsNear(hb.Position, 22)
					local d = (hb.Position - hrp.Position).Magnitude
					local want = G.FTQuestRock and m.Name == G.FTQuestRock and -350 or 0 -- quest asks for this rock type
					list[#list + 1] = { m = m, hb = hb, d = d, danger = danger, score = d + danger * 400 + want }
				end
			end
		end
	end
	table.sort(list, function(a, b)
		return a.score < b.score
	end)
	return list
end

local function mineOnce()
	local pick = LocalPlayer.Backpack:FindFirstChild('Pickaxe') or (LocalPlayer.Character and LocalPlayer.Character:FindFirstChild('Pickaxe'))
	if not pick then
		setStatus('no pickaxe')
		return false
	end
	local target = rockList()[1]
	if not target then
		setStatus('no rocks to mine in ' .. tostring(settings.mineZone))
		return false
	end
	if (target.danger or 0) > 0 and MineHooks.clear then
		-- Every reachable rock has mobs on it: kill those first, then mine.
		if MineHooks.clear(target.hb.Position) then
			return true
		end
	end
	setStatus(('mining %s (%.0f studs)'):format(target.m.Name, target.d))
	if not tweenTo(standNear(target.hb, 2), { abort = function()
		return not settings.autoMine or not target.m.Parent
	end }) then
		return true
	end
	local tool = equip('Pickaxe')
	local lastHp, lastChange = target.m:GetAttribute('Health'), os.clock()
	while alive and (settings.autoMine or G.FTQuestWantsOre) and target.m.Parent do
		local hp = target.m:GetAttribute('Health') or 0
		if hp <= 0 then
			stats.mined += 1
			break
		end
		if hp ~= lastHp then
			lastHp, lastChange = hp, os.clock()
		elseif os.clock() - lastChange > 4 then
			-- No damage for 4s: pickaxe too weak for this rock type.
			tooStrong[target.m.Name] = true
			setStatus(target.m.Name .. ' too strong for your pickaxe — skipping that type')
			break
		end
		local _, hrp = char()
		if hrp and (hrp.Position - target.hb.Position).Magnitude > math.max(target.hb.Size.X, target.hb.Size.Z) / 2 + 6 then
			break -- knocked away
		end
		swing(tool)
		task.wait(0.35)
	end
	return true
end

---------------------------------------------------------------------------
-- Selling (Greedy Cey)
---------------------------------------------------------------------------
local function sellNeeded()
	if not settings.autoSell then
		return false
	end
	local used, cap = bagCapacity()
	local _, total = oreCounts()
	if total <= 0 then
		return false
	end
	if used and cap and cap > 0 then
		return used / cap * 100 >= (tonumber(settings.sellAt) or 90)
	end
	return total >= 30
end

local function sellOres()
	local npc = workspace:FindFirstChild('Proximity') and workspace.Proximity:FindFirstChild('Greedy Cey')
	if not npc then
		setStatus('Greedy Cey not found')
		return false
	end
	local ores = oreCounts()
	local keep = settings.autoForge and math.max(0, tonumber(settings.forgeKeep) or 0) or 0
	local basket, count = {}, 0
	for name, n in pairs(ores) do
		local sell = n - keep
		if sell > 0 then
			basket[name] = sell
			count += sell
		end
	end
	if count == 0 then
		return false
	end
	setStatus(('selling %d ores'):format(count))
	local p = npc:GetPivot().Position
	local _, hrp = char()
	local dir = hrp and ((hrp.Position - p) * Vector3.new(1, 0, 1)) or Vector3.new(1, 0, 0)
	dir = dir.Magnitude > 0.1 and dir.Unit or Vector3.new(1, 0, 0)
	if not tweenTo(CFrame.lookAt(p + dir * 5, Vector3.new(p.X, p.Y, p.Z))) then
		return false
	end
	task.wait(0.3)
	local PS, DS = service('ProximityService'), service('DialogueService')
	local goldBefore = (data() or {}).Gold or 0
	pcall(function()
		PS:ForceDialogue(npc, 'SellConfirmMisc')
	end)
	task.wait(0.5)
	pcall(function()
		DS:RunCommand('SellConfirm', { Basket = basket })
	end)
	task.wait(1)
	-- Close the dialogue the sell opened.
	pcall(function()
		local ui = controller('UIController')
		if ui and ui.Modules and ui.Modules.Dialogue and ui.Modules.Dialogue.Close then
			ui.Modules.Dialogue:Close()
		end
	end)
	local gained = ((data() or {}).Gold or 0) - goldBefore
	stats.sold += count
	setStatus(('sold %d ores for %s gold'):format(count, tostring(math.floor(gained * 100) / 100)))
	return true
end

---------------------------------------------------------------------------
-- Forging (perfect minigames)
---------------------------------------------------------------------------
local hooked = false
local function hookMinigames(FC)
	if hooked or not FC.Minigames then
		return FC.Minigames ~= nil
	end
	local M = FC.Minigames
	local function finishTime(startTime, wait)
		local offset = workspace:GetServerTimeNow() - startTime
		task.wait(wait)
		return workspace:GetServerTimeNow() - offset
	end
	if M.MeltMinigame then
		M.MeltMinigame.Start = function(_, d)
			local t = finishTime(d.StartTime, (tonumber(d.RequiredTime) or 2) + 0.6)
			pcall(function()
				local ui = controller('UIController')
				for _, v in pairs(ui.Modules.Forge.physicalOres or {}) do
					v:Destroy()
				end
			end)
			return t, true
		end
	end
	if M.PourMinigame then
		M.PourMinigame.Start = function(_, d)
			return finishTime(d.StartTime, (tonumber(d.RequiredTime) or 2) + 0.4), true
		end
	end
	if M.HammerMinigame then
		-- Every note is "clicked" exactly on the beat (Lifetime * 25/44 after it appears).
		M.HammerMinigame.CreateNote = function(_, note)
			task.wait((tonumber(note.Lifetime) or 1) * 25 / 44)
			return true
		end
		-- Before the notes, the hammer waits for 3 clicks on the mould to break it open.
		-- Keep the game's original across reloads so wrappers never stack.
		G.FTOrigHammerStart = G.FTOrigHammerStart or M.HammerMinigame.Start
		local origStart = G.FTOrigHammerStart
		M.HammerMinigame.Start = function(self, d)
			task.spawn(function()
				local t0 = os.clock()
				while os.clock() - t0 < 15 do
					local mold
					for _, c in ipairs(workspace.Debris:GetChildren()) do
						if c.Name == 'Mold' and c:GetAttribute('IsDestroyed') ~= true and c:FindFirstChild('ClickDetector') then
							mold = c
						end
					end
					if mold then
						task.wait(0.3)
						for _ = 1, 3 do
							local cd = mold:FindFirstChild('ClickDetector')
							if not cd then
								break
							end
							local fired = false
							pcall(function()
								for _, conn in ipairs(getconnections(cd.MouseClick)) do
									conn:Fire()
									fired = true
								end
							end)
							if not fired then
								pcall(fireclickdetector, cd)
							end
							task.wait(0.2)
						end
						return
					end
					task.wait(0.1)
				end
			end)
			return origStart(self, d)
		end
	end
	hooked = true
	return true
end

-- What the active quests want from farming (filled in by the quest module each step).
local QS = { wantMobs = false, wantMine = false, storyMobs = false, storyMine = false, mobTarget = nil }

-- Active quest that wants something forged ("Forge Weapon 1/2") -> 'Weapon' / 'Armor', else nil.
local function questForgeType()
	if not settings.autoCompleteQuests then
		return nil
	end
	local d = data()
	for _, q in pairs(d and d.Quests or {}) do
		for _, p in ipairs(type(q) == 'table' and q.Progress or {}) do
			if type(p) == 'table' and p.questType == 'Forge'
				and (tonumber(p.currentProgress) or 0) < (tonumber(p.requiredAmount) or 0) then
				return (p.target == 'Armor') and 'Armor' or 'Weapon'
			end
		end
	end
	return nil
end
local function forgeTypeNow()
	return questForgeType() or settings.forgeType
end

local function forgeNeeded()
	local _, total = oreCounts()
	if questForgeType() then
		return total >= 3
	end
	if not settings.autoForge then
		return false
	end
	local need = math.max(3, tonumber(settings.forgeOres) or 3)
	if settings.forgeBest and need <= 3 then
		need = 20 -- wait for enough ores to make something bigger than a dagger
	end
	return total >= need
end

-- Mining vs mobs when both are on: take turns in blocks so ores still come in.
-- A pending forge quest with too few ores always mines.
-- Quests can switch farming on by themselves (kill X zombies / get Y ore).
local turnStart, turnMobs = os.clock(), true
local function chooseFarm()
	local mobs = settings.autoMobs or QS.wantMobs
	local mine = settings.autoMine or QS.wantMine
	if questForgeType() then
		local _, total = oreCounts()
		if total < 3 then
			return 'mine'
		end
	end
	if mobs and mine then
		-- Story quests (one-time) beat repeatable ones like "Rotten Depths".
		if QS.storyMine ~= QS.storyMobs then
			return QS.storyMine and 'mine' or 'mobs'
		end
		if QS.wantMobs ~= QS.wantMine then
			return QS.wantMobs and 'mobs' or 'mine'
		end
		local mins = math.max(1, tonumber(settings.switchMins) or 3)
		if os.clock() - turnStart >= mins * 60 then
			turnStart, turnMobs = os.clock(), not turnMobs
		end
		return turnMobs and 'mobs' or 'mine'
	end
	return (mobs and 'mobs') or (mine and 'mine') or nil
end

-- "Best gear" ore picking. Item strength = base stat of the item type x the AVERAGE multiplier of
-- the ores used x quality. More ores unlock bigger item types (Dagger 4.3 dmg ... Colossal Sword 20),
-- but adding weak ores drags the average multiplier down. So: rank ores by multiplier, and for every
-- ore count N take the N best ores and score  avgMultiplier(N) x expectedBaseStat(N), using the
-- game's own type odds (ItemRarity:CalculateProbabilities). Pick the N with the best score.
local Best = {}
do
	local multCache, neutral = nil, {}
	local function oreMult(name)
		if not multCache then
			multCache = {}
			pcall(function()
				for _, o in pairs(require(RS.Shared.Data.Ore)) do
					if type(o) == 'table' and o.Name then
						multCache[o.Name] = tonumber(o.Multiplier) or 0
						neutral[o.Name] = o.NeutralMultiplier == true
					end
				end
			end)
		end
		return multCache[name] or 0, neutral[name]
	end
	local baseCache = {}
	local function expectedBase(itemType, n)
		local key = itemType .. n
		if baseCache[key] then
			return baseCache[key]
		end
		local ev = 0
		pcall(function()
			local IR = require(RS.Shared.ItemRarity)
			local E = require(RS.Shared.Data.Equipments)
			local d = data()
			local okS, st = pcall(IR.ResolveStation, IR, 'Island1', d)
			if not okS then
				local f = workspace:FindFirstChild('Proximity') and workspace.Proximity:FindFirstChild('Forge')
				st = f and f:FindFirstChild('Station') and f.Station.Value and f.Station.Value.Name or 'Island1'
			end
			local okD, SD = pcall(IR.GetStationData, IR, st, itemType)
			local list = {}
			for _, v in ipairs(IR[itemType] or {}) do
				local ok = not (okD and type(SD) == 'table' and not SD[v.name])
				if ok then
					local okA, a = pcall(IR.GetAvailableItems, IR, st, itemType, v.name, d)
					if okA and type(a) == 'table' and #a == 0 then
						ok = false
					end
				end
				if ok then
					list[#list + 1] = v
				end
			end
			for _, p in ipairs(IR:CalculateProbabilities(n, list)) do
				local pr = tonumber(p.probability or p.chance or p.Probability) or 0
				if pr == 0 then
					for k, v in pairs(p) do
						if type(v) == 'number' and k ~= 'min_ores' and k ~= 'lock_min_ores' and k ~= 'base_weight' and k ~= 'scaling_factor' and k ~= 'current_weight' then
							pr = v
						end
					end
				end
				pr = pr > 1 and pr / 100 or pr
				local bt = E.BaseTypes[p.name]
				local stat = 0
				if bt and bt.Damage then
					stat = bt.Damage
				elseif bt and type(bt.Types) == 'table' then
					local sum, c = 0, 0
					for _, t in ipairs(bt.Types) do
						local a = E.Items.Armor and E.Items.Armor[t]
						if a and a.Health then
							sum += a.Health
							c += 1
						end
					end
					stat = c > 0 and sum / c or 0
				end
				ev += pr * stat
			end
		end)
		baseCache[key] = ev
		return ev
	end

	-- Returns pick {ore = n}, count, score. The forge takes at most 4 different ore types, so try
	-- every set of up to 4 of your best ore types and every ore count, and keep the best score.
	function Best.pick(itemType, maxOres)
		local types = {}
		for name, n in pairs((oreCounts())) do
			local m, neu = oreMult(name)
			if not neu and n > 0 then
				types[#types + 1] = { name = name, m = m, n = n }
			end
		end
		table.sort(types, function(a, b)
			return a.m > b.m
		end)
		while #types > 12 do
			table.remove(types) -- only the 12 strongest types are worth combining
		end
		local best = { score = -1 }
		local chosen = {}
		local function evaluate()
			-- ores of the chosen types, strongest first
			local list = {}
			for _, t in ipairs(chosen) do
				list[#list + 1] = t
			end
			table.sort(list, function(a, b)
				return a.m > b.m
			end)
			local sum, n = 0, 0
			local used = {}
			for _, t in ipairs(list) do
				for _ = 1, t.n do
					if n >= maxOres then
						break
					end
					n += 1
					sum += t.m
					used[t.name] = (used[t.name] or 0) + 1
					-- every type in the set must actually be used, else it's a smaller set (tried separately)
					local all = true
					for _, c in ipairs(list) do
						if not used[c.name] then
							all = false
							break
						end
					end
					if n >= 3 and all then
						local score = (sum / n) * expectedBase(itemType, n)
						if score > best.score then
							local pick = {}
							for k, v in pairs(used) do
								pick[k] = v
							end
							best = { score = score, pick = pick, n = n }
						end
					end
				end
			end
		end
		local function combos(start, depth)
			if depth > 0 then
				evaluate()
			end
			if depth == 4 then
				return
			end
			for i = start, #types do
				chosen[#chosen + 1] = types[i]
				combos(i + 1, depth + 1)
				chosen[#chosen] = nil
			end
		end
		combos(1, 0)
		if not best.pick then
			return {}, 0
		end
		return best.pick, best.n, best.score
	end
end

local function pickForgeOres(itemType)
	-- A quest that just wants "forge something" (auto forge off): use the 3 cheapest ores,
	-- don't burn your good ones on it.
	if not settings.autoForge and questForgeType() then
		local units = {}
		local okO, OreMod = pcall(function()
			return require(RS.Shared.Data.Ore)
		end)
		local mult = {}
		for _, o in pairs(okO and OreMod or {}) do
			if type(o) == 'table' and o.Name then
				mult[o.Name] = tonumber(o.Multiplier) or 0
			end
		end
		for name, n in pairs((oreCounts())) do
			for _ = 1, n do
				units[#units + 1] = { name = name, m = mult[name] or 0 }
			end
		end
		table.sort(units, function(a, b)
			return a.m < b.m
		end)
		local pick, got = {}, 0
		for i = 1, math.min(3, #units) do
			pick[units[i].name] = (pick[units[i].name] or 0) + 1
			got += 1
		end
		return pick, got
	end
	if settings.forgeBest then
		-- Slider left at the old default (3) would cap "best" at a dagger: treat <=3 as "no cap" (60).
		local cap = tonumber(settings.forgeOres) or 3
		cap = cap > 3 and cap or 60
		local pick, got = Best.pick(itemType or settings.forgeType, cap)
		if got >= 3 then
			return pick, got
		end
	end
	local want = math.max(3, tonumber(settings.forgeOres) or 3)
	local ores = oreCounts()
	local list = {}
	for name, n in pairs(ores) do
		list[#list + 1] = { name = name, n = n }
	end
	-- Most plentiful first, so common ore gets used up.
	table.sort(list, function(a, b)
		return a.n > b.n
	end)
	local pick, got, kinds = {}, 0, 0
	for _, e in ipairs(list) do
		if got >= want or kinds >= 4 then -- the forge takes at most 4 ore types
			break
		end
		kinds += 1
		local take = math.min(e.n, want - got)
		pick[e.name] = take
		got += take
	end
	return pick, got
end

-- Auto equip: put on any forged item that beats what's in its slot (empty slot, more ores, or
-- same ores with higher quality).
-- Rank items by what they actually do: the game's own damage (weapons) / health (armor) maths,
-- including ore multiplier, quality and enhancement.
local function itemScore(e)
	if type(e) ~= 'table' then
		return 0
	end
	local v = 0
	pcall(function()
		local E = require(RS.Shared.Data.Equipments)
		local slot = E:GetItemType(e.Type or e.Name)
		if slot == 'Weapon' then
			local a, b = E:CalculateDamage(e)
			v = tonumber(b or a) or 0
		elseif slot == 'Armor' then
			local a, b = E:CalculateHealth(e)
			v = tonumber(b or a) or 0
		end
	end)
	return v
end
local function autoEquipBest(force)
	if not settings.autoEquip and not force then
		return
	end
	local d = data()
	if not d or not d.Inventory then
		return
	end
	local okMod, Equip = pcall(function()
		return require(RS.Shared.Data.Equipments)
	end)
	if not okMod or not Equip then
		return
	end
	-- Weapon, or the armor piece (Helmet / Chestplate / Leggings) — each is its own slot.
	local function slotKey(e)
		local ok, t = pcall(Equip.GetItemType, Equip, e.Type or e.Name)
		if not ok or t == 'Pickaxe' or type(t) ~= 'string' then
			return nil
		end
		if t ~= 'Armor' then
			return t
		end
		local okB, base = pcall(Equip.GetItemBaseType, Equip, e.Type or e.Name)
		base = tostring(okB and base or e.Type)
		for _, piece in ipairs({ 'Helmet', 'Chestplate', 'Leggings' }) do
			if base:find(piece) or tostring(e.Type):find(piece) then
				return piece
			end
		end
		return 'Armor:' .. base
	end
	local best = {}
	for _, e in ipairs(d.Inventory.Equipments or {}) do
		if type(e) == 'table' and e.Type and e.GUID then
			local key = slotKey(e)
			if key and (not best[key] or itemScore(e) > itemScore(best[key])) then
				best[key] = e
			end
		end
	end
	local worn = {}
	for _, w in pairs(d.Equipped or {}) do
		if type(w) == 'table' and w.GUID then
			local key = slotKey(w)
			if key then
				worn[key] = w
			end
		end
	end
	for key, e in pairs(best) do
		local cur = worn[key]
		if not (cur and cur.GUID == e.GUID) and (not cur or itemScore(e) > itemScore(cur) + 0.01) then
			pcall(function()
				return service('CharacterService'):EquipItem(e)
			end)
			setStatus(('equipped %s (%.1f vs %.1f)'):format(tostring(e.Type), itemScore(e), cur and itemScore(cur) or 0))
			task.wait(0.5)
		end
	end
end

local function forgeOnce()
	local FC = controller('ForgeController')
	local forge = workspace:FindFirstChild('Proximity') and workspace.Proximity:FindFirstChild('Forge')
	if not FC or not forge then
		setStatus('forge not found')
		return false
	end
	local itemType = forgeTypeNow()
	local ores, got = pickForgeOres(itemType)
	if got < 3 then
		return false
	end
	setStatus(('forging a %s from %d ores'):format(itemType, got))
	if not tweenTo(standNear(forge, 3)) then
		return false
	end
	task.wait(0.3)
	-- A forge left "open" on our side (e.g. from before a reload) is often already closed on the
	-- server, which then rejects every forge: close it and open a fresh one.
	if FC.ForgeActive and (FC.Sequence == 'OreSelect' or FC.Sequence == 'Close') then
		pcall(function()
			FC:EndForge()
		end)
		task.wait(1.5)
	end
	if not FC.ForgeActive then
		pcall(function()
			service('ProximityService'):Forge(forge)
		end)
		local t0 = os.clock()
		while not FC.ForgeActive and os.clock() - t0 < 8 do
			task.wait(0.2)
		end
	end
	if not FC.ForgeActive then
		setStatus('forge did not open')
		return false
	end
	local t1 = os.clock()
	while not FC.Minigames and os.clock() - t1 < 5 do
		task.wait(0.2)
	end
	hookMinigames(FC)
	task.wait(1.2) -- let the ore-select screen settle
	local before = #(((data() or {}).Inventory or {}).Equipments or {})
	FC.Ores = ores
	FC.ItemType = itemType
	task.spawn(function()
		pcall(function()
			FC:ChangeSequence('Melt')
		end)
	end)
	-- Wait for the new item to land in the inventory (or give up after 90s).
	local t2 = os.clock()
	local ok = false
	local rejected = false
	while alive and os.clock() - t2 < 90 do
		local now = #(((data() or {}).Inventory or {}).Equipments or {})
		if now > before then
			ok = true
			break
		end
		-- The server refused to start (the game drops back to ore select): stop waiting.
		if os.clock() - t2 > 6 and FC.Sequence == 'OreSelect' then
			rejected = true
			break
		end
		task.wait(0.5)
	end
	if rejected then
		setStatus('forge was rejected — reopening it next time')
	end
	task.wait(2)
	pcall(function()
		FC:EndForge()
	end)
	pcall(function()
		local ui = controller('UIController')
		if ui and ui.Modules and ui.Modules.Forge and ui.Modules.Forge.Close then
			ui.Modules.Forge:Close()
		end
	end)
	-- Closing the forge from code can leave the forge screen's blur on: clear it once it's closed.
	task.delay(1.5, function()
		local FC2 = controller('ForgeController')
		if not (FC2 and FC2.ForgeActive) then
			pcall(function()
				local b = game:GetService('Lighting'):FindFirstChild('ForgeBlur')
				if b and b:IsA('BlurEffect') then
					b.Size = 0
				end
			end)
		end
	end)
	if ok then
		stats.forged += 1
		setStatus('forged a ' .. itemType)
		task.wait(1)
		pcall(autoEquipBest)
	else
		setStatus('forge timed out')
	end
	return ok
end

---------------------------------------------------------------------------
-- Mobs
---------------------------------------------------------------------------
local function baseName(n)
	return (string.gsub(n, '%d+$', ''))
end
-- Mob attack warning. Every mob gets a BoolValue "Attacking" ~0.6s before its hit lands (then a
-- "ParryWindow" attachment ~0.35s before). Tested on island 2 slimes: stepping out when "Attacking"
-- appears and coming back ~1s later took 0 damage over 6 attacks in a row.
local attackWarn = {} -- [mob model] = os.clock() when its attack started
pcall(function()
	if G.FTAttackWarnConn then
		G.FTAttackWarnConn:Disconnect()
	end
	G.FTAttackWarnConn = workspace:WaitForChild('Living', 10).DescendantAdded:Connect(function(d)
		if d.Name == 'Attacking' and d:IsA('ValueBase') then
			local m = d.Parent
			while m and m.Parent ~= workspace.Living do
				m = m.Parent
			end
			if m then
				attackWarn[m] = os.clock()
			end
		end
	end)
end)
local ATTACK_WINDOW = 1.0 -- seconds from "Attacking" until the swing is over
local function mobRoot(m)
	return m:FindFirstChild('HumanoidRootPart') or m.PrimaryPart or m:FindFirstChild('Head')
		or m:FindFirstChild('Torso') or m:FindFirstChildWhichIsA('BasePart')
end
-- Closest mob (within radius) whose attack is winding up right now -> its position, time it ends.
local function attackThreat(radius)
	local _, hrp = char()
	if not hrp then
		return nil
	end
	local now = os.clock()
	local bestPos, bestEnd, bestD
	for m, t in pairs(attackWarn) do
		if now - t > ATTACK_WINDOW or not m.Parent then
			attackWarn[m] = nil
		else
			local r = mobRoot(m)
			local d = r and (r.Position - hrp.Position).Magnitude
			if d and d <= radius and (not bestD or d < bestD) then
				bestPos, bestEnd, bestD = r.Position, t + ATTACK_WINDOW, d
			end
		end
	end
	return bestPos, bestEnd
end
-- "Slime" also matches variants like "Blazing Slime"; "Skeleton Rogue" matches "Elite Rogue Skeleton".
local function mobMatches(name, filter)
	if filter == nil or filter == 'Any' then
		return true
	end
	name = string.lower(name)
	if name == string.lower(filter) then
		return true
	end
	for word in string.gmatch(string.lower(filter), '%S+') do
		if not string.find(' ' .. name .. ' ', ' ' .. word .. ' ', 1, true) then
			return false
		end
	end
	return true
end

local function mobList()
	local _, hrp = char()
	local living = workspace:FindFirstChild('Living')
	local list = {}
	if not living or not hrp then
		return list
	end
	local players = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			players[p.Character] = true
		end
	end
	-- A saved "Target" that doesn't live on this island (e.g. Zombie after moving to island 2)
	-- used to leave it idle forever: fall back to any mob.
	local filter = QS.mobTarget or settings.mobFilter
	if filter ~= 'Any' then
		local exists = false
		for _, m in ipairs(living:GetChildren()) do
			if m:GetAttribute('IsNpc') and mobMatches(baseName(m.Name), filter) then
				exists = true
				break
			end
		end
		if not exists then
			filter = 'Any'
		end
	end
	for _, m in ipairs(living:GetChildren()) do
		if not players[m] and m:GetAttribute('IsNpc') then
			local h = m:FindFirstChildOfClass('Humanoid')
			local r = mobRoot(m)
			local cap = tonumber(settings.maxMobHp) or 0
			if h and r and h.Health > 0 and m:GetAttribute('KillCredited') ~= true
				and mobMatches(baseName(m.Name), filter)
				and (cap <= 0 or h.MaxHealth <= cap)
				and h.MaxHealth < 1e8 and not m.Name:find('Dummy') -- training dummies never die
			then
				list[#list + 1] = { m = m, h = h, r = r, d = (r.Position - hrp.Position).Magnitude }
			end
		end
	end
	table.sort(list, function(a, b)
		return a.d < b.d
	end)
	return list
end

local function lowHp()
	local _, _, hum = char()
	return hum and hum.MaxHealth > 0 and hum.Health / hum.MaxHealth * 100 < (tonumber(settings.retreatHp) or 35)
end

-- Low health: tween back to spawn (mobs don't follow that far) and wait to heal to 90%.
local function retreatAndHeal()
	local spawn = workspace:FindFirstChild('SpawnLocation')
	if spawn and spawn:IsA('BasePart') then
		setStatus('low health — retreating to spawn')
		tweenTo(spawn.CFrame + Vector3.new(0, spawn.Size.Y / 2 + 3, 0))
	end
	local t0 = os.clock()
	while alive and (settings.autoMobs or QS.wantMobs) and os.clock() - t0 < 120 do
		local _, _, hum = char()
		if not hum or hum.Health <= 0 then
			return
		end
		local pct = hum.MaxHealth > 0 and hum.Health / hum.MaxHealth * 100 or 100
		if pct >= 90 then
			return
		end
		setStatus(('healing at spawn (%.0f%%)'):format(pct))
		task.wait(1)
	end
end

-- Auto block / parry. Mobs play a wind-up animation, then the hit lands. The parry window is
-- a short time before the hit, so it learns each attack animation's hit time (from when damage /
-- the Parry / BlockHit effect actually happens) and starts the block "parry lead" before it.
local Block = {}
do
	local blockUntil = 0
	if type(G.FTBlockConns) == 'table' then
		for _, c in ipairs(G.FTBlockConns) do
			pcall(function()
				c:Disconnect()
			end)
		end
	end
	local blockConns = {}
	G.FTBlockConns = blockConns
	local hookedAnims = setmetatable({}, { __mode = 'k' })
	G.FTHitDelay = G.FTHitDelay or {} -- [animation id] = seconds from wind-up start to the hit
	local hitDelay = G.FTHitDelay
	local pending = {} -- recent attack wind-ups near us: { id, t }

	-- A hit / parry just happened: credit it to the most recent wind-up 0.2-1.6 s ago.
	local function learn()
		local now = os.clock()
		local bi
		for i, p in ipairs(pending) do
			local dt = now - p.t
			if dt > 0.2 and dt < 1.6 and (not bi or p.t > pending[bi].t) then
				bi = i
			end
		end
		if bi then
			local p = table.remove(pending, bi)
			local dt = now - p.t
			local old = hitDelay[p.id]
			hitDelay[p.id] = old and (old * 0.6 + dt * 0.4) or dt
		end
		for i = #pending, 1, -1 do
			if now - pending[i].t > 2 then
				table.remove(pending, i)
			end
		end
	end
	pcall(function()
		blockConns[#blockConns + 1] = workspace:WaitForChild('Debris', 5).ChildAdded:Connect(function(x)
			if x.Name == 'Parry' or x.Name == 'BlockHit' then
				learn()
			end
		end)
	end)
	local hpConn, hpChar
	local function watchHealth()
		local c, _, hum = char()
		if c and hum and c ~= hpChar then
			hpChar = c
			if hpConn then
				hpConn:Disconnect()
			end
			local last = hum.Health
			hpConn = hum.HealthChanged:Connect(function(h)
				if h < last - 0.5 then
					learn()
				end
				last = h
			end)
			blockConns[#blockConns + 1] = hpConn
		end
	end

	local stopping = false
	local function holdBlock(untilT)
		local tc = controller('ToolController')
		local ch = LocalPlayer.Character
		if not tc or not (ch and ch:FindFirstChild('Weapon')) then
			return
		end
		blockUntil = math.max(blockUntil, untilT)
		if not tc.isBlocking then
			pcall(tc.StartBlock, tc)
		end
		if stopping then
			return
		end
		stopping = true
		task.spawn(function()
			while os.clock() < blockUntil and alive do
				task.wait()
			end
			stopping = false
			if tc.isBlocking then
				pcall(tc.StopBlock, tc)
			end
		end)
	end

	local function onAnim(m, track)
		if not alive then
			return
		end
		local t0 = os.clock()
		local len = track.Length
		if len <= 0 then
			task.wait(0.05)
			len = track.Length
		end
		if len < 0.9 then
			return -- short clips are hit reactions, not attacks
		end
		local c, hrp = char()
		local r = m:FindFirstChild('HumanoidRootPart') or m.PrimaryPart
		if not (c and hrp and r) or (r.Position - hrp.Position).Magnitude > 24 then
			return
		end
		local id = tostring(track.Animation and track.Animation.AnimationId or track.Name)
		local hitAt = hitDelay[id] or math.min(0.9, len * 0.55)
		pending[#pending + 1] = { id = id, t = t0, m = m, r = r, hitAt = hitAt }
		-- Block / parry style only (hit & run dodges instead).
		if settings.combatStyle ~= 'Block / parry' or not settings.autoBlock or not c:FindFirstChild('Weapon') then
			return
		end
		if (r.Position - hrp.Position).Magnitude > 16 then
			return
		end
		local lead = (tonumber(settings.parryLead) or 20) / 100
		local startIn = math.max(0, hitAt - lead) - (os.clock() - t0)
		task.delay(math.max(0, startIn), function()
			holdBlock(t0 + hitAt + 0.3)
		end)
	end
	-- Soonest incoming hit from a mob within radius: returns attacker position, seconds until it lands.
	function Block.threat(radius)
		local now = os.clock()
		local _, hrp = char()
		if not hrp then
			return nil
		end
		local bestPos, bestRem
		for i = #pending, 1, -1 do
			local p = pending[i]
			local rem = p.t + (hitDelay[p.id] or p.hitAt) - now
			if rem < -0.35 or now - p.t > 2.5 then
				if now - p.t > 2.5 then
					table.remove(pending, i)
				end
			elseif p.m.Parent and p.r.Parent then
				local h = p.m:FindFirstChildOfClass('Humanoid')
				if (not h or h.Health > 0) and (p.r.Position - hrp.Position).Magnitude <= radius then
					if not bestRem or rem < bestRem then
						bestPos, bestRem = p.r.Position, rem
					end
				end
			end
		end
		return bestPos, bestRem
	end
	local function hook(m)
		if hookedAnims[m] or not m:GetAttribute('IsNpc') then
			return
		end
		local h = m:FindFirstChildOfClass('Humanoid') or m:FindFirstChildOfClass('AnimationController')
		local an = h and h:FindFirstChildOfClass('Animator')
		if not an then
			return
		end
		hookedAnims[m] = true
		blockConns[#blockConns + 1] = an.AnimationPlayed:Connect(function(track)
			task.spawn(onAnim, m, track)
		end)
	end
	local living = workspace:FindFirstChild('Living')
	if living then
		for _, m in ipairs(living:GetChildren()) do
			task.spawn(hook, m)
		end
	end
	-- Mobs respawn and their Animator can show up late: keep hooking new ones.
	task.spawn(function()
		while alive and G.FTBlockConns == blockConns do
			local lv = workspace:FindFirstChild('Living')
			for _, m in ipairs(lv and lv:GetChildren() or {}) do
				if not hookedAnims[m] then
					pcall(hook, m)
				end
			end
			pcall(watchHealth)
			task.wait(2)
		end
	end)
	function Block.active()
		return os.clock() < blockUntil
	end
	function Block.hold(seconds)
		holdBlock(os.clock() + math.max(0.1, tonumber(seconds) or 0.5))
	end
end

-- Hit & run: step out of reach just before a hit lands, toward open floor away from other mobs.
local dodgeParams = RaycastParams.new()
dodgeParams.FilterType = Enum.RaycastFilterType.Exclude
local function dodgeFrom(fromPos)
	local c, hrp = char()
	if not hrp then
		return false
	end
	local filter = { c }
	local living = workspace:FindFirstChild('Living')
	if living then
		filter[#filter + 1] = living
	end
	local debris = workspace:FindFirstChild('Debris')
	if debris then
		filter[#filter + 1] = debris
	end
	dodgeParams.FilterDescendantsInstances = filter
	local dist = tonumber(settings.dodgeDist) or 16
	local away = (hrp.Position - fromPos) * Vector3.new(1, 0, 1)
	if away.Magnitude < 0.2 then
		away = -hrp.CFrame.LookVector * Vector3.new(1, 0, 1)
	end
	away = away.Unit
	local _, near = mobsNear(hrp.Position, 40)
	local best, bestScore
	for _, ang in ipairs({ 0, 30, -30, 60, -60, 90, -90, 135, -135 }) do
		local a = math.rad(ang)
		local dir = Vector3.new(away.X * math.cos(a) - away.Z * math.sin(a), 0, away.X * math.sin(a) + away.Z * math.cos(a))
		local target = hrp.Position + dir * dist
		-- clear path (no wall) and floor under the landing spot
		local wall = workspace:Raycast(hrp.Position, dir * dist, dodgeParams)
		local floor = workspace:Raycast(target + Vector3.new(0, 8, 0), Vector3.new(0, -30, 0), dodgeParams)
		if not wall and floor then
			local score = math.huge
			for _, e in ipairs(near) do
				score = math.min(score, (e.r.Position - target).Magnitude)
			end
			score -= math.abs(ang) * 0.02 -- prefer straight back
			if not bestScore or score > bestScore then
				best, bestScore = floor.Position + Vector3.new(0, 3, 0), score
			end
		end
	end
	if not best then
		return false
	end
	hrp.CFrame = CFrame.lookAt(best, Vector3.new(fromPos.X, best.Y, fromPos.Z))
	hrp.AssemblyLinearVelocity = Vector3.zero
	return true
end

local function weaponReach()
	local reach = 6
	pcall(function()
		local w = data().Equipped.Weapon
		local E = require(RS.Shared.Data.Equipments)
		local base = E.BaseTypes[E:GetItemBaseType(w.Type)]
		reach = tonumber(base and base.Info and base.Info.Range) or reach
	end)
	return reach
end

local function fightOnce(forced)
	local function allowed()
		return forced ~= nil or settings.autoMobs or QS.wantMobs
	end
	if not (LocalPlayer.Backpack:FindFirstChild('Weapon') or (LocalPlayer.Character and LocalPlayer.Character:FindFirstChild('Weapon'))) then
		setStatus('no weapon — forge one first')
		return false
	end
	if lowHp() then
		retreatAndHeal()
		return true
	end
	local target = forced or mobList()[1]
	if not target then
		setStatus('no mobs found')
		return false
	end
	setStatus(('fighting %s (%.0f studs)'):format(target.m.Name, target.d))
	local tool = equip('Weapon')
	local t0 = os.clock()
	while alive and allowed() and target.m.Parent and target.h.Health > 0 and os.clock() - t0 < 30 do
		if lowHp() then
			retreatAndHeal()
			return true
		end
		local _, hrp = char()
		local reach = weaponReach()
		local threatPos, rem
		if settings.combatStyle == 'Hit & run' then
			-- The game's own attack warning first, learned animation timing as a fallback.
			local wPos, wEnd = attackThreat(reach + 14)
			if wPos then
				threatPos, rem = wPos, 0
				G.FTWarnEnd = wEnd
			else
				threatPos, rem = Block.threat(reach + 10)
				G.FTWarnEnd = nil
			end
		elseif settings.combatStyle == 'Block / parry' and settings.autoBlock then
			-- Hold block for the whole warned swing (halves the hit, parries it when the timing lines up).
			local wPos, wEnd = attackThreat(reach + 6)
			if wPos then
				Block.hold(wEnd - os.clock())
			end
		end
		if threatPos and rem and rem < 0.45 then
			-- A hit is about to land: get out of reach, wait for the swing to whiff, then go back in.
			setStatus(('dodging (%s)'):format(target.m.Name))
			dodgeFrom(threatPos)
			local untilT = G.FTWarnEnd or (os.clock() + math.max(0, rem) + 0.3)
			while alive and os.clock() < untilT do
				task.wait()
				-- if something else winds up meanwhile, keep moving
				local w2, e2 = attackThreat(10)
				if w2 and e2 > untilT then
					dodgeFrom(w2)
					untilT = e2
				end
				local p2, r2 = Block.threat(8)
				if p2 and r2 and r2 < 0.3 then
					dodgeFrom(p2)
					untilT = math.max(untilT, os.clock() + math.max(0, r2) + 0.3)
				end
			end
		elseif hrp and (hrp.Position - target.r.Position).Magnitude > reach + 1 then
			local stand = math.max(1.5, reach - 2.5)
			if settings.combatStyle == 'Hit & run' and (hrp.Position - target.r.Position).Magnitude < 30 then
				-- short hop straight back into range (faster than a tween)
				local cf = standNear(target.r, stand)
				hrp.CFrame = cf
				hrp.AssemblyLinearVelocity = Vector3.zero
			else
				tweenTo(standNear(target.r, stand), { abort = function()
					return not allowed() or not target.m.Parent or target.h.Health <= 0
				end })
			end
			tool = equip('Weapon')
		else
			if hrp then
				hrp.CFrame = CFrame.lookAt(hrp.Position, Vector3.new(target.r.Position.X, hrp.Position.Y, target.r.Position.Z))
			end
			if Block.active() then
				task.wait(0.05) -- holding block through an incoming hit
			else
				swing(tool)
				task.wait(0.25)
			end
		end
	end
	if not target.m.Parent or target.h.Health <= 0 then
		stats.kills += 1
	end
	return true
end

-- Mining safety: clear the mobs standing around a rock before mining it.
MineHooks.clear = function(pos)
	if not (LocalPlayer.Backpack:FindFirstChild('Weapon') or (LocalPlayer.Character and LocalPlayer.Character:FindFirstChild('Weapon'))) then
		return false -- no weapon: just mine
	end
	local n, list = mobsNear(pos, 22)
	if n == 0 then
		return false
	end
	setStatus(('clearing %d mob(s) near the rock first'):format(n))
	fightOnce(list[1])
	return true
end

---------------------------------------------------------------------------
-- Quests: accept from NPCs, work the objectives, turn in, claim quest-board rewards
---------------------------------------------------------------------------
local Quest = {}
do
	local QuestData, ShopData, DialogueNpcs, Functionals
	pcall(function()
		QuestData = require(RS.Shared.Data.Quests)
	end)
	pcall(function()
		local P = require(RS.Shared.Data.Proximities)
		ShopData, DialogueNpcs, Functionals = P.Shop, P.Dialogue, P.Functionals
	end)

	-- Which dialogue tree the server opened last (the game sends it on DialogueRemote).
	local lastTree
	pcall(function()
		if G.FTDialogueConn then
			G.FTDialogueConn:Disconnect()
		end
		G.FTDialogueConn = RS.DialogueEvents.DialogueRemote.OnClientEvent:Connect(function(tree)
			if typeof(tree) == 'Instance' then
				lastTree = tree
			end
		end)
	end)
	local function closeDialogue()
		pcall(function()
			getsenv(LocalPlayer.PlayerGui.DialogueUI.DialogueHandler).Close()
		end)
	end

	-- Commands a dialogue tree can send: give (accept a quest), check / finish (turn in).
	local cmdCache = setmetatable({}, { __mode = 'k' })
	local function treeCommands(tree)
		if cmdCache[tree] then
			return cmdCache[tree]
		end
		local out = { give = {}, check = {}, finish = {} }
		for _, node in ipairs(tree:GetDescendants()) do
			local typ = node:IsA('Configuration') and node:GetAttribute('Type')
			local ms = (typ == 'Command' or typ == 'Condition') and node:FindFirstChildWhichIsA('ModuleScript')
			if ms then
				local ok, mod = pcall(require, ms)
				local fn = ok and type(mod) == 'table' and mod.Run
				local okc, consts = false, nil
				if type(fn) == 'function' then
					okc, consts = pcall(debug.getconstants, fn)
				end
				for _, c in ipairs(okc and consts or {}) do
					if type(c) == 'string' and c ~= 'RunCommand' then
						if c:match('^Give') or c:match('^Accept') or c:match('^Start') then
							out.give[#out.give + 1] = { cmd = c, quest = node:GetAttribute('GivesQuest') }
						elseif c:match('^Check') then
							out.check[#out.check + 1] = c
						elseif c:match('^Finish') or c:match('^Complete') or c:match('^TurnIn') then
							out.finish[#out.finish + 1] = c
						end
					end
				end
			end
		end
		cmdCache[tree] = out
		return out
	end

	local function norm(s)
		return (string.lower(tostring(s)):gsub('[^%a]', ''))
	end
	local function npcModel(name)
		local prox = workspace:FindFirstChild('Proximity')
		if not prox or not name then
			return nil
		end
		local m = prox:FindFirstChild(name)
		if m then
			return m
		end
		-- "Sensei Moro 2" is a different NPC (Island 2) from "Sensei Moro": a name with a number
		-- only matches exactly, never the un-numbered NPC on this island.
		if tostring(name):match('%d') then
			return nil
		end
		local key = norm(name)
		for _, c in ipairs(prox:GetChildren()) do
			if norm(c.Name) == key then
				return c
			end
		end
		return nil
	end
	local function goTo(model)
		local ok, pos = pcall(function()
			return model:GetPivot().Position
		end)
		if not ok then
			return false
		end
		local _, hrp = char()
		if hrp and (hrp.Position - pos).Magnitude < 9 then
			return true
		end
		return tweenTo(CFrame.new(pos + Vector3.new(0, 1, 5)))
	end

	local function eligible(id)
		local d = data()
		local q = QuestData and QuestData[id]
		if not d or not q then
			return false
		end
		if (d.Quests or {})[id] then
			return false
		end
		if (d.CompletedQuests or {})[id] and not q.Repeatable then
			return false
		end
		for k, v in pairs(d.CooldownQuests or {}) do
			if k == id or v == id then
				return false
			end
		end
		return true
	end
	local function questDone(qd)
		for _, p in ipairs(qd.Progress or {}) do
			if (tonumber(p.currentProgress) or 0) < (tonumber(p.requiredAmount) or 1) then
				return false
			end
		end
		return true
	end

	local DS, PS = service('DialogueService'), service('ProximityService')
	-- Kept in getgenv so a reload doesn't send it on a full NPC tour again.
	G.FTQuestTreeOf = G.FTQuestTreeOf or {}
	G.FTQuestVisited = G.FTQuestVisited or {}
	local backoff = {} -- [npc|reason] = { n = useless visits, t = last }
	-- Fingerprint of all quest progress, to tell whether a visit did anything.
	local function questSig()
		local d = data()
		local parts = {}
		for id, qd in pairs(d and d.Quests or {}) do
			local p = {}
			for _, x in ipairs(type(qd) == 'table' and qd.Progress or {}) do
				p[#p + 1] = tostring(x.currentProgress)
			end
			parts[#parts + 1] = tostring(id) .. ':' .. table.concat(p, ',')
		end
		table.sort(parts)
		return table.concat(parts, ';')
	end
	local treeOf = G.FTQuestTreeOf -- [npc name] = last tree it opened
	local visited = G.FTQuestVisited -- [npc name] = os.clock() of last accept visit

	-- Walk to an NPC, open its dialogue and send the useful commands.
	local function visit(name, why)
		local npc = npcModel(name)
		if not npc then
			return false
		end
		-- Talked to them twice for this reason and nothing changed: leave them alone for 5 min.
		local bk = npc.Name .. '|' .. why
		local b = backoff[bk]
		if b and b.n >= 2 and os.clock() - b.t < 300 then
			return false
		end
		local before = questSig()
		setStatus(('quest: %s (%s)'):format(npc.Name, why))
		if not goTo(npc) then
			return false
		end
		-- The game ignores a new dialogue while the last one is still closing.
		pcall(function()
			local ui = LocalPlayer.PlayerGui:FindFirstChild('DialogueUI')
			local t1 = os.clock()
			while ui and ui.Enabled and os.clock() - t1 < 2 do
				task.wait(0.1)
			end
		end)
		lastTree = nil
		local ok, opened = pcall(function()
			return PS:Dialogue(npc)
		end)
		local t0 = os.clock()
		while not lastTree and os.clock() - t0 < 2 do
			task.wait(0.1)
		end
		local tree = lastTree
		visited[npc.Name] = os.clock()
		if not tree then
			closeDialogue()
			return ok and opened ~= false
		end
		treeOf[npc.Name] = tree
		local cmds = treeCommands(tree)
		task.wait(0.3)
		for _, c in ipairs(cmds.check) do
			pcall(function()
				DS:RunCommand(c)
			end)
			task.wait(0.2)
		end
		for _, c in ipairs(cmds.finish) do
			pcall(function()
				DS:RunCommand(c)
			end)
			task.wait(0.2)
		end
		if settings.autoAcceptQuests then
			for _, g in ipairs(cmds.give) do
				if g.quest and eligible(g.quest) then
					pcall(function()
						DS:RunCommand(g.cmd)
					end)
					setStatus('accepted quest ' .. tostring(g.quest))
					task.wait(0.3)
				end
			end
		end
		task.wait(0.3)
		closeDialogue()
		task.wait(0.5)
		if questSig() == before then
			backoff[bk] = { n = (b and b.n or 0) + 1, t = os.clock() }
		else
			backoff[bk] = nil
		end
		return true
	end

	local function equipBestPickaxe()
		local d = data()
		local best, bestPrice
		for _, e in ipairs(d and d.Inventory and d.Inventory.Equipments or {}) do
			local name = type(e) == 'table' and (e.Name or e.Type)
			local shop = name and ShopData and ShopData[name]
			if shop and tostring(name):find('Pickaxe') and (not bestPrice or (shop.Price or 0) > bestPrice) then
				best, bestPrice = e, shop.Price or 0
			end
		end
		local cur = d and d.Equipped and d.Equipped.Pickaxe
		if best and not (type(cur) == 'table' and (cur.Name or cur.Type) == (best.Name or best.Type)) then
			pcall(function()
				service('CharacterService'):EquipItem(best)
			end)
			setStatus('equipped ' .. tostring(best.Name or best.Type))
		end
	end

	local function buy(item, qty)
		qty = math.max(1, tonumber(qty) or 1)
		local shop = ShopData and ShopData[item]
		local d = data()
		if not shop or not d or (d.Gold or 0) < (shop.Price or math.huge) * qty then
			setStatus(('quest: need %s gold for %s'):format(tostring(shop and shop.Price or '?'), item))
			return false
		end
		local stand = npcModel(item)
		if not stand or not goTo(stand) then
			return false
		end
		setStatus(('buying %d x %s (%s gold each)'):format(qty, item, tostring(shop.Price)))
		pcall(function()
			PS:Purchase(item, qty)
		end)
		task.wait(1)
		if item:find('Pickaxe') then
			equipBestPickaxe()
		end
		return true
	end

	local function sellSpare(target)
		local d = data()
		local okMod, Equip = pcall(function()
			return require(RS.Shared.Data.Equipments)
		end)
		if not d or not okMod then
			return false
		end
		local equippedGuid = {}
		for _, e in pairs(d.Equipped or {}) do
			if type(e) == 'table' and e.GUID then
				equippedGuid[e.GUID] = true
			end
		end
		local worst
		for _, e in ipairs(d.Inventory.Equipments or {}) do
			if type(e) == 'table' and e.GUID and not equippedGuid[e.GUID] and not e.Favorite and not e.Favorited then
				local okT, slot = pcall(Equip.GetItemType, Equip, e.Type or e.Name)
				if okT and slot ~= 'Pickaxe' and (target == 'Any' or target == 'Equipment' or slot == target) then
					if not worst or itemScore(e) < itemScore(worst) then
						worst = e
					end
				end
			end
		end
		if not worst then
			return false
		end
		local npc = npcModel('Marbles')
		if not npc or not goTo(npc) then
			return false
		end
		setStatus(('quest: selling spare %s'):format(tostring(worst.Type)))
		pcall(function()
			PS:ForceDialogue(npc, 'SellConfirm')
		end)
		task.wait(0.5)
		pcall(function()
			DS:RunCommand('SellConfirm', { Basket = { [worst.GUID] = true } })
		end)
		task.wait(0.8)
		closeDialogue()
		return true
	end


	-- "Bring X to NPC" quests (Lost Guitar, Lost Cat): pick up the NPC's item (a Functionals prop
	-- named NPC..Item, e.g. BardGuitar) and then talk to the NPC.
	local extraAt = {}
	local function extraFetch(npcName)
		if os.clock() - (extraAt[npcName] or 0) < 45 then
			return false
		end
		extraAt[npcName] = os.clock()
		local d = data()
		local misc = d and d.MiscDialogues or {}
		local prox = workspace:FindFirstChild('Proximity')
		local key = norm(npcName)
		local found = false
		for name in pairs(Functionals or {}) do
			if norm(name):sub(1, #key) == key and norm(name) ~= key then
				if misc['Took' .. name] then
					found = true
				else
					local inst = prox and prox:FindFirstChild(name)
					if inst and goTo(inst) then
						setStatus('quest: picking up ' .. name)
						pcall(function()
							PS:Functionals(inst)
						end)
						task.wait(1.2)
						found = true
					end
				end
			end
		end
		if not found then
			-- No item to pick up (e.g. "deliver the supplies to Gurak"): just talk to them.
			if npcModel(npcName) then
				return visit(npcName, 'deliver')
			end
			return false -- NPC / item isn't on this island
		end
		return visit(npcName, 'deliver')
	end

	-- "Enhance any item to +N": enhance the equipped weapon at the Enhancer.
	local enhanceAt = 0
	local function enhanceTo(level)
		if os.clock() - enhanceAt < 60 then
			return false
		end
		enhanceAt = os.clock()
		local d = data()
		local w = d and d.Equipped and d.Equipped.Weapon
		if type(w) ~= 'table' or not w.GUID or (tonumber(w.Upgrade) or 0) >= level then
			return false
		end
		local npc = npcModel('Enhancer')
		if not npc or not goTo(npc) then
			return false
		end
		local ES = service('EnhanceService')
		local function have(name)
			local inv = data().Inventory
			if type(inv[name]) == 'number' then
				return inv[name]
			end
			for _, it in ipairs(inv.Misc or {}) do
				if it.Name == name then
					return tonumber(it.Quantity) or 0
				end
			end
			return 0
		end
		for _ = 1, 15 do
			local cur
			for _, e in ipairs(data().Inventory.Equipments or {}) do
				if type(e) == 'table' and e.GUID == w.GUID then
					cur = e
				end
			end
			cur = cur or w
			if (tonumber(cur.Upgrade) or 0) >= level then
				break
			end
			local okr, req = pcall(function()
				return select(2, ES:GetUpgradeRequirements(cur):await())
			end)
			if okr and type(req) == 'table' and type(req.materials) == 'table' then
				for _, v in pairs(req.materials) do
					local mname = type(v.material) == 'table' and v.material.Name or tostring(v.material)
					if have(mname) < (tonumber(v.quantity) or 0) then
						setStatus(('quest: need %s x%s to enhance'):format(mname, tostring(v.quantity)))
						return true
					end
				end
			end
			pcall(function()
				ES:EnhanceEquipment(cur.GUID):await()
			end)
			setStatus(('enhancing %s (now +%s, want +%d)'):format(tostring(cur.Type), tostring(cur.Upgrade or 0), level))
			task.wait(1.2)
		end
		return true
	end


	-- "Attach a rune": put one of your runes on an equipped item at the Runemaker (costs gold).
	local runeAt = 0
	local function attachRune()
		if os.clock() - runeAt < 60 then
			return false
		end
		runeAt = os.clock()
		local d = data()
		local okR, Runes = pcall(function()
			return require(RS.Shared.Data.Runes)
		end)
		local okE, Equip = pcall(function()
			return require(RS.Shared.Data.Equipments)
		end)
		if not (d and okR and okE) then
			return false
		end
		local equipped = {}
		for _, e in pairs(d.Equipped or {}) do
			if type(e) == 'table' then
				equipped[#equipped + 1] = e
			end
		end
		local pickItem, pickRune
		for _, it in ipairs(d.Inventory.Misc or {}) do
			local info = it.GUID and it.Id and Runes.Runes and Runes.Runes[it.Id]
			if info then
				for _, e in ipairs(equipped) do
					local okT, slot = pcall(Equip.GetItemType, Equip, e.Type or e.Name)
					-- Only items with a GUID can take runes (pickaxes are stored by name).
					if e.GUID and okT and table.find(info.WhitelistedTypes or {}, slot) and #(e.Runes or {}) == 0 then
						pickItem, pickRune = e, it
						break
					end
				end
			end
			if pickItem then
				break
			end
		end
		if not pickItem then
			setStatus('quest: no rune that fits your gear')
			return false
		end
		local npc = npcModel('Runemaker')
		if not npc or not goTo(npc) then
			return false
		end
		setStatus(('quest: attaching %s to %s'):format(tostring(pickRune.Id), tostring(pickItem.Type or pickItem.Name)))
		pcall(function()
			service('RuneService'):PurchaseAttach(pickItem.GUID or pickItem.Name, pickRune.GUID):await()
		end)
		task.wait(1)
		return true
	end


	-- "Bring 1 'Health Potion' to Isaac" / "Bring Monke 30 bananite" / "Bring 3 Fireite to Line".
	local function parseBring(desc)
		desc = tostring(desc or '')
		local n, item = desc:match("[Bb]ring%s+(%d+)%s+'([^']+)'")
		if not n then
			n, item = desc:match('[Bb]ring%s+(%d+)%s+(.-)%s+to%s')
		end
		if not n then
			local _
			_, n, item = desc:match('[Bb]ring%s+(%a+)%s+(%d+)%s+([%a%s]+)')
		end
		if n and item then
			return tonumber(n), (item:gsub('%s+$', ''))
		end
		return nil
	end
	local function itemCount(item)
		local d = data()
		local key = norm(item)
		local n = 0
		for k, v in pairs(d and d.Inventory or {}) do
			if type(v) == 'number' and norm(k) == key then
				n += v
			end
		end
		for _, it in ipairs(d and d.Inventory and d.Inventory.Misc or {}) do
			local nk = norm(it.Name)
			if nk == key or (nk:sub(1, #key) == key and nk:sub(#key + 1):match('^%d*$')) then
				n += tonumber(it.Quantity) or 1
			end
		end
		return n
	end
	local function oreKey(item)
		local key = norm(item)
		for name in pairs(ORE_NAMES) do
			if norm(name) == key then
				return name
			end
		end
		return nil
	end
	local function shopKey(item)
		local key = norm(item)
		local best, bestPrice
		for name, info in pairs(ShopData or {}) do
			local nk = norm(name)
			if nk == key or (nk:sub(1, #key) == key and nk:sub(#key + 1):match('^%d*$')) then
				if not bestPrice or (info.Price or 0) < bestPrice then
					best, bestPrice = name, info.Price or 0
				end
			end
		end
		return best
	end
	-- Returns true if it did something.
	local function deliverItem(questId, q, desc)
		local n, item = parseBring(desc)
		if not n then
			return false
		end
		local ore = oreKey(item)
		if ore then
			G.FTReserve[ore] = math.max(G.FTReserve[ore] or 0, n)
		end
		if itemCount(item) >= n then
			return q.Npc and visit(q.Npc, 'deliver') or false
		end
		local sk = shopKey(item)
		if sk and settings.questBuy then
			return buy(sk, n - itemCount(item))
		end
		if ore then
			QS.wantMine = true -- keep mining; this ore may only drop on another island
		end
		return false
	end

	local function claimBoard()
		local d = data()
		local qb = d and d.QuestBoard
		if type(qb) ~= 'table' then
			return
		end
		local QBS = service('QuestBoardService')
		for _, tier in ipairs({ 'Daily', 'Weekly', 'Monthly' }) do
			for i, q in ipairs(type(qb[tier]) == 'table' and qb[tier].Quests or {}) do
				if not q.Claimed and (tonumber(q.Progress) or 0) >= (tonumber(q.Goal) or math.huge) then
					pcall(function()
						QBS:ClaimQuest(tier, i)
					end)
					setStatus(('claimed %s quest %s'):format(tier, tostring(q.Id)))
					task.wait(0.5)
				end
			end
		end
	end

	local skipped = {}
	local turnInAt = {}
	local lastAcceptScan, lastBoard = 0, 0

	-- One quest action per call. Returns true if it did something.
	function Quest.step()
		QS.wantMobs, QS.wantMine, QS.mobTarget = false, false, nil
		QS.storyMobs, QS.storyMine = false, false
		G.FTQuestRock = nil
		G.FTReserve = {}
		local d = data()
		if not d then
			return false
		end
		if settings.claimBoard and os.clock() - lastBoard > 30 then
			lastBoard = os.clock()
			claimBoard()
		end
		if settings.autoCompleteQuests then
			-- One-time (story / NPC) quests first, repeatable ones last.
			local order = {}
			for id in pairs(d.Quests or {}) do
				order[#order + 1] = id
			end
			local focusId = settings.focusQuest ~= 'Auto' and d.Quests[settings.focusQuest] ~= nil and settings.focusQuest or nil
			table.sort(order, function(a, b)
				-- The quest you picked in "Focus quest" goes first.
				if focusId and (a == focusId) ~= (b == focusId) then
					return a == focusId
				end
				local ra = QuestData and QuestData[a] and QuestData[a].Repeatable and 1 or 0
				local rb = QuestData and QuestData[b] and QuestData[b].Repeatable and 1 or 0
				if ra ~= rb then
					return ra < rb
				end
				return tostring(a) < tostring(b)
			end)
			for _, id in ipairs(order) do
				local qd = d.Quests[id]
				local q = QuestData and QuestData[id] or {}
				-- Priority quest: the focused one, or (no focus) any one-time quest.
				local pri = (focusId ~= nil and id == focusId) or (focusId == nil and not q.Repeatable)
				if type(qd) == 'table' and questDone(qd) and q.AutoComplete ~= true
					and os.clock() - (turnInAt[id] or 0) > 30 then
					turnInAt[id] = os.clock()
					if visit(q.Npc or id, 'turn in') then
						return true
					end
				end
				for pi, p in ipairs(type(qd) == 'table' and qd.Progress or {}) do
					local cur, req = tonumber(p.currentProgress) or 0, tonumber(p.requiredAmount) or 1
					if cur < req then
						local t, target = p.questType, tostring(p.target)
						if t == 'Kill' then
							QS.wantMobs = true
							if pri then
								QS.storyMobs = true
							end
							-- Only aim at a specific mob if one with that name is actually around.
							if not QS.mobTarget and target ~= 'Any' and target ~= 'Mob' then
								local lv = workspace:FindFirstChild('Living')
								for _, m in ipairs(lv and lv:GetChildren() or {}) do
									if m:GetAttribute('IsNpc') and mobMatches((string.gsub(m.Name, '%d+$', '')), target) then
										QS.mobTarget = target
										break
									end
								end
							end
						elseif t == 'Mine' or (t == 'Collect' and (target == 'Ore' or not (ShopData and ShopData[target]))) then
							QS.wantMine = true
							if t == 'Mine' and target ~= 'Any' and target ~= 'Rock' then
								G.FTQuestRock = G.FTQuestRock or target
							end
							if pri then
								QS.storyMine = true
							end
						elseif t == 'Collect' and ShopData and ShopData[target] then
							if settings.questBuy and buy(target) then
								return true
							end
						elseif t == 'Talk' then
							if visit(target, 'talk') then
								return true
							end
						elseif t == 'Sell' then
							if target == 'Ore' or target == 'Ores' then
								if sellOres() then
									return true
								end
							elseif sellSpare(target) then
								return true
							end
						elseif t == 'Equip' or t == 'EquipWeapon' then
							if target == 'Pickaxe' then
								equipBestPickaxe()
							else
								autoEquipBest(true)
							end
						elseif t == 'Extra' then
							local desc = q.Objectives and q.Objectives[pi] and q.Objectives[pi].Description
							if target == 'None' or parseBring(desc) then
								if deliverItem(id, q, desc) then
									return true
								end
							elseif extraFetch(target) then
								return true
							end
						elseif t == 'UI' then
							-- "Open the map" style steps: tell the server, in order.
							pcall(function()
								service('QuestService'):ProgressUIQuest(id, pi)
							end)
							task.wait(0.3)
						elseif t == 'Enhance' then
							local lvl = 3
							pcall(function()
								for _, o in ipairs(q.Objectives or {}) do
									if o.Type == 'Enhance' then
										lvl = tonumber(tostring(o.Description):match('%+(%d+)')) or lvl
									end
								end
							end)
							if enhanceTo(lvl) then
								return true
							end
						elseif t == 'RuneAttach' then
							if attachRune() then
								return true
							end
						elseif t ~= 'Forge' and not skipped[t] then
							skipped[t] = true
							warn(('[ForgeTools] quest objective "%s" (%s) is not automated yet'):format(t, target))
						end
					end
				end
			end
		end
		-- A quest that needs ore: don't sit on a 10,000 HP Lucky Block.
		G.FTQuestWantsOre = QS.wantMine
		if settings.autoAcceptQuests and os.clock() - lastAcceptScan > 20 then
			lastAcceptScan = os.clock()
			local prox = workspace:FindFirstChild('Proximity')
			for _, npc in ipairs(prox and prox:GetChildren() or {}) do
				local isTalker = DialogueNpcs and (DialogueNpcs[npc.Name] or false)
				-- Only scout NPCs reasonably close (some sit thousands of studs away in side areas).
				local near = false
				pcall(function()
					local _, hrp = char()
					near = hrp and (npc:GetPivot().Position - hrp.Position).Magnitude <= (tonumber(settings.questRange) or 1000)
				end)
				if isTalker and near and npc:IsA('Model') then
					local tree = treeOf[npc.Name]
					local want = false
					if not tree then
						want = not visited[npc.Name] or os.clock() - visited[npc.Name] > 900
					else
						for _, g in ipairs(treeCommands(tree).give) do
							if g.quest and eligible(g.quest) then
								want = true
							end
						end
						want = want and (not visited[npc.Name] or os.clock() - visited[npc.Name] > 60)
					end
					if want and visit(npc.Name, 'looking for quests') then
						return true
					end
				end
			end
		end
		return false
	end
end

---------------------------------------------------------------------------
-- Rewards: mail, codes, daily login, level + index rewards
---------------------------------------------------------------------------
local Rewards = {}
do
	-- Known working codes (Nov 2026). Add more in PlayerTools/forgecodes.txt, one per line.
	local CODES = { 'AIDASAYSSORRY', 'SORRYFORSHUTDOWNN!', 'TWILIGHTWAR', 'FORGECOMEBACK', 'CRIMSONSAKURA' }
	local triedPath = 'PlayerTools/forgecodes_tried_' .. string.lower(LocalPlayer.Name):gsub('[^%w_]', '') .. '.txt'
	local tried = {}
	pcall(function()
		if isfile(triedPath) then
			for line in readfile(triedPath):gmatch('[^\r\n]+') do
				tried[line] = true
			end
		end
	end)
	local function codeList()
		local list, seen = {}, {}
		local function add(c)
			c = tostring(c):gsub('^%s+', ''):gsub('%s+$', '')
			if c ~= '' and not seen[c] then
				seen[c] = true
				list[#list + 1] = c
			end
		end
		for _, c in ipairs(CODES) do
			add(c)
		end
		pcall(function()
			if isfile('PlayerTools/forgecodes.txt') then
				for line in readfile('PlayerTools/forgecodes.txt'):gmatch('[^\r\n]+') do
					if not line:match('^%s*%-%-') then
						add(line)
					end
				end
			end
		end)
		return list
	end

	local last = 0
	function Rewards.step()
		if os.clock() - last < 60 then
			return
		end
		last = os.clock()
		local d = data()
		if not d then
			return
		end
		if settings.autoMail then
			pcall(function()
				local ok, res = service('MailService'):ClaimAll():await()
				if ok and type(res) == 'table' and (res.Success or res.Claimed) then
					setStatus('claimed mail')
				end
			end)
			pcall(function()
				service('LevelRewardsService'):ClaimAll()
			end)
			pcall(function()
				service('CodexService'):ClaimAll()
			end)
			-- Seasonal event (Twilight War etc.): free quest / milestone / free-step rewards and the altar daily.
			for _, call in ipairs({
				{ 'SeasonalEventService', 'ClaimAll' },
				{ 'SeasonalEventService', 'ClaimAllMilestones' },
				{ 'SeasonalEventService', 'ClaimFreeStep' },
			}) do
				pcall(function()
					local svc = service(call[1])
					if svc and svc[call[2]] then
						svc[call[2]](svc)
					end
				end)
			end
		end
		-- Twilight altar: free daily gifts, then offer shards (x10 while possible, then x1).
		pcall(function()
			local Altar = require(RS.Shared.Data.TwilightAltar)
			local svc = service('TwilightAltarService')
			if settings.autoMail then
				for _, gift in ipairs(Altar.Daily and Altar.Daily.Order or {}) do
					pcall(function()
						svc:ClaimDaily(gift)
					end)
				end
			end
			if not settings.autoOffer then
				return
			end
			local tw = d.Events and d.Events.TwilightWar
			local pledge = tw and tw.Pledge
			if type(pledge) ~= 'string' or pledge == '' then
				return
			end
			local function shards()
				for _, it in ipairs(d.Inventory and d.Inventory.Misc or {}) do
					local n = tostring(it.Name)
					if n:find('Shard') and n:lower():find(pledge:lower(), 1, true) then
						return tonumber(it.Quantity) or 0
					end
				end
				return 0
			end
			local cost = tonumber(Altar.OfferCost) or 100
			local offers = Altar.Offers or { 1, 10 }
			local big, small = offers[2] or 10, offers[1] or 1
			for _ = 1, 50 do
				local have = shards()
				local n = (have >= cost * big and big) or (have >= cost * small and small) or nil
				if not n then
					break
				end
				local ok, res = pcall(function()
					return select(2, svc:Offer(n):await())
				end)
				setStatus(('offered %d at the altar (%d shards left)'):format(n, shards()))
				if not ok or not res then
					break
				end
				task.wait(1.5)
			end
		end)
		if settings.autoDaily then
			pcall(function()
				local Util = require(RS.Shared.Utils.DailyLoginUtil)
				for day = 1, 31 do
					local okc, can = pcall(Util.CanClaimReward, d.DailyLogin, day)
					if okc and can then
						service('DailyLoginService'):Claim(day)
						setStatus('claimed daily login day ' .. day)
						task.wait(0.5)
					end
				end
			end)
		end
		if settings.autoCodes then
			local redeemed = {}
			for k, v in pairs(d.RedeemedCodes or {}) do
				redeemed[type(k) == 'string' and k or tostring(v)] = true
			end
			for _, code in ipairs(codeList()) do
				if not tried[code] and not redeemed[code] and not redeemed[code:upper()] then
					tried[code] = true
					local okr, res = pcall(function()
						return select(2, service('CodeService'):RedeemCode(code):await())
					end)
					local msg = okr and type(res) == 'table' and tostring(res.Message or res.Success) or tostring(res)
					setStatus(('code %s: %s'):format(code, msg))
					print(('[ForgeTools] code %s -> %s'):format(code, msg))
					if msg:lower():find('too many') or msg:lower():find('wait') then
						tried[code] = nil -- rate limited: try again next round
						break
					end
					pcall(function()
						local lines = {}
						for c in pairs(tried) do
							lines[#lines + 1] = c
						end
						writefile(triedPath, table.concat(lines, '\n') .. '\n')
					end)
					task.wait(3)
				end
			end
		end
	end
end


---------------------------------------------------------------------------
-- Abyss: walk into the Abyss cage, start the run, auto-pick cards and fight inside.
---------------------------------------------------------------------------
local Abyss = {}
do
	local A
	pcall(function()
		A = require(RS.Shared.Data.Abyss)
	end)
	-- Inside a run the place has no Abyss cage and the Abyss mode is on.
	-- In a run = not on any of the normal island places.
	local islandPlaces = {}
	pcall(function()
		for _, isl in ipairs(require(RS.Shared.Data.Islands).Data) do
			islandPlaces[isl.PlaceId] = true
		end
	end)
	function Abyss.inRun()
		if workspace:GetAttribute('AbyssRun') == true then
			return true
		end
		return next(islandPlaces) ~= nil and not islandPlaces[game.PlaceId]
	end

	-- Cards: score every offered card and pick the best one (12s to choose in game).
	--   Best overall: rarest, then damage. Damage / Survival: that kind first. Loot: reward cards.
	--   Cursed cards (Greed, Glass Cannon...) are skipped unless "Allow cursed cards" is on.
	local RANK = { Abyssal = 60, Fusion = 50, Epic = 40, Rare = 30, Common = 10, Cursed = 35 }
	local function cardScore(card)
		if type(card) ~= 'table' then
			return -1
		end
		local text = string.lower(tostring(card.Text or ''))
		-- Never take a card with a downside (all Cursed cards, Deep Pact, anything with a Cost or
		-- that makes enemies stronger / you take more damage / lowers a stat).
		if card.Cost ~= nil or card.Enemy ~= nil or card.Rarity == 'Cursed'
			or text:find('more damage') or text:find('stronger') or text:find('%-%d') then
			return -1000
		end
		local score = RANK[tostring(card.Rarity)] or 5
		local focus = settings.cardFocus
		local dmg = text:find('damage') and not text:find('less damage') and not text:find('more damage')
		local surv = text:find('health') or text:find('less damage') or text:find('heal') or text:find('survive')
		local loot = card.Loot ~= nil or text:find('reward')
		if focus == 'Damage' then
			score += dmg and 100 or 0
		elseif focus == 'Survival' then
			score += surv and 100 or 0
		elseif focus == 'Loot' then
			score += loot and 100 or 0
		else
			score += dmg and 5 or (surv and 4 or 0)
		end
		return score
	end
	Abyss.cardScore = cardScore
	local function pickFrom(offer)
		local best, bestScore
		for _, id in ipairs(offer.Cards) do
			local card = A and A.GetCard and A.GetCard(id)
			local sc = cardScore(card)
			if not bestScore or sc > bestScore then
				best, bestScore = id, sc
			end
		end
		return best, bestScore
	end
	local lastPicked
	pcall(function()
		if G.FTAbyssCardConn then
			G.FTAbyssCardConn:Disconnect()
		end
		if G.FTAbyssPickedConn then
			G.FTAbyssPickedConn:Disconnect()
		end
		local AS = service('AbyssService')
		G.FTAbyssPickedConn = AS.CardPicked:Connect(function()
			lastPicked = os.clock()
		end)
		G.FTAbyssCardConn = AS.CardOffer:Connect(function(offer)
			if not (settings.autoCards or settings.autoAbyss) or type(offer) ~= 'table' or type(offer.Cards) ~= 'table' then
				return
			end
			local offeredAt = os.clock()
			task.wait(1)
			-- Reroll every card that has a downside (3 rerolls per slot), then take the best one.
			local cards = table.clone(offer.Cards)
			for slot = 1, #cards do
				for _ = 1, 3 do
					if os.clock() - offeredAt > 9 then
						break
					end
					if cardScore(A and A.GetCard and A.GetCard(cards[slot])) > -1000 then
						break
					end
					local ok, a, b, c = pcall(function()
						return AS:RerollCards(slot):await()
					end)
					local newId = ok and a and b and c or nil
					if newId == nil then
						break -- out of rerolls
					end
					cards[slot] = newId
					task.wait(0.3)
				end
			end
			local best, bestScore = pickFrom({ Cards = cards })
			if best == nil then
				return
			end
			if bestScore <= -1000 then
				pcall(function()
					AS:SkipCards():await()
				end)
				setStatus('abyss: only cards with downsides — skipped')
				return
			end
			local card = A and A.GetCard and A.GetCard(best)
			-- Retry a few times in case the first call lands before the menu is ready.
			for _ = 1, 4 do
				pcall(function()
					AS:PickCard(best)
				end)
				task.wait(1.2)
				if lastPicked and lastPicked >= offeredAt then
					break
				end
			end
			setStatus('abyss: took ' .. tostring(card and card.Name or best))
		end)
	end)

	local lastTry = 0
	-- Outside a run: go to the cage, open the lobby (makes your party) and start it.
	function Abyss.step()
		if not settings.autoAbyss or Abyss.inRun() or os.clock() - lastTry < 15 then
			return false
		end
		local prox = workspace:FindFirstChild('Proximity')
		local cage = prox and prox:FindFirstChild('AbyssCreateParty')
		if not cage then
			return false
		end
		lastTry = os.clock()
		local ok, pos = pcall(function()
			return cage:GetPivot().Position
		end)
		if not ok then
			return false
		end
		local _, hrp = char()
		if hrp and (hrp.Position - pos).Magnitude > 250 then
			-- The cage is in the Abyss lobby far off the map: use the game's own teleport there
			-- (same as the Events page "Abyss" button), not a long walk.
			setStatus('abyss: teleporting to the Abyss lobby')
			pcall(function()
				service('AbyssService'):Enter():await()
			end)
			local t0 = os.clock()
			while os.clock() - t0 < 8 do
				task.wait(0.5)
				local _, h2 = char()
				if h2 and (h2.Position - pos).Magnitude < 250 then
					break
				end
			end
		end
		setStatus('abyss: walking to the cage')
		if not tweenTo(CFrame.new(pos + Vector3.new(0, 2, 4))) then
			return true
		end
		-- Same as pressing E on the purple circle: make an Abyss party, then start it.
		setStatus('abyss: making the party')
		local partyType = 'Abyss'
		pcall(function()
			local pr = cage:FindFirstChildWhichIsA('ProximityPrompt', true)
			partyType = pr and pr:GetAttribute('PartyType') or partyType
		end)
		pcall(function()
			local pc = controller('PartyController')
			if not (pc and pc.CurrentParty) then
				service('PartyService'):CreateParty(partyType):await()
			end
		end)
		task.wait(1.5)
		setStatus('abyss: starting the run')
		pcall(function()
			service('PartyService'):Activate():await()
		end)
		task.wait(8) -- teleporting into the run
		return true
	end
end

---------------------------------------------------------------------------
-- GUI
---------------------------------------------------------------------------
local Library
do
	G.Library = nil
	Library = assert(compile(readfile('PlayerTools/AtaraxiaLibrary.lua'), 'AtaraxiaLibrary.lua'), 'AtaraxiaLibrary.lua failed')()
	Library.Animations = type(Library.Animations) == 'table' and Library.Animations or {}
	Library.Animations.TabSwitch = false
	Library.Animations.Dropdown = false
	G.SB2ForgeToolsLibrary = Library
end
local Window = Library:CreateWindow({
	Title = 'Forge Tools',
	Footer = BUILD .. '  ·  ' .. LocalPlayer.Name,
	Folder = 'ForgeTools',
	Size = UDim2.fromOffset(640, 460),
	MinSize = Vector2.new(560, 380),
	Resizable = true,
	OnUnload = function()
		if type(G.SB2ForgeToolsUnload) == 'function' then
			pcall(G.SB2ForgeToolsUnload, true)
		end
	end,
})
local Tab = Window:AddTab('Main', 'pickaxe')
local FarmBox = Tab:AddLeftGroupbox('Mining & selling')
local ForgeBox = Tab:AddRightGroupbox('Forge')
local MobBox = Tab:AddLeftGroupbox('Mobs')
local InfoBox = Tab:AddRightGroupbox('Status')

-- Every feature toggle starts OFF each time the script loads (sliders / dropdowns keep their values)
-- EXCEPT right after a teleport (Abyss in/out, island travel): then they carry over.
local sessionPath = 'PlayerTools/forgetools_session_' .. string.lower(LocalPlayer.Name):gsub('[^%w_]', '') .. '.json'
local resume = {}
pcall(function()
	if isfile(sessionPath) then
		local sess = HttpService:JSONDecode(readfile(sessionPath))
		if type(sess) == 'table' and type(sess.t) == 'number' and os.time() - sess.t < 150 and type(sess.on) == 'table' then
			resume = sess.on
		end
		writefile(sessionPath, '{}') -- one use only
	end
end)
local toggleKeys = {}
pcall(function()
	if G.FTTeleportConn then
		G.FTTeleportConn:Disconnect()
	end
	G.FTTeleportConn = LocalPlayer.OnTeleport:Connect(function(state)
		if state == Enum.TeleportState.Started or state == Enum.TeleportState.InProgress then
			local on = {}
			for key in pairs(toggleKeys) do
				on[key] = settings[key] == true
			end
			pcall(writefile, sessionPath, HttpService:JSONEncode({ t = os.time(), on = on }))
		end
	end)
end)
local function bindToggle(box, idx, key, text, tip)
	toggleKeys[key] = true
	settings[key] = resume[key] == true
	box:AddToggle(idx, { Text = text, Default = settings[key], Tooltip = tip }):OnChanged(function(v)
		settings[key] = v == true
		save()
		if not v then
			stopTween()
		end
	end)
end
local function bindDropdown(box, idx, key, text, values, tip)
	local dd = box:AddDropdown(idx, { Text = text, Values = values, Default = settings[key], AllowNull = false, Tooltip = tip })
	dd:OnChanged(function(v)
		if type(v) == 'table' then
			v = next(v)
		end
		if v ~= nil then
			settings[key] = v
			save()
		end
	end)
	return dd
end
local function bindSlider(box, idx, key, text, min, max, tip)
	box:AddSlider(idx, { Text = text, Min = min, Max = max, Rounding = 0, Default = tonumber(settings[key]) or min, Tooltip = tip }):OnChanged(function(v)
		settings[key] = tonumber(v) or settings[key]
		save()
	end)
end

local function zoneNames()
	local out = { 'Any' }
	local rocks = workspace:FindFirstChild('Rocks')
	for _, z in ipairs(rocks and rocks:GetChildren() or {}) do
		if z.Name ~= 'Roof' then
			out[#out + 1] = z.Name
		end
	end
	return out
end
local function mobNames()
	local set, out = {}, { 'Any' }
	for _, m in ipairs(workspace:FindFirstChild('Living') and workspace.Living:GetChildren() or {}) do
		if m:GetAttribute('IsNpc') then
			local b = baseName(m.Name)
			if not set[b] then
				set[b] = true
				out[#out + 1] = b
			end
		end
	end
	return out
end

bindToggle(FarmBox, 'FTAutoMine', 'autoMine', 'Auto mine', 'Tweens to the nearest rock and mines it. Rock types your pickaxe cannot damage are skipped.')
local zoneDD = bindDropdown(FarmBox, 'FTMineZone', 'mineZone', 'Mine in', zoneNames())
bindToggle(FarmBox, 'FTSkipLucky', 'skipLucky', 'Skip Lucky Blocks', 'Lucky Blocks have 10,000 HP.')
bindToggle(FarmBox, 'FTAutoSell', 'autoSell', 'Auto sell ores', 'Sells your ores at Greedy Cey when the bag reaches the % below.')
bindSlider(FarmBox, 'FTSellAt', 'sellAt', 'Sell when bag is % full', 20, 100)
FarmBox:AddButton('Sell ores now', function()
	sellOres()
end)

bindToggle(ForgeBox, 'FTAutoForge', 'autoForge', 'Auto forge', 'When you have enough ores: tweens to the forge, puts them in and plays every minigame perfectly.')
bindDropdown(ForgeBox, 'FTForgeType', 'forgeType', 'Forge', { 'Weapon', 'Armor' })
bindSlider(ForgeBox, 'FTForgeOres', 'forgeOres', 'Ores per forge (max)', 3, 60, 'With "Best gear" on this is the most it will use; otherwise it uses exactly this many, most plentiful ores first.')
bindToggle(ForgeBox, 'FTForgeBest', 'forgeBest', 'Best gear (smart ore pick)', 'Uses your highest-multiplier ores and the ore count that gives the strongest expected item (bigger weapon/armor types vs. keeping the average multiplier high).')
bindSlider(ForgeBox, 'FTForgeKeep', 'forgeKeep', 'Keep of each ore (auto sell)', 0, 20, 'With auto forge on, auto sell leaves this many of each ore for forging.')
do
	local oreList = {}
	for name in pairs(ORE_NAMES) do
		oreList[#oreList + 1] = name
	end
	table.sort(oreList)
	if type(settings.keepOres) ~= 'table' then
		settings.keepOres = {}
	end
	local keepDD = ForgeBox:AddDropdown('FTKeepOres', { Text = 'Save these ores (never sell / forge)', Values = oreList, Multi = true, Default = settings.keepOres, AllowNull = true, Tooltip = 'Picked ores are kept: auto sell and auto forge leave them alone (e.g. Galgite, Heavenite).' })
	keepDD:OnChanged(function(v)
		local out = {}
		for k, on in pairs(type(v) == 'table' and v or {}) do
			if on then
				out[k] = true
			end
		end
		settings.keepOres = out
		save()
	end)
end
ForgeBox:AddButton('Forge now', function()
	forgeOnce()
end)

bindToggle(MobBox, 'FTAutoMobs', 'autoMobs', 'Auto kill mobs', 'Tweens to the nearest mob and fights it with your Weapon.')
local mobDD = bindDropdown(MobBox, 'FTMobFilter', 'mobFilter', 'Target', mobNames())
bindSlider(MobBox, 'FTRetreatHp', 'retreatHp', 'Retreat to spawn below % health', 0, 90, 'Goes back to spawn and waits until health is 90% before fighting again.')
bindSlider(MobBox, 'FTMaxMobHp', 'maxMobHp', 'Only fight mobs with max HP up to', 0, 2000, '0 = any mob. Keep this low until your gear is better.')
bindDropdown(MobBox, 'FTCombatStyle', 'combatStyle', 'Combat style', { 'Hit & run', 'Block / parry' }, 'Hit & run: steps out of reach right before each attack lands, then comes back in to hit. Block / parry: stands and blocks. (Floating over mobs was tested: their attacks reach straight up, so it is not offered.)')
bindSlider(MobBox, 'FTDodgeDist', 'dodgeDist', 'Dodge distance (studs)', 8, 30, 'How far it steps away from an incoming attack.')
bindToggle(MobBox, 'FTAutoAbyss', 'autoAbyss', 'Auto Abyss', 'Goes to the Abyss cage, starts a run, picks a card each floor (see below) and fights every floor. Re-enters when you come back.')
bindToggle(MobBox, 'FTAutoCards', 'autoCards', 'Auto pick abyss cards', 'Picks a card for you after each floor, even when you play the Abyss yourself.')
bindDropdown(MobBox, 'FTCardFocus', 'cardFocus', 'Card priority', { 'Best overall', 'Damage', 'Survival', 'Loot' }, 'Best overall: rarest card (Abyssal > Fusion > Epic > Rare > Common). Damage / Survival / Loot: that kind of card first, then rarity.')
bindToggle(MobBox, 'FTAutoBlock', 'autoBlock', 'Auto block (F)', 'Blocks right before a mob\'s attack lands, then goes back to swinging.')
bindSlider(MobBox, 'FTParryLead', 'parryLead', 'Parry lead (x10 ms before the hit)', 5, 50, 'Blocks this long before each attack lands. It learns every mob attack\'s timing by itself; ~20 parries best. Raise it if hits get through, lower it if you block but don\'t parry.')
bindSlider(MobBox, 'FTSwitchMins', 'switchMins', 'With auto mine on, switch every (min)', 1, 15, 'Mobs and mining take turns so you still get ores to forge with.')
local QuestBox = Tab:AddRightGroupbox('Quests')
bindToggle(QuestBox, 'FTAutoAccept', 'autoAcceptQuests', 'Auto accept quests', 'Visits NPCs and takes any quest they offer (repeatable ones again when they come back).')
bindToggle(QuestBox, 'FTAutoComplete', 'autoCompleteQuests', 'Auto complete quests', 'Works the objectives (forge, sell, equip, talk, kill, mine, buy) and turns quests in at the NPC.')
-- Quest tracker: pick the quest to focus on (it goes first and decides mine vs mobs).
local QuestDataUI
pcall(function()
	QuestDataUI = require(RS.Shared.Data.Quests)
end)
local function questLabel(id)
	local q = QuestDataUI and QuestDataUI[id]
	return tostring(q and q.Name or id)
end
local focusMap = {}
local function focusValues()
	local out = { 'Auto' }
	focusMap = { Auto = 'Auto' }
	local d = data()
	local ids = {}
	for id in pairs(d and d.Quests or {}) do
		ids[#ids + 1] = id
	end
	table.sort(ids, function(a, b)
		return questLabel(a) < questLabel(b)
	end)
	for _, id in ipairs(ids) do
		local name = questLabel(id)
		if focusMap[name] then
			name = name .. ' (' .. id .. ')'
		end
		focusMap[name] = id
		out[#out + 1] = name
	end
	return out
end
local focusList = focusValues()
local focusDefault = 'Auto'
for name, id in pairs(focusMap) do
	if id == settings.focusQuest then
		focusDefault = name
	end
end
local focusDD = QuestBox:AddDropdown('FTFocusQuest', { Text = 'Focus quest', Values = focusList, Default = focusDefault, AllowNull = false, Tooltip = 'Auto complete works this quest first. Auto = one-time quests before repeatable ones.' })
focusDD:OnChanged(function(v)
	if type(v) == 'table' then
		v = next(v)
	end
	if v ~= nil and focusMap[v] then
		settings.focusQuest = focusMap[v]
		save()
	end
end)
local trackerLabel = QuestBox:AddLabel('Tracking: -')
task.spawn(function()
	local lastSig
	while alive do
		pcall(function()
			local d = data()
			local quests = d and d.Quests or {}
			-- refresh the dropdown when quests come and go
			local ids = {}
			for id in pairs(quests) do
				ids[#ids + 1] = id
			end
			table.sort(ids)
			local sig = table.concat(ids, ',')
			if sig ~= lastSig then
				lastSig = sig
				focusDD:SetValues(focusValues())
			end
			local id = settings.focusQuest
			if id == 'Auto' or not quests[id] then
				trackerLabel:SetText(id ~= 'Auto' and 'Tracking: quest finished (back to Auto)' or 'Tracking: Auto')
				return
			end
			local lines = { 'Tracking: ' .. questLabel(id) }
			for _, pr in ipairs(quests[id].Progress or {}) do
				lines[#lines + 1] = ('  %s %s  %s/%s'):format(tostring(pr.questType), tostring(pr.target),
					tostring(pr.currentProgress or 0), tostring(pr.requiredAmount or 1))
			end
			trackerLabel:SetText(table.concat(lines, '\n'))
		end)
		task.wait(2)
	end
end)
bindToggle(QuestBox, 'FTQuestBuy', 'questBuy', 'Buy quest items with gold', 'For "Purchase X" objectives (e.g. Bronze Pickaxe). In-game gold only, then equips the better pickaxe.')
bindToggle(QuestBox, 'FTClaimBoard', 'claimBoard', 'Claim quest board rewards', 'Claims finished Daily / Weekly / Monthly board quests.')
bindSlider(QuestBox, 'FTQuestRange', 'questRange', 'Look for new quests within (studs)', 200, 5000, 'NPCs farther than this are not visited just to check for quests (quest turn-ins and talk objectives still go anywhere).')
bindToggle(QuestBox, 'FTAutoMail', 'autoMail', 'Auto claim mail & rewards', 'Every minute: claims all mail, level rewards, index (codex) rewards, and free seasonal-event rewards (event quests, milestones, altar daily).')
bindToggle(QuestBox, 'FTAutoOffer', 'autoOffer', 'Auto offer altar shards', 'Twilight War altar: spends your side\'s shards on offers (x10 while you can, then x1) and takes the free daily gifts.')
bindToggle(QuestBox, 'FTAutoDaily', 'autoDaily', 'Auto claim daily login', 'Claims the daily login reward when it is ready.')
bindToggle(QuestBox, 'FTAutoCodes', 'autoCodes', 'Auto redeem codes', 'Tries each known code once per account. Add new codes to PlayerTools/forgecodes.txt (one per line).')
bindToggle(ForgeBox, 'FTAutoEquip', 'autoEquip', 'Auto equip better gear', 'After forging, equips the item if its slot is empty or it beats what you have on (more ores, then quality).')
MobBox:AddButton('Refresh lists', function()
	pcall(function()
		mobDD:SetValues(mobNames())
	end)
	pcall(function()
		zoneDD:SetValues(zoneNames())
	end)
end)

-- Island travel (same thing the Portal tool does). Lists islands and whether you've unlocked them.
do
	local IslandsMod
	pcall(function()
		IslandsMod = require(RS.Shared.Data.Islands)
	end)
	local function islandList()
		local out = {}
		for _, isl in ipairs(IslandsMod and IslandsMod.Data or {}) do
			local ok, st = pcall(IslandsMod.GetRequirementStatus, isl.Name, data())
			local open = ok and type(st) == 'table' and st.AllMet
			out[#out + 1] = isl.Name .. (open and '' or ' (locked)')
		end
		return out
	end
	local list = islandList()
	local dd = InfoBox:AddDropdown('FTIsland', { Text = 'Travel to island', Values = list, Default = list[2] or list[1], AllowNull = false })
	InfoBox:AddButton('Travel', function()
		local v = dd.Value
		if type(v) == 'table' then
			v = next(v)
		end
		v = tostring(v or ''):gsub(' %(locked%)$', '')
		local ok, st = pcall(IslandsMod.GetRequirementStatus, v, data())
		if ok and type(st) == 'table' and not st.AllMet then
			local need = {}
			for _, r in ipairs(st.Requirements or {}) do
				if not r.Met then
					need[#need + 1] = tostring(r.DisplayText)
				end
			end
			setStatus(v .. ' is locked: ' .. table.concat(need, ', '))
			return
		end
		setStatus('travelling to ' .. v .. '…')
		task.spawn(function()
			local okT, a, b = pcall(function()
				return service('PortalService'):TeleportToIsland(v):await()
			end)
			if not okT or a == false then
				setStatus('travel failed: ' .. tostring(b or a))
			end
		end)
	end)
end

statusLabel = InfoBox:AddLabel('Status: idle')
local statsLabel = InfoBox:AddLabel('')
bindToggle(InfoBox, 'FTNoBlur', 'noBlur', 'No blur', 'Keeps the game\'s blur effects (forge / menus / dialogue) switched off.')
bindSlider(InfoBox, 'FTTweenSpeed', 'tweenSpeed', 'Tween speed (studs/s)', 20, 120, 'Too fast can get you snapped back.')
InfoBox:AddToggle('FTAutoload', { Text = 'Autoload on this account', Default = settings.autoload == true }):OnChanged(function(v)
	settings.autoload = v == true
	save()
end)

---------------------------------------------------------------------------
-- Main loop: forge > sell > mobs > mine
---------------------------------------------------------------------------
local token = {}
local lastQuestStep = 0
G.SB2ForgeToolsToken = token

-- Anti blur: keep every blur effect at 0 (forge screen, menus, dialogue depth of field).
task.spawn(function()
	local L = game:GetService('Lighting')
	while alive and G.SB2ForgeToolsToken == token do
		if settings.noBlur then
			for _, x in ipairs(L:GetChildren()) do
				if x:IsA('BlurEffect') and x.Size > 0 then
					x.Size = 0
				elseif x:IsA('DepthOfFieldEffect') and x.Name == 'DialogueDOF' then
					x.Enabled = false
				end
			end
			pcall(function()
				for _, x in ipairs(workspace.CurrentCamera:GetChildren()) do
					if x:IsA('BlurEffect') and x.Size > 0 then
						x.Size = 0
					end
				end
			end)
		end
		task.wait(0.3)
	end
end)

-- Forge watchdog: if a forge sits at the hammer step with an unbroken mould (a resumed forge,
-- or one started before a reload), click the mould open; also make sure the minigames are hooked.
task.spawn(function()
	local since
	while alive and G.SB2ForgeToolsToken == token do
		pcall(function()
			local FC = controller('ForgeController')
			if FC and FC.ForgeActive then
				hookMinigames(FC)
			end
			local mold = workspace:FindFirstChild('Debris') and workspace.Debris:FindFirstChild('Mold')
			if FC and FC.ForgeActive and FC.Sequence == 'Hammer' and mold and mold:GetAttribute('IsDestroyed') ~= true then
				since = since or os.clock()
				if os.clock() - since > 3 then
					local cd = mold:FindFirstChild('ClickDetector')
					if cd then
						for _, c in ipairs(getconnections(cd.MouseClick)) do
							c:Fire()
						end
					end
				end
			else
				since = nil
			end
		end)
		task.wait(0.4)
	end
end)
local loopGen = 0
local function mainLoop(myGen)
	while alive and G.SB2ForgeToolsToken == token and loopGen == myGen do
		local ok, err = pcall(function()
			local _, _, hum = char()
			if not hum or hum.Health <= 0 then
				setStatus('dead / respawning')
				task.wait(1)
				return
			end
			local FC = controller('ForgeController')
			if FC and FC.ForgeActive and not settings.autoForge and not questForgeType() then
				setStatus('forge open')
				task.wait(0.5)
				return
			end
			if settings.autoAbyss and Abyss.inRun() then
				-- In the Abyss: just fight (no quests / forging in there).
				QS.wantMobs = true
				if #mobList() > 0 then
					fightOnce()
				else
					setStatus('abyss: waiting for the next floor')
					task.wait(0.5)
				end
				return
			end
			if Abyss.step() then
				return
			end
			if os.clock() - lastQuestStep > 3 then
				lastQuestStep = os.clock()
				Rewards.step()
				if Quest.step() then
					return
				end
			end
			local farm = chooseFarm()
			if forgeNeeded() then
				forgeOnce()
			elseif sellNeeded() then
				sellOres()
			elseif farm == 'mobs' and #mobList() > 0 then
				fightOnce()
			elseif farm == 'mine' or (farm == 'mobs' and (settings.autoMine or QS.wantMine)) then
				if not mineOnce() then
					task.wait(1)
				end
			else
				setStatus('idle')
				task.wait(0.5)
			end
		end)
		if not ok then
			warn('[ForgeTools] ' .. tostring(err))
			setStatus('error: ' .. tostring(err):sub(1, 120))
			task.wait(1)
		end
		task.wait(0.05)
	end
end
local loopThread = task.spawn(mainLoop, loopGen)

-- Stuck watchdog: if an auto option is on but nothing has changed for 75s (no new status, no
-- movement, no forge running), stop whatever it is waiting on and restart the loop.
-- Every status is also written to PlayerTools/forgetools_log_<account>.txt so problems can be traced.
task.spawn(function()
	local lastPos, lastSave = nil, 0
	local logPath = 'PlayerTools/forgetools_log_' .. string.lower(LocalPlayer.Name) .. '.txt'
	while alive and G.SB2ForgeToolsToken == token do
		task.wait(3)
		local _, hrp = char()
		if hrp then
			if lastPos and (hrp.Position - lastPos).Magnitude > 3 then
				lastProgress = os.clock()
			end
			lastPos = hrp.Position
		end
		local anyOn = settings.autoMine or settings.autoMobs or settings.autoForge or settings.autoSell
			or settings.autoCompleteQuests or settings.autoAcceptQuests or settings.autoAbyss
		local FC = controller('ForgeController')
		local forging = FC and FC.ForgeActive
		if anyOn and not forging and os.clock() - lastProgress > 75 and _statusText ~= 'idle' then
			statusLog[#statusLog + 1] = os.date('%H:%M:%S ') .. 'WATCHDOG: stuck on "' .. tostring(_statusText) .. '" - restarting loop'
			warn('[ForgeTools] stuck on "' .. tostring(_statusText) .. '" for 75s - restarting')
			pcall(stopTween)
			pcall(function()
				getsenv(LocalPlayer.PlayerGui.DialogueUI.DialogueHandler).Close()
			end)
			pcall(task.cancel, loopThread)
			loopGen += 1
			lastProgress = os.clock()
			loopThread = task.spawn(mainLoop, loopGen)
		end
		if os.clock() - lastSave > 15 then
			lastSave = os.clock()
			pcall(writefile, logPath, table.concat(statusLog, '\n'))
		end
	end
end)

task.spawn(function()
	while alive and G.SB2ForgeToolsToken == token do
		local used, cap = bagCapacity()
		local d = data() or {}
		pcall(statsLabel.SetText, statsLabel, ('Gold %s · bag %s/%s · mined %d · sold %d · forged %d · kills %d'):format(
			tostring(math.floor((d.Gold or 0) * 100) / 100), tostring(used or '?'), tostring(cap or '?'),
			stats.mined, stats.sold, stats.forged, stats.kills))
		task.wait(1)
	end
end)

---------------------------------------------------------------------------
-- Teleport persistence + unload
---------------------------------------------------------------------------
pcall(function()
	local q = queue_on_teleport or (syn and syn.queue_on_teleport)
	if type(q) == 'function' then
		q([[
			if not game:IsLoaded() then game.Loaded:Wait() end
			task.wait(4)
			if getgenv().SB2ForgeToolsLoaded then return end
			if isfile('PlayerTools/ForgeTools.lua') then
				local fn = (loadstring or load)(readfile('PlayerTools/ForgeTools.lua'), 'ForgeTools.lua')
				if fn then task.spawn(fn) end
			end
		]])
	end
end)

G.SB2ForgeToolsUnload = function(fromWindow)
	alive = false
	G.SB2ForgeToolsToken = nil
	G.SB2ForgeToolsLoaded = nil
	G.SB2ForgeToolsUnload = nil
	stopTween()
	for _, c in ipairs(type(G.FTBlockConns) == 'table' and G.FTBlockConns or {}) do
		pcall(function()
			c:Disconnect()
		end)
	end
	pcall(function()
		G.FTDialogueConn:Disconnect()
	end)
	pcall(function()
		local tc = controller('ToolController')
		if tc and tc.isBlocking then
			tc:StopBlock()
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

Library:Notify('Forge Tools loaded (' .. LocalPlayer.Name .. ')', 4)
warn('[ForgeTools] loaded ' .. BUILD)
