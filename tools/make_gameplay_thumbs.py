"""Build the Roblox experience-page thumbnails from real Studio gameplay captures.

Run from the repo root:  python tools/make_gameplay_thumbs.py
Reads marketing/captures/*.jpg and writes marketing/gameplay-1..5.png (1920x1080).

The captures are unedited Studio Play screenshots (MCP screen_capture, 1048x955,
Hot Frog skin, Halloween off, bot-driven climb in each level; see
marketing/store-page.md). Studio's viewport is portrait-ish, so each capture is
scaled (about 1.13x) to the full 1080 px height and set on the right of a 16:9
canvas whose background is the same capture, blurred and darkened; the left
side carries the title and a caption. Nothing in the gameplay frame is redrawn.
make_marketing.py (icon + the composed sprite-art thumb-1..5) is separate.
"""

import os

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter

from make_marketing import H, OUT, W, text

CAPTURES = os.path.join(OUT, "captures")

# (capture file, big caption, small caption), in upload order
SHOTS = [
    ("kitchen-chef.jpg", "DODGE THE CHEF", "Grab shelves through the Kitchen"),
    ("pot.jpg", "CLIMB OUT", "Grab steps, pull the world past you"),
    ("country.jpg", "KEEP CLIMBING", "Across the Country"),
    ("space.jpg", "ALL THE WAY UP", "Into Space"),
    ("kitchen-knife.jpg", "BUILD A COMBO", "Time your grabs, speed up"),
]


def compose(capture, big, small):
    shot = Image.open(os.path.join(CAPTURES, capture)).convert("RGBA")

    # background: the capture itself, scaled to cover, blurred and darkened
    s = max(W / shot.width, H / shot.height)
    bg = shot.resize((round(shot.width * s), round(shot.height * s)), Image.LANCZOS)
    x, y = (bg.width - W) // 2, (bg.height - H) // 2
    bg = bg.crop((x, y, x + W, y + H)).filter(ImageFilter.GaussianBlur(28))
    bg = ImageEnhance.Brightness(bg).enhance(0.45)

    # foreground: the real frame at full height, right-aligned, with a drop shadow
    fg = shot.resize((round(shot.width * H / shot.height), H), Image.LANCZOS)
    fx = W - fg.width
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rectangle((fx - 30, 0, W, H), fill=(0, 0, 0, 170))
    bg.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(24)))
    bg.alpha_composite(fg, (fx, 0))

    cx = fx // 2
    text(bg, "HOT FROG", cx, 330, 150, "mm", fill=(80, 220, 90), stroke=(10, 40, 10), sw=10)
    text(bg, big, cx, 560, 92, "mm", fill=(255, 235, 90), sw=8)
    text(bg, small, cx, 680, 44, "mm", sw=5)
    return bg.convert("RGB")


def main():
    for i, (capture, big, small) in enumerate(SHOTS, 1):
        compose(capture, big, small).save(os.path.join(OUT, f"gameplay-{i}.png"))


if __name__ == "__main__":
    main()
