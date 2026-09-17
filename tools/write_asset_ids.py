#!/usr/bin/env python3
"""write_asset_ids.py — rewrite the `Ids` table in src/shared/SkinAssets.luau
and src/shared/SoundAssets.luau in place from tools/asset_manifest.json (the
full list of keys that should exist) and tools/asset_ids.json (key -> uploaded
id info, written by upload_to_roblox.py).

- Any key already written by hand in the file gets its number updated in
  place (indentation and trailing comment preserved) if asset_ids.json has a
  usable id for it; otherwise that line is left untouched.
- Any manifest key with NO line anywhere in the file is appended, grouped by
  table/skin, under a clearly marked auto-generated block at the end of the
  Ids table (`0` if asset_ids.json has no id for it yet).
- Idempotent: the auto-generated block is fully rebuilt from the manifest +
  cache on every run (not incrementally patched), so running twice with the
  same inputs produces byte-identical output.
- Never touches anything outside the `local Ids: { [string]: number } = { ... }`
  block, so the rest of the file (comments, SkinAssets.image/part/prefix,
  SoundAssets.id) is untouched.

IMPORTANT — images: only a resolved `imageId` is ever written into
SkinAssets.luau. Uploading an image creates a Decal wrapper around the actual
Image asset; the Open Cloud Assets API returns the Decal's id, and a Decal id
poked into `Decal.Texture`/`ImageLabel.Image` from a script does NOT render at
runtime (only Studio's property editor resolves a pasted decal id for you
interactively). `upload_to_roblox.py` resolves each decal to its image id and
caches both (`decalId`, `imageId`); if a key only has a `decalId` (resolution
hasn't completed yet — e.g. still moderating), this script leaves that key's
existing value untouched (0, or whatever was there) and prints a warning with
the count, so a bad decal-as-image id can never land in the Ids table
silently. See tools/README.md for how to finish resolution
(`upload_to_roblox.py --resolve-only`, or the tools/resolve_decals.luau Studio
fallback). Audio has no such split — its cached `assetId` is used directly.

Usage:
    python tools/write_asset_ids.py
    python tools/write_asset_ids.py --manifest tools/asset_manifest.json \\
        --ids tools/asset_ids.json \\
        --skin-assets src/shared/SkinAssets.luau \\
        --sound-assets src/shared/SoundAssets.luau
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

TABLE_BLOCK_RE = re.compile(r"(local Ids: \{ \[string\]: number \} = \{)(.*?)(\n\})", re.DOTALL)
KEY_LINE_RE = re.compile(r"^([ \t]*)([A-Za-z_][A-Za-z0-9_]*)([ \t]*=[ \t]*)-?\d+(.*)$")

AUTO_SENTINEL = "-- ==== Auto-added by tools/write_asset_ids.py"
AUTO_BLOCK_RE = re.compile(r"\n*\t" + re.escape(AUTO_SENTINEL) + r".*$", re.DOTALL)

SKIN_TABLE_ORDER = ["universal", "steps", "entities", "scenery", "ui"]
SKIN_TABLE_TITLE = {
    "universal": "Universal",
    "steps": "Steps",
    "entities": "Entities",
    "scenery": "Scenery",
    "ui": "UI / Menu",
}


def load_json(path: Path) -> dict:
    if not path.exists():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def audio_id_map(ids_cache: dict) -> dict[str, int]:
    """key -> assetId for audio entries. Audio has no Decal/Image split (an
    uploaded audio asset's id is directly usable in Sound.SoundId), so this is
    unchanged from before."""
    out: dict[str, int] = {}
    for key, v in ids_cache.items():
        if not isinstance(v, dict) or v.get("kind") not in (None, "audio"):
            continue
        aid = v.get("assetId")
        if isinstance(aid, (int, float)) and aid:
            out[key] = int(aid)
    return out


def image_id_map(ids_cache: dict) -> tuple[dict[str, int], list[str]]:
    """Returns (key -> imageId, [keys with a decalId but no resolved imageId
    yet]). Only ever returns *resolved* image ids — a key that only has a
    cached decalId is deliberately excluded from the map (not written as a
    placeholder id) so a Decal id, which does not render when poked into
    Decal.Texture/ImageLabel.Image from a script, can never land in
    SkinAssets.luau silently. See tools/upload_to_roblox.py's module
    docstring for why the API returns a decal id in the first place."""
    out: dict[str, int] = {}
    decal_only: list[str] = []
    for key, v in ids_cache.items():
        if not isinstance(v, dict) or v.get("kind") != "image":
            continue
        img = v.get("imageId")
        if isinstance(img, (int, float)) and img:
            out[key] = int(img)
        elif v.get("decalId"):
            decal_only.append(key)
    return out, sorted(decal_only)


def existing_keys(body_no_auto: str) -> set[str]:
    keys = set()
    for line in body_no_auto.splitlines():
        m = KEY_LINE_RE.match(line)
        if m:
            keys.add(m.group(2))
    return keys


def update_in_place(body: str, id_map: dict[str, int]) -> str:
    lines = body.splitlines(keepends=True)
    out_lines = []
    for line in lines:
        m = KEY_LINE_RE.match(line.rstrip("\n"))
        if m:
            indent, key, eq, rest = m.groups()
            if key in id_map:
                newline = "\n" if line.endswith("\n") else ""
                out_lines.append(f"{indent}{key}{eq}{id_map[key]}{rest}{newline}")
                continue
        out_lines.append(line)
    return "".join(out_lines)


def strip_auto_block(body: str) -> str:
    return AUTO_BLOCK_RE.sub("", body).rstrip("\n")


def build_auto_block_skin_assets(missing: list[dict], id_map: dict[str, int]) -> str:
    if not missing:
        return ""
    by_table: dict[str, list[dict]] = {}
    by_skin: dict[str, list[dict]] = {}
    for e in missing:
        if e["table"] == "part":
            by_skin.setdefault(e["skin"], []).append(e)
        else:
            by_table.setdefault(e["table"], []).append(e)

    lines = [f"\n\n\t{AUTO_SENTINEL} — keys from tools/asset_manifest.json not yet listed above.", "\t-- Re-running regenerates this block; hand-organize above the sentinel if you want a key to stay put. ===="]
    for table in SKIN_TABLE_ORDER:
        entries = sorted(by_table.get(table, []), key=lambda e: e["key"])
        if not entries:
            continue
        lines.append(f"\n\t-- {SKIN_TABLE_TITLE[table]} (auto)")
        for e in entries:
            lines.append(f"\t{e['key']} = {id_map.get(e['key'], 0)},")

    for skin in sorted(by_skin):
        entries = sorted(by_skin[skin], key=lambda e: e["key"])
        lines.append(f"\n\t-- {skin} (auto)")
        for e in entries:
            lines.append(f"\t{e['key']} = {id_map.get(e['key'], 0)},")

    return "\n".join(lines)


def build_auto_block_sound_assets(missing: list[dict], id_map: dict[str, int]) -> str:
    if not missing:
        return ""
    music = sorted([e for e in missing if e["key"].startswith("music")], key=lambda e: e["key"])
    one_shots = sorted([e for e in missing if not e["key"].startswith("music")], key=lambda e: e["key"])

    lines = [f"\n\n\t{AUTO_SENTINEL} — keys from tools/asset_manifest.json not yet listed above.", "\t-- Re-running regenerates this block; hand-organize above the sentinel if you want a key to stay put. ===="]
    if one_shots:
        lines.append("\n\t-- one-shots (auto)")
        for e in one_shots:
            lines.append(f"\t{e['key']} = {id_map.get(e['key'], 0)},")
    if music:
        lines.append("\n\t-- music (auto)")
        for e in music:
            lines.append(f"\t{e['key']} = {id_map.get(e['key'], 0)},")
    return "\n".join(lines)


def rewrite_file(path: Path, manifest_entries: list[dict], id_map: dict[str, int], build_auto_block) -> bool:
    """Returns True if the file's content changed."""
    text = path.read_text(encoding="utf-8")
    m = TABLE_BLOCK_RE.search(text)
    if not m:
        raise RuntimeError(f"{path}: couldn't find 'local Ids: {{ [string]: number }} = {{ ... }}' block")
    header, body, footer = m.group(1), m.group(2), m.group(3)

    hand_body = strip_auto_block(body)
    present = existing_keys(hand_body)
    hand_body = update_in_place(hand_body, id_map)

    missing = [e for e in manifest_entries if e["key"] not in present]
    auto_block = build_auto_block(missing, id_map)

    # `footer` already begins with the "\n" that precedes the closing "}", so
    # new_body must NOT end with its own trailing newline (else we'd double it).
    new_body = (hand_body.rstrip("\n") + (auto_block if auto_block else "")).rstrip("\n")
    new_text = text[: m.start()] + header + new_body + footer + text[m.end() :]

    changed = new_text != text
    if changed:
        path.write_text(new_text, encoding="utf-8")
    return changed


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--manifest", type=Path, default=REPO_ROOT / "tools" / "asset_manifest.json")
    ap.add_argument("--ids", type=Path, default=REPO_ROOT / "tools" / "asset_ids.json")
    ap.add_argument("--skin-assets", type=Path, default=REPO_ROOT / "src" / "shared" / "SkinAssets.luau")
    ap.add_argument("--sound-assets", type=Path, default=REPO_ROOT / "src" / "shared" / "SoundAssets.luau")
    args = ap.parse_args()

    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    ids_cache = load_json(args.ids)
    image_ids, decal_only_keys = image_id_map(ids_cache)
    audio_ids = audio_id_map(ids_cache)

    image_entries = [e for e in manifest["entries"] if e["kind"] == "image"]
    audio_entries = [e for e in manifest["entries"] if e["kind"] == "audio"]

    changed_skin = rewrite_file(args.skin_assets, image_entries, image_ids, build_auto_block_skin_assets)
    changed_sound = rewrite_file(args.sound_assets, audio_entries, audio_ids, build_auto_block_sound_assets)

    print(f"{args.skin_assets}: {'updated' if changed_skin else 'already up to date'}", file=sys.stderr)
    print(f"{args.sound_assets}: {'updated' if changed_sound else 'already up to date'}", file=sys.stderr)

    if decal_only_keys:
        preview = ", ".join(decal_only_keys[:20]) + (", ..." if len(decal_only_keys) > 20 else "")
        print(
            f"[warn] {len(decal_only_keys)} image key(s) have an uploaded Decal id but no resolved Image "
            f"id yet — left untouched rather than writing an unusable decal id: {preview}. Run "
            f"`python tools/upload_to_roblox.py --resolve-only` (once moderation clears) or use "
            f"tools/resolve_decals.luau in Studio, then re-run this script.",
            file=sys.stderr,
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
