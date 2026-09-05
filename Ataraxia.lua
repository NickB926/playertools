--[[
  Ataraxia.lua — load full PlayerTools on Ataraxia (Roster) chrome

  loadstring(readfile("Ataraxia.lua"))()
]]

warn('[Ataraxia] starting…')

local function say(msg)
	warn('[Ataraxia] ' .. tostring(msg))
end

local okBoot, bootErr = xpcall(function()
	if type(makefolder) == 'function' and type(isfolder) == 'function' then
		if not isfolder('PlayerTools') then
			pcall(makefolder, 'PlayerTools')
		end
	end
	if type(writefile) == 'function' then
		pcall(writefile, 'PlayerTools/backend', 'ataraxia')
	end

	local g = getgenv()
	g.SB2UseAtaraxiaLib = true
	g.SB2ForceFullReload = true
	g.SB2PlayerToolsManualUnload = nil

	-- Preview chrome
	if g._AtaraxiaUnload then
		pcall(g._AtaraxiaUnload)
		g._AtaraxiaUnload = nil
	end
	if g._RosterLabUnload then
		pcall(g._RosterLabUnload)
		g._RosterLabUnload = nil
	end

	-- Force FULL rebuild. Soft-refresh left alts stuck / looked like "no launch".
	do
		local lib = g.SB2PlayerToolsLibrary
		if type(lib) == 'table' and type(lib.Unload) == 'function' then
			pcall(function()
				lib:Unload()
			end)
		end
		local function nuke(root)
			if typeof(root) ~= 'Instance' then
				return
			end
			local kids = {}
			local okKids, list = pcall(function()
				return root:GetChildren()
			end)
			if not okKids or type(list) ~= 'table' then
				return
			end
			for _, gui in ipairs(list) do
				if typeof(gui) == 'Instance' and gui:IsA('ScreenGui') then
					local n = gui.Name
					if n == 'SB2PlayerTools'
						or n == 'Ataraxia'
						or n == 'AtaraxiaLab'
						or n == 'RosterLab'
						or gui:GetAttribute('SB2PlayerTools') == true
					then
						pcall(function()
							gui:Destroy()
						end)
					end
				end
			end
		end
		pcall(function()
			local lp = game:GetService('Players').LocalPlayer
			nuke(lp and lp:FindFirstChild('PlayerGui'))
		end)
		pcall(function()
			nuke(game:GetService('CoreGui'))
		end)
		pcall(function()
			if type(gethui) == 'function' then
				local ok, h = pcall(gethui)
				if ok then
					nuke(h)
				end
			end
		end)
		g.SB2PlayerTools = false
		g.SB2PlayerToolsGui = nil
		g.SB2RefreshPlayerTools = nil
		g.SB2PlayerToolsLibrary = nil
		g.SB2PlayerToolsLoading = false
		g.SB2PlayerToolsLoadingSince = nil
		g.SB2AllowObsidianFallback = true
	end

	local compile = loadstring or load
	if type(compile) ~= 'function' then
		error('loadstring/load unavailable')
	end

	local loaded = false
	for _, path in ipairs({ 'PlayerTools/PlayerTools.lua', 'PlayerTools.lua' }) do
		local exists = type(isfile) == 'function' and isfile(path)
		say(('check %s exists=%s'):format(path, tostring(exists)))
		if exists then
			local src = readfile(path)
			if type(src) ~= 'string' or src == '' then
				error(path .. ' empty/unreadable')
			end
			local fn, err = compile(src, path)
			if not fn then
				error('compile failed: ' .. tostring(err))
			end
			say('loading full PlayerTools on AtaraxiaLibrary (forced rebuild)')
			loaded = true
			return fn()
		end
	end

	if not loaded then
		error('PlayerTools/PlayerTools.lua missing — is workspace mapped?')
	end
end, function(err)
	return tostring(err) .. '\n' .. tostring(debug.traceback('', 2))
end)

if not okBoot then
	say('FAILED:\n' .. tostring(bootErr))
	pcall(function()
		if type(writefile) == 'function' then
			writefile('PlayerTools/_ataraxia_err.txt', tostring(bootErr))
		end
	end)
	error('[Ataraxia] ' .. tostring(bootErr), 0)
end

return okBoot
