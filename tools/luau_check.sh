#!/usr/bin/env bash
# Headless Luau type/lint check for a Rojo project (installed by /bugloop init).
# Usage: tools/luau_check.sh [files...]   (defaults to src/)
# Uses luau-lsp from rokit tool storage and the Roblox global types kept with the bugloop skill.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LSP="$(ls -d ~/.rokit/tool-storage/johnnymorganz/luau-lsp/*/luau-lsp.exe 2>/dev/null | sort -V | tail -1)"
DEFS="$HOME/.claude/skills/bugloop/templates/roblox/globalTypes.d.luau"
[ -x "$LSP" ] || { echo "luau-lsp not found in ~/.rokit/tool-storage" >&2; exit 2; }
MAP="${TEMP:-/tmp}/luau_check_sourcemap_$$.json"
trap 'rm -f "$MAP"' EXIT
rojo sourcemap "$ROOT/default.project.json" -o "$MAP" >/dev/null
cd "$ROOT"
STATUS=0
OUT="$("$LSP" analyze --defs="$DEFS" --sourcemap="$MAP" --no-strict-dm-types "${@:-src}" 2>&1)" || STATUS=$?
printf '%s
' "$OUT" | grep -v '^\[INFO\]\|^\[WARN\] client does not allow' | grep -v '^$' || true
exit $STATUS
