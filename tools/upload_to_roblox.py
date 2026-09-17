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

Setup:
  pip install -r tools/requirements.txt
  - Create an Open Cloud API key (create.roblox.com -> Creator Hub -> Open Cloud
    -> API Keys) with:
      * the **assets** API, Read + Write (create.roblox.com/docs/cloud/guides/usage-assets;
        for OAuth apps the equivalent scopes are asset:read / asset:write) — required
        for every upload;
      * the **legacy-asset:manage** scope — required for the decal->image id
        resolution step below (Asset Delivery API). If you don't want to grant
        that scope, use --no-resolve and the tools/resolve_decals.luau Studio
        fallback instead (see tools/README.md).
    Add your IP range (or use a key with no IP restriction for local runs).
  - Note your creator id: your user id, or a group id if the assets belong to a
    group. Assets you upload are owned by that creator.
  - export ROBLOX_API_KEY=...  (or pass --api-key). Never pass it as a bare CLI
    literal in a shared shell history if you can avoid it; the key is only ever
    read into memory here — this script never writes it to a file or log.

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
      same file formats — CONFIRMED from Roblox's docs source. Whether
      assetType="Image" returns a usable image id directly (skipping the whole
      decal problem) is UNVERIFIED: no example of anyone actually using
      assetType="Image" for a create call was found in DevForum threads or
      community tooling (rblx-open-cloud, Asphalt, the "OpenCloud | Assets
      API" community tutorial) — they all use "Decal". By default
      (--image-asset-type auto) this script tries "Image" first anyway (since
      it's documented) and falls back to "Decal" only if the API rejects that
      assetType outright; either way the id that lands in asset_ids.json is
      recorded honestly (assetType field) so you can tell which path was used.
    - When a Decal is uploaded, the script resolves it to its Image id via the
      Open Cloud **Asset Delivery API**
      (`GET https://apis.roblox.com/asset-delivery-api/v1/assetId/{decalId}`,
      scope `legacy-asset:manage` — endpoint and scope CONFIRMED from Roblox's
      creator-docs source (github.com/Roblox/creator-docs PR #1056) and a
      DevForum reply from Roblox community contributor Maximum_ADHD that it
      streams the asset's raw content back for an authorized caller). For a
      Decal, that content is the classic Roblox legacy asset format containing
      either `rbxassetid://<imageId>` or `http://www.roblox.com/asset/?id=
      <imageId>` — this exact byte-for-byte shape is long-standing, widely
      documented Roblox community knowledge but was NOT independently
      confirmed against a live response while writing this (no API key was
      available). The parser (`resolve_decal_to_image`) is deliberately
      loose — a regex over the raw response bytes — so it should survive minor
      format differences; if it doesn't work for you, use the
      tools/resolve_decals.luau Studio fallback instead (`InsertService:LoadAsset`,
      Studio-only, always works because Studio does this resolution for real).
    - Freshly uploaded images are often not yet moderated, so resolution can
      fail with "not available yet" right after upload; the script retries
      (--resolve-retries / --resolve-wait) and, if still unresolved, caches the
      decal id with status "pending-resolution" — re-run with --resolve-only
      later (no re-upload).
    - `tools/write_asset_ids.py` will ONLY ever write a resolved imageId into
      SkinAssets.luau's Ids table; a key with a decal id but no image id is
      left untouched (and a warning is printed with the count), so a bad
      decal-as-image id can never land in the Luau tables silently.

  Audio is uploaded as assetType "Audio"; the returned id works directly in
  Sound.SoundId as "rbxassetid://<id>" (audio has no Decal/Image split) — what
  SoundAssets.id() assumes. Audio entries are unaffected by any of the above.

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

ASSETS_URL = "https://apis.roblox.com/assets/v1/assets"
OPERATION_URL = "https://apis.roblox.com/assets/v1/operations/{}"
ASSET_DELIVERY_URL = "https://apis.roblox.com/asset-delivery-api/v1/assetId/{}"

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


def resolve_decal_to_image(decal_id: int, api_key: str, retries: int, wait: float) -> int | None:
    """Resolve a Decal asset id to its underlying Image asset id via the Open
    Cloud Asset Delivery API. See the "IMPORTANT: Decal ids vs. Image ids"
    section of this module's docstring for exactly what's confirmed vs. not
    about this endpoint and response format. Returns None (after `retries`
    attempts, with increasing backoff) if it can't be resolved yet — most
    commonly because the asset hasn't cleared moderation."""
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

    print(f"[resolve] decal {decal_id}: not resolved after {retries} attempt(s) ({last_status})", file=sys.stderr)
    return None


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

    dry = args.dry_run
    if not dry and not args.api_key:
        print("No API key: pass --api-key, set ROBLOX_API_KEY, or use --dry-run.", file=sys.stderr)
        return 2
    if not dry and not args.creator_id:
        print("No creator id: pass --creator-id, or use --dry-run.", file=sys.stderr)
        return 2

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
            hint = "assetType=Image, falls back to Decal+resolve" if is_image else "assetType=Audio"
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
                entry_cache["status"] = "resolved-direct (assetType=Image; unverified whether this differs from Decal — spot-check in Studio)"
                print(f"{tag}: -> image {asset_id} (assetType=Image, no resolution needed)", file=sys.stderr)
            else:
                entry_cache["decalId"] = int(asset_id)
                image_id = None if args.no_resolve else resolve_decal_to_image(int(asset_id), args.api_key, args.resolve_retries, args.resolve_wait)
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
                asset_id = upload(upload_path, args.api_key, creator_field, args.creator_id, description)
            except Exception as e:
                failed += 1
                print(f"{tag}: FAILED: {e}", file=sys.stderr)
                time.sleep(args.delay)
                continue
            cache[key] = {
                "kind": entry["kind"],
                "table": entry["table"],
                "assetId": int(asset_id),
                "sourceHash": file_hash,
                "uploadedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            }
            print(f"{tag}: -> {asset_id}", file=sys.stderr)

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
        print("Run `python tools/upload_to_roblox.py --resolve-only` again in a bit to pick up moderation-cleared ids.", file=sys.stderr)
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

    if not args.api_key:
        keys_preview = ", ".join(k for k, _ in pending[:20]) + (", ..." if len(pending) > 20 else "")
        print(
            f"{len(pending)} entries still need resolution but no API key is set ({keys_preview}). "
            f"Pass --api-key/$ROBLOX_API_KEY to retry via the Asset Delivery API, or use "
            f"tools/resolve_decals.luau in Studio and save its output as {args.decal_image_ids}, "
            f"then re-run --resolve-only.",
            file=sys.stderr,
        )
        return 1

    resolved = still_pending = 0
    for key, entry in pending:
        image_id = resolve_decal_to_image(entry["decalId"], args.api_key, args.resolve_retries, args.resolve_wait)
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
    return 0 if still_pending == 0 else 1


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
    ap.add_argument("--api-key", default=os.environ.get("ROBLOX_API_KEY"), help="Open Cloud key (or $ROBLOX_API_KEY). Never written to disk/logs by this script.")
    ap.add_argument("--creator-id", default=None, help="Owning user id or group id. Required unless --dry-run.")
    ap.add_argument("--creator-type", choices=("user", "group"), default="user")
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

    if args.emit_studio_resolver:
        return run_emit_studio_resolver(args)

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
                image_id = None if args.no_resolve else resolve_decal_to_image(int(asset_id), args.api_key, args.resolve_retries, args.resolve_wait)
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
