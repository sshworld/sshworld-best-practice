#!/usr/bin/env bash
# dispatch-spec-file.test.sh — build_spec_prompt 순수 함수 검증

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DISPATCH="$REPO/scripts/dispatch-slice-pane.sh"

pass=0
fail_count=0
total=3

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

check_not_contains() {
  local desc="$1" unexpected="$2" actual="$3"
  if echo "$actual" | grep -qF -- "$unexpected"; then
    echo "FAIL: $desc — unexpected substring='$unexpected' found in output='$actual'" >&2
    fail_count=$((fail_count + 1))
  else
    echo "ok: $desc"
    pass=$((pass + 1))
  fi
}

[ -f "$DISPATCH" ] || { echo "FAIL: $DISPATCH 없음" >&2; exit 1; }

# dispatch 를 source 해서 함수만 노출 (sourcing guard 로 main 은 실행 안됨)
# shellcheck source=/dev/null
source "$DISPATCH"

# 테스트용 spec 파일 (본문이 있는 파일 — inline send 안 되어야 함)
SPEC_FILE="/tmp/test-spec-body-$$.md"
SPEC_BODY="This is the entire spec body content with lots of details"
printf '%s\n' "$SPEC_BODY" > "$SPEC_FILE"
trap 'rm -f "$SPEC_FILE"' EXIT

result=$(build_spec_prompt "/tmp/foo.md" "my-slice")

# 1. prompt 에 "Read /tmp/foo.md" 포함
check_contains "prompt 에 Read /tmp/foo.md 포함" \
  "Read /tmp/foo.md" \
  "$result"

# 2. prompt 에 "✅ my-slice" 포함
check_contains "prompt 에 checkmark my-slice 포함" \
  "✅ my-slice" \
  "$result"

# 3. spec 본문(긴 내용)이 prompt 에 포함되지 않음 (경로만 전달, inline send 금지 패턴 검증)
result2=$(build_spec_prompt "$SPEC_FILE" "my-slice")
check_not_contains "spec 본문이 prompt 에 포함되지 않음" \
  "$SPEC_BODY" \
  "$result2"

echo ""
echo "ok: $pass/$total passed"
[ "$fail_count" -gt 0 ] && exit 1
exit 0
