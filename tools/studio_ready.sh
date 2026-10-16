#!/usr/bin/env bash
# Exit 0 when Hot Frog can be checked live: some running `rojo serve` (any port; several
# projects' servers may run at once and ports change day to day) serves this project, and
# a Roblox Studio window (one of possibly several) is titled with the place name.
# Prints the Rojo port on success. Usage: tools/studio_ready.sh [--rojo-only]
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NAME="$(sed -n 's/^ *"name": *"\([^"]*\)".*/\1/p' "$ROOT/default.project.json" | head -1)"
[ -n "$NAME" ] || { echo "no \"name\" in default.project.json" >&2; exit 1; }
PLACE="Hot Frog"

PORTS="$(powershell.exe -NoProfile -Command \
	'Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object { (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).ProcessName -eq "rojo" } | ForEach-Object { $_.LocalPort }' \
	2>/dev/null | tr -d '\r' | sort -un)"
# Rojo 7.7 answers in MessagePack: a name under 32 bytes is a fixstr whose first byte is
# 0xa0 + length, so matching that byte too rejects a project whose name merely contains ours.
PAT="$NAME"
if [ "${#NAME}" -lt 32 ]; then
	B="$(printf '%03o' $((0xa0 + ${#NAME})))"
	PAT="$(printf "\\$B")$NAME"
fi
FOUND=""
for p in $PORTS; do
	if curl -s --max-time 1 "http://127.0.0.1:$p/api/rojo" | LC_ALL=C grep -aqF "$PAT"; then
		FOUND="$p"
		break
	fi
done
[ -n "$FOUND" ] || { echo "no rojo serve is serving $NAME (rojo ports: ${PORTS:-none})" >&2; exit 1; }

if [ "${1:-}" != "--rojo-only" ]; then
	powershell.exe -NoProfile -Command \
		'(Get-Process RobloxStudioBeta -ErrorAction SilentlyContinue).MainWindowTitle' 2>/dev/null \
		| grep -q "$PLACE" || { echo "no Roblox Studio window titled $PLACE" >&2; exit 1; }
fi
echo "$FOUND"
