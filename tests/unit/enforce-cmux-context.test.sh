#!/usr/bin/env bash
# enforce-cmux-context.test.sh — enforce-cmux-context.sh hook 단위 검증
#
# 전제: jq 가용 (payload JSON 구성에 사용)
#   - stdin payload mock: make_payload 함수
#   - 케이스별 exit code + stderr 검증

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$REPO/.claude/hooks/enforce-cmux-context.sh"

pass=0
fail_count=0
total=8

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

check_empty() {
  local desc="$1" actual="$2"
  if [ -z "$actual" ]; then
    echo "ok: $desc"
    pass=$((pass + 1))
  else
    echo "FAIL: $desc — expected empty stderr, got='$actual'" >&2
    fail_count=$((fail_count + 1))
  fi
}

[ -f "$HOOK" ] || { echo "FAIL: $HOOK 없음" >&2; exit 1; }

# stdin payload 생성 헬퍼
make_payload() {
  local cmd="$1"
  printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$cmd"
}

# ----------------------------------------------------------------
# 1. cmux 안 + tmux send-keys → exit 0 + stderr 에 advisory 포함
stderr_out=$(make_payload "tmux send-keys -t pane1 'ls' Enter" | \
  env -i CMUX_WORKSPACE_ID="ws:1" PATH="$PATH" HOME="${HOME:-/tmp}" \
  bash "$HOOK" 2>&1 >/dev/null) || true
ec=0
make_payload "tmux send-keys -t pane1 'ls' Enter" | \
  env -i CMUX_WORKSPACE_ID="ws:1" PATH="$PATH" HOME="${HOME:-/tmp}" \
  bash "$HOOK" 2>/dev/null; ec=$?
check "case1: tmux send-keys in cmux → exit 0" "0" "$ec"
check_contains "case1: tmux send-keys in cmux → stderr advisory" "cmux 안에서 tmux" "$stderr_out"

# ----------------------------------------------------------------
# 2. cmux 안 + git commit (tmux 문자 포함 메시지) → exit 0 + stderr 없음
stderr_out2=$(make_payload 'git commit -m "fix tmux race"' | \
  env -i CMUX_WORKSPACE_ID="ws:1" PATH="$PATH" HOME="${HOME:-/tmp}" \
  bash "$HOOK" 2>&1 >/dev/null) || true
ec2=0
make_payload 'git commit -m "fix tmux race"' | \
  env -i CMUX_WORKSPACE_ID="ws:1" PATH="$PATH" HOME="${HOME:-/tmp}" \
  bash "$HOOK" 2>/dev/null; ec2=$?
check "case2: git commit in cmux → exit 0" "0" "$ec2"
check_empty "case2: git commit in cmux → no advisory" "$stderr_out2"

# ----------------------------------------------------------------
# 3. cmux 안 + cmux send → exit 0 + stderr 없음
stderr_out3=$(make_payload "cmux send --pane ws:1 'ls'" | \
  env -i CMUX_WORKSPACE_ID="ws:1" PATH="$PATH" HOME="${HOME:-/tmp}" \
  bash "$HOOK" 2>&1 >/dev/null) || true
ec3=0
make_payload "cmux send --pane ws:1 'ls'" | \
  env -i CMUX_WORKSPACE_ID="ws:1" PATH="$PATH" HOME="${HOME:-/tmp}" \
  bash "$HOOK" 2>/dev/null; ec3=$?
check "case3: cmux send in cmux → exit 0" "0" "$ec3"
check_empty "case3: cmux send in cmux → no advisory" "$stderr_out3"

# ----------------------------------------------------------------
# 4. cmux 환경 아님 (CMUX_WORKSPACE_ID unset) + tmux list-panes → exit 0
ec4=0
make_payload "tmux list-panes" | \
  env -i PATH="$PATH" HOME="${HOME:-/tmp}" \
  bash "$HOOK" 2>/dev/null; ec4=$?
check "case4: tmux list-panes, no CMUX_WORKSPACE_ID → exit 0" "0" "$ec4"

# ----------------------------------------------------------------
# 5. cmux 안 + tmux send-keys + STRICT=1 → exit 2
ec5=0
make_payload "tmux send-keys" | \
  env -i CMUX_WORKSPACE_ID="ws:1" CMUX_CONTEXT_HOOK_STRICT="1" \
  PATH="$PATH" HOME="${HOME:-/tmp}" \
  bash "$HOOK" 2>/dev/null || ec5=$?
check "case5: STRICT=1 → exit 2" "2" "$ec5"

# ----------------------------------------------------------------
# 6. cmux 안 + tmux send-keys + SKIP=1 → exit 0 + stderr 없음
stderr_out6=$(make_payload "tmux send-keys" | \
  env -i CMUX_WORKSPACE_ID="ws:1" SKIP_CMUX_CONTEXT_HOOK="1" \
  PATH="$PATH" HOME="${HOME:-/tmp}" \
  bash "$HOOK" 2>&1 >/dev/null) || true
ec6=0
make_payload "tmux send-keys" | \
  env -i CMUX_WORKSPACE_ID="ws:1" SKIP_CMUX_CONTEXT_HOOK="1" \
  PATH="$PATH" HOME="${HOME:-/tmp}" \
  bash "$HOOK" 2>/dev/null; ec6=$?
check "case6: SKIP_CMUX_CONTEXT_HOOK=1 → exit 0" "0" "$ec6"
check_empty "case6: SKIP_CMUX_CONTEXT_HOOK=1 → no advisory" "$stderr_out6"

# ----------------------------------------------------------------
# 7. cmux 안 + "echo hi; tmux list-panes" (multi-segment) → exit 0 + stderr advisory
stderr_out7=$(make_payload "echo hi; tmux list-panes" | \
  env -i CMUX_WORKSPACE_ID="ws:1" PATH="$PATH" HOME="${HOME:-/tmp}" \
  bash "$HOOK" 2>&1 >/dev/null) || true
ec7=0
make_payload "echo hi; tmux list-panes" | \
  env -i CMUX_WORKSPACE_ID="ws:1" PATH="$PATH" HOME="${HOME:-/tmp}" \
  bash "$HOOK" 2>/dev/null; ec7=$?
check "case7: multi-segment tmux in cmux → exit 0" "0" "$ec7"
check_contains "case7: multi-segment tmux in cmux → stderr advisory" "cmux 안에서 tmux" "$stderr_out7"

# ----------------------------------------------------------------
# 8. cmux 안 + ./scripts/tmux-pane.sh launch → exit 0 + stderr advisory
stderr_out8=$(make_payload "./scripts/tmux-pane.sh launch zsh" | \
  env -i CMUX_WORKSPACE_ID="ws:1" PATH="$PATH" HOME="${HOME:-/tmp}" \
  bash "$HOOK" 2>&1 >/dev/null) || true
ec8=0
make_payload "./scripts/tmux-pane.sh launch zsh" | \
  env -i CMUX_WORKSPACE_ID="ws:1" PATH="$PATH" HOME="${HOME:-/tmp}" \
  bash "$HOOK" 2>/dev/null; ec8=$?
check "case8: ./scripts/tmux-pane.sh in cmux → exit 0" "0" "$ec8"
check_contains "case8: ./scripts/tmux-pane.sh in cmux → stderr advisory" "cmux 안에서 tmux" "$stderr_out8"

echo ""
echo "ok: $pass/$total passed"
[ "$fail_count" -gt 0 ] && exit 1
exit 0
