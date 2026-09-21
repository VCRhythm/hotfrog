#!/usr/bin/env python3
"""grant_audio_to_experience.py — add the HotFrog experience to the allow-list
of every uploaded sound, in one command. Ported from the `scare` project.

WHY THIS EXISTS
  Roblox audio is permission-gated per EXPERIENCE. Audio you own normally plays
  in experiences you own, and publishing usually auto-grants it — but stragglers
  stay silent (the Output window shows "Asset has not been reviewed" or a
  permissions error while the id itself is fine). When the game is published to
  a NEW experience id, every sound needs to be usable there; this tool bulk-grants
  them so you don't click through the Creator Dashboard per sound. Images are NOT
  gated (nothing to do for SkinAssets).

  Run it only if sounds stay silent after publishing — not as a routine step.

AUTH (same cookie as the website upload path in tools/roblox_web.py)
  - ROBLOSECURITY in .env: the .ROBLOSECURITY cookie of the account that OWNS
    the audio. The permissions endpoint is a first-party website API, not Open
    Cloud, so ROBLOX_API_KEY does NOT work here.
  - The target experience must be owned by that same account.

  VERIFY-BEFORE-TRUST: PERMISSIONS_URL / build_grant_body / DEFAULT_ACTION
  mirror the Creator Dashboard's private "add experience" call as reconstructed
  on scare. Roblox can change the shape. Smoke test first: grant ONE sound
  (`--apply --limit 1`), confirm it appears under that sound's Permissions in
  the Creator Dashboard, THEN run the batch. If the shape is off it is a
  one-line change in those constants.

WHERE THE SOUND IDS COME FROM
  The union of every audio `assetId` in tools/asset_ids.json (the upload cache)
  and every non-zero id in src/shared/SoundAssets.luau (in case ids were pasted
  by hand). Either file may be missing.

USAGE
  python tools/grant_audio_to_experience.py --list                      # what would be granted; no network
  python tools/grant_audio_to_experience.py                             # dry run against $ROBLOX_UNIVERSE_ID
  python tools/grant_audio_to_experience.py --apply --limit 1           # smoke test one sound
  python tools/grant_audio_to_experience.py --apply                     # grant all (resume-safe)
  python tools/grant_audio_to_experience.py --verify-one 123456789      # read back one sound's permissions

  --universe-id defaults to ROBLOX_UNIVERSE_ID from .env (the experience's
  UNIVERSE id: Creator Dashboard -> experience -> "..." -> Copy Universe ID, or
  game.GameId in-game). It is NOT the place id.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import time
from pathlib import Path

import roblox_web

REPO = Path(__file__).resolve().parent.parent
DEFAULT_IDS_CACHE = REPO / "tools" / "asset_ids.json"
DEFAULT_SOUND_ASSETS = REPO / "src" / "shared" / "SoundAssets.luau"
DEFAULT_TRACKING = REPO / "tools" / ".asset_cache" / "audio_experience_grants.json"

# ── The three values to VERIFY against a live universe (see module docstring) ──
PERMISSIONS_URL = "https://apis.roblox.com/asset-permissions-api/v1/assets/{asset_id}/permissions"
SUBJECT_TYPE = "Universe"  # grant to the whole experience, not a single place
DEFAULT_ACTION = "Use"  # audio permission verb; some flows use "Play" (--action)

LUAU_ID_RE = re.compile(r"^\s*\w+\s*=\s*(\d+)\s*,", re.MULTILINE)
MAX_CONSECUTIVE_FAILURES = 5  # bail on a systemic problem (expired cookie / wrong endpoint)


def extract_sound_ids(ids_cache: Path, sound_assets: Path) -> list[int]:
    ids: set[int] = set()
    if ids_cache.exists():
        try:
            cache = json.loads(ids_cache.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            cache = {}
        for entry in cache.values():
            if isinstance(entry, dict) and entry.get("kind") == "audio" and entry.get("assetId"):
                ids.add(int(entry["assetId"]))
    if sound_assets.exists():
        text = sound_assets.read_text(encoding="utf-8")
        m = re.search(r"local Ids\s*:.*?=\s*\{(.*?)\n\}", text, re.DOTALL)
        body = m.group(1) if m else text
        ids.update(int(x) for x in LUAU_ID_RE.findall(body))
    ids.discard(0)
    return sorted(ids)


def build_grant_body(universe_id: int, action: str) -> bytes:
    """Payload that adds one universe to an audio asset's allow-list. VERIFY:
    mirrors the Creator Dashboard's private call; adjust here if Roblox rejects it."""
    return json.dumps({"requests": [{"subjectType": SUBJECT_TYPE, "subjectId": str(universe_id), "action": action}]}).encode("utf-8")


def grant_one(asset_id: int, universe_id: int, action: str, cookie: str, token: str) -> tuple[bool, str, str]:
    """Returns (ok, message, token) — the token may have been rotated by Roblox."""
    url = PERMISSIONS_URL.format(asset_id=asset_id)
    status, _, text, token = roblox_web.post_with_csrf_retry(url, cookie, token, build_grant_body(universe_id, action))
    if 200 <= status < 300:
        return True, f"HTTP {status}", token
    snippet = (text or "").strip().replace("\n", " ")[:200]
    return False, f"HTTP {status}: {snippet}", token


def verify_one(asset_id: int, cookie: str, token: str) -> None:
    url = PERMISSIONS_URL.format(asset_id=asset_id)
    status, _, text = roblox_web.http_request(url, "GET", roblox_web.web_headers(cookie, token))
    print(f"GET {url}\n  HTTP {status}\n  {(text or '').strip()[:1000]}")


def main() -> int:
    ap = argparse.ArgumentParser(prog="grant_audio_to_experience.py", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--universe-id", type=int, default=None, help="Target experience's UNIVERSE id (default: $ROBLOX_UNIVERSE_ID).")
    ap.add_argument("--ids-cache", type=Path, default=DEFAULT_IDS_CACHE, help=f"tools/asset_ids.json (default: {DEFAULT_IDS_CACHE}).")
    ap.add_argument("--sound-assets", type=Path, default=DEFAULT_SOUND_ASSETS, help=f"SoundAssets.luau (default: {DEFAULT_SOUND_ASSETS}).")
    ap.add_argument("--action", default=DEFAULT_ACTION, help=f"Permission verb (default: {DEFAULT_ACTION}; try 'Play' if the API rejects it).")
    ap.add_argument("--tracking", type=Path, default=DEFAULT_TRACKING, help=f"Resume-safe results JSON (default: {DEFAULT_TRACKING}).")
    ap.add_argument("--apply", action="store_true", help="Actually send grants. Without it, prints the plan and sends nothing.")
    ap.add_argument("--list", action="store_true", help="Just print the sound ids and exit (no network).")
    ap.add_argument("--limit", type=int, default=None, metavar="N", help="Only process the first N sounds (N=1 for a smoke test).")
    ap.add_argument("--rate-sleep", type=float, default=0.3, metavar="SECONDS", help="Sleep between grants (default: 0.3).")
    ap.add_argument("--verify-one", type=int, default=None, metavar="ASSET_ID", help="Read back one asset's current permissions and exit.")
    args = ap.parse_args()

    universe_id = args.universe_id
    if universe_id is None:
        env_universe = roblox_web.env_id("ROBLOX_UNIVERSE_ID")
        universe_id = int(env_universe) if env_universe and env_universe.isdigit() else None

    sound_ids = extract_sound_ids(args.ids_cache, args.sound_assets)
    if args.limit is not None:
        sound_ids = sound_ids[: max(0, args.limit)]

    if args.list:
        print(f"{len(sound_ids)} distinct sound id(s) from {args.ids_cache.name} + {args.sound_assets.name}:")
        for sid in sound_ids:
            print(f"  rbxassetid://{sid}")
        return 0

    cookie = roblox_web.resolve_cookie()

    if args.verify_one is not None:
        if not cookie:
            print("Error: --verify-one needs ROBLOSECURITY in .env.", file=sys.stderr)
            return 1
        verify_one(args.verify_one, cookie, roblox_web.fetch_csrf_token(cookie))
        return 0

    if not sound_ids:
        print("No sound ids found — upload audio first (tools/upload_to_roblox.py).", file=sys.stderr)
        return 1

    if not args.apply:
        target = universe_id if universe_id is not None else "<universe-id>"
        print(f"DRY RUN - would grant {len(sound_ids)} sound(s) to universe {target} (action={args.action}).")
        print("  Re-run with --apply to send. Smoke-test one first with --apply --limit 1.")
        for sid in sound_ids[:10]:
            print(f"    rbxassetid://{sid}")
        if len(sound_ids) > 10:
            print(f"    ... and {len(sound_ids) - 10} more (see --list).")
        return 0

    if universe_id is None:
        print("Error: --apply needs --universe-id (or ROBLOX_UNIVERSE_ID in .env).", file=sys.stderr)
        return 1
    if not cookie:
        print("Error: ROBLOSECURITY is not set. The permissions API needs the owner's cookie (see tools/roblox_web.py).", file=sys.stderr)
        return 1

    tracking: dict = {}
    if args.tracking.exists():
        tracking = json.loads(args.tracking.read_text(encoding="utf-8"))

    def save() -> None:
        args.tracking.parent.mkdir(parents=True, exist_ok=True)
        args.tracking.write_text(json.dumps(tracking, indent=2) + "\n", encoding="utf-8")

    def tkey(sid: int) -> str:
        return f"{universe_id}:{sid}"

    token = roblox_web.fetch_csrf_token(cookie)
    total = len(sound_ids)
    already = sum(1 for sid in sound_ids if tracking.get(tkey(sid), {}).get("granted"))
    print(f"Granting {total} sound(s) to universe {universe_id} (action={args.action}). Already granted: {already}.")

    failures: list[tuple[int, str]] = []
    consecutive = 0
    for i, sid in enumerate(sound_ids, 1):
        if tracking.get(tkey(sid), {}).get("granted"):
            print(f"[{i:3d}/{total}] skip   rbxassetid://{sid}")
            continue
        print(f"[{i:3d}/{total}] grant  rbxassetid://{sid} ...", end="", flush=True)
        ok, msg, token = grant_one(sid, universe_id, args.action, cookie, token)
        tracking[tkey(sid)] = {"assetId": sid, "universeId": universe_id, "granted": ok, "detail": msg}
        save()
        print(f" {'OK' if ok else 'FAILED'} ({msg})")
        if ok:
            consecutive = 0
        else:
            failures.append((sid, msg))
            consecutive += 1
            if consecutive >= MAX_CONSECUTIVE_FAILURES:
                print(f"\nBailing after {consecutive} consecutive failures — likely an expired cookie, wrong owner, or a changed endpoint (see the VERIFY note at the top of this file).", file=sys.stderr)
                break
        time.sleep(args.rate_sleep)

    granted = sum(1 for v in tracking.values() if v.get("granted"))
    print(f"\nDone: {granted} granted total, {len(failures)} failed this run.")
    print(f"Results: {args.tracking}")
    if failures:
        print("Failed:", file=sys.stderr)
        for sid, msg in failures:
            print(f"  rbxassetid://{sid}: {msg}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
