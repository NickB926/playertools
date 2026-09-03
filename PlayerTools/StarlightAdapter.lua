--[[
	PlayerTools/StarlightAdapter.lua

	Obsidian-compatible library facade backed by the Starlight Interface Suite.

	PlayerTools.lua is never modified. The launcher (PlayerTools_Starlight.lua)
	compiles this chunk and hands the resulting factory to PlayerTools in place of
	Obsidian's Library.lua, so all 14k lines of PlayerTools logic run unchanged.

	Contract this file must honour (everything PlayerTools / Obsidian's SaveManager
	actually touch):

	  Library.CreateWindow / Notify / Toggle / GetCustomIcon / GetTextBounds
	  Library.ScreenGui / Options / Toggles / Tabs / Window
	  Library.MinSize / OriginalMinSize / DPIScale / ShowCustomCursor
	  Library.Unloaded / Toggled / Open / ToggleKeybind / KeybindFrame

	  Window:AddTab(name, icon) / Window:AddDialog(idx, info)
	  Tab:AddLeftGroupbox / AddRightGroupbox / AddGroupbox{Side,Name} / Show
	  Groupbox:AddToggle / AddButton / AddSlider / AddDropdown / AddInput
	           / AddLabel / AddDivider
	  Label:AddKeyPicker

	  element.Value / .Type / :SetValue / :OnChanged / :SetText / :SetValues
	           / :SetVisible / :SetDisabled
]]

local Starlight = getgenv().SB2StarlightLib
if type(Starlight) ~= 'table' or type(Starlight.CreateWindow) ~= 'function' then
	error('[StarlightAdapter] getgenv().SB2StarlightLib missing — run PlayerTools_Starlight.lua')
end

local Players = game:GetService('Players')
local TextService = game:GetService('TextService')

-- Optional lucide/material name -> asset id resolver installed by the launcher.
local resolveIcon = getgenv().SB2StarlightIconResolver

-- Starlight toggle style: 1 = checkbox (Obsidian-like), 2 = switch.
local TOGGLE_STYLE = tonumber(getgenv().SB2StarlightToggleStyle) or 2
-- Starlight button style: 1 = filled/primary, 2 = secondary.
local BUTTON_STYLE = tonumber(getgenv().SB2StarlightButtonStyle) or 2

-- Starlight layout facts (measured, and fixed in its UI model):
--   * every element's Header label is a hard-coded Size = {0, 315}; it does not
--     scale down, so a narrower column just clips the end of the text
--   * a column loses 16px to padding before an element's Header starts
--     (groupbox PART_Content 5+5, element 3+3)
--   * columns sit in a horizontal UIListLayout with a 10px gap
--   * window chrome (tab rail + page inset) costs 230px of the window width
--
-- A column therefore has to be >= 315 + 16 = 331 wide or labels are cut off,
-- which is well above the 300 that Starlight's own UISizeConstraint enforces.
local ELEMENT_HEADER_WIDTH = 315
local GROUPBOX_INSET_X = 16
local COLUMN_MIN_WIDTH = ELEMENT_HEADER_WIDTH + GROUPBOX_INSET_X + 5
local COLUMN_GAP = 10
local WINDOW_CHROME_X = 230
local WINDOW_MARGIN = 10

local function widthForColumns(columns)
	return COLUMN_MIN_WIDTH * columns
		+ COLUMN_GAP * (columns - 1)
		+ WINDOW_CHROME_X
		+ WINDOW_MARGIN
end

-- Decided in CreateWindow: drops to a single column on screens too narrow for
-- two, so the menu is never cut off.
local columnCount = 2

local Library = {
	Toggles = {},
	Options = {},
	Tabs = {},

	ScreenGui = nil,
	Window = nil,

	MinSize = Vector2.new(240, 180),
	OriginalMinSize = Vector2.new(240, 180),
	DPIScale = 1,

	ShowCustomCursor = false,
	Unloaded = false,
	Toggled = true,
	Open = true,
	ToggleKeybind = nil,
	KeybindFrame = nil,

	NotifySound = false,
	Backend = 'Starlight',
}

local Toggles, Options = Library.Toggles, Library.Options

--============================================================================
-- helpers
--============================================================================

local function safe(fn, ...)
	if type(fn) ~= 'function' then
		return false
	end
	local ok, err = pcall(fn, ...)
	if not ok then
		warn('[StarlightAdapter] ' .. tostring(err))
	end
	return ok
end

local function callSoon(fn, value)
	if type(fn) ~= 'function' then
		return
	end
	local ok, err = pcall(fn, value)
	if not ok then
		warn('[StarlightAdapter] callback: ' .. tostring(err))
	end
end

local function iconFor(name)
	if name == nil or name == '' then
		return nil
	end
	if type(name) == 'number' then
		return name
	end
	if type(name) == 'string' then
		local id = name:match('^rbxassetid://(%d+)$') or name:match('^(%d+)$')
		if id then
			return tonumber(id)
		end
		if type(resolveIcon) == 'function' then
			local ok, resolved = pcall(resolveIcon, name)
			if ok and type(resolved) == 'number' then
				return resolved
			end
		end
	end
	return nil
end

-- Obsidian lets Values hold arbitrary objects (Player instances for the
-- SpecialType='Player' dropdown). Starlight only renders strings, so keep a
-- display<->real map per dropdown.
local function displayOf(value)
	if typeof(value) == 'Instance' then
		return tostring(value.Name)
	end
	return tostring(value)
end

--============================================================================
-- shared element base: Obsidian's Value / SetValue / OnChanged contract
--============================================================================

local function attachChanged(element)
	element.Changed = nil
	element.Callback = element.Callback or nil

	function element:OnChanged(fn)
		-- Obsidian stores one handler and does not fire it immediately.
		self.Changed = fn
		return self
	end

	function element:RunChanged()
		callSoon(self.Callback, self.Value)
		callSoon(self.Changed, self.Value)
	end

	function element:SetVisible(visible)
		local inst = self.SLInstance and self.SLInstance.Instance
		if typeof(inst) == 'Instance' then
			pcall(function()
				inst.Visible = visible and true or false
			end)
		end
		self.Visible = visible and true or false
		return self
	end

	function element:SetDisabled(disabled)
		self.Disabled = disabled and true or false
		local sl = self.SLInstance
		if sl then
			if self.Disabled and type(sl.Lock) == 'function' then
				safe(sl.Lock, sl, 'Disabled')
			elseif not self.Disabled and type(sl.Unlock) == 'function' then
				safe(sl.Unlock, sl)
			end
		end
		return self
	end

	-- No-ops PlayerTools / SaveManager may probe.
	function element:SetTooltip() end
	function element:Destroy()
		local sl = self.SLInstance
		if sl and type(sl.Destroy) == 'function' then
			safe(sl.Destroy, sl)
		end
	end

	return element
end

--============================================================================
-- Groupbox
--============================================================================

local Groupbox = {}
Groupbox.__index = Groupbox

local function newGroupbox(slGroupbox, tab)
	return setmetatable({
		SLGroupbox = slGroupbox,
		Tab = tab,
		Elements = {},
		Visible = true,
		Collapsed = false,
	}, Groupbox)
end

function Groupbox:_index(prefix)
	self._n = (self._n or 0) + 1
	return ('%s_%s_%d'):format(prefix, tostring(self.Name or 'box'), self._n)
end

function Groupbox:Resize() end
function Groupbox:SetVisible() end

-- Obsidian's SaveManager persists groupbox collapse state.
function Groupbox:SetCollapsed(collapsed)
	self.Collapsed = collapsed and true or false
	return self
end

---------------------------------------------------------------------- Toggle
function Groupbox:AddToggle(idx, info)
	info = info or {}
	local element = attachChanged({
		Type = 'Toggle',
		Idx = idx,
		Value = info.Default and true or false,
		Disabled = info.Disabled and true or false,
		Callback = info.Callback,
		Addons = {},
		Risky = info.Risky,
	})

	local applying = false

	local slToggle = self.SLGroupbox:CreateToggle({
		Name = tostring(info.Text or idx),
		Icon = iconFor(info.Icon),
		Tooltip = info.Tooltip,
		CurrentValue = element.Value,
		Style = TOGGLE_STYLE,
		IgnoreConfig = true,
		Callback = function(value)
			element.Value = value and true or false
			if applying then
				return
			end
			element:RunChanged()
		end,
	}, tostring(idx))

	element.SLInstance = slToggle

	function element:SetValue(value)
		if self.Disabled then
			return
		end
		value = value and true or false
		self.Value = value

		applying = true
		safe(function()
			slToggle:Set({ CurrentValue = value })
		end)
		applying = false

		for _, addon in pairs(self.Addons) do
			if addon.Type == 'KeyPicker' and addon.SyncToggleState then
				addon.Toggled = value
			end
		end

		self:RunChanged()
		return self
	end

	function element:SetText(text)
		safe(function()
			slToggle:Set({ Name = tostring(text) })
		end)
		return self
	end

	Toggles[idx] = element
	self.Elements[idx] = element
	return element
end

---------------------------------------------------------------------- Button
function Groupbox:AddButton(a, b)
	local box = self
	local info
	if type(a) == 'table' then
		info = a
	else
		info = { Text = a, Func = b }
	end

	local element = {
		Type = 'Button',
		Text = info.Text,
		Func = info.Func or info.Callback,
	}

	local idx = self:_index('BTN')
	local slButton = self.SLGroupbox:CreateButton({
		Name = tostring(info.Text or 'Button'),
		Icon = iconFor(info.Icon),
		Tooltip = info.Tooltip,
		Style = info.Style or BUTTON_STYLE,
		IgnoreConfig = true,
		Callback = function()
			if element.Disabled then
				return
			end
			callSoon(element.Func)
		end,
	}, idx)

	element.SLInstance = slButton

	function element:SetText(text)
		self.Text = text
		safe(function()
			slButton:Set({ Name = tostring(text) })
		end)
		return self
	end

	function element:SetDisabled(disabled)
		self.Disabled = disabled and true or false
		if self.Disabled then
			safe(function()
				slButton:Lock('Disabled')
			end)
		else
			safe(function()
				slButton:Unlock()
			end)
		end
		return self
	end

	function element:SetVisible(visible)
		local inst = slButton and slButton.Instance
		if typeof(inst) == 'Instance' then
			pcall(function()
				inst.Visible = visible and true or false
			end)
		end
		return self
	end

	-- Obsidian supports chained sub-buttons.
	function element:AddButton(sa, sb)
		return box:AddButton(sa, sb)
	end

	return element
end

---------------------------------------------------------------------- Label
function Groupbox:AddLabel(text, doesWrap)
	local element = {
		Type = 'Label',
		Text = text,
	}

	local idx = self:_index('LBL')
	local slLabel = self.SLGroupbox:CreateLabel({
		Name = tostring(text or ''),
		IgnoreConfig = true,
	}, idx)

	element.SLInstance = slLabel
	element.SLIndex = idx
	element.Box = self

	function element:SetText(newText)
		self.Text = newText
		safe(function()
			slLabel:Set({ Name = tostring(newText) })
		end)
		return self
	end

	function element:SetVisible(visible)
		local inst = slLabel and slLabel.Instance
		if typeof(inst) == 'Instance' then
			pcall(function()
				inst.Visible = visible and true or false
			end)
		end
		return self
	end

	function element:AddKeyPicker(kpIdx, kpInfo)
		return Groupbox._addKeyPicker(self.Box, element, kpIdx, kpInfo)
	end

	function element:AddDropdown(ddIdx, ddInfo)
		return Groupbox.AddDropdown(self.Box, ddIdx, ddInfo, element)
	end

	return element
end

---------------------------------------------------------------------- Divider
function Groupbox:AddDivider()
	local element = { Type = 'Divider' }
	local sl
	safe(function()
		sl = self.SLGroupbox:CreateDivider()
	end)
	element.SLInstance = sl
	return element
end

---------------------------------------------------------------------- Slider
function Groupbox:AddSlider(idx, info)
	info = info or {}
	local minValue = tonumber(info.Min) or 0
	local maxValue = tonumber(info.Max) or 100
	local rounding = tonumber(info.Rounding) or 0
	local increment = tonumber(info.Increment)
	if not increment then
		increment = rounding > 0 and (10 ^ -rounding) or 1
	end

	local element = attachChanged({
		Type = 'Slider',
		Idx = idx,
		Value = math.clamp(tonumber(info.Default) or minValue, minValue, maxValue),
		Min = minValue,
		Max = maxValue,
		Rounding = rounding,
		Callback = info.Callback,
		Disabled = info.Disabled and true or false,
	})

	local applying = false

	local slSlider = self.SLGroupbox:CreateSlider({
		Name = tostring(info.Text or idx),
		Icon = iconFor(info.Icon),
		Tooltip = info.Tooltip,
		Range = { minValue, maxValue },
		CurrentValue = element.Value,
		Increment = increment,
		Suffix = info.Suffix,
		IgnoreConfig = true,
		Callback = function(value)
			value = tonumber(value)
			if not value then
				return
			end
			element.Value = value
			if applying then
				return
			end
			element:RunChanged()
		end,
	}, tostring(idx))

	element.SLInstance = slSlider

	function element:SetValue(raw)
		if self.Disabled then
			return
		end
		local num = tonumber(raw)
		if not num then
			return
		end
		num = math.clamp(num, self.Min, self.Max)
		if num == self.Value then
			return
		end
		self.Value = num

		applying = true
		safe(function()
			slSlider:Set({ CurrentValue = num })
		end)
		applying = false

		self:RunChanged()
		return self
	end

	function element:SetMin(value)
		self.Min = tonumber(value) or self.Min
		safe(function()
			slSlider:Set({ Range = { self.Min, self.Max } })
		end)
		return self
	end

	function element:SetMax(value)
		self.Max = tonumber(value) or self.Max
		safe(function()
			slSlider:Set({ Range = { self.Min, self.Max } })
		end)
		return self
	end

	function element:SetText(text)
		safe(function()
			slSlider:Set({ Name = tostring(text) })
		end)
		return self
	end

	Options[idx] = element
	self.Elements[idx] = element
	return element
end

---------------------------------------------------------------------- Input
function Groupbox:AddInput(idx, info)
	info = info or {}

	local element = attachChanged({
		Type = 'Input',
		Idx = idx,
		Value = tostring(info.Default or ''),
		Numeric = info.Numeric and true or false,
		AllowEmpty = info.AllowEmpty ~= false,
		EmptyReset = info.EmptyReset or '',
		Callback = info.Callback,
	})

	local applying = false

	local slInput = self.SLGroupbox:CreateInput({
		Name = tostring(info.Text or idx),
		Icon = iconFor(info.Icon),
		Tooltip = info.Tooltip,
		CurrentValue = element.Value,
		PlaceholderText = info.Placeholder,
		Numeric = element.Numeric,
		Enter = info.Finished and true or false,
		MaxCharacters = tonumber(info.MaxLength),
		RemoveTextOnFocus = info.ClearTextOnFocus and true or false,
		IgnoreConfig = true,
		Callback = function(text)
			text = tostring(text or '')
			element.Value = text
			if applying then
				return
			end
			element:RunChanged()
		end,
	}, tostring(idx))

	element.SLInstance = slInput

	function element:SetValue(text)
		text = tostring(text or '')
		if not self.AllowEmpty and text:gsub('%s', '') == '' then
			text = self.EmptyReset
		end
		if self.Numeric and #text > 0 and not tonumber(text) then
			return
		end
		self.Value = text

		applying = true
		safe(function()
			slInput:Set({ CurrentValue = text })
		end)
		applying = false

		self:RunChanged()
		return self
	end

	function element:SetText(label)
		safe(function()
			slInput:Set({ Name = tostring(label) })
		end)
		return self
	end

	Options[idx] = element
	self.Elements[idx] = element
	return element
end

---------------------------------------------------------------------- Dropdown
-- `host` is set when the dropdown hangs off a Label (Starlight's native shape).
function Groupbox:AddDropdown(idx, info, host)
	info = info or {}
	local multi = info.Multi and true or false

	local element = attachChanged({
		Type = 'Dropdown',
		Idx = idx,
		Multi = multi,
		Values = {},
		Value = multi and {} or nil,
		AllowNull = info.AllowNull ~= false,
		Callback = info.Callback,
		SpecialType = info.SpecialType,
	})

	-- display string -> real value
	local lookup = {}
	local applying = false

	local function rebuildLookup(values)
		lookup = {}
		local displays = {}
		for _, value in ipairs(values or {}) do
			local key = displayOf(value)
			-- Keep names unique so selection stays unambiguous.
			if lookup[key] ~= nil then
				local n = 2
				while lookup[key .. ' (' .. n .. ')'] ~= nil do
					n += 1
				end
				key = key .. ' (' .. n .. ')'
			end
			lookup[key] = value
			displays[#displays + 1] = key
		end
		return displays
	end

	local function decode(selection)
		if multi then
			local out = {}
			if type(selection) == 'table' then
				for _, key in ipairs(selection) do
					local real = lookup[key]
					if real ~= nil then
						out[real] = true
					end
				end
			end
			return out
		end
		if type(selection) == 'table' then
			selection = selection[1]
		end
		if selection == nil then
			return nil
		end
		local real = lookup[selection]
		if real ~= nil then
			return real
		end
		return nil
	end

	local function encode(value)
		if multi then
			local out = {}
			if type(value) == 'table' then
				for real, active in pairs(value) do
					if active then
						for key, mapped in pairs(lookup) do
							if mapped == real then
								out[#out + 1] = key
								break
							end
						end
					end
				end
			end
			return out
		end
		if value == nil then
			return nil
		end
		for key, mapped in pairs(lookup) do
			if mapped == value then
				return { key }
			end
		end
		return nil
	end

	-- Resolve Obsidian's Default (index or literal value).
	local initialValues = info.Values or {}
	local displays = rebuildLookup(initialValues)
	element.Values = initialValues

	local defaultValue
	if info.Default ~= nil then
		if type(info.Default) == 'number' and initialValues[info.Default] ~= nil then
			defaultValue = initialValues[info.Default]
		else
			for _, value in ipairs(initialValues) do
				if value == info.Default or displayOf(value) == displayOf(info.Default) then
					defaultValue = value
					break
				end
			end
		end
	end
	if multi then
		element.Value = {}
		if defaultValue ~= nil then
			element.Value[defaultValue] = true
		end
	else
		element.Value = defaultValue
	end

	local slSettings = {
		Options = displays,
		CurrentOption = encode(element.Value),
		MultipleOptions = multi,
		Placeholder = info.Placeholder,
		Tooltip = info.Tooltip,
		IgnoreConfig = true,
		Callback = function(selection)
			element.Value = decode(selection)
			if applying then
				return
			end
			element:RunChanged()
		end,
	}

	-- Starlight only exposes dropdowns as a nested element, so give it a label
	-- carrier when PlayerTools asked for a standalone dropdown.
	local carrier = host
	if not carrier then
		carrier = self:AddLabel(tostring(info.Text or idx))
	elseif info.Text then
		carrier:SetText(tostring(info.Text))
	end

	local slDropdown
	safe(function()
		slDropdown = carrier.SLInstance:AddDropdown(slSettings, tostring(idx))
	end)

	element.SLInstance = slDropdown
	element.Carrier = carrier

	local function push()
		applying = true
		safe(function()
			slDropdown:Set({
				Options = rebuildLookup(element.Values),
				CurrentOption = encode(element.Value),
			})
		end)
		applying = false
	end

	function element:SetValues(values)
		self.Values = values or {}
		rebuildLookup(self.Values)

		-- Drop selections that no longer exist.
		if multi then
			for real in pairs(self.Value or {}) do
				local found = false
				for _, value in ipairs(self.Values) do
					if value == real then
						found = true
						break
					end
				end
				if not found then
					self.Value[real] = nil
				end
			end
		elseif self.Value ~= nil then
			local found = false
			for _, value in ipairs(self.Values) do
				if value == self.Value then
					found = true
					break
				end
			end
			if not found then
				self.Value = nil
			end
		end

		push()
		return self
	end

	function element:SetValue(value)
		if multi then
			local out = {}
			if type(value) == 'table' then
				for key, active in pairs(value) do
					if type(active) == 'boolean' then
						if active then
							out[key] = true
						end
					else
						out[active] = true
					end
				end
			end
			self.Value = out
		else
			self.Value = value
		end
		push()
		self:RunChanged()
		return self
	end

	function element:SetText(text)
		if carrier and carrier.SetText then
			carrier:SetText(tostring(text))
		end
		return self
	end

	function element:SetVisible(visible)
		if carrier and carrier.SetVisible then
			carrier:SetVisible(visible)
		end
		return self
	end

	Options[idx] = element
	self.Elements[idx] = element
	return element
end

---------------------------------------------------------------------- KeyPicker
function Groupbox._addKeyPicker(box, parent, idx, info)
	info = info or {}

	local element = attachChanged({
		Type = 'KeyPicker',
		Idx = idx,
		Value = tostring(info.Default or ''),
		Mode = info.Mode or 'Toggle',
		Modifiers = {},
		Toggled = false,
		SyncToggleState = info.SyncToggleState and true or false,
		Callback = info.Callback,
		NoUI = info.NoUI and true or false,
	})

	local slBind
	if not element.NoUI and parent and parent.SLInstance then
		local applying = false
		safe(function()
			slBind = parent.SLInstance:AddBind({
				CurrentValue = element.Value ~= '' and string.lower(element.Value) or nil,
				Tooltip = info.Tooltip,
				SyncToggleState = element.SyncToggleState,
				IgnoreConfig = true,
				Callback = function()
					if applying then
						return
					end
					element:RunChanged()
				end,
			}, tostring(idx))
		end)
	end

	element.SLInstance = slBind

	function element:SetValue(value)
		-- Obsidian passes { key, mode, modifiers }.
		if type(value) == 'table' then
			self.Value = tostring(value[1] or self.Value)
			self.Mode = value[2] or self.Mode
			self.Modifiers = value[3] or self.Modifiers
		else
			self.Value = tostring(value or '')
		end
		if slBind then
			safe(function()
				slBind:Set({ CurrentValue = string.lower(self.Value) })
			end)
		end
		return self
	end

	function element:Update() end
	function element:GetState()
		return self.Toggled
	end

	Options[idx] = element
	if parent then
		parent.KeyPicker = element
	end
	return element
end

function Groupbox:AddKeyPicker(idx, info)
	return Groupbox._addKeyPicker(self, nil, idx, info)
end

-- Obsidian extras PlayerTools may probe but does not depend on.
function Groupbox:AddColorPicker(idx, info)
	info = info or {}
	local element = attachChanged({
		Type = 'ColorPicker',
		Idx = idx,
		Value = info.Default or Color3.new(1, 1, 1),
		Transparency = info.Transparency or 0,
	})
	function element:SetValueRGB(color, transparency)
		self.Value = color
		self.Transparency = transparency or self.Transparency
		self:RunChanged()
		return self
	end
	function element:SetValue(value)
		return self:SetValueRGB(value)
	end
	Options[idx] = element
	return element
end

function Groupbox:AddDependencyBox()
	-- Starlight has no dependency boxes; behave like a passthrough groupbox.
	return self
end

--============================================================================
-- Tab
--============================================================================

local Tab = {}
Tab.__index = Tab

function Tab:_groupbox(name, column, icon)
	local slGroupbox
	safe(function()
		slGroupbox = self.SLTab:CreateGroupbox({
			Name = tostring(name or 'Group'),
			Icon = iconFor(icon),
			Column = column,
		}, ('%s_%s_%d'):format(tostring(self.Name), tostring(name), column))
	end)
	if not slGroupbox then
		return nil
	end

	local box = newGroupbox(slGroupbox, self)
	box.Name = name
	self.Groupboxes[name] = box
	return box
end

function Tab:AddLeftGroupbox(name, icon)
	return self:_groupbox(name, 1, icon)
end

function Tab:AddRightGroupbox(name, icon)
	-- Everything stacks into one column when the screen is too narrow for two.
	return self:_groupbox(name, math.min(2, columnCount), icon)
end

-- Used by Obsidian's SaveManager: Tab:AddGroupbox({ Side, Name, IconName }).
function Tab:AddGroupbox(info)
	info = info or {}
	local column = 1
	if tostring(info.Side or 'Left'):lower() == 'right' then
		column = math.min(2, columnCount)
	end
	return self:_groupbox(info.Name or 'Group', column, info.IconName or info.Icon)
end

-- Tabboxes degrade to a plain groupbox with tab-like children.
function Tab:AddLeftTabbox(name)
	local box = self:AddLeftGroupbox(name or 'Tabs')
	return {
		AddTab = function(_, tabName)
			return box
		end,
	}
end

function Tab:AddRightTabbox(name)
	local box = self:AddRightGroupbox(name or 'Tabs')
	return {
		AddTab = function(_, tabName)
			return box
		end,
	}
end

function Tab:Show()
	safe(function()
		if self.SLTab and type(self.SLTab.Show) == 'function' then
			self.SLTab:Show()
		elseif self.SLTab and self.SLTab.Instance then
			-- Starlight activates tabs by clicking the sidebar button.
			local button = self.SLTab.Button or self.SLTab.TabButton
			if button then
				button.Visible = true
			end
		end
	end)
end

function Tab:UpdateWarningBox() end

--============================================================================
-- Window
--============================================================================

local Window = {}
Window.__index = Window

function Window:AddTab(name, icon)
	local slTab
	safe(function()
		slTab = self.SLTabSection:CreateTab({
			Name = tostring(name),
			Icon = iconFor(icon),
			Columns = columnCount,
		}, tostring(name))
	end)
	if not slTab then
		error('[StarlightAdapter] CreateTab failed for ' .. tostring(name))
	end

	local tab = setmetatable({
		Name = name,
		SLTab = slTab,
		Groupboxes = {},
		Tabboxes = {},
	}, Tab)

	Library.Tabs[name] = tab
	self.Tabs[name] = tab
	return tab
end

function Window:AddKeyTab(name)
	return self:AddTab(name)
end

-- Obsidian dialog, used by SaveManager's destructive confirmations.
--
-- Starlight exposes no modal dialog, so instead of silently running a delete we
-- arm it: the first press only warns, a second press within the window commits.
local CONFIRM_WINDOW = 6
local pendingConfirms = {}

function Window:AddDialog(idx, info)
	info = info or {}

	local ordered = {}
	for key, button in pairs(info.FooterButtons or {}) do
		ordered[#ordered + 1] = { key = key, button = button }
	end
	table.sort(ordered, function(a, b)
		return (tonumber(a.button.Order) or 0) < (tonumber(b.button.Order) or 0)
	end)

	local dialog = {}
	function dialog:Dismiss() end

	-- Highest Order is the destructive action; Obsidian puts Cancel first.
	local primary = ordered[#ordered]
	local action = primary and primary.button and primary.button.Callback

	local key = tostring(idx)
	local now = os.clock()
	local armedAt = pendingConfirms[key]

	if armedAt and (now - armedAt) <= CONFIRM_WINDOW then
		pendingConfirms[key] = nil
		safe(function()
			Starlight:Notification({
				Title = tostring(info.Title or 'Confirmed'),
				Content = 'Confirmed.',
				Duration = 3,
			})
		end)
		if type(action) == 'function' then
			task.defer(function()
				callSoon(function()
					action(dialog)
				end)
			end)
		end
		return dialog
	end

	pendingConfirms[key] = now
	safe(function()
		Starlight:Notification({
			Title = tostring(info.Title or 'Confirm'),
			Content = ('%s\n\nPress again within %ds to confirm.'):format(
				tostring(info.Description or ''),
				CONFIRM_WINDOW
			),
			Duration = CONFIRM_WINDOW,
		})
	end)
	task.delay(CONFIRM_WINDOW, function()
		if pendingConfirms[key] == now then
			pendingConfirms[key] = nil
		end
	end)

	return dialog
end

--============================================================================
-- Library
--============================================================================

function Library:CreateWindow(info)
	info = info or {}

	local function sweepExistingStarlightUi()
		local function isTarget(gui)
			if not gui:IsA('ScreenGui') then
				return false
			end
			if gui:GetAttribute('SB2StarlightPlayerTools') == true then
				return true
			end
			if gui.Name == 'Starlight Interface Suite' or gui.Name == 'Starlight' then
				return true
			end
			local mw = gui:FindFirstChild('MainWindow')
			return mw and mw:FindFirstChild('Sidebar') and mw:FindFirstChild('Content')
		end
		local function sweep(parent)
			if not parent then
				return
			end
			local pending = {}
			for _, child in ipairs(parent:GetChildren()) do
				if isTarget(child) then
					pending[#pending + 1] = child
				end
			end
			for _, child in ipairs(pending) do
				pcall(function()
					child:Destroy()
				end)
			end
		end
		sweep(game:GetService('CoreGui'))
		sweep(game:GetService('CoreGui'):FindFirstChild('RobloxGui'))
		pcall(function()
			if type(gethui) == 'function' then
				sweep(gethui())
			end
		end)
		pcall(function()
			local lp = game:GetService('Players').LocalPlayer
			sweep(lp and lp:FindFirstChild('PlayerGui'))
		end)
		local prev = getgenv().SB2StarlightLib
		if type(prev) == 'table' then
			pcall(function()
				prev:Destroy()
			end)
		end
	end
	sweepExistingStarlightUi()

	-- PlayerTools ships a 300x260 Obsidian window, which is far below what
	-- Starlight's fixed-width columns need.
	local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize
	local maxWidth = viewport and (viewport.X - 40) or math.huge
	local maxHeight = viewport and (viewport.Y - 80) or math.huge

	columnCount = (widthForColumns(2) <= maxWidth) and 2 or 1

	local width = widthForColumns(columnCount)
	local height = 600

	local size = info.Size
	if typeof(size) == 'UDim2' then
		local minW = widthForColumns(columnCount)
		if size.X.Offset >= minW then
			width = size.X.Offset
		end
		if size.Y.Offset >= 360 then
			height = size.Y.Offset
		end
	end

	width = math.min(width, maxWidth)
	height = math.min(height, maxHeight)

	local defaultSize = UDim2.fromOffset(width, height)
	local minW, minH = width, height

	local slWindow
	local ok, err = pcall(function()
		slWindow = Starlight:CreateWindow({
			Name = tostring(info.Title or 'Ataraxia'),
			Subtitle = tostring(info.Footer or 'If you gaze long into an abyss, the abyss also gazes into you.'),
			Icon = iconFor(info.Icon),
			LoadingEnabled = false,
			BuildWarnings = false,
			InterfaceAdvertisingPrompts = false,
			NotifyOnCallbackError = false,
			DefaultSize = defaultSize,
			KeySystem = { Enabled = false },
			FileSettings = {
				RootFolder = 'PlayerTools',
				ConfigFolder = 'starlight',
			},
		})
	end)
	if not ok or not slWindow then
		error('[StarlightAdapter] Starlight CreateWindow failed: ' .. tostring(err))
	end

	local window = setmetatable({
		SLWindow = slWindow,
		Tabs = {},
	}, Window)

	safe(function()
		window.SLTabSection = slWindow:CreateTabSection('PlayerTools')
	end)
	if not window.SLTabSection then
		error('[StarlightAdapter] CreateTabSection failed')
	end

	Library.ScreenGui = Starlight.Instance
	Library.Window = window
	Library.WindowFrame = slWindow.Instance

	-- Tag it so the launcher can sweep our own orphans without touching an
	-- unrelated script's Starlight window.
	pcall(function()
		Starlight.Instance:SetAttribute('SB2StarlightPlayerTools', true)
	end)

	-- Starlight has no drag-resize and forgets position; persist it ourselves so
	-- the menu comes back where you left it.
	task.defer(function()
		local frame = slWindow.Instance
		if typeof(frame) ~= 'Instance' then
			return
		end
		-- Obsidian post-create sets Main to 300×260; re-apply Starlight's real size.
		local function enforceSize()
			if not frame.Parent then
				return
			end
			local cur = frame.Size
			local w = math.max(cur.X.Offset, minW)
			local h = math.max(cur.Y.Offset, minH)
			if w ~= cur.X.Offset or h ~= cur.Y.Offset then
				frame.Size = UDim2.fromOffset(w, h)
			end
		end
		enforceSize()
		task.delay(0.35, enforceSize)
		task.delay(1.5, enforceSize)
		pcall(function()
			frame:GetPropertyChangedSignal('Size'):Connect(function()
				if frame.Size.X.Offset < minW or frame.Size.Y.Offset < minH then
					enforceSize()
				end
			end)
		end)
		local path = 'PlayerTools/window_position_starlight'
		local function encode(pos)
			return ('%s,%s,%s,%s'):format(pos.X.Scale, pos.X.Offset, pos.Y.Scale, pos.Y.Offset)
		end
		pcall(function()
			if type(isfile) ~= 'function' or not isfile(path) then
				return
			end
			local xs, xo, ys, yo = tostring(readfile(path)):match('^([^,]+),([^,]+),([^,]+),([^,]+)$')
			xs, xo, ys, yo = tonumber(xs), tonumber(xo), tonumber(ys), tonumber(yo)
			if not (xs and xo and ys and yo) then
				return
			end
			-- A position saved for a smaller window can put this one off-screen.
			local screen = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize
			if screen then
				local w, h = frame.AbsoluteSize.X, frame.AbsoluteSize.Y
				xo = math.clamp(xo, 0, math.max(0, screen.X - w))
				yo = math.clamp(yo, 0, math.max(0, screen.Y - h))
				xs, ys = 0, 0
			end
			frame.Position = UDim2.new(xs, xo, ys, yo)
		end)
		local token = 0
		frame:GetPropertyChangedSignal('Position'):Connect(function()
			token += 1
			local mine = token
			task.delay(0.4, function()
				if mine ~= token or type(writefile) ~= 'function' then
					return
				end
				pcall(writefile, path, encode(frame.Position))
			end)
		end)
	end)

	pcall(function()
		game:GetService('StarterGui'):SetCore('SendNotification', {
			Title = 'Ataraxia',
			Text = 'UI loaded — If you gaze long into an abyss, the abyss also gazes into you.',
			Duration = 8,
		})
	end)

	return window
end

function Library:Notify(text, duration)
	if type(text) == 'table' then
		duration = text.Duration or duration
		text = text.Description or text.Content or text.Title or ''
	end
	safe(function()
		Starlight:Notification({
			Title = 'Ataraxia',
			Content = tostring(text),
			Duration = tonumber(duration) or 5,
		})
	end)
end

-- Hide the window frame, not the ScreenGui: PlayerTools runs a watchdog that
-- re-enables a disabled ScreenGui within a second, which would fight us.
function Library:Toggle()
	local frame = Library.WindowFrame
	if typeof(frame) == 'Instance' then
		pcall(function()
			frame.Visible = not frame.Visible
			Library.Toggled = frame.Visible
			Library.Open = frame.Visible
		end)
		return
	end

	local gui = Library.ScreenGui
	if typeof(gui) == 'Instance' then
		pcall(function()
			gui.Enabled = not gui.Enabled
			Library.Toggled = gui.Enabled
			Library.Open = gui.Enabled
		end)
	end
end

-- PlayerTools registers its menu keybind as a NoUI KeyPicker (default Home) and
-- assigns it to Library.ToggleKeybind, expecting the library to watch the key.
do
	local UserInputService = game:GetService('UserInputService')
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or Library.Unloaded then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end
		local picker = Library.ToggleKeybind
		local wanted = picker and picker.Value
		if type(wanted) ~= 'string' or wanted == '' then
			return
		end
		if input.KeyCode.Name:lower() == wanted:lower() then
			Library:Toggle()
		end
	end)
end

function Library:GetCustomIcon()
	-- PlayerTools falls back to its own icon handling when this returns nil.
	return nil
end

function Library:GetTextBounds(text, font, size, width)
	local fontSize = tonumber(size) or 14
	local ok, bounds = pcall(function()
		local params = Instance.new('GetTextBoundsParams')
		params.Text = tostring(text or '')
		params.Size = fontSize
		params.Width = tonumber(width) or math.huge
		return TextService:GetTextBoundsAsync(params)
	end)
	if ok and typeof(bounds) == 'Vector2' then
		return bounds.X, bounds.Y
	end
	return math.max(8, #tostring(text or '') * fontSize * 0.52), fontSize + 4
end

function Library:SafeCallback(fn, ...)
	if type(fn) ~= 'function' then
		return
	end
	local ok, err = pcall(fn, ...)
	if not ok then
		warn('[StarlightAdapter] callback: ' .. tostring(err))
	end
end

function Library:UpdateDependencyBoxes() end
function Library:SetWatermarkVisibility() end
function Library:SetWatermark() end
function Library:UpdateKeybindFrame() end
function Library:OnUnload(fn)
	Library.UnloadCallback = fn
end

function Library:Unload()
	Library.Unloaded = true
	if type(getgenv().SB2ScrubAllLeakedHooks) == 'function' then
		pcall(getgenv().SB2ScrubAllLeakedHooks)
	elseif type(getgenv().SB2DisconnectStarlightRenderStepped) == 'function' then
		pcall(getgenv().SB2DisconnectStarlightRenderStepped)
	end
	if type(Library.UnloadCallback) == 'function' then
		safe(Library.UnloadCallback)
	end
	safe(function()
		Starlight:Destroy()
	end)
	if type(getgenv().SB2ScrubAllLeakedHooks) == 'function' then
		pcall(getgenv().SB2ScrubAllLeakedHooks)
	elseif type(getgenv().SB2DisconnectStarlightRenderStepped) == 'function' then
		pcall(getgenv().SB2DisconnectStarlightRenderStepped)
	end
end

Library.SetNotifySound = function() end
Library.SetDPIScale = function() end

return Library
