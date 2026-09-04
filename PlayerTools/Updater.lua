--[[
	PlayerTools/Updater.lua

	Pulls versioned files from GitHub (Neuublue-style raw updates).

	Config (optional): PlayerTools/update_url.txt
	  one line = base raw URL, e.g.
	  https://raw.githubusercontent.com/NickB926/playertools/main

	Default base:
	  https://raw.githubusercontent.com/NickB926/playertools/main
]]

local HttpService = game:GetService('HttpService')

local DEFAULT_BASE = 'https://raw.githubusercontent.com/NickB926/playertools/main'
local VERSION_PATH = 'PlayerTools/version.json'
local UPDATE_URL_PATH = 'PlayerTools/update_url.txt'

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
	if type(game.HttpGet) == 'function' then
		local ok, body = pcall(function()
			return game:HttpGet(url)
		end)
		if ok and type(body) == 'string' and body ~= '' then
			return body
		end
	end
	return nil
end

local function readLocalVersion()
	if type(isfile) ~= 'function' or type(readfile) ~= 'function' then
		return nil
	end
	if not isfile(VERSION_PATH) then
		return nil
	end
	local ok, body = pcall(readfile, VERSION_PATH)
	if not ok or type(body) ~= 'string' or body == '' then
		return nil
	end
	local okJson, data = pcall(function()
		return HttpService:JSONDecode(body)
	end)
	if okJson and type(data) == 'table' then
		return data
	end
	return nil
end

local function updateBaseUrl()
	if type(isfile) == 'function' and type(readfile) == 'function' and isfile(UPDATE_URL_PATH) then
		local ok, body = pcall(readfile, UPDATE_URL_PATH)
		if ok and type(body) == 'string' then
			local url = body:gsub('%s+', ''):gsub('/+$', '')
			if url ~= '' then
				return url
			end
		end
	end
	local env = getgenv().SB2PlayerToolsUpdateBase
	if type(env) == 'string' and env ~= '' then
		return env:gsub('/+$', '')
	end
	return DEFAULT_BASE
end

local function ensureFolders(relPath)
	if type(makefolder) ~= 'function' then
		return
	end
	pcall(makefolder, 'PlayerTools')
	local parts = {}
	for part in string.gmatch(relPath, '[^/]+') do
		parts[#parts + 1] = part
		if #parts > 1 or part == 'PlayerTools' then
			-- build nested dirs except the file name
		end
	end
	-- Create parent dirs for paths like PlayerTools/hive/x
	local acc = ''
	local segs = {}
	for seg in string.gmatch(relPath, '[^/]+') do
		segs[#segs + 1] = seg
	end
	for i = 1, #segs - 1 do
		acc = acc == '' and segs[i] or (acc .. '/' .. segs[i])
		pcall(makefolder, acc)
	end
end

local function writeFile(relPath, body)
	if type(writefile) ~= 'function' or type(body) ~= 'string' then
		return false
	end
	ensureFolders(relPath)
	local ok = pcall(writefile, relPath, body)
	return ok and true or false
end

local Updater = {}

function Updater.getBase()
	return updateBaseUrl()
end

function Updater.fetchRemoteVersion()
	local base = updateBaseUrl()
	local body = httpGet(base .. '/version.json')
	if not body then
		return nil, 'could not fetch version.json'
	end
	local ok, data = pcall(function()
		return HttpService:JSONDecode(body)
	end)
	if not ok or type(data) ~= 'table' then
		return nil, 'bad version.json'
	end
	return data
end

function Updater.localVersion()
	local data = readLocalVersion()
	return data and tostring(data.version or '') or ''
end

function Updater.check()
	local remote, err = Updater.fetchRemoteVersion()
	if not remote then
		return { ok = false, error = err or 'fetch failed' }
	end
	local localVer = Updater.localVersion()
	local remoteVer = tostring(remote.version or '')
	return {
		ok = true,
		localVersion = localVer,
		remoteVersion = remoteVer,
		needsUpdate = localVer == '' or (remoteVer ~= '' and remoteVer ~= localVer),
		files = type(remote.files) == 'table' and remote.files or {},
		message = remote.message,
	}
end

function Updater.apply(opts)
	opts = type(opts) == 'table' and opts or {}
	local notify = opts.notify
	local function say(msg)
		msg = tostring(msg)
		if type(notify) == 'function' then
			pcall(notify, msg)
			-- notify already prints (e.g. bootstrap) — skip duplicate [PlayerTools Update] line
			if opts.quietWarn then
				return
			end
		end
		warn('[PlayerTools Update] ' .. msg)
	end

	local info = Updater.check()
	if not info.ok then
		say('Update check failed: ' .. tostring(info.error))
		return false, info.error
	end
	if not info.needsUpdate and not opts.force then
		say('Already on ' .. tostring(info.remoteVersion))
		return true, 'up to date'
	end

	local base = updateBaseUrl()
	local files = info.files
	if #files == 0 then
		return false, 'no files listed'
	end
	say(('Updating %s -> %s (%d files)...'):format(tostring(info.localVersion), tostring(info.remoteVersion), #files))
	local okCount, failCount = 0, 0
	for _, rel in ipairs(files) do
		rel = tostring(rel):gsub('^/+', '')
		if rel == '' then
			continue
		end
		local url = base .. '/' .. rel
		local body = httpGet(url)
		if type(body) == 'string' and body ~= '' then
			if writeFile(rel, body) then
				okCount += 1
			else
				failCount += 1
				say('write failed: ' .. rel)
			end
		else
			failCount += 1
			say('download failed: ' .. rel)
		end
		task.wait(0.05)
	end

	-- Always refresh local version stamp from remote.
	local remoteBody = httpGet(base .. '/version.json')
	if remoteBody then
		writeFile(VERSION_PATH, remoteBody)
	end

	say(('Update done - %d ok, %d failed. Rejoin / reload PlayerTools.'):format(okCount, failCount))
	-- Pin Ataraxia chrome after apply (friends often still had local backend=obsidian).
	pcall(function()
		if type(writefile) == 'function' then
			local be = ''
			if type(isfile) == 'function' and isfile('PlayerTools/backend') and type(readfile) == 'function' then
				be = tostring(readfile('PlayerTools/backend')):lower():gsub('%s', '')
			end
			if be ~= 'starlight' then
				writefile('PlayerTools/backend', 'ataraxia\n')
			end
		end
	end)
	return failCount == 0, ('%d/%d'):format(okCount, #files)
end

getgenv().SB2PlayerToolsUpdater = Updater
return Updater
