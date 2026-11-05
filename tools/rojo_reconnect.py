#!/usr/bin/env python3
"""Reconnect the Rojo Studio plugin in the Hot Frog Studio, using scare's tool.

Thin wrapper around H:/Roblox Projects/scare/tools/rojo_reconnect.py (override the path with
SCARE_ROJO_RECONNECT), pointed at hotfrog: project hotfrog-roblox (served on 34873), Studio
window "Hot Frog", hotfrog's src mounts for `fingerprint`. Status exit codes and the
"Rojo: Connect" chord (Ctrl+Alt+Shift+F8, bound once by the user in Studio) are scare's; see
scare's .claude/skills/rojo-reconnect/SKILL.md.

    python tools/rojo_reconnect.py status    # 0 connected, 1 serve up/no socket, 2 no serve, 3 no window
    python tools/rojo_reconnect.py request send [--accept]   # status 1: no keys, no focus (below)
    python tools/rojo_reconnect.py request result --value "<what the result snippet returned>"
    python tools/rojo_reconnect.py connect   # chord fallback, only on status 1; Studio must be in Edit
    python tools/rojo_reconnect.py click X Y # e.g. Accept on the plugin's confirm page
    python tools/rojo_reconnect.py fingerprint src/server/GameServer.server.luau

`request` is the unattended path (scare's step 5b): the Rojo plugin install is shared by every
Studio, and scare's tools/patch_rojo_plugin.py patched it with a watcher, so setting
ServerStorage.RojoReconnectRequest in the Hot Frog Edit DataModel (execute_luau, snippet printed
by `request send`) makes the plugin connect itself to localhost:34873; the second snippet's value
goes to `request result` (0 ok, 1 read again, 6 `confirming`: `request send --accept` once, 7
failed). Scare gates `send` on a stale canary verdict; here status 1 (no socket at all, a plainly
dropped session) is the gate instead, `--accept` is allowed after a `confirming` answer.

`canary` and `reconnect` are not supported (scare's canary file lives in a scare-only mount);
prove sync with `fingerprint`.
"""

from __future__ import annotations

import contextlib
import importlib.util
import io
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
    m = load()
    if argv[:2] == ["request", "send"] and "--force" not in argv:
        if "--accept" not in argv or (m.load_state().get("request") or {}).get("result") != "confirming":
            code = m.status(TITLE)
            if code != 1:
                print("refused: `request send` needs status 1 (serve up, no plugin socket)")
                return 5 if code == 0 else code
        argv = argv + ["--force"]  # status 1 stands in for scare's stale-canary gate
    out = io.StringIO()
    try:
        with contextlib.redirect_stdout(out):
            return m.main(argv)
    finally:  # scare's messages name its Studio; this wrapper only ever targets Hot Frog
        print(out.getvalue().replace("Centralia (Staging)", TITLE).replace("Centralia", TITLE), end="")


if __name__ == "__main__":
    sys.exit(main())
