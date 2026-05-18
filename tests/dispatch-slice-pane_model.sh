#!/usr/bin/env bash
# Slice F — dispatch-slice-pane.sh 의 build_child_cmd 순수 함수 단위 테스트.
# dispatcher 를 source 해서 함수만 사용. main flow 는 실행 안 함.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DISPATCH="$REPO/scripts/dispatch-slice-pane.sh"

step() { echo "[$1] $2"; }
fail() { echo "❌ FAIL: $1" >&2; exit 1; }

[ -f "$DISPATCH" ] || fail "dispatcher missing"

# dispatcher 는 source 됐을 때 main 을 실행하지 않아야 함 (sourcing guard).
# 즉 dispatcher 가 `[ "$0" = "${BASH_SOURCE[0]}" ] && main "$@"` 패턴이거나
# main 자체를 함수로 두고 끝에서만 호출하는 구조여야 함.
DISPATCH_SOURCED=1 source "$DISPATCH" 2>/dev/null || true

# build_child_cmd 함수 존재 확인
type build_child_cmd > /dev/null 2>&1 || fail "build_child_cmd 함수 미정의"

step 1 "DISPATCH_CHILD_CMD env 가 최우선"
RESULT=$(build_child_cmd "zsh" "interactive" "" "")
[ "$RESULT" = "zsh" ] || fail "expected 'zsh', got '$RESULT'"

step 2 "--model=haiku arg"
RESULT=$(build_child_cmd "" "interactive" "haiku" "")
[ "$RESULT" = "claude --model haiku" ] || fail "expected 'claude --model haiku', got '$RESULT'"

step 3 "DISPATCH_DEFAULT_MODEL env (arg 없을 때)"
RESULT=$(build_child_cmd "" "interactive" "" "opus")
[ "$RESULT" = "claude --model opus" ] || fail "expected 'claude --model opus', got '$RESULT'"

step 4 "arg 가 env 보다 우선"
RESULT=$(build_child_cmd "" "interactive" "haiku" "opus")
[ "$RESULT" = "claude --model haiku" ] || fail "expected arg-wins 'claude --model haiku', got '$RESULT'"

step 5 "모두 미지정 → sonnet 디폴트"
RESULT=$(build_child_cmd "" "interactive" "" "")
[ "$RESULT" = "claude --model sonnet" ] || fail "expected 'claude --model sonnet', got '$RESULT'"

step 6 "CHILD_CMD env 는 model 보다도 우선"
RESULT=$(build_child_cmd "/usr/bin/something" "interactive" "haiku" "opus")
[ "$RESULT" = "/usr/bin/something" ] || fail "CHILD_CMD should win"

echo "OK"
