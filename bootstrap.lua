--[[
	bootstrap.lua — one-line install / update for PlayerTools (Neuublue-style)

	Friend load:

	  loadstring(game:HttpGet("https://raw.githubusercontent.com/NickB926/playertools/main/bootstrap.lua"))()

	Optional feed override:
	  getgenv().SB2PlayerToolsUpdateBase = "https://raw.githubusercontent.com/NickB926/playertools/main"
]]

if getgenv().SB2PlayerToolsBootstrapBusy == true then
	warn('[PlayerTools bootstrap] already running — skip duplicate')
	return
end
getgenv().SB2PlayerToolsBootstrapBusy = true

local BASE = (type(getgenv().SB2PlayerToolsUpdateBase) == 'string' and getgenv().SB2PlayerToolsUpdateBase ~= ''
	and getgenv().SB2PlayerToolsUpdateBase:gsub('/+$', ''))
	or 'https://raw.githubusercontent.com/NickB926/playertools/main'

local function httpGet(url)
	local req = (syn and syn.request) or http_request or (http and http.request) or request
	if type(req) == 'function' then
		local ok, res = pcall(req, { Url = url, Method = 'GET' })
		if ok and type(res) == 'table' then
			local body = res.Body or res.body
			local code = tonumber(res.StatusCode or res.Status or res.statusCode) or 0
			if code >= 200 and code < 300 and type(body) == 'string' then
				return body
			end
		end
	end
	local ok, body = pcall(function()
		return game:HttpGet(url)
	end)
	if ok and type(body) == 'string' and body ~= '' then
		return body
	end
	return nil
end

local function say(msg)
	warn('[PlayerTools bootstrap] ' .. tostring(msg))
end

local function finish(err)
	getgenv().SB2PlayerToolsBootstrapBusy = nil
	if err then
		error(err)
	end
end

if type(makefolder) == 'function' then
	pcall(makefolder, 'PlayerTools')
end
if type(writefile) ~= 'function' then
	finish('[PlayerTools bootstrap] writefile required')
end

-- Refresh updater, then only pull files when remote version differs (or launch missing).
local updaterSrc = httpGet(BASE .. '/PlayerTools/Updater.lua')
if not updaterSrc then
	finish('[PlayerTools bootstrap] could not download Updater.lua from ' .. BASE)
end
pcall(writefile, 'PlayerTools/Updater.lua', updaterSrc)
pcall(writefile, 'PlayerTools/update_url.txt', BASE)

local fn, err = (loadstring or load)(updaterSrc, 'PlayerTools/Updater.lua')
if not fn then
	finish('[PlayerTools bootstrap] Updater compile failed: ' .. tostring(err))
end
local Updater = fn()
getgenv().SB2PlayerToolsUpdateBase = BASE

local hasLaunch = type(isfile) == 'function' and isfile('PlayerTools/launch.lua')
local function localHasWaveDefenseAllow()
	if type(isfile) ~= 'function' or type(readfile) ~= 'function' then
		return false
	end
	if not isfile('PlayerTools/PlayerTools_Obsidian.lua') then
		return false
	end
	local ok, body = pcall(readfile, 'PlayerTools/PlayerTools_Obsidian.lua')
	return ok and type(body) == 'string' and body:find('121252145396212', 1, true) ~= nil
end
local info = Updater.check and Updater.check() or { ok = false }
local needWave = not localHasWaveDefenseAllow()
if info.ok and not info.needsUpdate and hasLaunch and not needWave then
	say(('Already on %s — skip download'):format(tostring(info.remoteVersion)))
else
	-- First install, new version, or missing Wave Defense allow (same-version publish used to skip).
	local ok, detail = Updater.apply({
		force = not hasLaunch or needWave,
		notify = say,
		quietWarn = true,
	})
	if not ok then
		say('Update finished with issues: ' .. tostring(detail))
	else
		say('Files ready.')
	end
end

-- Friends stuck on Obsidian chrome: ensure Ataraxia bits even when version matches.
do
	local function ensureFile(rel)
		local path = rel
		if type(isfile) == 'function' and isfile(path) then
			return true
		end
		local body = httpGet(BASE .. '/' .. rel)
		if type(body) == 'string' and body ~= '' then
			pcall(writefile, path, body)
			return true
		end
		return false
	end
	ensureFile('PlayerTools/AtaraxiaLibrary.lua')
	-- Migrate default chrome. Explicit starlight pin is left alone.
	local be = ''
	if type(isfile) == 'function' and isfile('PlayerTools/backend') and type(readfile) == 'function' then
		local okBe, bodyBe = pcall(readfile, 'PlayerTools/backend')
		if okBe then
			be = tostring(bodyBe):lower():gsub('%s', '')
		end
	end
	if be ~= 'starlight' then
		pcall(writefile, 'PlayerTools/backend', 'ataraxia\n')
		if be == 'obsidian' or be == '' then
			say('chrome → ataraxia (was ' .. (be == '' and 'unset' or be) .. ')')
		end
	end
end

local launch = (isfile and isfile('PlayerTools/launch.lua') and readfile('PlayerTools/launch.lua')) or nil
if type(launch) ~= 'string' or launch == '' then
	launch = httpGet(BASE .. '/PlayerTools/launch.lua')
	if launch then
		pcall(writefile, 'PlayerTools/launch.lua', launch)
	end
end
if type(launch) ~= 'string' or launch == '' then
	finish('[PlayerTools bootstrap] launch.lua missing')
end
local run, runErr = (loadstring or load)(launch, 'PlayerTools/launch.lua')
if not run then
	finish('[PlayerTools bootstrap] launch compile failed: ' .. tostring(runErr))
end

local okRun, result = pcall(run)
getgenv().SB2PlayerToolsBootstrapBusy = nil
if not okRun then
	error(result)
end
return result
