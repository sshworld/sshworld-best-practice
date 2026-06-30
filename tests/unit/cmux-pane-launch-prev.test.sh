#!/usr/bin/env bash
# cmux-pane-launch-prev.test.sh — _do_launch_grid 의 live-prev 선택 검증
# dead prev_surface(tail-1) 가 있을 때 new-split 이 dead ref 기준으로 호출 안 되고
# live ref 기준 또는 new-pane 폴백임을 assert.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO/scripts/cmux-pane.sh"

pass=0
fail_count=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

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
  if printf '%s' "$actual" | grep -qF -- "$expected"; then
    echo "ok: $desc"
    pass=$((pass + 1))
  else
    echo "FAIL: $desc — expected substring='$expected' in output='$actual'" >&2
    fail_count=$((fail_count + 1))
  fi
}

check_not_contains() {
  local desc="$1" not_expected="$2" actual="$3"
  if printf '%s' "$actual" | grep -qF -- "$not_expected"; then
    echo "FAIL: $desc — unexpected substring='$not_expected' found in output='$actual'" >&2
    fail_count=$((fail_count + 1))
  else
    echo "ok: $desc"
    pass=$((pass + 1))
  fi
}

[ -f "$SCRIPT" ] || { echo "FAIL: $SCRIPT 없음" >&2; exit 1; }

total=9

# ----------------------------------------------------------------
# Mock cmux 구조:
#   - read-screen: CMUX_DEAD_SURFACE env 에 있는 ref 면 exit 1 (dead), 그 외 exit 0 (alive)
#   - new-pane: "OK surface:100\n" 출력 + CMUX_CALLS 에 기록
#   - new-split: "OK surface:101\n" 출력 + CMUX_CALLS 에 기록
#   - 그 외: CMUX_CALLS 에 기록 + exit 0
cat > "$TMP/cmux" << 'EOF'
#!/usr/bin/env bash
cmd="$1"; shift
log="${CMUX_CALLS:-/dev/null}"
case "$cmd" in
  read-screen)
    # --surface <ref> 형식 파싱
    surface_ref=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --surface) surface_ref="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    dead="${CMUX_DEAD_SURFACE:-}"
    if [ -n "$dead" ] && [ "$surface_ref" = "$dead" ]; then
      echo "Terminal not found" >&2
      exit 1
    fi
    echo "prompt"
    exit 0
    ;;
  new-pane)
    echo "new-pane $*" >> "$log"
    echo "OK surface:100"
    exit 0
    ;;
  new-split)
    echo "new-split $*" >> "$log"
    echo "OK surface:101"
    exit 0
    ;;
  rename-tab|send-key)
    echo "$cmd $*" >> "$log"
    exit 0
    ;;
  *)
    echo "$cmd $*" >> "$log"
    exit 0
    ;;
esac
EOF
chmod +x "$TMP/cmux"

# ----------------------------------------------------------------
# TC-1: state 가 비어있음 → new-pane 경로 (첫 자식)
STATE_FILE="$TMP/state1.json"
> "$STATE_FILE"
CALLS="$TMP/calls1.log"
> "$CALLS"

CMUX_BIN="$TMP/cmux" \
  CMUX_WORKSPACE_ID="ws:1" \
  CBP_STATE_FILE="$STATE_FILE" \
  CBP_DISABLE_WARMUP=1 \
  CMUX_CALLS="$CALLS" \
  CMUX_DEAD_SURFACE="" \
  bash "$SCRIPT" launch 2>/dev/null
new_pane_count=$(grep "^new-pane" "$CALLS" 2>/dev/null | wc -l | tr -d ' ')
new_split_count=$(grep "^new-split" "$CALLS" 2>/dev/null | wc -l | tr -d ' ')
check "TC-1: 빈 state → new-pane 호출" "1" "$new_pane_count"
check "TC-1: 빈 state → new-split 미호출" "0" "$new_split_count"

# ----------------------------------------------------------------
# TC-2: state 에 살아있는 prev_surface 만 있음 → new-split 이 그 ref 기준 호출됨
STATE_FILE="$TMP/state2.json"
printf 'surface=surface:5|name=cbp-aaa|ts=111|ws=ws:1\n' > "$STATE_FILE"
CALLS="$TMP/calls2.log"
> "$CALLS"

CMUX_BIN="$TMP/cmux" \
  CMUX_WORKSPACE_ID="ws:1" \
  CBP_STATE_FILE="$STATE_FILE" \
  CBP_DISABLE_WARMUP=1 \
  CMUX_CALLS="$CALLS" \
  CMUX_DEAD_SURFACE="" \
  bash "$SCRIPT" launch 2>/dev/null
new_split_line=$(grep "^new-split" "$CALLS" 2>/dev/null | head -1 || echo "")
check_contains "TC-2: live prev → new-split --surface surface:5" "--surface surface:5" "$new_split_line"
new_pane_count=$(grep "^new-pane" "$CALLS" 2>/dev/null | wc -l | tr -d ' ')
check "TC-2: live prev → new-pane 미호출" "0" "$new_pane_count"

# ----------------------------------------------------------------
# TC-3: state tail-1 이 dead, 앞에 live 가 있음 → new-split 이 live ref 기준으로 호출
# state: surface:5(live), surface:6(dead) — tail-1 은 surface:6
STATE_FILE="$TMP/state3.json"
printf 'surface=surface:5|name=cbp-aaa|ts=111|ws=ws:1\nsurface=surface:6|name=cbp-bbb|ts=222|ws=ws:1\n' > "$STATE_FILE"
CALLS="$TMP/calls3.log"
> "$CALLS"

CMUX_BIN="$TMP/cmux" \
  CMUX_WORKSPACE_ID="ws:1" \
  CBP_STATE_FILE="$STATE_FILE" \
  CBP_DISABLE_WARMUP=1 \
  CMUX_CALLS="$CALLS" \
  CMUX_DEAD_SURFACE="surface:6" \
  bash "$SCRIPT" launch 2>/dev/null
new_split_line=$(grep "^new-split" "$CALLS" 2>/dev/null | head -1 || echo "")
# dead surface:6 기준으로 호출되면 안 됨
check_not_contains "TC-3: dead tail → new-split 에 dead surface:6 미사용" "--surface surface:6" "$new_split_line"
# live surface:5 기준으로 호출돼야 함
check_contains "TC-3: dead tail → new-split 이 live surface:5 기준" "--surface surface:5" "$new_split_line"
new_pane_count=$(grep "^new-pane" "$CALLS" 2>/dev/null | wc -l | tr -d ' ')
check "TC-3: dead tail, live exists → new-pane 미호출" "0" "$new_pane_count"

# ----------------------------------------------------------------
# TC-4: state 의 모든 surface 가 dead → new-pane 폴백
STATE_FILE="$TMP/state4.json"
printf 'surface=surface:7|name=cbp-ccc|ts=333|ws=ws:1\nsurface=surface:8|name=cbp-ddd|ts=444|ws=ws:1\n' > "$STATE_FILE"
CALLS="$TMP/calls4.log"
> "$CALLS"

# CMUX_DEAD_SURFACE 는 단일 값이므로, 두 surface 모두 dead 처리하는 mock 사용
cat > "$TMP/cmux-alldead" << 'EOF'
#!/usr/bin/env bash
cmd="$1"; shift
log="${CMUX_CALLS:-/dev/null}"
case "$cmd" in
  read-screen)
    echo "Terminal not found" >&2
    exit 1
    ;;
  new-pane)
    echo "new-pane $*" >> "$log"
    echo "OK surface:100"
    exit 0
    ;;
  new-split)
    echo "new-split $*" >> "$log"
    echo "OK surface:101"
    exit 0
    ;;
  rename-tab|send-key)
    echo "$cmd $*" >> "$log"
    exit 0
    ;;
  *)
    echo "$cmd $*" >> "$log"
    exit 0
    ;;
esac
EOF
chmod +x "$TMP/cmux-alldead"

CMUX_BIN="$TMP/cmux-alldead" \
  CMUX_WORKSPACE_ID="ws:1" \
  CBP_STATE_FILE="$STATE_FILE" \
  CBP_DISABLE_WARMUP=1 \
  CMUX_CALLS="$CALLS" \
  bash "$SCRIPT" launch 2>/dev/null
new_pane_count=$(grep "^new-pane" "$CALLS" 2>/dev/null | wc -l | tr -d ' ')
new_split_count=$(grep "^new-split" "$CALLS" 2>/dev/null | wc -l | tr -d ' ')
check "TC-4: 모든 prev dead → new-pane 폴백" "1" "$new_pane_count"
check "TC-4: 모든 prev dead → new-split 미호출" "0" "$new_split_count"

echo ""
echo "ok: $pass/$total passed"
[ "$fail_count" -gt 0 ] && exit 1
exit 0
