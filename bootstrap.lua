--[[
	bootstrap.lua — one-line install / update for PlayerTools

	Friend load:

	  loadstring(game:HttpGet("https://raw.githubusercontent.com/NickB926/playertools/main/bootstrap.lua"))()

	Optional feed override:
	  getgenv().SB2PlayerToolsUpdateBase = "https://raw.githubusercontent.com/NickB926/playertools/main"

	Every step is guarded: if anything fails, you get an on-screen notification
	and PlayerTools/_bootstrap_err.txt says why (instead of silently showing nothing).
]]

local G = getgenv()

local function notify(title, text, dur)
	pcall(function()
		game:GetService('StarterGui'):SetCore('SendNotification', {
			Title = title,
			Text = text,
			Duration = dur or 6,
		})
	end)
end

local function say(msg)
	warn('[PlayerTools bootstrap] ' .. tostring(msg))
end

-- A previous run that crashed used to leave this flag set forever, so every
-- later run was skipped silently. Treat it as stale after 90 seconds.
local busy = G.SB2PlayerToolsBootstrapBusy
if type(busy) == 'number' and os.clock() - busy < 90 then
	say('already running - skip duplicate')
	notify('PlayerTools', 'Already loading - wait a few seconds.')
	return
end
G.SB2PlayerToolsBootstrapBusy = os.clock()

local BASE = (type(G.SB2PlayerToolsUpdateBase) == 'string' and G.SB2PlayerToolsUpdateBase ~= ''
	and G.SB2PlayerToolsUpdateBase:gsub('/+$', ''))
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
	if ok and type(body) == 'string' and body ~= '' and not body:match('^%s*404: Not Found') then
		return body
	end
	return nil
end

local function main()
	if type(writefile) ~= 'function' or type(readfile) ~= 'function' or type(isfile) ~= 'function' then
		error('your executor has no file functions (writefile/readfile/isfile) - PlayerTools needs them', 0)
	end
	if type(makefolder) == 'function' then
		pcall(makefolder, 'PlayerTools')
	end

	notify('PlayerTools', 'Checking for updates...', 4)

	local updaterSrc = httpGet(BASE .. '/PlayerTools/Updater.lua')
	local Updater
	if updaterSrc then
		local fn, err = (loadstring or load)(updaterSrc, 'PlayerTools/Updater.lua')
		if fn then
			pcall(writefile, 'PlayerTools/Updater.lua', updaterSrc)
			Updater = fn()
		else
			say('remote Updater compile failed: ' .. tostring(err))
		end
	end
	if not Updater and isfile('PlayerTools/Updater.lua') then
		local fn = (loadstring or load)(readfile('PlayerTools/Updater.lua'), 'PlayerTools/Updater.lua')
		Updater = fn and fn()
	end
	if type(Updater) ~= 'table' then
		error('could not download Updater.lua from ' .. BASE .. ' (is HttpGet blocked?)', 0)
	end
	pcall(writefile, 'PlayerTools/update_url.txt', BASE)
	G.SB2PlayerToolsUpdateBase = BASE

	local firstInstall = not isfile('PlayerTools/launch.lua') or not isfile('PlayerTools/PlayerTools_Obsidian.lua')
	if firstInstall then
		notify('PlayerTools', 'First install - downloading files (about 2 MB)...', 8)
	end
	-- apply() handles: new version, first install, and restoring any missing files.
	local ok, detail = Updater.apply({ force = firstInstall, notify = say, quietWarn = true })
	if not ok then
		say('update finished with issues: ' .. tostring(detail))
	end

	-- Ataraxia chrome is the only UI; make sure it is there and selected.
	if not isfile('PlayerTools/AtaraxiaLibrary.lua') then
		local body = httpGet(BASE .. '/PlayerTools/AtaraxiaLibrary.lua')
		if body then
			pcall(writefile, 'PlayerTools/AtaraxiaLibrary.lua', body)
		end
	end
	local be = ''
	if isfile('PlayerTools/backend') then
		local okBe, bodyBe = pcall(readfile, 'PlayerTools/backend')
		if okBe then
			be = tostring(bodyBe):lower():gsub('%s', '')
		end
	end
	if be ~= 'starlight' and be ~= 'ataraxia' then
		pcall(writefile, 'PlayerTools/backend', 'ataraxia\n')
	end

	for _, need in ipairs({ 'PlayerTools/launch.lua', 'PlayerTools/PlayerTools_Obsidian.lua', 'PlayerTools/AtaraxiaLibrary.lua' }) do
		if not isfile(need) then
			error(need .. ' is missing after download - check your executor can reach raw.githubusercontent.com', 0)
		end
	end

	-- A stale flag from an earlier crashed run makes the app think it is a reload.
	if G.SB2PlayerTools and not G.SB2PlayerToolsLibrary then
		G.SB2PlayerTools = false
	end

	local launch = readfile('PlayerTools/launch.lua')
	local run, runErr = (loadstring or load)(launch, 'PlayerTools/launch.lua')
	if not run then
		error('launch.lua compile failed: ' .. tostring(runErr), 0)
	end
	return run()
end

local okMain, result = pcall(main)
G.SB2PlayerToolsBootstrapBusy = nil
if not okMain then
	local msg = tostring(result)
	say('FAILED: ' .. msg)
	notify('PlayerTools failed to load', msg:sub(1, 180), 15)
	pcall(writefile, 'PlayerTools/_bootstrap_err.txt', os.date('%Y-%m-%d %H:%M:%S') .. '\n' .. msg .. '\n')
	return nil
end
pcall(function()
	if isfile('PlayerTools/_bootstrap_err.txt') then
		writefile('PlayerTools/_bootstrap_err.txt', '')
	end
end)
return result
