# tools/

Sprite-prep utilities for HotFrog (a Unity 2D project). Ported from the
`scare` project's toolset, trimmed to the engine-agnostic image tools and
adapted for Unity (PNG output, no power-of-two padding by default).

Run all commands from the **project root**.

## Setup

```bat
pip install -r tools/requirements.txt
copy .env.example .env
```

(`Pillow` for the converters, `numpy` for `pixel_pass.py`, `requests` for
`upload_to_catbox.py` / `upload_to_roblox.py` / `luau_exec.py` / `list_assets.py`.)

Fill in `.env` (gitignored; loaded by every Roblox script via
`tools/roblox_web.py`, an exported shell variable wins over the file):

| Variable | Secret? | Used for |
|----------|---------|----------|
| `ROBLOX_USER_ID` | no | the creator that owns uploads (`--creator-id` default) |
| `ROBLOX_UNIVERSE_ID`, `ROBLOX_PLACE_ID` | no | the HotFrog experience: headless decal resolution (`--resolve-only --via luau`) and the audio-grant target |
| `ROBLOX_API_KEY` | **yes** | Open Cloud: image uploads, `--status`, Luau execution |
| `ROBLOSECURITY` | **yes** | website audio upload (fast moderation), cookie decal resolution, `list_assets.py`, `grant_audio_to_experience.py` |

`.env.example` documents where each value comes from and which API-key scopes
are needed. `ROBLOSECURITY` is a full login credential — treat it like a
password; nothing in `tools/` ever writes it to a file or log.

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

:: 3. The real upload. Needs ROBLOX_API_KEY (assets Read+Write), ROBLOX_USER_ID
::    and — strongly recommended — ROBLOSECURITY in .env (see Setup). With the
::    cookie set, audio goes through the website path (moderates in seconds)
::    and decal->image resolution works; without it, audio goes through Open
::    Cloud and is likely to sit in "Reviewing" forever. Results are cached in
::    tools/asset_ids.json (image keys get decalId+imageId+status, audio keys
::    get assetId+via), so a failed/partial run just resumes — re-run the same
::    command and unchanged/already-uploaded files are skipped.
::
::    STRONGLY RECOMMENDED before running the full ~173-image batch: upload
::    ONE image first and confirm it actually renders on a part in Studio —
::    catching a bad id/scope/resolution problem on 1 asset is a lot cheaper
::    than on 173:
::      python tools/upload_to_roblox.py --manifest tools/asset_manifest.json --keys HotFrogBody
::      python tools/write_asset_ids.py
::      :: then in Studio: put that one id on a test Decal/ImageLabel and look at it.
python tools/upload_to_roblox.py --manifest tools/asset_manifest.json

:: 3b. Moderation. Two columns: "opencloud" (Reviewing/Approved/Rejected —
::     the slow human-review queue, authoritative for Rejected) and "auto"
::     (Green/Red from the cookie develop API — the automated pass that
::     actually gates loading; a website audio upload went Green within two
::     minutes while Open Cloud still said Reviewing, and Reviewing does not
::     block your own audio in your own experience). Exit 0 = everything
::     usable now, 1 = something still pending, 2 = something Rejected.
::     --wait-approved polls the pending ones.
python tools/upload_to_roblox.py --status

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
- By default (`--image-asset-type auto`) it uploads with assetType `"Image"`
  first and falls back to `"Decal"` only if the API rejects that. **Verified
  2026-09-19:** `"Image"` returns a genuine Image asset (AssetTypeId 1, the CDN
  serves the PNG, Approved within minutes) — no Decal wrapper, nothing to
  resolve. Everything below about resolution is the fallback path in case
  Roblox ever stops accepting `"Image"`.
- When a Decal is uploaded, it resolves the decal id to its image id, retrying
  a few times since a freshly uploaded asset can take a moment to become
  resolvable (moderation). Three strategies (`--via`):
  - **`cookie`** (default when `ROBLOSECURITY` is set): the asset-delivery CDN
    returns the Decal's XML, whose `Texture` property names the Image. Verified
    working on the `scare` project — this is the path to rely on.
  - **`opencloud`**: the Open Cloud Asset Delivery API with the API key. Kept as
    a fallback only — `scare` live-checked it and it returns 403 to the API key.
  - **`luau`** (`--resolve-only --via luau`): runs `resolve_decals.luau`
    headlessly inside the HotFrog experience through the Open Cloud Luau
    Execution API (`luau_exec.py`, needs `ROBLOX_UNIVERSE_ID`/`ROBLOX_PLACE_ID`
    and the Luau-execution scope on the key). Same `InsertService:LoadAsset`
    resolution Studio does, no Studio round-trip. Use it if the cookie path
    ever stops working.
  Both ids are cached in `tools/asset_ids.json` (`decalId`, `imageId`, `status`).
- `write_asset_ids.py` **only ever writes a resolved `imageId`** into
  `SkinAssets.luau`. A key that only got as far as `decalId` (still
  moderating, or resolution failed) is left untouched — 0, or whatever was
  already there — and the script prints a warning with the count, so a bad
  decal-as-image id can never land in the game silently.
- If resolution lags (still moderating), re-run later with `--resolve-only`
  (retries cached decal ids without re-uploading anything) or
  `--resolve-only --via luau`. The last resort is running
  **[`tools/resolve_decals.luau`](resolve_decals.luau)** by hand in Studio's
  Command Bar (`InsertService:LoadAsset`, exactly what Studio's own property
  editor does):
  ```bat
  python tools/upload_to_roblox.py --emit-studio-resolver
  :: paste the printed { ... } array into resolve_decals.luau's DECAL_IDS line,
  :: run that file in Studio's Command Bar, save its printed JSON as
  :: tools/decal_image_ids.json, then:
  python tools/upload_to_roblox.py --resolve-only
  python tools/write_asset_ids.py
  ```

Audio has no Decal/Image split — an uploaded audio asset's id is directly
usable in `Sound.SoundId`. **But the upload path matters** (`--audio-via`):
with `ROBLOSECURITY` set, audio goes through the cookie-authenticated
**website** endpoint the Creator Hub itself uses (`publish.roblox.com`), which
clears automated moderation in seconds and accepts `.wav` directly. The Open
Cloud path is widely reported (and observed on `scare`) to leave audio in
"Reviewing" indefinitely, so it is only used when no cookie is available, with
a warning. Audio is also permission-gated per experience — see
`grant_audio_to_experience.py` below if sounds stay silent after publishing.

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
blank until approved (`upload_to_roblox.py --status` shows where each one
stands). Never commit `.env`, `tools/asset_manifest.json` or
`tools/asset_ids.json` (all gitignored: the manifest embeds a machine-specific
absolute path to the external Audio folder, the ids file is a local cache);
secrets are read from the environment / `.env` and never written to any file
or log.

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

Turns Decal ids into Image ids with `InsertService:LoadAsset`. Normally run for
you, headlessly, by `upload_to_roblox.py --resolve-only --via luau` (through
`luau_exec.py`). Manual fallback: generate its input with
`upload_to_roblox.py --emit-studio-resolver`, paste and run it in Studio's
Command Bar, save the printed JSON as `tools/decal_image_ids.json`, then
`upload_to_roblox.py --resolve-only`. See "IMAGE IDS, NOT DECAL IDS" above.

## `roblox_web.py`

Shared module (not a command): `.env` loading, the `.ROBLOSECURITY` cookie +
CSRF dance, the website audio upload, cookie-based decal->image resolution and
Open Cloud moderation-state polling. Ported from `scare`'s `upload_asset.py`,
where each of these was verified against the live endpoints. Every other
Roblox script here imports it.

## `luau_exec.py`

Run a Luau script headlessly in the published HotFrog place via the Open Cloud
**Luau Execution API** — the equivalent of pasting into Studio's Command Bar,
with the script's `return` value printed as JSON and its `print`/`warn` output
on stderr. Needs `ROBLOX_UNIVERSE_ID`, `ROBLOX_PLACE_ID` and an API key with
the Luau-execution write scope for that experience. Used by
`upload_to_roblox.py --resolve-only --via luau`; also handy for one-off
inspection of the live DataModel.

```bat
python tools/luau_exec.py --script "return game.PlaceId"
python tools/luau_exec.py --script-file tools/resolve_decals.luau
```

## `grant_audio_to_experience.py`

Roblox audio is permission-gated **per experience**. Sounds you own normally
play in experiences you own, but after publishing to a new experience id some
can stay silent. This adds the experience (`ROBLOX_UNIVERSE_ID` or
`--universe-id`) to the allow-list of every sound id known to
`tools/asset_ids.json` and `src/shared/SoundAssets.luau`. Needs the owner's
`ROBLOSECURITY` cookie (website API, not Open Cloud). Only run it if sounds
are actually silent, and smoke-test one first — the endpoint shape was
reconstructed from the Creator Dashboard on `scare` and is flagged
verify-before-trust in the script.

```bat
python tools/grant_audio_to_experience.py --list             :: no network
python tools/grant_audio_to_experience.py                    :: dry run
python tools/grant_audio_to_experience.py --apply --limit 1  :: smoke test, then check the Dashboard
python tools/grant_audio_to_experience.py --apply            :: all, resume-safe
```

## `list_assets.py`

Dump the account's (or a group's) Asset Manager inventory as a markdown table
(name, id, `rbxassetid://`). Needs `ROBLOSECURITY`. Useful for checking what
actually landed after an upload run, or recovering ids if the local cache is
lost.

```bat
python tools/list_assets.py -t Image -t Audio -o docs/asset_inventory.md
```

