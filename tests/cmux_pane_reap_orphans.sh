#!/usr/bin/env bash
# cmux_pane_reap_orphans.sh — do_reap_orphans 서브커맨드 TDD 테스트.
#
# 케이스:
#   1) dead surface → close-surface 호출됨 (로그에 --workspace <WS> 포함) + 해당 state 라인 제거
#   2) alive surface (surface:ALIVE) → close 미호출 + state 유지
#   3) CMUX_SURFACE_ID=특정 ref → 그 ref dead 여도 제외 (close 미호출)
#   4) 모든 라인 제거된 state file → 파일 rm
#   5) CBP_REAP_ORPHANS_DRY_RUN=1 → close 미호출 + "would reap" 출력 + state 유지
#   6) state dir 없음/빈 → exit 0 무동작
#   7) 여러 state file (multi-workspace) → 각각 스캔, dead 만 정리

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

check_file_exists() {
  local desc="$1" path="$2"
  if [ -f "$path" ]; then
    echo "ok: $desc"
    pass=$((pass + 1))
  else
    echo "FAIL: $desc — file not found: $path" >&2
    fail_count=$((fail_count + 1))
  fi
}

check_file_absent() {
  local desc="$1" path="$2"
  if [ ! -f "$path" ]; then
    echo "ok: $desc"
    pass=$((pass + 1))
  else
    echo "FAIL: $desc — file should be absent but exists: $path" >&2
    fail_count=$((fail_count + 1))
  fi
}

check_line_in_file() {
  local desc="$1" needle="$2" file="$3"
  if grep -qF "$needle" "$file" 2>/dev/null; then
    echo "ok: $desc"
    pass=$((pass + 1))
  else
    echo "FAIL: $desc — '$needle' not found in $file" >&2
    fail_count=$((fail_count + 1))
  fi
}

check_line_absent_in_file() {
  local desc="$1" needle="$2" file="$3"
  if grep -qF "$needle" "$file" 2>/dev/null; then
    echo "FAIL: $desc — '$needle' should be absent but found in $file" >&2
    fail_count=$((fail_count + 1))
  else
    echo "ok: $desc"
    pass=$((pass + 1))
  fi
}

[ -f "$WRAPPER" ] || { echo "FAIL: $WRAPPER 없음" >&2; exit 1; }

# ── mock cmux 생성 헬퍼 ──────────────────────────────────────────────────────
# alive_surface: 이 ref 에 대해 read-screen → exit 0 (alive)
# 그 외 모든 surface → read-screen exit 1 (dead)
# close-surface 호출 인자는 로그파일($logfile)에 기록.
make_mock_cmux() {
  local mockdir="$1"
  local alive_surface="$2"    # "surface:ALIVE" 등; 빈 문자열이면 모두 dead
  local logfile="$3"

  cat > "$mockdir/cmux" <<MOCKEOF
#!/usr/bin/env bash
subcmd="\$1"; shift

case "\$subcmd" in
  read-screen)
    # --surface <ref> 를 파싱
    surface_ref=""
    while [ \$# -gt 0 ]; do
      case "\$1" in
        --surface) surface_ref="\$2"; shift 2 ;;
        --surface=*) surface_ref="\${1#*=}"; shift ;;
        *) shift ;;
      esac
    done
    if [ "\$surface_ref" = "$alive_surface" ] && [ -n "$alive_surface" ]; then
      exit 0
    else
      exit 1
    fi
    ;;
  close-surface)
    # 호출 인자를 로그에 기록
    printf 'close-surface %s\n' "\$*" >> "$logfile"
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
MOCKEOF
  chmod +x "$mockdir/cmux"
}

# ── ws-aware mock: read-screen 가 --workspace 인자가 있을 때만 alive 판정 ──────
# 버그 재현용. --workspace 없이 호출 시 exit 1 (dead 오판).
# alive_surface: 이 surface ref + --workspace 조합이면 exit 0. --workspace 없으면 exit 1.
make_mock_cmux_ws_aware() {
  local mockdir="$1"
  local alive_surface="$2"    # --workspace 도 있어야 alive 판정
  local logfile="$3"

  cat > "$mockdir/cmux" <<MOCKEOF
#!/usr/bin/env bash
subcmd="\$1"; shift

case "\$subcmd" in
  read-screen)
    surface_ref=""
    has_workspace=0
    while [ \$# -gt 0 ]; do
      case "\$1" in
        --surface) surface_ref="\$2"; shift 2 ;;
        --surface=*) surface_ref="\${1#*=}"; shift ;;
        --workspace|--workspace=*) has_workspace=1; shift ;;
        *) shift ;;
      esac
    done
    # alive 판정: surface 일치 AND --workspace 인자 있음
    if [ "\$surface_ref" = "$alive_surface" ] && [ "\$has_workspace" = "1" ] && [ -n "$alive_surface" ]; then
      exit 0
    else
      exit 1
    fi
    ;;
  close-surface)
    printf 'close-surface %s\n' "\$*" >> "$logfile"
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
MOCKEOF
  chmod +x "$mockdir/cmux"
}

run_reap_orphans() {
  # 가변 env 인자들 (key=value 형식) + 고정 env 조합
  env \
    CMUX_BIN="$MOCK_CMUX" \
    CBP_STATE_DIR="$STATE_DIR" \
    "$@" \
    bash "$WRAPPER" reap-orphans
}

# ============================================================================
# 케이스 1: dead surface → close-surface 호출됨 + 해당 state 라인 제거
# ============================================================================
echo ""
echo "[1] dead surface → close-surface 호출 + state 라인 제거"

TMPDIR1=$(mktemp -d)
trap 'rm -rf "$TMPDIR1"' EXIT

STATE_DIR="$TMPDIR1/state"
mkdir -p "$STATE_DIR"
LOG="$TMPDIR1/close.log"
touch "$LOG"
MOCK_DIR="$TMPDIR1/mock"
mkdir -p "$MOCK_DIR"

make_mock_cmux "$MOCK_DIR" "surface:ALIVE" "$LOG"
MOCK_CMUX="$MOCK_DIR/cmux"

# state file: workspace WS1 에 dead surface:DEAD1 하나
STATE_FILE1="$STATE_DIR/children-WS1.json"
cat > "$STATE_FILE1" <<'EOF'
surface=surface:DEAD1|name=cbp-aaa|ts=1000|ws=workspace:WS1
EOF

out1=$(run_reap_orphans 2>&1)
ec1=$?

check "case1: exit 0" "0" "$ec1"
# close-surface が呼ばれたか
check_contains "case1: close-surface ログ に --surface surface:DEAD1" "--surface surface:DEAD1" "$(cat "$LOG")"
check_contains "case1: close-surface ログ に --workspace workspace:WS1" "--workspace workspace:WS1" "$(cat "$LOG")"
# state file から該当ラインが消えているか (empty or no line with DEAD1)
check_line_absent_in_file "case1: state に surface:DEAD1 ライン なし" "surface:DEAD1" "$STATE_FILE1"

# ============================================================================
# 케이스 2: alive surface → close 미호출 + state 유지
# ============================================================================
echo ""
echo "[2] alive surface → close 미호출 + state 유지"

TMPDIR2=$(mktemp -d)
trap 'rm -rf "$TMPDIR2"' EXIT

STATE_DIR="$TMPDIR2/state"
mkdir -p "$STATE_DIR"
LOG2="$TMPDIR2/close.log"
touch "$LOG2"
MOCK_DIR2="$TMPDIR2/mock"
mkdir -p "$MOCK_DIR2"

make_mock_cmux "$MOCK_DIR2" "surface:ALIVE" "$LOG2"
MOCK_CMUX="$MOCK_DIR2/cmux"

STATE_FILE2="$STATE_DIR/children-WS2.json"
cat > "$STATE_FILE2" <<'EOF'
surface=surface:ALIVE|name=cbp-bbb|ts=1000|ws=workspace:WS2
EOF

run_reap_orphans 2>&1
ec2=$?

check "case2: exit 0" "0" "$ec2"
# close-surface が呼ばれていないか (logfile empty)
log2_content=$(cat "$LOG2")
check "case2: close-surface 미호출 (log empty)" "" "$log2_content"
# state ライン が残っているか
check_line_in_file "case2: state に surface:ALIVE ライン あり" "surface:ALIVE" "$STATE_FILE2"

# ============================================================================
# 케이스 3: CMUX_SURFACE_ID=surface:SELF → 그 ref dead 여도 제외
# ============================================================================
echo ""
echo "[3] CMUX_SURFACE_ID=surface:SELF → self skip (close 미호출)"

TMPDIR3=$(mktemp -d)
trap 'rm -rf "$TMPDIR3"' EXIT

STATE_DIR="$TMPDIR3/state"
mkdir -p "$STATE_DIR"
LOG3="$TMPDIR3/close.log"
touch "$LOG3"
MOCK_DIR3="$TMPDIR3/mock"
mkdir -p "$MOCK_DIR3"

# surface:SELF は dead (alive_surface を空にして全部 dead にする)
make_mock_cmux "$MOCK_DIR3" "" "$LOG3"
MOCK_CMUX="$MOCK_DIR3/cmux"

STATE_FILE3="$STATE_DIR/children-WS3.json"
cat > "$STATE_FILE3" <<'EOF'
surface=surface:SELF|name=cbp-self|ts=1000|ws=workspace:WS3
EOF

run_reap_orphans CMUX_SURFACE_ID="surface:SELF" 2>&1
ec3=$?

check "case3: exit 0" "0" "$ec3"
log3_content=$(cat "$LOG3")
check "case3: close-surface 미호출 (self skip)" "" "$log3_content"
# state ライン も残っているか
check_line_in_file "case3: self ライン state に残存" "surface:SELF" "$STATE_FILE3"

# ============================================================================
# 케이스 4: 全ライン 제거된 state file → ファイル rm
# ============================================================================
echo ""
echo "[4] 모든 라인 제거 → state file rm"

TMPDIR4=$(mktemp -d)
trap 'rm -rf "$TMPDIR4"' EXIT

STATE_DIR="$TMPDIR4/state"
mkdir -p "$STATE_DIR"
LOG4="$TMPDIR4/close.log"
touch "$LOG4"
MOCK_DIR4="$TMPDIR4/mock"
mkdir -p "$MOCK_DIR4"

# 全部 dead
make_mock_cmux "$MOCK_DIR4" "" "$LOG4"
MOCK_CMUX="$MOCK_DIR4/cmux"

STATE_FILE4="$STATE_DIR/children-WS4.json"
cat > "$STATE_FILE4" <<'EOF'
surface=surface:DEAD_A|name=cbp-d1|ts=1000|ws=workspace:WS4
surface=surface:DEAD_B|name=cbp-d2|ts=1001|ws=workspace:WS4
EOF

run_reap_orphans 2>&1
ec4=$?

check "case4: exit 0" "0" "$ec4"
check_file_absent "case4: state file が rm されていること" "$STATE_FILE4"

# ============================================================================
# 케이스 5: CBP_REAP_ORPHANS_DRY_RUN=1 → close 미호출 + "would reap" + state 유지
# ============================================================================
echo ""
echo "[5] CBP_REAP_ORPHANS_DRY_RUN=1 → dry-run: close 미호출 + 'would reap' 출력 + state 유지"

TMPDIR5=$(mktemp -d)
trap 'rm -rf "$TMPDIR5"' EXIT

STATE_DIR="$TMPDIR5/state"
mkdir -p "$STATE_DIR"
LOG5="$TMPDIR5/close.log"
touch "$LOG5"
MOCK_DIR5="$TMPDIR5/mock"
mkdir -p "$MOCK_DIR5"

make_mock_cmux "$MOCK_DIR5" "" "$LOG5"
MOCK_CMUX="$MOCK_DIR5/cmux"

STATE_FILE5="$STATE_DIR/children-WS5.json"
cat > "$STATE_FILE5" <<'EOF'
surface=surface:DEAD_DRY|name=cbp-dry|ts=1000|ws=workspace:WS5
EOF

stdout5=$(run_reap_orphans CBP_REAP_ORPHANS_DRY_RUN=1 2>&1)
ec5=$?

check "case5: exit 0" "0" "$ec5"
log5_content=$(cat "$LOG5")
check "case5: close-surface 미호출 (dry-run)" "" "$log5_content"
check_contains "case5: 'would reap' 출력 포함" "would reap" "$stdout5"
# state ライン が残っているか
check_line_in_file "case5: state に dry surface ライン 残存" "surface:DEAD_DRY" "$STATE_FILE5"

# ============================================================================
# 케이스 6: state dir 없음/빈 → exit 0 무동작
# ============================================================================
echo ""
echo "[6] state dir 없음 → exit 0 무동작"

TMPDIR6=$(mktemp -d)
trap 'rm -rf "$TMPDIR6"' EXIT

STATE_DIR="$TMPDIR6/nonexistent"
LOG6="$TMPDIR6/close.log"
touch "$LOG6"
MOCK_DIR6="$TMPDIR6/mock"
mkdir -p "$MOCK_DIR6"

make_mock_cmux "$MOCK_DIR6" "" "$LOG6"
MOCK_CMUX="$MOCK_DIR6/cmux"

stdout6=$(run_reap_orphans 2>&1)
ec6=$?

check "case6: exit 0" "0" "$ec6"
log6_content=$(cat "$LOG6")
check "case6: close-surface 미호출" "" "$log6_content"

echo ""
echo "[6b] state dir 있지만 state file 없음 → exit 0 무동작"

TMPDIR6B=$(mktemp -d)
trap 'rm -rf "$TMPDIR6B"' EXIT

STATE_DIR="$TMPDIR6B/state"
mkdir -p "$STATE_DIR"
LOG6B="$TMPDIR6B/close.log"
touch "$LOG6B"
MOCK_DIR6B="$TMPDIR6B/mock"
mkdir -p "$MOCK_DIR6B"

make_mock_cmux "$MOCK_DIR6B" "" "$LOG6B"
MOCK_CMUX="$MOCK_DIR6B/cmux"

stdout6b=$(run_reap_orphans 2>&1)
ec6b=$?

check "case6b: exit 0" "0" "$ec6b"
log6b_content=$(cat "$LOG6B")
check "case6b: close-surface 미호출" "" "$log6b_content"

# ============================================================================
# 케이스 7: 여러 state file (multi-workspace) → 각각 스캔
# ============================================================================
echo ""
echo "[7] multi-workspace state files → dead 만 정리, alive 유지"

TMPDIR7=$(mktemp -d)
trap 'rm -rf "$TMPDIR7"' EXIT

STATE_DIR="$TMPDIR7/state"
mkdir -p "$STATE_DIR"
LOG7="$TMPDIR7/close.log"
touch "$LOG7"
MOCK_DIR7="$TMPDIR7/mock"
mkdir -p "$MOCK_DIR7"

# surface:ALIVE は alive, 他は dead
make_mock_cmux "$MOCK_DIR7" "surface:ALIVE" "$LOG7"
MOCK_CMUX="$MOCK_DIR7/cmux"

# WS_A: dead surface
STATE_FILE7A="$STATE_DIR/children-WS_A.json"
cat > "$STATE_FILE7A" <<'EOF'
surface=surface:DEAD_WS_A|name=cbp-wa|ts=1000|ws=workspace:WS_A
EOF

# WS_B: alive + dead 混在
STATE_FILE7B="$STATE_DIR/children-WS_B.json"
cat > "$STATE_FILE7B" <<'EOF'
surface=surface:ALIVE|name=cbp-alive|ts=1001|ws=workspace:WS_B
surface=surface:DEAD_WS_B|name=cbp-wb|ts=1002|ws=workspace:WS_B
EOF

run_reap_orphans 2>&1
ec7=$?

check "case7: exit 0" "0" "$ec7"

# WS_A が clean されていること (全dead → file rm)
check_file_absent "case7: WS_A state file rm" "$STATE_FILE7A"

# WS_B: alive ライン残存, dead 削除
check_line_in_file "case7: WS_B に surface:ALIVE 残存" "surface:ALIVE" "$STATE_FILE7B"
check_line_absent_in_file "case7: WS_B に surface:DEAD_WS_B なし" "surface:DEAD_WS_B" "$STATE_FILE7B"

# close-surface が dead 2件に対してのみ呼ばれたか
log7_content=$(cat "$LOG7")
check_contains "case7: DEAD_WS_A の close-surface 呼ばれた" "--surface surface:DEAD_WS_A" "$log7_content"
check_contains "case7: DEAD_WS_B の close-surface 呼ばれた" "--surface surface:DEAD_WS_B" "$log7_content"
check_not_contains "case7: ALIVE の close-surface 呼ばれていない" "--surface surface:ALIVE" "$log7_content"

# ============================================================================
# 케이스 8: liveness read-screen 에 --workspace 누락 → alive surface 를 dead 오판 재현.
# ws-aware mock: --workspace 없으면 exit 1(dead), 있으면 exit 0(alive).
# 구현이 --workspace 를 넘기지 않으면: alive surface 가 dead 로 판정 → 잘못 reap.
# 구현이 --workspace 를 넘기면: alive → 보존, close 미호출.
# ============================================================================
echo ""
echo "[8] liveness read-screen 에 --workspace 포함 필수 — ws-aware mock 으로 회귀 검출"

TMPDIR8=$(mktemp -d)
trap 'rm -rf "$TMPDIR8"' EXIT

STATE_DIR="$TMPDIR8/state"
mkdir -p "$STATE_DIR"
LOG8="$TMPDIR8/close.log"
touch "$LOG8"
MOCK_DIR8="$TMPDIR8/mock"
mkdir -p "$MOCK_DIR8"

# ws-aware mock: surface:CROSS_ALIVE 는 --workspace 있을 때만 alive
make_mock_cmux_ws_aware "$MOCK_DIR8" "surface:CROSS_ALIVE" "$LOG8"
MOCK_CMUX="$MOCK_DIR8/cmux"

STATE_FILE8="$STATE_DIR/children-WS8.json"
cat > "$STATE_FILE8" <<'EOF'
surface=surface:CROSS_ALIVE|name=cbp-cross|ts=1000|ws=workspace:WS8
EOF

run_reap_orphans 2>&1
ec8=$?

check "case8: exit 0" "0" "$ec8"
# alive surface は close-surface 未呼び出し (--workspace 渡し正常なら保護される)
log8_content=$(cat "$LOG8")
check "case8: close-surface 미호출 (alive surface 보호)" "" "$log8_content"
# state ライン が残っているか
check_line_in_file "case8: alive surface state ライン 残存" "surface:CROSS_ALIVE" "$STATE_FILE8"

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
echo "✅ PASS"
