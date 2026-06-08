#!/usr/bin/env python3
"""pixel_pass.py — bake a sprite into a consistent low-res pixel-art look.

The pass:
  * premultiplied-alpha downscale to a low grid (default 48px) so edges don't
    pick up dark halos,
  * NO dithering on the palette cut (dithering causes a "smear"),
  * hard alpha on the grid so the upscaled pixels have crisp edges,
  * nearest-neighbour upscale by an integer factor so the pixels stay square,
  * output as PNG with transparency preserved (Unity's sprite importer wants
    PNG; pass --webp if you specifically need a lossless WebP instead).

Dark sprites can opt into a shadow-biased brightness lift (--lift) plus a subtle
edge rim (--rim) so they separate from a dark background.

Examples:
  # A frog sprite — already light, no lift:
  python tools/pixel_pass.py --out-dir Sprites/Frogs/Processed \
      Sprites/Frogs/_src/blue_frog.png

  # Dark sprite — lift + rim:
  python tools/pixel_pass.py --out-dir Sprites/Other/Processed --lift --rim 32 \
      Sprites/Other/_src/shadow_rock.png
"""
import argparse
import os
import numpy as np
from PIL import Image, ImageFilter


def shadow_lift(rgba: np.ndarray, gamma: float) -> np.ndarray:
    """Gamma < 1 brightens shadows more than highlights (RGB only)."""
    out = rgba.astype(np.float64)
    rgb = np.clip(out[..., :3] / 255.0, 0, 1) ** gamma
    out[..., :3] = rgb * 255.0
    return out


def premult_downscale(rgba: np.ndarray, grid: int):
    """Premultiplied-alpha area downscale -> (rgb float HxWx3, alpha float HxW)."""
    a = rgba[..., 3:4] / 255.0
    pm = np.concatenate([rgba[..., :3] * a, rgba[..., 3:4]], axis=2)
    pm_img = Image.fromarray(np.clip(pm, 0, 255).astype(np.uint8), "RGBA")
    small = np.asarray(pm_img.resize((grid, grid), Image.BILINEAR)).astype(np.float64)
    sa = small[..., 3:4] / 255.0
    rgb = np.divide(small[..., :3], np.where(sa == 0, 1.0, sa))
    return np.clip(rgb, 0, 255), small[..., 3]


def add_rim(rgb: np.ndarray, alpha: np.ndarray, strength: float) -> np.ndarray:
    """Lighten the 1px inner silhouette ring so dark shapes read on a dark bg."""
    a_img = Image.fromarray(alpha.astype(np.uint8), "L")
    eroded = np.asarray(a_img.filter(ImageFilter.MinFilter(3))).astype(np.float64)
    ring = np.clip(alpha - eroded, 0, 255) / 255.0
    return np.clip(rgb + ring[..., None] * strength, 0, 255)


def quantize(rgb: np.ndarray, colors: int) -> np.ndarray:
    img = Image.fromarray(rgb.astype(np.uint8), "RGB")
    q = img.quantize(colors=colors, method=Image.MEDIANCUT, dither=Image.Dither.NONE)
    return np.asarray(q.convert("RGB"))


def desaturate(rgba: np.ndarray) -> np.ndarray:
    """Collapse RGB to neutral grey (luma) so the sprite tints cleanly."""
    out = rgba.copy()
    luma = 0.299 * out[..., 0] + 0.587 * out[..., 1] + 0.114 * out[..., 2]
    out[..., 0] = out[..., 1] = out[..., 2] = luma
    return out


def process(path, out_dir, grid, colors, scale, lift, gamma, rim,
            alpha_thresh, soft_alpha, alpha_floor, desat, as_webp):
    rgba = np.asarray(Image.open(path).convert("RGBA")).astype(np.float64)
    if desat:
        rgba = desaturate(rgba)
    if lift:
        rgba = shadow_lift(rgba, gamma)
    rgb, alpha = premult_downscale(rgba, grid)
    if rim > 0:
        rgb = add_rim(rgb, alpha, rim)
    rgb = quantize(rgb, colors)
    if soft_alpha:
        # Keep graded edge alpha (only drop near-zero ghosts) so thin features
        # stay connected. Edges read slightly softer.
        a = np.where(alpha < alpha_floor, 0, alpha).astype(np.uint8)
    else:
        # Hard alpha on the grid -> crisp pixel edges, no soft upscaled halo.
        a = np.where(alpha >= alpha_thresh, 255, 0).astype(np.uint8)
    out = np.dstack([rgb.astype(np.uint8), a])
    img = Image.fromarray(out, "RGBA").resize((grid * scale, grid * scale), Image.NEAREST)
    base = os.path.splitext(os.path.basename(path))[0]
    if as_webp:
        dst = os.path.join(out_dir, base + ".webp")
        img.save(dst, "WEBP", lossless=True, quality=100, method=6)
    else:
        dst = os.path.join(out_dir, base + ".png")
        img.save(dst, "PNG")
    print(f"  {os.path.basename(path):28s} -> {dst}")


def main():
    ap = argparse.ArgumentParser(description="Bake sprites into a consistent low-res pixel look.")
    ap.add_argument("inputs", nargs="+")
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--grid", type=int, default=48)
    ap.add_argument("--colors", type=int, default=32)
    ap.add_argument("--scale", type=int, default=6, help="integer nearest upscale factor")
    ap.add_argument("--lift", action="store_true", help="shadow-biased brightness lift")
    ap.add_argument("--gamma", type=float, default=0.72)
    ap.add_argument("--rim", type=float, default=0.0, help="edge rim strength (0 = off)")
    ap.add_argument("--alpha-thresh", type=int, default=90)
    ap.add_argument("--soft-alpha", action="store_true",
                    help="keep graded edge alpha (thin features survive, softer edges)")
    ap.add_argument("--alpha-floor", type=int, default=16,
                    help="drop alpha below this when --soft-alpha (ghost cleanup)")
    ap.add_argument("--desaturate", action="store_true",
                    help="collapse to neutral grey (for tintable sprites)")
    ap.add_argument("--webp", action="store_true",
                    help="output lossless WebP instead of PNG")
    args = ap.parse_args()
    os.makedirs(args.out_dir, exist_ok=True)
    print(f"pixel_pass: grid={args.grid} colors={args.colors} scale={args.scale} "
          f"lift={args.lift} gamma={args.gamma} rim={args.rim} "
          f"fmt={'webp' if args.webp else 'png'}")
    for p in args.inputs:
        process(p, args.out_dir, args.grid, args.colors, args.scale,
                args.lift, args.gamma, args.rim, args.alpha_thresh,
                args.soft_alpha, args.alpha_floor, args.desaturate, args.webp)


if __name__ == "__main__":
    main()
