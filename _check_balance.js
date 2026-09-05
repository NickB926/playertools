const fs = require('fs')
const path = require('path')
const files = [
	'C:/Users/Revi/AppData/Local/Potassium/scripts/PlayerTools/AtaraxiaLibrary.lua',
	'C:/Users/Revi/AppData/Local/Potassium/scripts/PlayerTools/HiveMind.lua',
	'C:/Users/Revi/AppData/Local/Potassium/scripts/PlayerTools/ClearCharItems.iy',
	'C:/Users/Revi/AppData/Local/Potassium/scripts/PlayerTools/PlayerTools_Obsidian.lua',
	'C:/Users/Revi/AppData/Local/Potassium/scripts/PlayerTools/launch.lua',
]
for (const f of files) {
	let s = fs.readFileSync(f, 'utf8')
	s = s.replace(/--\[\[[\s\S]*?\]\]/g, '')
	s = s.replace(/--[^\n]*/g, '')
	s = s.replace(/\[[=]*\[[\s\S]*?\][=]*\]/g, '""')
	s = s.replace(/"(?:\\.|[^"\\])*"/g, '""')
	s = s.replace(/'(?:\\.|[^'\\])*'/g, "''")
	const count = (re) => (s.match(re) || []).length
	const funcs = count(/\bfunction\b/g)
	const ends = count(/\bend\b/g)
	const dos = count(/\bdo\b/g)
	const thens = count(/\bthen\b/g)
	const repeats = count(/\brepeat\b/g)
	const untils = count(/\buntil\b/g)
	const open = funcs + dos + thens + repeats
	const close = ends + untils
	console.log(path.basename(f), { funcs, ends, dos, thens, repeats, untils, open, close, delta: open - close })
}
