#!/usr/bin/env python3
"""create_badges.py - create the HotFrog badges through Open Cloud, resumably.

Reads the entries (name) from src/shared/Badges.luau, reuses badges that
already exist on the experience (matched by name), creates the rest, and
writes each real id over `id = 0` in Badges.luau. Cache: tools/badge_ids.json.

NEVER spends Robux: every create sends expectedCost=0; on a non-free /
over-quota response it stops (re-run on a later day to finish the rest).

Needs ROBLOX_UNIVERSE_ID and ROBLOX_API_KEY in .env, the key carrying the
legacy-universe.badge scopes (read, write, manage-and-spend-robux).

  python tools/create_badges.py [--dry-run] [--icon Sprites/Menu/FrogHeadIcon.png]
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

BADGES_LUAU = w.REPO_ROOT / "src" / "shared" / "Badges.luau"
CACHE = w.REPO_ROOT / "tools" / "badge_ids.json"
ROW = re.compile(r'^(\s*\{.*?)id = (\d+)(, name = "([^"]+)" \},?)\s*$')


def describe(name: str) -> str:
    m = re.match(r"(\d+) Steps!", name)
    if m:
        return f"Reach {m.group(1)} steps in a single run."
    m = re.match(r"(\d+)-Day Streak", name)
    if m:
        return f"Log in {m.group(1)} days in a row."
    return {
        "Out of the Pot": "Climb out of the pot and reach the Kitchen.",
        "Country Frog": "Reach the Country.",
        # Fly Jar tiers (src/shared/JarTiers.luau)
        "Fly Snacker": "Feed 1,000 Flys into the Fly Jar.",
        "Fly Keeper": "Feed 2,500 Flys into the Fly Jar.",
        "Swarm Tender": "Feed 5,000 Flys into the Fly Jar.",
        "Jar Master": "Feed 10,000 Flys into the Fly Jar.",
        "Fly Baron": "Feed 25,000 Flys into the Fly Jar.",
        "Lord of the Flies": "Feed 50,000 Flys into the Fly Jar.",
        "Frog Royalty": "Feed 100,000 Flys into the Fly Jar.",
    }.get(name, name)


def icon_png(path: Path) -> bytes:
    img = Image.open(path).convert("RGBA")
    img.thumbnail((448, 448), Image.LANCZOS)
    canvas = Image.new("RGBA", (512, 512), (40, 120, 50, 255))
    canvas.alpha_composite(img, ((512 - img.width) // 2, (512 - img.height) // 2))
    out = io.BytesIO()
    canvas.save(out, "PNG")
    return out.getvalue()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--icon", default="Sprites/Menu/FrogHeadIcon.png")
    args = ap.parse_args()
    w.load_env_file()
    uni, key = os.environ.get("ROBLOX_UNIVERSE_ID"), os.environ.get("ROBLOX_API_KEY")
    if not uni or not key:
        print("need ROBLOX_UNIVERSE_ID and ROBLOX_API_KEY in .env")
        return 1

    cache: dict[str, int] = json.loads(CACHE.read_text()) if CACHE.exists() else {}
    cursor = ""
    try:
        while True:
            r = requests.get(
                f"https://badges.roblox.com/v1/universes/{uni}/badges?limit=100&cursor={cursor}", timeout=30
            )
            r.raise_for_status()
            page = r.json()
            for b in page.get("data", []):
                cache.setdefault(b["name"], b["id"])
            cursor = page.get("nextPageCursor") or ""
            if not cursor:
                break
    except (requests.RequestException, ValueError) as e:
        print(f"abort: could not list existing badges ({e}); nothing created")
        return 1
    lines = BADGES_LUAU.read_text(encoding="utf-8").split("\n")
    names = [m.group(4) for ln in lines if (m := ROW.match(ln))]
    icon = icon_png(w.REPO_ROOT / args.icon)
    stop = False
    for name in names:
        if name in cache or stop:
            continue
        if args.dry_run:
            print(f"would create {name!r}: {describe(name)}")
            continue
        try:
            r = requests.post(
                f"https://apis.roblox.com/legacy-badges/v1/universes/{uni}/badges",
                headers={"x-api-key": key},
                data={"name": name, "description": describe(name), "paymentSourceType": "User", "expectedCost": "0"},
                files={"files": ("icon.png", icon, "image/png")},
                timeout=60,
            )
        except requests.RequestException as e:
            print(f"STOP at {name!r}: network error ({e})")
            stop = True
            CACHE.write_text(json.dumps(cache, indent=1))
            continue
        if r.ok:
            cache[name] = int(r.json()["id"])
            print(f"created {name!r} -> {cache[name]}")
        else:
            print(f"STOP at {name!r}: HTTP {r.status_code} {r.text[:300]}")
            stop = True
        CACHE.write_text(json.dumps(cache, indent=1))
    CACHE.write_text(json.dumps(cache, indent=1))

    out = []
    for ln in lines:
        m = ROW.match(ln)
        if m and m.group(4) in cache:
            ln = f"{m.group(1)}id = {cache[m.group(4)]}{m.group(3)}"
        out.append(ln)
    if not args.dry_run:
        with open(BADGES_LUAU, "w", encoding="utf-8", newline="\n") as f:
            f.write("\n".join(out))
    print(f"{sum(n in cache for n in names)}/{len(names)} badges have ids")
    return 0


if __name__ == "__main__":
    sys.exit(main())
