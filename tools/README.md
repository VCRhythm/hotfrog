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

## `upload_to_roblox.py`

Upload images to Roblox via the **Open Cloud Assets API** and print a
`{stem: assetId}` JSON map — the keys the Roblox port's `SkinAssets.luau` /
`SoundAssets.luau` expect (file stem, e.g. `HotFrogBody`). This is the step that
turns the `/Sprites` PNGs into `rbxassetid`s the game can render; Studio's Asset
Manager "Bulk Import" is the manual equivalent.

Needs an Open Cloud API key (assets, Read+Write) and your creator id:

```bat
set ROBLOX_API_KEY=...
python tools/upload_to_roblox.py "Sprites/Frogs" --recursive ^
    --creator-id 1234567 --creator-type user -o sprite_ids.json
:: also emit a paste-ready Lua id table:
python tools/upload_to_roblox.py Sprites/Other --creator-id 1234567 --lua-out ids.lua
```

Then paste the ids into the port's `SkinAssets.luau` (images) / `SoundAssets.luau`
(audio). Uploaded assets are moderated, so a fresh id can render blank until
approved; failed files map to `""` so you can re-run just those. Never commit your
key.

