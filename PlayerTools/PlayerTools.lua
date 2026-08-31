--[[
    PlayerTools.lua — entry shim (Starlight by default)

    Full Obsidian build: PlayerTools/PlayerTools_Obsidian.lua
    To force Obsidian: write "obsidian" to PlayerTools/backend, then reload.
]]

if getgenv().SB2PlayerTools == true
	and getgenv().SB2PlayerToolsGui
	and getgenv().SB2PlayerToolsGui.Parent
then
	local starRS = 0
	if type(getgenv().SB2CountStarlightRenderStepped) == 'function' then
		starRS = getgenv().SB2CountStarlightRenderStepped()
	end
	local leakThreshold = getgenv().SB2StarlightRSLeakThreshold or 35
	if starRS > leakThreshold then
		warn(('[PlayerTools] %d leaked Starlight hooks — full reload instead of refresh'):format(starRS))
		if type(getgenv().SB2TeardownStarlightLeaks) == 'function' then
			pcall(getgenv().SB2TeardownStarlightLeaks)
		end
	elseif type(getgenv().SB2RefreshPlayerTools) == 'function' then
		if type(getgenv().SB2DisconnectStarlightLibHooks) == 'function' then
			pcall(getgenv().SB2DisconnectStarlightLibHooks)
		end
		return getgenv().SB2RefreshPlayerTools()
	else
		warn('[PlayerTools] already loaded — skipping duplicate execute')
			return
		end
	end

	local compile = loadstring or load

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
