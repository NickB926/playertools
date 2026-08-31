# PlayerTools — GitHub updates (Neuublue-style)

Friends install / update with one line in their executor:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/NickB926/playertools/main/bootstrap.lua"))()
```

## How it works

1. `bootstrap.lua` downloads `PlayerTools/Updater.lua`
2. Updater reads `version.json` from this repo
3. Listed files are written into the executor `PlayerTools/` folder
4. `launch.lua` starts as usual

Each person keeps **their own** Hive tribute webhook + Discord ping under:
`PlayerTools/hive/tribute_webhook_<robloxUserId>.json`

## Publish a new update (you)

From Windows (this machine):

```powershell
cd C:\Users\Revi\Documents\playertools
.\Publish-PlayerTools.ps1
```

Or bump + push manually:

1. Edit files under `C:\Users\Revi\AppData\Local\Potassium\scripts\PlayerTools`
2. Bump `version` in `PlayerTools/version.json`
3. Run the publish script (copies into the git repo and pushes `main`)

## Visibility

Raw `HttpGet` only works if the repo is **public**, or friends use a token (awkward).
For Neuublue-style sharing, make the repo public when you're ready:

```powershell
gh repo edit NickB926/playertools --visibility public
```

Until then, add friends as collaborators on the private repo and have them clone, or temporarily publish.
