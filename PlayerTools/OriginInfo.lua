--!nocheck
--!nolint
--[[
	OriginInfo.lua — PlayerTools module.
	Adds the item's original owner to the menu you get when you click an item in your
	inventory:  "Origin: <name> [<UserId>]"  (or "Origin: you" for items you got yourself).

	Uses the Origin attribute every item already carries, the same one the mod
	ViewInventory panel shows. Read-only: nothing is sent to the server.

	getgenv().SB2SetOriginInfo(true/false)
]]

local BUILD = 'origininfo-v3'
local g = getgenv()
if type(g.SB2OriginInfoStop) == 'function' then
	pcall(g.SB2OriginInfoStop)
end

local Players = game:GetService('Players')
local RS = game:GetService('ReplicatedStorage')
local LocalPlayer = Players.LocalPlayer

local S = { on = false, inv = nil, orig = nil, names = {} }
g.SB2OriginInfoState = S
g.SB2OriginInfoBuild = BUILD

local PREFIX = 'Origin: '

-- Name lookups run on our own worker thread: called from inside the game's menu code
-- GetNameFromUserIdAsync fails, so the menu only reads the cache and queues misses.
local queue, queued = {}, {}
local function want(id)
	if id and not S.names[id] and not queued[id] then
		queued[id] = true
		queue[#queue + 1] = id
	end
end

local function nameOf(id)
	local cached = S.names[id]
	if cached then
		return cached
	end
	local p = Players:GetPlayerByUserId(id)
	if p then
		S.names[id] = p.Name
		return p.Name
	end
	-- Same as the mod menu: ask Roblox right now (usually ~0.1s).
	local ok, n = pcall(Players.GetNameFromUserIdAsync, Players, id)
	if ok and type(n) == 'string' then
		S.names[id] = n
		return n
	end
	-- Record why it failed so it can be fixed.
	local msg = ('%s id=%d err=%s thread=%s'):format(os.date('%H:%M:%S'), id, tostring(n), tostring(coroutine.isyieldable and coroutine.isyieldable()))
	g.SB2OriginLastErr = msg
	pcall(appendfile, 'PlayerTools/_origin_err.txt', msg .. '\n')
	want(id)
	return nil
end

local function startWorker()
	local token = {}
	S.workerToken = token
	task.spawn(function()
		while S.workerToken == token do
			local id = table.remove(queue, 1)
			if id then
				local ok, n = pcall(Players.GetNameFromUserIdAsync, Players, id)
				if ok and type(n) == 'string' then
					S.names[id] = n
					queued[id] = nil
				else
					-- try again later
					task.delay(10, function()
						queued[id] = nil
						want(id)
					end)
				end
				task.wait(0.15)
			else
				task.wait(0.5)
			end
		end
	end)
end

local function prefetchInventory()
	pcall(function()
		local inv = RS.Profiles[LocalPlayer.Name].Inventory
		for _, it in ipairs(inv:GetChildren()) do
			local id = tonumber(it:GetAttribute('Origin'))
			if id and id ~= LocalPlayer.UserId then
				want(id)
			end
		end
		S.invConn = inv.ChildAdded:Connect(function(it)
			local id = tonumber(it:GetAttribute('Origin'))
			if id and id ~= LocalPlayer.UserId then
				want(id)
			end
		end)
	end)
end

local function originLine(item)
	local id = tonumber(item and item:GetAttribute('Origin'))
	if not id then
		return PREFIX .. 'unknown'
	end
	if id == LocalPlayer.UserId then
		return PREFIX .. 'you [' .. id .. ']'
	end
	local name = nameOf(id)
	return PREFIX .. (name or 'looking up...') .. ' [' .. id .. ']'
end

local function inventoryModule()
	local ok, m = pcall(function()
		return require(RS.CardinalClient.MainModule.Services.UI.Inventory)
	end)
	if ok and type(m) == 'table' and type(m.GetOptions) == 'function' then
		return m
	end
	return nil
end

local function start()
	if S.on then
		return true
	end
	local inv = inventoryModule()
	if not inv then
		return false
	end
	S.inv = inv
	S.orig = inv.GetOptions
	local orig = S.orig
	inv.GetOptions = function(data, ...)
		local opts = orig(data, ...)
		-- The mod view already lists the owner; only add ours for your own inventory.
		if S.on and type(opts) == 'table' and not LocalPlayer:GetAttribute('ViewingProfile') then
			local ok, line = pcall(originLine, data and data.item)
			if ok and line then
				local at = table.find(opts, 'Cancel') or (#opts + 1)
				table.insert(opts, at, line)
			end
		end
		return opts
	end
	-- Clicking the info line should do nothing.
	if type(inv.itemAction) == 'function' then
		local origAction = inv.itemAction
		S.origAction = origAction
		inv.itemAction = function(data, action, ...)
			if type(action) == 'string' and action:sub(1, #PREFIX) == PREFIX then
				return
			end
			return origAction(data, action, ...)
		end
	end
	S.on = true
	startWorker()
	prefetchInventory()
	return true
end

local function stop()
	S.on = false
	S.workerToken = nil
	if S.invConn then
		pcall(function()
			S.invConn:Disconnect()
		end)
		S.invConn = nil
	end
	if S.inv then
		if S.orig then
			S.inv.GetOptions = S.orig
		end
		if S.origAction then
			S.inv.itemAction = S.origAction
		end
	end
	S.inv, S.orig, S.origAction = nil, nil, nil
end

g.SB2SetOriginInfo = function(on)
	if on then
		return start()
	end
	stop()
	return false
end
g.SB2OriginInfoStop = stop

return g.SB2SetOriginInfo
