#!/usr/bin/env bash
# bugloop for this project (installed by /bugloop init). Run from the project root like `rojo serve`:
#   ./bugloop.sh                 daily: listener in the background + the fixer-loop session in this window (rojo serve stays yours)
#   ./bugloop.sh down            stop that background listener
#   ./bugloop.sh serve           only the listener, in this window
#   ./bugloop.sh launch          only the fixer-loop Claude Code session
#   ./bugloop.sh status | pending | add "note" | projects | upgrade ...
HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL="$HOME/.claude/skills/bugloop/scripts/bugloop.py"
if [ $# -eq 0 ]; then set -- up; fi
exec python "$SKILL" --repo "$HERE" "$@"
