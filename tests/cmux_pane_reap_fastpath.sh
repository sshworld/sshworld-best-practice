#!/usr/bin/env bash
# cmux_pane_reap_fastpath.sh — reap 이 done-marker 파일(S2 생산) 을 fast-path 신호로 써서
# wait-idle 을 스킵하는지 검증. 계약: <git-common-dir>/cbp-slice-done-<sanitized branch>
# 파일의 첫 줄이 대상 surface ref 와 일치하면 wait-idle 생략 후 바로 capture 로 직행.
#
# 케이스:
#   1) fast-path 즉시 회수: marker 매치 + 정적 done 화면 → reaped, read-screen 호출 ≤2, marker 삭제.
#   2) false-positive 가드: marker 없음 + 화면 매 호출 변화(중간 ✅ bullet 포함) → kill 안 됨.
#   3) 다른 surface marker: marker 내용 불일치 → fast-path 미적용 (wait-idle 경로, 호출 >2).
#   4) --all grace 우회: 신생 자식(ts=now) + marker 매치 → grace 건너뛰고 probe → reaped.
#   5) input-pending 시 marker 보존: 완료 마커 + 미제출 텍스트 → input-pending kept, marker 존속.
#   6) 토글 off (CBP_REAP_FAST_CHECK=0): 케이스1 조건이어도 wait-idle 경로 (호출 ≥3).

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

check_le() {
  local desc="$1" max="$2" actual="$3"
  if [ "$actual" -le "$max" ] 2>/dev/null; then
    echo "ok: $desc (actual=$actual <= $max)"
    pass=$((pass + 1))
  else
    echo "FAIL: $desc — expected <= $max, got '$actual'" >&2
    fail_count=$((fail_count + 1))
  fi
}

check_gt() {
  local desc="$1" min="$2" actual="$3"
  if [ "$actual" -gt "$min" ] 2>/dev/null; then
    echo "ok: $desc (actual=$actual > $min)"
    pass=$((pass + 1))
  else
    echo "FAIL: $desc — expected > $min, got '$actual'" >&2
    fail_count=$((fail_count + 1))
  fi
}

check_ge() {
  local desc="$1" min="$2" actual="$3"
  if [ "$actual" -ge "$min" ] 2>/dev/null; then
    echo "ok: $desc (actual=$actual >= $min)"
    pass=$((pass + 1))
  else
    echo "FAIL: $desc — expected >= $min, got '$actual'" >&2
    fail_count=$((fail_count + 1))
  fi
}

[ -f "$WRAPPER" ] || { echo "FAIL: $WRAPPER 없음" >&2; exit 1; }

# 정적 화면 + read-screen 호출 카운터 mock. 인자: mockdir, screenfile, logfile, counterfile
make_mock_cmux_static() {
  local mockdir="$1" screenfile="$2" logfile="$3" counterfile="$4"
  printf '0' > "$counterfile"
  cat > "$mockdir/cmux" <<MOCKEOF
#!/usr/bin/env bash
subcmd="\$1"; shift
case "\$subcmd" in
  read-screen)
    c=\$(cat "$counterfile" 2>/dev/null || echo 0)
    c=\$((c + 1))
    printf '%s' "\$c" > "$counterfile"
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

# 호출마다 다른 화면(3종 순환) 반환하는 mock. 인자: mockdir, screensdir(s1..s3.txt), logfile, counterfile
make_mock_cmux_cycling() {
  local mockdir="$1" screensdir="$2" logfile="$3" counterfile="$4"
  printf '0' > "$counterfile"
  cat > "$mockdir/cmux" <<MOCKEOF
#!/usr/bin/env bash
subcmd="\$1"; shift
case "\$subcmd" in
  read-screen)
    c=\$(cat "$counterfile" 2>/dev/null || echo 0)
    c=\$((c + 1))
    printf '%s' "\$c" > "$counterfile"
    idx=\$(( (c - 1) % 3 + 1 ))
    cat "$screensdir/s\${idx}.txt"
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

# --pane/--surface 인자별 화면 파일을 스캔하는 --all 용 mock. 인자: mockdir, screensdir, logfile, callslog
make_mock_cmux_multi() {
  local mockdir="$1" screensdir="$2" logfile="$3" callslog="$4"
  cat > "$mockdir/cmux" <<MOCKEOF
#!/usr/bin/env bash
subcmd="\$1"; shift
if [ "\$subcmd" = "read-screen" ]; then
  echo "read-screen \$*" >> "$callslog"
  surface=""
  while [ \$# -gt 0 ]; do
    case "\$1" in
      --surface) surface="\$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  sanitized=\$(printf '%s' "\$surface" | tr ':' '_')
  cat "$screensdir/\${sanitized}.screen" 2>/dev/null || true
  exit 0
elif [ "\$subcmd" = "close-workspace" ] || [ "\$subcmd" = "close-surface" ]; then
  printf '%s %s\n' "\$subcmd" "\$*" >> "$logfile"
  exit 0
else
  exit 0
fi
MOCKEOF
  chmod +x "$mockdir/cmux"
}

# ============================================================================
# [1] fast-path 즉시 회수: marker 매치 + 정적 done 화면 → reaped, read-screen 호출 ≤2, marker 삭제
# ============================================================================
echo ""
echo "[1] fast-path 즉시 회수 — marker 매치 → wait-idle 스킵, reaped, 호출 ≤2, marker 삭제"

T1=$(mktemp -d)
trap 'rm -rf "$T1"' EXIT
( cd "$T1" && git init -q )
MARKER1="$T1/.git/cbp-slice-done-feature_reap-fastpath"
printf 'surface:7\n' > "$MARKER1"
LOG1="$T1/close.log"; touch "$LOG1"
COUNTER1="$T1/rs_count"
SCREEN1="$T1/screen.txt"
printf '⏺ ✅ done\n' > "$SCREEN1"
MOCKDIR1="$T1/mock"; mkdir -p "$MOCKDIR1"
make_mock_cmux_static "$MOCKDIR1" "$SCREEN1" "$LOG1" "$COUNTER1"
STATE1="$T1/state.json"

out1=$(cd "$T1" && env CMUX_BIN="$MOCKDIR1/cmux" CBP_STATE_FILE="$STATE1" \
  bash "$WRAPPER" reap --pane=surface:7 --idle=1 --timeout=5 2>&1)
ec1=$?
check "case1: exit 0" "0" "$ec1"
check_contains "case1: 출력에 reaped" "reaped" "$out1"
check_le "case1: read-screen 호출 ≤2" 2 "$(cat "$COUNTER1")"
check "case1: marker 파일 삭제됨" "0" "$([ -f "$MARKER1" ] && echo 1 || echo 0)"

# ============================================================================
# [2] false-positive 가드: marker 없음 + 화면 매 호출 변화 → kill 안 됨
# ============================================================================
echo ""
echo "[2] false-positive 가드 — marker 없음 + 변화하는 화면 → kill 안 됨"

T2=$(mktemp -d)
trap 'rm -rf "$T2"' EXIT
( cd "$T2" && git init -q )
LOG2="$T2/close.log"; touch "$LOG2"
COUNTER2="$T2/rs_count"
SCREENS2="$T2/screens"; mkdir -p "$SCREENS2"
printf '작업 중...\n' > "$SCREENS2/s1.txt"
printf '⏺ ✅ 테스트 통과 (중간 단계)\nstill working\n' > "$SCREENS2/s2.txt"
printf '작업 계속...\n' > "$SCREENS2/s3.txt"
MOCKDIR2="$T2/mock"; mkdir -p "$MOCKDIR2"
make_mock_cmux_cycling "$MOCKDIR2" "$SCREENS2" "$LOG2" "$COUNTER2"
STATE2="$T2/state.json"

out2=$(cd "$T2" && env CMUX_BIN="$MOCKDIR2/cmux" CBP_STATE_FILE="$STATE2" \
  bash "$WRAPPER" reap --pane=surface:8 --idle=1 --timeout=3 2>&1)
check_not_contains "case2: 출력에 reaped 없음" "reaped" "$out2"
check "case2: close-surface 미호출 (log empty)" "" "$(cat "$LOG2")"

# ============================================================================
# [3] 다른 surface marker: marker 내용 불일치 → fast-path 미적용 (wait-idle 경로, 호출 >2)
# ============================================================================
echo ""
echo "[3] 다른 surface marker — fast-path 미적용, wait-idle 경로로 회수(호출 >2)"

T3=$(mktemp -d)
trap 'rm -rf "$T3"' EXIT
( cd "$T3" && git init -q )
MARKER3="$T3/.git/cbp-slice-done-feature_other"
printf 'surface:99\n' > "$MARKER3"
LOG3="$T3/close.log"; touch "$LOG3"
COUNTER3="$T3/rs_count"
SCREEN3="$T3/screen.txt"
printf '⏺ ✅ done\n' > "$SCREEN3"
MOCKDIR3="$T3/mock"; mkdir -p "$MOCKDIR3"
make_mock_cmux_static "$MOCKDIR3" "$SCREEN3" "$LOG3" "$COUNTER3"
STATE3="$T3/state.json"

out3=$(cd "$T3" && env CMUX_BIN="$MOCKDIR3/cmux" CBP_STATE_FILE="$STATE3" \
  bash "$WRAPPER" reap --pane=surface:7 --idle=1 --timeout=5 2>&1)
check_contains "case3: 출력에 reaped (wait-idle 경로로도 결국 회수)" "reaped" "$out3"
check_gt "case3: read-screen 호출 >2 (wait-idle 거침)" 2 "$(cat "$COUNTER3")"
check "case3: 다른 surface marker 는 그대로 보존" "1" "$([ -f "$MARKER3" ] && echo 1 || echo 0)"

# ============================================================================
# [4] --all grace 우회: 신생 자식(ts=now) + marker 매치 → grace 건너뛰고 probe → reaped
# ============================================================================
echo ""
echo "[4] --all grace 우회 — 신생 자식 + marker 매치 → probe 수행 후 reaped"

T4=$(mktemp -d)
trap 'rm -rf "$T4"' EXIT
( cd "$T4" && git init -q )
MARKER4="$T4/.git/cbp-slice-done-feature_reap-fastpath"
printf 'surface:55\n' > "$MARKER4"
LOG4="$T4/close.log"; touch "$LOG4"
CALLS4="$T4/calls.log"; touch "$CALLS4"
SCREENS4="$T4/screens"; mkdir -p "$SCREENS4"
printf '⏺ ✅ done\n' > "$SCREENS4/surface_55.screen"
MOCKDIR4="$T4/mock"; mkdir -p "$MOCKDIR4"
make_mock_cmux_multi "$MOCKDIR4" "$SCREENS4" "$LOG4" "$CALLS4"
STATE4="$T4/state.json"
NOW_TS4=$(date +%s)
printf 'surface=surface:55|name=cbp-new|ts=%s|ws=ws1\n' "$NOW_TS4" > "$STATE4"

out4=$(cd "$T4" && env CMUX_BIN="$MOCKDIR4/cmux" CBP_STATE_FILE="$STATE4" \
  bash "$WRAPPER" reap --all --idle=1 --timeout=5 2>&1)
check_not_contains "case4: 'grace — kept' 미출력 (marker 로 grace 우회)" "grace — kept" "$out4"
check_contains "case4: 출력에 reaped" "reaped" "$out4"
check_contains "case4: read-screen 이 surface:55 대상으로 호출됨 (probe 수행)" "surface:55" "$(cat "$CALLS4")"
check "case4: marker 파일 삭제됨" "0" "$([ -f "$MARKER4" ] && echo 1 || echo 0)"

# ============================================================================
# [5] input-pending 시 marker 보존: 완료 마커 + 미제출 텍스트 → input-pending kept, marker 존속
# ============================================================================
echo ""
echo "[5] input-pending — marker 있어도 미제출 텍스트면 kept, marker 보존"

T5=$(mktemp -d)
trap 'rm -rf "$T5"' EXIT
( cd "$T5" && git init -q )
MARKER5="$T5/.git/cbp-slice-done-feature_reap-fastpath"
printf 'surface:7\n' > "$MARKER5"
LOG5="$T5/close.log"; touch "$LOG5"
COUNTER5="$T5/rs_count"
SCREEN5="$T5/screen.txt"
cat > "$SCREEN5" <<'EOF'
⏺ ✅ done
❯ leftover instruction text
EOF
MOCKDIR5="$T5/mock"; mkdir -p "$MOCKDIR5"
make_mock_cmux_static "$MOCKDIR5" "$SCREEN5" "$LOG5" "$COUNTER5"
STATE5="$T5/state.json"

out5=$(cd "$T5" && env CMUX_BIN="$MOCKDIR5/cmux" CBP_STATE_FILE="$STATE5" \
  bash "$WRAPPER" reap --pane=surface:7 --idle=1 --timeout=5 2>&1)
check_contains "case5: 출력에 input-pending — kept" "input-pending — kept" "$out5"
check "case5: close-surface 미호출" "" "$(cat "$LOG5")"
check "case5: marker 파일 존속" "1" "$([ -f "$MARKER5" ] && echo 1 || echo 0)"

# ============================================================================
# [6] 토글 off (CBP_REAP_FAST_CHECK=0): 케이스1 조건이어도 wait-idle 경로 (호출 ≥3)
# ============================================================================
echo ""
echo "[6] CBP_REAP_FAST_CHECK=0 — fast-path 비활성, wait-idle 경로 (호출 ≥3)"

T6=$(mktemp -d)
trap 'rm -rf "$T6"' EXIT
( cd "$T6" && git init -q )
MARKER6="$T6/.git/cbp-slice-done-feature_reap-fastpath"
printf 'surface:7\n' > "$MARKER6"
LOG6="$T6/close.log"; touch "$LOG6"
COUNTER6="$T6/rs_count"
SCREEN6="$T6/screen.txt"
printf '⏺ ✅ done\n' > "$SCREEN6"
MOCKDIR6="$T6/mock"; mkdir -p "$MOCKDIR6"
make_mock_cmux_static "$MOCKDIR6" "$SCREEN6" "$LOG6" "$COUNTER6"
STATE6="$T6/state.json"

out6=$(cd "$T6" && env CMUX_BIN="$MOCKDIR6/cmux" CBP_STATE_FILE="$STATE6" CBP_REAP_FAST_CHECK=0 \
  bash "$WRAPPER" reap --pane=surface:7 --idle=1 --timeout=5 2>&1)
check_contains "case6: 출력에 reaped (결국 회수)" "reaped" "$out6"
check_ge "case6: read-screen 호출 ≥3 (wait-idle 경로)" 3 "$(cat "$COUNTER6")"
check "case6: marker 파일 삭제됨 (reaped 시 rm 은 토글 무관)" "0" "$([ -f "$MARKER6" ] && echo 1 || echo 0)"

# ============================================================================
echo ""
echo "=== 결과: pass=$pass fail=$fail_count ==="
[ "$fail_count" -eq 0 ]
