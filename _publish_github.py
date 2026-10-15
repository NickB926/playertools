"""Upload selected files to NickB926/playertools main via Contents API."""
from __future__ import annotations

import base64
import json
import subprocess
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(r"C:\Users\Revi\Documents\playertools")
REPO = "NickB926/playertools"
FILES = [
    "PlayerTools/PlayerTools_Obsidian.lua",
    "PlayerTools/PlayerTools_event_dive.lua",
    "PlayerTools/version.json",
    "version.json",
    "Ataraxia.lua",
]
MESSAGE = "PlayerTools 1.0.23: full Locations/Mobs/Drops boss list for Boss kills"


def token() -> str:
    out = subprocess.check_output(["gh", "auth", "token"], text=True).strip()
    if not out:
        raise SystemExit("no gh token")
    return out


def api(method: str, path: str, tok: str, data: dict | None = None):
    url = f"https://api.github.com{path}"
    body = None if data is None else json.dumps(data).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=body,
        method=method,
        headers={
            "Authorization": f"Bearer {tok}",
            "Accept": "application/vnd.github+json",
            "User-Agent": "PlayerToolsPublish/1.0",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=180) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        err = e.read().decode("utf-8", errors="replace")
        raise SystemExit(f"{method} {path} -> {e.code}: {err[:500]}") from e


def main():
    tok = token()
    for rel in FILES:
        local = ROOT / rel
        if not local.exists():
            print("skip missing", rel)
            continue
        meta = None
        try:
            meta = api("GET", f"/repos/{REPO}/contents/{rel}?ref=main", tok)
        except SystemExit as e:
            if "404" not in str(e):
                raise
        sha = meta.get("sha") if isinstance(meta, dict) else None
        raw = local.read_bytes()
        payload = {
            "message": MESSAGE if rel.endswith("Obsidian.lua") else f"PlayerTools 1.0.23: {rel}",
            "content": base64.b64encode(raw).decode("ascii"),
            "branch": "main",
        }
        if sha:
            payload["sha"] = sha
        res = api("PUT", f"/repos/{REPO}/contents/{rel}", tok, payload)
        print(rel, "->", res.get("commit", {}).get("sha", "")[:7])


if __name__ == "__main__":
    main()
