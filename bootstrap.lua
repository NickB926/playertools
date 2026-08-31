--[[
	bootstrap.lua — one-line install / update for PlayerTools (Neuublue-style)

	Friend load (after repo is public, or they have access):

	  loadstring(game:HttpGet("https://raw.githubusercontent.com/NickB926/playertools/main/bootstrap.lua"))()

	Optional: pin a different feed
	  getgenv().SB2PlayerToolsUpdateBase = "https://raw.githubusercontent.com/NickB926/playertools/main"
]]

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

if type(makefolder) == 'function' then
	pcall(makefolder, 'PlayerTools')
end
if type(writefile) ~= 'function' then
	error('[PlayerTools bootstrap] writefile required')
end

-- Always refresh updater first, then run it.
local updaterSrc = httpGet(BASE .. '/PlayerTools/Updater.lua')
if not updaterSrc then
	error('[PlayerTools bootstrap] could not download Updater.lua from ' .. BASE)
end
pcall(writefile, 'PlayerTools/Updater.lua', updaterSrc)
pcall(writefile, 'PlayerTools/update_url.txt', BASE)

local fn, err = (loadstring or load)(updaterSrc, 'PlayerTools/Updater.lua')
if not fn then
	error('[PlayerTools bootstrap] Updater compile failed: ' .. tostring(err))
end
local Updater = fn()
getgenv().SB2PlayerToolsUpdateBase = BASE
local ok, detail = Updater.apply({ force = true, notify = say })
if not ok then
	say('Update finished with issues: ' .. tostring(detail))
else
	say('Files ready. Loading launch.lua…')
end

local launch = (isfile and isfile('PlayerTools/launch.lua') and readfile('PlayerTools/launch.lua')) or nil
if type(launch) ~= 'string' or launch == '' then
	launch = httpGet(BASE .. '/PlayerTools/launch.lua')
	if launch then
		pcall(writefile, 'PlayerTools/launch.lua', launch)
	end
end
if type(launch) ~= 'string' or launch == '' then
	error('[PlayerTools bootstrap] launch.lua missing')
end
local run, runErr = (loadstring or load)(launch, 'PlayerTools/launch.lua')
if not run then
	error('[PlayerTools bootstrap] launch compile failed: ' .. tostring(runErr))
end
return run()
