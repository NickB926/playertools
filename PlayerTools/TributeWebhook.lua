--[[
	TributeWebhook.lua — SwordBurst 2: post to a Discord webhook when a Tribute item drops.
	Standalone copy of the PlayerTools / HiveMind "Webhook: Tribute drops" feature.

	Settings are per Roblox account in PlayerTools/hive/tribute_webhook_<UserId>.json
	(the same file PlayerTools uses, so a URL you already saved there carries over).

	Load:  loadstring(readfile('PlayerTools/TributeWebhook.lua'))()
	Opens its own small window (no other files needed). You can also preset
	getgenv().TributeWebhookUrl / TributeWebhookPing before loading.
]]
local BUILD = 'tribute-webhook-v3'

local G = getgenv()
if type(G.TributeWebhookUnload) == 'function' then
	pcall(G.TributeWebhookUnload)
end

local Players = game:GetService('Players')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local HttpService = game:GetService('HttpService')
local LocalPlayer = Players.LocalPlayer
local DIR = 'PlayerTools/hive'
local CFG = DIR .. '/tribute_webhook_' .. tostring(LocalPlayer.UserId) .. '.json'

local state = { url = '', on = false, ping = '', rarities = 'Tribute' }
local alive = true
local conn

local function notify(msg)
	print('[TributeWebhook] ' .. tostring(msg))
	pcall(function()
		game:GetService('StarterGui'):SetCore('SendNotification', { Title = 'Tribute webhook', Text = tostring(msg), Duration = 4 })
	end)
end

local function normalizeUrl(raw)
	local url = tostring(raw or '')
	url = url:gsub('^%s+', ''):gsub('%s+$', ''):gsub('^<', ''):gsub('>$', '')
	url = url:gsub('^["\']', ''):gsub('["\']$', ''):gsub('%s+', '')
	url = url:gsub('^https://discordapp%.com/', 'https://discord.com/')
	url = url:gsub('^https://canary%.discord%.com/', 'https://discord.com/')
	url = url:gsub('^https://ptb%.discord%.com/', 'https://discord.com/')
	url = url:gsub('^http://discord%.com/', 'https://discord.com/')
	return url
end
local function isWebhook(url)
	return type(url) == 'string' and url:find('discord.com/api/webhooks/', 1, true) ~= nil
end

local function load()
	local ok, data = pcall(function()
		return isfile(CFG) and HttpService:JSONDecode(readfile(CFG)) or nil
	end)
	if ok and type(data) == 'table' then
		state.url = normalizeUrl(data.url)
		state.on = data.enabled == true
		state.ping = tostring(data.ping or ''):gsub('%D', '')
		if type(data.rarities) == 'string' and data.rarities ~= '' then
			state.rarities = data.rarities
		end
	end
	if type(G.TributeWebhookUrl) == 'string' and G.TributeWebhookUrl ~= '' then
		state.url = normalizeUrl(G.TributeWebhookUrl)
		state.on = true
	end
	if type(G.TributeWebhookPing) == 'string' then
		state.ping = G.TributeWebhookPing:gsub('%D', '')
	end
end
local function save()
	pcall(function()
		if not isfolder('PlayerTools') then
			makefolder('PlayerTools')
		end
		if not isfolder(DIR) then
			makefolder(DIR)
		end
		writefile(CFG, HttpService:JSONEncode({
			url = state.url,
			enabled = state.on,
			ping = state.ping,
			rarities = state.rarities,
			userId = LocalPlayer.UserId,
			username = LocalPlayer.Name,
			t = os.time(),
		}))
	end)
end

local function httpRequest(opts)
	local req = (syn and syn.request) or http_request or (http and http.request) or request
	if type(req) ~= 'function' then
		return false, 'no request function'
	end
	return pcall(req, opts)
end

local function post(title, isTest)
	if not isWebhook(state.url) then
		return false, 'bad url'
	end
	local content, allowed = '', { parse = {} }
	if state.ping ~= '' then
		content = ('<@%s>'):format(state.ping)
		allowed = { parse = {}, users = { state.ping } }
	end
	local body = HttpService:JSONEncode({
		content = content,
		allowed_mentions = allowed,
		embeds = {
			{
				title = isTest and '🧪 Tribute webhook test' or '🏆 Tribute drop',
				color = isTest and 0x5865F2 or 0xF1C40F,
				fields = {
					{ name = 'ITEM', value = tostring(title), inline = false },
					{ name = 'ACCOUNT', value = LocalPlayer.Name, inline = false },
					{ name = 'TIME', value = os.date('%Y-%m-%d %H:%M:%S'), inline = false },
				},
			},
		},
	})
	return httpRequest({ Url = state.url, Method = 'POST', Headers = { ['Content-Type'] = 'application/json' }, Body = body })
end

-- SB2 inventory: ReplicatedStorage.Profiles.<name>.Inventory, rarity from ReplicatedStorage.Database.Items.
local function inventory()
	local p = ReplicatedStorage:FindFirstChild('Profiles')
	p = p and p:FindFirstChild(LocalPlayer.Name)
	return p and p:FindFirstChild('Inventory')
end
local function rarity(item)
	local function read(ref)
		if not ref then
			return nil
		end
		local r = ref:FindFirstChild('Rarity')
		if r and r:IsA('ValueBase') then
			return tostring(r.Value)
		end
		local a = ref:GetAttribute('Rarity')
		return a and tostring(a) or nil
	end
	-- the item itself first, then the database entry by name (exact, then case-insensitive)
	local own = read(item)
	if own and own ~= '' then
		return own
	end
	local db = ReplicatedStorage:FindFirstChild('Database')
	local items = db and db:FindFirstChild('Items')
	if not items then
		return ''
	end
	local ref = items:FindFirstChild(item.Name)
	if not ref then
		local key = string.lower(item.Name)
		for _, c in ipairs(items:GetChildren()) do
			if string.lower(c.Name) == key then
				ref = c
				break
			end
		end
	end
	return read(ref) or ''
end
local function count(item)
	local c = item:FindFirstChild('Count')
	return c and c:IsA('ValueBase') and tonumber(c.Value) or 1
end

-- Which rarities to post (comma separated in the window). Default: Tribute.
local function wanted(r)
	r = string.lower(tostring(r or ''))
	for w in tostring(state.rarities or 'Tribute'):gmatch('[^,]+') do
		if string.lower((w:gsub('^%s+', ''):gsub('%s+$', ''))) == r then
			return true
		end
	end
	return false
end

-- Track the item objects themselves (not their ids — copies of the same item share an id),
-- plus each stack's count so a stack going 1 -> 2 also counts as a drop.
local known = setmetatable({}, { __mode = 'k' }) -- [Instance] = last count
local recent = {}
local lastSeen = ''
local itemConns = {}

local function announce(item, r)
	local key = string.lower(item.Name)
	if os.clock() - (recent[key] or 0) < 3 then
		return -- same drop reported twice in a row
	end
	recent[key] = os.clock()
	local up = item:FindFirstChild('Upgrade')
	local upv = up and up:IsA('ValueBase') and tonumber(up.Value)
	local title = upv and upv > 0 and ('%s (+%d)'):format(item.Name, upv) or item.Name
	notify(('%s drop: %s'):format(r, title))
	task.spawn(function()
		local ok, res = post(title, false)
		local code = type(res) == 'table' and (res.StatusCode or res.Status) or nil
		print(('[TributeWebhook] posted %s -> %s %s'):format(title, tostring(ok), tostring(code or res)))
	end)
end

local function watchCount(item)
	local c = item:FindFirstChild('Count')
	if c and c:IsA('ValueBase') then
		itemConns[#itemConns + 1] = c.Changed:Connect(function()
			local now = count(item)
			local before = known[item] or now
			known[item] = now
			if now > before and alive and state.on then
				local r = rarity(item)
				lastSeen = ('%s x%d (%s)'):format(item.Name, now, r ~= '' and r or '?')
				if wanted(r) then
					announce(item, r)
				end
			end
		end)
	end
end

local function onItem(item)
	if not alive or not item.Parent or known[item] ~= nil then
		return
	end
	known[item] = count(item)
	watchCount(item)
	local r = rarity(item)
	lastSeen = ('%s (%s)'):format(item.Name, r ~= '' and r or 'no rarity found')
	print('[TributeWebhook] new item: ' .. lastSeen)
	if state.on and wanted(r) then
		announce(item, r)
	end
end

local function stopWatch()
	if conn then
		pcall(function()
			conn:Disconnect()
		end)
		conn = nil
	end
	for _, c in ipairs(itemConns) do
		pcall(function()
			c:Disconnect()
		end)
	end
	itemConns = {}
end
local function startWatch()
	stopWatch()
	if not (alive and state.on and isWebhook(state.url)) then
		return
	end
	local inv = inventory()
	if not inv then
		task.delay(2, startWatch)
		return
	end
	for _, item in ipairs(inv:GetChildren()) do
		known[item] = count(item) -- don't announce what you already have
		watchCount(item)
	end
	conn = inv.ChildAdded:Connect(function(child)
		task.wait(0.2) -- let Count / Upgrade replicate
		onItem(child)
	end)
end

local function apply(quiet)
	save()
	if state.on and isWebhook(state.url) then
		startWatch()
		if not quiet then
			notify('Tribute webhook armed')
		end
	else
		stopWatch()
		if state.on and state.url ~= '' and not isWebhook(state.url) and not quiet then
			notify('Webhook URL looks wrong (needs discord.com/api/webhooks/...)')
		end
	end
end

local function test()
	if not isWebhook(state.url) then
		notify('Set a Discord webhook URL first')
		return
	end
	local ok, res = post('Test message', true)
	local code = type(res) == 'table' and (res.StatusCode or res.Status) or nil
	notify(ok and ('Test sent' .. (code and (' (HTTP ' .. tostring(code) .. ')') or '')) or ('Test failed: ' .. tostring(res)))
end

load()

-- Built-in window (no library files needed, works on any account / PC).
local screen
do
	local parent = (gethui and gethui()) or game:GetService('CoreGui')
	pcall(function()
		local old = parent:FindFirstChild('TributeWebhookGui')
		if old then
			old:Destroy()
		end
	end)
	screen = Instance.new('ScreenGui')
	screen.Name = 'TributeWebhookGui'
	screen.ResetOnSpawn = false
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	pcall(function()
		if syn and syn.protect_gui then
			syn.protect_gui(screen)
		end
	end)
	screen.Parent = parent

	local BG, PANEL, ACCENT, TEXT, DIM = Color3.fromRGB(18, 18, 22), Color3.fromRGB(30, 30, 37), Color3.fromRGB(241, 196, 15), Color3.fromRGB(235, 235, 240), Color3.fromRGB(150, 150, 160)
	local function corner(o, r)
		local c = Instance.new('UICorner')
		c.CornerRadius = UDim.new(0, r or 6)
		c.Parent = o
	end
	local frame = Instance.new('Frame')
	frame.Size = UDim2.fromOffset(340, 300)
	frame.Position = UDim2.new(0.5, -170, 0.5, -150)
	frame.BackgroundColor3 = BG
	frame.BorderSizePixel = 0
	frame.Active = true
	frame.Parent = screen
	corner(frame, 8)
	local stroke = Instance.new('UIStroke')
	stroke.Color = Color3.fromRGB(60, 60, 70)
	stroke.Parent = frame

	local title = Instance.new('TextLabel')
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(12, 6)
	title.Size = UDim2.new(1, -60, 0, 26)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 15
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = ACCENT
	title.Text = '🏆 Tribute Webhook  ·  ' .. LocalPlayer.Name
	title.Parent = frame

	local close = Instance.new('TextButton')
	close.Size = UDim2.fromOffset(26, 26)
	close.Position = UDim2.new(1, -32, 0, 6)
	close.BackgroundColor3 = PANEL
	close.TextColor3 = TEXT
	close.Font = Enum.Font.GothamBold
	close.TextSize = 14
	close.Text = '–'
	close.Parent = frame
	corner(close)

	local body = Instance.new('Frame')
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(12, 38)
	body.Size = UDim2.new(1, -24, 1, -46)
	body.Parent = frame
	local list = Instance.new('UIListLayout')
	list.Padding = UDim.new(0, 6)
	list.Parent = body

	local function label(text)
		local l = Instance.new('TextLabel')
		l.BackgroundTransparency = 1
		l.Size = UDim2.new(1, 0, 0, 14)
		l.Font = Enum.Font.Gotham
		l.TextSize = 12
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.TextColor3 = DIM
		l.Text = text
		l.Parent = body
		return l
	end
	local function box(text, placeholder)
		local b = Instance.new('TextBox')
		b.Size = UDim2.new(1, 0, 0, 28)
		b.BackgroundColor3 = PANEL
		b.TextColor3 = TEXT
		b.PlaceholderColor3 = DIM
		b.Font = Enum.Font.Gotham
		b.TextSize = 12
		b.ClearTextOnFocus = false
		b.TextXAlignment = Enum.TextXAlignment.Left
		b.TextTruncate = Enum.TextTruncate.AtEnd
		b.PlaceholderText = placeholder
		b.Text = text
		b.Parent = body
		corner(b)
		local pad = Instance.new('UIPadding')
		pad.PaddingLeft = UDim.new(0, 8)
		pad.PaddingRight = UDim.new(0, 8)
		pad.Parent = b
		return b
	end
	local function button(text, color)
		local b = Instance.new('TextButton')
		b.Size = UDim2.new(0.5, -3, 0, 30)
		b.BackgroundColor3 = color or PANEL
		b.TextColor3 = TEXT
		b.Font = Enum.Font.GothamBold
		b.TextSize = 13
		b.Text = text
		corner(b)
		return b
	end

	label('Discord webhook URL')
	local urlBox = box(state.url, 'https://discord.com/api/webhooks/...')
	label('Your Discord user ID to ping (optional)')
	local pingBox = box(state.ping, 'Developer Mode → right-click you → Copy User ID')
	label('Rarities to post (comma separated)')
	local rarBox = box(state.rarities, 'Tribute')

	local row = Instance.new('Frame')
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 30)
	row.Parent = body
	local rowList = Instance.new('UIListLayout')
	rowList.FillDirection = Enum.FillDirection.Horizontal
	rowList.Padding = UDim.new(0, 6)
	rowList.Parent = row
	local toggleBtn = button('')
	toggleBtn.Parent = row
	local testBtn = button('Test webhook')
	testBtn.Parent = row

	local statusLbl = label('')
	statusLbl.TextColor3 = DIM
	local seenLbl = label('Last item: (none yet)')
	task.spawn(function()
		while screen.Parent and alive do
			if lastSeen ~= '' then
				seenLbl.Text = 'Last item: ' .. lastSeen
			end
			task.wait(0.5)
		end
	end)

	local function refresh()
		toggleBtn.Text = state.on and 'ON  · watching drops' or 'OFF · click to arm'
		toggleBtn.BackgroundColor3 = state.on and Color3.fromRGB(46, 125, 50) or PANEL
		if state.on and not isWebhook(state.url) then
			statusLbl.Text = 'URL needs to be discord.com/api/webhooks/...'
		else
			statusLbl.Text = state.on and ('Armed — posting: ' .. tostring(state.rarities)) or 'Not armed.'
		end
	end
	urlBox.FocusLost:Connect(function()
		state.url = normalizeUrl(urlBox.Text)
		urlBox.Text = state.url
		apply(true)
		refresh()
	end)
	rarBox.FocusLost:Connect(function()
		state.rarities = rarBox.Text ~= '' and rarBox.Text or 'Tribute'
		rarBox.Text = state.rarities
		save()
		refresh()
	end)
	pingBox.FocusLost:Connect(function()
		state.ping = tostring(pingBox.Text or ''):gsub('%D', '')
		pingBox.Text = state.ping
		apply(true)
		refresh()
	end)
	toggleBtn.MouseButton1Click:Connect(function()
		state.url = normalizeUrl(urlBox.Text)
		state.on = not state.on
		apply(false)
		refresh()
	end)
	testBtn.MouseButton1Click:Connect(function()
		state.url = normalizeUrl(urlBox.Text)
		state.ping = tostring(pingBox.Text or ''):gsub('%D', '')
		save()
		statusLbl.Text = 'Sending test…'
		task.spawn(function()
			test()
			task.wait(2)
			refresh()
		end)
	end)

	-- Minimise / drag
	local minimized = false
	close.MouseButton1Click:Connect(function()
		minimized = not minimized
		body.Visible = not minimized
		frame.Size = minimized and UDim2.fromOffset(340, 38) or UDim2.fromOffset(340, 300)
		close.Text = minimized and '+' or '–'
	end)
	local UIS = game:GetService('UserInputService')
	local dragging, dragStart, startPos
	frame.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging, dragStart, startPos = true, input.Position, frame.Position
		end
	end)
	UIS.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - dragStart
			frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
		end
	end)
	UIS.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
	refresh()
end

apply(true)

G.TributeWebhookTest = test
G.TributeWebhookUnload = function(fromWindow)
	alive = false
	stopWatch()
	G.TributeWebhookUnload = nil
	pcall(function()
		screen:Destroy()
	end)
end

notify(('loaded — %s'):format(state.on and isWebhook(state.url) and 'watching for Tribute drops' or 'set a webhook URL to arm it'))
