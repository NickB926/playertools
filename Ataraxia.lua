--[[
  Ataraxia.lua — load full PlayerTools on Ataraxia (Roster) chrome

  loadstring(readfile("Ataraxia.lua"))()
]]

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

-- Preview chrome
if g._AtaraxiaUnload then
	pcall(g._AtaraxiaUnload)
	g._AtaraxiaUnload = nil
end
if g._RosterLabUnload then
	pcall(g._RosterLabUnload)
	g._RosterLabUnload = nil
end

-- Force FULL rebuild. PlayerTools.lua soft-refreshes when already live, which
-- leaves alts stuck on Obsidian chrome after Ataraxia.lua is run "to all".
do
	local lib = g.SB2PlayerToolsLibrary
	if type(lib) == 'table' and type(lib.Unload) == 'function' then
		pcall(function()
			lib:Unload()
		end)
	end
	local function nuke(root)
		if not root then
			return
		end
		for _, gui in ipairs(root:GetChildren()) do
			if gui:IsA('ScreenGui') then
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
	local lp = game:GetService('Players').LocalPlayer
	nuke(lp and lp:FindFirstChild('PlayerGui'))
	nuke(game:GetService('CoreGui'))
	if gethui then
		local ok, h = pcall(gethui)
		if ok then
			nuke(h)
		end
	end
	g.SB2PlayerTools = false
	g.SB2PlayerToolsGui = nil
	g.SB2RefreshPlayerTools = nil
	g.SB2PlayerToolsLibrary = nil
	g.SB2PlayerToolsLoading = false
	g.SB2PlayerToolsLoadingSince = nil
	g.SB2AllowObsidianFallback = true
end

local compile = loadstring or load
for _, path in ipairs({ 'PlayerTools/PlayerTools.lua', 'PlayerTools.lua' }) do
	if type(isfile) == 'function' and isfile(path) then
		local src = readfile(path)
		local fn, err = compile(src, path)
		if not fn then
			error('[Ataraxia] compile failed: ' .. tostring(err))
		end
		warn('[Ataraxia] loading full PlayerTools on AtaraxiaLibrary (forced rebuild)')
		return fn()
	end
end

error('[Ataraxia] PlayerTools/PlayerTools.lua missing')
