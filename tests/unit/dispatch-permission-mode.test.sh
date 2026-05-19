#!/usr/bin/env bash
# dispatch-permission-mode.test.sh — build_child_cmd 의 --permission-mode 인자 검증

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DISPATCH="$REPO/scripts/dispatch-slice-pane.sh"

pass=0
fail_count=0
total=5

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

[ -f "$DISPATCH" ] || { echo "FAIL: $DISPATCH 없음" >&2; exit 1; }

# dispatch 를 source 해서 함수만 노출 (sourcing guard 로 main 은 실행 안됨)
# shellcheck source=/dev/null
source "$DISPATCH"

# 1. 기본값(permission_mode_env="" → bypassPermissions)
result=$(build_child_cmd "" interactive "" "" "")
check "기본값 → bypassPermissions" \
  "claude --model sonnet --permission-mode bypassPermissions" \
  "$result"

# 2. model=opus, permission_mode 기본값
result=$(build_child_cmd "" interactive opus "" "")
check "model=opus → bypassPermissions" \
  "claude --model opus --permission-mode bypassPermissions" \
  "$result"

# 3. permission_mode=acceptEdits 명시
result=$(build_child_cmd "" interactive "" "" "acceptEdits")
check "acceptEdits 명시" \
  "claude --model sonnet --permission-mode acceptEdits" \
  "$result"

# 4. permission_mode=default → flag 생략
result=$(build_child_cmd "" interactive "" "" "default")
check "default → flag 없음" \
  "claude --model sonnet" \
  "$result"

# 5. child_cmd_env set → child_cmd_env 우선 (permission-mode 무시)
result=$(build_child_cmd "zsh" interactive "" "" "bypassPermissions")
check "child_cmd_env 우선 → zsh" \
  "zsh" \
  "$result"

echo ""
echo "ok: $pass/$total passed"
[ "$fail_count" -gt 0 ] && exit 1
exit 0
