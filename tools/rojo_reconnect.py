#!/usr/bin/env python3
"""Reconnect the Rojo Studio plugin in the Hot Frog Studio, using scare's tool.

Thin wrapper around H:/Roblox Projects/scare/tools/rojo_reconnect.py (override the path with
SCARE_ROJO_RECONNECT), pointed at hotfrog: project hotfrog-roblox (served on 34873), Studio
window "Hot Frog", hotfrog's src mounts for `fingerprint`. Status exit codes and the
"Rojo: Connect" chord (Ctrl+Alt+Shift+F8, bound once by the user in Studio) are scare's; see
scare's .claude/skills/rojo-reconnect/SKILL.md.

    python tools/rojo_reconnect.py status    # 0 connected, 1 serve up/no socket, 2 no serve, 3 no window
    python tools/rojo_reconnect.py connect   # only on status 1; Studio must be in Edit
    python tools/rojo_reconnect.py click X Y # e.g. Accept on the plugin's confirm page
    python tools/rojo_reconnect.py fingerprint src/server/GameServer.server.luau

`canary` and `reconnect` are not supported (scare's canary file lives in a scare-only mount);
prove sync with `fingerprint`.
"""

from __future__ import annotations

import importlib.util
import os
import sys
import tempfile
from pathlib import Path

SCARE_TOOL = Path(os.environ.get("SCARE_ROJO_RECONNECT", "H:/Roblox Projects/scare/tools/rojo_reconnect.py"))
TITLE = "Hot Frog"


def load():
    spec = importlib.util.spec_from_file_location("scare_rojo_reconnect", SCARE_TOOL)
    if spec is None or spec.loader is None or not SCARE_TOOL.exists():
        sys.exit(f"scare's rojo_reconnect.py not found at {SCARE_TOOL}")
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    m.ROOT = Path(__file__).resolve().parent.parent
    m.DEFAULT_TITLE = TITLE
    m.STATE = Path(tempfile.gettempdir()) / "hotfrog_rojo_reconnect_state.json"
    m.MOUNTS = [
        ("src/shared", "game.ReplicatedStorage.Shared"),
        ("src/server", "game.ServerScriptService.Server"),
        ("src/client", "game.StarterPlayer.StarterPlayerScripts.Client"),
    ]
    return m


def main() -> int:
    argv = sys.argv[1:]
    if argv and argv[0] in ("canary", "reconnect"):
        print(f"{argv[0]} is scare-only (its canary mount); use `fingerprint <file>` to prove sync")
        return 1
    for i, a in enumerate(argv):  # --title is locked: never aim keys or clicks at another Studio
        opt, eq, val = a.partition("=")
        if not (len(opt) > 2 and "--title".startswith(opt)):
            continue
        title = val if eq else argv[i + 1] if i + 1 < len(argv) else None
        if title != TITLE:
            print(f"refused: --title is locked to {TITLE!r} (got {title!r})")
            return 2
    return load().main(argv)


if __name__ == "__main__":
    sys.exit(main())
