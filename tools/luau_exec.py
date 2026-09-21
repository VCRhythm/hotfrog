#!/usr/bin/env python3
"""luau_exec.py — run a Luau script headlessly via the Roblox Open Cloud Luau
Execution API. Ported from the `scare` project's tools/luau_exec.py.

The Luau Execution API boots a temporary server instance of a published place,
runs your script in that place's DataModel, and returns whatever the script
`return`s plus its print/warn logs. It is the headless equivalent of pasting a
script into the Studio Command Bar. `upload_to_roblox.py --resolve-only --via luau`
uses it to run tools/resolve_decals.luau without a Studio round-trip.

The place is only the execution host; assets the script loads with
InsertService:LoadAsset stay owned by your account. Use the HotFrog experience
itself (it just needs to be published once, even as an empty baseplate).

Flow (https://create.roblox.com/docs/cloud/reference/features/luau-execution):
  POST /cloud/v2/universes/{u}/places/{p}/luau-execution-session-tasks {script,timeout}
  GET  {returned task path}?view=FULL        -> poll state until COMPLETE/FAILED
  GET  {returned task path}/logs?view=FLAT   -> print/warn output

Setup (.env at the repo root, see .env.example):
  ROBLOX_API_KEY      with the `universe.place.luau-execution-session:write`
                      scope granted for the experience below (Creator Dashboard
                      -> Open Cloud -> API Keys -> add the "Luau Execution"
                      permission for the experience).
  ROBLOX_UNIVERSE_ID  the experience's universe id (Creator Dashboard ->
                      experience -> "..." -> Copy Universe ID; also game.GameId).
  ROBLOX_PLACE_ID     the start place id (the number in the game URL; game.PlaceId).

Usage:
  python tools/luau_exec.py --script-file tools/resolve_decals.luau
  python tools/luau_exec.py --script 'return 1 + 1' --universe 123 --place 456
  echo 'return game.PlaceId' | python tools/luau_exec.py --script -

Prints the script's returned value(s) as JSON on stdout; logs go to stderr.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from pathlib import Path
from typing import Any

import requests

import roblox_web  # noqa: F401  (loads .env on import)

API_BASE = "https://apis.roblox.com"
CREATE_PATH = "/cloud/v2/universes/{u}/places/{p}/luau-execution-session-tasks"
POLL_SECS_DEFAULT = 3
TERMINAL = ("COMPLETE", "FAILED", "CANCELLED")


def load_api_key(explicit: str | None = None) -> str:
    key = explicit or os.environ.get("ROBLOX_API_KEY")
    if not key:
        sys.exit("ROBLOX_API_KEY not set in the environment or .env")
    return key


def _headers(key: str) -> dict[str, str]:
    return {"x-api-key": key, "User-Agent": roblox_web.API_USER_AGENT}


def _check(resp: requests.Response, what: str) -> dict[str, Any]:
    if resp.status_code >= 400:
        hint = ""
        if resp.status_code in (401, 403):
            hint = (
                "\n  The key needs the Luau Execution WRITE scope for THIS experience: in the"
                "\n  Creator Dashboard, edit the key and add the Luau Execution permission for"
                "\n  the experience whose universe id is ROBLOX_UNIVERSE_ID (the scope is granted"
                "\n  per-universe). Also check the key's IP allowlist."
            )
        sys.exit(f"{what} failed (HTTP {resp.status_code}).{hint}\n  {resp.text[:500]}")
    try:
        return resp.json()
    except ValueError:
        sys.exit(f"{what}: non-JSON response: {resp.text[:300]}")


def create_task(key: str, universe: str, place: str, script: str, timeout: str) -> dict[str, Any]:
    url = API_BASE + CREATE_PATH.format(u=universe, p=place)
    body = {"script": script, "timeout": timeout}
    return _check(requests.post(url, json=body, headers=_headers(key), timeout=60), "create task")


def _task_url(task_path: str, suffix: str = "") -> str:
    """The create response's `path` is relative to the API-version root (it
    omits the cloud/v2 prefix), so add it back."""
    p = task_path.strip("/")
    if not p.startswith("cloud/"):
        p = "cloud/v2/" + p
    return f"{API_BASE}/{p}{suffix}"


def poll_task(key: str, task_path: str, interval: int, label: str = "luau") -> dict[str, Any]:
    url = _task_url(task_path)
    while True:
        res = _check(requests.get(url, params={"view": "FULL"}, headers=_headers(key), timeout=60), "poll task")
        state = res.get("state")
        print(f"  {label}: {state}", file=sys.stderr)
        if state in TERMINAL:
            return res
        time.sleep(interval)


def get_logs(key: str, task_path: str) -> list[str]:
    url = _task_url(task_path, "/logs")
    try:
        res = _check(requests.get(url, params={"view": "FLAT"}, headers=_headers(key), timeout=60), "get logs")
    except SystemExit:
        return []
    out: list[str] = []
    for entry in res.get("luauExecutionSessionTaskLogs", []):
        out.extend(entry.get("messages", []))
    return out


def task_results(task: dict[str, Any]) -> Any:
    """The script's returned value(s) from a COMPLETE task. Open Cloud nests
    them under output.results (a list, one element per returned value)."""
    output = task.get("output") or {}
    if isinstance(output, dict) and "results" in output:
        return output["results"]
    return output


def run_script(
    key: str,
    universe: str,
    place: str,
    script: str,
    timeout: str = "120s",
    interval: int = POLL_SECS_DEFAULT,
    label: str = "luau",
) -> dict[str, Any]:
    """Submit a script, wait for it, return {state, results, error, logs, task}."""
    task = create_task(key, universe, place, script, timeout)
    path = task.get("path")
    if not path:
        sys.exit(f"create task returned no path: {json.dumps(task)[:300]}")
    print(f"  task: {path}", file=sys.stderr)
    done = poll_task(key, path, interval, label)
    logs = get_logs(key, path)
    return {
        "state": done.get("state"),
        "results": task_results(done) if done.get("state") == "COMPLETE" else None,
        "error": done.get("error"),
        "logs": logs,
        "task": done,
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument("--script", help="Inline Luau (or '-' to read stdin).")
    src.add_argument("--script-file", type=Path, help="Path to a .luau file to run.")
    ap.add_argument("--universe", default=roblox_web.env_id("ROBLOX_UNIVERSE_ID"), help="Universe id (else $ROBLOX_UNIVERSE_ID).")
    ap.add_argument("--place", default=roblox_web.env_id("ROBLOX_PLACE_ID"), help="Place id (else $ROBLOX_PLACE_ID).")
    ap.add_argument("--api-key", help="Open Cloud key (else $ROBLOX_API_KEY).")
    ap.add_argument("--timeout", default="120s", help="Script timeout duration (default 120s).")
    ap.add_argument("--poll-secs", type=int, default=POLL_SECS_DEFAULT)
    args = ap.parse_args()

    if not args.universe or not args.place:
        sys.exit("Need a universe + place: pass --universe/--place or set ROBLOX_UNIVERSE_ID / ROBLOX_PLACE_ID in .env.")

    if args.script_file:
        script = args.script_file.read_text(encoding="utf-8")
    elif args.script == "-":
        script = sys.stdin.read()
    else:
        script = args.script

    key = load_api_key(args.api_key)
    res = run_script(key, args.universe, args.place, script, args.timeout, args.poll_secs)

    for line in res["logs"]:
        print(f"  [log] {line}", file=sys.stderr)
    if res["state"] != "COMPLETE":
        print(f"Task ended {res['state']}: {json.dumps(res['error'])[:500]}", file=sys.stderr)
        return 1
    print(json.dumps(res["results"], indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
