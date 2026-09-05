--[[
    PlayerTools.lua — entry shim (Ataraxia)

    Feature app: PlayerTools/PlayerTools_Obsidian.lua
    Chrome: PlayerTools/AtaraxiaLibrary.lua
    Always launches via PlayerTools/launch.lua
]]

local compile = loadstring or load

local function guiAlive()
	local gui = getgenv().SB2PlayerToolsGui
	return typeof(gui) == 'Instance' and gui.Parent ~= nil
end

-- Always full relaunch when this entry is run. Soft refresh left stale anim-ghost
-- code in memory (Motor6D → live CharacterItems.Handle) and flung on every "reload".
getgenv().SB2ForceFullReload = true
getgenv().SB2PlayerToolsManualUnload = nil
getgenv().SB2PlayerToolsLoading = false
getgenv().SB2PlayerToolsLoadingSince = nil
getgenv().SB2PlayerToolsCode = nil -- never reuse cached Obsidian source
getgenv().SB2SoftPlayerToolsReload = true
-- Kill anim ghost BEFORE teardown so cross-welds cannot ragdoll for one frame.
pcall(function()
	if type(getgenv().SB2AnimSwapStop) == 'function' then
		getgenv().SB2AnimSwapStop()
	end
end)
pcall(function()
	local g = getgenv()._SB2AnimGhost
	if type(g) == 'table' then
		pcall(function()
			if g.hb then
				g.hb:Disconnect()
			end
		end)
		pcall(function()
			if g.played then
				g.played:Disconnect()
			end
		end)
		pcall(function()
			if g.clone then
				g.clone:Destroy()
			end
		end)
		pcall(function()
			if g.weaponFolder then
				g.weaponFolder:Destroy()
			end
		end)
		pcall(function()
			if g.world then
				g.world:Destroy()
			end
		end)
		getgenv()._SB2AnimGhost = nil
	end
	local cam = workspace.CurrentCamera
	if cam then
		for _, name in ipairs({
			'_SB2AnimGhostWorld',
			'_SB2AnimGhostChar',
			'_SB2AnimGhostWeapons',
		}) do
			local o = cam:FindFirstChild(name)
			if o then
				o:Destroy()
			end
		end
	end
	if type(getgenv().SB2WeaponModState) == 'table' then
		getgenv().SB2WeaponModState.AnimEnabled = false
		getgenv().SB2WeaponModState._AnimSkipAutoApply = true
	end
end)
-- Drop stale GUI so Ataraxia does not soft-return without rebuilding.
do
	local gui = getgenv().SB2PlayerToolsGui
	if typeof(gui) == 'Instance' then
		pcall(function()
			gui:Destroy()
		end)
	end
	getgenv().SB2PlayerToolsGui = nil
	getgenv().SB2PlayerTools = false
	getgenv().SB2RefreshPlayerTools = nil
end

for _, path in ipairs({ 'PlayerTools/launch.lua', 'launch.lua' }) do
	if type(isfile) == 'function' and isfile(path) then
		local src = readfile(path)
		local fn, err = compile(src, path)
		if not fn then
			error('[PlayerTools] launch compile failed (' .. path .. '): ' .. tostring(err))
		end
		return fn()
	end
end

error('[PlayerTools] launch.lua missing')
