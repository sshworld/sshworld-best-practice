#!/usr/bin/env bash
# cmux-pane-reap-orphans-lock.test.sh — do_reap_orphans 2-phase lock + 신생 grace + ws_ref 조건부 close.
#
# 케이스:
#   L1) reap 진행 중(phase1/phase2 사이) append 된 줄이 유실되지 않음
#       (mock read-screen 시점에 state file 에 새 줄 추가하는 방식으로 병렬 launch 재현).
#   L2) ts=$(date +%s) 신생 줄 → read-screen 호출 자체가 없음 (mock 호출 로그 검증) + 보존.
#   L3) ts=abc / ts 결측 줄 → 기존 동작 (liveness 검사 수행).
#   L4) ws_ref 빈 dead 줄 → close-surface 호출에 --workspace 없음.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
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

check_line_in_file() {
  local desc="$1" needle="$2" file="$3"
  if grep -qF "$needle" "$file" 2>/dev/null; then
    echo "ok: $desc"
    pass=$((pass + 1))
  else
    echo "FAIL: $desc — '$needle' not found in $file (content: $(cat "$file" 2>/dev/null))" >&2
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

run_reap_orphans() {
  env \
    CMUX_BIN="$MOCK_CMUX" \
    CBP_STATE_DIR="$STATE_DIR" \
    "$@" \
    bash "$WRAPPER" reap-orphans
}

# ============================================================================
# L1: phase1/phase2 사이 append 된 줄이 유실되지 않음
# ============================================================================
echo ""
echo "[L1] reap 진행 중 append 된 줄 유실되지 않음 (lock 재-read 로 보존)"

TMPDIR1=$(mktemp -d)
trap 'rm -rf "$TMPDIR1"' EXIT

STATE_DIR="$TMPDIR1/state"
mkdir -p "$STATE_DIR"
LOG1="$TMPDIR1/close.log"
touch "$LOG1"
MOCK_DIR1="$TMPDIR1/mock"
mkdir -p "$MOCK_DIR1"

STATE_FILE1="$STATE_DIR/children-WS1.json"
cat > "$STATE_FILE1" <<'EOF'
surface=surface:OLD_DEAD|name=cbp-old|ts=1000|ws=workspace:WS1
EOF

# mock: read-screen 이 호출되는 시점(=phase2 진행 중)에 state file 에 새 줄을 append 후 dead(exit1) 반환.
cat > "$MOCK_DIR1/cmux" <<MOCKEOF
#!/usr/bin/env bash
subcmd="\$1"; shift
case "\$subcmd" in
  read-screen)
    printf 'surface=surface:NEW_APPENDED|name=cbp-new|ts=1000|ws=workspace:WS1\n' >> "$STATE_FILE1"
    exit 1
    ;;
  close-surface)
    printf 'close-surface %s\n' "\$*" >> "$LOG1"
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
MOCKEOF
chmod +x "$MOCK_DIR1/cmux"
MOCK_CMUX="$MOCK_DIR1/cmux"

out1=$(run_reap_orphans 2>&1)
ec1=$?

check "L1: exit 0" "0" "$ec1"
check_contains "L1: OLD_DEAD close-surface 호출됨" "--surface surface:OLD_DEAD" "$(cat "$LOG1")"
check_line_absent_in_file "L1: state 에 OLD_DEAD 없음" "surface:OLD_DEAD" "$STATE_FILE1"
check_line_in_file "L1: 병렬 append 된 NEW_APPENDED 유실되지 않고 보존" "surface:NEW_APPENDED" "$STATE_FILE1"

# ============================================================================
# L2: ts=$(date +%s) 신생 줄 → read-screen 호출 없음 + 보존
# ============================================================================
echo ""
echo "[L2] 신생(ts=now) 줄 → liveness 검사(read-screen) 자체 skip + 보존"

TMPDIR2=$(mktemp -d)
trap 'rm -rf "$TMPDIR2"' EXIT

STATE_DIR="$TMPDIR2/state"
mkdir -p "$STATE_DIR"
CALLLOG2="$TMPDIR2/calls.log"
touch "$CALLLOG2"
MOCK_DIR2="$TMPDIR2/mock"
mkdir -p "$MOCK_DIR2"

NOW_TS=$(date +%s)
STATE_FILE2="$STATE_DIR/children-WS2.json"
cat > "$STATE_FILE2" <<EOF
surface=surface:NEW_GRACE|name=cbp-new|ts=${NOW_TS}|ws=workspace:WS2
EOF

# mock: 모든 호출을 로그에 기록. read-screen 은 항상 dead(exit1) — grace 미적용 시 잘못 reap 되는지 검증.
cat > "$MOCK_DIR2/cmux" <<MOCKEOF
#!/usr/bin/env bash
printf '%s %s\n' "\$1" "\$*" >> "$CALLLOG2"
subcmd="\$1"; shift
case "\$subcmd" in
  read-screen) exit 1 ;;
  close-surface) exit 0 ;;
  *) exit 0 ;;
esac
MOCKEOF
chmod +x "$MOCK_DIR2/cmux"
MOCK_CMUX="$MOCK_DIR2/cmux"

out2=$(run_reap_orphans 2>&1)
ec2=$?

check "L2: exit 0" "0" "$ec2"
check_not_contains "L2: read-screen 호출에 surface:NEW_GRACE 없음(호출 자체 없음)" "surface:NEW_GRACE" "$(cat "$CALLLOG2")"
check_line_in_file "L2: state 에 NEW_GRACE 보존" "surface:NEW_GRACE" "$STATE_FILE2"

# ============================================================================
# L3: ts=abc / ts 결측 → 기존 동작 (liveness 검사 수행)
# ============================================================================
echo ""
echo "[L3] ts=abc / ts 결측 → grace 미적용, liveness 검사 정상 수행"

TMPDIR3=$(mktemp -d)
trap 'rm -rf "$TMPDIR3"' EXIT

STATE_DIR="$TMPDIR3/state"
mkdir -p "$STATE_DIR"
CALLLOG3="$TMPDIR3/calls.log"
touch "$CALLLOG3"
MOCK_DIR3="$TMPDIR3/mock"
mkdir -p "$MOCK_DIR3"

STATE_FILE3="$STATE_DIR/children-WS3.json"
cat > "$STATE_FILE3" <<'EOF'
surface=surface:BADTS_ALIVE|name=cbp-a|ts=abc|ws=workspace:WS3
surface=surface:NOTS_DEAD|name=cbp-b|ws=workspace:WS3
EOF

# mock: surface:BADTS_ALIVE 는 alive(exit0), 그 외는 dead(exit1). 모든 read-screen 호출은 로그에 기록.
cat > "$MOCK_DIR3/cmux" <<MOCKEOF
#!/usr/bin/env bash
subcmd="\$1"; shift
case "\$subcmd" in
  read-screen)
    surface_ref=""
    while [ \$# -gt 0 ]; do
      case "\$1" in
        --surface) surface_ref="\$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    printf 'read-screen --surface %s\n' "\$surface_ref" >> "$CALLLOG3"
    if [ "\$surface_ref" = "surface:BADTS_ALIVE" ]; then
      exit 0
    else
      exit 1
    fi
    ;;
  close-surface)
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
MOCKEOF
chmod +x "$MOCK_DIR3/cmux"
MOCK_CMUX="$MOCK_DIR3/cmux"

out3=$(run_reap_orphans 2>&1)
ec3=$?

check "L3: exit 0" "0" "$ec3"
check_contains "L3: ts=abc 줄도 liveness 검사 수행됨" "surface:BADTS_ALIVE" "$(cat "$CALLLOG3")"
check_contains "L3: ts 결측 줄도 liveness 검사 수행됨" "surface:NOTS_DEAD" "$(cat "$CALLLOG3")"
check_line_in_file "L3: ts=abc alive → state 보존" "surface:BADTS_ALIVE" "$STATE_FILE3"
check_line_absent_in_file "L3: ts 결측 dead → state 제거" "surface:NOTS_DEAD" "$STATE_FILE3"

# ============================================================================
# L4: ws_ref 빈 dead 줄 → close-surface 호출에 --workspace 없음
# ============================================================================
echo ""
echo "[L4] ws_ref 빈 dead 줄 → close-surface 호출에 --workspace 미포함"

TMPDIR4=$(mktemp -d)
trap 'rm -rf "$TMPDIR4"' EXIT

STATE_DIR="$TMPDIR4/state"
mkdir -p "$STATE_DIR"
LOG4="$TMPDIR4/close.log"
touch "$LOG4"
MOCK_DIR4="$TMPDIR4/mock"
mkdir -p "$MOCK_DIR4"

STATE_FILE4="$STATE_DIR/children-WS4.json"
cat > "$STATE_FILE4" <<'EOF'
surface=surface:NOWS_DEAD|name=cbp-c|ts=1000|ws=
EOF

cat > "$MOCK_DIR4/cmux" <<MOCKEOF
#!/usr/bin/env bash
subcmd="\$1"; shift
case "\$subcmd" in
  read-screen) exit 1 ;;
  close-surface)
    printf 'close-surface %s\n' "\$*" >> "$LOG4"
    exit 0
    ;;
  *) exit 0 ;;
esac
MOCKEOF
chmod +x "$MOCK_DIR4/cmux"
MOCK_CMUX="$MOCK_DIR4/cmux"

out4=$(run_reap_orphans 2>&1)
ec4=$?

check "L4: exit 0" "0" "$ec4"
check_contains "L4: close-surface --surface surface:NOWS_DEAD 호출됨" "--surface surface:NOWS_DEAD" "$(cat "$LOG4")"
check_not_contains "L4: close-surface 호출에 --workspace 없음" "--workspace" "$(cat "$LOG4")"

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
