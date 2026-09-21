#!/usr/bin/env python3
"""list_assets.py — list the account's (or a group's) assets from the Roblox
Asset Manager as a markdown table. Ported from the `scare` project.

Use it to verify what actually landed on Roblox after an upload run, or to
recover ids if tools/asset_ids.json is ever lost.

Setup:
  ROBLOSECURITY in .env (the logged-in .ROBLOSECURITY cookie — see
  tools/roblox_web.py for where to get it). This is a website API; the Open
  Cloud API key does not work here.

Usage:
  python tools/list_assets.py                    # all asset types to stdout
  python tools/list_assets.py -t Image           # images only
  python tools/list_assets.py -t Image -t Audio  # multiple types
  python tools/list_assets.py -o assets.md       # write to file
  python tools/list_assets.py --limit 50         # cap at 50 assets
  python tools/list_assets.py --group-id 12345   # list group assets

Asset types: Image, Audio, Decal, Model, Mesh, MeshPart, Animation, TShirt
"""

from __future__ import annotations

import argparse
import sys
import time
from datetime import datetime

import requests

import roblox_web

ASSET_TYPES = ["Image", "Audio", "Decal", "Model", "Mesh", "MeshPart", "Animation", "TShirt"]
BASE_URL = "https://itemconfiguration.roblox.com/v1/creations/get-assets"


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(description="List Roblox Asset Manager assets as a markdown table.")
    ap.add_argument("--type", "-t", dest="types", action="append", metavar="TYPE", help=f"Asset type filter (repeatable). Options: {', '.join(ASSET_TYPES)}. Default: all.")
    ap.add_argument("--group-id", type=int, default=None, help="List assets owned by this group instead of your account.")
    ap.add_argument("--limit", type=int, default=None, help="Max total assets to fetch. Default: unlimited.")
    ap.add_argument("--output", "-o", metavar="PATH", help="Write markdown to file instead of stdout.")
    ap.add_argument("--cookie", default=None, help=".ROBLOSECURITY cookie value (overrides $ROBLOSECURITY).")
    return ap.parse_args()


def create_session(cookie: str) -> requests.Session:
    session = requests.Session()
    session.headers.update({"User-Agent": roblox_web.WEB_USER_AGENT})
    session.cookies.set(".ROBLOSECURITY", cookie, domain=".roblox.com")
    return session


def list_assets(session: requests.Session, asset_type: str, group_id: int | None = None, limit: int | None = None) -> list[dict]:
    assets: list[dict] = []
    cursor = None
    while True:
        params: dict = {"assetType": asset_type, "isArchived": "false", "limit": 100}
        if group_id:
            params["groupId"] = group_id
        if cursor:
            params["cursor"] = cursor
        try:
            resp = session.get(BASE_URL, params=params, timeout=60)
        except requests.ConnectionError:
            print(f"  Connection error fetching {asset_type} assets.", file=sys.stderr)
            break
        if resp.status_code == 401:
            sys.exit("Error: authentication failed. The cookie may be invalid or expired.")
        if resp.status_code == 403:
            print(f"  403 Forbidden for {asset_type} — skipping.", file=sys.stderr)
            break
        if resp.status_code == 429:
            print("  Rate limited — waiting 5s...", file=sys.stderr)
            time.sleep(5)
            continue
        if resp.status_code != 200:
            print(f"  Unexpected status {resp.status_code} for {asset_type} — skipping.", file=sys.stderr)
            break
        data = resp.json()
        assets.extend(data.get("data", []))
        if limit and len(assets) >= limit:
            assets = assets[:limit]
            break
        cursor = data.get("nextPageCursor")
        if not cursor:
            break
        time.sleep(0.5)
    return assets


def format_markdown(assets_by_type: dict[str, list[dict]]) -> str:
    lines = ["# Roblox Asset Inventory", f"> Generated {datetime.now().strftime('%Y-%m-%d %H:%M')} by `tools/list_assets.py`", ""]
    total = 0
    for asset_type, assets in assets_by_type.items():
        if not assets:
            continue
        total += len(assets)
        lines += [f"## {asset_type}", "", "| Name | Asset ID | rbxassetid |", "|------|----------|------------|"]
        for a in sorted(assets, key=lambda x: x.get("name", "")):
            asset_id = a.get("assetId", "?")
            lines.append(f"| {a.get('name', 'Untitled')} | {asset_id} | rbxassetid://{asset_id} |")
        lines.append("")
    if total == 0:
        lines += ["*No assets found.*", ""]
    lines.append(f"**Total: {total} assets**")
    return "\n".join(lines)


def main() -> int:
    args = parse_args()
    cookie = roblox_web.resolve_cookie(args.cookie)
    if not cookie:
        sys.exit("Error: no .ROBLOSECURITY cookie. Set ROBLOSECURITY in .env or pass --cookie.")
    session = create_session(cookie)

    types_to_fetch = list(args.types or ASSET_TYPES)
    for t in types_to_fetch:
        if t not in ASSET_TYPES:
            print(f"Warning: unknown asset type '{t}'. Known: {', '.join(ASSET_TYPES)}", file=sys.stderr)

    print(f"Fetching assets for types: {', '.join(types_to_fetch)}...", file=sys.stderr)
    assets_by_type: dict[str, list[dict]] = {}
    remaining = args.limit
    for asset_type in types_to_fetch:
        print(f"  {asset_type}...", file=sys.stderr, end=" ", flush=True)
        assets = list_assets(session, asset_type, args.group_id, remaining if remaining else None)
        assets_by_type[asset_type] = assets
        print(f"{len(assets)} found", file=sys.stderr)
        if remaining:
            remaining -= len(assets)
            if remaining <= 0:
                break

    md = format_markdown(assets_by_type)
    if args.output:
        with open(args.output, "w", encoding="utf-8") as f:
            f.write(md)
        print(f"\nWritten to {args.output}", file=sys.stderr)
    else:
        print(md)
    return 0


if __name__ == "__main__":
    sys.exit(main())
