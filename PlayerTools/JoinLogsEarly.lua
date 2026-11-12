--[[
	JoinLogsEarly.lua — first-boot join logger.

	Runs before PlayerTools / IY / loading screen. Hooks Players immediately,
	buffers join/leave, then loads the full JoinLogs panel when the file exists.
	Re-queues itself on teleport so the next floor is covered from frame 1.
]]

local Players = game:GetService('Players')
local g = getgenv()

local function queueSelf()
	local q = (type(queueteleport) == 'function' and queueteleport)
		or (type(queue_on_teleport) == 'function' and queue_on_teleport)
		or (type(queueonteleport) == 'function' and queueonteleport)
	if type(q) ~= 'function' then
		return
	end
	if g.SB2JoinLogsEarlyQueued == true then
		return
	end
	g.SB2JoinLogsEarlyQueued = true
	pcall(q, [[
		getgenv().SB2JoinLogsEarlyQueued=nil
		local gid=tonumber(game.GameId); local pid=tonumber(game.PlaceId)
		if gid~=212154879 and gid~=8460001097 and pid~=121252145396212 then return end
		pcall(function()
			local p=(isfile and isfile('PlayerTools/JoinLogsEarly.lua') and 'PlayerTools/JoinLogsEarly.lua')
				or (isfile and isfile('PlayerTools/JoinLogs.iy') and 'PlayerTools/JoinLogs.iy')
				or (isfile and isfile('JoinLogs.iy') and 'JoinLogs.iy')
			if not p then return end
			local fn=(loadstring or load)(readfile(p), p)
			if fn then fn() end
		end)
	]])
end

local buf = g.SB2JoinLogsEarlyBuf
if type(buf) ~= 'table' then
	buf = {}
	g.SB2JoinLogsEarlyBuf = buf
end

local function rec(kind, plr)
	if typeof(plr) ~= 'Instance' then
		return
	end
	local lp = Players.LocalPlayer
	if lp and plr == lp and kind ~= 'here' then
		return
	end
	local row = {
		kind = kind,
		username = plr.Name,
		displayName = plr.DisplayName or plr.Name,
		userId = plr.UserId,
		accountAge = tonumber(plr.AccountAge) or 0,
		time = os.time(),
	}
	-- If the panel is already up, push once. Do not also keep a buffer copy
	-- or drain/seed will log the same person twice.
	if type(g.SB2JoinLogsPush) == 'function' then
		pcall(g.SB2JoinLogsPush, kind, row, { force = true })
		return
	end
	buf[#buf + 1] = row
end

if g.SB2JoinLogsEarlyHooked ~= true then
	g.SB2JoinLogsEarlyHooked = true
	g.SB2JoinLogsPlayersHooked = true
	pcall(function()
		Players.PlayerAdded:Connect(function(plr)
			rec('join', plr)
		end)
	end)
	pcall(function()
		Players.PlayerRemoving:Connect(function(plr)
			rec('leave', plr)
		end)
	end)
	for _, plr in ipairs(Players:GetPlayers()) do
		rec('here', plr)
	end
end

queueSelf()

local gui = g.SB2JoinLogsGui
if gui and gui.Parent then
	g.SB2JoinLogsReady = true
	return
end
if g.SB2JoinLogsReady == true then
	return
end

local paths = {
	'PlayerTools/JoinLogs.iy',
	'JoinLogs.iy',
}
for _, path in ipairs(paths) do
	local okFile = type(isfile) == 'function' and isfile(path)
	if okFile and type(readfile) == 'function' then
		local ok, src = pcall(readfile, path)
		if ok and type(src) == 'string' and #src > 80 then
			local fn = (loadstring or load)(src, path)
			if fn then
				pcall(fn)
			end
			break
		end
	end
end
