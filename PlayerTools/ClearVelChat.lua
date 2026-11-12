--!nocheck
--!nolint
--[[
	ClearVelChat.lua — PlayerTools module (moved out of the CCI plugin).
	Hides the "Vel Obtained" chat spam:
	  1. Wraps the game's UI.ServerEvent so VelObtained messages never make a chat line.
	  2. Anything that still lands (ChatVelTemplate) is hidden, then destroyed, and the
	     bottom-anchored chat is reflowed so normal lines don't get stranded off-screen.

	Loaded by PlayerTools_Obsidian.lua (Settings → "Hide Vel Obtained chat").
	State lives in getgenv() so a reload replaces the previous copy cleanly.
	  getgenv().SB2SetClearVel(true/false)  — turn on/off
	  getgenv().SB2ClearVelStop()           — unhook everything
]]

local BUILD = 'clearvel-v2-keeporder'
local g = getgenv()

if type(g.SB2ClearVelStop) == 'function' then
	pcall(g.SB2ClearVelStop)
end

local Players = game:GetService('Players')
local LocalPlayer = Players.LocalPlayer

local S = {
	on = false,
	conns = {},
	scroll = nil,
	scrollSearchAt = 0,
	uiOld = nil,
	uiWrapped = nil,
	uiRetry = nil,
	sweep = nil,
	fitting = false,
}
g.SB2ClearVelState = S
g.SB2ClearVelBuild = BUILD

local function disconnectAll()
	for _, c in ipairs(S.conns) do
		pcall(function()
			c:Disconnect()
		end)
	end
	S.conns = {}
end

-- ── chat line handling ─────────────────────────────────────────────────────

local function isLiveVelFrame(frame)
	if not frame or frame.Name ~= 'ChatVelTemplate' then
		return false
	end
	local parent = frame.Parent
	if not parent then
		return false
	end
	if parent.Name == 'ScrollContent' then
		return true
	end
	-- Never touch the prototype stored in a Templates folder outside the chat.
	local ok, underChat = pcall(function()
		local cur = frame
		while cur and cur ~= game do
			if cur.Name == 'Chat' and cur:FindFirstAncestorOfClass('PlayerGui') then
				return frame:IsA('GuiObject') and frame.Visible
			end
			cur = cur.Parent
		end
		return false
	end)
	return ok and underChat == true
end

local function destroyVelFrame(frame)
	if not isLiveVelFrame(frame) then
		return
	end
	-- Hide first, destroy a moment later (instant Destroy races the chat layout).
	-- Height 0, not negative: negative rows shrank the canvas so chat could not scroll.
	pcall(function()
		frame.Visible = false
		frame.Size = UDim2.fromOffset(0, 0)
	end)
	task.delay(0.15, function()
		pcall(function()
			if frame.Parent then
				frame:Destroy()
			end
		end)
	end)
end

local function wipeVelTemplates(scroll)
	if not scroll then
		return
	end
	for _, child in ipairs(scroll:GetChildren()) do
		if child.Name == 'ChatVelTemplate' then
			destroyVelFrame(child)
		end
	end
end

local function findChatScroll()
	if S.scroll and S.scroll.Parent then
		return S.scroll
	end
	S.scroll = nil
	local playerGui = LocalPlayer and LocalPlayer:FindFirstChild('PlayerGui')
	if not playerGui then
		return nil
	end
	local cardinal = playerGui:FindFirstChild('CardinalUI')
	local playerUI = cardinal and cardinal:FindFirstChild('PlayerUI')
	local chat = playerUI and playerUI:FindFirstChild('Chat')
	local scroll = chat and chat:FindFirstChild('ScrollContent')
	if scroll then
		S.scroll = scroll
		return scroll
	end
	-- Expensive fallback, at most once every 10s.
	local now = os.clock()
	if now - S.scrollSearchAt < 10 then
		return nil
	end
	S.scrollSearchAt = now
	for _, d in ipairs(playerGui:GetDescendants()) do
		if d.Name == 'ScrollContent' and d.Parent and d.Parent.Name == 'Chat' then
			S.scroll = d
			return d
		end
	end
	return nil
end

-- Chat lines are bottom-anchored (yScale 1, negative offset). Removing lines without a
-- reflow left messages stranded off-screen ("1 line chat").
local function reflowChatScroll(scroll)
	if not scroll then
		return
	end
	local lines = {}
	for _, child in ipairs(scroll:GetChildren()) do
		if child:IsA('GuiObject')
			and child.Visible
			and child.Name ~= 'UIListLayout'
			and child.Name ~= 'UIPadding'
			and child.Name ~= 'ChatVelTemplate'
		then
			lines[#lines + 1] = child
		end
	end
	-- Keep exactly the order they are on screen. The game deletes the TOPMOST line when chat
	-- hits 50, so a newer line ending up above an older one got that newer line deleted.
	table.sort(lines, function(a, b)
		return a.AbsolutePosition.Y < b.AbsolutePosition.Y
	end)
	local yOff = 0
	for i = #lines, 1, -1 do
		local c = lines[i]
		local h = c.AbsoluteSize.Y
		if h < 1 then
			h = c.Size.Y.Offset > 0 and c.Size.Y.Offset or 25
		end
		yOff += h + 5 -- same 5px gap the game uses
		pcall(function()
			c.Position = UDim2.new(0, 0, 1, -yOff)
		end)
	end
	local height = math.max(yOff, 1)
	pcall(function()
		scroll.CanvasSize = UDim2.new(1, 0, 0, height)
		local win = scroll.AbsoluteWindowSize.Y
		if win < 1 then
			win = scroll.AbsoluteSize.Y
		end
		scroll.CanvasPosition = Vector2.new(0, math.max(0, height - win))
	end)
end

-- Keep the canvas tall enough for every line so the chat stays scrollable.
local function ensureCanvasFits(scroll)
	if S.fitting or not scroll or not scroll.Parent then
		return
	end
	local needed = 0
	for _, child in ipairs(scroll:GetChildren()) do
		if child:IsA('GuiObject') and child.Visible and child.Name ~= 'ChatVelTemplate' then
			local p = child.Position
			if p.Y.Scale == 1 then
				needed = math.max(needed, -p.Y.Offset)
			end
		end
	end
	if needed <= 0 then
		return
	end
	local canvas = scroll.CanvasSize
	local have = canvas.Y.Offset
	if canvas.Y.Scale ~= 0 or needed <= have + 1 then
		return
	end
	S.fitting = true
	pcall(function()
		local win = scroll.AbsoluteWindowSize.Y
		if win < 1 then
			win = scroll.AbsoluteSize.Y
		end
		local atBottom = scroll.CanvasPosition.Y >= math.max(0, have - win) - 4
		scroll.CanvasSize = UDim2.new(canvas.X.Scale, canvas.X.Offset, 0, needed)
		if atBottom then
			scroll.CanvasPosition = Vector2.new(0, math.max(0, needed - win))
		end
	end)
	S.fitting = false
end

local function bindChat(scroll)
	if not S.on or not scroll then
		return
	end
	if S.boundScroll == scroll and S.chatConns and #S.chatConns > 0 then
		local hadVel = scroll:FindFirstChild('ChatVelTemplate') ~= nil
		wipeVelTemplates(scroll)
		if hadVel then
			task.delay(0.2, reflowChatScroll, scroll)
		end
		return
	end
	for _, c in ipairs(S.chatConns or {}) do
		pcall(function()
			c:Disconnect()
		end)
	end
	S.chatConns = {}
	S.boundScroll = scroll
	wipeVelTemplates(scroll)
	S.chatConns[#S.chatConns + 1] = scroll.ChildAdded:Connect(function(frame)
		if not S.on then
			return
		end
		if frame and frame.Name == 'ChatVelTemplate' then
			destroyVelFrame(frame)
			task.delay(0.2, function()
				reflowChatScroll(scroll)
			end)
		else
			task.defer(ensureCanvasFits, scroll)
		end
	end)
	S.chatConns[#S.chatConns + 1] = scroll:GetPropertyChangedSignal('CanvasSize'):Connect(function()
		task.defer(ensureCanvasFits, scroll)
	end)
	if scroll:FindFirstChild('ChatVelTemplate') then
		task.delay(0.2, reflowChatScroll, scroll)
	end
end

local function unbindChat()
	for _, c in ipairs(S.chatConns or {}) do
		pcall(function()
			c:Disconnect()
		end)
	end
	S.chatConns = {}
	S.boundScroll = nil
end

-- ── UI.ServerEvent hook (stops the line being made at all) ─────────────────

local function findGameService(serviceName)
	local ok, objects = pcall(getgc, true)
	if not ok or type(objects) ~= 'table' then
		return nil
	end
	for _, object in next, objects do
		if type(object) == 'table' then
			local Services = rawget(object, 'Services')
			local svc = Services and rawget(Services, serviceName)
			if svc and type(rawget(svc, 'ServerEvent')) == 'function' then
				return svc
			end
		end
	end
	return nil
end

local function installUIHook()
	if type(getgc) ~= 'function' then
		return false
	end
	local UI = findGameService('UI')
	if not UI or type(UI.ServerEvent) ~= 'function' then
		return false
	end
	if S.uiWrapped and UI.ServerEvent == S.uiWrapped then
		return true
	end
	local old = UI.ServerEvent
	S.uiOld = old
	local function wrapped(...)
		if S.on then
			local payload = (...)
			if type(payload) == 'table' and payload[2] == 'VelObtained' then
				return
			end
		end
		return old(...)
	end
	UI.ServerEvent = wrapped
	S.uiWrapped = wrapped
	S.uiService = UI
	return true
end

local function ensureUIHook()
	if installUIHook() or S.uiRetry then
		return
	end
	S.uiRetry = task.spawn(function()
		for _ = 1, 40 do
			if not S.on then
				break
			end
			if installUIHook() then
				break
			end
			task.wait(0.5)
		end
		S.uiRetry = nil
	end)
end

local function restoreUIHook()
	if S.uiRetry then
		pcall(task.cancel, S.uiRetry)
		S.uiRetry = nil
	end
	local UI = S.uiService
	if UI and S.uiOld and UI.ServerEvent == S.uiWrapped then
		pcall(function()
			UI.ServerEvent = S.uiOld
		end)
	end
	S.uiOld, S.uiWrapped, S.uiService = nil, nil, nil
end

-- ── on / off ───────────────────────────────────────────────────────────────

local function start()
	if S.on then
		local scroll = findChatScroll()
		if scroll then
			bindChat(scroll)
		end
		return
	end
	S.on = true
	ensureUIHook()
	local scroll = findChatScroll()
	if scroll then
		bindChat(scroll)
	end
	-- Chat UI can be rebuilt (respawn / teleport UI reset): rebind when it comes back.
	local playerGui = LocalPlayer and (LocalPlayer:FindFirstChild('PlayerGui'))
	if playerGui then
		S.conns[#S.conns + 1] = playerGui.DescendantAdded:Connect(function(desc)
			if not S.on then
				return
			end
			if desc.Name == 'ScrollContent' and desc.Parent and desc.Parent.Name == 'Chat' then
				S.scroll = desc
				task.defer(bindChat, desc)
			elseif desc.Name == 'ChatVelTemplate' then
				destroyVelFrame(desc)
			end
		end)
	else
		task.spawn(function()
			local pg = LocalPlayer:WaitForChild('PlayerGui', 120)
			if pg and S.on then
				S.on = false
				start()
			end
		end)
	end
	-- Light safety net (no PlayerGui scans): rebind if the scroll was swapped, re-hook UI.
	S.sweep = task.spawn(function()
		while S.on do
			task.wait(12)
			if not S.on then
				break
			end
			local sc = findChatScroll()
			if sc then
				bindChat(sc)
			end
			-- getgc() is a heavy scan: only retry a few times if the hook never took.
			if not (S.uiWrapped and S.uiService and S.uiService.ServerEvent == S.uiWrapped) then
				S.uiMisses = (S.uiMisses or 0) + 1
				if S.uiMisses <= 5 then
					installUIHook()
				end
			end
		end
	end)
end

local function stop()
	S.on = false
	disconnectAll()
	unbindChat()
	if S.sweep then
		pcall(task.cancel, S.sweep)
		S.sweep = nil
	end
	restoreUIHook()
end

g.SB2SetClearVel = function(on)
	if on then
		start()
	else
		stop()
	end
	return S.on
end
g.SB2ClearVelStop = stop

return g.SB2SetClearVel
