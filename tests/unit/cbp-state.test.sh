#!/usr/bin/env bash
# cbp-state.test.sh — cmux-pane.sh 의 cbp_state_* 헬퍼 함수 단위 테스트
#
# 환경변수 주입:
#   CBP_STATE_FILE — state file 경로 override (기본: ~/.cache/cbp/children-<ws>.json)
#   CMUX_WORKSPACE_ID — workspace ID (sanitize 규칙 테스트용)

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO/scripts/cmux-pane.sh"

pass=0
fail_count=0

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

check_not_contains() {
  local desc="$1" not_expected="$2" actual="$3"
  if echo "$actual" | grep -qF -- "$not_expected"; then
    echo "FAIL: $desc — unexpected substring='$not_expected' found in output='$actual'" >&2
    fail_count=$((fail_count + 1))
  else
    echo "ok: $desc"
    pass=$((pass + 1))
  fi
}

[ -f "$SCRIPT" ] || { echo "FAIL: $SCRIPT 없음" >&2; exit 1; }

# 임시 state file 경로 inject
STATE_FILE="/tmp/test-cbp-$$.json"
export CBP_STATE_FILE="$STATE_FILE"
export CMUX_WORKSPACE_ID="workspace:test"

# cleanup trap
cleanup() {
  rm -f "$STATE_FILE" "$LOADER_SCRIPT"
}
trap cleanup EXIT

# ----------------------------------------------------------------
# cmux-pane.sh 의 마지막 줄 "main "$@"" 는 직접 실행 시 호출됨.
# sourcing guard 가 없으므로 source 시 main 이 실행됨 → exit 2.
# 해결: 마지막 "main "$@"" 줄을 제거한 loader script 생성.
# macOS sed: sed '$d' 는 마지막 줄 삭제.
LOADER_SCRIPT="/tmp/cbp-loader-$$.sh"
sed '$d' "$SCRIPT" > "$LOADER_SCRIPT"
# loader 하단에 sourcing guard 역할 줄 추가
echo "# loader: main call removed" >> "$LOADER_SCRIPT"
chmod +x "$LOADER_SCRIPT"

# 헬퍼 함수 호출: source loader 후 함수 실행
call_state() {
  local fn="$1"; shift
  env CBP_STATE_FILE="$STATE_FILE" \
      CMUX_WORKSPACE_ID="workspace:test" \
      CMUX_BIN="${CMUX_BIN:-cmux}" \
      CBP_WORKSPACE_PREFIX="cbp-" \
    bash -c "source '$LOADER_SCRIPT'; $fn \"\$@\"" -- "$@"
}

total=7

# ----------------------------------------------------------------
# 1. cbp_state_append + 파일 존재 + 1줄
call_state cbp_state_append "surface:1" "cbp-foo"
line_count=$(wc -l < "$STATE_FILE" | tr -d ' ')
check "append: file 존재 + 1줄" "1" "$line_count"

# ----------------------------------------------------------------
# 2. 두 번째 append → 2줄
call_state cbp_state_append "surface:2" "cbp-bar"
line_count=$(wc -l < "$STATE_FILE" | tr -d ' ')
check "append x2: 2줄" "2" "$line_count"

# ----------------------------------------------------------------
# 3. cbp_state_list → surface:1 과 surface:2 각 줄 포함
list_out=$(call_state cbp_state_list)
check_contains "list: surface:1 포함" "surface:1" "$list_out"
check_contains "list: surface:2 포함" "surface:2" "$list_out"

# ----------------------------------------------------------------
# 4. cbp_state_remove surface:1 → list 에 surface:2 만 남음
call_state cbp_state_remove "surface:1"
list_out=$(call_state cbp_state_list)
check_not_contains "remove: surface:1 제거됨" "surface:1" "$list_out"
check_contains "remove: surface:2 남음" "surface:2" "$list_out"

# ----------------------------------------------------------------
# 5. 동시성: bg job 10개로 append → 정확히 10줄 (flock/mutex lock 동작)
# 먼저 state file 초기화
rm -f "$STATE_FILE"

for i in $(seq 1 10); do
  (call_state cbp_state_append "surface:$i" "cbp-bg-$i") &
done
wait

concurrent_lines=$(wc -l < "$STATE_FILE" | tr -d ' ')
check "concurrent append x10: 정확히 10줄" "10" "$concurrent_lines"

echo ""
echo "ok: $pass/$total passed"
[ "$fail_count" -gt 0 ] && exit 1
exit 0
