--[[
	Titling.lua - preview SpecialAlias titles + build custom nameplate titles.

	Game titles: MainModule.Services.Graphics.SpecialAlias.* via `.new(label, {UserId})`.
	Custom titles: local UIGradient / UIStroke / Icon / optional loops (client-only).
]]

return function(env)
	local WikiTab = env.WikiTab or env.ItemsTab
	local Library = env.Library
	local Options = env.Options
	local LocalPlayer = env.LocalPlayer
	local NONE = env.NONE or '---'
	local setDropdown = env.setDropdown
	local registerWikiBox = env.registerWikiBox
	local Players = game:GetService('Players')
	local CollectionService = game:GetService('CollectionService')
	local ReplicatedStorage = game:GetService('ReplicatedStorage')
	local TweenService = game:GetService('TweenService')
	local HttpService = game:GetService('HttpService')

	local CUSTOM_PRESETS_PATH = 'PlayerTools/custom_titles.json'
	local DEFAULT_SPARK_IMAGE = 'rbxassetid://8310516210'
	local DEFAULT_ICON_IMAGE = 'rbxassetid://2607452359'

	local TitlingBox = WikiTab:AddLeftGroupbox('Titling')
	assert(TitlingBox, 'Titling groupbox nil')
	if type(registerWikiBox) == 'function' then
		pcall(registerWikiBox, TitlingBox)
	end

	local CustomBox = WikiTab:AddLeftGroupbox('Custom title')
	assert(CustomBox, 'Custom title groupbox nil')
	if type(registerWikiBox) == 'function' then
		pcall(registerWikiBox, CustomBox)
	end

	TitlingBox:AddLabel('Preview SpecialAlias titles on a nameplate (client-only).')

	local savedPlates = {}
	local activeFx = {} -- [label] = { token = number, conns = {..} }

	local function stopCustomFx(label)
		local fx = label and activeFx[label]
		if not fx then
			return
		end
		fx.token = (fx.token or 0) + 1
		if fx.conns then
			for _, c in ipairs(fx.conns) do
				pcall(function()
					c:Disconnect()
				end)
			end
		end
		activeFx[label] = nil
	end

	-- SpecialAlias loops (Blossom/Plasmatic/custom sparks) keep a hard ref to the Tag
	-- TextLabel and keep parenting Image overlays after we only Destroy children.
	-- Replacing the Tag instance makes those loops see Parent==nil and exit.
	local function resetNameplateTag(oldLabel)
		if not oldLabel or not oldLabel.Parent then
			return nil
		end
		stopCustomFx(oldLabel)
		pcall(function()
			for _, tag in ipairs(CollectionService:GetTags(oldLabel)) do
				CollectionService:RemoveTag(oldLabel, tag)
			end
		end)
		local parent = oldLabel.Parent
		local behide = parent:FindFirstChild('BehideFrame')
		if behide then
			pcall(function()
				behide:Destroy()
			end)
		end

		local fresh = Instance.new('TextLabel')
		local copyProps = {
			'Name',
			'Text',
			'TextColor3',
			'TextSize',
			'Font',
			'Size',
			'Position',
			'AnchorPoint',
			'LayoutOrder',
			'ZIndex',
			'BackgroundColor3',
			'BackgroundTransparency',
			'BorderSizePixel',
			'TextStrokeColor3',
			'TextStrokeTransparency',
			'TextTransparency',
			'TextXAlignment',
			'TextYAlignment',
			'RichText',
			'TextScaled',
			'TextWrapped',
			'AutomaticSize',
			'Visible',
			'ClipsDescendants',
			'MaxVisibleGraphemes',
		}
		for _, prop in ipairs(copyProps) do
			pcall(function()
				fresh[prop] = oldLabel[prop]
			end)
		end
		pcall(function()
			if oldLabel.FontFace then
				fresh.FontFace = oldLabel.FontFace
			end
		end)
		for _, attr in ipairs(oldLabel:GetAttributes()) do
			pcall(function()
				fresh:SetAttribute(attr, oldLabel:GetAttribute(attr))
			end)
		end
		fresh.Name = oldLabel.Name
		fresh.TextColor3 = Color3.new(1, 1, 1)
		fresh.RichText = false

		local order = oldLabel.LayoutOrder
		pcall(function()
			oldLabel:Destroy()
		end)
		fresh.Parent = parent
		fresh.LayoutOrder = order
		return fresh
	end

	local function getProfilesFolder()
		return ReplicatedStorage:FindFirstChild('Profiles')
	end

	local function listPlayerNames()
		local names = {}
		local seen = {}
		local function add(n)
			if type(n) ~= 'string' or n == '' or seen[n] then
				return
			end
			seen[n] = true
			names[#names + 1] = n
		end
		local folder = workspace:FindFirstChild('Characters')
		if folder then
			for _, ch in ipairs(folder:GetChildren()) do
				add(ch.Name)
			end
		end
		local profiles = getProfilesFolder()
		if profiles then
			for _, child in ipairs(profiles:GetChildren()) do
				if not child:IsA('LocalScript') and not child:IsA('ModuleScript') and not child:IsA('Script') then
					add(child.Name)
				end
			end
		end
		for _, plr in ipairs(Players:GetPlayers()) do
			add(plr.Name)
		end
		table.sort(names, function(a, b)
			return a:lower() < b:lower()
		end)
		return names
	end

	local function findSpecialAliasModule(tagName)
		if type(tagName) ~= 'string' or tagName == '' then
			return nil
		end
		if type(getloadedmodules) == 'function' then
			for _, mod in ipairs(getloadedmodules()) do
				if mod.Name == tagName and mod:GetFullName():find('SpecialAlias', 1, true) then
					return mod
				end
			end
		end
		local cc = ReplicatedStorage:FindFirstChild('CardinalClient')
		local main = cc and cc:FindFirstChild('MainModule')
		local services = main and main:FindFirstChild('Services')
		local graphics = services and services:FindFirstChild('Graphics')
		local alias = graphics and graphics:FindFirstChild('SpecialAlias')
		local mod = alias and alias:FindFirstChild(tagName)
		if mod and mod:IsA('ModuleScript') then
			return mod
		end
		return nil
	end

	local function listTitleNames()
		local names = {}
		local seen = {}
		local function add(n)
			if type(n) ~= 'string' or n == '' or n == NONE or seen[n] then
				return
			end
			seen[n] = true
			names[#names + 1] = n
		end
		if type(getloadedmodules) == 'function' then
			for _, mod in ipairs(getloadedmodules()) do
				if mod:IsA('ModuleScript') and mod:GetFullName():find('SpecialAlias', 1, true) then
					add(mod.Name)
				end
			end
		end
		local profiles = getProfilesFolder()
		if profiles then
			for _, profile in ipairs(profiles:GetChildren()) do
				local ct = profile:FindFirstChild('CosmeticTags')
				if ct then
					for _, child in ipairs(ct:GetChildren()) do
						if child:IsA('BoolValue') or child:IsA('StringValue') then
							add(child.Name)
						end
					end
				end
				local cur = profile:FindFirstChild('CurrentTag')
				if cur and cur:IsA('ValueBase') and tostring(cur.Value) ~= '' then
					add(tostring(cur.Value))
				end
			end
		end
		table.sort(names, function(a, b)
			return a:lower() < b:lower()
		end)
		return names, seen
	end

	local function resolveCharacter(name)
		if type(name) ~= 'string' or name == '' then
			return nil
		end
		local folder = workspace:FindFirstChild('Characters')
		local char = folder and folder:FindFirstChild(name)
		if char then
			return char
		end
		local plr = Players:FindFirstChild(name)
		return plr and plr.Character or nil
	end

	local function getNameplateTag(char)
		if not char then
			return nil
		end
		local np = char:FindFirstChild('Nameplate')
		return np and np:FindFirstChild('Tag', true) or nil
	end

	local function snapshotPlate(key, label)
		if not label or savedPlates[key] then
			return
		end
		local tags = {}
		pcall(function()
			for _, t in ipairs(CollectionService:GetTags(label)) do
				tags[#tags + 1] = t
			end
		end)
		savedPlates[key] = {
			text = label.Text,
			tags = tags,
		}
	end

	local function stripTitleDecor(label)
		if not label then
			return
		end
		stopCustomFx(label)
		for _, child in ipairs(label:GetChildren()) do
			if child:IsA('UIGradient')
				or child:IsA('UIStroke')
				or child:IsA('UIPadding')
				or child:IsA('ImageLabel')
				or child:IsA('ImageButton')
				or child:IsA('Frame')
			then
				pcall(function()
					child:Destroy()
				end)
			end
		end
		local parent = label.Parent
		if parent then
			local behide = parent:FindFirstChild('BehideFrame')
			if behide then
				pcall(function()
					behide:Destroy()
				end)
			end
		end
		pcall(function()
			label.TextColor3 = Color3.new(1, 1, 1)
			label.RichText = false
			label.ZIndex = 1
		end)
	end

	local function resolveUserId(playerName)
		if type(playerName) ~= 'string' or playerName == '' then
			return nil
		end
		local plr = Players:FindFirstChild(playerName)
		if plr then
			return plr.UserId
		end
		local ok, id = pcall(function()
			return Players:GetUserIdFromNameAsync(playerName)
		end)
		if ok and type(id) == 'number' then
			return id
		end
		return nil
	end

	local function clearKnownTags(label, knownSet)
		if not label then
			return
		end
		pcall(function()
			for _, tag in ipairs(CollectionService:GetTags(label)) do
				if not knownSet or knownSet[tag] then
					CollectionService:RemoveTag(label, tag)
				end
			end
		end)
	end

	local function applyTitleToLabel(label, tagName, knownSet, userId)
		if not label or type(tagName) ~= 'string' or tagName == '' then
			return false, 'missing label/tag', nil
		end
		label = resetNameplateTag(label)
		if not label then
			return false, 'could not reset nameplate tag', nil
		end

		local modScript = findSpecialAliasModule(tagName)
		if not modScript then
			label.Text = '[' .. tagName .. ']'
			return true, 'text-only (no SpecialAlias module)', label
		end

		local okReq, mod = pcall(require, modScript)
		if not okReq or type(mod) ~= 'table' then
			label.Text = '[' .. tagName .. ']'
			return true, 'text-only (require failed)', label
		end

		label.Text = '[' .. tagName .. ']'
		local effectData = { UserId = userId }
		if type(mod.new) == 'function' then
			local okNew = pcall(mod.new, label, effectData)
			if okNew then
				pcall(function()
					CollectionService:AddTag(label, tagName)
				end)
				local hasFx = false
				for _, child in ipairs(label:GetChildren()) do
					if child:IsA('UIGradient') or child:IsA('UIStroke') or child:IsA('ImageLabel') then
						hasFx = true
						break
					end
				end
				if hasFx then
					return true, 'SpecialAlias.new', label
				end
			end
		end

		local cloned = 0
		for _, child in ipairs(modScript:GetChildren()) do
			if child:IsA('UIGradient')
				or child:IsA('UIStroke')
				or child:IsA('UIPadding')
				or child:IsA('ImageLabel')
				or child:IsA('ImageButton')
			then
				local okC = pcall(function()
					child:Clone().Parent = label
				end)
				if okC then
					cloned += 1
				end
			end
		end
		pcall(function()
			CollectionService:AddTag(label, tagName)
		end)
		if cloned > 0 then
			return true, 'cloned-assets', label
		end
		return true, 'text-only', label
	end

	local function colorToHex(c)
		if typeof(c) ~= 'Color3' then
			return 'FFFFFF'
		end
		return string.format('%02X%02X%02X', math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
	end

	local function readColor(opt, fallback)
		local v = opt and opt.Value
		if typeof(v) == 'Color3' then
			return v
		end
		return fallback
	end

	local function normalizeAsset(raw)
		if type(raw) ~= 'string' then
			raw = tostring(raw or '')
		end
		raw = raw:gsub('%s+', '')
		if raw == '' then
			return ''
		end
		local id = raw:match('(%d+)')
		if id then
			return 'rbxassetid://' .. id
		end
		if raw:find('rbxasset', 1, true) then
			return raw
		end
		return ''
	end

	local function applyCustomToLabel(label, cfg)
		if not label or type(cfg) ~= 'table' then
			return false, 'missing', nil
		end
		label = resetNameplateTag(label)
		if not label then
			return false, 'could not reset nameplate tag', nil
		end

		local text = tostring(cfg.text or 'Custom')
		if text == '' then
			text = 'Custom'
		end
		if cfg.brackets ~= false then
			label.Text = '[' .. text .. ']'
		else
			label.Text = text
		end
		label.TextColor3 = Color3.new(1, 1, 1)

		local c1 = cfg.c1 or Color3.fromRGB(255, 215, 0)
		local c2 = cfg.c2 or Color3.fromRGB(255, 215, 0)
		local c3 = cfg.c3 or Color3.fromRGB(255, 154, 65)
		local strokeCol = cfg.stroke or Color3.fromRGB(40, 40, 60)
		local thickness = tonumber(cfg.thickness) or 1.5
		local anim = tostring(cfg.anim or 'None')
		local iconAsset = normalizeAsset(cfg.icon or '')
		local sparkAsset = normalizeAsset(cfg.spark or '')
		if sparkAsset == '' then
			sparkAsset = DEFAULT_SPARK_IMAGE
		end

		local grad = Instance.new('UIGradient')
		grad.Name = 'Gradient'
		grad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, c1),
			ColorSequenceKeypoint.new(0.5, c2),
			ColorSequenceKeypoint.new(1, c3),
		})
		grad.Parent = label

		local stroke = Instance.new('UIStroke')
		stroke.Name = 'UIStroke'
		stroke.Color = strokeCol
		stroke.Thickness = thickness
		stroke.Parent = label

		local icon
		if iconAsset ~= '' then
			icon = Instance.new('ImageLabel')
			icon.Name = 'Icon'
			icon.BackgroundTransparency = 1
			icon.Image = iconAsset
			icon.AnchorPoint = Vector2.new(0.5, 0.5)
			icon.Position = UDim2.fromScale(0.9, 0.5)
			icon.Size = UDim2.fromScale(0.1, 1)
			icon.ZIndex = 2
			icon.Parent = label
			local ig = Instance.new('UIGradient')
			ig.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, c1),
				ColorSequenceKeypoint.new(1, c2),
			})
			ig.Parent = icon
		end

		local fx = { token = 1, conns = {} }
		activeFx[label] = fx
		local token = fx.token

		local function alive()
			return activeFx[label] == fx and fx.token == token and label.Parent ~= nil
		end

		local wantSlide = anim == 'Gradient slide' or anim == 'Full' or anim == 'Cursed Full'
		local wantPulse = anim == 'Icon pulse' or anim == 'Full' or anim == 'Cursed Full'
		local wantSparks = anim == 'Sparks' or anim == 'Full' or anim == 'Cursed Full'
		local wantGlitch = anim == 'Glitch text' or anim == 'Cursed' or anim == 'Cursed Full'

		if wantSlide then
			task.defer(function()
				while alive() do
					local t1 = TweenService:Create(grad, TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
						Offset = Vector2.new(0, -0.35),
					})
					t1:Play()
					t1.Completed:Wait()
					if not alive() then
						break
					end
					local t2 = TweenService:Create(grad, TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
						Offset = Vector2.new(0, 0.35),
					})
					t2:Play()
					t2.Completed:Wait()
				end
			end)
		end

		if icon and wantPulse then
			task.defer(function()
				while alive() and icon.Parent do
					local t1 = TweenService:Create(icon, TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
						Size = UDim2.fromScale(0.13, 1.15),
					})
					t1:Play()
					t1.Completed:Wait()
					if not alive() then
						break
					end
					local t2 = TweenService:Create(icon, TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
						Size = UDim2.fromScale(0.1, 1),
					})
					t2:Play()
					t2.Completed:Wait()
				end
			end)
		end

		if wantSparks then
			task.defer(function()
				while alive() do
					local burst = math.random(5, 8)
					for _ = 1, burst do
						if not alive() then
							break
						end
						local spark = Instance.new('ImageLabel')
						spark.Name = 'Image'
						spark.BackgroundTransparency = 1
						spark.Image = sparkAsset
						local tint = ({ c1, c2, c3 })[math.random(1, 3)]
						spark.ImageColor3 = tint
						spark.AnchorPoint = Vector2.new(0.5, 0.5)
						spark.Position = UDim2.fromScale(0.05 + math.random() * 0.9, 0.05 + math.random() * 0.9)
						local s = 0.035 + math.random() * 0.07
						spark.Size = UDim2.fromScale(s, s)
						spark.ZIndex = 3
						spark.ImageTransparency = 0.05 + math.random() * 0.2
						spark.Rotation = math.random(-25, 25)
						spark.Parent = label
						task.defer(function()
							local tw = TweenService:Create(spark, TweenInfo.new(0.55 + math.random() * 0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
								ImageTransparency = 1,
								Position = spark.Position + UDim2.fromScale((math.random() - 0.5) * 0.35, -0.15 - math.random() * 0.35),
								Size = UDim2.fromScale(s * 0.25, s * 0.25),
								Rotation = spark.Rotation + math.random(-40, 40),
							})
							tw:Play()
							tw.Completed:Wait()
							pcall(function()
								spark:Destroy()
							end)
						end)
					end
					task.wait(0.07 + math.random() * 0.06)
				end
			end)
		end

		-- Cursed One style: briefly corrupt many characters to "_" then restore.
		if wantGlitch then
			task.defer(function()
				while alive() do
					local base = label.Text
					if type(base) == 'string' and #base > 3 then
						local flashes = math.random(2, 4)
						for flash = 1, flashes do
							if not alive() then
								break
							end
							local chars = {}
							for i = 1, #base do
								chars[i] = string.sub(base, i, i)
							end
							local eligible = {}
							for i = 1, #chars do
								local ch = chars[i]
								if ch ~= '[' and ch ~= ']' and ch ~= ' ' then
									eligible[#eligible + 1] = i
								end
							end
							if #eligible > 0 then
								local n = math.clamp(math.random(math.max(3, math.floor(#eligible * 0.45)), math.max(4, math.floor(#eligible * 0.85))), 1, #eligible)
								-- shuffle pick
								for i = #eligible, 2, -1 do
									local j = math.random(1, i)
									eligible[i], eligible[j] = eligible[j], eligible[i]
								end
								for i = 1, n do
									chars[eligible[i]] = '_'
								end
								label.Text = table.concat(chars)
							end
							task.wait(0.045 + math.random() * 0.05)
							if not alive() then
								break
							end
							label.Text = base
							if flash < flashes then
								task.wait(0.02 + math.random() * 0.03)
							end
						end
					end
					task.wait(0.12 + math.random() * 0.18)
				end
			end)
		end

		return true, 'custom', label
	end

	local function restorePlate(key)
		local char = resolveCharacter(key)
		local label = getNameplateTag(char)
		local snap = savedPlates[key]
		if not label then
			return false, 'nameplate not loaded'
		end
		local _, knownSet = listTitleNames()
		label = resetNameplateTag(label)
		if not label then
			return false, 'could not reset nameplate tag'
		end
		if snap then
			pcall(function()
				label.Text = snap.text
			end)
			local originalName = tostring(snap.text or ''):match('%[(.-)%]') or (snap.tags and snap.tags[1])
			if originalName and originalName ~= '' then
				applyTitleToLabel(label, originalName, knownSet, resolveUserId(key))
			elseif snap.tags then
				for _, tag in ipairs(snap.tags) do
					pcall(function()
						CollectionService:AddTag(label, tag)
					end)
				end
			end
		else
			label.Text = ''
		end
		return true
	end

	local function loadStore()
		local store = {
			version = 2,
			lastPreset = '',
			draft = nil,
			presets = {},
		}
		if type(isfile) ~= 'function' or not isfile(CUSTOM_PRESETS_PATH) or type(readfile) ~= 'function' then
			return store
		end
		local ok, raw = pcall(readfile, CUSTOM_PRESETS_PATH)
		if not ok or type(raw) ~= 'string' or raw == '' then
			return store
		end
		local okJ, data = pcall(HttpService.JSONDecode, HttpService, raw)
		if not okJ or type(data) ~= 'table' then
			return store
		end
		-- Legacy: bare array of presets
		if data[1] ~= nil or next(data) == nil then
			for _, row in ipairs(data) do
				if type(row) == 'table' and type(row.name) == 'string' then
					store.presets[#store.presets + 1] = row
				end
			end
			return store
		end
		if type(data.presets) == 'table' then
			for _, row in ipairs(data.presets) do
				if type(row) == 'table' and type(row.name) == 'string' then
					store.presets[#store.presets + 1] = row
				end
			end
		end
		if type(data.lastPreset) == 'string' then
			store.lastPreset = data.lastPreset
		end
		if type(data.draft) == 'table' then
			store.draft = data.draft
		end
		return store
	end

	local function saveStore(store)
		if type(writefile) ~= 'function' or type(store) ~= 'table' then
			return false
		end
		local payload = {
			version = 2,
			lastPreset = tostring(store.lastPreset or ''),
			draft = store.draft,
			presets = store.presets or {},
		}
		local ok, enc = pcall(HttpService.JSONEncode, HttpService, payload)
		if not ok then
			return false
		end
		return pcall(writefile, CUSTOM_PRESETS_PATH, enc)
	end

	local function loadPresets()
		return loadStore().presets
	end

	local function savePresets(list, lastPreset, draft)
		local store = loadStore()
		store.presets = list or store.presets
		if lastPreset ~= nil then
			store.lastPreset = lastPreset
		end
		if draft ~= nil then
			store.draft = draft
		end
		return saveStore(store)
	end

	local function presetNames()
		local names = { NONE }
		local rows = loadPresets()
		table.sort(rows, function(a, b)
			return tostring(a.name):lower() < tostring(b.name):lower()
		end)
		for _, row in ipairs(rows) do
			names[#names + 1] = row.name
		end
		return names
	end

	local function findPreset(name)
		if type(name) ~= 'string' or name == '' then
			return nil
		end
		for _, row in ipairs(loadPresets()) do
			if row.name == name then
				return row
			end
		end
		return nil
	end

	local function gatherCustomCfg()
		local text = Options.TitlingCustomText and Options.TitlingCustomText.Value or 'Custom'
		local icon = Options.TitlingCustomIcon and Options.TitlingCustomIcon.Value or ''
		local spark = Options.TitlingCustomSpark and Options.TitlingCustomSpark.Value or ''
		local anim = Options.TitlingCustomAnim and Options.TitlingCustomAnim.Value or 'None'
		if spark == '' then
			spark = DEFAULT_SPARK_IMAGE
		end
		return {
			text = tostring(text),
			brackets = true,
			c1 = readColor(Options.TitlingGradA, Color3.fromRGB(255, 215, 0)),
			c2 = readColor(Options.TitlingGradB, Color3.fromRGB(255, 215, 0)),
			c3 = readColor(Options.TitlingGradC, Color3.fromRGB(255, 154, 65)),
			stroke = readColor(Options.TitlingStrokeCol, Color3.fromRGB(40, 40, 60)),
			thickness = 2,
			icon = tostring(icon or ''),
			spark = tostring(spark or ''),
			anim = tostring(anim or 'None'),
		}
	end

	local function assetIdOnly(img)
		local n = normalizeAsset(img)
		local id = n:match('(%d+)')
		return id or n or ''
	end

	local function sampleFromGradient(grad, fallbacks)
		local c1, c2, c3 = fallbacks[1], fallbacks[2], fallbacks[3]
		if not grad or not grad:IsA('UIGradient') then
			return c1, c2, c3
		end
		local ok, kps = pcall(function()
			return grad.Color.Keypoints
		end)
		if not ok or type(kps) ~= 'table' or #kps == 0 then
			return c1, c2, c3
		end
		c1 = kps[1].Value
		if #kps == 1 then
			c2, c3 = c1, c1
		elseif #kps == 2 then
			c2 = kps[2].Value
			c3 = kps[2].Value
		else
			c2 = kps[math.ceil(#kps / 2)].Value
			c3 = kps[#kps].Value
		end
		return c1, c2, c3
	end

	local ICON_NAMES = {
		Icon = true,
		Symbol = true,
		Star = true,
		Hammer = true,
		Shine = true,
		Rat = true,
		Blossom = true,
		LightningBolt = true,
		EggTemplate = true,
	}

	local DEFAULT_TITLE_COLORS = {
		Color3.fromRGB(255, 215, 0),
		Color3.fromRGB(255, 215, 0),
		Color3.fromRGB(255, 154, 65),
	}

	local function colorsLookLikeFallback(c1, c2, c3)
		local function near(a, b)
			return typeof(a) == 'Color3'
				and typeof(b) == 'Color3'
				and math.abs(a.R - b.R) < 0.02
				and math.abs(a.G - b.G) < 0.02
				and math.abs(a.B - b.B) < 0.02
		end
		-- Old pink/cyan editor defaults (wrong imports) OR gold placeholder.
		local pinkish = {
			Color3.fromRGB(120, 200, 255),
			Color3.fromRGB(255, 160, 220),
			Color3.fromRGB(180, 140, 255),
		}
		if near(c1, pinkish[1]) and near(c2, pinkish[2]) then
			return true
		end
		if near(c1, DEFAULT_TITLE_COLORS[1]) and near(c2, DEFAULT_TITLE_COLORS[2]) and near(c3, DEFAULT_TITLE_COLORS[3]) then
			return true
		end
		return false
	end

	local function sampleModuleAssetColors(modScript)
		local grad = modScript and modScript:FindFirstChildWhichIsA('UIGradient', true)
		local c1, c2, c3 = sampleFromGradient(grad, DEFAULT_TITLE_COLORS)
		local strokeCol = Color3.fromRGB(40, 40, 60)
		local thickness = 1.5
		local us = modScript and modScript:FindFirstChildWhichIsA('UIStroke', true)
		if us then
			strokeCol = us.Color
			thickness = tonumber(us.Thickness) or 1.5
		end
		return c1, c2, c3, strokeCol, thickness, grad ~= nil
	end

	local function sampleTitleFromLabel(label)
		if not label then
			return nil, 'no label'
		end
		local raw = tostring(label.Text or '')
		local inner = raw:match('^%[(.*)%]$')
		local brackets = inner ~= nil
		local text = inner or raw
		if text == '' then
			text = 'Custom'
		end

		local grad = label:FindFirstChildWhichIsA('UIGradient')
		local c1, c2, c3
		local hasColors = false
		if grad then
			c1, c2, c3 = sampleFromGradient(grad, DEFAULT_TITLE_COLORS)
			hasColors = true
		else
			local tc = label.TextColor3
			if tc and (tc.R + tc.G + tc.B) < 2.95 then
				c1, c2, c3 = tc, tc, tc
				hasColors = true
			else
				c1, c2, c3 = DEFAULT_TITLE_COLORS[1], DEFAULT_TITLE_COLORS[2], DEFAULT_TITLE_COLORS[3]
			end
		end

		local strokeCol = Color3.fromRGB(40, 40, 60)
		local thickness = 1.5
		local us = label:FindFirstChildWhichIsA('UIStroke')
		if us then
			strokeCol = us.Color
			thickness = tonumber(us.Thickness) or 1.5
		end

		local icon, spark = '', ''
		local sparkCount = 0
		for _, ch in ipairs(label:GetChildren()) do
			if ch:IsA('ImageLabel') or ch:IsA('ImageButton') then
				local img = tostring(ch.Image or '')
				if img ~= '' and img ~= 'rbxasset://textures/ui/GuiImagePlaceholder.png' then
					local n = ch.Name
					if ICON_NAMES[n] or n:find('Icon', 1, true) or n:find('Symbol', 1, true) then
						if icon == '' then
							icon = img
						end
					elseif n == 'Image' or n == 'Spark' or n == 'Smoke' or n == 'Petal' or n == 'Snow' then
						sparkCount += 1
						if spark == '' then
							spark = img
						end
					elseif icon == '' then
						icon = img
					elseif spark == '' then
						spark = img
						sparkCount += 1
					end
				end
			end
		end

		local anim = 'None'
		if sparkCount >= 2 and icon ~= '' then
			anim = 'Full'
		elseif sparkCount >= 2 then
			anim = 'Sparks'
		elseif icon ~= '' and grad then
			anim = 'Icon pulse'
		elseif grad then
			anim = 'Gradient slide'
		end

		return {
			text = text,
			brackets = brackets,
			c1 = c1,
			c2 = c2,
			c3 = c3,
			stroke = strokeCol,
			thickness = thickness,
			icon = assetIdOnly(icon),
			spark = assetIdOnly(spark),
			anim = anim,
			hasColors = hasColors,
		}
	end

	local function extractAssetIdsFromModule(modScript)
		local ids = {}
		local seen = {}
		local function add(img)
			local id = assetIdOnly(img)
			if id ~= '' and not seen[id] then
				seen[id] = true
				ids[#ids + 1] = id
			end
		end
		for _, ch in ipairs(modScript:GetDescendants()) do
			if ch:IsA('ImageLabel') or ch:IsA('ImageButton') or ch:IsA('Decal') then
				add(ch.Image or ch.Texture)
			end
		end
		if type(decompile) == 'function' then
			local ok, src = pcall(decompile, modScript)
			if ok and type(src) == 'string' then
				for id in src:gmatch('rbxassetid://(%d+)') do
					add(id)
				end
			end
		end
		return ids
	end

	local function sampleTitleFromModule(tagName)
		local modScript = findSpecialAliasModule(tagName)
		if not modScript then
			return nil, 'no SpecialAlias module for "' .. tostring(tagName) .. '"'
		end

		-- ModuleScript Gradient/Stroke is authoritative for colors (live .new sometimes
		-- fails under CoreGui and previously fell back to fake pink defaults).
		local assetC1, assetC2, assetC3, assetStroke, assetThick, hasAssetGrad =
			sampleModuleAssetColors(modScript)

		local cfg
		local okReq, mod = pcall(require, modScript)
		if okReq and type(mod) == 'table' and type(mod.new) == 'function' then
			local holder = Instance.new('ScreenGui')
			holder.Name = 'SB2TitleSample'
			holder.ResetOnSpawn = false
			holder.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
			pcall(function()
				holder.Parent = LocalPlayer:FindFirstChild('PlayerGui')
			end)
			if not holder.Parent then
				pcall(function()
					holder.Parent = game:GetService('CoreGui')
				end)
			end
			local lab = Instance.new('TextLabel')
			lab.Name = 'Tag'
			lab.BackgroundTransparency = 1
			lab.Size = UDim2.fromOffset(420, 52)
			lab.Position = UDim2.fromOffset(20, 20)
			lab.Text = '[' .. tagName .. ']'
			lab.TextColor3 = Color3.new(1, 1, 1)
			lab.TextScaled = true
			lab.Parent = holder
			local okNew = pcall(mod.new, lab, { UserId = LocalPlayer.UserId })
			if okNew then
				task.wait(0.15)
				cfg = sampleTitleFromLabel(lab)
			end
			pcall(function()
				holder:Destroy()
			end)
		end

		if not cfg then
			cfg = {
				text = tagName,
				name = tagName,
				brackets = true,
				c1 = assetC1,
				c2 = assetC2,
				c3 = assetC3,
				stroke = assetStroke,
				thickness = assetThick,
				icon = '',
				spark = '',
				anim = hasAssetGrad and 'Gradient slide' or 'None',
			}
		else
			cfg.text = tagName
			cfg.name = tagName
			cfg.brackets = true
			-- Always prefer module gradient when present (avoids pink/white guess).
			if hasAssetGrad or not cfg.hasColors or colorsLookLikeFallback(cfg.c1, cfg.c2, cfg.c3) then
				if hasAssetGrad then
					cfg.c1, cfg.c2, cfg.c3 = assetC1, assetC2, assetC3
				end
			end
			if hasAssetGrad then
				cfg.stroke = assetStroke
				cfg.thickness = assetThick
			end
		end
		cfg.hasColors = nil

		if cfg.icon == '' or cfg.spark == '' then
			local ids = extractAssetIdsFromModule(modScript)
			if cfg.icon == '' and ids[1] then
				cfg.icon = ids[1]
			end
			if cfg.spark == '' then
				cfg.spark = ids[2] or ids[1] or cfg.spark
			end
		end
		if cfg.icon == '' or cfg.spark == '' then
			for _, ch in ipairs(modScript:GetDescendants()) do
				if ch:IsA('ImageLabel') or ch:IsA('ImageButton') then
					local img = tostring(ch.Image or '')
					if img ~= '' and img ~= 'rbxasset://textures/ui/GuiImagePlaceholder.png' then
						if ICON_NAMES[ch.Name] or ch.Name:find('Icon', 1, true) or ch.Name:find('Symbol', 1, true) or ch.Name == 'Star' then
							if cfg.icon == '' then
								cfg.icon = img
							end
						elseif cfg.spark == '' then
							cfg.spark = img
						end
					end
				end
			end
		end
		cfg.icon = assetIdOnly(cfg.icon)
		cfg.spark = assetIdOnly(cfg.spark)

		local isGlitch = tagName == 'Cursed One'
		if not isGlitch and type(decompile) == 'function' then
			local okD, src = pcall(decompile, modScript)
			if okD and type(src) == 'string' and src:find('StartLoop', 1, true) and src:find('"_"', 1, true) then
				isGlitch = true
			end
		end
		if isGlitch then
			cfg.anim = (cfg.icon ~= '' or cfg.spark ~= '') and 'Cursed Full' or 'Glitch text'
		elseif cfg.anim == 'None' or not cfg.anim then
			local hasIcon = cfg.icon ~= ''
			local hasSpark = cfg.spark ~= ''
			if hasIcon and hasSpark then
				cfg.anim = 'Full'
			elseif hasSpark then
				cfg.anim = 'Sparks'
			elseif hasIcon then
				cfg.anim = 'Icon pulse'
			elseif hasAssetGrad then
				cfg.anim = 'Gradient slide'
			else
				cfg.anim = 'None'
			end
		end
		return cfg
	end

	local function pushCfgToCustomUi(cfg)
		if type(cfg) ~= 'table' then
			return false
		end
		local function setColor(opt, color)
			if not opt or typeof(color) ~= 'Color3' then
				return
			end
			pcall(function()
				if type(opt.SetValueRGB) == 'function' then
					opt:SetValueRGB(color)
				elseif type(opt.SetValue) == 'function' then
					opt:SetValue(color)
				else
					opt.Value = color
				end
				if type(opt.Display) == 'function' then
					opt:Display()
				end
			end)
		end
		local function setOpt(opt, value)
			if not opt then
				return
			end
			pcall(function()
				if type(opt.SetValue) == 'function' then
					opt:SetValue(value)
				else
					opt.Value = value
				end
			end)
		end
		setOpt(Options.TitlingCustomText, tostring(cfg.text or ''))
		setColor(Options.TitlingGradA, cfg.c1)
		setColor(Options.TitlingGradB, cfg.c2)
		setColor(Options.TitlingGradC, cfg.c3)
		setColor(Options.TitlingStrokeCol, cfg.stroke)
		setOpt(Options.TitlingCustomIcon, tostring(cfg.icon or ''))
		setOpt(Options.TitlingCustomAnim, tostring(cfg.anim or 'None'))
		return true
	end

	local function serializeCfg(cfg)
		return {
			name = cfg.name,
			text = cfg.text,
			brackets = cfg.brackets ~= false,
			c1 = colorToHex(cfg.c1),
			c2 = colorToHex(cfg.c2),
			c3 = colorToHex(cfg.c3),
			stroke = colorToHex(cfg.stroke),
			thickness = cfg.thickness,
			icon = cfg.icon,
			spark = cfg.spark,
			anim = cfg.anim,
		}
	end

	local function hexToColor(hex, fallback)
		if type(hex) ~= 'string' then
			return fallback
		end
		local r, g, b = hex:match('^(%x%x)(%x%x)(%x%x)$')
		if not r then
			return fallback
		end
		return Color3.fromRGB(tonumber(r, 16), tonumber(g, 16), tonumber(b, 16))
	end

	local function deserializeCfg(row)
		return {
			name = row.name,
			text = row.text or row.name,
			brackets = row.brackets ~= false,
			c1 = hexToColor(row.c1, Color3.fromRGB(255, 215, 0)),
			c2 = hexToColor(row.c2, Color3.fromRGB(255, 215, 0)),
			c3 = hexToColor(row.c3, Color3.fromRGB(255, 154, 65)),
			stroke = hexToColor(row.stroke, Color3.fromRGB(40, 40, 60)),
			thickness = tonumber(row.thickness) or 1.5,
			icon = row.icon or '',
			spark = row.spark or '',
			anim = row.anim or 'None',
		}
	end

	local function upsertPreset(cfg)
		if type(cfg) ~= 'table' then
			return false, 'bad cfg'
		end
		local name = tostring(cfg.name or ''):gsub('^%s+', ''):gsub('%s+$', '')
		if name == '' then
			return false, 'empty preset name'
		end
		cfg.name = name
		local store = loadStore()
		local row = serializeCfg(cfg)
		local replaced = false
		for i, existing in ipairs(store.presets) do
			if existing.name == name then
				store.presets[i] = row
				replaced = true
				break
			end
		end
		if not replaced then
			store.presets[#store.presets + 1] = row
		end
		store.lastPreset = name
		store.draft = row
		if not saveStore(store) then
			return false, 'write failed'
		end
		return true, replaced and 'updated' or 'created'
	end

	local function saveDraftFromUi()
		local cfg = gatherCustomCfg()
		cfg.name = cfg.text
		local store = loadStore()
		store.draft = serializeCfg(cfg)
		if type(cfg.name) == 'string' and cfg.name ~= '' then
			store.lastPreset = cfg.name
		end
		return saveStore(store)
	end

	-- Existing title preview
	local playerDrop = TitlingBox:AddDropdown('TitlingPlayer', {
		Text = 'Player',
		Values = { NONE },
		AllowNull = true,
		Searchable = true,
		Tooltip = 'Type to autofill from Profiles / Characters',
	})

	local titleDrop = TitlingBox:AddDropdown('TitlingTitle', {
		Text = 'Title / tag',
		Values = { NONE },
		AllowNull = true,
		Searchable = true,
		Tooltip = 'From SpecialAlias + CosmeticTags',
	})

	local statusLabel = TitlingBox:AddLabel('Pick a player + title, then Apply preview')

	local function setStatus(text)
		pcall(function()
			if statusLabel.SetText then
				statusLabel:SetText(tostring(text))
			elseif statusLabel.Text ~= nil then
				statusLabel.Text = tostring(text)
			end
		end)
	end

	local function refreshPlayers()
		local names = listPlayerNames()
		if #names == 0 then
			names = { NONE }
		end
		local keep = Options.TitlingPlayer and Options.TitlingPlayer.Value
		if type(setDropdown) == 'function' then
			setDropdown(Options.TitlingPlayer, names, keep)
		elseif playerDrop and type(playerDrop.SetValues) == 'function' then
			playerDrop:SetValues(names)
		end
		return #names
	end

	local function refreshTitles()
		local names = listTitleNames()
		if #names == 0 then
			names = { NONE }
		end
		local keep = Options.TitlingTitle and Options.TitlingTitle.Value
		local keepImport = Options.TitlingImportTitle and Options.TitlingImportTitle.Value
		if type(setDropdown) == 'function' then
			setDropdown(Options.TitlingTitle, names, keep)
			if Options.TitlingImportTitle then
				setDropdown(Options.TitlingImportTitle, names, keepImport or keep)
			end
		elseif titleDrop and type(titleDrop.SetValues) == 'function' then
			titleDrop:SetValues(names)
		end
		return #names
	end

	TitlingBox:AddButton('Refresh lists', function()
		local pn = refreshPlayers()
		local tn = refreshTitles()
		setStatus(('Players %d - titles %d'):format(pn, tn))
		Library:Notify(('Titling - %d players, %d titles'):format(pn, tn), 4)
	end)

	TitlingBox:AddButton('Apply preview', function()
		local playerName = Options.TitlingPlayer and Options.TitlingPlayer.Value
		local titleName = Options.TitlingTitle and Options.TitlingTitle.Value
		if type(playerName) ~= 'string' or playerName == '' or playerName == NONE then
			Library:Notify('Select a player first')
			return
		end
		if type(titleName) ~= 'string' or titleName == '' or titleName == NONE then
			Library:Notify('Select a title/tag first')
			return
		end
		local char = resolveCharacter(playerName)
		local label = getNameplateTag(char)
		if not label then
			Library:Notify(playerName .. ' - nameplate not loaded (need them streamed in)', 8, true)
			setStatus('No nameplate for ' .. playerName)
			return
		end
		snapshotPlate(playerName, label)
		local _, knownSet = listTitleNames()
		local ok, how = applyTitleToLabel(label, titleName, knownSet, resolveUserId(playerName))
		if ok then
			setStatus(('[%s] on %s - %s'):format(titleName, playerName, tostring(how)))
			Library:Notify(('Title preview: %s on %s'):format(titleName, playerName), 5)
		else
			setStatus('Apply failed: ' .. tostring(how))
			Library:Notify('Titling failed: ' .. tostring(how), 6, true)
		end
	end)

	TitlingBox:AddButton('Restore nameplate', function()
		local playerName = Options.TitlingPlayer and Options.TitlingPlayer.Value
		if type(playerName) ~= 'string' or playerName == '' or playerName == NONE then
			Library:Notify('Select a player first')
			return
		end
		local ok, err = restorePlate(playerName)
		if ok then
			setStatus('Restored ' .. playerName)
			Library:Notify('Restored nameplate: ' .. playerName, 4)
		else
			Library:Notify('Restore failed: ' .. tostring(err), 6, true)
		end
	end)

	TitlingBox:AddButton('Clear title', function()
		local playerName = Options.TitlingPlayer and Options.TitlingPlayer.Value
		local char = resolveCharacter(playerName)
		local label = getNameplateTag(char)
		if not label then
			Library:Notify('Nameplate not loaded')
			return
		end
		snapshotPlate(playerName, label)
		label = resetNameplateTag(label)
		if label then
			label.Text = ''
		end
		setStatus('Cleared title on ' .. tostring(playerName))
	end)

	-- Custom title builder (simplified)
	CustomBox:AddLabel('1) Pick player  2) Import or edit  3) Apply / Save preset')

	local importDrop = CustomBox:AddDropdown('TitlingImportTitle', {
		Text = 'Import game title',
		Values = { NONE },
		AllowNull = true,
		Searchable = true,
		Tooltip = 'Loads colors/icon/anim from any SpecialAlias (incl. Cursed One glitch)',
	})

	CustomBox:AddInput('TitlingCustomText', {
		Text = 'Title text',
		Default = 'Custom',
		Placeholder = 'What shows on the nameplate',
	})

	pcall(function()
		CustomBox:AddLabel('Color A'):AddColorPicker('TitlingGradA', {
			Default = Color3.fromRGB(255, 215, 0),
			Title = 'A',
		})
		CustomBox:AddLabel('Color B'):AddColorPicker('TitlingGradB', {
			Default = Color3.fromRGB(255, 215, 0),
			Title = 'B',
		})
		CustomBox:AddLabel('Color C'):AddColorPicker('TitlingGradC', {
			Default = Color3.fromRGB(255, 154, 65),
			Title = 'C',
		})
		CustomBox:AddLabel('Stroke'):AddColorPicker('TitlingStrokeCol', {
			Default = Color3.fromRGB(40, 40, 60),
			Title = 'Stroke',
		})
	end)

	CustomBox:AddInput('TitlingCustomIcon', {
		Text = 'Icon id (optional)',
		Default = '',
		Placeholder = 'Asset id - blank = text only',
	})

	CustomBox:AddDropdown('TitlingCustomAnim', {
		Text = 'Animation',
		Values = {
			'None',
			'Gradient slide',
			'Sparks',
			'Icon pulse',
			'Full',
			'Glitch text',
			'Cursed Full',
		},
		Default = 'Full',
		Tooltip = 'Glitch text = Cursed One; Cursed Full = glitch + slide + sparks',
	})

	local suppressPresetLoad = false
	local presetDrop = CustomBox:AddDropdown('TitlingCustomPreset', {
		Text = 'My presets',
		Values = presetNames(),
		AllowNull = true,
		Searchable = true,
		Tooltip = 'Select to load - Save keeps edits',
	})

	local customStatus = CustomBox:AddLabel('Uses Player from Titling above.')

	local function setCustomStatus(text)
		pcall(function()
			if customStatus.SetText then
				customStatus:SetText(tostring(text))
			elseif customStatus.Text ~= nil then
				customStatus.Text = tostring(text)
			end
		end)
	end

	local function refreshPresetDrop(keep)
		local names = presetNames()
		if type(setDropdown) == 'function' then
			setDropdown(Options.TitlingCustomPreset, names, keep or NONE)
		elseif presetDrop and type(presetDrop.SetValues) == 'function' then
			presetDrop:SetValues(names)
		end
	end

	local function loadPresetIntoEditor(name, silent)
		if type(name) ~= 'string' or name == '' or name == NONE then
			return false
		end
		local row = findPreset(name)
		if not row then
			if not silent then
				Library:Notify('Preset not found: ' .. name, 5, true)
			end
			return false
		end
		local cfg = deserializeCfg(row)
		suppressPresetLoad = true
		pushCfgToCustomUi(cfg)
		suppressPresetLoad = false
		local store = loadStore()
		store.lastPreset = name
		store.draft = row
		saveStore(store)
		if not silent then
			setCustomStatus(('Loaded "%s"'):format(name))
			Library:Notify('Loaded preset: ' .. name, 4)
		end
		return true
	end

	local function importGameTitle(listed)
		if type(listed) ~= 'string' or listed == '' or listed == NONE then
			Library:Notify('Pick a game title to import', 6, true)
			return false
		end
		Library:Notify('Importing "' .. listed .. '"...', 3)
		local cfg, err = sampleTitleFromModule(listed)
		if not cfg then
			Library:Notify('Import failed: ' .. tostring(err), 8, true)
			setCustomStatus('Import failed: ' .. tostring(err))
			return false
		end
		pushCfgToCustomUi(cfg)
		saveDraftFromUi()
		setCustomStatus(('Imported [%s] - anim %s'):format(listed, tostring(cfg.anim)))
		Library:Notify('Imported "' .. listed .. '"', 5)
		return true
	end

	pcall(function()
		if importDrop and importDrop.OnChanged then
			importDrop:OnChanged(function(value)
				if type(value) == 'string' and value ~= '' and value ~= NONE then
					importGameTitle(value)
				end
			end)
		end
	end)

	pcall(function()
		if presetDrop and presetDrop.OnChanged then
			presetDrop:OnChanged(function(value)
				if suppressPresetLoad then
					return
				end
				if type(value) == 'string' and value ~= '' and value ~= NONE then
					loadPresetIntoEditor(value, false)
				end
			end)
		end
	end)

	local function selectedPlayer()
		local n = Options.TitlingPlayer and Options.TitlingPlayer.Value
		if type(n) == 'string' and n ~= '' and n ~= NONE then
			return n
		end
		return nil
	end

	CustomBox:AddButton('Apply', function()
		local playerName = selectedPlayer()
		if not playerName then
			Library:Notify('Select a Player in Titling first')
			return
		end
		local char = resolveCharacter(playerName)
		local label = getNameplateTag(char)
		if not label then
			Library:Notify(playerName .. ' - nameplate not loaded', 8, true)
			return
		end
		snapshotPlate(playerName, label)
		local cfg = gatherCustomCfg()
		local ok, how = applyCustomToLabel(label, cfg)
		saveDraftFromUi()
		if ok then
			setCustomStatus(('Applied [%s] on %s'):format(cfg.text, playerName))
			Library:Notify(('Applied on %s'):format(playerName), 5)
		else
			Library:Notify('Apply failed: ' .. tostring(how), 6, true)
		end
	end)

	CustomBox:AddButton('Save preset', function()
		local cfg = gatherCustomCfg()
		cfg.name = tostring(cfg.text or ''):gsub('^%s+', ''):gsub('%s+$', '')
		if cfg.name == '' then
			Library:Notify('Set title text before saving')
			return
		end
		local ok, how = upsertPreset(cfg)
		if ok then
			suppressPresetLoad = true
			refreshPresetDrop(cfg.name)
			pcall(function()
				if Options.TitlingCustomPreset then
					Options.TitlingCustomPreset:SetValue(cfg.name)
				end
			end)
			suppressPresetLoad = false
			setCustomStatus(('%s "%s"'):format(how == 'updated' and 'Updated' or 'Saved', cfg.name))
			Library:Notify(('Preset %s: %s'):format(how, cfg.name), 4)
		else
			Library:Notify('Save failed: ' .. tostring(how), 6, true)
		end
	end)

	CustomBox:AddButton('Copy nameplate', function()
		local playerName = selectedPlayer()
		if not playerName then
			Library:Notify('Select a Player in Titling first')
			return
		end
		local char = resolveCharacter(playerName)
		local label = getNameplateTag(char)
		if not label then
			Library:Notify('Nameplate not loaded', 8, true)
			return
		end
		local cfg, err = sampleTitleFromLabel(label)
		if not cfg then
			Library:Notify('Sample failed: ' .. tostring(err), 6, true)
			return
		end
		local listed = Options.TitlingTitle and Options.TitlingTitle.Value
		if (cfg.icon == '' and cfg.anim == 'None' or cfg.anim == 'Gradient slide') and type(listed) == 'string' and listed ~= NONE then
			local modCfg = sampleTitleFromModule(listed)
			if modCfg then
				modCfg.text = cfg.text ~= '' and cfg.text or modCfg.text
				cfg = modCfg
			end
		end
		cfg.name = cfg.text
		pushCfgToCustomUi(cfg)
		saveDraftFromUi()
		setCustomStatus(('Copied nameplate [%s]'):format(cfg.text))
		Library:Notify('Copied nameplate into editor', 4)
	end)

	CustomBox:AddButton('Delete preset', function()
		local pick = Options.TitlingCustomPreset and Options.TitlingCustomPreset.Value
		if type(pick) ~= 'string' or pick == '' or pick == NONE then
			Library:Notify('Select a preset to delete')
			return
		end
		local store = loadStore()
		local nextList = {}
		for _, row in ipairs(store.presets) do
			if row.name ~= pick then
				nextList[#nextList + 1] = row
			end
		end
		store.presets = nextList
		if store.lastPreset == pick then
			store.lastPreset = ''
		end
		saveStore(store)
		suppressPresetLoad = true
		refreshPresetDrop(NONE)
		suppressPresetLoad = false
		setCustomStatus('Deleted: ' .. pick)
	end)

	task.defer(function()
		refreshPlayers()
		refreshTitles()
		local store = loadStore()
		refreshPresetDrop(store.lastPreset ~= '' and store.lastPreset or NONE)
		if store.lastPreset ~= '' and findPreset(store.lastPreset) then
			loadPresetIntoEditor(store.lastPreset, true)
			setCustomStatus(('Restored "%s"'):format(store.lastPreset))
		elseif store.draft and type(store.draft) == 'table' then
			pushCfgToCustomUi(deserializeCfg(store.draft))
			setCustomStatus('Restored draft')
		end
	end)
	task.delay(2, function()
		refreshTitles()
	end)
	getgenv().SB2TitlingDraftToken = (getgenv().SB2TitlingDraftToken or 0) + 1
	local draftToken = getgenv().SB2TitlingDraftToken
	task.spawn(function()
		while getgenv().SB2TitlingDraftToken == draftToken do
			task.wait(8)
			if getgenv().SB2TitlingDraftToken ~= draftToken then
				break
			end
			pcall(saveDraftFromUi)
		end
	end)
end
