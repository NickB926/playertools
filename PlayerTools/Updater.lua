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
		if ok and type(body) == 'string' and body ~= '' and not body:match('^%s*404: Not Found') then
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

-- The author's own machine keeps a PlayerTools/_no_github_update marker so a GitHub
-- update never overwrites newer local work.
function Updater.isDevCopy()
	if type(isfile) ~= 'function' then
		return false
	end
	local ok, is = pcall(isfile, 'PlayerTools/_no_github_update')
	return ok and is == true
end

local function localMissing(files)
	local out = {}
	if type(isfile) ~= 'function' then
		return out
	end
	for _, rel in ipairs(files) do
		rel = tostring(rel):gsub('^/+', '')
		if rel ~= '' and rel ~= VERSION_PATH then
			local ok, is = pcall(isfile, rel)
			if not (ok and is == true) then
				out[#out + 1] = rel
			end
		end
	end
	return out
end
Updater.localMissing = localMissing

-- Files merged with the friend's own copy instead of replaced.
local MERGE_LINES = {
	['PlayerTools/whitelist.txt'] = true,
}
local function mergeLines(rel, remoteBody)
	if type(isfile) ~= 'function' or type(readfile) ~= 'function' then
		return remoteBody
	end
	local okIs, is = pcall(isfile, rel)
	if not (okIs and is) then
		return remoteBody
	end
	local okRead, localBody = pcall(readfile, rel)
	if not okRead or type(localBody) ~= 'string' or localBody == '' then
		return remoteBody
	end
	local seen, out = {}, {}
	local function add(body)
		for line in string.gmatch(body, '[^\r\n]+') do
			local key = line:gsub('^%s+', ''):gsub('%s+$', ''):lower()
			if key ~= '' and not seen[key] then
				seen[key] = true
				out[#out + 1] = line
			end
		end
	end
	add(remoteBody)
	add(localBody)
	return table.concat(out, '\n') .. '\n'
end

-- Friend installs start with every toggle off (launch.lua reads this marker).
function Updater.markFriendBuild()
	if Updater.isDevCopy() or type(writefile) ~= 'function' then
		return
	end
	local okIs, is = pcall(isfile, 'PlayerTools/_friend_build')
	if not (okIs and is) then
		pcall(writefile, 'PlayerTools/_friend_build', 'toggles start off on this install\n')
	end
end

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

local function parseVersionParts(ver)
	ver = tostring(ver or ''):gsub('^%s*(.-)%s*$', '%1')
	local major, minor, patch = ver:match('^(%d+)%.(%d+)%.(%d+)')
	if not major then
		return nil
	end
	return tonumber(major), tonumber(minor), tonumber(patch)
end

-- Returns 1 if a > b, -1 if a < b, 0 if equal or unparseable tie.
function Updater.compareVersions(a, b)
	local am, an, ap = parseVersionParts(a)
	local bm, bn, bp = parseVersionParts(b)
	if not am or not bm then
		return tostring(a) == tostring(b) and 0 or nil
	end
	if am ~= bm then
		return am > bm and 1 or -1
	end
	if an ~= bn then
		return an > bn and 1 or -1
	end
	if ap ~= bp then
		return ap > bp and 1 or -1
	end
	return 0
end

function Updater.check()
	local remote, err = Updater.fetchRemoteVersion()
	if not remote then
		return { ok = false, error = err or 'fetch failed' }
	end
	local localVer = Updater.localVersion()
	local remoteVer = tostring(remote.version or '')
	local cmp = Updater.compareVersions(remoteVer, localVer)
	-- Every publish stamps a new build id, so a re-publish under the same version
	-- number still reaches friends (1.0.37 went out twice and half-updated people).
	local localData = readLocalVersion() or {}
	local remoteBuild = tostring(remote.build or '')
	local buildChanged = remoteBuild ~= '' and remoteBuild ~= tostring(localData.build or '')
	local needsUpdate = localVer == ''
		or (remoteVer ~= '' and cmp == 1)
		or (remoteVer ~= '' and localVer ~= remoteVer and cmp == nil)
		or (buildChanged and cmp ~= -1)
	return {
		ok = true,
		localVersion = localVer,
		remoteVersion = remoteVer,
		needsUpdate = needsUpdate,
		localNewer = cmp == -1,
		files = type(remote.files) == 'table' and remote.files or {},
		missing = localMissing(type(remote.files) == 'table' and remote.files or {}),
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

	if Updater.isDevCopy() and not opts.forceDev then
		say('PlayerTools/_no_github_update present - skipping GitHub update (dev machine).')
		return true, 'dev copy'
	end
	Updater.markFriendBuild()
	local info = Updater.check()
	if not info.ok then
		say('Update check failed: ' .. tostring(info.error))
		return false, info.error
	end
	local repairOnly = not info.needsUpdate and not opts.force and #info.missing > 0
	if not info.needsUpdate and not opts.force and not repairOnly then
		if info.localNewer then
			say(
				('Local %s is newer than remote %s — keeping local files (no downgrade).'):format(
					tostring(info.localVersion),
					tostring(info.remoteVersion)
				)
			)
			return true, 'local newer'
		end
		say('Already on ' .. tostring(info.remoteVersion))
		return true, 'up to date'
	end

	local base = updateBaseUrl()
	local files = repairOnly and info.missing or info.files
	if #files == 0 then
		return false, 'no files listed'
	end
	if repairOnly then
		say(('Restoring %d missing file(s)...'):format(#files))
	else
		say(('Updating %s -> %s (%d files)...'):format(tostring(info.localVersion), tostring(info.remoteVersion), #files))
	end
	local okCount, failCount = 0, 0
	for _, rel in ipairs(files) do
		rel = tostring(rel):gsub('^/+', '')
		if rel == '' then
			continue
		end
		local url = base .. '/' .. rel
		local body = httpGet(url)
		-- Never replace a working local file with one that will not compile.
		if type(body) == 'string' and body ~= '' and rel:match('%.lua$') then
			local compiler = loadstring or load
			if type(compiler) == 'function' and not compiler(body, rel) then
				say('skipped (does not compile): ' .. rel)
				body = nil
			end
		end
		if type(body) == 'string' and body ~= '' and MERGE_LINES[rel] then
			body = mergeLines(rel, body)
		end
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
