#!/usr/bin/env bash
# S2 — dispatch-slice-pane.sh cmux child-start verify + loud-fail/fallback.
# CMUX_BIN mock + DISPATCH_CHILD_CMD mock → capture 출력을 시나리오별로 고정.
#
# 시나리오:
#   T1: capture 에 claude TUI 패턴 즉시 포함 → dispatch 정상 종료 (success JSON, exit0)
#   T2: capture 가 항상 빈 shell prompt → exit 비0 + stderr "subagent" 포함
#   T3: DISPATCH_VERIFY=0 → 검증 skip, 기존 success 동작

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DISPATCH="$REPO/scripts/dispatch-slice-pane.sh"

PASS=0; FAIL=0; FAILED=()

fail_msg() { echo "  FAIL: $*" >&2; }

run() {
  local name="$1"; shift
  echo ""
  echo "[$name]"
  if "$@"; then
    PASS=$((PASS+1))
    echo "  OK"
  else
    FAIL=$((FAIL+1))
    FAILED+=("$name")
    echo "  FAILED" >&2
  fi
}

[ -f "$DISPATCH" ] || { echo "dispatcher missing: $DISPATCH" >&2; exit 1; }

# 공통 tmpdir
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

# 더미 git repo (worktree add 가 필요하므로 git repo 기반)
(
  cd "$tmpdir"
  git init -b main -q
  git config user.email t@e.local
  git config user.name tester
  echo dummy > README
  git add README
  git -c commit.gpgsign=false commit -m base -q
) 2>/dev/null

echo "spec content" > "$tmpdir/spec.md"

# ─────────────────────────────────────────────
# T1: claude TUI 패턴이 capture 에 즉시 나옴 → success JSON, exit 0
# ─────────────────────────────────────────────
t1_tui_detected_success() {
  local mock_cmux="$tmpdir/cmux-t1"
  local launch_count_file="$tmpdir/t1-launch-count"
  echo "0" > "$launch_count_file"

  cat > "$mock_cmux" <<'MOCK'
#!/usr/bin/env bash
case "$1" in
  ping)
    echo "PONG"; exit 0 ;;
  launch)
    echo "surface:1"; exit 0 ;;
  send|send-key)
    exit 0 ;;
  wait-idle)
    exit 0 ;;
  capture|read-screen)
    # claude TUI 패턴 포함 — 검증 성공
    echo "╭─────────────────────────────────────────╮"
    echo "│ > │"
    echo "╰─────────────────────────────────────────╯"
    echo "? for shortcuts"
    exit 0 ;;
  kill)
    exit 0 ;;
  identify)
    echo "workspace:1"; exit 0 ;;
  *)
    exit 0 ;;
esac
MOCK
  chmod +x "$mock_cmux"

  local out ec=0
  out=$(cd "$tmpdir" && \
    CMUX_BIN="$mock_cmux" \
    DISPATCH_CHILD_CMD="zsh" \
    DISPATCH_SKIP_CLEANUP=1 \
    DISPATCH_VERIFY_TRIES=2 \
    CBP_WARMUP_SLEEP=0 \
    CBP_SEND_CONFIRM=0 \
    bash "$DISPATCH" \
      --slice=verify-t1 \
      --spec-file="$tmpdir/spec.md" \
      --worktree="$tmpdir/.worktrees/verify-t1" \
      --mode=cmux 2>"$tmpdir/t1-stderr") || ec=$?

  if [ "$ec" -ne 0 ]; then
    fail_msg "exit code $ec (expected 0)"
    cat "$tmpdir/t1-stderr" >&2
    return 1
  fi

  # success JSON 확인
  echo "$out" | python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
assert 'pane' in d, 'pane 필드 없음'
assert d.get('driver') == 'cmux', 'driver != cmux'
" 2>&1 || { fail_msg "JSON 확인 실패: $out"; return 1; }

  return 0
}

# ─────────────────────────────────────────────
# T2: capture 가 항상 빈 shell prompt → exit 비0 + stderr "subagent" 포함
# ─────────────────────────────────────────────
t2_tui_not_detected_loud_fail() {
  local mock_cmux="$tmpdir/cmux-t2"

  cat > "$mock_cmux" <<'MOCK'
#!/usr/bin/env bash
case "$1" in
  ping)
    echo "PONG"; exit 0 ;;
  launch)
    echo "surface:2"; exit 0 ;;
  send|send-key)
    exit 0 ;;
  wait-idle)
    exit 0 ;;
  capture|read-screen)
    # claude TUI 패턴 없음 — shell prompt 만
    echo "user@host ~ % "
    exit 0 ;;
  kill)
    exit 0 ;;
  identify)
    echo "workspace:1"; exit 0 ;;
  *)
    exit 0 ;;
esac
MOCK
  chmod +x "$mock_cmux"

  local out ec=0
  out=$(cd "$tmpdir" && \
    CMUX_BIN="$mock_cmux" \
    DISPATCH_CHILD_CMD="zsh" \
    DISPATCH_SKIP_CLEANUP=1 \
    DISPATCH_VERIFY_TRIES=2 \
    CBP_WARMUP_SLEEP=0 \
    CBP_SEND_CONFIRM=0 \
    bash "$DISPATCH" \
      --slice=verify-t2 \
      --spec-file="$tmpdir/spec.md" \
      --worktree="$tmpdir/.worktrees/verify-t2" \
      --mode=cmux 2>"$tmpdir/t2-stderr") || ec=$?

  if [ "$ec" -eq 0 ]; then
    fail_msg "exit 0 이면 안 됨 (검증 실패여야 함). JSON: $out"
    return 1
  fi

  # stderr 에 "subagent" 포함 확인
  local stderr_out
  stderr_out=$(cat "$tmpdir/t2-stderr")
  if ! echo "$stderr_out" | grep -qi "subagent"; then
    fail_msg "stderr 에 'subagent' 없음: $stderr_out"
    return 1
  fi

  echo "  exit=$ec, stderr contains 'subagent' OK"
  return 0
}

# ─────────────────────────────────────────────
# T3: DISPATCH_VERIFY=0 → 검증 skip, 기존 success 동작
# ─────────────────────────────────────────────
t3_verify_disabled_skip() {
  local mock_cmux="$tmpdir/cmux-t3"

  cat > "$mock_cmux" <<'MOCK'
#!/usr/bin/env bash
case "$1" in
  ping)
    echo "PONG"; exit 0 ;;
  launch)
    echo "surface:3"; exit 0 ;;
  send|send-key)
    exit 0 ;;
  wait-idle)
    exit 0 ;;
  capture|read-screen)
    # 검증 skip 이므로 빈 prompt 여도 success 해야 함
    echo "user@host ~ % "
    exit 0 ;;
  kill)
    exit 0 ;;
  identify)
    echo "workspace:1"; exit 0 ;;
  *)
    exit 0 ;;
esac
MOCK
  chmod +x "$mock_cmux"

  local out ec=0
  out=$(cd "$tmpdir" && \
    CMUX_BIN="$mock_cmux" \
    DISPATCH_CHILD_CMD="zsh" \
    DISPATCH_SKIP_CLEANUP=1 \
    DISPATCH_VERIFY=0 \
    bash "$DISPATCH" \
      --slice=verify-t3 \
      --spec-file="$tmpdir/spec.md" \
      --worktree="$tmpdir/.worktrees/verify-t3" \
      --mode=cmux 2>"$tmpdir/t3-stderr") || ec=$?

  if [ "$ec" -ne 0 ]; then
    fail_msg "DISPATCH_VERIFY=0 인데 exit $ec (expected 0)"
    cat "$tmpdir/t3-stderr" >&2
    return 1
  fi

  echo "$out" | python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
assert 'pane' in d, 'pane 필드 없음'
" 2>&1 || { fail_msg "JSON 확인 실패: $out"; return 1; }

  echo "  DISPATCH_VERIFY=0 → skip → success OK"
  return 0
}

# ─────────────────────────────────────────────
# T4: DISPATCH_DRY_RUN=1 은 검증 코드를 타지 않고 기존대로 동작
# ─────────────────────────────────────────────
t4_dry_run_unaffected() {
  local out ec=0
  out=$(DISPATCH_DRY_RUN=1 \
    DISPATCH_SKIP_CLEANUP=1 \
    CMUX_BIN=echo \
    bash "$DISPATCH" \
      --slice=verify-t4 \
      --spec-file=/dev/null \
      --mode=cmux 2>/dev/null) || ec=$?

  if [ "$ec" -ne 0 ]; then
    fail_msg "DRY_RUN exit $ec (expected 0)"
    return 1
  fi

  echo "$out" | python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
assert d.get('driver') == 'cmux', 'driver != cmux'
assert 'worktree' in d, 'worktree 필드 없음'
" 2>&1 || { fail_msg "DRY_RUN JSON 확인 실패: $out"; return 1; }

  echo "  DRY_RUN unaffected OK"
  return 0
}

# ─────────────────────────────────────────────
# T5: tmux 모드는 영향 없음 (검증 코드 미실행 — DRY_RUN 으로만 확인)
# ─────────────────────────────────────────────
t5_tmux_mode_unaffected() {
  local out ec=0
  out=$(DISPATCH_DRY_RUN=1 \
    DISPATCH_SKIP_CLEANUP=1 \
    bash "$DISPATCH" \
      --slice=verify-t5 \
      --spec-file=/dev/null \
      --mode=tmux 2>/dev/null) || ec=$?

  if [ "$ec" -ne 0 ]; then
    fail_msg "tmux DRY_RUN exit $ec (expected 0)"
    return 1
  fi

  echo "$out" | python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
assert d.get('driver') == 'tmux', 'driver != tmux'
" 2>&1 || { fail_msg "tmux DRY_RUN JSON 확인 실패: $out"; return 1; }

  echo "  tmux mode unaffected OK"
  return 0
}

run "T1 TUI 감지 성공 → success JSON"     t1_tui_detected_success
run "T2 TUI 미감지 → exit 비0 + subagent" t2_tui_not_detected_loud_fail
run "T3 DISPATCH_VERIFY=0 → skip success" t3_verify_disabled_skip
run "T4 DRY_RUN 무영향"                   t4_dry_run_unaffected
run "T5 tmux 모드 무영향"                 t5_tmux_mode_unaffected

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && echo "✅ all pass" || { echo "❌ FAILED: ${FAILED[*]}"; exit 1; }
