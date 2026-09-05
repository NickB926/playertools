--[[
	PlayerTools/launch.lua

	Ataraxia-only entry: loads PlayerTools_Obsidian.lua (feature app) with
	AtaraxiaLibrary.lua chrome. No Starlight / Obsidian UI backends.
]]

local compile = loadstring or load

local APP_PATHS = {
	'PlayerTools/PlayerTools_Obsidian.lua',
	'PlayerTools_Obsidian.lua',
}
local ATA_PATHS = {
	'PlayerTools/AtaraxiaLibrary.lua',
	'AtaraxiaLibrary.lua',
}

local function exists(path)
	if type(isfile) ~= 'function' then
		return false
	end
	local ok, is = pcall(isfile, path)
	return ok and is == true
end

local function run(path)
	local src = readfile(path)
	local fn, err = compile(src, path)
	if not fn then
		error('[PlayerTools] compile failed (' .. path .. '): ' .. tostring(err))
	end
	return fn()
end

local function hideRobloxChat()
	pcall(function()
		game:GetService('StarterGui'):SetCoreGuiEnabled(Enum.CoreGuiType.Chat, false)
	end)
	pcall(function()
		local ec = game:GetService('CoreGui'):FindFirstChild('ExperienceChat')
		if ec and ec:IsA('ScreenGui') then
			ec.Enabled = false
		end
	end)
end

local function ensureGameChatVisible()
	pcall(function()
		local ui = getgenv().SB2RequiredServices and getgenv().SB2RequiredServices.UI
		if ui and ui.Pui and ui.Pui.Chat then
			ui.Pui.Chat.Visible = true
		end
	end)
end

getgenv().SB2HideGameChat = hideRobloxChat
getgenv().SB2EnsureGameChat = ensureGameChatVisible

local ataPath
for _, path in ipairs(ATA_PATHS) do
	if exists(path) then
		ataPath = path
		break
	end
end
if not ataPath then
	error('[PlayerTools] AtaraxiaLibrary.lua missing — required for Ataraxia chrome')
end

local appPath
for _, path in ipairs(APP_PATHS) do
	if exists(path) then
		appPath = path
		break
	end
end
if not appPath then
	error('[PlayerTools] PlayerTools_Obsidian.lua missing')
end

getgenv().SB2UseAtaraxiaLib = true
getgenv().SB2PlayerToolsBackend = 'ataraxia'
getgenv().SB2PlayerToolsBackendError = nil
getgenv().SB2AllowObsidianFallback = nil
getgenv().SB2StarlightAdapterSource = nil

hideRobloxChat()
ensureGameChatVisible()
warn('[PlayerTools] launching Ataraxia')
return run(appPath)
