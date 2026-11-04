#!/usr/bin/env bash
#
# mayhem/test.sh — RUN the known-answer oracle built by mayhem/build.sh (normal flags, no sanitizers).
# The oracle asserts parsed values from Velox's type, date/time-format, JSON-path and timestamp parsers;
# this script counts its PASS/FAIL lines and requires its DONE marker, so a no-op/early-exit fails.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
cd "$SRC"

emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

ORACLE="$SRC/_build/bin/velox_oracle"
EXPECTED=15
if [ ! -x "$ORACLE" ]; then
  echo "missing $ORACLE (mayhem/build.sh should have built it)" >&2
  emit_ctrf "velox-kat" 0 1 0
  exit 1
fi

out="$(timeout 300 "$ORACLE" 2>/dev/null)"; rc=$?
printf '%s\n' "$out"
passed="$(printf '%s\n' "$out" | grep -c '^PASS ')"
failed="$(printf '%s\n' "$out" | grep -c '^FAIL ')"
done_n="$(printf '%s\n' "$out" | sed -n 's/^DONE \([0-9][0-9]*\)$/\1/p' | tail -1)"
# Missing checks (early exit, crash, wrong count) count as failures.
if [ "$rc" -ne 0 ] || [ "${done_n:-}" != "$EXPECTED" ] || [ "$passed" -ne "$EXPECTED" ]; then
  missing=$(( EXPECTED - passed - failed )); [ "$missing" -lt 1 ] && missing=0
  [ "$failed" -eq 0 ] && [ "$missing" -eq 0 ] && failed=1
  emit_ctrf "velox-kat" "$passed" $(( failed + missing )) 0
  exit 1
fi
emit_ctrf "velox-kat" "$passed" 0 0
