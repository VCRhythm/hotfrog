"""Upload images to catbox.moe and print a {name: url} JSON map.

Catbox accepts anonymous uploads via multipart POST and returns the direct file
URL in the response body. Handy for sharing sprite art as links (design docs,
chats, issue threads) without committing binaries anywhere public.

Setup:
  pip install requests

Usage:
  python tools/upload_to_catbox.py Sprites/Frogs/Blue Frog/BlueFrogBody.png
  python tools/upload_to_catbox.py Sprites/Menu --pattern "*.png"
  python tools/upload_to_catbox.py Sprites/Frogs --recursive -o urls.json
  python tools/upload_to_catbox.py a.png b.png c.png

Notes:
  - Inputs may be individual image files and/or directories.
  - --pattern only filters directory inputs (default "*.png"); explicit file
    arguments are always uploaded.
  - Keys in the JSON map are file stems; on a name collision the later file wins.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

import requests

CATBOX_URL = "https://catbox.moe/user/api.php"

MIME_BY_SUFFIX = {
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".webp": "image/webp",
    ".gif": "image/gif",
    ".bmp": "image/bmp",
    ".tga": "image/x-tga",
}


def collect_files(inputs: list[Path], pattern: str, recursive: bool) -> list[Path]:
    files: list[Path] = []
    seen: set[Path] = set()
    for raw in inputs:
        if raw.is_file():
            candidates = [raw]
        elif raw.is_dir():
            glob_pattern = f"**/{pattern}" if recursive else pattern
            candidates = sorted(p for p in raw.glob(glob_pattern) if p.is_file())
        else:
            print(f"[skip] not found: {raw}", file=sys.stderr)
            continue
        for path in candidates:
            resolved = path.resolve()
            if resolved not in seen:
                seen.add(resolved)
                files.append(path)
    return files


def upload(path: Path) -> str:
    mime = MIME_BY_SUFFIX.get(path.suffix.lower(), "application/octet-stream")
    with path.open("rb") as fh:
        data = {"reqtype": "fileupload"}
        files = {"fileToUpload": (path.name, fh, mime)}
        resp = requests.post(CATBOX_URL, data=data, files=files, timeout=120)
    resp.raise_for_status()
    url = resp.text.strip()
    if not url.startswith("http"):
        raise RuntimeError(f"Unexpected catbox response for {path}: {url!r}")
    return url


def main() -> int:
    ap = argparse.ArgumentParser(
        prog="upload_to_catbox.py",
        description="Upload images to catbox.moe and print a {name: url} JSON map.",
    )
    ap.add_argument("inputs", nargs="+", type=Path, help="Image files and/or directories.")
    ap.add_argument("--pattern", default="*.png", help="Glob for directory inputs. Default: *.png")
    ap.add_argument("--recursive", action="store_true", help="Recurse into directory inputs.")
    ap.add_argument("--output", "-o", type=Path, default=None, help="Write JSON map here instead of stdout.")
    args = ap.parse_args()

    files = collect_files(args.inputs, args.pattern, args.recursive)
    if not files:
        print("No matching image files to upload.", file=sys.stderr)
        return 1

    results: dict[str, str] = {}
    failed = 0
    for i, path in enumerate(files, 1):
        try:
            url = upload(path)
            results[path.stem] = url
            print(f"[{i}/{len(files)}] {path.name} -> {url}", file=sys.stderr)
        except Exception as e:
            failed += 1
            print(f"[{i}/{len(files)}] {path.name} FAILED: {e}", file=sys.stderr)
            results[path.stem] = ""
        time.sleep(0.5)

    payload = json.dumps(results, indent=2)
    if args.output:
        args.output.write_text(payload)
        print(f"Wrote {args.output}", file=sys.stderr)
    else:
        print(payload)
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
