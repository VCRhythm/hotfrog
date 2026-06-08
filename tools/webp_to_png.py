"""Convert .webp images to .png.

Setup:
  pip install Pillow

Usage:
  python tools/webp_to_png.py image.webp
  python tools/webp_to_png.py image.webp --output image.png
  python tools/webp_to_png.py folder_with_webps --recursive
  python tools/webp_to_png.py a.webp b.webp --output converted_pngs

Notes:
  - A file input defaults to "<same folder>/<same name>.png".
  - Directory inputs convert every .webp they contain.
  - When multiple files are converted, --output must be a directory.
  - Unity's sprite importer wants .png, not .webp, so run this on any .webp
    art before dropping it into Assets/Sprites.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="webp_to_png.py",
        description="Convert one or more .webp images to .png.",
        formatter_class=argparse.RawTextHelpFormatter,
    )
    parser.add_argument(
        "inputs",
        nargs="+",
        help="One or more .webp files or directories containing .webp files.",
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
        help="Overwrite existing .png outputs.",
    )
    parser.add_argument(
        "--quiet",
        action="store_true",
        help="Suppress per-file success logs.",
    )
    return parser


def load_image_module():
    try:
        from PIL import Image  # type: ignore[import-not-found]
    except ImportError:
        print("Error: Pillow is required for .webp conversion.", file=sys.stderr)
        print("Install it with: pip install Pillow", file=sys.stderr)
        raise SystemExit(1)

    return Image


def find_webp_files(path: Path, recursive: bool) -> list[Path]:
    if path.is_file():
        if path.suffix.lower() != ".webp":
            raise ValueError(f"Input is not a .webp file: {path}")
        return [path]

    if path.is_dir():
        pattern = "**/*.webp" if recursive else "*.webp"
        return sorted(candidate for candidate in path.glob(pattern) if candidate.is_file())

    raise ValueError(f"Input path does not exist: {path}")


def default_output_for_file(source_file: Path) -> Path:
    return source_file.with_suffix(".png")


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
        return output_arg / f"{source_file.stem}.png"

    if input_root is not None:
        relative_parent = source_file.relative_to(input_root).parent
        return output_arg / relative_parent / f"{source_file.stem}.png"

    return output_arg / f"{source_file.stem}.png"


def convert_one(source_file: Path, output_file: Path, overwrite: bool, quiet: bool) -> bool:
    if output_file.exists() and not overwrite:
        print(f"Skipping existing file: {output_file}", file=sys.stderr)
        return False

    output_file.parent.mkdir(parents=True, exist_ok=True)
    image_module = load_image_module()

    with image_module.open(source_file) as image:
        image.save(output_file, format="PNG")

    if not quiet:
        print(f"Converted: {source_file} -> {output_file}")
    return True


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    output_arg = Path(args.output).expanduser().resolve() if args.output else None
    input_paths = [Path(raw_input).expanduser().resolve() for raw_input in args.inputs]

    has_directory_input = any(path.is_dir() for path in input_paths)
    multiple_outputs = has_directory_input or len(input_paths) > 1

    if output_arg is not None and multiple_outputs and output_arg.suffix.lower() == ".png":
        parser.error("--output must be a directory when converting multiple files or directories.")

    conversion_plan: list[tuple[Path, Path | None]] = []
    for input_path in input_paths:
        try:
            matching_files = find_webp_files(input_path, args.recursive)
        except ValueError as error:
            print(f"Error: {error}", file=sys.stderr)
            return 2

        if input_path.is_dir() and not matching_files:
            print(f"No .webp files found in: {input_path}", file=sys.stderr)
            continue

        input_root = input_path if input_path.is_dir() else None
        for source_file in matching_files:
            conversion_plan.append((source_file, input_root))

    if not conversion_plan:
        print("No .webp files found to convert.", file=sys.stderr)
        return 2

    converted_count = 0
    skipped_count = 0
    failed_count = 0

    for source_file, input_root in conversion_plan:
        output_file = resolve_output_path(source_file, input_root, output_arg, multiple_outputs)
        try:
            did_convert = convert_one(source_file, output_file, args.overwrite, args.quiet)
        except Exception as error:
            failed_count += 1
            print(f"Failed: {source_file} ({error})", file=sys.stderr)
            continue

        if did_convert:
            converted_count += 1
        else:
            skipped_count += 1

    print(
        f"Done. Converted: {converted_count}, skipped: {skipped_count}, failed: {failed_count}"
    )
    return 0 if failed_count == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
