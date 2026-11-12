--!nocheck
--!nolint
--[[
	ItemEditor.lua — PlayerTools module. Purely visual item editing for YOUR inventory screen.

	Wraps the game's UI.Inventory.GetItemData (what the inventory uses to draw each item) and
	swaps in your own display name, rarity, level and stat values for chosen items. Nothing is
	sent to the server and real stats are unchanged; only what your inventory shows.

	Edits are per item copy (its unique id) and saved in PlayerTools/item_overrides.json.

	getgenv().SB2ItemEditor = {
		start(), stop(),
		set(id, override), get(id), clear(id), clearAll(),
		list(query, limit) -> { {label=, id=, name=}, ... },
		current(id) -> { name, rarity, level, stats = { {label, value}, ... } }  (game's own values)
	}
	override = { name = 'text', rarity = 'Tribute', level = 500,
	             stats = { Damage = '999,999', Crit = '100%', ['Health Regeneration'] = '5%' } }
]]

local BUILD = 'itemeditor-v5-fastfill'
local g = getgenv()
if type(g.SB2ItemEditor) == 'table' and type(g.SB2ItemEditor.stop) == 'function' then
	pcall(g.SB2ItemEditor.stop)
end

local Players = game:GetService('Players')
local RS = game:GetService('ReplicatedStorage')
local HS = game:GetService('HttpService')
local LocalPlayer = Players.LocalPlayer
local FILE = 'PlayerTools/item_overrides.json'

local S = { on = false, inv = nil, orig = nil, overrides = {} }

local function load()
	S.overrides = {}
	pcall(function()
		if isfile(FILE) then
			local d = HS:JSONDecode(readfile(FILE))
			if type(d) == 'table' then
				S.overrides = d
			end
		end
	end)
end

local function save()
	pcall(function()
		writefile(FILE, HS:JSONEncode(S.overrides))
	end)
end

local function key(id)
	return tostring(id)
end

local function inventoryFolder()
	local profiles = RS:FindFirstChild('Profiles')
	local prof = profiles and profiles:FindFirstChild(LocalPlayer.Name)
	return prof and prof:FindFirstChild('Inventory')
end

local function inventoryModule()
	local ok, m = pcall(function()
		return require(RS.CardinalClient.MainModule.Services.UI.Inventory)
	end)
	if ok and type(m) == 'table' and type(m.GetItemData) == 'function' then
		return m
	end
	return nil
end

-- Percent stats (regens, crit, lifesteal, speed) get their % added if you typed a bare number.
local function formatStat(label, value)
	if type(value) ~= 'string' or value == '' then
		return value
	end
	local l = string.lower(tostring(label))
	local pct = string.find(l, 'regen', 1, true) or l == 'crit' or string.find(l, 'lifesteal', 1, true)
		or string.find(l, 'speed', 1, true)
	if pct and string.match(value, '^%s*[%d%.,%-%+]+%s*$') then
		return (string.gsub(value, '%s', '')) .. '%'
	end
	return value
end

-- The item panel re-calculates lines labelled exactly "Damage" / "Defense" (adds the match-best
-- bonus and the upgrade bonus), which turned a typed 676,767 into 1,488,887. A trailing space
-- keeps the label looking the same but makes the panel show the value exactly as typed.
local function asTyped(label)
	if label == 'Damage' or label == 'Defense' then
		return label .. ' '
	end
	return label
end

-- What the panel actually shows for Damage / Defense (same formula as the game's item panel),
-- so the editor pre-fills the number you see rather than the raw stored value.
local function shownValue(data, label, raw)
	local v = tonumber(raw)
	if not v or (label ~= 'Damage' and label ~= 'Defense') or type(data) ~= 'table' or not data.itemref then
		return raw
	end
	local ok, out = pcall(function()
		local ref = data.itemref
		local sbl = ref:FindFirstChild('ScaleByLevel')
		local mb = ref:FindFirstChild('MatchBest')
		if sbl then
			local exp = RS.Profiles[LocalPlayer.Name].Stats.Exp.Value
			v = v * (sbl.Value * math.floor(exp ^ (1 / 3)))
		end
		if mb then
			local pref = require(RS.Shared.Util.GetItemPerferedStat)(ref.Name)
			local mult = mb:IsA('ValueBase') and (mb.Value or 1) or 1
			v = v + (LocalPlayer:GetAttribute('Highest' .. tostring(pref)) or 0) * mult
		end
		v = math.floor(v)
		local up = tonumber(data.upgrade) or 0
		if up > 0 then
			local RD = require(RS.Shared.Library.RarityData)
			local maxUp = RD.RarityUpgrades[data.rarity]
			local m = RD.UpgradeLevelMultipliers[maxUp] or RD.UpgradeLevelMultipliers.default
			local du = ref:FindFirstChild('Stats') and ref.Stats:FindFirstChild('DamageUpgrade')
			if du then
				m = du.Value or m
			end
			if label == 'Defense' then
				m = RD.UpgradeLevelMultipliers.default
			end
			if maxUp then
				v = math.floor(v + up / maxUp * m * v)
			end
		end
		return tostring(v)
	end)
	return ok and out or raw
end

local rarityColors = nil
local function normalizeRarity(r)
	if not rarityColors then
		pcall(function()
			for _, o in next, getgc(true) do
				if type(o) == 'table' and type(rawget(o, 'rarityColors')) == 'table' then
					rarityColors = rawget(o, 'rarityColors')
					break
				end
			end
		end)
	end
	local want = string.lower(tostring(r))
	if rarityColors then
		for name in pairs(rarityColors) do
			if string.lower(tostring(name)) == want then
				return name
			end
		end
		return nil
	end
	for _, name in ipairs({ 'Common', 'Uncommon', 'Rare', 'Legendary', 'Tribute', 'Burst' }) do
		if string.lower(name) == want then
			return name
		end
	end
	return nil
end

local function applyOverride(data, ov)
	if type(data) ~= 'table' or type(ov) ~= 'table' then
		return data
	end
	if type(ov.name) == 'string' and ov.name ~= '' then
		data.name = ov.name
	end
	if type(ov.classname) == 'string' and ov.classname ~= '' then
		data.classname = ov.classname
	end
	if type(ov.rarity) == 'string' and ov.rarity ~= '' then
		-- Must be an exact game rarity name ('Tribute', not 'tribute'): an unknown one makes the
		-- slot builder error and the whole inventory list / aura picker stays empty.
		local r = normalizeRarity(ov.rarity)
		if r then
			data.rarity = r
		end
	end
	if tonumber(ov.level) then
		data.level = tonumber(ov.level)
	end
	if type(ov.stats) == 'table' and next(ov.stats) ~= nil then
		local out, seen = {}, {}
		local src = type(data.stats) == 'table' and data.stats or {}
		local maxI = 0
		for i in pairs(src) do
			if type(i) == 'number' and i > maxI then
				maxI = i
			end
		end
		for i = 1, maxI do
			local e = src[i]
			if type(e) == 'table' then
				local label = e[1]
				local want = ov.stats[label]
				if want ~= nil then
					seen[label] = true
					if want ~= '' then
						out[#out + 1] = { asTyped(label), formatStat(label, want) }
					end
				else
					out[#out + 1] = { e[1], e[2] }
				end
			end
		end
		for label, value in pairs(ov.stats) do
			if not seen[label] and type(value) == 'string' and value ~= '' then
				out[#out + 1] = { asTyped(label), formatStat(label, value) }
			end
		end
		data.stats = out
	end
	return data
end

local function start()
	if S.on then
		return true
	end
	load()
	local inv = inventoryModule()
	if not inv then
		return false
	end
	local orig = inv.GetItemData
	S.inv, S.orig = inv, orig
	inv.GetItemData = function(item, ...)
		local data = orig(item, ...)
		if S.on and type(data) == 'table' and data.id ~= nil then
			-- The mod "view inventory" shows other players' items: leave those alone.
			if not LocalPlayer:GetAttribute('ViewingProfile') then
				local ov = S.overrides[key(data.id)]
				if ov then
					data = applyOverride(data, ov)
				end
			end
		end
		return data
	end
	-- Faster inventory list fill (also used by the "Apply Aura" weapon picker). The game makes
	-- every missing slot first, then parents 3 per frame and re-measures the canvas after each
	-- one: with ~1000 weapon stacks the picker sat empty for seconds. Same logic, but slots are
	-- made and shown in order, ~25 per frame, canvas re-measured once per batch.
	if getgenv().SB2InvFastFill ~= false and type(inv.IncrementInventoryPlacement) == 'function'
		and type(inv.StackItems) == 'function' and type(inv.ClearupActiveThread) == 'function'
	then
		S.origIncrement = inv.IncrementInventoryPlacement
		inv.IncrementInventoryPlacement = function(u68, u69, u70, u71)
			inv.ClearupActiveThread(u68)
			if not u68.LastStack then
				u68.LastStack = {}
			end
			u68.ActiveUpdateThread = task.defer(function()
				local okRun, errRun = pcall(function()
				local stacks = inv.StackItems(u68, u69)
				local order = {}
				for i, v in pairs(stacks) do
					order[#order + 1] = { i, v }
				end
				table.sort(order, function(a, b)
					return (tonumber(a[2].Index) or 0) < (tonumber(b[2].Index) or 0)
				end)
				local batch = 0
				for _, pair in ipairs(order) do
					local i, v = pair[1], pair[2]
					local v75 = u68.LastStack[i]
					if not v75 then
						-- One broken item must not empty the whole list: skip it instead.
						local okMake = pcall(function()
						local Data = v.Data
						local btn, after = u70(v.Index, Data)
						local fav = Data.item:GetAttribute('Favorited') ~= nil
						local locked = Data.item:GetAttribute('Locked') ~= nil
						btn:SetAttribute('Stack', i)
						btn.Frame.Favorited.Visible = locked or fav
						btn.Frame.Favorited.ImageTransparency = fav and 0 or 0.6
						btn.Frame.Lock.Visible = locked
						btn.Frame.Count.Text = v.Count > 1 and (v.Count or '') or ''
						v.AfterParented = after
						v.BTN = btn
						u68.LastStack[i] = v
						end)
						v75 = okMake and u68.LastStack[i] or nil
						batch += 1
					end
					if v75 then
					v75.BTN.Name = v.Index
					v75.BTN.LayoutOrder = v.Index
					if v75.BTN.Parent ~= u68.iFrame then
						v75.BTN.Parent = u68.iFrame
						if v75.AfterParented then
							pcall(v75.AfterParented)
						end
						batch += 1
					end
					end
					if batch >= 25 then
						batch = 0
						u71()
						task.wait()
					end
				end
				u71()
				end)
				if not okRun then
					getgenv().SB2InvFastFillErr = tostring(errRun)
					warn('[ItemEditor] fast fill: ' .. tostring(errRun))
				end
			end)
		end
	end
	S.on = true
	return true
end

local function stop()
	S.on = false
	if S.inv and S.orig then
		S.inv.GetItemData = S.orig
	end
	if S.inv and S.origIncrement then
		S.inv.IncrementInventoryPlacement = S.origIncrement
	end
	S.inv, S.orig, S.origIncrement = nil, nil, nil
end

local function itemById(id)
	local inv = inventoryFolder()
	if not inv then
		return nil
	end
	for _, it in ipairs(inv:GetChildren()) do
		if it:IsA('ValueBase') and tostring(it.Value) == tostring(id) then
			return it
		end
	end
	return nil
end

-- Game's own values for one item (before overrides), for prefilling the editor.
local function current(id)
	local it = itemById(id)
	if not it or not S.orig then
		return nil
	end
	local ok, data = pcall(S.orig, it)
	if not ok or type(data) ~= 'table' then
		return nil
	end
	local stats = {}
	local maxI = 0
	for i in pairs(data.stats or {}) do
		if type(i) == 'number' and i > maxI then
			maxI = i
		end
	end
	for i = 1, maxI do
		local e = data.stats[i]
		if type(e) == 'table' and type(e[2]) ~= 'boolean' then
			stats[#stats + 1] = { tostring(e[1]), shownValue(data, e[1], tostring(e[2])) }
		end
	end
	return { name = data.name, classname = data.classname, rarity = data.rarity, level = data.level, stats = stats }
end

local EDITABLE_TYPES = { Weapon = true, Clothing = true, Accessory = true, Companion = true }

local function list(query, limit)
	limit = limit or 80
	query = string.lower(tostring(query or ''))
	local inv = inventoryFolder()
	local items = RS:FindFirstChild('Database') and RS.Database:FindFirstChild('Items')
	local out = {}
	if not inv or not items then
		return out
	end
	for _, it in ipairs(inv:GetChildren()) do
		if it:IsA('ValueBase') and not it:FindFirstChild('Count') then
			local db = items:FindFirstChild(it.Name)
			local t = db and db:FindFirstChild('Type')
			if t and EDITABLE_TYPES[t.Value] and (query == '' or string.find(string.lower(it.Name), query, 1, true)) then
				local up = it:FindFirstChild('Upgrade')
				local label = ('%s%s  #%s%s'):format(
					it.Name,
					up and (' +' .. up.Value) or '',
					tostring(it.Value),
					S.overrides[key(it.Value)] and '  (edited)' or ''
				)
				out[#out + 1] = { label = label, id = it.Value, name = it.Name }
				if #out >= limit then
					break
				end
			end
		end
	end
	table.sort(out, function(a, b)
		return a.label < b.label
	end)
	return out
end

g.SB2ItemEditor = {
	build = BUILD,
	start = start,
	stop = stop,
	set = function(id, ov)
		S.overrides[key(id)] = ov
		save()
	end,
	get = function(id)
		return S.overrides[key(id)]
	end,
	clear = function(id)
		S.overrides[key(id)] = nil
		save()
	end,
	clearAll = function()
		S.overrides = {}
		save()
	end,
	count = function()
		local n = 0
		for _ in pairs(S.overrides) do
			n += 1
		end
		return n
	end,
	list = list,
	current = current,
}

return g.SB2ItemEditor
