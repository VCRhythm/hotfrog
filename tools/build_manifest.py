#!/usr/bin/env python3
"""build_manifest.py — scan /Sprites (in-repo) and the Unity Audio folder
(out-of-repo) and emit tools/asset_manifest.json: a deterministic, re-runnable
list of every art/audio asset the game needs, the Roblox upload "kind"
(image/audio), which src/shared table it belongs in, and the key that table
uses (a sprite file stem for images, an AudioManager-derived stem for audio —
both already match what SkinAssets.luau / SoundAssets.luau expect).

This is step 1 of the asset pipeline:
    build_manifest.py -> upload_to_roblox.py --manifest --dry-run (or for real)
    -> write_asset_ids.py

Usage:
    python tools/build_manifest.py
    python tools/build_manifest.py --audio-dir "D:\\path\\to\\Assets\\Audio"
    python tools/build_manifest.py -o tools/asset_manifest.json

The audio source tree lives outside the repo (it's the Unity project's
Assets/Audio). Default path is read from $ROBLOX_AUDIO_SRC, else a
known-machine fallback; if neither resolves, audio entries are still listed
(so the manifest documents the full sound roster) but marked skipped with
reason "source audio directory not found".
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
SPRITES_DIR = REPO_ROOT / "Sprites"
SKIN_CATALOG_PATH = REPO_ROOT / "src" / "shared" / "SkinCatalog.luau"

FALLBACK_AUDIO_DIR = Path(
    r"C:\Users\Tristan\OneDrive\Projects\Unity Projects-Acer14\Hawt Frog\Assets\Audio"
)

IMAGE_EXTS = {".png", ".jpg", ".jpeg", ".bmp", ".tga"}
MAP_SUFFIX_RE = re.compile(r"_(DEPTH|NORMALS|OCCLUSION)$", re.IGNORECASE)

# Roblox Open Cloud Assets API limits (create.roblox.com/docs/cloud/guides/usage-assets):
# max 20 MB per asset file; audio up to 7 minutes; images must be < 8000x8000px.
# We flag anything over a safety margin below that so upload_to_roblox.py can
# convert (ffmpeg) or the operator can shrink it by hand.
MAX_ASSET_BYTES = 20 * 1024 * 1024
CONVERSION_SAFETY_BYTES = 19 * 1024 * 1024
MAX_AUDIO_SECONDS = 7 * 60
AUDIO_SAFETY_SECONDS = MAX_AUDIO_SECONDS - 5


def read_skin_names() -> list[str]:
    """Parse `name = "..."` entries out of SkinCatalog.luau (data-only table,
    so a small regex is more robust here than a real Lua parser dependency)."""
    text = SKIN_CATALOG_PATH.read_text(encoding="utf-8")
    return re.findall(r'name\s*=\s*"([^"]+)"', text)


def rel(path: Path) -> str:
    resolved = path.resolve()
    try:
        return resolved.relative_to(REPO_ROOT).as_posix()
    except ValueError:
        return str(resolved)  # outside the repo (e.g. the external Audio folder)


def is_map_texture(stem: str) -> bool:
    return bool(MAP_SUFFIX_RE.search(stem))


def image_entry(key: str, path: Path, table: str, skin: str | None = None, note: str = "") -> dict:
    return {
        "key": key,
        "kind": "image",
        "source": rel(path),
        "table": table,
        "skin": skin,
        "size_bytes": path.stat().st_size,
        "needs_conversion": False,
        "note": note,
    }


def skipped(key: str, source, reason: str, kind: str = "image") -> dict:
    return {"key": key, "kind": kind, "source": (rel(source) if isinstance(source, Path) else source), "reason": reason}


# ---------------------------------------------------------------------------
# Images
# ---------------------------------------------------------------------------


def collect_frog_parts(skin_names: list[str]) -> tuple[list[dict], list[dict]]:
    entries: list[dict] = []
    skips: list[dict] = []
    frogs_dir = SPRITES_DIR / "Frogs"

    # Universal (shared pupils/sclera/tongue) -> SkinAssets "universal" section.
    universal_dir = frogs_dir / "Universal"
    if universal_dir.is_dir():
        for png in sorted(universal_dir.glob("*.png")):
            stem = png.stem
            if is_map_texture(stem):
                skips.append(skipped(stem, png, "normal/depth/occlusion map, not a display texture"))
                continue
            entries.append(image_entry(stem, png, "universal"))

    # Per-skin folders. Mystery Frog note: Unity ships three prefabs
    # (MysteryFrog1/2/3) but all three reference the *same* "Mystery Frog"
    # sprite set (verified against the referencePath fields in the .prefab
    # files) — they're recolors via Material tint, not separate art. There is
    # also exactly one SkinCatalog entry ("Mystery Frog"), so one sprite
    # folder -> one upload set is correct; no extra manifest handling needed.
    for name in skin_names:
        skin_dir = frogs_dir / name
        if not skin_dir.is_dir():
            skips.append(skipped(name, skin_dir, "SkinCatalog entry has no matching Sprites/Frogs/<name>/ folder"))
            continue
        pngs = sorted(p for p in skin_dir.glob("*.png") if p.is_file())
        if not pngs:
            skips.append(skipped(name, skin_dir, "skin folder has no top-level .png files"))
            continue
        for png in pngs:
            stem = png.stem
            if is_map_texture(stem):
                skips.append(skipped(stem, png, "normal/depth/occlusion map, not a display texture"))
                continue
            entries.append(image_entry(stem, png, "part", skin=name))

    return entries, skips


def collect_thumbnails(skin_names: list[str]) -> tuple[list[dict], list[dict]]:
    """Per-skin store thumbnails live in Sprites/Menu/<Prefix>Thumbnail.png,
    not inside the skin's own folder (some skin folders only have a leftover
    .mat for Thumbnail with no .png alongside it)."""
    entries: list[dict] = []
    skips: list[dict] = []
    menu_dir = SPRITES_DIR / "Menu"
    prefixes = {name: name.replace(" ", "") for name in skin_names}
    found_for = set()
    for png in sorted(menu_dir.glob("*Thumbnail.png")):
        stem = png.stem  # e.g. "HotFrogThumbnail"
        matched = None
        for name, prefix in prefixes.items():
            if stem == prefix + "Thumbnail":
                matched = name
                break
        if matched:
            entries.append(image_entry(stem, png, "part", skin=matched, note="store/UI thumbnail"))
            found_for.add(matched)
        else:
            entries.append(image_entry(stem, png, "ui", note="thumbnail with no matching SkinCatalog entry"))
    for name in skin_names:
        if name not in found_for:
            skips.append(
                skipped(
                    prefixes[name] + "Thumbnail",
                    menu_dir / f"{prefixes[name]}Thumbnail.png",
                    f"no Sprites/Menu/{prefixes[name]}Thumbnail.png on disk for skin '{name}'",
                )
            )
    return entries, skips


def collect_steps() -> tuple[list[dict], list[dict]]:
    entries: list[dict] = []
    skips: list[dict] = []
    rocks_dir = SPRITES_DIR / "Rocks"
    for png in sorted(rocks_dir.glob("*.png")):
        stem = png.stem
        if is_map_texture(stem):
            skips.append(skipped(stem, png, "normal/depth/occlusion map, not a display texture"))
            continue
        entries.append(image_entry(stem, png, "steps"))
    return entries, skips


# Sprites/Other + Sprites/Scenery classification. Explicit maps beat a
# heuristic here: there are ~60 files and misclassifying one silently is
# worse than a few lines of bookkeeping. table=None => not a manifest asset
# (handled separately as a skip with a reason).
OTHER_TABLE = {
    "Bug": "entities",
    "Wing1": "entities",
    "Wing2": "entities",
    "Wing3": "entities",
    "Speck": "entities",
    "Bubble": "scenery",
    "Chef": "scenery",
    "Cloud": "scenery",
    "Cloud2": "scenery",
    "Cloud3": "scenery",
    "Fork": "scenery",
    "Grass": "scenery",
    "LavaSplash": "scenery",
    "Leaf": "scenery",
    "Shelf": "scenery",
    "Spoon": "scenery",
    "Stars": "scenery",
    "Sun": "scenery",
    "Window": "scenery",
    "branch2": "scenery",
    "branch3": "scenery",
    "SplashBackground": "scenery",
    "Circle": "ui",
    "Arrow": "ui",
}
OTHER_SKIP_REASONS = {
    "FeatureImage": "store marketing asset, not used in-game",
    "Icon": "store marketing asset (app icon), not used in-game",
    "VFLogo": "store marketing asset (publisher logo), not used in-game",
    "PressCaution": "matches the 'Press*' store-marketing exclusion",
    "PressDone": "matches the 'Press*' store-marketing exclusion",
    # NOTE: PressIcon/PressImpactIcon are actually used in-game (Guidance.prefab's
    # touch-guidance finger icon per docs/roblox-port/12-unity-spawn-and-audio-data.md
    # section 6), not marketing — flagged here only because the task's exclusion
    # list explicitly said "Press*". Reconsider including them for phase covering
    # the Guidance/touch-indicator UI.
    "PressIcon": "matches the 'Press*' store-marketing exclusion (NOTE: actually gameplay touch-guidance art per doc 12 — reconsider)",
    "PressImpactIcon": "matches the 'Press*' store-marketing exclusion (NOTE: actually gameplay touch-guidance art per doc 12 — reconsider)",
}

SCENERY_TABLE = {
    "Flame": "scenery",
    "Flame2": "scenery",
    "Water": "scenery",
}
SCENERY_SKIP_REASONS = {
    "NorthAmerica": "not referenced by any extracted Unity prefab/script data; not in the task's scenery inclusion list — likely unused minigame/easter-egg art",
    "USBlueStates": "not referenced by any extracted Unity prefab/script data; not in the task's scenery inclusion list — likely unused minigame/easter-egg art",
    "USRedStates": "not referenced by any extracted Unity prefab/script data; not in the task's scenery inclusion list — likely unused minigame/easter-egg art",
}

MENU_UI_SKIP = set()  # non-thumbnail Menu files are all included as "ui"


def collect_other_and_scenery() -> tuple[list[dict], list[dict]]:
    entries: list[dict] = []
    skips: list[dict] = []

    other_dir = SPRITES_DIR / "Other"
    for png in sorted(other_dir.glob("*.png")):
        stem = png.stem
        if is_map_texture(stem):
            skips.append(skipped(stem, png, "normal/depth/occlusion map, not a display texture"))
            continue
        if stem in OTHER_SKIP_REASONS:
            skips.append(skipped(stem, png, OTHER_SKIP_REASONS[stem]))
            continue
        table = OTHER_TABLE.get(stem)
        if table is None:
            # Unclassified but not explicitly excluded: include defensively as
            # scenery rather than silently drop it.
            entries.append(image_entry(stem, png, "scenery", note="unclear usage — included defensively, not in the task's explicit inclusion list"))
            continue
        entries.append(image_entry(stem, png, table))

    scenery_dir = SPRITES_DIR / "Scenery"
    for png in sorted(scenery_dir.glob("*.png")):
        stem = png.stem
        if stem in SCENERY_SKIP_REASONS:
            skips.append(skipped(stem, png, SCENERY_SKIP_REASONS[stem]))
            continue
        table = SCENERY_TABLE.get(stem, "scenery")
        entries.append(image_entry(stem, png, table))

    return entries, skips


def collect_menu_ui(skin_names: list[str]) -> list[dict]:
    entries: list[dict] = []
    menu_dir = SPRITES_DIR / "Menu"
    prefixes = {name.replace(" ", "") + "Thumbnail" for name in skin_names}
    for png in sorted(menu_dir.glob("*.png")):
        stem = png.stem
        if stem.endswith("Thumbnail"):
            continue  # handled by collect_thumbnails
        entries.append(image_entry(stem, png, "ui"))
    return entries


def collect_top_level_ui() -> list[dict]:
    entries: list[dict] = []
    for ext in ("*.png", "*.tga"):
        for path in sorted(SPRITES_DIR.glob(ext)):
            entries.append(
                image_entry(
                    path.stem,
                    path,
                    "ui",
                    note="Roblox Decal API accepts .tga directly (image/tga) — no Pillow conversion needed" if path.suffix.lower() == ".tga" else "",
                )
            )
    return entries


# ---------------------------------------------------------------------------
# Audio
# ---------------------------------------------------------------------------

# (key, filename relative to Audio dir, table) — keys marked "existing" must
# stay exactly as-is: they're already called from src/client (SoundFX.play(...)).
ONE_SHOT_SOUNDS = [
    ("grab", "Grab.wav"),  # existing key — SoundFX.play("grab") in GameClient.client.luau
    ("crumble", "Crumble.wav"),  # existing key
    ("crumbleShort", "CrumbleShort.wav"),  # existing key — SoundFX.play("crumbleShort") in Effects.client.luau
    ("fall", "Fall.wav"),  # existing key — SoundFX.play("fall") in Effects.client.luau
    ("fly", "Flys.wav"),  # existing key; AudioManager field "flySound" looks up clip named "Flys"
    ("slurp", "Slurp.wav"),  # existing key — SoundFX.play("slurp") in GameClient.client.luau
    ("squish", "Squish.wav"),  # existing key — SoundFX.play("squish") in Effects.client.luau
    ("awake", "Awake.wav"),  # existing key
    ("miss", "Miss.wav"),  # existing key — SoundFX.play("miss") in GameClient.client.luau
    ("holdOnVoice", "HoldOnVO.wav"),  # existing key
    ("blink", "Blink.wav"),
    ("select", "Select.wav"),
    ("hurt", "Hurt.wav"),
    ("new", "New.wav"),
    ("highScore", "HighScore.wav"),
    ("base10", "Base10.wav"),
    ("boilVoice", "BoilAFrogVO.wav"),
    ("perfectVoice", "PerfectVO.wav"),
    ("okVoice", "OKVO.wav"),
    ("greatVoice", "GreatVO.wav"),
    ("splash", "Splash.wav"),
    ("hotFrogVO", "HotFrogVO.wav"),  # Frog.cs audioIntroduction — wired directly, not by AudioManager name lookup
    ("pop", "Pop.wav"),  # Bubble.prefab Spawn.grabClip — wired directly
    ("leaves", "Leaves.wav"),  # FirstTree*.prefab AudioSource.m_audioClip — wired directly, not via AudioManager
]

MUSIC = [
    ("music1", "Music/BrusselSprouts.wav"),  # existing key — musicClips[0]
    ("music2", "Music/FrogSounds.wav"),  # existing key — musicClips[1]
    ("music3", "Music/Opening.mp3"),  # existing key — musicClips[2]
    ("music4", "Music/Adenine.mp3"),  # NEW — musicClips[3], previously missing from SoundAssets.luau
]

AUDIO_SKIP_REASONS = {
    "MegaManDeath.wav": "third-party copyrighted audio (Mega Man death jingle) — excluded from the port",
    "MegaManDeath2.wav": "third-party copyrighted audio (Mega Man death jingle) — excluded from the port",
    "Awake-old1.wav": "superseded duplicate ('-old' suffix) of Awake.wav",
}

# Present on disk, not referenced by AudioManager.soundClips[]/musicClips[] or
# any directly-wired clip field (per docs/roblox-port/12-unity-spawn-and-audio-data.md
# "Audio files on disk not referenced by AudioManager's arrays"). Listed as
# optional/skipped rather than silently dropped.
UNREFERENCED_OPTIONAL = [
    "BusinessVO.wav",
    "EvenHotterVO.wav",
    "ExpensiveVO.wav",
    "ExploreVO.wav",
    "FryingPanVO.wav",
    "GoodVO.wav",
    "HomageVO.wav",
    "NoSelect.wav",
    "NothingVO.wav",
    "SeeHimVO.wav",
    "VeryHotVO.wav",
    "Music/Two Wrongs.wav",
]


def ffprobe_duration(path: Path) -> float | None:
    try:
        out = subprocess.run(
            ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(path)],
            capture_output=True,
            text=True,
            timeout=30,
        )
        if out.returncode == 0 and out.stdout.strip():
            return float(out.stdout.strip())
    except (OSError, ValueError, subprocess.TimeoutExpired):
        pass
    return None


def audio_entry(key: str, path: Path, table: str) -> dict:
    size = path.stat().st_size
    duration = ffprobe_duration(path)
    needs_conversion = size > CONVERSION_SAFETY_BYTES or (duration is not None and duration > AUDIO_SAFETY_SECONDS)
    e = {
        "key": key,
        "kind": "audio",
        "source": str(path),  # outside the repo; not repo-relative
        "table": table,
        "skin": None,
        "size_bytes": size,
        "duration_seconds": duration,
        "needs_conversion": needs_conversion,
        "note": "",
    }
    if needs_conversion:
        e["note"] = (
            f"over the Open Cloud Assets API's 20MB/7min limit (size={size} bytes"
            + (f", duration={duration:.1f}s" if duration is not None else "")
            + "); upload_to_roblox.py will transcode via ffmpeg to mp3 before upload if ffmpeg is on PATH, else this entry is skipped with needs_conversion=true"
        )
    return e


def collect_audio(audio_dir: Path | None) -> tuple[list[dict], list[dict]]:
    entries: list[dict] = []
    skips: list[dict] = []

    if audio_dir is None or not audio_dir.is_dir():
        reason = f"source audio directory not found ({audio_dir}) — set --audio-dir or $ROBLOX_AUDIO_SRC"
        for key, filename in ONE_SHOT_SOUNDS + MUSIC:
            skips.append(skipped(key, filename, reason, kind="audio"))
        skips.append(skipped("leafSound", "(none)", "AudioManager field 'leafSound' looks up clip name 'LeafSound', which doesn't exist in soundClips[] — unresolved/null at runtime in the original game; no asset to upload", kind="audio"))
        for filename in UNREFERENCED_OPTIONAL:
            skips.append(skipped(Path(filename).stem, filename, "not referenced by AudioManager.soundClips[]/musicClips[] or any directly-wired clip field — optional, not uploaded by default", kind="audio"))
        for filename in AUDIO_SKIP_REASONS:
            skips.append(skipped(Path(filename).stem, filename, AUDIO_SKIP_REASONS[filename], kind="audio"))
        return entries, skips

    for key, filename in ONE_SHOT_SOUNDS:
        path = audio_dir / filename
        if not path.is_file():
            skips.append(skipped(key, path, "expected file not found on disk", kind="audio"))
            continue
        entries.append(audio_entry(key, path, "sound"))

    for key, filename in MUSIC:
        path = audio_dir / filename
        if not path.is_file():
            skips.append(skipped(key, path, "expected file not found on disk", kind="audio"))
            continue
        entries.append(audio_entry(key, path, "sound"))

    skips.append(
        skipped(
            "leafSound",
            audio_dir / "LeafSound.wav",
            "AudioManager field 'leafSound' looks up clip name 'LeafSound', which doesn't exist in soundClips[] — unresolved/null at runtime in the original game; no asset to upload",
            kind="audio",
        )
    )

    for filename in AUDIO_SKIP_REASONS:
        path = audio_dir / filename
        if path.is_file():
            skips.append(skipped(Path(filename).stem, path, AUDIO_SKIP_REASONS[filename], kind="audio"))

    for filename in UNREFERENCED_OPTIONAL:
        path = audio_dir / filename
        if path.is_file():
            skips.append(
                skipped(
                    Path(filename).stem,
                    path,
                    "not referenced by AudioManager.soundClips[]/musicClips[] or any directly-wired clip field (see docs/roblox-port/12-unity-spawn-and-audio-data.md) — optional, not uploaded by default",
                    kind="audio",
                )
            )

    return entries, skips


# ---------------------------------------------------------------------------


def build(audio_dir: Path | None) -> dict:
    skin_names = read_skin_names()

    all_entries: list[dict] = []
    all_skips: list[dict] = []

    for fn in (
        lambda: collect_frog_parts(skin_names),
        lambda: collect_thumbnails(skin_names),
        lambda: collect_steps(),
        lambda: collect_other_and_scenery(),
    ):
        e, s = fn()
        all_entries.extend(e)
        all_skips.extend(s)

    all_entries.extend(collect_menu_ui(skin_names))
    all_entries.extend(collect_top_level_ui())

    audio_entries, audio_skips = collect_audio(audio_dir)
    all_entries.extend(audio_entries)
    all_skips.extend(audio_skips)

    # De-dupe by key, deterministic order: stray/duplicate files (e.g. a
    # sprite left directly under Sprites/Frogs/ instead of inside its skin
    # folder) never enter `all_entries` in the first place because collection
    # only walks known folders — but guard anyway in case two buckets
    # produced the same key.
    seen: dict[str, dict] = {}
    deduped: list[dict] = []
    for e in all_entries:
        if e["key"] in seen:
            all_skips.append(skipped(e["key"], e["source"], f"duplicate key, already provided by {seen[e['key']]['source']}", kind=e["kind"]))
            continue
        seen[e["key"]] = e
        deduped.append(e)

    deduped.sort(key=lambda e: (e["kind"], e["table"], e["skin"] or "", e["key"]))
    all_skips.sort(key=lambda e: (e["kind"], e["key"]))

    by_kind: dict[str, int] = {}
    by_table: dict[str, int] = {}
    for e in deduped:
        by_kind[e["kind"]] = by_kind.get(e["kind"], 0) + 1
        by_table[e["table"]] = by_table.get(e["table"], 0) + 1
    needs_conversion_count = sum(1 for e in deduped if e.get("needs_conversion"))

    return {
        "$schema_note": "Generated by tools/build_manifest.py — do not hand edit, re-run instead.",
        "skin_names": skin_names,
        "summary": {
            "entries": len(deduped),
            "skipped": len(all_skips),
            "by_kind": by_kind,
            "by_table": by_table,
            "needs_conversion": needs_conversion_count,
        },
        "entries": deduped,
        "skipped": all_skips,
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--audio-dir", type=Path, default=None, help="Unity Assets/Audio folder (outside the repo). Default: $ROBLOX_AUDIO_SRC or a known-machine fallback.")
    ap.add_argument("-o", "--output", type=Path, default=REPO_ROOT / "tools" / "asset_manifest.json")
    args = ap.parse_args()

    audio_dir = args.audio_dir or (Path(os.environ["ROBLOX_AUDIO_SRC"]) if os.environ.get("ROBLOX_AUDIO_SRC") else FALLBACK_AUDIO_DIR)
    manifest = build(audio_dir)

    args.output.write_text(json.dumps(manifest, indent=2, sort_keys=False) + "\n", encoding="utf-8")
    s = manifest["summary"]
    print(f"Wrote {args.output} — {s['entries']} entries ({s['by_kind']}), {s['skipped']} skipped, {s['needs_conversion']} need conversion.", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
