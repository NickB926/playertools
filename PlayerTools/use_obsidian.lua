--[[
  Switch PlayerTools to Obsidian and load it — Potassium Execute:
    loadstring(readfile('PlayerTools/use_obsidian.lua'))()
]]
print('[use_obsidian] switching backend to Obsidian')

local g = getgenv()

pcall(function()
	if g.SB2HookWatchdogConn then
		g.SB2HookWatchdogConn:Disconnect()
	end
end)
g.SB2HookWatchdogConn = nil

if type(g.SB2TeardownStarlightLeaks) == 'function' then
	pcall(g.SB2TeardownStarlightLeaks)
elseif type(g.SB2ScrubAllLeakedHooks) == 'function' then
	pcall(g.SB2ScrubAllLeakedHooks)
end

if type(g.SB2StarlightLib) == 'table' then
	pcall(function()
		g.SB2StarlightLib:Destroy()
	end)
end
g.SB2StarlightLib = nil
g.SB2StarlightAdapterSource = nil
g.SB2PlayerTools = false
g.SB2RefreshPlayerTools = nil
g.SB2PlayerToolsGui = nil
g.SB2PlayerToolsLibrary = nil
g.SB2PlayerToolsBackend = nil

local function destroyStarlightGui(parent)
	if not parent then
		return
	end
	for _, child in ipairs(parent:GetChildren()) do
		if child:IsA('ScreenGui') then
			if child:GetAttribute('SB2StarlightPlayerTools') == true
				or child.Name == 'Starlight Interface Suite'
				or child.Name == 'Starlight'
				or (child:FindFirstChild('MainWindow') and child.MainWindow:FindFirstChild('Sidebar'))
			then
				pcall(function()
					child:Destroy()
				end)
			end
		end
	end
end

destroyStarlightGui(game:GetService('CoreGui'))
destroyStarlightGui(game:GetService('CoreGui'):FindFirstChild('RobloxGui'))
if type(gethui) == 'function' then
	pcall(function()
		destroyStarlightGui(gethui())
	end)
end
local lp = game:GetService('Players').LocalPlayer
destroyStarlightGui(lp and lp:FindFirstChild('PlayerGui'))

if type(writefile) == 'function' then
	pcall(writefile, 'PlayerTools/backend', 'obsidian')
end

g.SB2AllowObsidianFallback = true
loadstring(readfile('PlayerTools/launch.lua'))()
