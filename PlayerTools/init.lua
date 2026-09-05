--[[
    PlayerTools folder entrypoint (Potassium one-folder layout).
    Tries folder-local paths first, then scripts-root paths.
    Ataraxia chrome only — see launch.lua.
]]

if getgenv().SB2PlayerTools == true
	and getgenv().SB2PlayerToolsGui
	and getgenv().SB2PlayerToolsGui.Parent
then
	if type(getgenv().SB2RefreshPlayerTools) == 'function' then
		return getgenv().SB2RefreshPlayerTools()
	end
	warn('[PlayerTools] already loaded — skipping duplicate execute')
	return
end
getgenv().SB2PlayerToolsInstance = nil

local compile = loadstring or load
assert(compile, '[PlayerTools] loadstring/load unavailable')

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

-- launch.lua loads Ataraxia chrome + feature app.
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
