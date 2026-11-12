-- Client-only weapon / body aura preview (uses in-game Tagged / skin assets).
-- weapon-aura-preview-v9
return function(env)
	local MODULE_BUILD = 'weapon-aura-preview-v9'
	getgenv().SB2WeaponAuraPreviewBuild = MODULE_BUILD
	local Library = env.Library
	local Options = env.Options
	local tab = env.InvTab or env.ItemsTab
	local NONE = env.NONE or '(none)'
	local Players = game:GetService('Players')
	local ReplicatedStorage = game:GetService('ReplicatedStorage')
	local RunService = game:GetService('RunService')
	local CollectionService = game:GetService('CollectionService')

	local getItemsFolder = env.getItemsFolder
	local getItemFolder = env.getItemFolder
	local valueOf = env.valueOf
	local itemKind = env.itemKind

	if type(getItemsFolder) ~= 'function' then
		getItemsFolder = function()
			local db = ReplicatedStorage:FindFirstChild('Database')
			return db and db:FindFirstChild('Items')
		end
	end
	if type(getItemFolder) ~= 'function' then
		getItemFolder = function(name)
			local items = getItemsFolder()
			return items and name and items:FindFirstChild(name)
		end
	end
	if type(valueOf) ~= 'function' then
		valueOf = function(folder, key)
			if not folder then
				return nil
			end
			local ch = folder:FindFirstChild(key)
			if ch and ch:IsA('ValueBase') then
				return ch.Value
			end
			return nil
		end
	end
	if type(itemKind) ~= 'function' then
		itemKind = function(folder)
			local typ = tostring(valueOf(folder, 'Type') or '')
			if typ == 'Skin' then
				return 'Aura'
			end
			return typ
		end
	end

	local PREVIEW_ATTR = '_SB2AuraPreviewRoot'
	local CLONE_MARK = '_SB2AuraPreviewClone'
	local SWING_ATTR = '_SB2PreviewSwingVfx'
	local BODY_MARK = '_SB2BodyAuraPreview'
	-- Forward declare (loadstring-safe; avoids nil calls from `local function` ordering).
	local anchorPart
	local markPreviewTree
	local getWeaponTool
	local stripToolCosmeticVfx
	local attachDatabaseItemVfx
	local isSwingOnlyVfx
	local configurePreviewVfx
	local state = getgenv().SB2WeaponAuraPreviewState
	if type(state) ~= 'table' then
		state = { aura = nil, hands = {}, bodyAura = nil, bodyInst = nil, hiddenBody = {} }
		getgenv().SB2WeaponAuraPreviewState = state
	end
	state.hiddenBody = state.hiddenBody or {}

	local function getServices()
		return getgenv().SB2RequiredServices or getgenv().SB2CardinalServices
	end

	local auraNamesList = {}

	local function flattenOpt(value)
		local fn = getgenv().SB2FlattenOptionValue
		if type(fn) == 'function' then
			local ok, out = pcall(fn, value)
			if ok and out ~= nil then
				return out
			end
		end
		if type(value) == 'string' then
			return value
		end
		if type(value) == 'table' then
			if type(value[1]) == 'string' then
				return value[1]
			end
			for k, on in pairs(value) do
				if on == true and type(k) == 'string' then
					return k
				end
			end
		end
		return tostring(value or '')
	end

	local function isWeaponAuraName(name)
		if type(name) ~= 'string' or name == '' then
			return false
		end
		local lower = string.lower(name)
		if not lower:find('aura', 1, true) then
			return false
		end
		if lower:find('body aura', 1, true) then
			return false
		end
		local folder = getItemFolder(name)
		if not folder then
			return false
		end
		return itemKind(folder) == 'Aura'
	end

	local function resolveAuraDropdownName(raw)
		if raw == nil then
			return nil
		end
		if type(raw) == 'string' and isWeaponAuraName(raw) then
			return raw
		end
		local idx = type(raw) == 'number' and raw or tonumber(flattenOpt(raw))
		if idx and auraNamesList[idx] and isWeaponAuraName(auraNamesList[idx]) then
			return auraNamesList[idx]
		end
		local flat = flattenOpt(raw)
		if type(flat) == 'string' and isWeaponAuraName(flat) then
			return flat
		end
		local opt = Options.WeaponAuraPreviewList
		if opt and type(opt.Values) == 'table' then
			if type(raw) == 'number' and opt.Values[raw] then
				return opt.Values[raw]
			end
			for _, name in ipairs(opt.Values) do
				if name == flat or name == tostring(raw) then
					return name
				end
			end
		end
		return type(flat) == 'string' and flat or nil
	end

	local function listWeaponAuras()
		local items = getItemsFolder()
		if not items then
			return {}
		end
		local names = {}
		for _, child in ipairs(items:GetChildren()) do
			if isWeaponAuraName(child.Name) then
				names[#names + 1] = child.Name
			end
		end
		table.sort(names)
		return names
	end

	local function isBodyAuraName(name)
		if type(name) ~= 'string' or name == '' then
			return false
		end
		local lower = string.lower(name)
		if not lower:find('body aura', 1, true) then
			return false
		end
		local folder = getItemFolder(name)
		if not folder then
			return lower:find('body aura', 1, true) ~= nil
		end
		local kind = itemKind(folder)
		return kind == 'Accessory' or kind == 'Aura' or tostring(valueOf(folder, 'Type') or '') == 'Accessory'
	end

	local bodyAuraNamesList = {}

	local function listBodyAuras()
		local items = getItemsFolder()
		if not items then
			return {}
		end
		local names = {}
		for _, child in ipairs(items:GetChildren()) do
			if isBodyAuraName(child.Name) then
				names[#names + 1] = child.Name
			end
		end
		table.sort(names)
		return names
	end

	local function resolveBodyAuraDropdownName(raw)
		if raw == nil then
			return nil
		end
		if type(raw) == 'string' and isBodyAuraName(raw) then
			return raw
		end
		local idx = type(raw) == 'number' and raw or tonumber(flattenOpt(raw))
		if idx and bodyAuraNamesList[idx] and isBodyAuraName(bodyAuraNamesList[idx]) then
			return bodyAuraNamesList[idx]
		end
		local flat = flattenOpt(raw)
		if type(flat) == 'string' and isBodyAuraName(flat) then
			return flat
		end
		local opt = Options.BodyAuraPreviewList
		if opt and type(opt.Values) == 'table' then
			if type(raw) == 'number' and opt.Values[raw] then
				return opt.Values[raw]
			end
			for _, name in ipairs(opt.Values) do
				if name == flat or name == tostring(raw) then
					return name
				end
			end
		end
		return type(flat) == 'string' and flat or nil
	end

	local function getTaggedFolder()
		local cc = ReplicatedStorage:FindFirstChild('CardinalClient')
		local services = cc and cc:FindFirstChild('MainModule') and cc.MainModule:FindFirstChild('Services')
		return services and services:FindFirstChild('Tagged')
	end

	local function auraNameCandidates(auraName)
		local base = auraName:gsub(' Aura$', '')
		return {
			auraName,
			base,
			base .. 'Skin',
			base .. ' Aura',
		}
	end

	local function findSkinModuleScript(auraName)
		local tagged = getTaggedFolder()
		if not tagged then
			return nil
		end
		local roots = { tagged }
		for _, sub in ipairs({ 'Skins', 'WeaponSkins', 'ItemSkins', 'Auras', 'Weapons', 'Items' }) do
			local f = tagged:FindFirstChild(sub)
			if f then
				roots[#roots + 1] = f
			end
		end
		local seen = {}
		for _, root in ipairs(roots) do
			for _, cand in ipairs(auraNameCandidates(auraName)) do
				local key = root:GetFullName() .. '\0' .. cand
				if not seen[key] then
					seen[key] = true
					local inst = root:FindFirstChild(cand)
					if inst and inst:IsA('ModuleScript') then
						return inst
					end
				end
			end
		end
		return nil
	end

	local function itemFolderHasVfx(folder)
		if not folder then
			return false
		end
		for _, d in ipairs(folder:GetDescendants()) do
			if d:IsA('ParticleEmitter') or d:IsA('Trail') or d:IsA('Beam') or d:IsA('Highlight') then
				return true
			end
		end
		return false
	end

	local function findSkinAssetFolder(auraName)
		local itemFolder = getItemFolder(auraName)
		if itemFolder and itemFolderHasVfx(itemFolder) then
			return itemFolder
		end
		local tagged = getTaggedFolder()
		if not tagged then
			return nil
		end
		for _, cand in ipairs(auraNameCandidates(auraName)) do
			for _, root in ipairs({ tagged, tagged:FindFirstChild('Skins'), tagged:FindFirstChild('WeaponSkins') }) do
				if root then
					local inst = root:FindFirstChild(cand)
					if inst and (inst:IsA('Folder') or inst:IsA('Model')) then
						return inst
					end
				end
			end
		end
		local rs = ReplicatedStorage
		for _, cand in ipairs(auraNameCandidates(auraName)) do
			for _, root in ipairs({
				rs:FindFirstChild('Assets') and rs.Assets:FindFirstChild('Skins'),
				rs:FindFirstChild('Skins'),
			}) do
				if root then
					local inst = root:FindFirstChild(cand)
					if inst and (inst:IsA('Folder') or inst:IsA('Model')) then
						return inst
					end
				end
			end
		end
		return nil
	end

	isSwingOnlyVfx = function(inst)
		if typeof(inst) ~= 'Instance' then
			return false
		end
		if inst:IsA('Trail') then
			return true
		end
		if not (inst:IsA('ParticleEmitter') or inst:IsA('Beam')) then
			return false
		end
		local n = string.lower(tostring(inst.Name))
		return string.find(n, 'swing', 1, true) ~= nil
			or string.find(n, 'slash', 1, true) ~= nil
	end

	configurePreviewVfx = function(inst)
		if typeof(inst) ~= 'Instance' then
			return
		end
		if not (inst:IsA('ParticleEmitter') or inst:IsA('Trail') or inst:IsA('Beam')) then
			return
		end
		if isSwingOnlyVfx(inst) then
			inst:SetAttribute(SWING_ATTR, true)
			inst.Enabled = false
		end
	end

	markPreviewTree = function(inst)
		if typeof(inst) ~= 'Instance' then
			return
		end
		inst:SetAttribute(CLONE_MARK, true)
		configurePreviewVfx(inst)
		for _, d in ipairs(inst:GetDescendants()) do
			d:SetAttribute(CLONE_MARK, true)
			configurePreviewVfx(d)
		end
	end

	local HAND_VALUES = { 'Right', 'Left', 'Both' }

	getWeaponTool = function(hand)
		local lp = Players.LocalPlayer
		local root = workspace:FindFirstChild('CharacterItems')
		root = root and lp and root:FindFirstChild(tostring(lp.UserId))
		if not root then
			return nil
		end
		local folderName = hand == 'Left' and 'LeftWeapon' or 'RightWeapon'
		local folder = root:FindFirstChild(folderName)
		if not folder then
			return nil
		end
		local tool = folder:FindFirstChild('Tool')
		if tool then
			return tool
		end
		for _, child in ipairs(folder:GetChildren()) do
			if child:IsA('Tool') or (child:IsA('Model') and child:FindFirstChild('Blade', true)) then
				return child
			end
		end
		return nil
	end

	local swingCache = {}
	local swingCacheAt = 0
	local function invalidateSwingCache()
		swingCache = {}
		swingCacheAt = 0
	end

	local function collectSwingVfx()
		local now = os.clock()
		if now - swingCacheAt < 0.25 and #swingCache > 0 then
			return swingCache
		end
		local list = {}
		for _, hand in ipairs({ 'Right', 'Left' }) do
			local tool = getWeaponTool(hand)
			if tool then
				for _, d in ipairs(tool:GetDescendants()) do
					if d:GetAttribute(CLONE_MARK) and (d:GetAttribute(SWING_ATTR) or isSwingOnlyVfx(d)) then
						list[#list + 1] = d
					end
				end
			end
		end
		swingCache = list
		swingCacheAt = now
		return list
	end

	local function setSwingVfxEnabled(on)
		for _, d in ipairs(collectSwingVfx()) do
			if d.Parent and d.Enabled ~= on then
				d.Enabled = on
			end
		end
	end

	local function combatAnimPlaying()
		local lp = Players.LocalPlayer
		local char = lp and lp.Character
		local hum = char and char:FindFirstChildOfClass('Humanoid')
		local animator = hum and hum:FindFirstChildOfClass('Animator')
		if not animator then
			return false
		end
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
			local prio = track.Priority
			if prio == Enum.AnimationPriority.Action
				or prio == Enum.AnimationPriority.Action2
				or prio == Enum.AnimationPriority.Action3
				or prio == Enum.AnimationPriority.Action4
			then
				return true
			end
		end
		return false
	end

	local function startTrailGate()
		if state.trailGateConn then
			pcall(function()
				state.trailGateConn:Disconnect()
			end)
			state.trailGateConn = nil
		end
		invalidateSwingCache()
		local swinging = combatAnimPlaying()
		setSwingVfxEnabled(swinging)
		local acc = 0
		state.trailGateConn = RunService.Heartbeat:Connect(function(dt)
			local on = combatAnimPlaying()
			if on ~= swinging then
				swinging = on
				invalidateSwingCache()
				setSwingVfxEnabled(on)
				acc = 0
				return
			end
			if not on then
				acc += dt
				if acc >= 0.15 then
					acc = 0
					setSwingVfxEnabled(false)
				end
			end
		end)
	end

	anchorPart = function(tool)
		if not tool then
			return nil
		end
		return tool:FindFirstChild('Blade')
			or tool:FindFirstChild('Handle')
			or tool:FindFirstChildWhichIsA('BasePart', true)
	end

	-- In-game leaderboard auras parent Highlight to CharacterItems.<uid>.RightWeapon
	-- (sibling of inner Tool / Handle), named AuraHighlight.
	local HL_STASH = '_SB2PreviewHLEnabled'
	local function highlightHost(tool)
		if not tool then
			return nil
		end
		local p = tool.Parent
		if p and (p.Name == 'RightWeapon' or p.Name == 'LeftWeapon') then
			return p
		end
		return tool
	end

	local function eachHighlight(tool, fn)
		local host = highlightHost(tool)
		if not host then
			return
		end
		if host:IsA('Highlight') then
			fn(host)
		end
		for _, d in ipairs(host:GetDescendants()) do
			if d:IsA('Highlight') then
				fn(d)
			end
		end
	end

	local function stashLiveHighlights(tool)
		eachHighlight(tool, function(h)
			if h:GetAttribute(CLONE_MARK) then
				return
			end
			if h:GetAttribute(HL_STASH) == nil then
				h:SetAttribute(HL_STASH, h.Enabled)
			end
			h.Enabled = false
		end)
	end

	local function restoreLiveHighlights(tool)
		local clones = {}
		eachHighlight(tool, function(h)
			if h:GetAttribute(CLONE_MARK) then
				clones[#clones + 1] = h
				return
			end
			local prev = h:GetAttribute(HL_STASH)
			if prev ~= nil then
				h.Enabled = prev == true
				h:SetAttribute(HL_STASH, nil)
			end
		end)
		for _, h in ipairs(clones) do
			h:Destroy()
		end
	end

	stripToolCosmeticVfx = function(tool, previewOnly)
		if not tool then
			return
		end
		for _, d in ipairs(tool:GetDescendants()) do
			if d:IsA('ParticleEmitter') or d:IsA('Trail') or d:IsA('Beam') then
				if not previewOnly or d:GetAttribute(CLONE_MARK) then
					d:Destroy()
				end
			end
		end
		if previewOnly then
			local clones = {}
			eachHighlight(tool, function(h)
				if h:GetAttribute(CLONE_MARK) then
					clones[#clones + 1] = h
				end
			end)
			for _, h in ipairs(clones) do
				h:Destroy()
			end
		end
	end

	attachDatabaseItemVfx = function(auraName, tool)
		local itemFolder = getItemFolder(auraName)
		if not itemFolder or not itemFolderHasVfx(itemFolder) then
			return false, 'no Database.Items VFX for this aura'
		end
		local anchor = anchorPart and anchorPart(tool)
		if not anchor and tool then
			anchor = tool:FindFirstChild('Blade')
				or tool:FindFirstChild('Handle')
				or tool:FindFirstChildWhichIsA('BasePart', true)
		end
		if not anchor then
			return false, 'no anchor part on weapon'
		end
		local att1 = anchor:FindFirstChild('TrailAttachment1')
		local att2 = anchor:FindFirstChild('TrailAttachment2')
		local count = 0
		local seen = {}
		local function cloneVfx(inst)
			if not inst or seen[inst] then
				return
			end
			seen[inst] = true
			local clone = inst:Clone()
			if type(markPreviewTree) == 'function' then
				markPreviewTree(clone)
			else
				clone:SetAttribute(CLONE_MARK, true)
				configurePreviewVfx(clone)
			end
			if clone:IsA('Trail') and att1 and att2 then
				clone.Attachment0 = att1
				clone.Attachment1 = att2
			end
			clone.Parent = anchor
			configurePreviewVfx(clone)
			count += 1
		end
		local function cloneHighlight(inst)
			if not inst or seen[inst] then
				return
			end
			seen[inst] = true
			local host = highlightHost(tool)
			if not host then
				return
			end
			local clone = inst:Clone()
			clone.Name = 'AuraHighlight'
			clone.Enabled = true
			clone.Adornee = nil
			if type(markPreviewTree) == 'function' then
				markPreviewTree(clone)
			else
				clone:SetAttribute(CLONE_MARK, true)
			end
			clone.Parent = host
			count += 1
		end
		for _, d in ipairs(itemFolder:GetDescendants()) do
			if d:IsA('ParticleEmitter') or d:IsA('Trail') or d:IsA('Beam') then
				cloneVfx(d)
			elseif d:IsA('Highlight') then
				cloneHighlight(d)
			end
		end
		if count == 0 then
			return false, 'item folder had no cloneable VFX'
		end
		return true, ('Database.Items (%d VFX)'):format(count)
	end

	local function clearToolPreview(tool)
		if not tool then
			return
		end
		for _, child in ipairs(tool:GetChildren()) do
			if child:GetAttribute(PREVIEW_ATTR) or child.Name == 'SB2AuraPreview' then
				child:Destroy()
			end
		end
		stripToolCosmeticVfx(tool, true)
		for _, d in ipairs(tool:GetDescendants()) do
			if d:GetAttribute(CLONE_MARK) and (d:IsA('ParticleEmitter') or d:IsA('Trail') or d:IsA('Beam')) then
				d:Destroy()
			end
		end
		restoreLiveHighlights(tool)
		if tool:GetAttribute('_SB2PreviewHasAura') ~= nil then
			local old = tool:GetAttribute('_SB2PreviewHasAura')
			if old == false then
				tool:SetAttribute('HasAura', nil)
			else
				tool:SetAttribute('HasAura', old)
			end
			tool:SetAttribute('_SB2PreviewHasAura', nil)
		end
		if tool:GetAttribute('_SB2PreviewSkinName') ~= nil then
			local oldSkin = tool:GetAttribute('_SB2PreviewSkinName')
			if oldSkin == '' or oldSkin == false then
				tool:SetAttribute('SkinName', nil)
			else
				tool:SetAttribute('SkinName', oldSkin)
			end
			tool:SetAttribute('_SB2PreviewSkinName', nil)
		end
	end

	local function weldPartToAnchor(part, anchor)
		if not part:IsA('BasePart') or not anchor then
			return
		end
		part.Anchored = false
		part.CanCollide = false
		part.Massless = true
		local weld = Instance.new('Weld')
		weld.Name = 'SB2AuraPreviewWeld'
		weld:SetAttribute(CLONE_MARK, true)
		weld.Part0 = anchor
		weld.Part1 = part
		weld.C0 = anchor.CFrame:ToObjectSpace(part.CFrame)
		weld.Parent = part
	end

	local function attachAssetFolderToTool(assetFolder, tool)
		local anchor = anchorPart(tool)
		if not anchor then
			return false, 'no anchor part on weapon'
		end
		local host = Instance.new('Folder')
		host.Name = 'SB2AuraPreview'
		host:SetAttribute(PREVIEW_ATTR, true)
		host:SetAttribute(CLONE_MARK, true)
		local clone = assetFolder:Clone()
		markPreviewTree(clone)
		clone.Parent = host
		host.Parent = tool
		for _, d in ipairs(clone:GetDescendants()) do
			if d:IsA('BasePart') then
				weldPartToAnchor(d, anchor)
			elseif d:IsA('Attachment') and d.Parent and d.Parent:IsA('BasePart') then
				-- keep attachment on cloned part
			end
		end
		return true
	end

	local function tryModuleApply(modScript, tool, auraName)
		local okReq, mod = pcall(require, modScript)
		if not okReq then
			return false, 'require failed'
		end
		local tries = {}
		if type(mod) == 'table' then
			tries = {
				function()
					if type(mod.ApplySkin) == 'function' then
						mod.ApplySkin(tool, auraName)
						return true
					end
				end,
				function()
					if type(mod.Apply) == 'function' then
						mod.Apply(tool, auraName)
						return true
					end
				end,
				function()
					if type(mod.Apply) == 'function' then
						mod.Apply(tool)
						return true
					end
				end,
				function()
					if type(mod.Attach) == 'function' then
						mod.Attach(tool)
						return true
					end
				end,
				function()
					if type(mod.new) == 'function' then
						local obj = mod.new(tool, auraName)
						if type(obj) == 'table' and type(obj.Start) == 'function' then
							obj:Start()
						end
						return true
					end
				end,
				function()
					if type(mod.Start) == 'function' then
						mod:Start(tool)
						return true
					end
				end,
			}
		elseif type(mod) == 'function' then
			tries[1] = function()
				mod(tool, auraName)
				return true
			end
		end
		for _, fn in ipairs(tries) do
			local ok, res = pcall(fn)
			if ok and res then
				return true, modScript:GetFullName()
			end
		end
		return false, 'module had no usable Apply'
	end

	local function tryTaggedService(tool, auraName)
		local services = getServices()
		local tagged = services and services.Tagged
		if type(tagged) ~= 'table' then
			return false
		end
		for _, name in ipairs({ 'ApplySkin', 'ApplyItemSkin', 'ApplyAura', 'SetSkin', 'Apply' }) do
			local fn = tagged[name]
			if type(fn) == 'function' then
				local ok = pcall(fn, tool, auraName)
				if ok then
					return true, 'Tagged.' .. name
				end
			end
		end
		return false
	end

	local function tryEquipmentService(tool, auraName)
		local services = getServices()
		local eq = services and services.Equipment
		if type(eq) ~= 'table' then
			return false
		end
		for _, name in ipairs({ 'ApplySkinLocal', 'ApplySkin', 'PreviewSkin', 'UpdateSkin', 'RefreshSkin' }) do
			local fn = eq[name]
			if type(fn) == 'function' then
				local ok = pcall(fn, tool, auraName)
				if ok then
					return true, 'Equipment.' .. name
				end
			end
		end
		return false
	end

	local function setPreviewToolAttributes(tool, auraName)
		if tool:GetAttribute('_SB2PreviewHasAura') == nil and tool:GetAttribute('HasAura') ~= nil then
			tool:SetAttribute('_SB2PreviewHasAura', tool:GetAttribute('HasAura'))
		end
		if tool:GetAttribute('_SB2PreviewSkinName') == nil and tool:GetAttribute('SkinName') ~= nil then
			tool:SetAttribute('_SB2PreviewSkinName', tool:GetAttribute('SkinName'))
		end
		tool:SetAttribute('HasAura', true)
		tool:SetAttribute('SkinName', auraName)
	end

	local function refreshItemEffectState(tool)
		local ev = ReplicatedStorage:FindFirstChild('Event')
		if not ev then
			return false
		end
		local ok = pcall(function()
			ev:FireServer('Equipment', { 'SetItemEffectState', tool })
		end)
		return ok
	end

	local function applyPreviewToHand(auraName, hand, opts)
		opts = opts or {}
		local tool = getWeaponTool(hand)
		if not tool then
			return false, ('no %s weapon equipped'):format(hand)
		end
		clearToolPreview(tool)
		stripToolCosmeticVfx(tool, false)
		stashLiveHighlights(tool)
		setPreviewToolAttributes(tool, auraName)

		local ok, via
		ok, via = attachDatabaseItemVfx(auraName, tool)
		if ok then
			state.hands[hand] = tool
			return true, via
		end

		ok, via = tryEquipmentService(tool, auraName)
		if ok then
			state.hands[hand] = tool
			return true, via
		end
		ok, via = tryTaggedService(tool, auraName)
		if ok then
			state.hands[hand] = tool
			return true, via
		end

		local modScript = findSkinModuleScript(auraName)
		if modScript then
			ok, via = tryModuleApply(modScript, tool, auraName)
			if ok then
				state.hands[hand] = tool
				return true, via
			end
		end

		local asset = findSkinAssetFolder(auraName)
		if asset then
			ok, via = attachAssetFolderToTool(asset, tool)
			if ok then
				state.hands[hand] = tool
				return true, 'asset ' .. asset:GetFullName()
			end
			return false, via
		end

		if opts.allowEffectRefresh == true then
			if refreshItemEffectState(tool) then
				state.hands[hand] = tool
				return true, 'SetItemEffectState (refresh)'
			end
		end

		return false, 'no skin module/asset found for this aura'
	end

	local function resolveHandDropdown(raw)
		if type(raw) == 'number' and HAND_VALUES[raw] then
			return HAND_VALUES[raw]
		end
		local t = flattenOpt(raw)
		local n = tonumber(t)
		if n and HAND_VALUES[n] then
			return HAND_VALUES[n]
		end
		if t == 'Right' or t == 'Left' or t == 'Both' then
			return t
		end
		return 'Both'
	end

	local function listTargetHands(choice)
		if choice == 'Left' then
			return { 'Left' }
		end
		if choice == 'Right' then
			return { 'Right' }
		end
		local hands = {}
		for _, hand in ipairs({ 'Right', 'Left' }) do
			if getWeaponTool(hand) then
				hands[#hands + 1] = hand
			end
		end
		if #hands == 0 then
			return { 'Right' }
		end
		return hands
	end

	local function targetHands()
		local raw = Options.WeaponAuraPreviewHand and Options.WeaponAuraPreviewHand.Value
		return listTargetHands(resolveHandDropdown(raw))
	end

	local function getLocalCharacter()
		local lp = Players.LocalPlayer
		if not lp then
			return nil
		end
		local folder = workspace:FindFirstChild('Characters')
		local live = folder and folder:FindFirstChild(lp.Name)
		if live and live.Parent then
			return live
		end
		return lp.Character
	end

	local function getLocalItemsFolder()
		local lp = Players.LocalPlayer
		local root = workspace:FindFirstChild('CharacterItems')
		if not (lp and root) then
			return nil
		end
		return root:FindFirstChild(tostring(lp.UserId))
	end

	local function bodyNameCandidates(auraName)
		local base = auraName:gsub(' Body Aura$', ''):gsub(' Aura$', '')
		return { auraName, base .. ' Body Aura', base, base .. ' Aura' }
	end

	local function getBodyAuraCacheFolder()
		local folder = ReplicatedStorage:FindFirstChild('_SB2BodyAuraCache')
		if folder and folder:IsA('Folder') then
			return folder
		end
		folder = Instance.new('Folder')
		folder.Name = '_SB2BodyAuraCache'
		folder.Parent = ReplicatedStorage
		return folder
	end

	local function rememberBodyAuraTemplate(inst, auraName)
		if typeof(inst) ~= 'Instance' or inst:GetAttribute(BODY_MARK) then
			return
		end
		auraName = auraName or inst.Name
		if not isBodyAuraName(auraName) and not isBodyAuraName(inst.Name) then
			if not string.lower(tostring(inst.Name)):find('body aura', 1, true) then
				return
			end
			auraName = inst.Name
		end
		local cache = getBodyAuraCacheFolder()
		if cache:FindFirstChild(auraName) then
			return
		end
		local ok, clone = pcall(function()
			return inst:Clone()
		end)
		if not ok or not clone then
			return
		end
		clone.Name = auraName
		clone.Parent = cache
	end

	local function findLiveBodyAccessory(auraName)
		local root = workspace:FindFirstChild('CharacterItems')
		if not root then
			return nil
		end
		local lp = Players.LocalPlayer
		local selfId = lp and tostring(lp.UserId)
		local cands = bodyNameCandidates(auraName)
		local function searchFolder(folder)
			if not folder then
				return nil
			end
			for _, cand in ipairs(cands) do
				local inst = folder:FindFirstChild(cand)
				if inst and not inst:GetAttribute(BODY_MARK) then
					return inst
				end
			end
			return nil
		end
		for _, folder in ipairs(root:GetChildren()) do
			if folder.Name ~= selfId then
				local inst = searchFolder(folder)
				if inst then
					return inst
				end
			end
		end
		return searchFolder(selfId and root:FindFirstChild(selfId))
	end

	local function findCachedBodyTemplate(auraName)
		local cache = ReplicatedStorage:FindFirstChild('_SB2BodyAuraCache')
		if not cache then
			return nil
		end
		for _, cand in ipairs(bodyNameCandidates(auraName)) do
			local inst = cache:FindFirstChild(cand)
			if inst then
				return inst
			end
		end
		return nil
	end

	local function findTaggedBodyHostTemplate(auraName)
		local tagged = getTaggedFolder()
		if not tagged then
			return nil
		end
		for _, folderName in ipairs({ 'BodyAuras', 'Accessories' }) do
			local root = tagged:FindFirstChild(folderName)
			if root then
				for _, cand in ipairs(bodyNameCandidates(auraName)) do
					local mod = root:FindFirstChild(cand)
					if mod then
						for _, ch in ipairs(mod:GetChildren()) do
							if ch:IsA('Accessory') or ch:IsA('Model') or ch:IsA('BasePart') then
								return ch
							end
						end
					end
				end
			end
		end
		return nil
	end

	local function retargetAccessoryWelds(clone, char)
		if not (clone and char) then
			return
		end
		for _, w in ipairs(clone:GetDescendants()) do
			if w:IsA('Weld') or w:IsA('WeldConstraint') or w:IsA('Motor6D') then
				for _, prop in ipairs({ 'Part0', 'Part1' }) do
					local part = w[prop]
					if part and not part:IsDescendantOf(clone) then
						local bp = char:FindFirstChild(part.Name)
						if bp and bp:IsA('BasePart') then
							w[prop] = bp
						end
					end
				end
			end
		end
	end

	local function enableBodyPreviewVfx(inst)
		if typeof(inst) ~= 'Instance' then
			return
		end
		local function touch(d)
			if d:IsA('ParticleEmitter') or d:IsA('Trail') or d:IsA('Beam') then
				d.Enabled = true
			end
		end
		touch(inst)
		for _, d in ipairs(inst:GetDescendants()) do
			touch(d)
		end
	end

	local function markBodyPreviewTree(inst)
		if typeof(inst) ~= 'Instance' then
			return
		end
		inst:SetAttribute(BODY_MARK, true)
		for _, d in ipairs(inst:GetDescendants()) do
			d:SetAttribute(BODY_MARK, true)
		end
	end

	local function getBodyAuraHideFolder()
		local folder = ReplicatedStorage:FindFirstChild('_SB2BodyAuraHidden')
		if folder and folder:IsA('Folder') then
			return folder
		end
		folder = Instance.new('Folder')
		folder.Name = '_SB2BodyAuraHidden'
		folder.Parent = ReplicatedStorage
		return folder
	end

	local function restoreHiddenBodyAuras()
		local folder = getLocalItemsFolder()
		for _, inst in ipairs(state.hiddenBody or {}) do
			if inst and inst.Parent then
				if folder then
					pcall(function()
						inst.Parent = folder
					end)
				end
			end
		end
		state.hiddenBody = {}
	end

	local function hideRealBodyAuras()
		restoreHiddenBodyAuras()
		local folder = getLocalItemsFolder()
		if not folder then
			return
		end
		local hide = getBodyAuraHideFolder()
		for _, ch in ipairs(folder:GetChildren()) do
			if not ch:GetAttribute(BODY_MARK) then
				local n = string.lower(ch.Name)
				if n:find('body aura', 1, true) then
					state.hiddenBody[#state.hiddenBody + 1] = ch
					pcall(function()
						ch.Parent = hide
					end)
				end
			end
		end
	end

	local function clearBodyPreview()
		restoreHiddenBodyAuras()
		local folder = getLocalItemsFolder()
		if folder then
			for _, ch in ipairs(folder:GetChildren()) do
				if ch:GetAttribute(BODY_MARK) then
					pcall(function()
						CollectionService:RemoveTag(ch, ch.Name)
					end)
					ch:Destroy()
				end
			end
		end
		if state.bodyInst and state.bodyInst.Parent then
			pcall(function()
				CollectionService:RemoveTag(state.bodyInst, state.bodyInst.Name)
			end)
			state.bodyInst:Destroy()
		end
		state.bodyInst = nil
		state.bodyAura = nil
	end

	local function startBodyAuraCacheWatch()
		if state.bodyCacheConn then
			pcall(function()
				state.bodyCacheConn:Disconnect()
			end)
			state.bodyCacheConn = nil
		end
		local root = workspace:FindFirstChild('CharacterItems')
		if not root then
			return
		end
		local function consider(inst)
			if typeof(inst) ~= 'Instance' then
				return
			end
			if inst:GetAttribute(BODY_MARK) then
				return
			end
			if inst:IsA('Accessory') or inst:IsA('Model') then
				if string.lower(inst.Name):find('body aura', 1, true) then
					rememberBodyAuraTemplate(inst, inst.Name)
				end
			end
		end
		for _, folder in ipairs(root:GetChildren()) do
			for _, ch in ipairs(folder:GetChildren()) do
				consider(ch)
			end
		end
		state.bodyCacheConn = root.DescendantAdded:Connect(function(inst)
			if inst:IsA('Accessory') or inst:IsA('Model') then
				consider(inst)
			elseif inst.Parent and (inst.Parent:IsA('Accessory') or inst.Parent:IsA('Model')) then
				consider(inst.Parent)
			end
		end)
	end

	local function applyBodyPreview(auraName)
		auraName = resolveBodyAuraDropdownName(auraName) or auraName
		if type(auraName) ~= 'string' or auraName == '' or auraName == NONE then
			return false, 'pick a body aura'
		end
		if not isBodyAuraName(auraName) then
			return false, ('not a body aura item (%s)'):format(tostring(auraName))
		end
		local char = getLocalCharacter()
		local folder = getLocalItemsFolder()
		if not char then
			return false, 'no character'
		end
		if not folder then
			return false, 'no CharacterItems folder'
		end
		clearBodyPreview()
		hideRealBodyAuras()
		local src = findLiveBodyAccessory(auraName)
			or findCachedBodyTemplate(auraName)
			or findTaggedBodyHostTemplate(auraName)
		local via
		local clone
		if src then
			rememberBodyAuraTemplate(src, auraName)
			local ok, cloned = pcall(function()
				return src:Clone()
			end)
			if not ok or not cloned then
				restoreHiddenBodyAuras()
				return false, 'clone failed'
			end
			clone = cloned
			via = 'cloned ' .. src:GetFullName()
		else
			clone = Instance.new('Accessory')
			clone.Name = auraName
			via = 'tagged host (no 3D template on this client — cached when someone wears it)'
		end
		clone.Name = auraName
		markBodyPreviewTree(clone)
		clone.Parent = folder
		retargetAccessoryWelds(clone, char)
		enableBodyPreviewVfx(clone)
		pcall(function()
			CollectionService:AddTag(clone, auraName)
		end)
		state.bodyInst = clone
		state.bodyAura = auraName
		return true, via
	end

	local function clearPreview()
		for _, hand in ipairs({ 'Right', 'Left' }) do
			clearToolPreview(getWeaponTool(hand))
		end
		clearBodyPreview()
		state.aura = nil
		state.hands = {}
		invalidateSwingCache()
	end

	local function applyPreview(auraName)
		auraName = resolveAuraDropdownName(auraName) or auraName
		if type(auraName) ~= 'string' or auraName == '' or auraName == NONE then
			return false, 'pick an aura'
		end
		if not isWeaponAuraName(auraName) then
			return false, ('not a weapon aura item (%s)'):format(tostring(auraName))
		end
		local allowRefresh = Options.WeaponAuraPreviewRefresh
			and Options.WeaponAuraPreviewRefresh.Value == true
		local hands = targetHands()
		local msgs = {}
		local allOk = true
		for _, hand in ipairs(hands) do
			local callOk, handOk, msg = pcall(applyPreviewToHand, auraName, hand, { allowEffectRefresh = allowRefresh })
			if not callOk then
				msgs[#msgs + 1] = hand .. ': error ' .. tostring(handOk)
				allOk = false
			else
				msgs[#msgs + 1] = hand .. ': ' .. tostring(msg)
				allOk = allOk and handOk == true
			end
		end
		if allOk then
			state.aura = auraName
		end
		invalidateSwingCache()
		setSwingVfxEnabled(combatAnimPlaying())
		return allOk, table.concat(msgs, ' | ')
	end

	getgenv().SB2WeaponAuraPreviewApply = applyPreview
	getgenv().SB2WeaponAuraPreviewClear = clearPreview
	getgenv().SB2ListWeaponAuras = listWeaponAuras
	getgenv().SB2BodyAuraPreviewApply = applyBodyPreview
	getgenv().SB2BodyAuraPreviewClear = clearBodyPreview
	getgenv().SB2ListBodyAuras = listBodyAuras
	startTrailGate()
	startBodyAuraCacheWatch()
	warn('[WeaponAuraPreview] loaded ', MODULE_BUILD)

	if type(tab) ~= 'table' or type(tab.AddRightGroupbox) ~= 'function' then
		warn('[WeaponAuraPreview] InvTab/ItemsTab missing — UI not created')
		return
	end

	local weaponUiExists = type(Options) == 'table' and Options.WeaponAuraPreviewList ~= nil
	local bodyUiExists = type(Options) == 'table' and Options.BodyAuraPreviewList ~= nil
	if weaponUiExists and bodyUiExists then
		warn('[WeaponAuraPreview] functions refreshed ', MODULE_BUILD)
		return
	end

	if not weaponUiExists then
		auraNamesList = listWeaponAuras()
		local auraNames = auraNamesList
		local defaultAura = (#auraNames > 0 and auraNames[1]) or NONE
		local PreviewBox = tab:AddRightGroupbox('Weapon aura preview')
		PreviewBox:AddLabel('Client-only — replaces blade VFX on chosen hand(s). Re-equip to restore real skins.')

		PreviewBox:AddDropdown('WeaponAuraPreviewList', {
			Text = 'Weapon aura',
			Values = #auraNames > 0 and auraNames or { NONE },
			Default = defaultAura,
			AllowNull = true,
			Searchable = true,
		})

		PreviewBox:AddDropdown('WeaponAuraPreviewHand', {
			Text = 'Hand',
			Values = { 'Right', 'Left', 'Both' },
			Default = 'Both',
		})

		PreviewBox:AddToggle('WeaponAuraPreviewRefresh', {
			Text = 'Also fire SetItemEffectState',
			Default = false,
			Tooltip = 'One Equipment refresh per apply (same as in-game effect sync). Off = pure client attach only.',
		})

		PreviewBox:AddButton('Apply preview', function()
			local raw = Options.WeaponAuraPreviewList and Options.WeaponAuraPreviewList.Value
			local name = resolveAuraDropdownName(raw) or flattenOpt(raw)
			local fn = getgenv().SB2WeaponAuraPreviewApply or applyPreview
			local callOk, ok, msg = pcall(fn, name)
			if not callOk then
				Library:Notify(('Aura preview error: %s'):format(tostring(ok)), 10)
			elseif ok then
				Library:Notify(('Preview: %s (%s)'):format(tostring(name), tostring(msg)), 8)
			else
				Library:Notify(('Aura preview failed: %s'):format(tostring(msg)), 10)
			end
		end)

		PreviewBox:AddButton('Clear preview', function()
			local fn = getgenv().SB2WeaponAuraPreviewClear or clearPreview
			fn()
			Library:Notify('Cleared weapon aura preview', 4)
		end)

		PreviewBox:AddButton('Rescan aura list', function()
			auraNamesList = listWeaponAuras()
			auraNames = auraNamesList
			local vals = #auraNames > 0 and auraNames or { NONE }
			if env.setDropdown then
				env.setDropdown(Options.WeaponAuraPreviewList, vals, NONE)
			end
			Library:Notify(('Weapon auras: %d'):format(#auraNames), 4)
		end)
	end

	if not bodyUiExists then
		bodyAuraNamesList = listBodyAuras()
		local bodyNames = bodyAuraNamesList
		local defaultBody = (#bodyNames > 0 and bodyNames[1]) or NONE
		local BodyBox = tab:AddRightGroupbox('Body aura preview')
		BodyBox:AddLabel('Client-only — clones the accessory onto you. 3D is cached when anyone in the server wears that aura.')

		BodyBox:AddDropdown('BodyAuraPreviewList', {
			Text = 'Body aura',
			Values = #bodyNames > 0 and bodyNames or { NONE },
			Default = defaultBody,
			AllowNull = true,
			Searchable = true,
		})

		BodyBox:AddButton('Apply body preview', function()
			local raw = Options.BodyAuraPreviewList and Options.BodyAuraPreviewList.Value
			local name = resolveBodyAuraDropdownName(raw) or flattenOpt(raw)
			local fn = getgenv().SB2BodyAuraPreviewApply or applyBodyPreview
			local callOk, ok, msg = pcall(fn, name)
			if not callOk then
				Library:Notify(('Body aura preview error: %s'):format(tostring(ok)), 10)
			elseif ok then
				Library:Notify(('Body preview: %s (%s)'):format(tostring(name), tostring(msg)), 8)
			else
				Library:Notify(('Body aura preview failed: %s'):format(tostring(msg)), 10)
			end
		end)

		BodyBox:AddButton('Clear body preview', function()
			local fn = getgenv().SB2BodyAuraPreviewClear or clearBodyPreview
			fn()
			Library:Notify('Cleared body aura preview', 4)
		end)

		BodyBox:AddButton('Rescan body auras', function()
			bodyAuraNamesList = listBodyAuras()
			bodyNames = bodyAuraNamesList
			local vals = #bodyNames > 0 and bodyNames or { NONE }
			if env.setDropdown then
				env.setDropdown(Options.BodyAuraPreviewList, vals, NONE)
			end
			Library:Notify(('Body auras: %d'):format(#bodyNames), 4)
		end)
	end
end
