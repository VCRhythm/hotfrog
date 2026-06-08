"""Remove the background from .png images and crop to visible content.

Setup:
  pip install Pillow

Usage:
  python tools/remove_bg.py image.png
  python tools/remove_bg.py image.png --output image_trimmed.png
  python tools/remove_bg.py image.png --tolerance 20
  python tools/remove_bg.py image.png --background 255,255,255
  python tools/remove_bg.py Sprites/Frogs/ --recursive --output processed
  python tools/remove_bg.py icon.png --pad-square   # legacy square power-of-4 canvas

Notes:
  - Existing transparent pixels are preserved.
  - Background removal targets edge-connected pixels similar to the border color,
    which avoids punching holes through enclosed details.
  - By default the output is cropped tight to the visible content — ideal for
    Unity sprites, which do not need a square / power-of-two canvas.
  - Pass --pad-square to re-center the content on a square power-of-4 canvas
    (the original behavior, useful for fixed-size icon slots).
"""

from __future__ import annotations

import argparse
import math
import sys
from collections import deque
from pathlib import Path


RGBA = tuple[int, int, int, int]
RGB = tuple[int, int, int]


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="remove_bg.py",
        description="Remove a PNG background and crop to visible content.",
        formatter_class=argparse.RawTextHelpFormatter,
    )
    parser.add_argument(
        "inputs",
        nargs="+",
        help="One or more .png files or directories containing .png files.",
    )
    parser.add_argument(
        "--output",
        "-o",
        help=(
            "Optional output path. For a single file input, this may be a .png file path "
            "or a directory. For multiple inputs or any directory input, this must be a directory."
        ),
    )
    parser.add_argument(
        "--recursive",
        action="store_true",
        help="Recurse into subdirectories when an input is a directory.",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Overwrite existing outputs.",
    )
    parser.add_argument(
        "--quiet",
        action="store_true",
        help="Suppress per-file success logs.",
    )
    parser.add_argument(
        "--tolerance",
        type=int,
        default=16,
        help="Per-channel tolerance used for edge background detection. Default: 16.",
    )
    parser.add_argument(
        "--alpha-threshold",
        type=int,
        default=8,
        help="Alpha values at or below this are treated as transparent. Default: 8.",
    )
    parser.add_argument(
        "--background",
        help=(
            "Optional explicit RGB background color in the form R,G,B. "
            "If omitted, the script estimates the background from border pixels."
        ),
    )
    parser.add_argument(
        "--pad-square",
        action="store_true",
        help="Re-center cropped content on a square power-of-4 canvas (legacy icon mode).",
    )
    parser.add_argument(
        "--min-size",
        type=int,
        default=4,
        help="Minimum square side length when --pad-square. Must be a power of 4. Default: 4.",
    )
    return parser


def load_image_module():
    try:
        from PIL import Image  # type: ignore[import-not-found]
    except ImportError:
        print("Error: Pillow is required for PNG processing.", file=sys.stderr)
        print("Install it with: pip install Pillow", file=sys.stderr)
        raise SystemExit(1)

    return Image


def parse_background(raw_value: str | None) -> RGB | None:
    if raw_value is None:
        return None

    parts = [segment.strip() for segment in raw_value.split(",")]
    if len(parts) != 3:
        raise ValueError("--background must be in the form R,G,B")

    try:
        channels = tuple(int(part) for part in parts)
    except ValueError as exc:
        raise ValueError("--background must contain integer channel values") from exc

    if any(channel < 0 or channel > 255 for channel in channels):
        raise ValueError("--background channel values must be between 0 and 255")

    return channels  # type: ignore[return-value]


def is_power_of_4(value: int) -> bool:
    if value < 1:
        return False
    while value % 4 == 0:
        value //= 4
    return value == 1


def find_png_files(path: Path, recursive: bool) -> list[Path]:
    if path.is_file():
        if path.suffix.lower() != ".png":
            raise ValueError(f"Input is not a .png file: {path}")
        return [path]

    if path.is_dir():
        pattern = "**/*.png" if recursive else "*.png"
        return sorted(candidate for candidate in path.glob(pattern) if candidate.is_file())

    raise ValueError(f"Input path does not exist: {path}")


def default_output_for_file(source_file: Path) -> Path:
    return source_file.with_name(f"{source_file.stem}_trimmed.png")


def resolve_output_path(
    source_file: Path,
    input_root: Path | None,
    output_arg: Path | None,
    multiple_outputs: bool,
) -> Path:
    if output_arg is None:
        return default_output_for_file(source_file)

    if not multiple_outputs:
        if output_arg.suffix.lower() == ".png":
            return output_arg
        return output_arg / f"{source_file.stem}_trimmed.png"

    if input_root is not None:
        relative_parent = source_file.relative_to(input_root).parent
        return output_arg / relative_parent / f"{source_file.stem}_trimmed.png"

    return output_arg / f"{source_file.stem}_trimmed.png"


def estimate_background_color(border_pixels: list[RGBA], alpha_threshold: int) -> RGB:
    opaque_pixels = [pixel for pixel in border_pixels if pixel[3] > alpha_threshold]
    if not opaque_pixels:
        return (255, 255, 255)

    red = round(sum(pixel[0] for pixel in opaque_pixels) / len(opaque_pixels))
    green = round(sum(pixel[1] for pixel in opaque_pixels) / len(opaque_pixels))
    blue = round(sum(pixel[2] for pixel in opaque_pixels) / len(opaque_pixels))
    return (red, green, blue)


def collect_border_pixels(image) -> list[RGBA]:
    width, height = image.size
    pixels = image.load()
    border_pixels: list[RGBA] = []

    for x in range(width):
        border_pixels.append(pixels[x, 0])
        if height > 1:
            border_pixels.append(pixels[x, height - 1])

    for y in range(1, max(height - 1, 1)):
        border_pixels.append(pixels[0, y])
        if width > 1:
            border_pixels.append(pixels[width - 1, y])

    return border_pixels


def within_tolerance(pixel: RGBA, background: RGB, tolerance: int, alpha_threshold: int) -> bool:
    if pixel[3] <= alpha_threshold:
        return True

    return (
        abs(pixel[0] - background[0]) <= tolerance
        and abs(pixel[1] - background[1]) <= tolerance
        and abs(pixel[2] - background[2]) <= tolerance
    )


def remove_edge_background(image, background: RGB, tolerance: int, alpha_threshold: int):
    width, height = image.size
    pixels = image.load()
    visited: set[tuple[int, int]] = set()
    queue: deque[tuple[int, int]] = deque()

    for x in range(width):
        queue.append((x, 0))
        if height > 1:
            queue.append((x, height - 1))

    for y in range(height):
        queue.append((0, y))
        if width > 1:
            queue.append((width - 1, y))

    while queue:
        x, y = queue.popleft()
        if (x, y) in visited:
            continue
        visited.add((x, y))

        pixel = pixels[x, y]
        if not within_tolerance(pixel, background, tolerance, alpha_threshold):
            continue

        pixels[x, y] = (pixel[0], pixel[1], pixel[2], 0)

        for offset_x, offset_y in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            next_x = x + offset_x
            next_y = y + offset_y
            if 0 <= next_x < width and 0 <= next_y < height:
                queue.append((next_x, next_y))

    return image


def crop_to_visible_content(image, alpha_threshold: int):
    width, height = image.size
    pixels = image.load()
    min_x = width
    min_y = height
    max_x = -1
    max_y = -1

    for y in range(height):
        for x in range(width):
            if pixels[x, y][3] > alpha_threshold:
                min_x = min(min_x, x)
                min_y = min(min_y, y)
                max_x = max(max_x, x)
                max_y = max(max_y, y)

    if max_x == -1:
        return None

    return image.crop((min_x, min_y, max_x + 1, max_y + 1))


def next_power_of_4(size: int, min_size: int) -> int:
    size = max(size, min_size)
    if size <= 1:
        return 1

    exponent = math.ceil(math.log(size, 4))
    return 4 ** exponent


def build_square_canvas(image_module, cropped_image, min_size: int):
    side_length = next_power_of_4(max(cropped_image.size), min_size)
    canvas = image_module.new("RGBA", (side_length, side_length), (0, 0, 0, 0))
    offset_x = (side_length - cropped_image.size[0]) // 2
    offset_y = (side_length - cropped_image.size[1]) // 2
    canvas.paste(cropped_image, (offset_x, offset_y), cropped_image)
    return canvas


def process_one(
    source_file: Path,
    output_file: Path,
    overwrite: bool,
    quiet: bool,
    tolerance: int,
    alpha_threshold: int,
    explicit_background: RGB | None,
    pad_square: bool,
    min_size: int,
) -> bool:
    if output_file.exists() and not overwrite:
        print(f"Skipping existing file: {output_file}", file=sys.stderr)
        return False

    image_module = load_image_module()
    output_file.parent.mkdir(parents=True, exist_ok=True)

    with image_module.open(source_file) as source_image:
        image = source_image.convert("RGBA")
        background = explicit_background or estimate_background_color(
            collect_border_pixels(image),
            alpha_threshold,
        )
        image = remove_edge_background(image, background, tolerance, alpha_threshold)
        cropped_image = crop_to_visible_content(image, alpha_threshold)
        if cropped_image is None:
            fallback = max(min_size, 1)
            cropped_image = image_module.new("RGBA", (fallback, fallback), (0, 0, 0, 0))
        if pad_square:
            output_image = build_square_canvas(image_module, cropped_image, min_size)
        else:
            output_image = cropped_image
        output_image.save(output_file, format="PNG")

    if not quiet:
        print(f"Processed: {source_file} -> {output_file}")
    return True


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    if args.tolerance < 0 or args.tolerance > 255:
        parser.error("--tolerance must be between 0 and 255.")

    if args.alpha_threshold < 0 or args.alpha_threshold > 255:
        parser.error("--alpha-threshold must be between 0 and 255.")

    if args.pad_square and (args.min_size < 1 or not is_power_of_4(args.min_size)):
        parser.error("--min-size must be a positive power of 4.")

    try:
        explicit_background = parse_background(args.background)
    except ValueError as error:
        parser.error(str(error))

    output_arg = Path(args.output).expanduser().resolve() if args.output else None
    input_paths = [Path(raw_input).expanduser().resolve() for raw_input in args.inputs]

    has_directory_input = any(path.is_dir() for path in input_paths)
    multiple_outputs = has_directory_input or len(input_paths) > 1

    if output_arg is not None and multiple_outputs and output_arg.suffix.lower() == ".png":
        parser.error("--output must be a directory when processing multiple files or directories.")

    processing_plan: list[tuple[Path, Path | None]] = []
    for input_path in input_paths:
        try:
            matching_files = find_png_files(input_path, args.recursive)
        except ValueError as error:
            print(f"Error: {error}", file=sys.stderr)
            return 2

        if input_path.is_dir() and not matching_files:
            print(f"No .png files found in: {input_path}", file=sys.stderr)
            continue

        input_root = input_path if input_path.is_dir() else None
        for source_file in matching_files:
            processing_plan.append((source_file, input_root))

    if not processing_plan:
        print("No .png files found to process.", file=sys.stderr)
        return 2

    processed_count = 0
    skipped_count = 0
    failed_count = 0

    for source_file, input_root in processing_plan:
        output_file = resolve_output_path(source_file, input_root, output_arg, multiple_outputs)
        try:
            did_process = process_one(
                source_file=source_file,
                output_file=output_file,
                overwrite=args.overwrite,
                quiet=args.quiet,
                tolerance=args.tolerance,
                alpha_threshold=args.alpha_threshold,
                explicit_background=explicit_background,
                pad_square=args.pad_square,
                min_size=args.min_size,
            )
        except Exception as error:
            failed_count += 1
            print(f"Failed: {source_file} ({error})", file=sys.stderr)
            continue

        if did_process:
            processed_count += 1
        else:
            skipped_count += 1

    print(
        f"Done. Processed: {processed_count}, skipped: {skipped_count}, failed: {failed_count}"
    )
    return 0 if failed_count == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
