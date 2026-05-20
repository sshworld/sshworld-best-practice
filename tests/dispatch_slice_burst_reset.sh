#!/usr/bin/env bash
# Tests for dispatch-slice-pane.sh --mode=cmux burst counter reset

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DISPATCH="$REPO/scripts/dispatch-slice-pane.sh"

PASS=0; FAIL=0; FAILED=()

run() {
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then
    PASS=$((PASS+1))
    echo "✔ $name"
  else
    FAIL=$((FAIL+1))
    FAILED+=("$name")
    echo "✘ $name" >&2
  fi
}

[ -x "$DISPATCH" ] || { echo "dispatch not executable: $DISPATCH" >&2; exit 1; }

# T1: counter file "5" exists → dispatch dry-run → file deleted
t1_burst_reset_on_dispatch() {
  local f; f=$(mktemp); echo "5" > "$f"
  local rc=0
  CMUX_WORKSPACE_ID="test-ws" CBP_BURST_FILE="$f" DISPATCH_DRY_RUN=1 \
    "$DISPATCH" --mode=cmux --slice=x --spec-file=/tmp/x >/dev/null 2>&1 || rc=$?
  local exists=0
  [ -f "$f" ] && exists=1
  rm -f "$f"
  [ "$rc" -eq 0 ] && [ "$exists" -eq 0 ]
}

# T2: no counter file → dispatch dry-run → no error
t2_no_file_no_error() {
  local f="/tmp/cbp-burst-nonexistent-$(date +%s).count"
  local rc=0
  CMUX_WORKSPACE_ID="test-ws" CBP_BURST_FILE="$f" DISPATCH_DRY_RUN=1 \
    "$DISPATCH" --mode=cmux --slice=x --spec-file=/tmp/x >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 0 ]
}

run "T1 burst reset on dispatch"  t1_burst_reset_on_dispatch
run "T2 no file no error"         t2_no_file_no_error

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && echo "✅ all pass" || { echo "❌ FAILED: ${FAILED[*]}"; exit 1; }
