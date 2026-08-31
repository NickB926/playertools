--[[
    PlayerTools folder entrypoint (Potassium one-folder layout).
    Tries folder-local paths first, then scripts-root paths.
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
getgenv().SB2PlayerToolsInstance = nil

local compile = loadstring or load
assert(compile, '[PlayerTools] loadstring/load unavailable')

local candidates = {
	'PlayerTools.lua', -- when Potassium cwd is the PlayerTools folder
	'PlayerTools/PlayerTools.lua', -- when cwd is scripts/
	'init.lua',
	'PlayerTools/init.lua',
}

local function tryRead(path)
	if type(isfile) == 'function' then
		local ok, exists = pcall(isfile, path)
		if ok and not exists then
			return nil
		end
	end
	if type(readfile) ~= 'function' then
		return nil
	end
	local ok, src = pcall(readfile, path)
	if ok and type(src) == 'string' and src ~= '' then
		return src
	end
	return nil
end

-- launch.lua picks the UI backend (Starlight, falling back to Obsidian).
for _, path in ipairs({ 'PlayerTools/launch.lua', 'launch.lua' }) do
	local src = tryRead(path)
	if src then
		local fn, err = compile(src, path)
		if not fn then
			error('[PlayerTools] compile failed (' .. path .. '): ' .. tostring(err))
		end
		return fn()
	end
end

-- Prefer the main script over re-entering init.
for _, path in ipairs({ 'PlayerTools.lua', 'PlayerTools/PlayerTools.lua' }) do
	local src = tryRead(path)
	if src then
		local fn, err = compile(src, path)
		if not fn then
			error('[PlayerTools] compile failed (' .. path .. '): ' .. tostring(err))
		end
		return fn()
	end
end

error(
	'[PlayerTools] could not read PlayerTools.lua. '
		.. 'In Potassium open the PlayerTools folder and execute PlayerTools.lua directly.'
)
