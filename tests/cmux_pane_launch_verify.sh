#!/usr/bin/env bash
# cmux_pane_launch_verify.sh — _do_launch_grid 의 PTY 검증 루프 테스트.
#
# 케이스:
#   1) read-screen 즉시 성공 → launch exit0 + stdout 에 surface ref
#   2) K회 후 성공(K < tries) → exit0
#   3) 항상 실패 → exit3 + stderr 에 "terminal" 포함
#   4) CBP_LAUNCH_VERIFY_TRIES=2 로 빨리 실패 확인
#   5) CBP_DISABLE_WARMUP=1 → 검증 스킵 exit0
#
# CMUX_BIN mock 은 tmpdir 에 생성. 카운터 파일로 N회째부터 성공 시나리오 구현.

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

check_re() {
  local desc="$1" pattern="$2" haystack="$3"
  if printf '%s' "$haystack" | grep -qE -- "$pattern"; then
    echo "ok: $desc"
    pass=$((pass + 1))
  else
    echo "FAIL: $desc — pattern='$pattern' not matched in='$haystack'" >&2
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

# ---- helpers ---------------------------------------------------------------

make_tmpdir() {
  local d
  d=$(mktemp -d)
  echo "$d"
}

# Mock cmux 를 생성한다.
# read-screen 동작은 카운터 파일($counter_file) 기반:
#   호출 횟수 < $succeed_after_n  → "Surface is not a terminal" + exit 1
#   호출 횟수 >= $succeed_after_n → 빈 stdout + exit 0 (terminal 상태)
# $succeed_after_n=999 이면 항상 실패
make_mock_cmux() {
  local mockdir="$1"
  local succeed_after_n="${2:-0}"   # 0=즉시 성공, N=N회 이후 성공, 999=항상 실패
  local counter_file="$mockdir/read_screen_count"
  printf '0' > "$counter_file"

  cat > "$mockdir/cmux" <<MOCKEOF
#!/usr/bin/env bash
case "\$1" in
  new-pane)
    echo "OK surface:99"
    ;;
  new-split)
    echo "OK surface:99"
    ;;
  send-key)
    # 무시
    ;;
  rename-tab)
    # 무시
    ;;
  read-screen)
    count=\$(cat "$counter_file" 2>/dev/null || echo 0)
    count=\$((count + 1))
    printf '%s' "\$count" > "$counter_file"
    if [ "\$count" -ge "$succeed_after_n" ] && [ "$succeed_after_n" -ne 999 ]; then
      # 성공 (terminal ready)
      exit 0
    else
      echo "Surface is not a terminal" >&2
      exit 1
    fi
    ;;
  *)
    ;;
esac
exit 0
MOCKEOF
  chmod +x "$mockdir/cmux"
  echo "$mockdir/cmux"
}

# make_mock_cmux 와 동일 동작 + 그 외 서브커맨드(close-surface 등)를 CMUX_CALLS_LOG 에 기록.
# 좀비 케이스(케이스 6) — trap cleanup 이 close-surface 를 호출하는지 검증하는 데 사용.
make_mock_cmux_logging() {
  local mockdir="$1"
  local succeed_after_n="${2:-0}"
  local counter_file="$mockdir/read_screen_count"
  printf '0' > "$counter_file"

  cat > "$mockdir/cmux" <<MOCKEOF
#!/usr/bin/env bash
cmd="\$1"; shift
case "\$cmd" in
  new-pane)
    echo "OK surface:99"
    ;;
  new-split)
    echo "OK surface:99"
    ;;
  read-screen)
    count=\$(cat "$counter_file" 2>/dev/null || echo 0)
    count=\$((count + 1))
    printf '%s' "\$count" > "$counter_file"
    if [ "\$count" -ge "$succeed_after_n" ] && [ "$succeed_after_n" -ne 999 ]; then
      exit 0
    else
      echo "Surface is not a terminal" >&2
      exit 1
    fi
    ;;
  *)
    echo "\$cmd \$*" >> "\${CMUX_CALLS_LOG:-/dev/null}"
    ;;
esac
exit 0
MOCKEOF
  chmod +x "$mockdir/cmux"
  echo "$mockdir/cmux"
}

# _do_launch_grid 를 직접 호출 — launch 서브커맨드로 호출
run_launch() {
  local cmux_bin="$1"
  local state_file="$2"
  shift 2
  # 나머지 인자는 env 오버라이드용 (key=val 형식)
  env \
    CMUX_BIN="$cmux_bin" \
    CMUX_WORKSPACE_ID="workspace:test-parent" \
    CBP_STATE_FILE="$state_file" \
    CBP_DISABLE_LAUNCH_LOCK=1 \
    CBP_WARMUP_SLEEP=0 \
    "$@" \
    bash "$WRAPPER" launch
}
# 주: 이 테스트는 _do_launch_grid 의 PTY 검증 루프만 검증 → cmd 없이 launch 호출.
# (launch <cmd> 의 cmd 전달=do_send 는 tests/unit/cmux-pane-launch-cmd.test.sh 가 담당.
#  cmd 를 주면 do_send confirm 루프가 read-screen 을 추가 호출해 검증 카운트가 오염됨.)

# ============================================================================
# 케이스 1: read-screen 즉시 성공 (succeed_after_n=1 → 첫 번째 호출부터 성공)
# ============================================================================
echo ""
echo "[1] read-screen 즉시 성공 → exit0 + stdout surface ref"

tmpdir1=$(make_tmpdir)
trap 'rm -rf "$tmpdir1"' EXIT
state1="$tmpdir1/state.json"

mock1=$(make_mock_cmux "$tmpdir1" 1)

stdout1=""
stderr1=""
exit1=0
stdout1=$(run_launch "$mock1" "$state1" 2>"$tmpdir1/err.txt") || exit1=$?
stderr1=$(cat "$tmpdir1/err.txt")

check "case1: exit code 0" "0" "$exit1"
check_re "case1: stdout 에 surface ref" "surface:" "$stdout1"

# ============================================================================
# 케이스 2: K=3회 후 성공 (succeed_after_n=3, tries=5)
# ============================================================================
echo ""
echo "[2] K=3회 후 성공 → exit0"

tmpdir2=$(make_tmpdir)
trap 'rm -rf "$tmpdir2"' EXIT
state2="$tmpdir2/state.json"

mock2=$(make_mock_cmux "$tmpdir2" 3)

stdout2=""
exit2=0
stdout2=$(run_launch "$mock2" "$state2" \
  CBP_LAUNCH_VERIFY_TRIES=5 2>"$tmpdir2/err.txt") || exit2=$?

check "case2: exit code 0" "0" "$exit2"
check_re "case2: stdout 에 surface ref" "surface:" "$stdout2"

# ============================================================================
# 케이스 3: 항상 실패 → exit3 + stderr 에 "terminal" 포함
# ============================================================================
echo ""
echo "[3] 항상 실패 → exit3 + stderr 'terminal' 포함"

tmpdir3=$(make_tmpdir)
trap 'rm -rf "$tmpdir3"' EXIT
state3="$tmpdir3/state.json"

mock3=$(make_mock_cmux "$tmpdir3" 999)

stdout3=""
stderr3=""
exit3=0
stdout3=$(run_launch "$mock3" "$state3" \
  CBP_LAUNCH_VERIFY_TRIES=3 2>"$tmpdir3/err.txt") || exit3=$?
stderr3=$(cat "$tmpdir3/err.txt")

check "case3: exit code 3" "3" "$exit3"
check_re "case3: stderr 에 'terminal' 포함" "terminal" "$stderr3"

# ============================================================================
# 케이스 4: CBP_LAUNCH_VERIFY_TRIES=2 로 빨리 실패 확인
# ============================================================================
echo ""
echo "[4] CBP_LAUNCH_VERIFY_TRIES=2 → 2회 시도 후 exit3"

tmpdir4=$(make_tmpdir)
trap 'rm -rf "$tmpdir4"' EXIT
state4="$tmpdir4/state.json"
counter4="$tmpdir4/read_screen_count"

mock4=$(make_mock_cmux "$tmpdir4" 999)

exit4=0
run_launch "$mock4" "$state4" \
  CBP_LAUNCH_VERIFY_TRIES=2 >"$tmpdir4/out.txt" 2>"$tmpdir4/err.txt" || exit4=$?

# 카운터 확인: read-screen 이 정확히 2회 호출됐는지
read_count4=$(cat "$tmpdir4/read_screen_count" 2>/dev/null || echo "0")

check "case4: exit code 3" "3" "$exit4"
check "case4: read-screen 호출 횟수=2" "2" "$read_count4"

# ============================================================================
# 케이스 5: CBP_DISABLE_WARMUP=1 → 검증 스킵, exit0 (read-screen 호출 안 함)
# ============================================================================
echo ""
echo "[5] CBP_DISABLE_WARMUP=1 → 검증 스킵 exit0"

tmpdir5=$(make_tmpdir)
trap 'rm -rf "$tmpdir5"' EXIT
state5="$tmpdir5/state.json"
counter5="$tmpdir5/read_screen_count"

# 항상 실패하는 mock — 그러나 DISABLE_WARMUP=1 이면 read-screen 아예 안 불러야 함
mock5=$(make_mock_cmux "$tmpdir5" 999)

stdout5=""
exit5=0
stdout5=$(run_launch "$mock5" "$state5" \
  CBP_DISABLE_WARMUP=1 2>"$tmpdir5/err.txt") || exit5=$?

read_count5=$(cat "$tmpdir5/read_screen_count" 2>/dev/null || echo "0")

check "case5: exit code 0" "0" "$exit5"
check_re "case5: stdout 에 surface ref" "surface:" "$stdout5"
check "case5: read-screen 호출 없음 (count=0)" "0" "$read_count5"

# ============================================================================
# 케이스 6: 좀비 surface 방지 — verify 전실패(항상 rc1) → exit3 이면서
#           trap cleanup 이 close-surface 호출 + state file 에 surface 무잔존
# ============================================================================
echo ""
echo "[6] verify 전실패 → 좀비 방지: close-surface 호출 + state 무잔존"

tmpdir6=$(make_tmpdir)
trap 'rm -rf "$tmpdir6"' EXIT
state6="$tmpdir6/state.json"
calls6="$tmpdir6/calls.log"
: > "$calls6"

mock6=$(make_mock_cmux_logging "$tmpdir6" 999)

exit6=0
run_launch "$mock6" "$state6" \
  CBP_LAUNCH_VERIFY_TRIES=2 CMUX_CALLS_LOG="$calls6" \
  >"$tmpdir6/out.txt" 2>"$tmpdir6/err.txt" || exit6=$?

close_called6=$(grep -c "close-surface --surface surface:99" "$calls6" 2>/dev/null || echo 0)
state_has6=$(grep -c 'surface=surface:99|' "$state6" 2>/dev/null || true)

check "case6: exit code 3" "3" "$exit6"
check "case6: trap cleanup → close-surface 호출" "1" "$close_called6"
check "case6: trap cleanup → state file 에 surface:99 무잔존" "0" "$state_has6"

# ============================================================================
# 케이스 7: CBP_LAUNCH_DEBUG=1 → stderr 진단 marker 포함, off 시 무변화
# ============================================================================
echo ""
echo "[7] CBP_LAUNCH_DEBUG — on 시 진단 marker, off 시 완전 무변화"

tmpdir7=$(make_tmpdir)
trap 'rm -rf "$tmpdir7"' EXIT
state7a="$tmpdir7/state-off.json"
state7b="$tmpdir7/state-on.json"

# debug off (기본) — 진단 marker 없어야 함
mock7a=$(make_mock_cmux "$tmpdir7" 999)
exit7a=0
run_launch "$mock7a" "$state7a" \
  CBP_LAUNCH_VERIFY_TRIES=1 >"$tmpdir7/out-off.txt" 2>"$tmpdir7/err-off.txt" || exit7a=$?
stderr7a=$(cat "$tmpdir7/err-off.txt")
check_not_contains "case7: debug off → stderr 에 CBP_LAUNCH_DEBUG marker 없음" "CBP_LAUNCH_DEBUG" "$stderr7a"

# debug on — 진단 marker(생성 경로 + read-screen dump) 포함
mock7b=$(make_mock_cmux "$tmpdir7" 999)
exit7b=0
run_launch "$mock7b" "$state7b" \
  CBP_LAUNCH_VERIFY_TRIES=1 CBP_LAUNCH_DEBUG=1 \
  >"$tmpdir7/out-on.txt" 2>"$tmpdir7/err-on.txt" || exit7b=$?
stderr7b=$(cat "$tmpdir7/err-on.txt")
check_contains "case7: debug on → stderr 에 CBP_LAUNCH_DEBUG marker 포함" "CBP_LAUNCH_DEBUG" "$stderr7b"
check_contains "case7: debug on → 생성 경로(creation path) marker 포함" "creation path" "$stderr7b"
check_contains "case7: debug on → verify read-screen dump 포함" "read-screen" "$stderr7b"

# ============================================================================
# 결과
# ============================================================================
echo ""
total=$((pass + fail_count))
echo "passed: $pass / $total"
if [ "$fail_count" -gt 0 ]; then
  echo "❌ FAIL ($fail_count failures)"
  exit 1
fi
echo "✅"
