#!/usr/bin/env python3
"""upload_to_roblox.py — upload images/audio to Roblox via the Open Cloud
Assets API and cache the resulting ids (tools/asset_ids.json) for
write_asset_ids.py to write into SkinAssets.luau / SoundAssets.luau.

This is the missing step between /Sprites (+ the Unity Audio folder) and the
game: a Roblox Decal/ImageLabel/Sound needs an rbxassetid, which only exists
after an upload. Studio's Asset Manager "Bulk Import" does the same thing by
hand; this does the whole manifest unattended and hands you the id map.

Two ways to drive it:

  1. Manifest mode (preferred — covers images AND audio in one pass):
       python tools/build_manifest.py                      # writes tools/asset_manifest.json
       python tools/upload_to_roblox.py --manifest tools/asset_manifest.json \\
           --creator-id 1234567 --creator-type user --dry-run
       # drop --dry-run and set ROBLOX_API_KEY to actually upload.

       Upload ONE test image first (--keys <one key>) and confirm it renders
       on a part in Studio before running the full batch of ~173 — see
       "IMPORTANT: Decal ids vs. Image ids" below and tools/README.md.

  2. Legacy directory mode (images only, unchanged shape from before):
       python tools/upload_to_roblox.py "Sprites/Frogs" --recursive \\
           --creator-id 1234567 --creator-type user -o sprite_ids.json

Setup (all of it can live in <repo>/.env — see .env.example; tools/roblox_web.py
loads it, and a value already exported in the shell wins):
  pip install -r tools/requirements.txt
  - ROBLOX_API_KEY: an Open Cloud API key (create.roblox.com -> Creator Hub ->
    Open Cloud -> API Keys) with the **assets** API, Read + Write (for OAuth apps
    the equivalent scopes are asset:read / asset:write) — required for every
    image upload and for --status. Add your IP range (or no IP restriction).
  - ROBLOX_USER_ID (or pass --creator-id / --creator-type group): the owning
    creator. Assets you upload are owned by that creator.
  - ROBLOSECURITY: the logged-in .ROBLOSECURITY cookie of that same account.
    Optional but strongly recommended — it enables (a) the WEBSITE audio upload
    path, which clears moderation in seconds where the Open Cloud audio path is
    widely reported to sit in "Reviewing" indefinitely, and (b) cookie-based
    decal->image id resolution (see below). It is a full login credential:
    keep it in .env only, never commit or paste it anywhere.
  - ROBLOX_UNIVERSE_ID + ROBLOX_PLACE_ID: the HotFrog experience (published at
    least once). Only needed for `--resolve-only --via luau`, the headless
    Studio-equivalent resolver (tools/luau_exec.py); the key then also needs the
    `universe.place.luau-execution-session:write` scope for that experience.
  None of the secrets are ever written to a file or log by this script.

Roblox Open Cloud Assets API limits (create.roblox.com/docs/cloud/guides/usage-assets,
confirmed from Roblox's own creator-docs source for this change): max 20MB per
asset file; images must be under 8000x8000px (png/jpeg/bmp/tga accepted, assetType
"Decal" or "Image" — both share the exact same format table); audio accepts
mp3/ogg/wav/flac up to 7 minutes. Files over ~19MB are transcoded to mp3
(192kbps) via ffmpeg if it's on PATH (see tools/build_manifest.py's
`needs_conversion` flag); otherwise they're skipped with a message telling you
to convert by hand.

IMPORTANT: Decal ids vs. Image ids (read this before uploading ~173 assets).
  Uploading an image through the Assets API with assetType "Decal" creates TWO
  Roblox assets: an underlying Image (the actual pixel content) and a Decal
  that wraps it. **The API returns the Decal's id, not the Image's id.** A
  Decal id set on `Decal.Texture` / `ImageLabel.Image` *from a script* does
  NOT render at runtime — only Roblox Studio's property editor auto-resolves a
  pasted decal id to its image for you interactively; game code doesn't get
  that resolution. See
  https://devforum.roblox.com/t/provide-a-stable-open-cloud-api-to-get-an-image-id-from-a-decal-id/3594046
  (this is an open, unresolved Roblox complaint as of research for this
  change — there is no first-class Open Cloud endpoint that returns the image
  id directly from a decal upload).

  What this script actually does about it:
    - The Open Cloud Assets API's format table (create.roblox.com/docs/cloud/guides/usage-assets)
      lists "Decal, Image" together as accepted assetType values for the exact
      same file formats. VERIFIED 2026-09-19 on this account: uploading with
      assetType="Image" returns a genuine Image asset (economy API
      AssetTypeId 1, CDN serves the PNG bytes, Open Cloud reports it Approved
      within minutes) — no Decal wrapper, nothing to resolve. So the default
      (--image-asset-type auto) tries "Image" first and only falls back to
      "Decal" + resolution if the API ever rejects that assetType; the id that
      lands in asset_ids.json records which path was used (assetType field).
      Everything below about resolution is therefore the FALLBACK path.
    - When a Decal is uploaded, the script resolves it to its Image id. Three
      strategies, tried in this order (--via picks one explicitly):
        cookie    GET https://assetdelivery.roblox.com/v1/asset/?id=<decalId>
                  with the .ROBLOSECURITY cookie. The CDN returns the Decal's
                  XML, whose "Texture" property names the Image. VERIFIED
                  working on the scare project (tools/roblox_web.py).
        opencloud GET https://apis.roblox.com/asset-delivery-api/v1/assetId/<decalId>
                  with the API key (scope legacy-asset:manage). Kept as a
                  fallback, but scare live-checked this route and it returned
                  403 to the API key — expect it NOT to work. Every endpoint
                  that carries the Texture is a first-party website API.
        luau      `--resolve-only --via luau`: runs tools/resolve_decals.luau
                  headlessly in the HotFrog experience via the Open Cloud Luau
                  Execution API (tools/luau_exec.py, needs ROBLOX_UNIVERSE_ID /
                  ROBLOX_PLACE_ID). Same InsertService:LoadAsset resolution
                  Studio does, no Studio round-trip. Always works once the
                  decal has cleared moderation.
      The manual Studio Command Bar paste (tools/resolve_decals.luau +
      --emit-studio-resolver + --decal-image-ids) remains as the last resort.
    - Freshly uploaded images are often not yet moderated, so resolution can
      fail with "not available yet" right after upload; the script retries
      (--resolve-retries / --resolve-wait) and, if still unresolved, caches the
      decal id with status "pending-resolution" — re-run with --resolve-only
      later (no re-upload). `--status` shows each cached id's moderation state.
    - `tools/write_asset_ids.py` will ONLY ever write a resolved imageId into
      SkinAssets.luau's Ids table; a key with a decal id but no image id is
      left untouched (and a warning is printed with the count), so a bad
      decal-as-image id can never land in the Luau tables silently.

  Audio has no Decal/Image split — the returned id works directly in
  Sound.SoundId as "rbxassetid://<id>", which is what SoundAssets.id() assumes.
  BUT the upload path matters (--audio-via):
    website   (default whenever ROBLOSECURITY is set) the cookie-authenticated
              publish.roblox.com endpoint the Creator Hub itself uses. Clears
              the automated audio-moderation pipeline in seconds. The creator
              is the cookie's user (pass --creator-type group to upload to a
              group). Accepts .wav directly — no ffmpeg needed for wav.
    opencloud the Assets API. Widely reported (and observed on scare) to leave
              audio in "Reviewing" moderation indefinitely. Used only when no
              cookie is available, with a loud warning.
  Cached audio entries record which path was used ("via").

  Audio permissions per experience: audio is permission-gated per EXPERIENCE.
  Sounds you own normally play in experiences you own, but after publishing to
  a NEW experience run tools/grant_audio_to_experience.py if anything stays
  silent — it bulk-adds the experience to every sound's allow-list.

Notes:
  - Uploaded assets go through Roblox moderation -- a freshly returned id may
    render/play blank until approved.
  - `tools/asset_ids.json` is a persistent cache (key -> {kind, table,
    sourceHash, uploadedAt, assetType, decalId, imageId, status} for images;
    key -> {kind, table, sourceHash, uploadedAt, assetId} for audio). Re-runs
    hash each source file (post-conversion, if converted) and skip anything
    whose hash hasn't changed and already has a successful id — so a
    failed/partial run just resumes.
  - Uploads are sequential with a small delay and bounded retries (exponential
    backoff, honoring `Retry-After` on 429s) to stay under rate limits.
  - Only your account/group can be the creator; there is no anonymous upload
    (unlike catbox). Never commit your API key or tools/asset_ids.json if it
    were ever to contain anything sensitive (it doesn't — ids only).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

import requests

import roblox_web  # loads <repo>/.env into os.environ on import

ASSETS_URL = "https://apis.roblox.com/assets/v1/assets"
OPERATION_URL = "https://apis.roblox.com/assets/v1/operations/{}"
# Open Cloud decal->image route. Kept as a fallback only: the scare project
# live-checked it and it 403s the API key (see the module docstring).
ASSET_DELIVERY_URL = "https://apis.roblox.com/asset-delivery-api/v1/assetId/{}"
RESOLVE_DECALS_LUAU = Path(__file__).resolve().parent / "resolve_decals.luau"

IMAGE_MIME_BY_SUFFIX = {
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".bmp": "image/bmp",
    ".tga": "image/tga",
}
AUDIO_MIME_BY_SUFFIX = {
    ".mp3": "audio/mpeg",
    ".ogg": "audio/ogg",
    ".wav": "audio/wav",
    ".flac": "audio/flac",
}
MIME_BY_SUFFIX = {**IMAGE_MIME_BY_SUFFIX, **AUDIO_MIME_BY_SUFFIX}

REPO_ROOT = Path(__file__).resolve().parent.parent
CONVERTED_AUDIO_DIR = REPO_ROOT / "tools" / ".asset_cache" / "converted_audio"
DEFAULT_CACHE_PATH = REPO_ROOT / "tools" / "asset_ids.json"
DEFAULT_DECAL_IMAGE_IDS_PATH = REPO_ROOT / "tools" / "decal_image_ids.json"

MAX_RETRIES = 4
RETRY_BACKOFF_BASE = 2.0

# Matches "rbxassetid://<id>" or "...?id=<id>" / "...&id=<id>" — the two shapes
# a Decal's resolved image id is known to appear in from the Asset Delivery
# API's legacy content format. Deliberately loose (see module docstring).
IMAGE_ID_PATTERN = re.compile(rb"rbxassetid://(\d+)|[?&]id=(\d+)")


# ---------------------------------------------------------------------------
# Legacy directory-scan mode (unchanged behavior)
# ---------------------------------------------------------------------------


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
            if resolved not in seen and path.suffix.lower() in IMAGE_MIME_BY_SUFFIX:
                seen.add(resolved)
                files.append(path)
    return files


# ---------------------------------------------------------------------------
# Cache (tools/asset_ids.json)
# ---------------------------------------------------------------------------


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def load_cache(path: Path) -> dict[str, dict]:
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        print(f"[warn] {path} is not valid JSON, starting fresh", file=sys.stderr)
        return {}


def save_cache(path: Path, cache: dict[str, dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(cache, indent=2, sort_keys=True) + "\n", encoding="utf-8")


# ---------------------------------------------------------------------------
# Audio conversion (needs_conversion entries)
# ---------------------------------------------------------------------------


def ffmpeg_available() -> bool:
    return shutil.which("ffmpeg") is not None


def convert_to_mp3(src: Path, key: str) -> Path | None:
    """Transcode an oversized audio file to mp3 (192kbps) via ffmpeg. Returns
    the converted path, or None if ffmpeg isn't available / conversion failed."""
    if not ffmpeg_available():
        return None
    CONVERTED_AUDIO_DIR.mkdir(parents=True, exist_ok=True)
    out = CONVERTED_AUDIO_DIR / f"{key}.mp3"
    cmd = ["ffmpeg", "-y", "-v", "error", "-i", str(src), "-codec:a", "libmp3lame", "-b:a", "192k", str(out)]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
    except (OSError, subprocess.TimeoutExpired) as e:
        print(f"[convert] {key}: ffmpeg failed to run: {e}", file=sys.stderr)
        return None
    if result.returncode != 0 or not out.exists():
        print(f"[convert] {key}: ffmpeg exited {result.returncode}: {result.stderr.strip()[:300]}", file=sys.stderr)
        return None
    return out


# ---------------------------------------------------------------------------
# Upload
# ---------------------------------------------------------------------------


def asset_type_for(path: Path) -> str:
    """Default assetType by file extension — "Audio" for audio, "Decal" for
    images (the long-confirmed-working image assetType; see upload_image() for
    where "Image" is tried first)."""
    return "Audio" if path.suffix.lower() in AUDIO_MIME_BY_SUFFIX else "Decal"


def upload(path: Path, api_key: str, creator_field: str, creator_id: str, description: str, asset_type: str | None = None) -> str:
    """Upload one file and return its asset id (raises on failure). Retries
    transient failures (429/5xx/network) with exponential backoff, honoring
    Retry-After on 429s; a 4xx client error (e.g. an assetType the API
    rejects) raises immediately without retrying, so callers can decide
    whether to fall back to a different assetType."""
    asset_type = asset_type or asset_type_for(path)
    request = {
        "assetType": asset_type,
        "displayName": path.stem[:50],
        "description": description,
        "creationContext": {"creator": {creator_field: creator_id}},
    }
    mime = MIME_BY_SUFFIX[path.suffix.lower()]

    last_error: Exception | None = None
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            with path.open("rb") as fh:
                resp = requests.post(
                    ASSETS_URL,
                    headers={"x-api-key": api_key},
                    data={"request": json.dumps(request)},
                    files={"fileContent": (path.name, fh, mime)},
                    timeout=120,
                )
            if resp.status_code == 429:
                retry_after = float(resp.headers.get("Retry-After", RETRY_BACKOFF_BASE**attempt))
                time.sleep(retry_after)
                continue
            if 400 <= resp.status_code < 500:
                # Client error (e.g. bad/unsupported assetType) — not transient,
                # don't burn retries on it. Callers inspect the message to decide
                # whether to fall back to a different assetType.
                raise RuntimeError(f"upload failed: HTTP {resp.status_code} for assetType={asset_type}: {resp.text[:500]}")
            resp.raise_for_status()
            body = resp.json()
            operation_id = body.get("operationId") or body.get("path", "").split("/")[-1]
            if not operation_id:
                raise RuntimeError(f"no operationId in response: {resp.text!r}")
            return poll_operation(operation_id, api_key)
        except requests.exceptions.RequestException as e:
            last_error = e
            if attempt < MAX_RETRIES:
                time.sleep(RETRY_BACKOFF_BASE**attempt)
    raise RuntimeError(f"upload failed after {MAX_RETRIES} attempts: {last_error}")


def poll_operation(operation_id: str, api_key: str) -> str:
    for _ in range(30):
        time.sleep(1.0)
        op = requests.get(OPERATION_URL.format(operation_id), headers={"x-api-key": api_key}, timeout=60)
        op.raise_for_status()
        body = op.json()
        if body.get("done"):
            asset_id = body.get("response", {}).get("assetId")
            if not asset_id:
                raise RuntimeError(f"operation done but no assetId: {body!r}")
            return str(asset_id)
    raise RuntimeError("timed out waiting for the upload operation")


def upload_image(path: Path, api_key: str, creator_field: str, creator_id: str, description: str, image_asset_type_pref: str) -> tuple[str, str]:
    """Upload an image and return (asset_id, asset_type_used).

    image_asset_type_pref:
      "decal"  — always upload as assetType "Decal" (the known-working path;
                 the returned id needs resolve_decal_to_image()).
      "image"  — always upload as assetType "Image" (documented as accepted,
                 but UNVERIFIED whether the id it returns is directly usable —
                 see the module docstring).
      "auto"   — try "Image" first, fall back to "Decal" only if the API
                 rejects that assetType (a 4xx mentioning it); a
                 network/5xx/429 failure is NOT retried under "Decal" since
                 it would fail the same way.
    """
    if image_asset_type_pref == "decal":
        order = ["Decal"]
    elif image_asset_type_pref == "image":
        order = ["Image"]
    else:
        order = ["Image", "Decal"]

    last_error: Exception | None = None
    for i, asset_type in enumerate(order):
        try:
            asset_id = upload(path, api_key, creator_field, creator_id, description, asset_type=asset_type)
            return asset_id, asset_type
        except RuntimeError as e:
            last_error = e
            is_last = i + 1 >= len(order)
            looks_like_bad_asset_type = "HTTP 4" in str(e)
            if asset_type == "Image" and not is_last and looks_like_bad_asset_type:
                print(f"[upload] assetType=Image rejected for {path.name}, falling back to Decal: {e}", file=sys.stderr)
                continue
            raise
    assert last_error is not None
    raise last_error


def resolve_decal_to_image(decal_id: int, api_key: str | None, retries: int, wait: float, cookie: str | None = None, via: str = "auto") -> int | None:
    """Resolve a Decal asset id to its underlying Image asset id.

    via="auto" tries the cookie path (assetdelivery CDN, verified working) when
    a cookie is available, then the Open Cloud Asset Delivery API (known to 403
    the API key, kept as a fallback). via="cookie" / "opencloud" forces one.
    Returns None (after `retries` attempts, with increasing backoff) if it can't
    be resolved yet — most commonly because the asset hasn't cleared moderation.
    """
    if via in ("auto", "cookie") and cookie:
        image_id = roblox_web.resolve_decal_image_id(decal_id, cookie, attempts=retries, backoff=wait)
        if image_id:
            return image_id
        print(f"[resolve] decal {decal_id}: cookie/CDN path could not resolve it after {retries} attempt(s) (not moderated yet, or cookie expired)", file=sys.stderr)
        if via == "cookie" or not api_key:
            return None
    elif via == "cookie":
        print(f"[resolve] decal {decal_id}: --via cookie but ROBLOSECURITY is not set", file=sys.stderr)
        return None
    if not api_key:
        print(f"[resolve] decal {decal_id}: no cookie and no API key — cannot resolve", file=sys.stderr)
        return None
    return _resolve_via_open_cloud(decal_id, api_key, retries, wait)


def _resolve_via_open_cloud(decal_id: int, api_key: str, retries: int, wait: float) -> int | None:
    headers = {"x-api-key": api_key}
    last_status = "no attempts made"
    for attempt in range(1, retries + 1):
        try:
            resp = requests.get(ASSET_DELIVERY_URL.format(decal_id), headers=headers, timeout=30)
        except requests.exceptions.RequestException as e:
            last_status = f"request error: {e}"
            time.sleep(wait * attempt)
            continue

        if resp.status_code == 200:
            body = resp.content
            # A couple of Open Cloud endpoints return {"location": "..."}
            # instead of streaming content directly — handle both shapes.
            content_type = resp.headers.get("Content-Type", "")
            if content_type.startswith("application/json"):
                try:
                    location = resp.json().get("location")
                except ValueError:
                    location = None
                if location:
                    try:
                        body = requests.get(location, timeout=30).content
                    except requests.exceptions.RequestException as e:
                        last_status = f"failed to follow location url: {e}"
                        time.sleep(wait * attempt)
                        continue
            match = IMAGE_ID_PATTERN.search(body)
            if match:
                return int(match.group(1) or match.group(2))
            last_status = f"200 OK but no image id found in {len(body)} bytes of response"
        elif resp.status_code == 404:
            last_status = "404 (not available yet — likely still moderating)"
        elif resp.status_code == 403:
            last_status = "403 (check the API key has the legacy-asset:manage scope)"
        else:
            last_status = f"HTTP {resp.status_code}: {resp.text[:200]}"

        if attempt < retries:
            time.sleep(wait * attempt)

    print(f"[resolve] decal {decal_id}: Open Cloud path not resolved after {retries} attempt(s) ({last_status})", file=sys.stderr)
    return None


def resolve_via_luau(decal_ids: list[int], args: argparse.Namespace) -> dict[str, int | None]:
    """Run tools/resolve_decals.luau headlessly in the HotFrog experience via
    the Open Cloud Luau Execution API and return {decalId: imageId|None}."""
    import luau_exec  # local import: only needed for this path

    universe = args.universe or roblox_web.env_id("ROBLOX_UNIVERSE_ID")
    place = args.place or roblox_web.env_id("ROBLOX_PLACE_ID")
    if not universe or not place:
        print("--via luau needs the experience: pass --universe/--place or set ROBLOX_UNIVERSE_ID / ROBLOX_PLACE_ID in .env.", file=sys.stderr)
        return {}
    if not args.api_key:
        print("--via luau needs ROBLOX_API_KEY (with the luau-execution-session:write scope for that experience).", file=sys.stderr)
        return {}

    template = RESOLVE_DECALS_LUAU.read_text(encoding="utf-8")
    literal = "{ " + ", ".join(str(i) for i in decal_ids) + " }"
    script, n = re.subn(r"^local DECAL_IDS: \{ number \} = \{.*?\}$", f"local DECAL_IDS: {{ number }} = {literal}", template, count=1, flags=re.MULTILINE)
    if n != 1:
        print(f"Could not find the DECAL_IDS line in {RESOLVE_DECALS_LUAU}.", file=sys.stderr)
        return {}

    res = luau_exec.run_script(args.api_key, universe, place, script, timeout="300s", label="resolve_decals")
    for line in res["logs"]:
        print(f"  [luau] {line}", file=sys.stderr)
    if res["state"] != "COMPLETE":
        print(f"Luau task ended {res['state']}: {json.dumps(res['error'])[:500]}", file=sys.stderr)
        return {}
    results = res["results"]
    if isinstance(results, list):
        results = results[0] if results else {}
    if not isinstance(results, dict):
        print(f"Unexpected Luau result shape: {json.dumps(results)[:300]}", file=sys.stderr)
        return {}
    return {str(k): (int(v) if v else None) for k, v in results.items()}


# ---------------------------------------------------------------------------
# Manifest-driven run
# ---------------------------------------------------------------------------


def run_manifest(args: argparse.Namespace) -> int:
    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    entries: list[dict[str, Any]] = manifest["entries"]
    if args.kind:
        entries = [e for e in entries if e["kind"] == args.kind]
    if args.keys:
        wanted = set(args.keys)
        entries = [e for e in entries if e["key"] in wanted]

    cache = load_cache(args.cache)
    creator_field = "userId" if args.creator_type == "user" else "groupId"
    cookie = args.cookie

    # Audio path: website (cookie) unless told otherwise / no cookie.
    audio_via = args.audio_via
    if audio_via == "auto":
        audio_via = "website" if cookie else "opencloud"
    if audio_via == "website" and not cookie:
        print("--audio-via website needs a .ROBLOSECURITY cookie: set ROBLOSECURITY in .env or pass --cookie.", file=sys.stderr)
        return 2

    dry = args.dry_run
    has_images = any(e["kind"] == "image" for e in entries)
    has_audio = any(e["kind"] == "audio" for e in entries)
    needs_open_cloud = has_images or (has_audio and audio_via == "opencloud")
    if not dry and needs_open_cloud and not args.api_key:
        print("No API key: pass --api-key, set ROBLOX_API_KEY, or use --dry-run.", file=sys.stderr)
        return 2
    if not dry and needs_open_cloud and not args.creator_id:
        print("No creator id: pass --creator-id, set ROBLOX_USER_ID, or use --dry-run.", file=sys.stderr)
        return 2
    if has_audio and audio_via == "opencloud" and not dry:
        print(
            "WARNING: uploading audio via the Open Cloud Assets API. This path is widely reported to leave "
            "audio in 'Reviewing' moderation indefinitely. Set ROBLOSECURITY in .env to use the website path "
            "that clears moderation in seconds (see the module docstring).",
            file=sys.stderr,
        )
    # Website audio uploads to a group need the group id; to a user it's implied by the cookie.
    website_group_id = args.creator_id if (audio_via == "website" and args.creator_type == "group") else None

    uploaded = skipped_unchanged = converted = failed = missing_ffmpeg = pending_resolution = 0

    for i, entry in enumerate(entries, 1):
        key = entry["key"]
        src = Path(entry["source"])
        tag = f"[{i}/{len(entries)}] {key} ({entry['kind']}, {entry['table']})"

        if not src.exists():
            print(f"{tag}: SKIP source not found: {src}", file=sys.stderr)
            failed += 1
            continue

        upload_path = src
        if entry.get("needs_conversion"):
            if dry:
                print(f"{tag}: DRY-RUN would convert {src.name} via ffmpeg (needs_conversion) then upload", file=sys.stderr)
                converted += 1
                continue
            converted_path = convert_to_mp3(src, key)
            if converted_path is None:
                print(f"{tag}: SKIP needs_conversion=true and ffmpeg unavailable/failed — convert '{src}' to mp3/ogg under 20MB by hand and re-run", file=sys.stderr)
                missing_ffmpeg += 1
                continue
            upload_path = converted_path

        file_hash = sha256_file(upload_path)
        cached = cache.get(key)
        is_image = entry["kind"] == "image"
        cached_ok = cached and cached.get("sourceHash") == file_hash and (
            (is_image and cached.get("imageId")) or (not is_image and cached.get("assetId"))
        )
        if cached_ok:
            id_shown = cached.get("imageId") if is_image else cached.get("assetId")
            print(f"{tag}: cached, unchanged (id={id_shown})", file=sys.stderr)
            skipped_unchanged += 1
            continue

        if dry:
            state = "new" if not cached else "changed"
            hint = "assetType=Image, falls back to Decal+resolve" if is_image else f"Audio via {audio_via}"
            print(f"{tag}: DRY-RUN would upload ({state}, {hint}, {upload_path.stat().st_size} bytes)", file=sys.stderr)
            continue

        description = f"HotFrog {entry['kind']} asset ({entry['table']})"

        if is_image:
            try:
                asset_id, asset_type_used = upload_image(upload_path, args.api_key, creator_field, args.creator_id, description, args.image_asset_type)
            except Exception as e:
                failed += 1
                print(f"{tag}: FAILED: {e}", file=sys.stderr)
                time.sleep(args.delay)
                continue

            entry_cache: dict[str, Any] = {
                "kind": "image",
                "table": entry["table"],
                "sourceHash": file_hash,
                "uploadedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "assetType": asset_type_used,
            }
            if asset_type_used == "Image":
                entry_cache["decalId"] = None
                entry_cache["imageId"] = int(asset_id)
                entry_cache["status"] = "resolved-direct (assetType=Image returns a real Image asset, AssetTypeId 1 — verified 2026-09-19)"
                print(f"{tag}: -> image {asset_id} (assetType=Image, no resolution needed)", file=sys.stderr)
            else:
                entry_cache["decalId"] = int(asset_id)
                image_id = None if args.no_resolve else resolve_decal_to_image(int(asset_id), args.api_key, args.resolve_retries, args.resolve_wait, cookie=cookie, via=args.via)
                entry_cache["imageId"] = image_id
                if image_id:
                    entry_cache["status"] = "resolved"
                    print(f"{tag}: decal {asset_id} -> image {image_id}", file=sys.stderr)
                else:
                    entry_cache["status"] = "pending-resolution"
                    pending_resolution += 1
                    print(
                        f"{tag}: decal {asset_id} uploaded, image id NOT resolved yet — "
                        f"re-run with --resolve-only later, or use tools/resolve_decals.luau in Studio.",
                        file=sys.stderr,
                    )
            cache[key] = entry_cache
        else:
            try:
                if audio_via == "website":
                    asset_id, _ = roblox_web.web_upload_audio(cookie, upload_path.stem[:50], upload_path.read_bytes(), website_group_id)
                else:
                    asset_id = upload(upload_path, args.api_key, creator_field, args.creator_id, description)
            except Exception as e:
                failed += 1
                print(f"{tag}: FAILED: {e}", file=sys.stderr)
                if isinstance(e, roblox_web.RobloxWebError) and "unauthorized" in str(e):
                    print("Cookie rejected — stopping the run rather than failing every remaining audio entry.", file=sys.stderr)
                    break
                time.sleep(args.delay)
                continue
            cache[key] = {
                "kind": entry["kind"],
                "table": entry["table"],
                "assetId": int(asset_id),
                "sourceHash": file_hash,
                "uploadedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "via": audio_via,
            }
            print(f"{tag}: -> {asset_id} (via {audio_via})", file=sys.stderr)

        save_cache(args.cache, cache)  # persist after every success so a crash mid-run loses nothing
        uploaded += 1
        time.sleep(args.delay)

    print(
        f"\nDone: {uploaded} uploaded, {skipped_unchanged} cached/unchanged, "
        f"{converted} would-convert (dry-run), {missing_ffmpeg} need manual conversion, "
        f"{pending_resolution} uploaded but pending image-id resolution, {failed} failed.",
        file=sys.stderr,
    )
    if pending_resolution:
        print("Run `python tools/upload_to_roblox.py --resolve-only` again in a bit to pick up moderation-cleared ids (or `--resolve-only --via luau`).", file=sys.stderr)
    if uploaded:
        print("Check moderation with `python tools/upload_to_roblox.py --status` before playtesting.", file=sys.stderr)
    return 0 if failed == 0 and missing_ffmpeg == 0 else 1


# ---------------------------------------------------------------------------
# --resolve-only and --emit-studio-resolver
# ---------------------------------------------------------------------------


def run_resolve_only(args: argparse.Namespace) -> int:
    cache = load_cache(args.cache)

    merged_from_file = 0
    if args.decal_image_ids.exists():
        try:
            overrides = json.loads(args.decal_image_ids.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            print(f"[warn] {args.decal_image_ids} is not valid JSON, ignoring", file=sys.stderr)
            overrides = {}
        by_decal_id = {
            str(entry["decalId"]): key
            for key, entry in cache.items()
            if isinstance(entry, dict) and entry.get("kind") == "image" and entry.get("decalId")
        }
        for decal_id_str, image_id in overrides.items():
            if not image_id:
                continue
            key = by_decal_id.get(str(decal_id_str))
            if key and not cache[key].get("imageId"):
                cache[key]["imageId"] = int(image_id)
                cache[key]["status"] = "resolved (via tools/resolve_decals.luau)"
                merged_from_file += 1
        if merged_from_file:
            save_cache(args.cache, cache)
        print(f"Merged {merged_from_file} id(s) from {args.decal_image_ids}.", file=sys.stderr)
    else:
        print(f"({args.decal_image_ids} not found — skipping the Studio-fallback merge step.)", file=sys.stderr)

    pending = [
        (key, entry)
        for key, entry in cache.items()
        if isinstance(entry, dict) and entry.get("kind") == "image" and entry.get("decalId") and not entry.get("imageId")
    ]
    if args.keys:
        wanted = set(args.keys)
        pending = [(k, e) for k, e in pending if k in wanted]

    if not pending:
        print("No pending image entries need resolution.", file=sys.stderr)
        return 0

    resolved = still_pending = 0

    if args.via == "luau":
        decal_ids = sorted({int(e["decalId"]) for _, e in pending})
        print(f"Resolving {len(decal_ids)} decal id(s) headlessly via the Luau Execution API...", file=sys.stderr)
        mapping = resolve_via_luau(decal_ids, args)
        for key, entry in pending:
            image_id = mapping.get(str(entry["decalId"]))
            if image_id:
                cache[key]["imageId"] = image_id
                cache[key]["status"] = "resolved (via luau_exec)"
                resolved += 1
                print(f"{key}: decal {entry['decalId']} -> image {image_id}", file=sys.stderr)
            else:
                still_pending += 1
                print(f"{key}: still not resolvable (decal {entry['decalId']})", file=sys.stderr)
        if resolved:
            save_cache(args.cache, cache)
        print(f"\nResolve-only (luau): {resolved} resolved, {still_pending} still pending.", file=sys.stderr)
        return 0 if still_pending == 0 else 1

    if not args.cookie and not args.api_key:
        keys_preview = ", ".join(k for k, _ in pending[:20]) + (", ..." if len(pending) > 20 else "")
        print(
            f"{len(pending)} entries still need resolution but neither ROBLOSECURITY nor ROBLOX_API_KEY is set ({keys_preview}). "
            f"Set one in .env, use `--resolve-only --via luau`, or run tools/resolve_decals.luau in Studio and save its "
            f"output as {args.decal_image_ids}, then re-run --resolve-only.",
            file=sys.stderr,
        )
        return 1

    for key, entry in pending:
        image_id = resolve_decal_to_image(entry["decalId"], args.api_key, args.resolve_retries, args.resolve_wait, cookie=args.cookie, via=args.via)
        if image_id:
            cache[key]["imageId"] = image_id
            cache[key]["status"] = "resolved"
            resolved += 1
            save_cache(args.cache, cache)
            print(f"{key}: decal {entry['decalId']} -> image {image_id}", file=sys.stderr)
        else:
            still_pending += 1
            print(f"{key}: still not resolvable (decal {entry['decalId']})", file=sys.stderr)

    print(f"\nResolve-only: {resolved} resolved, {still_pending} still pending.", file=sys.stderr)
    if still_pending:
        print("Tip: `--resolve-only --via luau` resolves through the experience itself once ROBLOX_UNIVERSE_ID/ROBLOX_PLACE_ID are set.", file=sys.stderr)
    return 0 if still_pending == 0 else 1


# ---------------------------------------------------------------------------
# --status: moderation state of every cached id
# ---------------------------------------------------------------------------


def run_status(args: argparse.Namespace) -> int:
    """Print the moderation state (Reviewing / Approved / Rejected) of every id
    in the cache via the Open Cloud asset-metadata GET. With --wait-approved,
    poll each non-terminal id until it resolves or --approve-timeout expires.
    Exit 2 if anything was Rejected, 1 if anything is still Reviewing."""
    if not args.api_key:
        print("--status needs ROBLOX_API_KEY (asset:read).", file=sys.stderr)
        return 2
    cache = load_cache(args.cache)
    items: list[tuple[str, str, int]] = []  # (key, label, id)
    for key, entry in sorted(cache.items()):
        if not isinstance(entry, dict):
            continue
        if args.keys and key not in set(args.keys):
            continue
        if entry.get("kind") == "image":
            # The Image is what renders; moderation is reported on whichever id we have.
            if entry.get("imageId"):
                items.append((key, "image", int(entry["imageId"])))
            elif entry.get("decalId"):
                items.append((key, "decal", int(entry["decalId"])))
        elif entry.get("assetId"):
            items.append((key, "audio", int(entry["assetId"])))
    if not items:
        print("Nothing in the cache to check.", file=sys.stderr)
        return 0

    # Two signals. Open Cloud's moderationState tracks the slow human-review
    # queue (Reviewing for hours/days) and is authoritative for "Rejected". The
    # cookie develop API's moderationStatus (Green/Red) is the automated pass
    # that actually gates whether the asset loads — live-checked 2026-09-19
    # (see roblox_web.fetch_automated_moderation). Show both when we can.
    automated: dict[str, dict] = {}
    if args.cookie:
        automated = roblox_web.fetch_automated_moderation([i for _, _, i in items], args.cookie)

    counts: dict[str, int] = {}
    usable = 0
    rows: list[str] = []
    for key, label, asset_id in items:
        state, detail = roblox_web.fetch_moderation_state(asset_id, args.api_key)
        # Open Cloud rate-limits the metadata GET after ~120 quick reads; back off and retry.
        for backoff in (5, 15, 30):
            if state is not None or not detail.startswith("HTTP 429"):
                break
            time.sleep(backoff)
            state, detail = roblox_web.fetch_moderation_state(asset_id, args.api_key)
        auto = automated.get(str(asset_id), {})
        auto_status = auto.get("moderationStatus")
        if args.wait_approved and state not in ("Approved", "Rejected") and auto_status != "Green":
            state = roblox_web.wait_for_moderation(asset_id, args.api_key, args.approve_timeout, quiet=True)
        shown = state or "unknown"
        counts[shown] = counts.get(shown, 0) + 1
        if auto_status == "Green" or state == "Approved":
            usable += 1
        auto_col = f"{auto_status or '-':<6}" if args.cookie else ""
        extra = "" if state else f"  ({detail[:80]})"
        rows.append(f"{shown:<10} {auto_col}{label:<6} {asset_id:<16} {key}{extra}")
        cache[key]["moderation"] = shown
        if auto_status:
            cache[key]["automatedModeration"] = auto_status
        cache[key]["moderationCheckedAt"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        time.sleep(0.5)
    save_cache(args.cache, cache)

    header = f"{'opencloud':<10} {'auto  ' if args.cookie else ''}{'kind':<6} {'id':<16} key"
    print(header)
    print("\n".join(rows))
    summary = f"\n{len(items)} checked: " + ", ".join(f"{n} {s}" for s, n in sorted(counts.items()))
    if args.cookie:
        summary += f"; {usable} usable now (automated Green or Approved)"
        if counts.get("Reviewing") and usable == len(items):
            summary += ". 'Reviewing' is the human-review queue — it does not block your own audio in your own experience."
    print(summary, file=sys.stderr)
    if counts.get("Rejected") or any(a.get("moderationStatus") == "Red" for a in automated.values()):
        print("Rejected assets will never load in-game — re-export/rename and re-upload those keys (delete them from tools/asset_ids.json first).", file=sys.stderr)
        return 2
    if usable < len(items):
        return 1
    return 0


def run_emit_studio_resolver(args: argparse.Namespace) -> int:
    cache = load_cache(args.cache)
    decal_ids = sorted(
        {
            entry["decalId"]
            for entry in cache.values()
            if isinstance(entry, dict) and entry.get("kind") == "image" and entry.get("decalId") and not entry.get("imageId")
        }
    )
    if not decal_ids:
        print("No decal ids are pending resolution — nothing to emit.", file=sys.stderr)
        return 0

    literal = "{ " + ", ".join(str(i) for i in decal_ids) + " }"
    placeholder_hint = "local DECAL_IDS ="

    if args.studio_resolver_out:
        args.studio_resolver_out.write_text(literal + "\n", encoding="utf-8")
        print(
            f"Wrote {args.studio_resolver_out} ({len(decal_ids)} decal id(s)). Paste its contents over the "
            f"'{placeholder_hint} ...' line in tools/resolve_decals.luau, run that file in Studio's Command "
            f"Bar, and save the JSON it prints as {args.decal_image_ids}.",
            file=sys.stderr,
        )
    else:
        print(literal)
        print(
            f"\n({len(decal_ids)} decal id(s) above — paste that line over the '{placeholder_hint} ...' line "
            f"in tools/resolve_decals.luau, run that file in Studio's Command Bar, save the JSON it prints as "
            f"{args.decal_image_ids}, then run: python tools/upload_to_roblox.py --resolve-only",
            file=sys.stderr,
        )
    return 0


# ---------------------------------------------------------------------------


def main() -> int:
    ap = argparse.ArgumentParser(
        prog="upload_to_roblox.py",
        description="Upload images/audio to Roblox (Open Cloud) and cache the resulting ids.",
    )
    ap.add_argument("inputs", nargs="*", type=Path, help="Legacy mode: image files and/or directories (ignored if --manifest is given).")
    ap.add_argument("--manifest", type=Path, default=None, help="tools/asset_manifest.json from build_manifest.py — drives image+audio upload together.")
    ap.add_argument("--dry-run", action="store_true", help="Print what would be uploaded; no network calls, no API key/creator-id required.")
    ap.add_argument("--cache", type=Path, default=DEFAULT_CACHE_PATH, help=f"Persistent id/hash cache (default: {DEFAULT_CACHE_PATH}).")
    ap.add_argument("--kind", choices=("image", "audio"), default=None, help="Manifest mode: only upload this kind.")
    ap.add_argument("--keys", nargs="*", default=None, help="Manifest mode / --resolve-only: only touch these specific keys (e.g. to upload or resolve one test image first).")
    ap.add_argument("--delay", type=float, default=0.5, help="Seconds to sleep between uploads (manifest mode). Default: 0.5")
    ap.add_argument("--api-key", default=os.environ.get("ROBLOX_API_KEY"), help="Open Cloud key (or $ROBLOX_API_KEY / .env). Never written to disk/logs by this script.")
    ap.add_argument("--cookie", default=None, help=".ROBLOSECURITY cookie value (or $ROBLOSECURITY / .env). Enables the website audio path and cookie decal resolution.")
    ap.add_argument("--creator-id", default=roblox_web.env_id("ROBLOX_USER_ID") or roblox_web.env_id("ROBLOX_GROUP_ID"), help="Owning user id or group id (default: $ROBLOX_USER_ID, else $ROBLOX_GROUP_ID). Required for Open Cloud uploads unless --dry-run.")
    ap.add_argument("--creator-type", choices=("user", "group"), default="group" if (not roblox_web.env_id("ROBLOX_USER_ID") and roblox_web.env_id("ROBLOX_GROUP_ID")) else "user")
    ap.add_argument("--audio-via", choices=("auto", "website", "opencloud"), default="auto", help="Audio upload path. 'auto' (default) = website when a cookie is set (fast moderation), else Open Cloud (slow/stuck moderation).")
    ap.add_argument("--via", choices=("auto", "cookie", "opencloud", "luau"), default="auto", help="Decal->image resolution strategy. 'auto' = cookie CDN if a cookie is set, then Open Cloud. 'luau' (only with --resolve-only) runs tools/resolve_decals.luau headlessly in the experience via tools/luau_exec.py.")
    ap.add_argument("--universe", default=None, help="--via luau: universe id (or $ROBLOX_UNIVERSE_ID).")
    ap.add_argument("--place", default=None, help="--via luau: place id (or $ROBLOX_PLACE_ID).")
    ap.add_argument("--status", action="store_true", help="Report the moderation state of every cached id (Reviewing/Approved/Rejected) and exit. Needs the API key.")
    ap.add_argument("--wait-approved", action="store_true", help="With --status: poll each pending id until it is Approved/Rejected or --approve-timeout expires.")
    ap.add_argument("--approve-timeout", type=float, default=120.0, help="Seconds per asset for --wait-approved (default 120).")
    ap.add_argument("--pattern", default="*.png", help="Legacy mode: glob for directory inputs. Default: *.png")
    ap.add_argument("--recursive", action="store_true", help="Legacy mode: recurse into directory inputs.")
    ap.add_argument("--output", "-o", type=Path, default=None, help="Legacy mode: write the JSON {stem: {decalId, imageId}} map here.")
    ap.add_argument("--lua-out", type=Path, default=None, help="Legacy mode: also write a paste-ready Lua id table (image ids only; unresolved entries are left at 0 with a comment).")

    ap.add_argument(
        "--image-asset-type",
        choices=("auto", "image", "decal"),
        default="auto",
        help="Which Open Cloud assetType to try for images. 'auto' (default) tries 'Image' first "
        "(documented as an accepted assetType alongside 'Decal' for the same formats, though unverified "
        "whether it returns a directly-usable image id) and falls back to 'Decal' + resolution if the API "
        "rejects 'Image'. 'decal' skips straight to the known-working Decal+resolve path.",
    )
    ap.add_argument("--no-resolve", action="store_true", help="Skip decal->image id resolution after a Decal upload (leaves imageId unresolved; use --resolve-only later).")
    ap.add_argument("--resolve-retries", type=int, default=5, help="Attempts to resolve a fresh decal id to its image id before giving up (default: 5).")
    ap.add_argument("--resolve-wait", type=float, default=5.0, help="Base seconds between resolution retries, multiplied by attempt number (default: 5.0).")
    ap.add_argument("--resolve-only", action="store_true", help="Don't upload anything: (re)try resolving cached image entries that have a decalId but no imageId yet, merging --decal-image-ids first if present.")
    ap.add_argument("--emit-studio-resolver", action="store_true", help="Network-free: print the Lua array literal of decal ids still pending resolution, to paste into tools/resolve_decals.luau.")
    ap.add_argument("--studio-resolver-out", type=Path, default=None, help="Write the --emit-studio-resolver array literal to this file instead of stdout.")
    ap.add_argument("--decal-image-ids", type=Path, default=DEFAULT_DECAL_IMAGE_IDS_PATH, help=f"JSON {{decalId: imageId}} produced by tools/resolve_decals.luau, merged by --resolve-only (default: {DEFAULT_DECAL_IMAGE_IDS_PATH}).")

    args = ap.parse_args()
    args.cookie = roblox_web.resolve_cookie(args.cookie)

    if args.via == "luau" and not args.resolve_only:
        print("--via luau only applies to --resolve-only (upload first, then resolve headlessly).", file=sys.stderr)
        return 2

    if args.emit_studio_resolver:
        return run_emit_studio_resolver(args)

    if args.status:
        return run_status(args)

    if args.resolve_only:
        return run_resolve_only(args)

    if args.manifest:
        return run_manifest(args)

    # ---- legacy directory-scan mode ----
    if not args.dry_run and not args.api_key:
        print("No API key: pass --api-key or set ROBLOX_API_KEY (or use --dry-run).", file=sys.stderr)
        return 2
    if not args.dry_run and not args.creator_id:
        print("No creator id: pass --creator-id (or use --dry-run).", file=sys.stderr)
        return 2
    if not args.inputs:
        print("Provide image files/directories, or use --manifest.", file=sys.stderr)
        return 2

    creator_field = "userId" if args.creator_type == "user" else "groupId"
    files = collect_files(args.inputs, args.pattern, args.recursive)
    if not files:
        print("No matching image files to upload.", file=sys.stderr)
        return 1

    results: dict[str, dict[str, Any]] = {}
    failed = 0
    for i, path in enumerate(files, 1):
        if args.dry_run:
            print(f"[{i}/{len(files)}] DRY-RUN would upload {path.name}", file=sys.stderr)
            continue
        try:
            asset_id, asset_type_used = upload_image(path, args.api_key, creator_field, args.creator_id, "HotFrog sprite", args.image_asset_type)
            if asset_type_used == "Image":
                results[path.stem] = {"decalId": None, "imageId": int(asset_id)}
                print(f"[{i}/{len(files)}] {path.name} -> image {asset_id} (assetType=Image)", file=sys.stderr)
            else:
                image_id = None if args.no_resolve else resolve_decal_to_image(int(asset_id), args.api_key, args.resolve_retries, args.resolve_wait, cookie=args.cookie, via=args.via)
                results[path.stem] = {"decalId": int(asset_id), "imageId": image_id}
                if image_id:
                    print(f"[{i}/{len(files)}] {path.name} -> decal {asset_id}, image {image_id}", file=sys.stderr)
                else:
                    print(f"[{i}/{len(files)}] {path.name} -> decal {asset_id}, image id NOT resolved yet", file=sys.stderr)
        except Exception as e:
            failed += 1
            results[path.stem] = {"decalId": None, "imageId": None, "error": str(e)}
            print(f"[{i}/{len(files)}] {path.name} FAILED: {e}", file=sys.stderr)
        time.sleep(args.delay)

    if args.dry_run:
        return 0

    payload = json.dumps(results, indent=2, sort_keys=True)
    if args.output:
        args.output.write_text(payload)
        print(f"Wrote {args.output}", file=sys.stderr)
    else:
        print(payload)

    if args.lua_out:
        lines = []
        for stem, r in sorted(results.items()):
            image_id = r.get("imageId")
            if image_id:
                lines.append(f"\t{stem} = {image_id},")
            else:
                lines.append(f"\t{stem} = 0, -- NOT resolved to an image id yet (decalId={r.get('decalId')!r}); re-run --resolve-only or see tools/resolve_decals.luau")
        args.lua_out.write_text(
            "-- paste into the Ids table of SkinAssets.luau (image ids only — see tools/README.md)\n" + "\n".join(lines) + "\n"
        )
        print(f"Wrote {args.lua_out}", file=sys.stderr)

    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
