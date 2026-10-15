from pathlib import Path

root = Path(r"C:\Users\Revi\Documents\playertools\PlayerTools")
obs = (root / "PlayerTools_Obsidian.lua").read_text(encoding="utf-8").splitlines()


def extract(start_line, end_line, header_extra, env_setup):
    block = obs[start_line - 1 : end_line]
    body = []
    for line in block:
        if line.startswith("\t\t"):
            body.append("\t" + line[2:])
        else:
            body.append(line)
    header = (
        "--[[\n"
        "\tSplit from PlayerTools_Obsidian.lua (Luau 200-local register cap).\n"
        "]]\n"
        f"{header_extra}\n\n"
        "return function(env)\n"
    )
    return header + env_setup + "\n".join(body) + "\nend\n"


wk_env = (
    "\tlocal WdBox = env.WdBox\n"
    "\tlocal RunService = env.RunService\n"
    "\tlocal Library = env.Library\n"
    "\tlocal LocalPlayer = env.LocalPlayer\n"
    "\tlocal Toggles = env.Toggles\n"
    "\tlocal isToggleOn = env.isToggleOn\n"
    "\tlocal getMyCharacterModel = env.getMyCharacterModel\n"
    "\tlocal getMyBringPart = env.getMyBringPart\n"
    "\tassert(WdBox, 'WaveKillTarget: WdBox required')\n"
)
fd_env = (
    "\tlocal CombatBox = env.CombatBox\n"
    "\tlocal RunService = env.RunService\n"
    "\tlocal LocalPlayer = env.LocalPlayer\n"
    "\tlocal Toggles = env.Toggles\n"
    "\tlocal isToggleOn = env.isToggleOn\n"
    "\tlocal isLocalAlive = env.isLocalAlive\n"
    "\tlocal getMyCharacterModel = env.getMyCharacterModel\n"
    "\tassert(CombatBox, 'AutoFloorDodge: CombatBox required')\n"
)

(root / "WaveKillTarget.lua").write_text(
    extract(17082, 17724, "getgenv().SB2WaveKillBuild = 'wave-kill-phantom-v3'", wk_env),
    encoding="utf-8",
)
(root / "AutoFloorDodge.lua").write_text(
    extract(11789, 11894, "getgenv().SB2AutoFloorDodgeBuild = 'floor-dodge-v2'", fd_env),
    encoding="utf-8",
)
print("ok")
