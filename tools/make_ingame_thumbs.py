"""Build full-bleed 16:9 Roblox thumbnails from in-game Studio Play captures.

Run from the repo root:  python tools/make_ingame_thumbs.py
Reads marketing/captures/ingame/*.jpg and writes marketing/ingame-1..N.png (1920x1080).

The captures are Studio Play screenshots (MCP screen_capture) taken with the
Studio window set to 2221x1460, which gives a 1806x1016 (16:9) viewport, HUD and
menus hidden locally, GameClient's native framing (FOV 40, 43.2 studs, centred
on the lane), and local-only lighting tweaks (lighter Atmosphere, shadows off,
+0.3..0.6 exposure); see marketing/store-page.md. Each frame is scaled (about
1.06x) to fill the canvas and gets a small title and caption in the top-left
corner. Nothing in the gameplay frame is redrawn. make_gameplay_thumbs.py (the
older portrait captures set beside a caption panel) is separate.
"""

import os

from PIL import Image, ImageDraw, ImageFilter

from make_marketing import H, OUT, W, text

CAPTURES = os.path.join(OUT, "captures", "ingame")

# (capture file, caption), in upload order
SHOTS = [
    ("kitchen-chef-grab.jpg", "DODGE THE CHEF"),
    ("pot-lava-b.jpg", "CLIMB OUT OF THE POT"),
    ("kitchen-chef-knife.jpg", "WATCH THE KNIFE"),
    ("kitchen-fly-catch.jpg", "CATCH FLIES"),
]


def compose(capture, caption):
    shot = Image.open(os.path.join(CAPTURES, capture)).convert("RGBA")

    # full bleed: scale to cover 1920x1080 and centre-crop (captures are 16:9 already)
    s = max(W / shot.width, H / shot.height)
    img = shot.resize((round(shot.width * s), round(shot.height * s)), Image.LANCZOS)
    x, y = (img.width - W) // 2, (img.height - H) // 2
    img = img.crop((x, y, x + W, y + H))

    # soft dark corner behind the text so it reads on any background
    shade = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shade).rounded_rectangle((-40, -40, 820, 250), 60, fill=(0, 0, 0, 120))
    img.alpha_composite(shade.filter(ImageFilter.GaussianBlur(30)))

    text(img, "HOT FROG", 60, 40, 96, "la", fill=(80, 220, 90), stroke=(10, 40, 10), sw=7)
    text(img, caption, 64, 150, 56, "la", fill=(255, 235, 90), sw=5)
    return img.convert("RGB")


def main():
    for i, (capture, caption) in enumerate(SHOTS, 1):
        compose(capture, caption).save(os.path.join(OUT, f"ingame-{i}.png"))


if __name__ == "__main__":
    main()
