from pathlib import Path

path = Path(r"C:\Users\Revi\Documents\playertools\PlayerTools\PlayerTools_Obsidian.lua")
lines = path.read_text(encoding="utf-8").splitlines()

FLOOR_LOADER = [
	"\t\tdo",
	"\t\t\tlocal compile = loadstring or load",
	"\t\t\tfor _, modPath in ipairs({ 'PlayerTools/AutoFloorDodge.lua', 'AutoFloorDodge.lua' }) do",
	"\t\t\t\tif type(isfile) == 'function' and isfile(modPath) and type(readfile) == 'function' then",
	"\t\t\t\t\tlocal src = readfile(modPath)",
	"\t\t\t\t\tif type(src) == 'string' and src ~= '' then",
	"\t\t\t\t\t\tlocal fn, err = compile(src, modPath)",
	"\t\t\t\t\t\tif fn then",
	"\t\t\t\t\t\t\tlocal ok, runErr = pcall(fn, {",
	"\t\t\t\t\t\t\t\tCombatBox = CombatBox,",
	"\t\t\t\t\t\t\t\tRunService = RunService,",
	"\t\t\t\t\t\t\t\tLocalPlayer = LocalPlayer,",
	"\t\t\t\t\t\t\t\tToggles = Toggles,",
	"\t\t\t\t\t\t\t\tisToggleOn = isToggleOn,",
	"\t\t\t\t\t\t\t\tisLocalAlive = isLocalAlive,",
	"\t\t\t\t\t\t\t\tgetMyCharacterModel = getMyCharacterModel,",
	"\t\t\t\t\t\t\t})",
	"\t\t\t\t\t\t\tif ok then",
	"\t\t\t\t\t\t\t\tbreak",
	"\t\t\t\t\t\t\tend",
	"\t\t\t\t\t\t\twarn('[AutoFloorDodge] init failed: ', runErr)",
	"\t\t\t\t\t\telse",
	"\t\t\t\t\t\t\twarn('[AutoFloorDodge] compile failed: ', err)",
	"\t\t\t\t\t\tend",
	"\t\t\t\t\tend",
	"\t\t\t\tend",
	"\t\t\tend",
	"\t\tend",
]

WAVE_LOADER = [
	"\t\tdo",
	"\t\t\tlocal compile = loadstring or load",
	"\t\t\tfor _, modPath in ipairs({ 'PlayerTools/WaveKillTarget.lua', 'WaveKillTarget.lua' }) do",
	"\t\t\t\tif type(isfile) == 'function' and isfile(modPath) and type(readfile) == 'function' then",
	"\t\t\t\t\tlocal src = readfile(modPath)",
	"\t\t\t\t\tif type(src) == 'string' and src ~= '' then",
	"\t\t\t\t\t\tlocal fn, err = compile(src, modPath)",
	"\t\t\t\t\t\tif fn then",
	"\t\t\t\t\t\t\tlocal ok, runErr = pcall(fn, {",
	"\t\t\t\t\t\t\t\tWdBox = WdBox,",
	"\t\t\t\t\t\t\t\tRunService = RunService,",
	"\t\t\t\t\t\t\t\tLibrary = Library,",
	"\t\t\t\t\t\t\t\tLocalPlayer = LocalPlayer,",
	"\t\t\t\t\t\t\t\tToggles = Toggles,",
	"\t\t\t\t\t\t\t\tisToggleOn = isToggleOn,",
	"\t\t\t\t\t\t\t\tgetMyCharacterModel = getMyCharacterModel,",
	"\t\t\t\t\t\t\t\tgetMyBringPart = getMyBringPart,",
	"\t\t\t\t\t\t\t})",
	"\t\t\t\t\t\t\tif ok then",
	"\t\t\t\t\t\t\t\tbreak",
	"\t\t\t\t\t\t\tend",
	"\t\t\t\t\t\t\twarn('[WaveKillTarget] init failed: ', runErr)",
	"\t\t\t\t\t\telse",
	"\t\t\t\t\t\t\twarn('[WaveKillTarget] compile failed: ', err)",
	"\t\t\t\t\t\tend",
	"\t\t\t\t\tend",
	"\t\t\t\tend",
	"\t\t\tend",
	"\t\tend",
]

# 1-based line ranges to replace (inclusive)
replacements = [
	(11789, 11894, FLOOR_LOADER),
	(17082, 17724, WAVE_LOADER),
]

# apply bottom-up so line numbers stay valid
replacements.sort(key=lambda x: x[0], reverse=True)
for start, end, insert in replacements:
	lines[start - 1 : end] = insert

path.write_text("\n".join(lines) + "\n", encoding="utf-8")
print("patched", path)
