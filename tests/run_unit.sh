#!/usr/bin/env bash
# Runs every tests/test_*.mojo and fails on a failed test or a compiler warning.
set -uo pipefail
cd "$(dirname "$0")/.."

status=0
for f in tests/test_*.mojo; do
  log=$(mktemp)
  mojo run -I src "$f" >"$log" 2>&1
  rc=$?
  warnings=$(grep -cE '\.mojo:[0-9]+:[0-9]+: warning:' "$log" || true)
  summary=$(grep -E '^Summary' "$log" | sed 's/^Summary \[[^]]*\] //')
  printf '%-28s %s\n' "$f" "${summary:-no summary}"
  if [ "$rc" -ne 0 ] || [ "$warnings" -ne 0 ]; then
    [ "$warnings" -ne 0 ] && echo "  $warnings compiler warning(s)"
    grep -E 'FAIL|\.mojo:[0-9]+:[0-9]+: (error|warning):|AssertionError|left:|right:' -A2 "$log" | sed 's/^/  /' | head -40
    status=1
  fi
  rm -f "$log"
done
exit $status
