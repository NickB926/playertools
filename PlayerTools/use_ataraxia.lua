-- use_ataraxia.lua — pin backend to Ataraxia chrome and reload PlayerTools
if type(makefolder) == 'function' and type(isfolder) == 'function' then
	if not isfolder('PlayerTools') then
		pcall(makefolder, 'PlayerTools')
	end
end
if type(writefile) == 'function' then
	writefile('PlayerTools/backend', 'ataraxia')
end
getgenv().SB2UseAtaraxiaLib = true
warn('[PlayerTools] backend=ataraxia — run PlayerTools/PlayerTools.lua or Ataraxia.lua')
