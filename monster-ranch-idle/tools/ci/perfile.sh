#!/usr/bin/env bash
# Runs the whole test suite one spec file per `lune run tests` process, so no single process holds
# every spec's worlds at once (the one-process run grew past the CI runner's memory and was killed,
# exit 143, 2026-09-27). The filter is a substring, so a file whose name contains another file's
# name (GamepadClient.spec contains Client.spec) is already covered by that file's run and is
# skipped. Fails when any run fails or ends without its summary line.
#
#   tools/ci/perfile.sh            (from monster-ranch-idle/)
set -u
plan=$(python3 - <<'PY'
import os
files = sorted(f for f in os.listdir("tests/specs") if f.endswith(".spec.luau"))
low = {f: f.lower() for f in files}
for f in files:
    if not any(o != f and low[o] in low[f] for o in files):
        print(f)
PY
)
failed=0
total=0
for f in $plan; do
	total=$((total + 1))
	out=$(lune run tests "$f" 2>&1)
	rc=$?
	summary=$(printf '%s\n' "$out" | grep -a 'passed,' | tail -1)
	if [ $rc -ne 0 ] || [ -z "$summary" ]; then
		printf '%s\n' "$out" | grep -a -v '^\[Kernel\] started' | tail -80
		echo "FAILED: $f (exit $rc)"
		failed=$((failed + 1))
	else
		echo "$f: $summary"
	fi
done
echo "$total spec runs, $failed failed"
[ $failed -eq 0 ]
