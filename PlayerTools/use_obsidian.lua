--[[
  use_obsidian.lua — pin backend to Obsidian UI and force a full rebuild
]]
if type(makefolder) == 'function' and type(isfolder) == 'function' then
	if not isfolder('PlayerTools') then
		pcall(makefolder, 'PlayerTools')
	end
end
if type(writefile) == 'function' then
	writefile('PlayerTools/backend', 'obsidian')
end

local g = getgenv()
g.SB2UseAtaraxiaLib = nil

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

warn('[PlayerTools] backend=obsidian — full rebuild')
loadstring(readfile('PlayerTools/PlayerTools.lua'))()
