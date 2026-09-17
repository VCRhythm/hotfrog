# tools/

Sprite-prep utilities for HotFrog (a Unity 2D project). Ported from the
`scare` project's toolset, trimmed to the engine-agnostic image tools and
adapted for Unity (PNG output, no power-of-two padding by default).

Run all commands from the **project root**.

## Setup

```bat
pip install -r tools/requirements.txt
```

(`Pillow` for the converters, `numpy` for `pixel_pass.py`, `requests` for
`upload_to_catbox.py`.)

---

## `webp_to_png.py`

Convert `.webp` images to `.png`. AI art tools and asset packs often ship
`.webp`; Unity's sprite importer wants `.png`. Accepts files or directories.

```bat
python tools/webp_to_png.py art.webp
python tools/webp_to_png.py Sprites/_incoming --recursive
python tools/webp_to_png.py a.webp b.webp --output Sprites/converted
```

## `remove_bg.py`

Remove a solid/near-solid background, then crop tight to the visible content.
Edge-connected flood fill, so enclosed details aren't punched through.
Tight crop by default (no square/POT canvas — Unity sprites don't need one).

```bat
python tools/remove_bg.py Sprites/Frogs/_src/blue_frog.png
python tools/remove_bg.py Sprites/Frogs --recursive --output Sprites/processed
python tools/remove_bg.py icon.png --background 255,255,255 --tolerance 20

# Legacy icon mode: re-center on a square power-of-4 canvas
python tools/remove_bg.py icon.png --pad-square
```

## `pixel_pass.py`

Bake a sprite into a consistent low-res pixel-art look: premultiplied-alpha
downscale → median-cut palette quantize (no dither) → crisp alpha →
integer nearest-neighbour upscale. Outputs PNG (pass `--webp` for lossless WebP).

```bat
# Light sprite, default settings
python tools/pixel_pass.py --out-dir Sprites/Frogs/Processed \
    Sprites/Frogs/_src/blue_frog.png

# Dark sprite: brighten shadows + add an edge rim
python tools/pixel_pass.py --out-dir Sprites/Other/Processed --lift --rim 32 \
    Sprites/Other/_src/shadow_rock.png
```

Key flags: `--grid` (downscale resolution, default 48), `--colors` (palette
size, default 32), `--scale` (integer upscale factor, default 6),
`--desaturate` (neutral grey for tintable sprites).

## `upload_to_catbox.py`

Upload images to [catbox.moe](https://catbox.moe) and print a `{name: url}`
JSON map. Useful for sharing sprite art as direct links in design docs, chats,
or issues without committing binaries somewhere public. Anonymous upload, no key.

```bat
python tools/upload_to_catbox.py "Sprites/Frogs/Blue Frog/BlueFrogBody.png"
python tools/upload_to_catbox.py Sprites/Menu --pattern "*.png" -o urls.json
python tools/upload_to_catbox.py Sprites/Frogs --recursive
```

Accepts files and/or directories; `--pattern` filters directory inputs only.

## The full asset pipeline (one command per step, ~200 ids, no hand-pasting)

Four commands take every sprite in `/Sprites` plus every sound in the Unity
project's `Assets/Audio` folder, upload them to Roblox, and fill in the id
tables in `src/shared/SkinAssets.luau` / `SoundAssets.luau`:

```bat
:: 1. Scan /Sprites + the Unity Audio folder, write tools/asset_manifest.json
::    (deterministic, re-runnable; excludes marketing art, normal/depth/occlusion
::    maps, third-party-copyrighted audio, and "-old" duplicates; flags oversized
::    audio as needs_conversion).
python tools/build_manifest.py
:: (if the Unity Audio folder isn't at the default path on your machine:)
python tools/build_manifest.py --audio-dir "D:\path\to\Assets\Audio"

:: 2. Dry run first — no network calls, no API key needed. Prints exactly what
::    would upload (and what would be transcoded) so you can sanity-check counts.
python tools/upload_to_roblox.py --manifest tools/asset_manifest.json ^
    --creator-id 1234567 --creator-type user --dry-run

:: 3. The real upload. Needs an Open Cloud API key (create.roblox.com ->
::    Creator Hub -> Open Cloud -> API Keys) with:
::      - the **assets** API, Read+Write, and your IP range added (required
::        for every upload; OAuth apps use scopes asset:read/asset:write)
::      - the **legacy-asset:manage** scope (required for the decal->image id
::        resolution step below — see "IMAGE IDS, NOT DECAL IDS")
::    and your creator id (your user id, or a group id if the assets should
::    belong to a group). Results are cached in tools/asset_ids.json (image
::    keys get decalId+imageId+status, audio keys get assetId), so a
::    failed/partial run just resumes — re-run the same command and
::    unchanged/already-uploaded files are skipped.
::
::    STRONGLY RECOMMENDED before running the full ~173-image batch: upload
::    ONE image first and confirm it actually renders on a part in Studio —
::    catching a bad id/scope/resolution problem on 1 asset is a lot cheaper
::    than on 173:
::      python tools/upload_to_roblox.py --manifest tools/asset_manifest.json ^
::          --creator-id 1234567 --creator-type user --keys HotFrogBody
::      python tools/write_asset_ids.py
::      :: then in Studio: put that one id on a test Decal/ImageLabel and look at it.
set ROBLOX_API_KEY=...
python tools/upload_to_roblox.py --manifest tools/asset_manifest.json ^
    --creator-id 1234567 --creator-type user

:: 4. Write the cached ids into SkinAssets.luau / SoundAssets.luau in place —
::    idempotent, preserves hand-written comments/formatting, and adds
::    placeholder `= 0` entries (grouped, auto-labeled) for any manifest key
::    that isn't in the file yet. Only *resolved* image ids are ever written
::    (see below) — anything still pending resolution is left at 0 with a
::    warning printed, never a wrong-but-nonzero id.
python tools/write_asset_ids.py
```

Re-running any step is always safe: `build_manifest.py` regenerates the same
manifest from the current file tree, `upload_to_roblox.py` skips files whose
hash hasn't changed and already have an id, and `write_asset_ids.py` only
touches numbers (and the clearly-marked auto-added block) inside the `Ids`
table.

**IMAGE IDS, NOT DECAL IDS.** Uploading a PNG through the Open Cloud Assets
API creates *two* Roblox assets — an underlying Image (the pixel content) and
a Decal that wraps it — and the API's response only gives you the **Decal's**
id. A Decal id poked into `Decal.Texture` / `ImageLabel.Image` from a script
does **not** render at runtime (only Studio's property editor resolves a
pasted decal id for you interactively; game code doesn't get that same
resolution). See
[this open Roblox DevForum thread](https://devforum.roblox.com/t/provide-a-stable-open-cloud-api-to-get-an-image-id-from-a-decal-id/3594046)
— there's still no first-class Open Cloud endpoint that hands back the image
id directly from an upload.

`upload_to_roblox.py` handles this for you:
- By default (`--image-asset-type auto`) it tries uploading with assetType
  `"Image"` first — the Assets API's format table
  (create.roblox.com/docs/cloud/guides/usage-assets) lists `Image` as an
  accepted type alongside `Decal` for the exact same file formats — and falls
  back to `"Decal"` if the API rejects that. (Whether `"Image"` actually
  returns a directly-usable id, skipping the whole problem, is *unverified* —
  no example of anyone doing this was found anywhere online while building
  this; spot-check the very first id you get back in Studio either way.)
- When a Decal is uploaded, it resolves the decal id to its image id via the
  Open Cloud **Asset Delivery API**
  (`GET https://apis.roblox.com/asset-delivery-api/v1/assetId/{decalId}`,
  scope `legacy-asset:manage`), retrying a few times since a freshly uploaded
  asset can take a moment to become resolvable (moderation). Both ids are
  cached in `tools/asset_ids.json` (`decalId`, `imageId`, `status`).
- `write_asset_ids.py` **only ever writes a resolved `imageId`** into
  `SkinAssets.luau`. A key that only got as far as `decalId` (still
  moderating, or resolution failed) is left untouched — 0, or whatever was
  already there — and the script prints a warning with the count, so a bad
  decal-as-image id can never land in the game silently.
- If resolution doesn't work for you (no `legacy-asset:manage` scope, the
  endpoint is unavailable, etc.), re-run later with `--resolve-only` (retries
  cached decal ids without re-uploading anything), or fall back to
  **[`tools/resolve_decals.luau`](resolve_decals.luau)** — a small Studio
  Command Bar snippet that resolves decal ids via `InsertService:LoadAsset`
  (this always works, since it's exactly what Studio's own property editor
  does):
  ```bat
  python tools/upload_to_roblox.py --emit-studio-resolver
  :: paste the printed { ... } array into resolve_decals.luau's DECAL_IDS line,
  :: run that file in Studio's Command Bar, save its printed JSON as
  :: tools/decal_image_ids.json, then:
  python tools/upload_to_roblox.py --resolve-only
  python tools/write_asset_ids.py
  ```

Audio is unaffected by any of this — an uploaded audio asset's id is directly
usable in `Sound.SoundId` (no Decal/Image split).

**Audio conversion:** the Open Cloud Assets API caps uploads at 20MB and 7
minutes of audio. Only `Music/BrusselSprouts.wav` (~34MB) currently exceeds
that; `upload_to_roblox.py` transcodes it to mp3 (192kbps) via `ffmpeg` if
`ffmpeg` is on `PATH` before uploading (cached under
`tools/.asset_cache/converted_audio/`, gitignored). Without `ffmpeg`, that
entry is skipped with a message telling you to convert it by hand.

**Excluded by design** (see `tools/asset_manifest.json`'s `skipped` list for
the full reasoning per file): store-marketing art (`FeatureImage`, `Icon`,
`VFLogo`, `Press*`), `_DEPTH`/`_NORMALS`/`_OCCLUSION` maps, third-party
copyrighted audio (`MegaManDeath*.wav`), `-old` duplicate audio, and a handful
of unreferenced VO/music files (listed as `optional`/skipped with a reason,
not silently dropped).

Uploaded assets go through Roblox moderation — a fresh id can render/play
blank until approved. Never commit `tools/asset_manifest.json` or
`tools/asset_ids.json` (both gitignored: the former embeds a machine-specific
absolute path to the external Audio folder, the latter is a local cache); the
API key is read from `$ROBLOX_API_KEY` (or `--api-key`) and is never written
to either file or logged.

## `upload_to_roblox.py`

Upload images/audio to Roblox via the **Open Cloud Assets API**, resolve each
uploaded image's Decal id to its actual Image id (see "IMAGE IDS, NOT DECAL
IDS" above), and cache the results — the keys the Roblox port's
`SkinAssets.luau` / `SoundAssets.luau` expect (file stem, e.g. `HotFrogBody`,
or the sound stem from the manifest, e.g. `grab`). This is the step that turns
`/Sprites` PNGs and `Assets/Audio` clips into `rbxassetid`s the game can
render/play; Studio's Asset Manager "Bulk Import" is the manual equivalent.
See the 4-command pipeline above for the manifest-driven workflow
(`--manifest`, `--dry-run`, the `tools/asset_ids.json` cache), and "IMAGE IDS,
NOT DECAL IDS" above for `--image-asset-type`, `--resolve-only`,
`--emit-studio-resolver` and `--decal-image-ids`.

The original directory-scan mode (images only, no manifest) still works for ad
hoc uploads, and now goes through the same Decal->Image resolution:

```bat
set ROBLOX_API_KEY=...
python tools/upload_to_roblox.py "Sprites/Frogs" --recursive ^
    --creator-id 1234567 --creator-type user -o sprite_ids.json
:: also emit a paste-ready Lua id table (image ids only; unresolved entries
:: are left at 0 with a comment explaining why):
python tools/upload_to_roblox.py Sprites/Other --creator-id 1234567 --lua-out ids.lua
```

`-o`/`--output` in this mode writes `{stem: {decalId, imageId}}` (not a bare
id) so you can see which ones are still pending resolution. Then paste the
`imageId`s into the port's `SkinAssets.luau` (images) / `SoundAssets.luau`
(audio), or use `write_asset_ids.py` (manifest mode) to do it for you. Uploaded
assets are moderated, so a fresh id can render blank until approved, and
resolution itself can also lag until moderation clears; failed uploads record
an `"error"` field so you can re-run just those. Never commit your key.

## `build_manifest.py`

Scans `/Sprites` and the Unity `Assets/Audio` folder and writes
`tools/asset_manifest.json`: every asset to upload, with its key, source path,
kind (`image`/`audio`), and target table (`SkinAssets` universal/steps/
entities/scenery/ui section, a per-skin `part`, or `SoundAssets`). See the
4-command pipeline above.

## `write_asset_ids.py`

Reads `tools/asset_manifest.json` (what keys should exist) and
`tools/asset_ids.json` (what ids are known) and rewrites the `Ids` table in
`src/shared/SkinAssets.luau` / `SoundAssets.luau` in place — idempotent,
preserves existing comments/formatting, leaves `0` for anything not yet
uploaded **or not yet resolved to an image id** (a cached Decal id alone is
never written — see "IMAGE IDS, NOT DECAL IDS" above; the script prints a
warning naming every key left pending). See the 4-command pipeline above.

## `resolve_decals.luau`

Studio Command Bar fallback for turning Decal ids into Image ids
(`InsertService:LoadAsset`) when `upload_to_roblox.py`'s Asset Delivery API
resolution isn't available to you. Generate its input with
`upload_to_roblox.py --emit-studio-resolver`, run it in Studio, save the
printed JSON as `tools/decal_image_ids.json`, then
`upload_to_roblox.py --resolve-only`. See "IMAGE IDS, NOT DECAL IDS" above.

