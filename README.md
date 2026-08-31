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

Same flow as discord-lite — from Windows:

```powershell
cd C:\Users\Revi\Documents\playertools
npm run publish:updates
```

Or double-click `publish-updates.bat`.

That auto-bumps `1.0.0` → `1.0.1`, copies from Potassium `scripts/PlayerTools`, commits, and pushes `main`.

Optional:

```powershell
npm run publish:updates -- -Message "tribute ping fix"
npm run publish:updates -- -Version 1.2.0 -Message "big drop"
npm run publish:updates:skip-bump
```

## Tribute webhook ping (you or a friend)

1. Discord → create a webhook in **your** channel → copy URL  
2. Discord → Settings → Advanced → **Developer Mode** ON → right-click **your** username → **Copy User ID**  
3. In PlayerTools → Hive → paste webhook URL + that Discord user ID → enable **Webhook: Tribute drops**  

Each Roblox account stores its own config (`hive/tribute_webhook_<userId>.json`). Friend uses **his** webhook + **his** Discord ID so he gets pinged, not you.
## Visibility

Raw `HttpGet` only works if the repo is **public**, or friends use a token (awkward).
For Neuublue-style sharing, make the repo public when you're ready:

```powershell
gh repo edit NickB926/playertools --visibility public
```

Until then, add friends as collaborators on the private repo and have them clone, or temporarily publish.
