#!/usr/bin/env python3
"""create_gamepasses.py - create the HotFrog premium-skin Game Passes through
Open Cloud, resumably.

Reuses passes that already exist on the experience (matched by name), creates
the rest, and writes each real id over `gamePassId = 0` on exactly the matching
rows of src/shared/SkinCatalog.luau. Cache: tools/gamepass_ids.json.
Creating a pass costs nothing.

Needs ROBLOX_UNIVERSE_ID and ROBLOX_API_KEY in .env, the key carrying the
Game Passes API system with read + write permission for this experience.

  python tools/create_gamepasses.py [--dry-run]
"""
from __future__ import annotations

import argparse
import io
import json
import os
import re
import sys
from pathlib import Path

import requests
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import roblox_web as w  # noqa: E402

# Skin name -> Robux price. Edit freely.
PRICES: dict[str, int] = {
    "Business Frog": 99,
    "Hot Lawyer": 149,
    "Invisible Man": 199,
    "Crossy Frog": 249,
}

CATALOG = w.REPO_ROOT / "src" / "shared" / "SkinCatalog.luau"
CACHE = w.REPO_ROOT / "tools" / "gamepass_ids.json"
BASE = "https://apis.roblox.com/game-passes/v1/universes"
ROW = re.compile(r'^(.*name = "([^"]+)".*?gamePassId = )(\d+)(.*)$')


def icon_png(skin: str) -> bytes:
    path = w.REPO_ROOT / "Sprites" / "Frogs" / skin / f"{skin.replace(' ', '')}Body.png"
    img = Image.open(path).convert("RGBA")
    img.thumbnail((448, 448), Image.LANCZOS)
    canvas = Image.new("RGBA", (512, 512), (40, 120, 50, 255))
    canvas.alpha_composite(img, ((512 - img.width) // 2, (512 - img.height) // 2))
    out = io.BytesIO()
    canvas.save(out, "PNG")
    return out.getvalue()


def save(cache: dict[str, int], dry_run: bool = False) -> None:
    if dry_run:
        return
    CACHE.write_text(json.dumps(cache, indent=1))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    w.load_env_file()
    uni, key = os.environ.get("ROBLOX_UNIVERSE_ID"), os.environ.get("ROBLOX_API_KEY")
    if not uni or not key:
        print("need ROBLOX_UNIVERSE_ID and ROBLOX_API_KEY in .env")
        return 1
    headers = {"x-api-key": key}

    cache: dict[str, int] = json.loads(CACHE.read_text()) if CACHE.exists() else {}
    token = ""
    try:
        while True:
            r = requests.get(
                f"{BASE}/{uni}/game-passes/creator",
                headers=headers,
                params={"pageSize": 100, "pageToken": token},
                timeout=30,
            )
            if r.status_code in (401, 403):
                print(
                    f"STOP: HTTP {r.status_code} listing passes. Add the Game Passes API system "
                    "(read + write) for this experience to the key in Creator Hub > Open Cloud > API Keys."
                )
                print(r.text[:300])
                return 2
            r.raise_for_status()
            page = r.json()
            for p in page.get("gamePasses", page.get("data", [])):
                pid = p.get("gamePassId", p.get("id"))
                if p.get("name") and pid:
                    cache.setdefault(p["name"], int(pid))
            token = page.get("nextPageToken") or ""
            if not token:
                break
    except (requests.RequestException, ValueError) as e:
        print(f"abort: could not list existing passes ({e}); nothing created")
        return 1

    for name, price in PRICES.items():
        if name in cache:
            continue
        if args.dry_run:
            print(f"would create {name!r} at {price} Robux")
            continue
        try:
            r = requests.post(
                f"{BASE}/{uni}/game-passes",
                headers=headers,
                data={
                    "name": name,
                    "description": f"Permanently unlock the {name} skin in HotFrog.",
                    "isForSale": "true",
                    "price": str(price),
                },
                files={"imageFile": ("icon.png", icon_png(name), "image/png")},
                timeout=60,
            )
        except requests.RequestException as e:
            print(f"STOP at {name!r}: network error ({e})")
            break
        if r.ok:
            try:
                body = r.json()
                cache[name] = int(body.get("gamePassId", body.get("id")))
            except (ValueError, TypeError, AttributeError):
                print(f"STOP at {name!r}: unexpected create response {r.text[:300]}")
                break
            print(f"created {name!r} -> {cache[name]}")
            save(cache)
        else:
            print(f"STOP at {name!r}: HTTP {r.status_code} {r.text[:300]}")
            break
    save(cache, args.dry_run)

    out = []
    for ln in CATALOG.read_text(encoding="utf-8").split("\n"):
        m = ROW.match(ln)
        if m and m.group(2) in PRICES and m.group(2) in cache:
            ln = f"{m.group(1)}{cache[m.group(2)]}{m.group(4)}"
        out.append(ln)
    if not args.dry_run:
        with open(CATALOG, "w", encoding="utf-8", newline="\n") as f:
            f.write("\n".join(out))
    print(f"{sum(n in cache for n in PRICES)}/{len(PRICES)} passes have ids")
    return 0


if __name__ == "__main__":
    sys.exit(main())
