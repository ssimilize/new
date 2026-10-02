#!/usr/bin/env bash
# Opt-in local check: runs the Living World Foundry's `lore` static lint (SC3) over this checkout
# against the tracked baseline tools/lore_baseline.json. Not part of CI or tests/lint: the CI runner
# has no Foundry. Skips (exit 0) when the Foundry is missing; exits nonzero on findings the
# baseline does not hold. Accept the current findings again with:
#   tools/ci/lore.sh --baseline write
#
#   tools/ci/lore.sh            (from monster-ranch-idle/)
#   FOUNDRY_ROOT=<dir> tools/ci/lore.sh
set -u
here=$(cd "$(dirname "$0")/../.." && pwd)
foundry="${FOUNDRY_ROOT:-${USERPROFILE:-$HOME}/Documents/foundry}"
if [ ! -f "$foundry/foundry/__main__.py" ]; then
	echo "lore: SKIPPED (Foundry not found at $foundry)"
	exit 0
fi
py=py
command -v py >/dev/null 2>&1 || py=python3
mode="use"
if [ "${1:-}" = "--baseline" ] && [ -n "${2:-}" ]; then
	mode="$2"
	shift 2
fi
PYTHONPATH="$foundry" "$py" -m foundry lore check --game monster-ranch --root "$here/.." \
	--baseline "$mode" --baseline-file "$here/tools/lore_baseline.json" "$@"
rc=$?
[ $rc -eq 0 ] && echo "lore: OK" || echo "lore: FAILED (exit $rc)"
exit $rc
