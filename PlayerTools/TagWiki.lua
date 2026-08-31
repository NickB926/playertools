-- Cosmetic tags wiki module (separate chunk for Luau 200-local limit)
return function(env)
	local ensureItemsFolder = env.ensureItemsFolder
	local copyText = env.copyText
	local setLabel = env.setLabel
	local setDropdown = env.setDropdown
	local ItemsTab = env.ItemsTab
	local Library = env.Library
	local Options = env.Options
	local HttpService = env.HttpService
	local NONE = env.NONE
	local SEARCH_HINT = env.SEARCH_HINT
	local TAGS_KNOWN_PATH = env.TAGS_KNOWN_PATH
	local WIKI_TAGS_DUMP_PATH = env.WIKI_TAGS_DUMP_PATH
	local LocalPlayer = env.LocalPlayer
		-- ── Cosmetic tags (SpecialAlias + Cosmetic Titles UI) ──
		local tagLiveCache = {} -- key -> lightweight record
		local tagLiveNames = {}
		local tagLastAdded = {}
		local tagLastRemoved = {}
		local tagSearchToken = 0
		local tagProbeCache = {} -- key -> full probe
		local tagProbeGui = nil
		local tagScanStatusWritten = false
		local tagFocusedName = nil -- last tag viewed/selected (dropdown Value is often stale)

		local writeWikiTagsDump, copyWikiTag, formatTagRec
		local scanLiveTags, loadTagsKnownSet, saveTagsKnownFromLive, writeTagScanStatus
		local getTagModule, getTagProbe, dumpWikiTag, tagRecordByName
		local forgetTagNames, pickRandomKnownTags, buildTagVariations

		do -- tag scan (Luau local limit)
		writeWikiTagsDump = function(text)
			if type(writefile) ~= 'function' then
				return
			end
			pcall(writefile, 'PlayerTools/wiki_tags_dump.txt', text)
			if ensureItemsFolder() then
				pcall(writefile, WIKI_TAGS_DUMP_PATH, text)
			end
		end

		copyWikiTag = function(text)
			if type(text) ~= 'string' or text == '' then
				Library:Notify('Nothing to copy — pick a tag first', 5)
				warn('[TagWiki] copyWikiTag: empty text')
				return false
			end
			writeWikiTagsDump(text)

			local function extractFandomBlock(body)
				local marker = '-- Fandom wikitext --'
				local pos = body:find(marker, 1, true)
				if not pos then
					return nil
				end
				local tail = body:sub(pos + #marker)
				local lines = {}
				for line in tail:gmatch('[^\r\n]+') do
					local trimmed = line:gsub('^%s+', ''):gsub('%s+$', '')
					if trimmed:sub(1, 1) == '|' then
						lines[#lines + 1] = trimmed
					elseif trimmed:sub(1, 2) == '--' and #lines > 0 then
						break
					elseif trimmed == '' and #lines > 0 then
						break
					end
				end
				if #lines == 0 then
					return nil
				end
				return table.concat(lines, '\n')
			end

			local function copyToClipboard(payload)
				if type(payload) ~= 'string' or payload == '' then
					return false
				end
				if copyText(payload) then
					return true
				end
				if type(setclipboard) == 'function' and pcall(setclipboard, payload) then
					return true
				end
				if type(toclipboard) == 'function' and pcall(toclipboard, payload) then
					return true
				end
				if syn and type(syn.write_clipboard) == 'function' and pcall(syn.write_clipboard, payload) then
					return true
				end
				return false
			end

			local fandomBlock = extractFandomBlock(text)
			local clipPayload = fandomBlock or text
			if copyToClipboard(clipPayload) then
				local msg = fandomBlock
						and 'Copied Fandom wikitext (full dump in wiki_tags_dump.txt)'
					or 'Copied tag wiki dump (also wiki_tags_dump.txt)'
				Library:Notify(msg, 6)
				warn('[TagWiki] ' .. msg)
				return true
			end
			Library:Notify('Wrote PlayerTools/wiki_tags_dump.txt (clipboard unavailable)', 6)
			warn('[TagWiki] clipboard unavailable — see PlayerTools/wiki_tags_dump.txt')
			return false
		end

		local function color3ToRgb(c)
			if typeof(c) ~= 'Color3' then
				return nil
			end
			return string.format('%d, %d, %d', math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
		end

		local function color3ToHex(c)
			if typeof(c) ~= 'Color3' then
				return nil
			end
			return string.format(
				'#%02X%02X%02X',
				math.floor(c.R * 255 + 0.5),
				math.floor(c.G * 255 + 0.5),
				math.floor(c.B * 255 + 0.5)
			)
		end

		local function normalizeAssetId(raw)
			if raw == nil or raw == '' then
				return nil
			end
			local s = tostring(raw)
			local id = s:match('rbxassetid://(%d+)') or s:match('id=(%d+)') or s:match('^(%d+)$')
			if id then
				return id, 'rbxassetid://' .. id
			end
			return nil, s
		end

		local function isNumericName(name)
			return type(name) == 'string' and name:match('^%d+$') ~= nil
		end

		local function getSpecialAliasFolder()
			local function fromCardinalPath()
				local cc = game:GetService('ReplicatedStorage'):FindFirstChild('CardinalClient')
				local main = cc and cc:FindFirstChild('MainModule')
				local services = main and main:FindFirstChild('Services')
				local graphics = services and services:FindFirstChild('Graphics')
				return graphics and graphics:FindFirstChild('SpecialAlias')
			end
			local folder = fromCardinalPath()
			if folder then
				return folder
			end
			local rs = game:GetService('ReplicatedStorage')
			for _, inst in ipairs(rs:GetDescendants()) do
				if inst.Name == 'SpecialAlias' and inst:IsA('Folder') then
					return inst
				end
			end
			return nil
		end

		-- Declared up front: getCosmeticTagUiRow calls this before the definition
		-- below, which otherwise resolves to a nil global.
		local getCosmeticTagsUi

		local function getCosmeticTagUiRow(rec)
			local ui = getCosmeticTagsUi()
			if not ui or type(rec) ~= 'table' then
				return nil
			end
			local name = rec.settingsName or rec.displayName or rec.moduleName
			if type(name) ~= 'string' or name == '' then
				return nil
			end
			return ui:FindFirstChild(name)
		end

		function getCosmeticTagsUi()
			local pg = LocalPlayer:FindFirstChild('PlayerGui')
			local cardinal = pg and pg:FindFirstChild('CardinalUI')
			local playerUi = cardinal and cardinal:FindFirstChild('PlayerUI')
			local main = playerUi and playerUi:FindFirstChild('MainFrame')
			local tabs = main and main:FindFirstChild('TabFrames')
			local settings = tabs and tabs:FindFirstChild('Settings')
			local attachments = settings and settings:FindFirstChild('Attachments')
			return attachments and attachments:FindFirstChild('CosmeticTags')
		end

		local function tagRecKey(rec)
			if type(rec) ~= 'table' then
				return nil
			end
			if rec.settingsName and rec.settingsName ~= '' then
				return rec.settingsName
			end
			if rec.displayName and rec.displayName ~= '' then
				return rec.displayName
			end
			return rec.moduleName
		end

		formatTagRec = function(rec)
			if not rec then
				return ''
			end
			local bits = { tagRecKey(rec) or '?' }
			if rec.moduleName and rec.moduleName ~= bits[1] then
				bits[#bits + 1] = 'mod:' .. rec.moduleName
			end
			local flags = {}
			if rec.inSettings then
				flags[#flags + 1] = 'UI'
			end
			if rec.inSpecialAlias then
				flags[#flags + 1] = 'SA'
			end
			if rec.animated then
				flags[#flags + 1] = 'anim'
			end
			if rec.iconCount and rec.iconCount > 0 then
				flags[#flags + 1] = rec.iconCount .. ' img'
			end
			if #flags > 0 then
				bits[#bits + 1] = table.concat(flags, ' · ')
			end
			return table.concat(bits, ' · ')
		end

		local function mergeTagRecord(into, patch)
			for k, v in pairs(patch) do
				if k == 'inSettings' or k == 'inSpecialAlias' then
					into[k] = into[k] or v
				elseif into[k] == nil or into[k] == '' then
					into[k] = v
				end
			end
			if patch.settingsName and patch.settingsName ~= '' then
				into.displayName = patch.settingsName
			elseif into.displayName == nil or into.displayName == '' then
				into.displayName = into.moduleName or into.settingsName
			end
		end

		local function upsertTagRecord(byKey, names, key, patch)
			if type(key) ~= 'string' or key == '' then
				return nil
			end
			local rec = byKey[key]
			if not rec then
				rec = {
					displayName = key,
					moduleName = nil,
					settingsName = nil,
					inSpecialAlias = false,
					inSettings = false,
					animated = false,
					iconCount = 0,
				}
				byKey[key] = rec
				names[#names + 1] = key
			end
			mergeTagRecord(rec, patch)
			return rec
		end

		local function linkNumericModules(byKey, names)
			local orphans = {}
			local settingsByModule = {}
			for key, rec in pairs(byKey) do
				if rec.inSettings and rec.moduleName and not isNumericName(rec.moduleName) then
					settingsByModule[rec.moduleName] = rec
				end
				if rec.inSpecialAlias and isNumericName(rec.moduleName or key) then
					orphans[#orphans + 1] = rec
				end
			end
			for _, rec in ipairs(orphans) do
				local modName = rec.moduleName or rec.displayName
				if settingsByModule[modName] then
					mergeTagRecord(settingsByModule[modName], rec)
				end
			end
		end

		local function scanCosmeticTagsFromUi()
			local names = {}
			local ui = getCosmeticTagsUi()
			if not ui then
				return names
			end
			for _, child in ipairs(ui:GetChildren()) do
				if child:IsA('GuiObject') and child.Name ~= 'UIPadding' and child.Name ~= 'UIListLayout' then
					names[#names + 1] = child.Name
				end
			end
			table.sort(names)
			return names
		end

		scanLiveTags = function()
			table.clear(tagLiveCache)
			table.clear(tagLiveNames)
			local byKey = {}
			local aliasFolder = getSpecialAliasFolder()
			local aliasCount = 0
			if aliasFolder then
				for _, child in ipairs(aliasFolder:GetChildren()) do
					if child:IsA('ModuleScript') then
						aliasCount += 1
						local modName = child.Name
						local key = isNumericName(modName) and modName or modName
						upsertTagRecord(byKey, tagLiveNames, key, {
							moduleName = modName,
							inSpecialAlias = true,
							displayName = isNumericName(modName) and modName or modName,
						})
					end
				end
			end
			local settingsNames = scanCosmeticTagsFromUi()
			for _, settingsName in ipairs(settingsNames) do
				local existing = byKey[settingsName]
				if existing then
					mergeTagRecord(existing, {
						settingsName = settingsName,
						inSettings = true,
						displayName = settingsName,
					})
				else
					local mod = aliasFolder and aliasFolder:FindFirstChild(settingsName)
					upsertTagRecord(byKey, tagLiveNames, settingsName, {
						settingsName = settingsName,
						moduleName = mod and mod.Name or settingsName,
						inSettings = true,
						inSpecialAlias = mod ~= nil,
						displayName = settingsName,
					})
				end
			end
			linkNumericModules(byKey, tagLiveNames)
			for key, rec in pairs(byKey) do
				tagLiveCache[key] = {
					displayName = rec.displayName,
					moduleName = rec.moduleName,
					settingsName = rec.settingsName,
					inSpecialAlias = rec.inSpecialAlias,
					inSettings = rec.inSettings,
					animated = rec.animated,
					iconCount = rec.iconCount,
				}
			end
			table.sort(tagLiveNames)
			return #tagLiveNames, aliasCount, #settingsNames
		end

		writeTagScanStatus = function(liveCount, aliasCount, settingsCount)
			if tagScanStatusWritten or not ensureItemsFolder() then
				return
			end
			local aliasPath = 'missing'
			local aliasFolder = getSpecialAliasFolder()
			if aliasFolder then
				aliasPath = aliasFolder:GetFullName()
			end
			local uiPath = 'missing'
			local ui = getCosmeticTagsUi()
			if ui then
				uiPath = ui:GetFullName()
			end
			local lines = {
				('scanAt=%s'):format(os.date('!%Y-%m-%dT%H:%M:%SZ')),
				('liveTags=%d'):format(liveCount),
				('specialAliasModules=%d'):format(aliasCount),
				('cosmeticTitlesUi=%d'):format(settingsCount),
				('specialAliasPath=%s'):format(aliasPath),
				('cosmeticTagsUiPath=%s'):format(uiPath),
			}
			pcall(writefile, 'PlayerTools/_tags_probe_status.txt', table.concat(lines, '\n'))
			tagScanStatusWritten = true
		end

		local function tagsKnownPaths()
			return {
				TAGS_KNOWN_PATH,
				'PlayerTools/tags_known.json',
				'tags_known.json',
			}
		end

		loadTagsKnownSet = function()
			local set = {}
			if type(isfile) ~= 'function' or type(readfile) ~= 'function' then
				return set, 0
			end
			for _, path in ipairs(tagsKnownPaths()) do
				local okExists, exists = pcall(isfile, path)
				if okExists and exists then
					local okRead, body = pcall(readfile, path)
					if okRead and type(body) == 'string' and body ~= '' then
						local okJson, data = pcall(function()
							return HttpService:JSONDecode(body)
						end)
						if okJson and type(data) == 'table' and type(data.tags) == 'table' then
							local n = 0
							for name in pairs(data.tags) do
								if type(name) == 'string' then
									set[name] = true
									n += 1
								end
							end
							return set, n
						end
					end
				end
			end
			return set, 0
		end

		local function loadTagsKnownData()
			if type(isfile) ~= 'function' or type(readfile) ~= 'function' then
				return nil
			end
			for _, path in ipairs(tagsKnownPaths()) do
				local okExists, exists = pcall(isfile, path)
				if okExists and exists then
					local okRead, body = pcall(readfile, path)
					if okRead and type(body) == 'string' and body ~= '' then
						local okJson, data = pcall(function()
							return HttpService:JSONDecode(body)
						end)
						if okJson and type(data) == 'table' then
							if type(data.tags) ~= 'table' then
								data.tags = {}
							end
							return data
						end
					end
				end
			end
			return nil
		end

		local function writeTagsKnownData(data)
			if not ensureItemsFolder() or type(data) ~= 'table' then
				return false
			end
			local n = 0
			if type(data.tags) == 'table' then
				for _ in pairs(data.tags) do
					n += 1
				end
			end
			data.count = n
			local okJson, body = pcall(function()
				return HttpService:JSONEncode(data)
			end)
			if not okJson or type(body) ~= 'string' then
				return false
			end
			pcall(writefile, TAGS_KNOWN_PATH, body)
			pcall(writefile, 'PlayerTools/tags_known.json', body)
			return true
		end

		saveTagsKnownFromLive = function()
			if not ensureItemsFolder() then
				return false, 0
			end
			local count = select(1, scanLiveTags())
			local payload = {
				count = count,
				tags = tagLiveCache,
			}
			if not writeTagsKnownData(payload) then
				return false, 0
			end
			return true, count
		end

		getTagModule = function(rec)
			if type(rec) ~= 'table' then
				return nil
			end
			local aliasFolder = getSpecialAliasFolder()
			if not aliasFolder then
				return nil
			end
			local modName = rec.moduleName or rec.settingsName or rec.displayName
			if type(modName) ~= 'string' or modName == '' then
				return nil
			end
			local mod = aliasFolder:FindFirstChild(modName)
			if mod and mod:IsA('ModuleScript') then
				return mod
			end
			if rec.settingsName then
				mod = aliasFolder:FindFirstChild(rec.settingsName)
				if mod and mod:IsA('ModuleScript') then
					return mod
				end
			end
			return nil
		end

		local function getProbeGui()
			if tagProbeGui and tagProbeGui.Parent then
				return tagProbeGui
			end
			tagProbeGui = Instance.new('ScreenGui')
			tagProbeGui.Name = 'SB2TagProbe'
			tagProbeGui.ResetOnSpawn = false
			tagProbeGui.Enabled = false
			tagProbeGui.DisplayOrder = -999
			tagProbeGui.Parent = LocalPlayer:WaitForChild('PlayerGui')
			return tagProbeGui
		end

		local function formatColorSequence(seq)
			if typeof(seq) ~= 'ColorSequence' then
				return nil
			end
			local parts = {}
			for _, kp in ipairs(seq.Keypoints) do
				local hex = color3ToHex(kp.Value) or '?'
				parts[#parts + 1] = string.format('%.2f %s', kp.Time, hex)
			end
			return table.concat(parts, ' | ')
		end

		local function formatNumberSequence(seq)
			if typeof(seq) ~= 'NumberSequence' then
				return nil
			end
			local parts = {}
			for _, kp in ipairs(seq.Keypoints) do
				parts[#parts + 1] = string.format('%.2f %.2f', kp.Time, kp.Value)
			end
			return table.concat(parts, ' | ')
		end

		local function inspectProbeTree(root, meta)
			if not root then
				return
			end
			local function visit(inst)
				if inst:IsA('TextLabel') or inst:IsA('TextButton') then
					meta.textLabels[#meta.textLabels + 1] = {
						name = inst.Name,
						text = inst.Text,
						font = tostring(inst.Font),
						textSize = inst.TextSize,
						textColor3 = color3ToRgb(inst.TextColor3),
						textColorHex = color3ToHex(inst.TextColor3),
						textTransparency = inst.TextTransparency,
						richText = inst.RichText,
					}
				elseif inst:IsA('UIStroke') then
					meta.strokes[#meta.strokes + 1] = {
						name = inst.Name,
						color = color3ToHex(inst.Color),
						colorRgb = color3ToRgb(inst.Color),
						thickness = inst.Thickness,
						transparency = inst.Transparency,
						applyStrokeMode = tostring(inst.ApplyStrokeMode),
					}
				elseif inst:IsA('UIGradient') then
					local parent = inst.Parent
					local textHost = parent
					if parent and parent:IsA('UIStroke') then
						textHost = parent.Parent
					end
					local keypoints = {}
					for _, kp in ipairs(inst.Color.Keypoints) do
						keypoints[#keypoints + 1] = {
							time = kp.Time,
							hex = color3ToHex(kp.Value),
							rgb = color3ToRgb(kp.Value),
						}
					end
					meta.gradients[#meta.gradients + 1] = {
						name = inst.Name,
						color = formatColorSequence(inst.Color),
						keypoints = keypoints,
						transparency = formatNumberSequence(inst.Transparency),
						rotation = inst.Rotation,
						offset = tostring(inst.Offset),
						parentName = parent and parent.Name,
						parentClass = parent and parent.ClassName,
						textHostName = textHost and textHost.Name,
					}
				elseif inst:IsA('ImageLabel') or inst:IsA('ImageButton') then
					local id, norm = normalizeAssetId(inst.Image)
					if id or (inst.Image and inst.Image ~= '') then
						meta.images[#meta.images + 1] = {
							name = inst.Name,
							image = norm or inst.Image,
							assetId = id,
							imageColor3 = color3ToRgb(inst.ImageColor3),
							imageTransparency = inst.ImageTransparency,
							zIndex = inst.ZIndex,
							size = tostring(inst.Size),
							position = tostring(inst.Position),
						}
					end
				elseif inst:IsA('UIPadding') then
					meta.paddings[#meta.paddings + 1] = {
						name = inst.Name,
						top = inst.PaddingTop.Offset,
						bottom = inst.PaddingBottom.Offset,
						left = inst.PaddingLeft.Offset,
						right = inst.PaddingRight.Offset,
					}
				elseif inst:IsA('UICorner') then
					meta.corners[#meta.corners + 1] = {
						name = inst.Name,
						radius = inst.CornerRadius.Offset,
					}
				end
			end
			visit(root)
			for _, desc in ipairs(root:GetDescendants()) do
				visit(desc)
			end
		end

		local function parseColor3Expr(expr)
			if type(expr) ~= 'string' then
				return nil
			end
			expr = expr:gsub('^%s+', ''):gsub('%s+$', '')
			local r, g, b = expr:match('^Color3%.fromRGB%((%d+),%s*(%d+),%s*(%d+)%)')
			if r then
				return string.format('#%02X%02X%02X', tonumber(r), tonumber(g), tonumber(b))
			end
			r, g, b = expr:match('^Color3%.new%(([%d%.]+),%s*([%d%.]+),%s*([%d%.]+)%)')
			if r then
				return string.format(
					'#%02X%02X%02X',
					math.floor(tonumber(r) * 255 + 0.5),
					math.floor(tonumber(g) * 255 + 0.5),
					math.floor(tonumber(b) * 255 + 0.5)
				)
			end
			return nil
		end

		local function parseKeypointsFromBlock(block)
			if type(block) ~= 'string' then
				return nil
			end
			local keypoints = {}
			for time, colorExpr in block:gmatch('ColorSequenceKeypoint%.new%(([%d%.]+),%s*(Color3[^%)]+)%)') do
				local hex = parseColor3Expr(colorExpr)
				if hex then
					keypoints[#keypoints + 1] = {
						time = tonumber(time),
						hex = hex,
						rgb = nil,
					}
				end
			end
			if #keypoints < 2 then
				return nil
			end
			table.sort(keypoints, function(a, b)
				return a.time < b.time
			end)
			return keypoints
		end

		local function parseDecompileGradients(src)
			local results = {}
			local seen = {}
			local function push(keypoints, roleHint)
				if not keypoints or #keypoints < 2 then
					return
				end
				local sigParts = {}
				for _, kp in ipairs(keypoints) do
					sigParts[#sigParts + 1] = string.format('%.2f:%s', kp.time or 0, kp.hex or '?')
				end
				local sig = table.concat(sigParts, '|')
				if seen[sig] then
					return
				end
				seen[sig] = true
				results[#results + 1] = {
					name = roleHint or ('Frame ' .. (#results + 1)),
					role = roleHint or ('Frame ' .. (#results + 1)),
					keypoints = keypoints,
					rotation = 90,
					source = 'decompile',
				}
			end

			for block in src:gmatch('ColorSequence%.new%b{}') do
				push(parseKeypointsFromBlock(block))
			end

			local pos = 1
			while true do
				local start = src:find('ColorSequence.new(', pos, true)
				if not start then
					break
				end
				local i = start + #'ColorSequence.new('
				local depth = 1
				while i <= #src and depth > 0 do
					local ch = src:sub(i, i)
					if ch == '(' then
						depth += 1
					elseif ch == ')' then
						depth -= 1
					end
					i += 1
				end
				if depth == 0 then
					local block = src:sub(start + #'ColorSequence.new', i - 1)
					if block:sub(1, 1) == '(' and not block:find('{', 1, true) then
						push(parseKeypointsFromBlock(block))
					end
				end
				pos = start + 1
			end

			for i, gr in ipairs(results) do
				if not gr.role or gr.role:match('^Frame %d+$') then
					gr.role = 'Frame ' .. i
					gr.name = gr.role
				end
			end
			return results
		end

		local function decompileTagHints(moduleScript, meta)
			if type(decompile) ~= 'function' then
				return
			end
			local ok, src = pcall(decompile, moduleScript)
			if not ok or type(src) ~= 'string' or src == '' then
				meta.probeError = meta.probeError or 'decompile failed'
				return
			end
			meta.decompiled = true
			meta.decompileSource = src
			if src:find('TweenService', 1, true) or src:find('RunService', 1, true) then
				meta.animatedHint = true
			end
			for id in src:gmatch('rbxassetid://(%d+)') do
				meta.decompileAssets[#meta.decompileAssets + 1] = id
			end
			for id in src:gmatch('(%d%d%d%d%d%d%d%d+)') do
				if #id >= 8 then
					meta.decompileAssets[#meta.decompileAssets + 1] = id
				end
			end
			meta.decompileGradients = parseDecompileGradients(src)
			if #meta.decompileGradients > 1 then
				meta.animatedHint = true
			end
		end

		local TAG_IMAGE_CHROME = {
			Shadow = true,
			Locked = true,
			SelectedTag = true,
			Selected = true,
		}

		local TAG_IMAGE_PRIMARY = {
			Icon = true,
			Symbol = true,
			Badge = true,
			Logo = true,
			Emblem = true,
		}

		local function isTagChromeImage(name)
			if type(name) ~= 'string' then
				return false
			end
			if TAG_IMAGE_CHROME[name] then
				return true
			end
			return name:sub(1, 8) == 'Selected'
		end

		local function classifyTagImage(name)
			if TAG_IMAGE_PRIMARY[name] then
				return 'primary'
			end
			return 'effect'
		end

		local function organizeTagImages(images)
			local primary = {}
			local effects = {}
			local seen = {}
			for _, img in ipairs(images or {}) do
				if not isTagChromeImage(img.name) then
					local key = tostring(img.assetId or img.image) .. '|' .. tostring(img.name)
					if not seen[key] then
						seen[key] = true
						local entry = {
							name = img.name,
							assetId = img.assetId,
							image = img.image,
							role = classifyTagImage(img.name),
						}
						if entry.role == 'primary' then
							primary[#primary + 1] = entry
						else
							effects[#effects + 1] = entry
						end
					end
				end
			end
			return primary, effects
		end

		local function summarizeProbe(meta)
			if (meta.iconCount or 0) == 0 and #meta.decompileAssets > 0 then
				local seen = {}
				for _, id in ipairs(meta.decompileAssets) do
					if not seen[id] then
						seen[id] = true
						local _, norm = normalizeAssetId(id)
						meta.images[#meta.images + 1] = {
							name = 'decompile',
							image = norm,
							assetId = id,
						}
					end
				end
			end
			local primaryIcons, effectIcons = organizeTagImages(meta.images)
			meta.iconCount = #primaryIcons
			meta.primaryIconCount = #primaryIcons
			meta.effectIconCount = #effectIcons
			meta.animated = (#meta.gradients > 1)
				or (#(meta.decompileGradients or {}) > 1)
				or (#primaryIcons + #effectIcons > 1)
				or meta.animatedHint == true
			if #meta.textLabels > 0 and (isNumericName(meta.displayName) or meta.displayName == meta.moduleName) then
				for _, tl in ipairs(meta.textLabels) do
					if tl.text and tl.text ~= '' then
						meta.probedDisplayName = tl.text
						break
					end
				end
			end
		end

		local function mergeProbeMeta(base, extra)
			if not base then
				return extra
			end
			if not extra then
				return base
			end
			local merged = {
				moduleName = base.moduleName or extra.moduleName,
				displayName = base.displayName or extra.displayName,
				source = base.source or extra.source,
				textLabels = {},
				strokes = {},
				gradients = {},
				images = {},
				paddings = {},
				corners = {},
				decompileAssets = {},
				decompileGradients = {},
				probeError = base.probeError or extra.probeError,
				decompiled = base.decompiled or extra.decompiled,
				animatedHint = base.animatedHint or extra.animatedHint,
				probedDisplayName = base.probedDisplayName or extra.probedDisplayName,
			}
			if base.source and extra.source and base.source ~= extra.source then
				merged.source = base.source .. '+' .. extra.source
			end
			local listKeys = {
				'textLabels',
				'strokes',
				'gradients',
				'images',
				'paddings',
				'corners',
				'decompileAssets',
				'decompileGradients',
			}
			for _, key in ipairs(listKeys) do
				for _, item in ipairs(base[key] or {}) do
					merged[key][#merged[key] + 1] = item
				end
				for _, item in ipairs(extra[key] or {}) do
					merged[key][#merged[key] + 1] = item
				end
			end
			summarizeProbe(merged)
			return merged
		end

		local function probeTagTemplate(moduleScript, rec)
			local meta = {
				moduleName = moduleScript and moduleScript.Name or (rec and rec.moduleName),
				displayName = rec and (rec.settingsName or rec.displayName or rec.moduleName) or nil,
				textLabels = {},
				strokes = {},
				gradients = {},
				images = {},
				paddings = {},
				corners = {},
				decompileAssets = {},
				decompileGradients = {},
				probeError = nil,
			}
			if not moduleScript or not moduleScript:IsA('ModuleScript') then
				meta.probeError = 'no module'
				summarizeProbe(meta)
				return meta
			end
			local cloned = nil
			local okRequire, result = pcall(require, moduleScript)
			if okRequire and typeof(result) == 'Instance' then
				cloned = result:Clone()
			elseif #moduleScript:GetChildren() > 0 then
				cloned = moduleScript:Clone()
			end
			if cloned then
				local gui = getProbeGui()
				cloned.Parent = gui
				inspectProbeTree(cloned, meta)
				cloned:Destroy()
			elseif not okRequire then
				meta.probeError = meta.probeError or ('require: ' .. tostring(result))
			end
			decompileTagHints(moduleScript, meta)
			summarizeProbe(meta)
			return meta
		end

		local function probeTagFromUi(rec)
			local row = getCosmeticTagUiRow(rec)
			if not row then
				return nil, 'CosmeticTags UI row not found (open Settings → Cosmetic Titles?)'
			end
			local meta = {
				source = 'ui',
				moduleName = rec.moduleName,
				displayName = rec.settingsName or rec.displayName or rec.moduleName,
				textLabels = {},
				strokes = {},
				gradients = {},
				images = {},
				paddings = {},
				corners = {},
				decompileAssets = {},
				decompileGradients = {},
				probeError = nil,
			}
			inspectProbeTree(row, meta)
			summarizeProbe(meta)
			return meta
		end

		local function titleCaseTagLabel(text)
			if type(text) ~= 'string' or text == '' then
				return text
			end
			return (text:gsub('(%a)([%w\']*)', function(first, rest)
				return first:upper() .. rest:lower()
			end))
		end

		local function gradientCssDirection(rotation)
			local r = ((tonumber(rotation) or 0) % 360 + 360) % 360
			if r >= 315 or r < 45 then
				return 'to right'
			elseif r < 135 then
				return 'to bottom'
			elseif r < 225 then
				return 'to left'
			end
			return 'to top'
		end

		local function gradientCssStopList(keypoints)
			if type(keypoints) ~= 'table' or #keypoints == 0 then
				return nil
			end
			local stops = {}
			for _, kp in ipairs(keypoints) do
				if type(kp.hex) == 'string' and kp.hex ~= '' then
					stops[#stops + 1] = kp.hex
				end
			end
			if #stops == 0 then
				return nil
			end
			local compact = {}
			local prev = nil
			for _, hex in ipairs(stops) do
				if hex ~= prev then
					compact[#compact + 1] = hex
					prev = hex
				end
			end
			if #compact == 1 then
				return compact[1], compact[1]
			end
			return table.concat(compact, ', ')
		end

		local function pickPrimaryTextLabel(probe)
			if not probe or #probe.textLabels == 0 then
				return nil
			end
			for _, tl in ipairs(probe.textLabels) do
				if type(tl.text) == 'string' and tl.text ~= '' then
					return tl
				end
			end
			return probe.textLabels[1]
		end

		local function textLabelByName(probe, name)
			if type(name) ~= 'string' then
				return nil
			end
			for _, tl in ipairs(probe.textLabels or {}) do
				if tl.name == name then
					return tl
				end
			end
			return nil
		end

		local function gradientSignature(gr)
			if not gr or type(gr.keypoints) ~= 'table' then
				return nil
			end
			local parts = {}
			for _, kp in ipairs(gr.keypoints) do
				parts[#parts + 1] = string.format('%.2f:%s', kp.time or 0, kp.hex or '?')
			end
			return table.concat(parts, '|') .. '|r' .. tostring(gr.rotation or 0)
		end

		buildTagVariations = function(probe, displayName)
			local variations = {}
			local seen = {}
			local function addVariation(role, gr, tl)
				local sig = gradientSignature(gr)
				if sig and seen[sig] then
					return
				end
				if sig then
					seen[sig] = true
				end
				variations[#variations + 1] = {
					role = role,
					gradient = gr,
					textLabel = tl,
					labelText = (tl and tl.text ~= '' and tl.text) or displayName or '?',
				}
			end

			for _, gr in ipairs(probe.gradients or {}) do
				if gr.parentClass == 'UIStroke' then
					local tl = textLabelByName(probe, gr.textHostName) or pickPrimaryTextLabel(probe)
					addVariation('Stroke', gr, tl)
				else
					local tl = textLabelByName(probe, gr.parentName)
						or textLabelByName(probe, gr.textHostName)
						or pickPrimaryTextLabel(probe)
					addVariation('Text', gr, tl)
				end
			end

			for _, gr in ipairs(probe.decompileGradients or {}) do
				local tl = pickPrimaryTextLabel(probe)
				addVariation(gr.role or gr.name or 'Frame', gr, tl)
			end

			if #variations == 0 then
				local tl = pickPrimaryTextLabel(probe)
				variations[1] = {
					role = 'Text',
					gradient = nil,
					textLabel = tl,
					labelText = (tl and tl.text ~= '' and tl.text) or displayName or '?',
				}
			end
			return variations
		end

		local function formatFandomIconSnippet(icon)
			if not icon or not icon.assetId then
				return nil
			end
			return string.format(
				'<img src="https://www.roblox.com/asset-thumbnail/image?assetId=%s&width=48&height=48&format=png" width="22" height="22" alt="%s"/>',
				icon.assetId,
				icon.name or 'icon'
			)
		end

		local function formatFandomTextSpan(labelText, tl, gr)
			local wikiLabel = titleCaseTagLabel(labelText)
			local linkInner = '[[' .. '#1|' .. '[' .. wikiLabel .. '] ' .. ']]'
			local bigLink = '<big>' .. linkInner .. '</big>'
			if gr and type(gr.keypoints) == 'table' and #gr.keypoints > 0 then
				local cssStops = gradientCssStopList(gr.keypoints)
				if cssStops then
					local dir = gradientCssDirection(gr.rotation)
					local style = string.format(
						'background: linear-gradient(%s, %s); -webkit-background-clip: text; -webkit-text-fill-color: transparent;',
						dir,
						cssStops
					)
					return '<span style="' .. style .. '">' .. bigLink .. '</span>'
				end
			end
			local hex = tl and tl.textColorHex
			if hex then
				return '<span style="color: ' .. hex .. ';">' .. bigLink .. '</span>'
			end
			return bigLink
		end

		local function formatFandomTagWikitext(displayName, probe)
			local primaryIcons, effectIcons = organizeTagImages(probe and probe.images)
			local variations = buildTagVariations(probe, displayName)
			local iconPrefix = ''
			if #primaryIcons > 0 then
				local bits = {}
				for _, icon in ipairs(primaryIcons) do
					local snippet = formatFandomIconSnippet(icon)
					if snippet then
						bits[#bits + 1] = snippet
					end
				end
				if #bits > 0 then
					iconPrefix = table.concat(bits, ' ') .. ' '
				end
			end

			local lines = {}
			for _, variation in ipairs(variations) do
				local span = formatFandomTextSpan(variation.labelText, variation.textLabel, variation.gradient)
				local rolePrefix = (#variations > 1) and ('(' .. variation.role .. ') ') or ''
				lines[#lines + 1] = '| ' .. rolePrefix .. iconPrefix .. span
			end

			if #effectIcons > 0 then
				local bits = {}
				for _, icon in ipairs(effectIcons) do
					if icon.assetId then
						bits[#bits + 1] = icon.name .. '=' .. icon.assetId
					end
				end
				if #bits > 0 then
					lines[#lines + 1] = '| Effect layers: ' .. table.concat(bits, ', ')
				end
			end

			return table.concat(lines, '\n')
		end

		getTagProbe = function(rec)
			local key = tagRecKey(rec)
			if not key then
				return nil, 'invalid tag'
			end
			if tagProbeCache[key] then
				return tagProbeCache[key]
			end

			local mod = getTagModule(rec)
			local merged = nil
			if mod then
				local ok, meta = pcall(probeTagTemplate, mod, rec)
				if ok and type(meta) == 'table' then
					merged = meta
				end
			end

			local uiMeta, uiErr = probeTagFromUi(rec)
			if uiMeta then
				merged = mergeProbeMeta(merged, uiMeta)
			end

			if not merged then
				return nil, uiErr or (mod and 'module probe empty' or 'SpecialAlias module not found')
			end

			if mod and not merged.decompiled then
				decompileTagHints(mod, merged)
				summarizeProbe(merged)
			end

			if #merged.textLabels == 0 and #merged.gradients == 0 and #merged.images == 0
				and #merged.strokes == 0 and #(merged.decompileGradients or {}) == 0 then
				return nil, uiErr or 'probe empty'
			end

			if merged.probedDisplayName and isNumericName(rec.displayName or rec.moduleName) then
				rec.displayName = merged.probedDisplayName
			end
			if tagLiveCache[key] then
				tagLiveCache[key].animated = merged.animated
				tagLiveCache[key].iconCount = merged.iconCount
			end

			tagProbeCache[key] = merged
			return merged
		end

		dumpWikiTag = function(rec)
			if type(rec) ~= 'table' then
				return '(invalid tag record)'
			end
			local key = tagRecKey(rec)
			local display = rec.settingsName or rec.displayName or rec.moduleName or key or '?'
			local lines = { '=== ' .. display .. ' ===' }
			local function add(label, val)
				if val == nil or val == '' then
					return
				end
				lines[#lines + 1] = label .. ': ' .. tostring(val)
			end
			add('Display name', display)
			add('Module name', rec.moduleName)
			add('In Cosmetic Titles UI', rec.inSettings and 'yes' or 'no')
			local probe, probeErr = getTagProbe(rec)
			if probe then
				add('Probe source', probe.source or 'module')
				add('Animated', probe.animated and 'yes' or 'no')
				if probe.probedDisplayName then
					add('Probed label', probe.probedDisplayName)
				end
				local tl = pickPrimaryTextLabel(probe)
				if tl then
					lines[#lines + 1] = ''
					lines[#lines + 1] = '-- Text --'
					if tl.text and tl.text ~= '' then
						add('Label', tl.text)
					end
					add('Font', tl.font)
					add('TextSize', tl.textSize)
					if tl.textColorHex then
						add('TextColor hex', tl.textColorHex)
					end
					if tl.textColor3 then
						add('TextColor rgb', tl.textColor3)
					end
					if tl.richText then
						add('RichText', 'yes')
					end
				end
				if #probe.strokes > 0 then
					lines[#lines + 1] = ''
					lines[#lines + 1] = '-- Stroke --'
					for i, st in ipairs(probe.strokes) do
						if i > 1 then
							lines[#lines + 1] = ''
						end
						add('Name', st.name)
						add('Color hex', st.color)
						if st.colorRgb then
							add('Color rgb', st.colorRgb)
						end
						add('Thickness', st.thickness)
						add('Transparency', st.transparency)
					end
				end
				if #probe.gradients > 0 then
					lines[#lines + 1] = ''
					lines[#lines + 1] = '-- Gradient --'
					for gi, gr in ipairs(probe.gradients) do
						if gi > 1 then
							lines[#lines + 1] = ''
						end
						add('Name', gr.name)
						if gr.parentClass then
							add('On', gr.parentClass .. (gr.parentName and (' / ' .. gr.parentName) or ''))
						end
						add('Rotation', gr.rotation)
						add('CSS direction', gradientCssDirection(gr.rotation))
						if gr.offset then
							add('Offset', gr.offset)
						end
						if type(gr.keypoints) == 'table' and #gr.keypoints > 0 then
							for _, kp in ipairs(gr.keypoints) do
								lines[#lines + 1] = string.format('Stop %.2f: %s (%s)', kp.time or 0, kp.hex or '?', kp.rgb or '?')
							end
							local cssStops = gradientCssStopList(gr.keypoints)
							if cssStops then
								add('CSS stops', cssStops)
							end
						elseif gr.color then
							add('Colors', gr.color)
						end
						if gr.transparency then
							add('Transparency', gr.transparency)
						end
					end
				end
				local primaryIcons, effectIcons = organizeTagImages(probe.images)
				if #primaryIcons > 0 or #effectIcons > 0 then
					lines[#lines + 1] = ''
					if #primaryIcons > 0 then
						lines[#lines + 1] = ('-- Primary icons (%d) --'):format(#primaryIcons)
						for _, img in ipairs(primaryIcons) do
							lines[#lines + 1] = img.name .. ': ' .. tostring(img.image)
							if img.assetId then
								lines[#lines + 1] = '  https://www.roblox.com/library/' .. img.assetId
							end
						end
					end
					if #effectIcons > 0 then
						lines[#lines + 1] = ''
						lines[#lines + 1] = ('-- Effect layers (%d) --'):format(#effectIcons)
						for _, img in ipairs(effectIcons) do
							lines[#lines + 1] = img.name .. ': ' .. tostring(img.image)
							if img.assetId then
								lines[#lines + 1] = '  https://www.roblox.com/library/' .. img.assetId
							end
						end
					end
				end
				local variations = buildTagVariations(probe, display)
				if #(probe.decompileGradients or {}) > 0 then
					lines[#lines + 1] = ''
					lines[#lines + 1] = ('-- Animation frames from module (%d) --'):format(#probe.decompileGradients)
					for fi, gr in ipairs(probe.decompileGradients) do
						if fi > 1 then
							lines[#lines + 1] = ''
						end
						add('Frame', gr.role or gr.name or ('Frame ' .. fi))
						add('Rotation', gr.rotation)
						if type(gr.keypoints) == 'table' then
							for _, kp in ipairs(gr.keypoints) do
								lines[#lines + 1] = string.format('Stop %.2f: %s', kp.time or 0, kp.hex or '?')
							end
							local cssStops = gradientCssStopList(gr.keypoints)
							if cssStops then
								add('CSS stops', cssStops)
							end
						end
					end
				end
				if #variations > 1 then
					lines[#lines + 1] = ''
					lines[#lines + 1] = ('-- Variations (%d) --'):format(#variations)
					for vi, var in ipairs(variations) do
						if vi > 1 then
							lines[#lines + 1] = ''
						end
						add('Role', var.role)
						add('Label', var.labelText)
						if var.gradient then
							add('Rotation', var.gradient.rotation)
							local cssStops = gradientCssStopList(var.gradient.keypoints)
							if cssStops then
								add('CSS stops', cssStops)
							end
						end
					end
				end
				if probe.probeError and #probe.images == 0 and #probe.textLabels == 0 and #probe.gradients == 0 then
					lines[#lines + 1] = ''
					lines[#lines + 1] = '(partial probe: ' .. tostring(probe.probeError) .. ')'
				end
				lines[#lines + 1] = ''
				lines[#lines + 1] = '-- Fandom wikitext --'
				lines[#lines + 1] = formatFandomTagWikitext(display, probe)
				lines[#lines + 1] = ''
				lines[#lines + 1] = '-- Notes --'
				if probe.animated then
					lines[#lines + 1] = 'Multi-layer tag (animated-style template)'
				else
					lines[#lines + 1] = 'Static tag template'
				end
				if probe.primaryIconCount and probe.primaryIconCount > 0 then
					lines[#lines + 1] = ('Primary icons: %d'):format(probe.primaryIconCount)
				end
				if probe.effectIconCount and probe.effectIconCount > 0 then
					lines[#lines + 1] = ('Effect layers: %d unique assets'):format(probe.effectIconCount)
				end
				if #variations > 1 then
					lines[#lines + 1] = ('Gradient variations: %d (text/stroke layers + animation frames)'):format(#variations)
				elseif #(probe.decompileGradients or {}) > 0 then
					lines[#lines + 1] = ('Animation frames in module source: %d (Settings UI shows one preview)'):format(
						#probe.decompileGradients
					)
				end
				if probe.source == 'ui' then
					lines[#lines + 1] = 'Colors/gradient read from Cosmetic Titles UI row (SpecialAlias not in ReplicatedStorage tree).'
				end
				if #primaryIcons > 0 or #effectIcons > 0 then
					lines[#lines + 1] = ''
					lines[#lines + 1] = '-- Image layer table --'
					lines[#lines + 1] = '{| class="wikitable"'
					lines[#lines + 1] = '! Role !! Layer !! Asset'
					for _, img in ipairs(primaryIcons) do
						lines[#lines + 1] = '|-'
						lines[#lines + 1] = '| Primary || ' .. img.name .. ' || ' .. tostring(img.image)
					end
					for _, img in ipairs(effectIcons) do
						lines[#lines + 1] = '|-'
						lines[#lines + 1] = '| Effect || ' .. img.name .. ' || ' .. tostring(img.image)
					end
					lines[#lines + 1] = '|}'
				end
			else
				add('Animated', rec.animated and 'yes' or 'no')
				lines[#lines + 1] = ''
				lines[#lines + 1] = '(probe failed: ' .. tostring(probeErr) .. ')'
			end
			return table.concat(lines, '\n')
		end

		tagRecordByName = function(name)
			if type(name) ~= 'string' or name == '' then
				return nil
			end
			if tagLiveCache[name] then
				return tagLiveCache[name]
			end
			for key, rec in pairs(tagLiveCache) do
				if rec.moduleName == name or rec.settingsName == name or rec.displayName == name or key == name then
					return rec
				end
			end
			return nil
		end

		forgetTagNames = function(names)
			if type(names) ~= 'table' or #names == 0 then
				return false, {}
			end
			local data = loadTagsKnownData()
			if not data or type(data.tags) ~= 'table' then
				scanLiveTags()
				local set = loadTagsKnownSet()
				data = { count = 0, tags = {} }
				for name, rec in pairs(tagLiveCache) do
					if set[name] then
						data.tags[name] = rec
					end
				end
			end
			local removed = {}
			for _, name in ipairs(names) do
				if type(name) == 'string' and data.tags[name] ~= nil then
					data.tags[name] = nil
					removed[#removed + 1] = name
				end
			end
			if #removed == 0 then
				return false, removed
			end
			if not writeTagsKnownData(data) then
				return false, removed
			end
			return true, removed
		end

		pickRandomKnownTags = function(count)
			scanLiveTags()
			local known = loadTagsKnownSet()
			local pool = {}
			for _, name in ipairs(tagLiveNames) do
				if known[name] then
					pool[#pool + 1] = name
				end
			end
			local picks = {}
			local n = math.min(count, #pool)
			for _ = 1, n do
				local idx = math.random(1, #pool)
				picks[#picks + 1] = pool[idx]
				table.remove(pool, idx)
			end
			return picks
		end
		end

		do -- tag ui (Luau local limit)
		local TagsDiffBox = ItemsTab:AddLeftGroupbox('Cosmetic tags — new since snapshot')
		local TagsSearchBox = ItemsTab:AddRightGroupbox('Search cosmetic tags')
		if type(env.registerWikiBox) == 'function' then
			pcall(env.registerWikiBox, TagsDiffBox)
			pcall(env.registerWikiBox, TagsSearchBox)
		end

		local tagStatusLabel = TagsDiffBox:AddLabel('Scan tags after a patch. First run saves a baseline.')
		local tagDetailLabel = TagsDiffBox:AddLabel(' ')

		local function rememberTagFocus(name)
			if type(name) ~= 'string' or name == '' or name == NONE or name == SEARCH_HINT then
				return
			end
			tagFocusedName = name
		end

		local function dropdownPick(option)
			if not option then
				return nil
			end
			local value
			pcall(function()
				value = option.Value
			end)
			if type(value) ~= 'string' or value == '' or value == NONE or value == SEARCH_HINT then
				return nil
			end
			return value
		end

		local function currentSelectedTagName()
			local search = dropdownPick(Options.TagSearchResults)
			if search then
				return search
			end
			local all = dropdownPick(Options.AllTagList)
			if all then
				return all
			end
			local neu = dropdownPick(Options.NewTagList)
			if neu then
				return neu
			end
			if tagFocusedName then
				return tagFocusedName
			end
			return nil
		end

		local function showTagDetail(name)
			if type(name) ~= 'string' or name == '' or name == NONE then
				setLabel(tagDetailLabel, ' ')
				return
			end
			rememberTagFocus(name)
			if not tagLiveCache[name] then
				scanLiveTags()
			end
			local rec = tagLiveCache[name]
			if not rec then
				setLabel(tagDetailLabel, name)
				return
			end
			setLabel(tagDetailLabel, formatTagRec(rec))
			local probe = getTagProbe(rec)
			if probe then
				local bits = {
					formatTagRec(rec),
					probe.animated and 'animated' or 'static',
					tostring(probe.primaryIconCount or probe.iconCount or 0) .. ' icon(s)',
				}
				local varCount = #buildTagVariations(probe, name)
				if varCount > 1 then
					bits[#bits + 1] = varCount .. ' gradients'
				end
				if probe.effectIconCount and probe.effectIconCount > 0 then
					bits[#bits + 1] = probe.effectIconCount .. ' effects'
				end
				setLabel(tagDetailLabel, table.concat(bits, ' · '))
			end
		end

		TagsDiffBox:AddDropdown('NewTagList', {
			Text = 'New tag names',
			Values = { NONE },
			AllowNull = true,
		}):OnChanged(function(name)
			showTagDetail(name)
		end)

		TagsDiffBox:AddDropdown('RemovedTagList', {
			Text = 'Removed / renamed',
			Values = { NONE },
			AllowNull = true,
		})

		local function refreshAllTagList()
			if #tagLiveNames == 0 then
				scanLiveTags()
			end
			if #tagLiveNames == 0 then
				setDropdown(Options.AllTagList, { NONE }, NONE)
				return 0
			end
			setDropdown(Options.AllTagList, tagLiveNames, tagLiveNames[1])
			return #tagLiveNames
		end

		local function runTagScan(notifyBaseline)
			local liveCount, aliasCount, settingsCount = scanLiveTags()
			if liveCount == 0 then
				setLabel(tagStatusLabel, 'No tags found (SpecialAlias missing?)')
				Library:Notify('No cosmetic tags found')
				return
			end
			writeTagScanStatus(liveCount, aliasCount, settingsCount)
			refreshAllTagList()
			local known, knownCount = loadTagsKnownSet()
			if knownCount == 0 then
				local ok, n = saveTagsKnownFromLive()
				table.clear(tagLastAdded)
				table.clear(tagLastRemoved)
				setDropdown(Options.NewTagList, { NONE }, NONE)
				setDropdown(Options.RemovedTagList, { NONE }, NONE)
				local msg = ok
					and ('Saved tag baseline of %d tags. After the next patch, Scan lists only new names.'):format(n)
					or 'Could not write tags_known.json'
				setLabel(tagStatusLabel, msg)
				if notifyBaseline ~= false then
					Library:Notify(msg, 8)
				end
				return
			end
			table.clear(tagLastAdded)
			table.clear(tagLastRemoved)
			for _, name in ipairs(tagLiveNames) do
				if not known[name] then
					tagLastAdded[#tagLastAdded + 1] = name
				end
			end
			for name in pairs(known) do
				if not tagLiveCache[name] then
					tagLastRemoved[#tagLastRemoved + 1] = name
				end
			end
			table.sort(tagLastRemoved)
			setDropdown(Options.NewTagList, tagLastAdded, NONE)
			setDropdown(Options.RemovedTagList, tagLastRemoved, NONE)
			local msg = ('Tags live %d · known %d · new %d · gone %d · SA %d · UI %d'):format(
				liveCount,
				knownCount,
				#tagLastAdded,
				#tagLastRemoved,
				aliasCount,
				settingsCount
			)
			setLabel(tagStatusLabel, msg)
			Library:Notify(msg, 6)
		end

		local function dumpAllNewTagsWiki()
			if #tagLastAdded == 0 then
				return nil, 'No new tags — Scan first'
			end
			local blocks = {}
			for _, name in ipairs(tagLastAdded) do
				local rec = tagLiveCache[name]
				if rec then
					blocks[#blocks + 1] = dumpWikiTag(rec)
				end
			end
			return table.concat(blocks, '\n\n'), nil
		end

		TagsDiffBox:AddButton('Scan tags', function()
			runTagScan(true)
		end)

		TagsDiffBox:AddButton('Save tags baseline', function()
			local ok, n = saveTagsKnownFromLive()
			if not ok then
				Library:Notify('Could not write tags_known.json')
				return
			end
			table.clear(tagLastAdded)
			table.clear(tagLastRemoved)
			setDropdown(Options.NewTagList, { NONE }, NONE)
			setDropdown(Options.RemovedTagList, { NONE }, NONE)
			refreshAllTagList()
			local msg = ('Saved %d tags as known. Next patch flags additions only.'):format(n)
			setLabel(tagStatusLabel, msg)
			Library:Notify(msg, 6)
		end)

		TagsDiffBox:AddButton('Copy new tag names', function()
			if #tagLastAdded == 0 then
				Library:Notify('No new tags — Scan first')
				return
			end
			if copyText(table.concat(tagLastAdded, '\n')) then
				Library:Notify(('Copied %d new tag names'):format(#tagLastAdded))
			else
				Library:Notify('Clipboard unavailable')
			end
		end)

		TagsDiffBox:AddButton('Copy wiki: all new tags', function()
			local text, err = dumpAllNewTagsWiki()
			if not text then
				Library:Notify(err)
				return
			end
			copyWikiTag(text)
		end)

		TagsDiffBox:AddButton('Forget selected (test)', function()
			local name = currentSelectedTagName()
			if not name then
				Library:Notify('Pick a tag from All, Search, or New list first')
				return
			end
			local ok, removed = forgetTagNames({ name })
			if not ok or #removed == 0 then
				Library:Notify(name .. ' was not in the snapshot')
				return
			end
			Library:Notify('Forgot ' .. name .. ' — scanning')
			runTagScan(true)
		end)

		TagsDiffBox:AddButton('Forget 3 random (test)', function()
			local picks = pickRandomKnownTags(3)
			if #picks == 0 then
				Library:Notify('No known tags to forget — save a baseline first')
				return
			end
			local ok, removed = forgetTagNames(picks)
			if not ok or #removed == 0 then
				Library:Notify('Could not update tags_known.json')
				return
			end
			Library:Notify('Forgot: ' .. table.concat(removed, ', '), 8)
			runTagScan(true)
		end)

		local function applyTagSearch(query)
			query = string.lower(tostring(query or ''):gsub('^%s+', ''):gsub('%s+$', ''))
			if query == '' then
				setDropdown(Options.TagSearchResults, { SEARCH_HINT }, SEARCH_HINT)
				setLabel(tagDetailLabel, ' ')
				return
			end
			if #tagLiveNames == 0 then
				scanLiveTags()
			end
			local hits = {}
			for _, name in ipairs(tagLiveNames) do
				local rec = tagLiveCache[name]
				local hay = string.lower(name)
				if rec and rec.moduleName and rec.moduleName ~= name then
					hay = hay .. ' ' .. string.lower(rec.moduleName)
				end
				if string.find(hay, query, 1, true) then
					hits[#hits + 1] = name
					if #hits >= 80 then
						break
					end
				end
			end
			setDropdown(Options.TagSearchResults, hits, SEARCH_HINT)
			if #hits == 1 then
				rememberTagFocus(hits[1])
				setLabel(tagDetailLabel, formatTagRec(tagLiveCache[hits[1]]))
			end
		end

		TagsSearchBox:AddLabel('Scan tags (left) refreshes the full list and new-since-baseline diff.')

		TagsSearchBox:AddDropdown('AllTagList', {
			Text = 'All cosmetic tags',
			Values = { NONE },
			AllowNull = true,
			Searchable = true,
		}):OnChanged(function(name)
			showTagDetail(name)
		end)

		TagsSearchBox:AddInput('TagSearchQuery', {
			Text = 'Name contains',
			Default = '',
			Placeholder = 'e.g. Plasmatic',
			Finished = false,
			ClearTextOnFocus = false,
			AllowEmpty = true,
			Callback = function(value)
				tagSearchToken += 1
				local token = tagSearchToken
				task.delay(0.12, function()
					if token == tagSearchToken then
						applyTagSearch(value)
					end
				end)
			end,
		})

		TagsSearchBox:AddDropdown('TagSearchResults', {
			Text = 'Matches',
			Values = { SEARCH_HINT },
			AllowNull = true,
		}):OnChanged(function(name)
			if type(name) ~= 'string' or name == '' or name == SEARCH_HINT or name == NONE then
				return
			end
			showTagDetail(name)
		end)

		TagsSearchBox:AddButton('Copy wiki: selected tag', function()
			local name = currentSelectedTagName()
			if not name then
				Library:Notify('Pick a tag from All, Search, or New list first', 6)
				warn('[TagWiki] Copy wiki: no tag selected')
				return
			end
			local rec = tagRecordByName(name)
			if not rec then
				Library:Notify('Tag not found — Scan tags first', 6)
				warn('[TagWiki] Copy wiki: no record for ' .. tostring(name))
				return
			end
			local okDump, text = pcall(dumpWikiTag, rec)
			if not okDump then
				Library:Notify('Wiki dump failed: ' .. tostring(text), 8)
				warn('[TagWiki] dumpWikiTag failed: ' .. tostring(text))
				return
			end
			copyWikiTag(text)
		end)

		TagsSearchBox:AddButton('Copy tag module name', function()
			local name = currentSelectedTagName()
			if not name then
				Library:Notify('Pick a tag from All, Search, or New list first')
				return
			end
			local rec = tagRecordByName(name)
			local modName = rec and rec.moduleName or name
			if copyText(modName) then
				Library:Notify('Copied ' .. modName)
			else
				Library:Notify('Clipboard unavailable')
			end
		end)

		task.defer(function()
			local liveCount, aliasCount, settingsCount = scanLiveTags()
			if liveCount > 0 then
				writeTagScanStatus(liveCount, aliasCount, settingsCount)
			end
			local _, tagKnownCount = loadTagsKnownSet()
			if tagKnownCount == 0 and liveCount > 0 then
				runTagScan(false)
			elseif tagKnownCount > 0 then
				setLabel(tagStatusLabel, ('Known tags: %d. Scan after a patch.'):format(tagKnownCount))
				refreshAllTagList()
			elseif liveCount == 0 then
				task.delay(2, function()
					local retryCount, retryAlias, retrySettings = scanLiveTags()
					if retryCount > 0 then
						writeTagScanStatus(retryCount, retryAlias, retrySettings)
						local _, tc = loadTagsKnownSet()
						if tc == 0 then
							runTagScan(false)
						end
					end
				end)
			end
		end)
		end

end
