"""Compose the Roblox experience-page marketing images from the project's own sprites.

Run from the repo root:  python tools/make_marketing.py
Writes marketing/icon-512.png and marketing/thumb-1..5.png (1920x1080).
Everything is composed from Sprites/ (the thumbnails are not Studio captures).
Fonts: uses Impact (C:/Windows/Fonts/impact.ttf) if present, else Pillow's built-in
default font (plain, but the script still runs on non-Windows machines).
"""

import os
import random

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "marketing")
W, H = 1920, 1080
FONT = "C:/Windows/Fonts/impact.ttf"


def load_font(size):
    if os.path.exists(FONT):
        return ImageFont.truetype(FONT, size)
    return ImageFont.load_default(size=size)


def sprite(path, height=None, width=None):
    img = Image.open(os.path.join(ROOT, "Sprites", path)).convert("RGBA")
    img.putalpha(img.getchannel("A").point(lambda a: 0 if a < 40 else a))
    img = img.crop(img.getbbox())
    if height:
        img = img.resize((round(img.width * height / img.height), height), Image.LANCZOS)
    elif width:
        img = img.resize((width, round(img.height * width / img.width)), Image.LANCZOS)
    return img


def paste(canvas, img, cx, cy, rot=0, shadow=True):
    if rot:
        img = img.rotate(rot, expand=True, resample=Image.BICUBIC)
    if shadow:
        sh = Image.new("RGBA", img.size, (0, 0, 0, 0))
        sh.putalpha(img.getchannel("A").point(lambda a: a * 0.45))
        sh = sh.filter(ImageFilter.GaussianBlur(12))
        canvas.alpha_composite(sh, (round(cx - img.width / 2 + 10), round(cy - img.height / 2 + 14)))
    canvas.alpha_composite(img, (round(cx - img.width / 2), round(cy - img.height / 2)))


def cover(path, size=(W, H)):
    img = Image.open(os.path.join(ROOT, "Sprites", path)).convert("RGBA")
    s = max(size[0] / img.width, size[1] / img.height)
    img = img.resize((round(img.width * s), round(img.height * s)), Image.LANCZOS)
    x, y = (img.width - size[0]) // 2, (img.height - size[1]) // 2
    return img.crop((x, y, x + size[0], y + size[1]))


def lava_bg():
    bg = Image.open(os.path.join(ROOT, "Sprites/Other/Icon.png")).convert("RGBA").crop((0, 0, 95, 80))
    bg = bg.resize((W, H), Image.LANCZOS).filter(ImageFilter.GaussianBlur(14))
    dark = Image.new("RGBA", (W, H), (20, 0, 0, 0))
    grad = Image.linear_gradient("L").resize((W, H))  # black top -> white bottom
    dark.putalpha(grad.point(lambda v: int(190 * (1 - v / 255))))
    bg.alpha_composite(dark)
    return bg


def vgrad(top, bottom):
    img = Image.new("RGBA", (W, H))
    d = ImageDraw.Draw(img)
    for y in range(H):
        t = y / (H - 1)
        d.line([(0, y), (W, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)) + (255,))
    return img


def lava_strip(canvas, h=120):
    tile = Image.open(os.path.join(ROOT, "Sprites/Other/Icon.png")).convert("RGBA").crop((0, 0, 95, 80))
    strip = tile.resize((W, h), Image.LANCZOS).filter(ImageFilter.GaussianBlur(6))
    canvas.alpha_composite(strip, (0, H - h))


def text(canvas, s, x, y, size, anchor="la", fill=(255, 255, 255), stroke=(20, 20, 20), sw=10):
    d = ImageDraw.Draw(canvas)
    d.text((x, y), s, font=load_font(size), fill=fill, anchor=anchor, stroke_width=sw, stroke_fill=stroke)


def caption(canvas, big, small=None, x=80, y=70):
    text(canvas, big, x, y, 150, fill=(255, 235, 90))
    if small:
        text(canvas, small, x + 6, y + 170, 70, sw=7)


def frog(canvas, cx, cy, height=520, name="Hot Frog"):
    paste(canvas, sprite("Menu/FrogHeadIcon.png", height=height), cx, cy)


def steps(canvas, spots, size=200):
    arrows = ["UpArrow", "UpLeftArrow", "UpRightArrow", "LeftArrow", "RightArrow"]
    for i, (x, y) in enumerate(spots):
        paste(canvas, sprite(f"Rocks/{arrows[i % 5]}.png", height=size), x, y)


def make_icon():
    img = Image.open(os.path.join(ROOT, "Sprites/Other/Icon.png")).convert("RGB")
    img.resize((512, 512), Image.LANCZOS).save(os.path.join(OUT, "icon-512.png"))


def thumb1():
    c = lava_bg()
    text(c, "HOT FROG", 1250, 330, 260, "mm", fill=(255, 235, 90), sw=14)
    text(c, "Grab. Climb. Don't fall!", 1250, 520, 90, "mm", sw=8)
    steps(c, [(1000, 800), (1500, 860), (1750, 720), (1250, 700)], 190)
    frog(c, 430, 560, 640)
    for x, y, r in ((1000, 90, 20), (1700, 110, -15)):
        paste(c, sprite("Rocks/Carrot.png", height=170), x, y, r)
    return c


def thumb2():
    c = vgrad((60, 40, 35), (150, 95, 60))
    sh = sprite("Other/Shelf.png", width=1300)
    paste(c, sh, 960, 760, shadow=False)
    paste(c, sprite("Rocks/Toaster.png", width=520), 1500, 420)
    paste(c, sprite("Other/Chef.png", height=620), 1560, 700)
    steps(c, [(1000, 330), (1150, 150), (760, 560)], 200)
    frog(c, 330, 760, 520)
    lava_strip(c)
    caption(c, "KITCHEN CHEF!", small="He's after your steps")
    return c


def thumb3():
    c = cover("Other/CountryBack.png")
    for x, y, w in ((300, 200, 600), (1450, 330, 700), (900, 700, 500)):
        paste(c, sprite("Other/Cloud.png", width=w), x, y, shadow=False)
    paste(c, sprite("Rocks/Balloon.png", height=520), 1600, 560)
    paste(c, sprite("Rocks/Castle.png", height=700), 1100, 620)
    steps(c, [(800, 560), (1400, 150)], 200)
    frog(c, 330, 760, 520)
    lava_strip(c)
    caption(c, "CLIMB TO THE SKY", small="Pot, Kitchen, Country... and Space")
    return c


def thumb4():
    c = cover("Other/SpaceBack.png")
    rng = random.Random(4)
    d = ImageDraw.Draw(c)
    for _ in range(160):
        r = rng.choice((1, 1, 2, 3))
        x, y = rng.randrange(W), rng.randrange(H)
        d.ellipse((x - r, y - r, x + r, y + r), fill=(255, 255, 255, 230))
    paste(c, sprite("Rocks/Rocket.png", height=760), 1560, 580, 20)
    paste(c, sprite("Rocks/UFO.png", width=420), 1060, 640)
    paste(c, sprite("Rocks/Satellite.png", width=360), 1000, 800, -12)
    steps(c, [(760, 460), (1300, 520)], 200)
    frog(c, 330, 760, 520)
    caption(c, "ALL THE WAY TO SPACE", small="Rockets, UFOs and satellites")
    return c


def thumb5():
    c = lava_bg()
    caption(c, "UNLOCK SKINS", small="Earn Flys, collect frogs", x=80, y=60)
    names = ["Hot Frog", "Hawt Frog", "Hot Lawyer", "Business Frog", "Crossy Frog"]
    for i, n in enumerate(names):
        x = 200 + i * 370
        card = Image.new("RGBA", (340, 420), (255, 250, 235, 235))
        m = Image.new("L", card.size, 0)
        ImageDraw.Draw(m).rounded_rectangle((0, 0, 339, 419), 36, fill=255)
        card.putalpha(m)
        paste(c, card, x + 20, 720, shadow=True)
        paste(c, sprite(f"Menu/{n.replace(' ', '')}Thumbnail.png", width=330), x + 20, 680, shadow=False)
        text(c, n.upper(), x + 20, 880, 52, "mm", sw=0, fill=(30, 90, 30), stroke=(0, 0, 0))
    return c


def main():
    os.makedirs(OUT, exist_ok=True)
    make_icon()
    for i, fn in enumerate((thumb1, thumb2, thumb3, thumb4, thumb5), 1):
        fn().convert("RGB").save(os.path.join(OUT, f"thumb-{i}.png"))


if __name__ == "__main__":
    main()
