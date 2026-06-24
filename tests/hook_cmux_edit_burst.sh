#!/usr/bin/env bash
# Tests for hooks/track-cmux-edit-burst.sh

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$REPO/hooks/track-cmux-edit-burst.sh"

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

make_payload() {
  local tool="$1"
  printf '{"tool_name":"%s","tool_input":{"file_path":"x"}}' "$tool"
}

[ -x "$HOOK" ] || { echo "hook not executable: $HOOK" >&2; exit 1; }

# helper: run hook from a plain git repo (non-worktree) to avoid worktree-skip
_run_in_plain_repo() {
  local tmpbase; tmpbase=$(mktemp -d)
  local repo="$tmpbase/repo"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" commit --allow-empty -q -m init 2>/dev/null
  (cd "$repo" && "$@")
  local rc=$?
  rm -rf "$tmpbase"
  return $rc
}

# T1: CMUX_WORKSPACE_ID unset → exit 0
t1_unset_workspace() {
  local f; f=$(mktemp)
  local rc=0
  (unset CMUX_WORKSPACE_ID; make_payload "Edit" | CBP_BURST_FILE="$f" "$HOOK" >/dev/null 2>&1) || rc=$?
  rm -f "$f"
  [ "$rc" -eq 0 ]
}

# T2: cmux env + Edit tool_name → counter 1 + exit 0
t2_edit_increments() {
  local f; f=$(mktemp)
  local rc=0
  _run_in_plain_repo bash -c "make_payload() { printf '{\"tool_name\":\"%s\",\"tool_input\":{\"file_path\":\"x\"}}' \"\$1\"; }; make_payload Edit | CMUX_WORKSPACE_ID='test-ws' CBP_BURST_FILE='$f' '$HOOK' >/dev/null 2>&1" || rc=$?
  local cnt; cnt=$(cat "$f" 2>/dev/null || echo -1)
  rm -f "$f"
  [ "$rc" -eq 0 ] && [ "$cnt" -eq 1 ]
}

# T3: count=2 (below threshold=3) → exit 0, no advisory
t3_below_threshold_no_advisory() {
  local f; f=$(mktemp); echo "1" > "$f"
  local rc=0 err
  err=$(_run_in_plain_repo bash -c "make_payload() { printf '{\"tool_name\":\"%s\",\"tool_input\":{\"file_path\":\"x\"}}' \"\$1\"; }; make_payload Edit | CMUX_WORKSPACE_ID='test-ws' CBP_BURST_FILE='$f' CMUX_EDIT_BURST_THRESHOLD=3 '$HOOK' 2>&1 >/dev/null") || rc=$?
  rm -f "$f"
  [ "$rc" -eq 0 ] && ! echo "$err" | grep -q "dispatch-slice-pane"
}

# T4: count=3 (at threshold) → exit 0 + stderr has "dispatch-slice-pane"
t4_threshold_advisory() {
  local f; f=$(mktemp); echo "2" > "$f"
  local rc=0 err
  err=$(_run_in_plain_repo bash -c "make_payload() { printf '{\"tool_name\":\"%s\",\"tool_input\":{\"file_path\":\"x\"}}' \"\$1\"; }; make_payload Edit | CMUX_WORKSPACE_ID='test-ws' CBP_BURST_FILE='$f' CMUX_EDIT_BURST_THRESHOLD=3 '$HOOK' 2>&1 >/dev/null") || rc=$?
  rm -f "$f"
  [ "$rc" -eq 0 ] && echo "$err" | grep -q "dispatch-slice-pane"
}

# T5: T4 + CMUX_EDIT_BURST_STRICT=1 → exit 2
t5_strict_blocks() {
  local f; f=$(mktemp); echo "2" > "$f"
  local rc=0
  _run_in_plain_repo bash -c "make_payload() { printf '{\"tool_name\":\"%s\",\"tool_input\":{\"file_path\":\"x\"}}' \"\$1\"; }; make_payload Edit | CMUX_WORKSPACE_ID='test-ws' CBP_BURST_FILE='$f' CMUX_EDIT_BURST_THRESHOLD=3 CMUX_EDIT_BURST_STRICT=1 '$HOOK' >/dev/null 2>&1" || rc=$?
  rm -f "$f"
  [ "$rc" -eq 2 ]
}

# T6: mtime 6 minutes ago → auto reset → count=1
t6_mtime_reset() {
  local f; f=$(mktemp); echo "5" > "$f"
  python3 -c "import os,time; os.utime('$f', (time.time()-420, time.time()-420))"
  local rc=0
  _run_in_plain_repo bash -c "make_payload() { printf '{\"tool_name\":\"%s\",\"tool_input\":{\"file_path\":\"x\"}}' \"\$1\"; }; make_payload Edit | CMUX_WORKSPACE_ID='test-ws' CBP_BURST_FILE='$f' CMUX_EDIT_BURST_IDLE_SEC=300 '$HOOK' >/dev/null 2>&1" || rc=$?
  local cnt; cnt=$(cat "$f" 2>/dev/null || echo -1)
  rm -f "$f"
  [ "$rc" -eq 0 ] && [ "$cnt" -eq 1 ]
}

# T7: SKIP_CMUX_EDIT_BURST=1 → exit 0, counter unchanged
t7_skip_bypass() {
  local f; f=$(mktemp); echo "5" > "$f"
  local rc=0
  make_payload "Edit" | CMUX_WORKSPACE_ID="test-ws" CBP_BURST_FILE="$f" SKIP_CMUX_EDIT_BURST=1 "$HOOK" >/dev/null 2>&1 || rc=$?
  local cnt; cnt=$(cat "$f" 2>/dev/null || echo -1)
  rm -f "$f"
  [ "$rc" -eq 0 ] && [ "$cnt" -eq 5 ]
}

# T8: DISABLE_CMUX_EDIT_BURST_HOOK=1 → exit 0, counter unchanged
t8_disable_bypass() {
  local f; f=$(mktemp); echo "5" > "$f"
  local rc=0
  make_payload "Edit" | CMUX_WORKSPACE_ID="test-ws" CBP_BURST_FILE="$f" DISABLE_CMUX_EDIT_BURST_HOOK=1 "$HOOK" >/dev/null 2>&1 || rc=$?
  local cnt; cnt=$(cat "$f" 2>/dev/null || echo -1)
  rm -f "$f"
  [ "$rc" -eq 0 ] && [ "$cnt" -eq 5 ]
}

# T9: tool_name=Bash → exit 0, counter unchanged
t9_bash_skipped() {
  local f; f=$(mktemp); echo "5" > "$f"
  local rc=0
  make_payload "Bash" | CMUX_WORKSPACE_ID="test-ws" CBP_BURST_FILE="$f" "$HOOK" >/dev/null 2>&1 || rc=$?
  local cnt; cnt=$(cat "$f" 2>/dev/null || echo -1)
  rm -f "$f"
  [ "$rc" -eq 0 ] && [ "$cnt" -eq 5 ]
}

run "T1 unset workspace"          t1_unset_workspace
run "T2 edit increments counter"  t2_edit_increments
run "T3 below threshold no adv"   t3_below_threshold_no_advisory
run "T4 threshold advisory"       t4_threshold_advisory
run "T5 strict blocks"            t5_strict_blocks
run "T6 mtime reset"              t6_mtime_reset
run "T7 skip bypass"              t7_skip_bypass
run "T8 disable bypass"           t8_disable_bypass
run "T9 bash skipped"             t9_bash_skipped

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && echo "✅ all pass" || { echo "❌ FAILED: ${FAILED[*]}"; exit 1; }
