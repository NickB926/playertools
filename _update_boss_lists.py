import json
import re
from pathlib import Path

ROOT = Path(r"C:\Users\Revi\Documents\playertools")
bosses = json.loads(
    Path(r"C:\Users\Revi\Documents\sb2-wiki\_bosses_from_locations.json").read_text(
        encoding="utf-8"
    )
)["all"]

junk = {"Chests", "Azured Bastion Shield"}
extra = [
    "Terror Incarnatus, The Eldritch Unbound",
    "Saurus the All-Seeing",
    "Panku",
    "Pan Ku, Chaos-born",
    "BOB",
    "Bob",
    "Hunter",
    "Wa, the Curious",
    "Guardian's Vessel",
]

names = []
seen = set()
for n in bosses + extra:
    if n in junk:
        continue
    key = n.casefold()
    if key in seen:
        continue
    seen.add(key)
    names.append(n)
names = sorted(names, key=lambda s: s.casefold())
print("boss count", len(names))


def fmt_list(items, indent):
    out = []
    for n in items:
        if "'" in n:
            out.append(f'{indent}"{n}",')
        else:
            out.append(f"{indent}'{n}',")
    return "\n".join(out)


def replace_list(src, varname, body, indent_close):
    pat = re.compile(rf"(local {varname} = \{{\n)(.*?)(\n{indent_close}\}})", re.S)
    m = pat.search(src)
    if not m:
        raise SystemExit(f"miss {varname}")
    return src[: m.start()] + m.group(1) + body + m.group(3) + src[m.end() :]


kill_block = fmt_list(names, "\t")
combat_block = fmt_list(names, "\t\t")

obs = ROOT / "PlayerTools" / "PlayerTools_Obsidian.lua"
s = obs.read_text(encoding="utf-8")
s = replace_list(s, "BOSS_KILL_NAME_LIST", kill_block, "\t")
s = replace_list(s, "BOSS_NAME_LIST", combat_block, "\t\t")
obs.write_text(s, encoding="utf-8")
print("Obsidian updated")

ed = ROOT / "PlayerTools" / "PlayerTools_event_dive.lua"
if ed.exists():
    e = ed.read_text(encoding="utf-8")
    if "BOSS_NAME_LIST" in e:
        e = replace_list(e, "BOSS_NAME_LIST", combat_block, "\t\t")
        ed.write_text(e, encoding="utf-8")
        print("event_dive updated")

ver = """{
    "version":  "1.0.23",
    "message":  "Boss kills: full Locations/Mobs/Drops boss + miniboss list",
    "files":  [
                  "Ataraxia.lua",
                  "PlayerTools/launch.lua",
                  "PlayerTools/PlayerTools.lua",
                  "PlayerTools/init.lua",
                  "PlayerTools/Updater.lua",
                  "PlayerTools/HiveMind.lua",
                  "PlayerTools/PlayerTools_Obsidian.lua",
                  "PlayerTools/PlayerTools_Starlight.lua",
                  "PlayerTools/PlayerTools_event_dive.lua",
                  "PlayerTools/StarlightAdapter.lua",
                  "PlayerTools/AtaraxiaLibrary.lua",
                  "PlayerTools/TagWiki.lua",
                  "PlayerTools/Titling.lua",
                  "PlayerTools/PillDock.lua",
                  "PlayerTools/AutoBlock.iy",
                  "PlayerTools/ServerHop.iy",
                  "PlayerTools/KeepPlayerTools.iy",
                  "PlayerTools/KeepServerHop.iy",
                  "PlayerTools/JoinLogs.iy",
                  "PlayerTools/Waypoints.iy",
                  "PlayerTools/Tracers.iy",
                  "PlayerTools/CCI.iy",
                  "PlayerTools/ClearCharItems.iy",
                  "PlayerTools/StuckLoadRejoin.iy",
                  "PlayerTools/AutoHideIY.iy",
                  "PlayerTools/backend",
                  "PlayerTools/use_obsidian.lua",
                  "PlayerTools/use_ataraxia.lua",
                  "PlayerTools/version.json"
              ]
}
"""
(ROOT / "version.json").write_text(ver, encoding="utf-8")
(ROOT / "PlayerTools" / "version.json").write_text(ver, encoding="utf-8")
print("version 1.0.23")
print("has Dire Wolf", "Dire Wolf" in s)
print("has Aeganatos", "Aeganatos" in s)
print("has Tworz", "Tworz" in s)
