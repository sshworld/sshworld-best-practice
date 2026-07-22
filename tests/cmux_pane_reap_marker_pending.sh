#!/usr/bin/env bash
# cmux_pane_reap_marker_pending.sh — done-marker 가 있으면 input-pending 오탐이
# 자동 회수를 막지 않는지 검증 (composer draft 오버레이 대응 버그 픽스).
#
# 배경: cmux workspace 잔존 composer draft(예: "❯ push it")가 모든 자식 surface 의
# read-screen 캡처에 찍혀 `_send_is_submitted` 기반 input-pending 가드가 상시 오탐.
# done-marker(자식 Stop hook 이 transcript ✅/❌ 판정으로 생성한 턴 종료 권위 신호)가
# 있으면 화면 input 줄보다 그 marker 가 권위 높음 — pending 이어도 회수 진행.
#
# 케이스:
#   1) marker(own-ws 확인) + done + pending → reaped + "pending-input 무시" + 원문 텍스트
#      포함, marker 파일 rm.
#   2) CBP_REAP_MARKER_TRUMPS_PENDING=0 → input-pending — kept, marker 보존 (구 동작 복원).
#   3) marker 없음 + done + pending → input-pending — kept (보수 가드 보존).
#   4) marker + pending 없음(빈 ❯ 줄) → reaped (fast-path 무회귀).
#   5) CBP_REAP_DRY_RUN=1 + 시나리오1 조건 → would reap, kill(close-surface) 미호출.
#   6) 입력줄에 " 와 input-pending substring 포함 → 출력 한 줄 + ^reaped prefix + " 미포함.
#   7) --all 경로 (state 자식 1개, 시나리오1 조건) → 요약 "reaped 1 / kept 0 / pending 0".

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WRAPPER="$REPO/scripts/cmux-pane.sh"

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
  local desc="$1" needle="$2" haystack="$3"
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then
    echo "ok: $desc"
    pass=$((pass + 1))
  else
    echo "FAIL: $desc — expected substring='$needle' not in output='$haystack'" >&2
    fail_count=$((fail_count + 1))
  fi
}

check_not_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then
    echo "FAIL: $desc — unexpected substring='$needle' found in output='$haystack'" >&2
    fail_count=$((fail_count + 1))
  else
    echo "ok: $desc"
    pass=$((pass + 1))
  fi
}

[ -f "$WRAPPER" ] || { echo "FAIL: $WRAPPER 없음" >&2; exit 1; }

WSID="cbp-test-ws-marker-trumps"

# 화면 fixture 를 고정 반환하고 close-workspace/close-surface 호출을 로그에 남기는 mock cmux.
make_mock_cmux() {
  local mockdir="$1" screenfile="$2" logfile="$3"
  cat > "$mockdir/cmux" <<MOCKEOF
#!/usr/bin/env bash
subcmd="\$1"; shift
case "\$subcmd" in
  read-screen)
    cat "$screenfile"
    exit 0
    ;;
  close-workspace|close-surface)
    printf '%s %s\n' "\$subcmd" "\$*" >> "$logfile"
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
MOCKEOF
  chmod +x "$mockdir/cmux"
}

# 자체 workspace 로 확인된 2줄 done-marker(line1=surface ref, line2=$WSID) 를 만든다.
make_marker() {
  local common_dir="$1" marker_path="$2" surface_ref="$3"
  printf '%s\n%s\n' "$surface_ref" "$WSID" > "$marker_path"
}

# ============================================================================
# 케이스 1: marker(own-ws) + done + pending → reaped + annotation, marker rm
# ============================================================================
echo ""
echo "[1] marker(own-ws) + pending → done-marker 가 권위 높음 — reaped + annotation"

T1=$(mktemp -d)
trap 'rm -rf "$T1"' EXIT
( cd "$T1" && git init -q )
MARKER1="$T1/.git/cbp-slice-done-marker-trumps-pending"
make_marker "$T1/.git" "$MARKER1" "surface:9"
LOG1="$T1/close.log"; touch "$LOG1"
SCREEN1="$T1/screen.txt"
cat > "$SCREEN1" <<'EOF'
⏺ ✅ done
❯ push it
EOF
MOCKDIR1="$T1/mock"; mkdir -p "$MOCKDIR1"
make_mock_cmux "$MOCKDIR1" "$SCREEN1" "$LOG1"

out1=$(cd "$T1" && env CMUX_BIN="$MOCKDIR1/cmux" CMUX_WORKSPACE_ID="$WSID" \
  bash "$WRAPPER" reap --pane=surface:9 --idle=1 --timeout=5 2>&1)
ec1=$?
check "case1: exit 0" "0" "$ec1"
check_contains "case1: 출력에 ^reaped" "reaped surface:9" "$out1"
check_contains "case1: annotation pending-input 무시 포함" "pending-input 무시" "$out1"
check_contains "case1: 원문 텍스트 push it 포함" "push it" "$out1"
check_contains "case1: close-surface 호출됨" "close-surface" "$(cat "$LOG1")"
check "case1: marker 파일 rm 됨" "0" "$([ -f "$MARKER1" ] && echo 1 || echo 0)"

# ============================================================================
# 케이스 2: CBP_REAP_MARKER_TRUMPS_PENDING=0 → input-pending — kept, marker 보존
# ============================================================================
echo ""
echo "[2] CBP_REAP_MARKER_TRUMPS_PENDING=0 — 구 동작 복원, kept + marker 보존"

T2=$(mktemp -d)
trap 'rm -rf "$T2"' EXIT
( cd "$T2" && git init -q )
MARKER2="$T2/.git/cbp-slice-done-marker-trumps-pending"
make_marker "$T2/.git" "$MARKER2" "surface:9"
LOG2="$T2/close.log"; touch "$LOG2"
MOCKDIR2="$T2/mock"; mkdir -p "$MOCKDIR2"
make_mock_cmux "$MOCKDIR2" "$SCREEN1" "$LOG2"

out2=$(cd "$T2" && env CMUX_BIN="$MOCKDIR2/cmux" CMUX_WORKSPACE_ID="$WSID" CBP_REAP_MARKER_TRUMPS_PENDING=0 \
  bash "$WRAPPER" reap --pane=surface:9 --idle=1 --timeout=5 2>&1)
ec2=$?
check "case2: exit 0" "0" "$ec2"
check_contains "case2: 출력에 input-pending — kept" "input-pending — kept" "$out2"
check "case2: close 미호출" "" "$(cat "$LOG2")"
check "case2: marker 파일 보존" "1" "$([ -f "$MARKER2" ] && echo 1 || echo 0)"

# ============================================================================
# 케이스 3: marker 없음 + done + pending → input-pending — kept (보수 가드 보존)
# ============================================================================
echo ""
echo "[3] marker 없음 — 화면만으로 done 판정은 신뢰도 낮음, kept 그대로"

T3=$(mktemp -d)
trap 'rm -rf "$T3"' EXIT
( cd "$T3" && git init -q )
LOG3="$T3/close.log"; touch "$LOG3"
MOCKDIR3="$T3/mock"; mkdir -p "$MOCKDIR3"
make_mock_cmux "$MOCKDIR3" "$SCREEN1" "$LOG3"

out3=$(cd "$T3" && env CMUX_BIN="$MOCKDIR3/cmux" CMUX_WORKSPACE_ID="$WSID" \
  bash "$WRAPPER" reap --pane=surface:9 --idle=1 --timeout=5 2>&1)
ec3=$?
check "case3: exit 0" "0" "$ec3"
check_contains "case3: 출력에 input-pending — kept" "input-pending — kept" "$out3"
check "case3: close 미호출" "" "$(cat "$LOG3")"

# ============================================================================
# 케이스 4: marker + pending 없음(빈 ❯ 줄) → reaped (fast-path 무회귀)
# ============================================================================
echo ""
echo "[4] marker + 빈 프롬프트(pending 없음) — reaped (기존 fast-path 무회귀)"

T4=$(mktemp -d)
trap 'rm -rf "$T4"' EXIT
( cd "$T4" && git init -q )
MARKER4="$T4/.git/cbp-slice-done-marker-trumps-pending"
make_marker "$T4/.git" "$MARKER4" "surface:9"
LOG4="$T4/close.log"; touch "$LOG4"
SCREEN4="$T4/screen.txt"
cat > "$SCREEN4" <<'EOF'
⏺ ✅ done
❯
EOF
MOCKDIR4="$T4/mock"; mkdir -p "$MOCKDIR4"
make_mock_cmux "$MOCKDIR4" "$SCREEN4" "$LOG4"

out4=$(cd "$T4" && env CMUX_BIN="$MOCKDIR4/cmux" CMUX_WORKSPACE_ID="$WSID" \
  bash "$WRAPPER" reap --pane=surface:9 --idle=1 --timeout=5 2>&1)
ec4=$?
check "case4: exit 0" "0" "$ec4"
check_contains "case4: 출력에 reaped" "reaped" "$out4"
check_not_contains "case4: annotation 없음(pending 자체가 없었음)" "pending-input 무시" "$out4"
check_contains "case4: close-surface 호출됨" "close-surface" "$(cat "$LOG4")"
check "case4: marker 파일 rm 됨" "0" "$([ -f "$MARKER4" ] && echo 1 || echo 0)"

# ============================================================================
# 케이스 5: CBP_REAP_DRY_RUN=1 + 시나리오1 조건 → would reap, kill 미호출
# ============================================================================
echo ""
echo "[5] dry-run — would reap, kill(close-surface) 미호출, marker 보존"

T5=$(mktemp -d)
trap 'rm -rf "$T5"' EXIT
( cd "$T5" && git init -q )
MARKER5="$T5/.git/cbp-slice-done-marker-trumps-pending"
make_marker "$T5/.git" "$MARKER5" "surface:9"
LOG5="$T5/close.log"; touch "$LOG5"
MOCKDIR5="$T5/mock"; mkdir -p "$MOCKDIR5"
make_mock_cmux "$MOCKDIR5" "$SCREEN1" "$LOG5"

out5=$(cd "$T5" && env CMUX_BIN="$MOCKDIR5/cmux" CMUX_WORKSPACE_ID="$WSID" CBP_REAP_DRY_RUN=1 \
  bash "$WRAPPER" reap --pane=surface:9 --idle=1 --timeout=5 2>&1)
ec5=$?
check "case5: exit 0" "0" "$ec5"
check_contains "case5: 출력에 would reap" "would reap" "$out5"
check "case5: close 미호출" "" "$(cat "$LOG5")"

# ============================================================================
# 케이스 6: 입력줄에 " 와 input-pending substring 포함 → 한 줄 + ^reaped + " 미포함
# ============================================================================
echo ""
echo "[6] 입력줄에 큰따옴표+input-pending substring — sanitize 후 reaped 한 줄"

T6=$(mktemp -d)
trap 'rm -rf "$T6"' EXIT
( cd "$T6" && git init -q )
MARKER6="$T6/.git/cbp-slice-done-marker-trumps-pending"
make_marker "$T6/.git" "$MARKER6" "surface:9"
LOG6="$T6/close.log"; touch "$LOG6"
SCREEN6="$T6/screen.txt"
cat > "$SCREEN6" <<'EOF'
⏺ ✅ done
❯ he said "input-pending" ok
EOF
MOCKDIR6="$T6/mock"; mkdir -p "$MOCKDIR6"
make_mock_cmux "$MOCKDIR6" "$SCREEN6" "$LOG6"

out6=$(cd "$T6" && env CMUX_BIN="$MOCKDIR6/cmux" CMUX_WORKSPACE_ID="$WSID" \
  bash "$WRAPPER" reap --pane=surface:9 --idle=1 --timeout=5 2>&1)
ec6=$?
check "case6: exit 0" "0" "$ec6"
reaped_line_count6=$(printf '%s\n' "$out6" | grep -c '^reaped ')
check "case6: ^reaped prefix 정확히 1줄" "1" "$reaped_line_count6"
reaped_line6=$(printf '%s\n' "$out6" | grep '^reaped ')
check_not_contains "case6: reaped 줄(annotation)에 큰따옴표 미포함(sanitize)" '"' "$reaped_line6"

# ============================================================================
# 케이스 7: --all 경로 (state 자식 1개, 시나리오1 조건) → 요약 reaped 1 / kept 0 / pending 0
# ============================================================================
echo ""
echo "[7] --all — state 자식 1개, marker+pending 조건 → 요약 reaped 1 / kept 0 / pending 0"

T7=$(mktemp -d)
trap 'rm -rf "$T7"' EXIT
( cd "$T7" && git init -q )
MARKER7="$T7/.git/cbp-slice-done-marker-trumps-pending"
make_marker "$T7/.git" "$MARKER7" "surface:9"
LOG7="$T7/close.log"; touch "$LOG7"
MOCKDIR7="$T7/mock"; mkdir -p "$MOCKDIR7"
make_mock_cmux "$MOCKDIR7" "$SCREEN1" "$LOG7"

STATE_FILE7="$T7/children-WS7.json"
OLD_TS=$(( $(date +%s) - 100 ))
cat > "$STATE_FILE7" <<EOF
surface=surface:9|name=cbp-p1|ts=${OLD_TS}|ws=workspace:WS7
EOF

out7=$(cd "$T7" && env CMUX_BIN="$MOCKDIR7/cmux" CMUX_WORKSPACE_ID="$WSID" CBP_STATE_FILE="$STATE_FILE7" \
  bash "$WRAPPER" reap --all --idle=1 --timeout=5 2>&1)
ec7=$?
check "case7: exit 0" "0" "$ec7"
check_contains "case7: 요약 reaped 1 / kept 0 / pending 0" "reaped 1 / kept 0 / pending 0" "$out7"
check "case7: marker 파일 rm 됨" "0" "$([ -f "$MARKER7" ] && echo 1 || echo 0)"

# ============================================================================
echo ""
echo "=== 결과: pass=$pass fail=$fail_count ==="
[ "$fail_count" -eq 0 ]
