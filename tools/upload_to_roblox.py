#!/usr/bin/env python3
"""upload_to_roblox.py — upload images to Roblox via the Open Cloud Assets API
and print a {stem: assetId} JSON map (the keys SkinAssets.luau / SoundAssets.luau
expect).

This is the missing step between /Sprites (PNGs) and the game: a Roblox
Decal/ImageLabel needs an rbxassetid, which only exists after an upload. Studio's
Asset Manager "Bulk Import" does the same thing by hand; this does ~250 files
unattended and hands you the id map to paste in.

Setup:
  pip install requests
  - Create an Open Cloud API key (create.roblox.com -> Creator Hub -> Open Cloud
    -> API Keys) with the **assets** API, Read + Write, and add your IP range.
  - Note your creator id: your user id, or a group id if the assets belong to a
    group. Assets you upload are owned by that creator.

Usage:
  export ROBLOX_API_KEY=...                      # or pass --api-key
  python tools/upload_to_roblox.py "Sprites/Frogs" --recursive \\
      --creator-id 1234567 --creator-type user -o sprite_ids.json
  # also emit a paste-ready Lua snippet of the id table:
  python tools/upload_to_roblox.py Sprites/Other --pattern "*.png" \\
      --creator-id 1234567 --lua-out sprite_ids.lua

Then drop the ids into src/shared/SkinAssets.luau (images) or SoundAssets.luau
(audio), keyed by stem. Keys are file stems, so HotFrogBody.png -> "HotFrogBody",
matching SkinAssets.part("Hot Frog", "Body").

Notes:
  - Images are uploaded as assetType "Decal"; the returned id works in
    Decal.Texture / ImageLabel.Image. Uploaded assets go through Roblox
    moderation -- a freshly returned id may render blank until approved.
  - Uploads are sequential with a small delay to stay under rate limits; failed
    files get "" in the map so you can re-run just those.
  - Only your account/group can be the creator; there is no anonymous upload
    (unlike catbox). Never commit your API key.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from pathlib import Path

import requests

ASSETS_URL = "https://apis.roblox.com/assets/v1/assets"
OPERATION_URL = "https://apis.roblox.com/assets/v1/operations/{}"

MIME_BY_SUFFIX = {
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".bmp": "image/bmp",
    ".tga": "image/tga",
}


def collect_files(inputs: list[Path], pattern: str, recursive: bool) -> list[Path]:
    files: list[Path] = []
    seen: set[Path] = set()
    for raw in inputs:
        if raw.is_file():
            candidates = [raw]
        elif raw.is_dir():
            glob = f"**/{pattern}" if recursive else pattern
            candidates = sorted(p for p in raw.glob(glob) if p.is_file())
        else:
            print(f"[skip] not found: {raw}", file=sys.stderr)
            continue
        for path in candidates:
            resolved = path.resolve()
            if resolved not in seen and path.suffix.lower() in MIME_BY_SUFFIX:
                seen.add(resolved)
                files.append(path)
    return files


def upload(path: Path, api_key: str, creator_field: str, creator_id: str) -> str:
    """Upload one image and return its asset id (raises on failure)."""
    request = {
        "assetType": "Decal",
        "displayName": path.stem,
        "description": "HotFrog sprite",
        "creationContext": {"creator": {creator_field: creator_id}},
    }
    mime = MIME_BY_SUFFIX[path.suffix.lower()]
    with path.open("rb") as fh:
        resp = requests.post(
            ASSETS_URL,
            headers={"x-api-key": api_key},
            data={"request": json.dumps(request)},
            files={"fileContent": (path.name, fh, mime)},
            timeout=120,
        )
    resp.raise_for_status()
    operation_id = resp.json().get("operationId") or resp.json().get("path", "").split("/")[-1]
    if not operation_id:
        raise RuntimeError(f"no operationId in response: {resp.text!r}")

    # poll the operation until the asset is created
    for _ in range(30):
        time.sleep(1.0)
        op = requests.get(
            OPERATION_URL.format(operation_id),
            headers={"x-api-key": api_key},
            timeout=60,
        )
        op.raise_for_status()
        body = op.json()
        if body.get("done"):
            asset_id = body.get("response", {}).get("assetId")
            if not asset_id:
                raise RuntimeError(f"operation done but no assetId: {body!r}")
            return str(asset_id)
    raise RuntimeError("timed out waiting for the upload operation")


def main() -> int:
    ap = argparse.ArgumentParser(
        prog="upload_to_roblox.py",
        description="Upload images to Roblox (Open Cloud) and print a {stem: assetId} map.",
    )
    ap.add_argument("inputs", nargs="+", type=Path, help="Image files and/or directories.")
    ap.add_argument("--api-key", default=os.environ.get("ROBLOX_API_KEY"), help="Open Cloud key (or $ROBLOX_API_KEY).")
    ap.add_argument("--creator-id", required=True, help="Owning user id or group id.")
    ap.add_argument("--creator-type", choices=("user", "group"), default="user")
    ap.add_argument("--pattern", default="*.png", help="Glob for directory inputs. Default: *.png")
    ap.add_argument("--recursive", action="store_true", help="Recurse into directory inputs.")
    ap.add_argument("--output", "-o", type=Path, default=None, help="Write the JSON map here.")
    ap.add_argument("--lua-out", type=Path, default=None, help="Also write a paste-ready Lua id table.")
    args = ap.parse_args()

    if not args.api_key:
        print("No API key: pass --api-key or set ROBLOX_API_KEY.", file=sys.stderr)
        return 2

    creator_field = "userId" if args.creator_type == "user" else "groupId"
    files = collect_files(args.inputs, args.pattern, args.recursive)
    if not files:
        print("No matching image files to upload.", file=sys.stderr)
        return 1

    results: dict[str, str] = {}
    failed = 0
    for i, path in enumerate(files, 1):
        try:
            asset_id = upload(path, args.api_key, creator_field, args.creator_id)
            results[path.stem] = asset_id
            print(f"[{i}/{len(files)}] {path.name} -> {asset_id}", file=sys.stderr)
        except Exception as e:
            failed += 1
            results[path.stem] = ""
            print(f"[{i}/{len(files)}] {path.name} FAILED: {e}", file=sys.stderr)
        time.sleep(0.5)  # gentle on the rate limit

    payload = json.dumps(results, indent=2, sort_keys=True)
    if args.output:
        args.output.write_text(payload)
        print(f"Wrote {args.output}", file=sys.stderr)
    else:
        print(payload)

    if args.lua_out:
        lines = [f"\t{stem} = {aid or 0}," for stem, aid in sorted(results.items())]
        args.lua_out.write_text("-- paste into the Ids table of SkinAssets.luau / SoundAssets.luau\n" + "\n".join(lines) + "\n")
        print(f"Wrote {args.lua_out}", file=sys.stderr)

    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
