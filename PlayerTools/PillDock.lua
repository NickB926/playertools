--[[
    PillDock.lua — shared vertical pill stack for ServerHop / Waypoints / JoinLogs
    Drag anywhere on the stack to move all pills together.
    Save: PlayerTools/pill_dock.json
]]

local Players = game:GetService('Players')
local UserInputService = game:GetService('UserInputService')
local HttpService = game:GetService('HttpService')

local LocalPlayer = Players.LocalPlayer
	or Players:GetPropertyChangedSignal('LocalPlayer'):Wait()
	or Players.LocalPlayer

local SAVE_PATHS = {
	'PlayerTools/pill_dock.json',
	'pill_dock.json',
}

local ORDER = { 'Join', 'WP', 'JL' }

local function parentGui()
	local ok, hui = pcall(function()
		return gethui and gethui()
	end)
	if ok and hui then
		return hui
	end
	return game:GetService('CoreGui') or (LocalPlayer and LocalPlayer:FindFirstChild('PlayerGui'))
end

local function ensureFolder()
	if type(makefolder) ~= 'function' or type(isfolder) ~= 'function' then
		return
	end
	pcall(function()
		if not isfolder('PlayerTools') then
			makefolder('PlayerTools')
		end
	end)
end

local function loadPos()
	if type(readfile) ~= 'function' then
		return nil
	end
	for _, path in ipairs(SAVE_PATHS) do
		local okEx, exists = pcall(function()
			return isfile and isfile(path)
		end)
		if okEx and exists then
			local ok, body = pcall(readfile, path)
			if ok and type(body) == 'string' and body ~= '' then
				local jok, data = pcall(function()
					return HttpService:JSONDecode(body)
				end)
				if jok and type(data) == 'table' and type(data.ox) == 'number' then
					return data
				end
			end
		end
	end
	return nil
end

local function savePos(stack)
	if type(writefile) ~= 'function' or not stack then
		return
	end
	ensureFolder()
	local abs = stack.AbsolutePosition
	local ox = math.floor((abs and abs.X or stack.Position.X.Offset) + 0.5)
	local oy = math.floor((abs and abs.Y or stack.Position.Y.Offset) + 0.5)
	local okJson, payload = pcall(function()
		return HttpService:JSONEncode({
			sx = 0,
			ox = ox,
			sy = 0,
			oy = oy,
		})
	end)
	if not okJson or type(payload) ~= 'string' then
		payload = ('{"sx":0,"ox":%d,"sy":0,"oy":%d}'):format(ox, oy)
	end
	for _, path in ipairs(SAVE_PATHS) do
		pcall(writefile, path, payload)
	end
end

local function clampStack(stack)
	if not stack then
		return
	end
	local size = stack.AbsoluteSize
	-- AutomaticSize is 0 until pills layout — don't treat that as off-screen.
	if size.X < 20 or size.Y < 20 then
		return
	end
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
	local abs = stack.AbsolutePosition
	local maxX = math.max(8, vp.X - size.X - 8)
	local maxY = math.max(8, vp.Y - size.Y - 8)
	local x = math.clamp(abs.X, 8, maxX)
	local y = math.clamp(abs.Y, 8, maxY)
	if math.abs(x - abs.X) > 2 or math.abs(y - abs.Y) > 2 then
		stack.Position = UDim2.fromOffset(x, y)
	end
end

local function ensureDock()
	local dock = getgenv().SB2PillDock
	if dock and dock.gui and dock.gui.Parent and dock.stack and dock.stack.Parent then
		return dock
	end
	if dock and dock.gui then
		pcall(function()
			dock.gui:Destroy()
		end)
	end

	local gui = Instance.new('ScreenGui')
	gui.Name = 'SB2PillDock'
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 2000
	pcall(function()
		gui.Parent = parentGui()
	end)
	if not gui.Parent and LocalPlayer then
		gui.Parent = LocalPlayer:WaitForChild('PlayerGui')
	end

	local saved = loadPos()
	local stack = Instance.new('Frame')
	stack.Name = 'Stack'
	stack.BackgroundTransparency = 1
	stack.BorderSizePixel = 0
	stack.AutomaticSize = Enum.AutomaticSize.XY
	stack.Size = UDim2.fromOffset(0, 0)
	if saved then
		stack.Position = UDim2.fromOffset(saved.ox or 16, saved.oy or 80)
	else
		stack.Position = UDim2.fromOffset(16, 80)
	end
	stack.Active = true
	stack.Parent = gui

	local layout = Instance.new('UIListLayout')
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = stack

	dock = {
		gui = gui,
		stack = stack,
		pills = {},
		specs = {},
		dragDist = 0,
		dragging = false,
		dragStart = nil,
		startPos = nil,
	}
	getgenv().SB2PillDock = dock

	-- Drag the whole stack (from background of stack or any pill that starts a drag).
	local function beginDrag(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch
		then
			return
		end
		dock.dragging = true
		dock.dragDist = 0
		dock.dragStart = input.Position
		dock.startPos = stack.Position
	end
	dock.beginDrag = beginDrag
	local function endDrag()
		if not dock.dragging then
			return
		end
		dock.dragging = false
		if dock.dragDist >= 4 then
			savePos(stack)
		end
	end
	stack.InputBegan:Connect(beginDrag)
	stack.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			endDrag()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			endDrag()
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if not dock.dragging or not dock.dragStart or not dock.startPos then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch
		then
			local delta = input.Position - dock.dragStart
			dock.dragDist = math.max(dock.dragDist, math.abs(delta.X) + math.abs(delta.Y))
			stack.Position = UDim2.new(
				dock.startPos.X.Scale,
				dock.startPos.X.Offset + delta.X,
				dock.startPos.Y.Scale,
				dock.startPos.Y.Offset + delta.Y
			)
		end
	end)

	local saveToken = 0
	stack:GetPropertyChangedSignal('Position'):Connect(function()
		if dock.dragging then
			return
		end
		saveToken += 1
		local token = saveToken
		task.delay(0.2, function()
			if token == saveToken and stack and stack.Parent then
				savePos(stack)
			end
		end)
	end)

	task.defer(function()
		clampStack(stack)
	end)

	return dock
end

local function orderIndex(id)
	for i, name in ipairs(ORDER) do
		if name == id then
			return i
		end
	end
	return 99
end

--[[
  spec = {
    id = 'Join'|'WP'|'JL',
    text = 'Join',
    textColor = Color3,
    strokeColor = Color3,
    onClick = function(),
  }
  returns the TextButton
]]
local function registerPill(spec)
	if type(spec) ~= 'table' or not spec.id then
		return nil
	end
	local dock = ensureDock()
	dock.specs[spec.id] = spec

	local old = dock.pills[spec.id]
	if old then
		pcall(function()
			old:Destroy()
		end)
		dock.pills[spec.id] = nil
	end

	local btn = Instance.new('TextButton')
	btn.Name = 'Pill_' .. tostring(spec.id)
	btn.LayoutOrder = orderIndex(spec.id)
	btn.Size = UDim2.fromOffset(72, 28)
	btn.BackgroundColor3 = Color3.fromRGB(28, 32, 40)
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = true
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 13
	btn.TextColor3 = spec.textColor or Color3.fromRGB(220, 230, 245)
	btn.Text = tostring(spec.text or spec.id)
	btn.ZIndex = 20
	btn.Parent = dock.stack
	Instance.new('UICorner', btn).CornerRadius = UDim.new(0, 8)
	local stroke = Instance.new('UIStroke')
	stroke.Color = spec.strokeColor or Color3.fromRGB(70, 90, 120)
	stroke.Thickness = 1
	stroke.Parent = btn

	btn.InputBegan:Connect(function(input)
		if type(dock.beginDrag) == 'function' then
			dock.beginDrag(input)
		end
	end)
	btn.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			if dock.dragging then
				dock.dragging = false
				if (dock.dragDist or 0) >= 4 then
					savePos(dock.stack)
				end
			end
		end
	end)

	btn.MouseButton1Click:Connect(function()
		if (dock.dragDist or 0) >= 4 then
			return
		end
		if type(spec.onClick) == 'function' then
			pcall(spec.onClick)
		end
	end)

	dock.pills[spec.id] = btn
	task.defer(function()
		clampStack(dock.stack)
	end)
	return btn
end

local function setPillText(id, text)
	local dock = getgenv().SB2PillDock
	local btn = dock and dock.pills and dock.pills[id]
	if btn then
		btn.Text = tostring(text)
	end
end

local function closeAllPillPanels()
	pcall(function()
		local hop = getgenv().SB2ServerHopGui
		local root = hop and hop:FindFirstChild('Root')
		if root then
			root.Visible = false
		end
	end)
	pcall(function()
		local wp = getgenv().SB2WaypointsGui
		local main = wp and wp:FindFirstChild('Main')
		if main then
			main.Visible = false
		end
	end)
	pcall(function()
		local jl = getgenv().SB2JoinLogsGui
		local main = jl and jl:FindFirstChild('Main')
		if main then
			main.Visible = false
		end
	end)
end

local function sessionOverlayUp()
	local lp = LocalPlayer
	local pg = lp and lp:FindFirstChild('PlayerGui')
	local gui = pg and pg:FindFirstChild('Gui')
	if not (gui and gui:IsA('ScreenGui') and gui.Enabled) then
		return false
	end
	local bg = gui:FindFirstChild('Background')
	if bg and bg:FindFirstChild('LoadingCircle') then
		return true
	end
	local ok, desc = pcall(function()
		return gui:GetDescendants()
	end)
	if ok and type(desc) == 'table' then
		for _, d in ipairs(desc) do
			if d:IsA('TextLabel') then
				local t = string.lower(tostring(d.Text))
				if string.find(t, 'session is loading', 1, true) or string.find(t, 'found server', 1, true) then
					return true
				end
			end
		end
	end
	return false
end

-- Close Join/WP/JL panels once Roblox has a session (loading overlay gone).
-- Only after we actually saw the overlay — don't slam a panel you opened later.
task.spawn(function()
	local sawOverlay = false
	for _ = 1, 120 do
		if sessionOverlayUp() then
			sawOverlay = true
		elseif sawOverlay then
			closeAllPillPanels()
			return
		end
		task.wait(0.5)
	end
	if sawOverlay then
		closeAllPillPanels()
	end
end)

getgenv().SB2EnsurePillDock = ensureDock
getgenv().SB2RegisterPill = registerPill
getgenv().SB2SetPillText = setPillText
getgenv().SB2CloseAllPillPanels = closeAllPillPanels
getgenv().SB2ClampPillDock = function()
	local dock = getgenv().SB2PillDock
	if dock then
		clampStack(dock.stack)
	end
end

return {
	ensure = ensureDock,
	register = registerPill,
	setText = setPillText,
	closePanels = closeAllPillPanels,
}
