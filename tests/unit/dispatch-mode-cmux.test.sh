#!/usr/bin/env bash
# dispatch-mode-cmux.test.sh — dispatch-slice-pane.sh 의 멀티-driver --mode 분기 검증
#
# 전제:
#   DISPATCH_DRY_RUN=1 — dispatch 가 wrapper 호출 직전에 JSON 출력 후 exit 0
#   DISPATCH_CHILD_CMD=: — 자식 명령 no-op mock
#   CMUX_BIN=echo — cmux CLI mock (모든 서브커맨드 echo 로 대체)
#   DISPATCH_SKIP_CLEANUP=1 — tmux cleanup 스킵
#   DISPATCH_SKIP_WORKTREE=1 — git worktree 생성 스킵 (DRY_RUN 시 자동)

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DISPATCH="$REPO/scripts/dispatch-slice-pane.sh"
DETECT="$REPO/scripts/detect-pane-env.sh"
TRUE_BIN="$(which true)"
FALSE_BIN="$(which false)"

pass=0
fail_count=0
total=15

check() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "ok: $desc"
    pass=$((pass + 1))
  else
    echo "FAIL: $desc — expected='$expected' got='$actual'" >&2
    fail_count=$((fail_count + 1))
  fi
}

check_contains() {
  local desc="$1" expected="$2" actual="$3"
  if echo "$actual" | grep -qF -- "$expected"; then
    echo "ok: $desc"
    pass=$((pass + 1))
  else
    echo "FAIL: $desc — expected substring='$expected' in output='$actual'" >&2
    fail_count=$((fail_count + 1))
  fi
}

[ -f "$DISPATCH" ] || { echo "FAIL: $DISPATCH 없음" >&2; exit 1; }

# spec 파일 준비 (DRY_RUN 시 존재 검사는 pass 함)
SPEC_FILE="/tmp/cbp-spec-$$.md"
printf '# test spec\n' > "$SPEC_FILE"
trap 'rm -f "$SPEC_FILE"' EXIT

# 공통 base env: worktree 생성 없이 dry-run 만 검증
# DISPATCH_DRY_RUN=1 이면 spec-file 존재 검사 없이 JSON 출력 후 exit 0
BASE_ENV="DISPATCH_DRY_RUN=1 DISPATCH_SKIP_CLEANUP=1 DISPATCH_CHILD_CMD=:"

# ----------------------------------------------------------------
# 1. --mode=tmux → driver=tmux
result=$(env -i \
  DISPATCH_DRY_RUN=1 \
  DISPATCH_SKIP_CLEANUP=1 \
  DISPATCH_CHILD_CMD=: \
  PATH="$PATH" \
  HOME="${HOME:-/tmp}" \
  bash "$DISPATCH" --slice=t --spec-file="$SPEC_FILE" --mode=tmux 2>/dev/null)
check_contains "--mode=tmux → driver=tmux" '"driver":"tmux"' "$result"

# ----------------------------------------------------------------
# 2. --mode=cmux → driver=cmux
result=$(env -i \
  DISPATCH_DRY_RUN=1 \
  DISPATCH_SKIP_CLEANUP=1 \
  DISPATCH_CHILD_CMD=: \
  CMUX_BIN=echo \
  PATH="$PATH" \
  HOME="${HOME:-/tmp}" \
  bash "$DISPATCH" --slice=t --spec-file="$SPEC_FILE" --mode=cmux 2>/dev/null)
check_contains "--mode=cmux → driver=cmux" '"driver":"cmux"' "$result"

# ----------------------------------------------------------------
# 3. --mode=pane → driver=tmux (alias 호환)
result=$(env -i \
  DISPATCH_DRY_RUN=1 \
  DISPATCH_SKIP_CLEANUP=1 \
  DISPATCH_CHILD_CMD=: \
  PATH="$PATH" \
  HOME="${HOME:-/tmp}" \
  bash "$DISPATCH" --slice=t --spec-file="$SPEC_FILE" --mode=pane 2>/dev/null)
check_contains "--mode=pane → driver=tmux" '"driver":"tmux"' "$result"

# ----------------------------------------------------------------
# 4. --mode=auto + TMUX set → driver=tmux
result=$(env -i \
  DISPATCH_DRY_RUN=1 \
  DISPATCH_SKIP_CLEANUP=1 \
  DISPATCH_CHILD_CMD=: \
  TMUX="/tmp/tmux.sock" \
  PATH="$PATH" \
  HOME="${HOME:-/tmp}" \
  bash "$DISPATCH" --slice=t --spec-file="$SPEC_FILE" --mode=auto 2>/dev/null)
check_contains "--mode=auto + TMUX set → driver=tmux" '"driver":"tmux"' "$result"

# ----------------------------------------------------------------
# 5. --mode=auto + CMUX_SOCKET_PASSWORD set (no TMUX) → driver=cmux
result=$(env -i \
  DISPATCH_DRY_RUN=1 \
  DISPATCH_SKIP_CLEANUP=1 \
  DISPATCH_CHILD_CMD=: \
  CMUX_SOCKET_PASSWORD="secret" \
  CMUX_BIN=echo \
  PATH="$PATH" \
  HOME="${HOME:-/tmp}" \
  bash "$DISPATCH" --slice=t --spec-file="$SPEC_FILE" --mode=auto 2>/dev/null)
check_contains "--mode=auto + CMUX_SOCKET_PASSWORD → driver=cmux" '"driver":"cmux"' "$result"

# ----------------------------------------------------------------
# 6. --mode=auto + CMUX_BIN=true (ping 성공, no TMUX) → driver=cmux
result=$(env -i \
  DISPATCH_DRY_RUN=1 \
  DISPATCH_SKIP_CLEANUP=1 \
  DISPATCH_CHILD_CMD=: \
  CMUX_BIN="$TRUE_BIN" \
  PATH="$PATH" \
  HOME="${HOME:-/tmp}" \
  bash "$DISPATCH" --slice=t --spec-file="$SPEC_FILE" --mode=auto 2>/dev/null)
check_contains "--mode=auto + CMUX_BIN=true (ping 성공) → driver=cmux" '"driver":"cmux"' "$result"

# ----------------------------------------------------------------
# 7. --mode=auto + 둘 다 unset (CMUX_BIN=false → ping 실패) → exit 2
exit_code=0
env -i \
  DISPATCH_DRY_RUN=1 \
  DISPATCH_SKIP_CLEANUP=1 \
  DISPATCH_CHILD_CMD=: \
  CMUX_BIN="$FALSE_BIN" \
  PATH="$PATH" \
  HOME="${HOME:-/tmp}" \
  bash "$DISPATCH" --slice=t --spec-file="$SPEC_FILE" --mode=auto 2>/dev/null \
  || exit_code=$?
check "--mode=auto + no env → exit 2" "2" "$exit_code"

# ----------------------------------------------------------------
# 8. --mode=subagent → exit 0 + stderr 안내
stderr_msg=$(env -i \
  DISPATCH_DRY_RUN=1 \
  DISPATCH_SKIP_CLEANUP=1 \
  DISPATCH_CHILD_CMD=: \
  PATH="$PATH" \
  HOME="${HOME:-/tmp}" \
  bash "$DISPATCH" --slice=t --spec-file="$SPEC_FILE" --mode=subagent 2>&1 >/dev/null) || true
check_contains "--mode=subagent → stderr 안내 포함" "subagent" "$stderr_msg"

# ----------------------------------------------------------------
# 9. --mode=subagent → exit 0
exit_code=99
env -i \
  DISPATCH_DRY_RUN=1 \
  DISPATCH_SKIP_CLEANUP=1 \
  DISPATCH_CHILD_CMD=: \
  PATH="$PATH" \
  HOME="${HOME:-/tmp}" \
  bash "$DISPATCH" --slice=t --spec-file="$SPEC_FILE" --mode=subagent 2>/dev/null \
  && exit_code=0 || exit_code=$?
check "--mode=subagent → exit 0" "0" "$exit_code"

# ----------------------------------------------------------------
# T4. validate_pane_ref — wrapper launch 계약 검증
# dispatch 를 source 해서 함수만 노출 (main 은 sourcing guard 로 안 불림)
# ----------------------------------------------------------------
source "$DISPATCH"

# T4-pass-a: surface:N 통과
result=$(validate_pane_ref "surface:5" 2>/dev/null) && rc=0 || rc=$?
check "T4-pass: surface:5 → 통과" "surface:5" "$result"

# T4-pass-b: workspace:cbp-abc123 통과
result=$(validate_pane_ref "workspace:cbp-abc123" 2>/dev/null) && rc=0 || rc=$?
check "T4-pass: workspace:cbp-abc123 → 통과" "workspace:cbp-abc123" "$result"

# T4-pass-c: trailing \r\n 트림 후 surface:5
result=$(validate_pane_ref "$(printf 'surface:5\r\n')" 2>/dev/null) && rc=0 || rc=$?
check "T4-pass: trailing CRLF 트림 → surface:5" "surface:5" "$result"

# T4-fail-a: cmux 응답 누수형 PANE → DIE (exit non-zero)
validate_pane_ref "OK action=rename tab=tab:5 workspace=workspace:3 surface:5" >/dev/null 2>&1 && rc=0 || rc=$?
check "T4-fail: 'OK action=...' 깨진 ref → 거부" "1" "$rc"

# T4-fail-b: 빈 문자열 → DIE
validate_pane_ref "" >/dev/null 2>&1 && rc=0 || rc=$?
check "T4-fail: 빈 문자열 → 거부" "1" "$rc"

# T4-fail-c: garbage → DIE
validate_pane_ref "garbage" >/dev/null 2>&1 && rc=0 || rc=$?
check "T4-fail: 'garbage' → 거부" "1" "$rc"

echo ""
echo "ok: $pass/$total passed"
[ "$fail_count" -gt 0 ] && exit 1
exit 0
