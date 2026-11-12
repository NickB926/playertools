--!nocheck
--!nolint
--[[
	InventoryThemes.lua — PlayerTools module.
	Re-skins the game's menu / inventory window (CardinalUI.PlayerUI.MainFrame: the window with
	the Inventory / Skills / Travel ... tabs) on YOUR screen only.
	Item data, equipping, upgrading etc. are untouched: only colours / corners / outlines / fonts.

	LIGHT version: v4 added outlines/corners/watchers to every slot (~1,800) and a button inside
	the game's menu, and the inventory stopped loading. This version only changes colours and
	fonts on what is already there, adds NO instances inside the game's UI, and keeps no per-slot
	connections. The theme button lives in its own ScreenGui that follows the menu window.
	Slot tiles keep the game's rarity colours untouched.

	getgenv().SB2SetInventoryTheme('Midnight')  -- or 'Default' to put the game's look back
	getgenv().SB2InventoryThemeNames            -- list of theme names
]]

local BUILD = 'invtheme-v9b-bars'
local g = getgenv()

if type(g.SB2InventoryThemeStop) == 'function' then
	pcall(g.SB2InventoryThemeStop)
end

local Players = game:GetService('Players')
local LocalPlayer = Players.LocalPlayer

local buildPicker -- defined further down; the UI-rebuild hook calls it
local TAG = 'SB2Theme' -- name prefix of every instance we add, so we can remove them

-- ── themes ─────────────────────────────────────────────────────────────────
-- panel / panelT : window background colour + transparency
-- accent         : top/bottom bars, window outline, active text
-- slot / slotT   : slot tile colour + how much of the game's rarity tile shows (rarityT)
-- text / font    : level / count text
local THEMES = {
	Midnight = {
		panel = Color3.fromRGB(14, 17, 28), panelT = 0.08,
		accent = Color3.fromRGB(110, 170, 255),
		slot = Color3.fromRGB(26, 31, 48), slotT = 0, rarityT = 0.72,
		button = Color3.fromRGB(30, 36, 56), buttonText = Color3.fromRGB(205, 220, 255),
		text = Color3.fromRGB(225, 232, 255), font = Enum.Font.GothamBold,
		corner = 10, stroke = 2,
	},
	Crimson = {
		panel = Color3.fromRGB(22, 8, 12), panelT = 0.1,
		accent = Color3.fromRGB(255, 70, 90),
		slot = Color3.fromRGB(40, 14, 20), slotT = 0, rarityT = 0.7,
		button = Color3.fromRGB(58, 18, 26), buttonText = Color3.fromRGB(255, 205, 210),
		text = Color3.fromRGB(255, 230, 232), font = Enum.Font.GothamBold,
		corner = 8, stroke = 2,
	},
	Glass = {
		panel = Color3.fromRGB(235, 240, 255), panelT = 0.82,
		accent = Color3.fromRGB(255, 255, 255),
		slot = Color3.fromRGB(255, 255, 255), slotT = 0.86, rarityT = 0.45,
		button = Color3.fromRGB(255, 255, 255), buttonText = Color3.fromRGB(255, 255, 255),
		buttonT = 0.8,
		text = Color3.fromRGB(255, 255, 255), font = Enum.Font.GothamMedium,
		corner = 14, stroke = 1.5,
	},
	Mono = {
		panel = Color3.fromRGB(18, 18, 18), panelT = 0.05,
		accent = Color3.fromRGB(240, 240, 240),
		slot = Color3.fromRGB(34, 34, 34), slotT = 0, rarityT = 0.85,
		button = Color3.fromRGB(44, 44, 44), buttonText = Color3.fromRGB(235, 235, 235),
		text = Color3.fromRGB(240, 240, 240), font = Enum.Font.Code,
		corner = 4, stroke = 1.5,
	},
	Gold = {
		panel = Color3.fromRGB(24, 19, 10), panelT = 0.08,
		accent = Color3.fromRGB(240, 190, 70),
		slot = Color3.fromRGB(44, 34, 16), slotT = 0, rarityT = 0.7,
		button = Color3.fromRGB(60, 46, 20), buttonText = Color3.fromRGB(255, 230, 170),
		text = Color3.fromRGB(255, 240, 205), font = Enum.Font.Garamond,
		corner = 6, stroke = 2,
	},
	Sakura = {
		panel = Color3.fromRGB(36, 22, 32), panelT = 0.1,
		accent = Color3.fromRGB(255, 160, 200),
		slot = Color3.fromRGB(58, 34, 50), slotT = 0, rarityT = 0.7,
		button = Color3.fromRGB(78, 42, 64), buttonText = Color3.fromRGB(255, 220, 236),
		text = Color3.fromRGB(255, 236, 246), font = Enum.Font.FredokaOne,
		corner = 16, stroke = 2,
	},
	Ocean = {
		panel = Color3.fromRGB(8, 26, 40), panelT = 0.08,
		accent = Color3.fromRGB(60, 200, 220),
		slot = Color3.fromRGB(14, 44, 62), slotT = 0, rarityT = 0.7,
		button = Color3.fromRGB(16, 56, 78), buttonText = Color3.fromRGB(190, 240, 250),
		text = Color3.fromRGB(220, 248, 255), font = Enum.Font.GothamBold,
		corner = 8, stroke = 2,
	},
	Emerald = {
		panel = Color3.fromRGB(8, 26, 16), panelT = 0.08,
		accent = Color3.fromRGB(70, 220, 130),
		slot = Color3.fromRGB(14, 46, 28), slotT = 0, rarityT = 0.7,
		button = Color3.fromRGB(18, 60, 36), buttonText = Color3.fromRGB(195, 255, 215),
		text = Color3.fromRGB(225, 255, 235), font = Enum.Font.GothamBold,
		corner = 8, stroke = 2,
	},
	Amethyst = {
		panel = Color3.fromRGB(24, 12, 36), panelT = 0.08,
		accent = Color3.fromRGB(190, 120, 255),
		slot = Color3.fromRGB(40, 22, 60), slotT = 0, rarityT = 0.7,
		button = Color3.fromRGB(54, 28, 82), buttonText = Color3.fromRGB(230, 205, 255),
		text = Color3.fromRGB(242, 228, 255), font = Enum.Font.GothamBold,
		corner = 8, stroke = 2,
	},
	Sunset = {
		panel = Color3.fromRGB(36, 14, 18), panelT = 0.08,
		accent = Color3.fromRGB(255, 140, 70),
		slot = Color3.fromRGB(60, 24, 30), slotT = 0, rarityT = 0.7,
		button = Color3.fromRGB(84, 32, 36), buttonText = Color3.fromRGB(255, 215, 180),
		text = Color3.fromRGB(255, 236, 220), font = Enum.Font.GothamBold,
		corner = 8, stroke = 2,
	},
	Frost = {
		panel = Color3.fromRGB(220, 236, 248), panelT = 0.15,
		accent = Color3.fromRGB(70, 150, 230),
		slot = Color3.fromRGB(190, 214, 236), slotT = 0, rarityT = 0.7,
		button = Color3.fromRGB(176, 204, 232), buttonText = Color3.fromRGB(20, 50, 90),
		text = Color3.fromRGB(15, 40, 75), font = Enum.Font.GothamBold,
		corner = 8, stroke = 2,
	},
	Void = {
		panel = Color3.fromRGB(2, 2, 4), panelT = 0.0,
		accent = Color3.fromRGB(150, 70, 255),
		slot = Color3.fromRGB(10, 8, 16), slotT = 0, rarityT = 0.7,
		button = Color3.fromRGB(16, 12, 26), buttonText = Color3.fromRGB(200, 170, 255),
		text = Color3.fromRGB(220, 205, 255), font = Enum.Font.Arcade,
		corner = 8, stroke = 2,
	},
	Neon = {
		panel = Color3.fromRGB(6, 4, 18), panelT = 0.05,
		accent = Color3.fromRGB(0, 255, 200),
		slot = Color3.fromRGB(14, 10, 34), slotT = 0, rarityT = 0.7,
		button = Color3.fromRGB(20, 14, 48), buttonText = Color3.fromRGB(255, 70, 220),
		text = Color3.fromRGB(0, 255, 200), font = Enum.Font.Arcade,
		corner = 8, stroke = 2,
	},
	Lava = {
		panel = Color3.fromRGB(28, 8, 2), panelT = 0.05,
		accent = Color3.fromRGB(255, 110, 20),
		slot = Color3.fromRGB(52, 16, 6), slotT = 0, rarityT = 0.7,
		button = Color3.fromRGB(74, 22, 8), buttonText = Color3.fromRGB(255, 200, 140),
		text = Color3.fromRGB(255, 228, 200), font = Enum.Font.Bangers,
		corner = 8, stroke = 2,
	},
	Forest = {
		panel = Color3.fromRGB(16, 22, 12), panelT = 0.1,
		accent = Color3.fromRGB(160, 200, 90),
		slot = Color3.fromRGB(30, 40, 22), slotT = 0, rarityT = 0.7,
		button = Color3.fromRGB(42, 54, 30), buttonText = Color3.fromRGB(220, 235, 190),
		text = Color3.fromRGB(235, 245, 215), font = Enum.Font.Fantasy,
		corner = 8, stroke = 2,
	},
	Coffee = {
		panel = Color3.fromRGB(30, 20, 14), panelT = 0.08,
		accent = Color3.fromRGB(205, 155, 100),
		slot = Color3.fromRGB(52, 36, 26), slotT = 0, rarityT = 0.7,
		button = Color3.fromRGB(68, 48, 34), buttonText = Color3.fromRGB(240, 220, 195),
		text = Color3.fromRGB(248, 235, 218), font = Enum.Font.Merriweather,
		corner = 8, stroke = 2,
	},
	Bubblegum = {
		panel = Color3.fromRGB(255, 220, 238), panelT = 0.2,
		accent = Color3.fromRGB(255, 90, 170),
		slot = Color3.fromRGB(255, 190, 222), slotT = 0, rarityT = 0.7,
		button = Color3.fromRGB(255, 170, 210), buttonText = Color3.fromRGB(120, 20, 70),
		text = Color3.fromRGB(110, 20, 64), font = Enum.Font.FredokaOne,
		corner = 8, stroke = 2,
	},
	Retro = {
		panel = Color3.fromRGB(10, 10, 6), panelT = 0.05,
		accent = Color3.fromRGB(255, 176, 0),
		slot = Color3.fromRGB(22, 20, 10), slotT = 0, rarityT = 0.7,
		button = Color3.fromRGB(30, 26, 12), buttonText = Color3.fromRGB(255, 190, 60),
		text = Color3.fromRGB(255, 200, 80), font = Enum.Font.Code,
		corner = 8, stroke = 2,
	},
	Abyss = {
		panel = Color3.fromRGB(4, 10, 22), panelT = 0.05,
		accent = Color3.fromRGB(40, 120, 255),
		slot = Color3.fromRGB(8, 20, 40), slotT = 0, rarityT = 0.7,
		button = Color3.fromRGB(10, 26, 52), buttonText = Color3.fromRGB(150, 190, 255),
		text = Color3.fromRGB(200, 220, 255), font = Enum.Font.SciFi,
		corner = 8, stroke = 2,
	},
	Royal = {
		panel = Color3.fromRGB(18, 10, 40), panelT = 0.08,
		accent = Color3.fromRGB(255, 205, 70),
		slot = Color3.fromRGB(34, 22, 72), slotT = 0, rarityT = 0.7,
		button = Color3.fromRGB(44, 28, 92), buttonText = Color3.fromRGB(255, 230, 160),
		text = Color3.fromRGB(255, 240, 200), font = Enum.Font.Garamond,
		corner = 8, stroke = 2,
	},
	Mint = {
		panel = Color3.fromRGB(228, 250, 242), panelT = 0.18,
		accent = Color3.fromRGB(30, 170, 130),
		slot = Color3.fromRGB(200, 240, 226), slotT = 0, rarityT = 0.7,
		button = Color3.fromRGB(186, 232, 216), buttonText = Color3.fromRGB(10, 80, 60),
		text = Color3.fromRGB(8, 70, 52), font = Enum.Font.GothamBold,
		corner = 8, stroke = 2,
	},
	['Frosted Glass'] = {
		panel = Color3.fromRGB(200, 225, 255), panelT = 0.78,
		accent = Color3.fromRGB(170, 215, 255),
		slot = Color3.fromRGB(210, 232, 255), slotT = 0.86, rarityT = 0.45,
		button = Color3.fromRGB(210, 232, 255), buttonText = Color3.fromRGB(235, 245, 255),
		buttonT = 0.75,
		text = Color3.fromRGB(240, 248, 255), font = Enum.Font.GothamMedium,
		corner = 14, stroke = 1.5,
	},
	['Smoke Glass'] = {
		panel = Color3.fromRGB(10, 10, 14), panelT = 0.72,
		accent = Color3.fromRGB(200, 200, 210),
		slot = Color3.fromRGB(30, 30, 38), slotT = 0.86, rarityT = 0.45,
		button = Color3.fromRGB(30, 30, 38), buttonText = Color3.fromRGB(230, 230, 240),
		buttonT = 0.7,
		text = Color3.fromRGB(240, 240, 245), font = Enum.Font.GothamMedium,
		corner = 14, stroke = 1.5,
	},
	['Rose Glass'] = {
		panel = Color3.fromRGB(255, 200, 220), panelT = 0.8,
		accent = Color3.fromRGB(255, 150, 190),
		slot = Color3.fromRGB(255, 210, 228), slotT = 0.86, rarityT = 0.45,
		button = Color3.fromRGB(255, 210, 228), buttonText = Color3.fromRGB(255, 235, 243),
		buttonT = 0.75,
		text = Color3.fromRGB(255, 242, 248), font = Enum.Font.GothamMedium,
		corner = 14, stroke = 1.5,
	},
	['Aqua Glass'] = {
		panel = Color3.fromRGB(160, 245, 235), panelT = 0.8,
		accent = Color3.fromRGB(90, 230, 210),
		slot = Color3.fromRGB(190, 250, 242), slotT = 0.86, rarityT = 0.45,
		button = Color3.fromRGB(190, 250, 242), buttonText = Color3.fromRGB(225, 255, 250),
		buttonT = 0.75,
		text = Color3.fromRGB(235, 255, 252), font = Enum.Font.GothamMedium,
		corner = 14, stroke = 1.5,
	},
	['Violet Glass'] = {
		panel = Color3.fromRGB(205, 180, 255), panelT = 0.8,
		accent = Color3.fromRGB(185, 150, 255),
		slot = Color3.fromRGB(220, 200, 255), slotT = 0.86, rarityT = 0.45,
		button = Color3.fromRGB(220, 200, 255), buttonText = Color3.fromRGB(240, 232, 255),
		buttonT = 0.75,
		text = Color3.fromRGB(246, 240, 255), font = Enum.Font.GothamMedium,
		corner = 14, stroke = 1.5,
	},
	['Amber Glass'] = {
		panel = Color3.fromRGB(255, 205, 130), panelT = 0.8,
		accent = Color3.fromRGB(255, 190, 90),
		slot = Color3.fromRGB(255, 220, 160), slotT = 0.86, rarityT = 0.45,
		button = Color3.fromRGB(255, 220, 160), buttonText = Color3.fromRGB(255, 242, 220),
		buttonT = 0.75,
		text = Color3.fromRGB(255, 246, 230), font = Enum.Font.GothamMedium,
		corner = 14, stroke = 1.5,
	},
	['Mint Glass'] = {
		panel = Color3.fromRGB(180, 255, 215), panelT = 0.8,
		accent = Color3.fromRGB(120, 235, 175),
		slot = Color3.fromRGB(205, 255, 228), slotT = 0.86, rarityT = 0.45,
		button = Color3.fromRGB(205, 255, 228), buttonText = Color3.fromRGB(230, 255, 242),
		buttonT = 0.75,
		text = Color3.fromRGB(238, 255, 246), font = Enum.Font.GothamMedium,
		corner = 14, stroke = 1.5,
	},
	['Clear'] = {
		panel = Color3.fromRGB(255, 255, 255), panelT = 0.96,
		accent = Color3.fromRGB(255, 255, 255),
		slot = Color3.fromRGB(255, 255, 255), slotT = 0.86, rarityT = 0.45,
		button = Color3.fromRGB(255, 255, 255), buttonText = Color3.fromRGB(255, 255, 255),
		buttonT = 0.92,
		text = Color3.fromRGB(255, 255, 255), font = Enum.Font.GothamMedium,
		corner = 14, stroke = 1.5,
	},
	['Night Glass'] = {
		panel = Color3.fromRGB(20, 30, 70), panelT = 0.72,
		accent = Color3.fromRGB(120, 160, 255),
		slot = Color3.fromRGB(40, 55, 110), slotT = 0.86, rarityT = 0.45,
		button = Color3.fromRGB(40, 55, 110), buttonText = Color3.fromRGB(215, 225, 255),
		buttonT = 0.7,
		text = Color3.fromRGB(230, 236, 255), font = Enum.Font.GothamMedium,
		corner = 14, stroke = 1.5,
	},
}
local NAMES = {
	'Default', 'Midnight', 'Crimson', 'Glass', 'Mono', 'Gold', 'Sakura',
	'Ocean', 'Emerald', 'Amethyst', 'Sunset', 'Frost', 'Void', 'Neon', 'Lava',
	'Forest', 'Coffee', 'Bubblegum', 'Retro', 'Abyss', 'Royal', 'Mint',
	'Frosted Glass', 'Smoke Glass', 'Rose Glass', 'Aqua Glass', 'Violet Glass',
	'Amber Glass', 'Mint Glass', 'Night Glass', 'Clear',
}

local S = {
	theme = nil,
	conns = {},
	-- instance -> { prop = original value }. Strong keys on purpose: Roblox can drop an
	-- Instance from a weak table while it still exists, and its original look was lost.
	saved = {},
	added = {},
}
g.SB2InventoryThemeState = S
g.SB2InventoryThemeBuild = BUILD
g.SB2InventoryThemeNames = NAMES

-- ── helpers ────────────────────────────────────────────────────────────────

local function setp(inst, prop, value)
	if not inst then
		return
	end
	local rec = S.saved[inst]
	if not rec then
		rec = {}
		S.saved[inst] = rec
	end
	if rec[prop] == nil then
		local ok, cur = pcall(function()
			return inst[prop]
		end)
		if not ok then
			return
		end
		rec[prop] = cur
	end
	pcall(function()
		inst[prop] = value
	end)
end

local function addChild(parent, className, name, props)
	if not parent then
		return nil
	end
	local inst = parent:FindFirstChild(TAG .. name)
	if not inst then
		inst = Instance.new(className)
		inst.Name = TAG .. name
		inst.Parent = parent
		S.added[#S.added + 1] = inst
	end
	for k, v in pairs(props) do
		pcall(function()
			inst[k] = v
		end)
	end
	return inst
end

local function restoreAll()
	for inst, rec in pairs(S.saved) do
		for prop, value in pairs(rec) do
			pcall(function()
				inst[prop] = value
			end)
		end
	end
	S.saved = {}
	for _, inst in ipairs(S.added) do
		pcall(function()
			inst:Destroy()
		end)
	end
	S.added = {}
end

local function disconnectAll()
	for _, c in ipairs(S.conns) do
		pcall(function()
			c:Disconnect()
		end)
	end
	S.conns = {}
end

-- The window you actually use (tabs: Inventory, Skills, Travel, Players, Store, Stats, Quests).
-- PlayerUI.Inventory is an old hidden frame the game keeps around; it is not this.
local function inventoryRoot()
	local pg = LocalPlayer and LocalPlayer:FindFirstChild('PlayerGui')
	local c = pg and pg:FindFirstChild('CardinalUI')
	local p = c and c:FindFirstChild('PlayerUI')
	return p and p:FindFirstChild('MainFrame')
end

-- Returns the scrolling item grid.
local function slotList(root)
	local tf = root and root:FindFirstChild('TabFrames')
	local f = tf and tf:FindFirstChild('InventoryFrame')
	local inv = f and f:FindFirstChild('Inventory')
	local list = inv and inv:FindFirstChild('List')
	return list, list
end

-- The equipped-item slots on the character panel (left side).
local function equipSlots(root)
	local tf = root and root:FindFirstChild('TabFrames')
	local f = tf and tf:FindFirstChild('InventoryFrame')
	local cf = f and f:FindFirstChild('CharacterFrame')
	local ch = cf and cf:FindFirstChild('Character')
	local out = {}
	if ch then
		for _, d in ipairs(ch:GetDescendants()) do
			if d:IsA('GuiButton') and d:FindFirstChild('Frame') then
				out[#out + 1] = d
			end
		end
	end
	return out, cf
end

-- ── styling ────────────────────────────────────────────────────────────────

local function styleText(lbl, T)
	if not lbl or not lbl:IsA('TextLabel') then
		return
	end
	setp(lbl, 'TextColor3', T.text)
	setp(lbl, 'Font', T.font)
end

local function styleSlot(slot, T)
	if not slot:IsA('GuiButton') then
		return
	end
	local frame = slot:FindFirstChild('Frame')
	if not frame then
		return
	end
	local inner = frame:FindFirstChild('InnerShadow')
	if inner then
		setp(inner, 'ImageTransparency', 0.6)
	end
	styleText(frame:FindFirstChild('Level'), T)
	styleText(frame:FindFirstChild('Count'), T)
end

local function styleButtons(inv, T)
	local sorting = inv:FindFirstChild('ItemSorting')
	if not sorting then
		return
	end
	local buttons = sorting:FindFirstChild('Buttons')
	if buttons then
		for _, b in ipairs(buttons:GetChildren()) do
			if b:IsA('TextButton') then
				setp(b, 'BackgroundColor3', T.button)
				setp(b, 'BackgroundTransparency', T.buttonT or 0)
				setp(b, 'TextColor3', T.buttonText)
				setp(b, 'Font', T.font)
			end
		end
	end
	local search = sorting:FindFirstChild('SearchFrame')
	if search then
		setp(search, 'BackgroundColor3', T.button)
		setp(search, 'BackgroundTransparency', T.buttonT or 0)
		local box = search:FindFirstChild('SearchBox')
		if box then
			setp(box, 'TextColor3', T.buttonText)
			setp(box, 'PlaceholderColor3', T.buttonText:Lerp(Color3.new(0.5, 0.5, 0.5), 0.5))
			setp(box, 'Font', T.font)
		end
	end
end

local function styleWindow(root, T)
	local tf = root:FindFirstChild('TabFrames')
	if tf then
		setp(tf, 'BackgroundColor3', T.panel)
		setp(tf, 'BackgroundTransparency', T.panelT)
	end
	-- Tab bar along the top.
	local bkg = root:FindFirstChild('TabsBkg')
	if bkg then
		setp(bkg, 'BackgroundColor3', T.button)
		setp(bkg, 'BackgroundTransparency', math.min(T.panelT + 0.05, 0.9))
	end
	local tabs = root:FindFirstChild('Tabs')
	if tabs then
		for _, d in ipairs(tabs:GetDescendants()) do
			if d:IsA('TextLabel') or d:IsA('TextButton') then
				setp(d, 'TextColor3', T.buttonText)
				setp(d, 'Font', T.font)
			elseif d:IsA('ImageLabel') or d:IsA('ImageButton') then
				setp(d, 'ImageColor3', T.accent)
			end
		end
	end
	-- Character / equipment panel on the left.
	local _, cf = equipSlots(root)
	if cf then
		setp(cf, 'BackgroundColor3', T.slot)
		setp(cf, 'BackgroundTransparency', math.clamp(T.panelT + 0.25, 0, 0.92))
		local cur = cf:FindFirstChild('Currency')
		if cur and cur:IsA('TextLabel') then
			setp(cur, 'TextColor3', T.accent)
			setp(cur, 'Font', T.font)
		end
	end
	-- Window drop shadow: tint it so light themes don't get a black halo.
	local shadow = root:FindFirstChild('BoxShadow')
	if shadow then
		for _, d in ipairs(shadow:GetChildren()) do
			if d:IsA('ImageLabel') then
				setp(d, 'ImageColor3', T.panel)
			end
		end
	end
	local list = slotList(root)
	if list and list:IsA('ScrollingFrame') then
		setp(list, 'ScrollBarImageColor3', T.accent)
	end
end

-- ── generic restyle (other menu tabs, HUD, hotkey bar) ─────────────────────
-- Properties only, decided from each element's ORIGINAL colour (so re-applying or
-- switching themes never compounds): grey/white text → theme text + font, dark grey
-- backgrounds → theme panel/button, the game's gold → theme accent. Coloured things
-- (rarity, red/green, health/stamina bars, item icons) are left alone.
local GAME_GOLD = Color3.new(0.827451, 0.627451, 0.223529)
local SKIP_NAMES = {
	Healthbar = true, StaminaBar = true, Redbar = true, Bar = true,
	Icon = true, Cooldown = true, Shadow = true, InnerShadow = true,
	-- (the inventory page is skipped as a whole: it has its own styling)
	ScrollContent = true, -- chat lines already on screen (new ones come from themed templates)
}

local function orig(inst, prop)
	local rec = S.saved[inst]
	if rec and rec[prop] ~= nil then
		return rec[prop]
	end
	local ok, v = pcall(function()
		return inst[prop]
	end)
	return ok and v or nil
end

local function satLum(c)
	local hi = math.max(c.R, c.G, c.B)
	local lo = math.min(c.R, c.G, c.B)
	return hi - lo, hi
end

local function isGold(c)
	return typeof(c) == 'Color3'
		and math.abs(c.R - GAME_GOLD.R) + math.abs(c.G - GAME_GOLD.G) + math.abs(c.B - GAME_GOLD.B) < 0.2
end

-- HUD / wave panel: the right-hand counters get their colours from UIGradients. Recolour
-- only the decorative ones; lives, hearts and the damage gradient keep their meaning.
local HUD_SKIP = {
	Healthbar = true, StaminaBar = true, Redbar = true,
	Lives = true, Heart = true, DamageGradient = true,
	Revive = true, Spectate = true, Return = true,
	MobVariant = true, -- boss variant tag (colour means something)
}
local HUD_RIMS = { HealthRim = true, StaminaRim = true }

local function styleNode(d, T, hud)
	if hud and d:IsA('UIGradient') then
		local par = d.Parent
		if par and not HUD_SKIP[par.Name] then
			setp(d, 'Color', ColorSequence.new(T.accent:Lerp(Color3.new(1, 1, 1), 0.45), T.accent))
		end
		return
	end
	if hud and HUD_RIMS[d.Name] and d:IsA('ImageLabel') then
		setp(d, 'ImageColor3', T.accent)
		return
	end
	if d:IsA('UIStroke') then
		local c = orig(d, 'Color')
		if isGold(c) then
			setp(d, 'Color', T.accent)
		end
		return
	end
	if not d:IsA('GuiObject') then
		return
	end
	if d:IsA('TextLabel') or d:IsA('TextButton') or d:IsA('TextBox') then
		local c = orig(d, 'TextColor3')
		if typeof(c) == 'Color3' then
			local s, l = satLum(c)
			if isGold(c) then
				setp(d, 'TextColor3', T.accent)
				setp(d, 'Font', T.font)
			elseif s < 0.12 and l > 0.55 then
				setp(d, 'TextColor3', T.text)
				setp(d, 'Font', T.font)
			end
		end
	end
	if d:IsA('ImageLabel') or d:IsA('ImageButton') then
		if isGold(orig(d, 'ImageColor3')) then
			setp(d, 'ImageColor3', T.accent)
		end
	end
	local bt = orig(d, 'BackgroundTransparency')
	local bc = orig(d, 'BackgroundColor3')
	if type(bt) == 'number' and bt < 0.95 and typeof(bc) == 'Color3' then
		local s, l = satLum(bc)
		if isGold(bc) then
			setp(d, 'BackgroundColor3', T.accent)
		elseif s < 0.1 and l < 0.35 then
			local isBtn = d:IsA('GuiButton') or d:IsA('TextBox')
			setp(d, 'BackgroundColor3', isBtn and T.button or T.panel)
			-- Glass themes: let nested dark boxes go see-through too.
			if T.panelT > 0.3 then
				local want = isBtn and (T.buttonT or T.panelT) or T.panelT
				setp(d, 'BackgroundTransparency', math.clamp(math.max(bt, want), 0, 0.9))
			end
		end
	end
end

-- Walks a tree in batches (big lists like Quests/Players stay hitch-free).
local function styleTree(root, T, hud)
	if not root then
		return
	end
	local skip = hud and HUD_SKIP or SKIP_NAMES
	local list = {}
	local function walk(n)
		for _, ch in ipairs(n:GetChildren()) do
			if not skip[ch.Name] then
				list[#list + 1] = ch
				walk(ch)
			end
		end
	end
	walk(root)
	local token = S.applyToken
	task.spawn(function()
		for i, d in ipairs(list) do
			if S.theme == nil or S.applyToken ~= token then
				return
			end
			if d.Parent then
				styleNode(d, T, hud)
			end
			if i % 200 == 0 then
				task.wait()
			end
		end
	end)
end

local function playerUI()
	local inv = inventoryRoot()
	return inv and inv.Parent
end

local function styleOtherPages(inv, T, only)
	local tf = inv:FindFirstChild('TabFrames')
	if not tf then
		return
	end
	for _, page in ipairs(tf:GetChildren()) do
		if page.Name ~= 'InventoryFrame' and page:IsA('GuiObject') and (not only or page == only) then
			styleTree(page, T)
		end
	end
end

local function styleHud(T)
	local pui = playerUI()
	if not pui then
		return
	end
	for _, name in ipairs({ 'HUD', 'HotkeyBar', 'MenuButton' }) do
		styleTree(pui:FindFirstChild(name), T, true)
	end
	-- Wave defense / dungeon counters (wave #, timer, mobs left, wave bar, vel earned).
	local pop = pui:FindFirstChild('Popups')
	if pop then
		for _, name in ipairs({ 'WaveDefense', 'Dungeon' }) do
			styleTree(pop:FindFirstChild(name), T, true)
		end
	end
	-- Boss health bars (the template too, so new bars come out themed).
	styleTree(pui:FindFirstChild('BossHealthBars'), T, true)
end

-- Player health / stamina fill. The green/blue is baked into the bar textures, so a tint
-- alone goes muddy. Instead: theme colour as the bar's background, and the original
-- texture drawn black at low opacity on top so its shading/gloss is kept.
-- Redbar (the red "damage just taken" trail) stays red.
local function styleBars(T)
	local pui = playerUI()
	local hud = pui and pui:FindFirstChild('HUD')
	if not hud then
		return
	end
	local fills = {
		Healthbar = T.accent,
		StaminaBar = T.accent:Lerp(T.text, 0.45),
	}
	local function grad(col)
		return ColorSequence.new(col:Lerp(Color3.new(1, 1, 1), 0.45), col)
	end
	for name, col in pairs(fills) do
		local f = hud:FindFirstChild(name)
		local bar = f and f:FindFirstChild('Bar')
		if bar and bar:IsA('ImageLabel') then
			-- White base + gradient = same light-to-accent look as the other themed bits.
			setp(bar, 'BackgroundColor3', Color3.new(1, 1, 1))
			setp(bar, 'BackgroundTransparency', 0)
			setp(bar, 'ImageColor3', Color3.new(0, 0, 0))
			setp(bar, 'ImageTransparency', 0.72)
			addChild(bar, 'UIGradient', 'Grad', { Color = grad(col), Rotation = 0 })
		end
	end
	-- Rims: the game rewrites their ImageColor3 every frame, but a UIGradient multiplies
	-- on top of whatever it writes, so it sticks. Two instances total, removed on Default.
	local hbf0 = hud:FindFirstChild('HealthBarFrame')
	if hbf0 then
		for _, rn in ipairs({ 'HealthRim', 'StaminaRim' }) do
			local rim = hbf0:FindFirstChild(rn)
			if rim and rim:IsA('ImageLabel') then
				addChild(rim, 'UIGradient', 'Grad', { Color = grad(T.accent), Rotation = 0 })
			end
		end
	end
	local hbf = hud:FindFirstChild('HealthBarFrame')
	local pct = hbf and hbf:FindFirstChild('Percent')
	if pct and pct:IsA('TextLabel') then
		setp(pct, 'TextColor3', T.text)
		setp(pct, 'Font', T.font)
	end
end

-- Every other window. Rarity / red / green colours are left alone by styleNode.
local WINDOWS = {
	'BoostShop', 'CrystalForge', 'Shop', 'RightNotice', 'Chat', 'Upgrade', 'Trade',
	'Dismantle', 'Notification', 'Party', 'Guild', 'PartyInvite', 'Spectate',
}
local POPUP_WINDOWS = { 'ReviveFrame', 'AmountSelection', 'EnemyDialogue', 'EnemyAlert' }
-- Templates the game clones (notifications, trade rows, shop rows, chat lines...): themed
-- at the source, so every new copy is born themed and the game sizes it with our font.
local TEMPLATES = {
	'Notification', 'TradeTemplate', 'ShopTemplate', 'NameList', 'ServerEntry',
	'ServerFilter', 'OptionsTemplate', 'ChatTemplate', 'ChatJustText', 'ChatTagTemplate',
	'ChatItemTemplate', 'ChatImageAndTextTemplate', 'ChatFriendJoinedTemplate',
	'ChatCurrencyTemplate', 'StatEntry', 'StatDescription', 'StatNoteTemplate',
}
local function windowList(pui)
	local out = {}
	for _, n in ipairs(WINDOWS) do
		out[#out + 1] = pui:FindFirstChild(n)
	end
	local pop = pui:FindFirstChild('Popups')
	if pop then
		for _, n in ipairs(POPUP_WINDOWS) do
			out[#out + 1] = pop:FindFirstChild(n)
		end
	end
	local pg = pui:FindFirstAncestorOfClass('PlayerGui')
	if pg then
		out[#out + 1] = pg:FindFirstChild('NPCDialogue')
		out[#out + 1] = pg:FindFirstChild('Blessings')
	end
	return out
end

local function styleWindows(T)
	local pui = playerUI()
	if not pui then
		return
	end
	for _, w in ipairs(windowList(pui)) do
		if w:IsA('GuiObject') then
			styleNode(w, T)
		end
		styleTree(w, T)
	end
	local tpl = pui:FindFirstChild('Templates')
	if tpl then
		for _, n in ipairs(TEMPLATES) do
			local t = tpl:FindFirstChild(n)
			if t then
				if t:IsA('GuiObject') then
					styleNode(t, T)
				end
				styleTree(t, T)
			end
		end
	end
end

local function applyAll()
	local T = S.theme and THEMES[S.theme]
	if not T then
		return
	end
	local inv = inventoryRoot()
	if not inv then
		return
	end
	S.applyToken = (S.applyToken or 0) + 1
	styleWindow(inv, T)
	styleButtons(inv, T)
	styleOtherPages(inv, T)
	styleHud(T)
	styleBars(T)
	styleWindows(T)
	for _, slot in ipairs((equipSlots(inv))) do
		styleSlot(slot, T)
	end
	local _, list = slotList(inv)
	if list then
		-- Big inventories have 1,500+ slots: style them in batches so the game never hitches.
		local token = S.applyToken
		local kids = list:GetChildren()
		task.spawn(function()
			for i, slot in ipairs(kids) do
				if S.applyToken ~= token or S.theme == nil then
					return
				end
				styleSlot(slot, T)
				if i % 150 == 0 then
					task.wait()
				end
			end
		end)
	end
end

local function hook()
	disconnectAll()
	local inv = inventoryRoot()
	if not inv then
		-- UI not built yet: wait for it once.
		task.spawn(function()
			local pg = LocalPlayer:WaitForChild('PlayerGui', 60)
			local c = pg and pg:WaitForChild('CardinalUI', 60)
			local p = c and c:WaitForChild('PlayerUI', 60)
			local i = p and p:WaitForChild('MainFrame', 60)
			if i and S.theme then
				hook()
			end
		end)
		return
	end
	local _, list = slotList(inv)
	if list then
		-- The game rebuilds the slots on open / sort / search: style each new one.
		S.conns[#S.conns + 1] = list.ChildAdded:Connect(function(slot)
			if not S.theme then
				return
			end
			task.defer(function()
				local T = THEMES[S.theme]
				if T then
					styleSlot(slot, T)
				end
			end)
		end)
	end
	S.conns[#S.conns + 1] = inv:GetPropertyChangedSignal('Visible'):Connect(function()
		if inv.Visible and S.theme then
			task.defer(applyAll)
		end
	end)
	-- Other tabs fill in lazily: restyle a page each time it is shown (one signal per page).
	local tf = inv:FindFirstChild('TabFrames')
	if tf then
		for _, page in ipairs(tf:GetChildren()) do
			if page.Name ~= 'InventoryFrame' and page:IsA('GuiObject') then
				S.conns[#S.conns + 1] = page:GetPropertyChangedSignal('Visible'):Connect(function()
					if page.Visible and S.theme then
						task.delay(0.15, function()
							local T = THEMES[S.theme or '']
							if T then
								styleOtherPages(inv, T, page)
							end
						end)
					end
				end)
			end
		end
	end
	-- Wave / dungeon panels show up mid-game: restyle when they do.
	local pop = inv.Parent and inv.Parent:FindFirstChild('Popups')
	if pop then
		for _, name in ipairs({ 'WaveDefense', 'Dungeon' }) do
			local f = pop:FindFirstChild(name)
			if f and f:IsA('GuiObject') then
				S.conns[#S.conns + 1] = f:GetPropertyChangedSignal('Visible'):Connect(function()
					if f.Visible and S.theme then
						task.delay(0.2, function()
							local T = THEMES[S.theme or '']
							if T then
								styleTree(f, T, true)
							end
						end)
					end
				end)
			end
		end
	end
	-- Other windows: restyle when opened (they often fill their lists on open).
	local pui = inv.Parent
	if pui then
		for _, w in ipairs(windowList(pui)) do
			local isGui = w:IsA('GuiObject')
			local sig = isGui and w:GetPropertyChangedSignal('Visible')
				or (w:IsA('LayerCollector') and w:GetPropertyChangedSignal('Enabled'))
			if sig then
				S.conns[#S.conns + 1] = sig:Connect(function()
					local shown = isGui and w.Visible or (not isGui and w.Enabled)
					if shown and S.theme then
						task.delay(0.15, function()
							local T = THEMES[S.theme or '']
							if T then
								styleTree(w, T)
							end
						end)
					end
				end)
			end
		end
		-- New boss bars are cloned in during fights.
		local bhb = pui:FindFirstChild('BossHealthBars')
		if bhb then
			S.conns[#S.conns + 1] = bhb.ChildAdded:Connect(function(ch)
				task.defer(function()
					local T = THEMES[S.theme or '']
					if T then
						styleTree(ch, T, true)
					end
				end)
			end)
		end
	end
	-- Whole UI rebuilt (respawn / reset): hook the new one.
	S.conns[#S.conns + 1] = inv.AncestryChanged:Connect(function(_, parent)
		if not parent and S.theme then
			task.delay(1, function()
				if S.theme then
					hook()
					applyAll()
				end
				pcall(buildPicker)
			end)
		end
	end)
	applyAll()
end

local function setTheme(name)
	name = tostring(name or 'Default')
	restoreAll()
	disconnectAll()
	if name == 'Default' or not THEMES[name] then
		S.theme = nil
		return 'Default'
	end
	S.theme = name
	hook()
	return name
end

local SAVE_PATH = 'PlayerTools/inv_theme'
local function saveTheme(name)
	if type(writefile) ~= 'function' then
		return
	end
	pcall(function()
		if type(isfolder) == 'function' and type(makefolder) == 'function' and not isfolder('PlayerTools') then
			makefolder('PlayerTools')
		end
		writefile(SAVE_PATH, tostring(name))
	end)
end

-- ── theme button inside the game's inventory window ───────────────────────
-- A small "Theme" button above the window's top-right corner; click it for the list.
local PICKER = 'SB2ThemePicker'
buildPicker = function()
	local inv = inventoryRoot()
	local pg = LocalPlayer and LocalPlayer:FindFirstChild('PlayerGui')
	if not inv or not pg then
		return
	end
	local old = pg:FindFirstChild(PICKER)
	if old then
		old:Destroy()
	end
	-- Own ScreenGui: nothing is added inside the game's menu.
	local gui = Instance.new('ScreenGui')
	gui.Name = PICKER
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 50
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = pg
	local holder = Instance.new('Frame')
	holder.Name = 'Holder'
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(130, 26)
	holder.AnchorPoint = Vector2.new(1, 1)
	holder.ZIndex = 20
	holder.Parent = gui
	-- Follow the menu window: sit just above its top-right corner (above the tab bar).
	local function follow()
		local ok = pcall(function()
			local p, sz = inv.AbsolutePosition, inv.AbsoluteSize
			local inset = game:GetService('GuiService'):GetGuiInset()
			holder.Position = UDim2.fromOffset(p.X + sz.X, p.Y + inset.Y - sz.Y * 0.1 - 6)
			holder.Visible = inv.Visible
		end)
		if not ok then
			holder.Visible = false
		end
	end
	follow()
	for _, prop in ipairs({ 'AbsolutePosition', 'AbsoluteSize', 'Visible' }) do
		S.pickerConns = S.pickerConns or {}
		S.pickerConns[#S.pickerConns + 1] = inv:GetPropertyChangedSignal(prop):Connect(follow)
	end

	local btn = Instance.new('TextButton')
	btn.Name = 'Button'
	btn.Size = UDim2.fromScale(1, 1)
	btn.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
	btn.BackgroundTransparency = 0.15
	btn.TextColor3 = Color3.fromRGB(240, 240, 240)
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 13
	btn.AutoButtonColor = true
	btn.ZIndex = 21
	btn.Parent = holder
	Instance.new('UICorner', btn).CornerRadius = UDim.new(0, 6)
	local bs = Instance.new('UIStroke', btn)
	bs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	bs.Color = Color3.fromRGB(211, 160, 57)
	bs.Thickness = 1

	-- Scrolls once there are more themes than fit (max ~10 rows tall).
	local list = Instance.new('ScrollingFrame')
	list.Name = 'List'
	list.Visible = false
	list.BackgroundColor3 = Color3.fromRGB(16, 16, 20)
	list.BackgroundTransparency = 0.05
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 4
	list.CanvasSize = UDim2.fromOffset(0, #NAMES * 26 + 8)
	list.Size = UDim2.fromOffset(130, math.min(#NAMES, 10) * 26 + 8)
	list.Position = UDim2.new(0, 0, 1, 4)
	list.ZIndex = 30
	list.Parent = holder
	Instance.new('UICorner', list).CornerRadius = UDim.new(0, 6)
	local ls = Instance.new('UIStroke', list)
	ls.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	ls.Color = Color3.fromRGB(211, 160, 57)
	ls.Thickness = 1
	local pad = Instance.new('UIPadding', list)
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingLeft = UDim.new(0, 4)
	pad.PaddingRight = UDim.new(0, 4)
	local layout = Instance.new('UIListLayout', list)
	layout.SortOrder = Enum.SortOrder.LayoutOrder

	local function refresh()
		local cur = S.theme or 'Default'
		btn.Text = 'Theme: ' .. cur
		local T = THEMES[cur]
		bs.Color = T and T.accent or Color3.fromRGB(211, 160, 57)
		ls.Color = bs.Color
		for _, b in ipairs(list:GetChildren()) do
			if b:IsA('TextButton') then
				local on = b.Name == cur
				b.TextColor3 = on and bs.Color or Color3.fromRGB(225, 225, 225)
				b.Font = on and Enum.Font.GothamBold or Enum.Font.Gotham
			end
		end
	end
	for i, name in ipairs(NAMES) do
		local b = Instance.new('TextButton')
		b.Name = name
		b.LayoutOrder = i
		b.Size = UDim2.new(1, 0, 0, 26)
		b.BackgroundTransparency = 1
		b.Text = name
		b.TextSize = 13
		b.TextXAlignment = Enum.TextXAlignment.Left
		b.ZIndex = 31
		b.Parent = list
		local T = THEMES[name]
		if T then
			local dot = Instance.new('Frame')
			dot.Name = 'Swatch'
			dot.Size = UDim2.fromOffset(10, 10)
			dot.AnchorPoint = Vector2.new(1, 0.5)
			dot.Position = UDim2.new(1, -4, 0.5, 0)
			dot.BackgroundColor3 = T.accent
			dot.ZIndex = 32
			dot.Parent = b
			Instance.new('UICorner', dot).CornerRadius = UDim.new(1, 0)
		end
		b.MouseButton1Click:Connect(function()
			list.Visible = false
			local applied = g.SB2SetInventoryTheme(name)
			saveTheme(applied)
			refresh()
		end)
	end
	btn.MouseButton1Click:Connect(function()
		list.Visible = not list.Visible
	end)
	S.pickerRefresh = refresh
	refresh()
end

local function setThemeAndPicker(name)
	local applied = setTheme(name)
	local pg = LocalPlayer and LocalPlayer:FindFirstChild('PlayerGui')
	if pg and not pg:FindFirstChild(PICKER) then
		pcall(buildPicker)
	end
	if type(S.pickerRefresh) == 'function' then
		pcall(S.pickerRefresh)
	end
	return applied
end

g.SB2SetInventoryTheme = setThemeAndPicker
g.SB2InventoryThemeStop = function()
	S.theme = nil
	disconnectAll()
	restoreAll()
	for _, c in ipairs(S.pickerConns or {}) do
		pcall(function()
			c:Disconnect()
		end)
	end
	S.pickerConns = {}
	local pg = LocalPlayer and LocalPlayer:FindFirstChild('PlayerGui')
	local p = pg and pg:FindFirstChild(PICKER)
	if p then
		p:Destroy()
	end
end

-- Show the button straight away (and again if the UI is rebuilt).
task.spawn(function()
	local pg = LocalPlayer:WaitForChild('PlayerGui', 60)
	local c = pg and pg:WaitForChild('CardinalUI', 60)
	local p = c and c:WaitForChild('PlayerUI', 60)
	local i = p and p:WaitForChild('MainFrame', 60)
	if i and not pg:FindFirstChild(PICKER) then
		pcall(buildPicker)
	end
end)

return setThemeAndPicker
