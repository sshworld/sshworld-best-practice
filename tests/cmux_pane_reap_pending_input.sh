#!/usr/bin/env bash
# cmux_pane_reap_pending_input.sh — reap 이 pending input(미제출 사용자 텍스트) pane 을
# 보존하는지 검증. `_do_reap_one` 은 기존에 DONE_PATTERN(✅/❌) 매치만 보고 do_kill 했음 —
# 자식 input box 에 미제출 텍스트가 남아 있어도 무시하고 회수해 사용자 지시가 유실됐다.
#
# 케이스:
#   1) pending: ✅ + 마지막 프롬프트 라인 "❯ leftover instruction text" → input-pending — kept, kill 미호출
#   2) 빈 프롬프트: ✅ + "❯" (빈 프롬프트) → reaped, kill 호출됨
#   3) 테두리 렌더 잔존 구멍 (pinned, known-issue): ✅ + "│ > text │" (❯/> 로 안 시작) → reaped
#   4) escape: CBP_REAP_IGNORE_PENDING=1 + 케이스1 화면 → reaped
#   5) --all 요약: pending 자식 1 → 요약에 "pending 1" 포함, pending 이 kept 로 흡수 안 됨("kept 1" 미출력)
#   6) dry-run: CBP_REAP_DRY_RUN=1 + 케이스1 → "would keep (input-pending)", kill 미호출

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

# 화면 fixture 를 고정 반환하고 close-workspace/close-surface 호출을 로그에 남기는 mock cmux.
# read-screen 은 항상 같은 화면을 돌려줘 wait-idle 이 즉시 idle 판정하도록 한다.
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

# ============================================================================
# 케이스 1: pending — ✅ + 미제출 프롬프트 텍스트 → input-pending, kill 미호출
# ============================================================================
echo ""
echo "[1] pending — 미제출 프롬프트 텍스트 → input-pending, kill 미호출"

T1=$(mktemp -d)
trap 'rm -rf "$T1"' EXIT
LOG1="$T1/close.log"; touch "$LOG1"
SCREEN1="$T1/screen.txt"
cat > "$SCREEN1" <<'EOF'
⏺ ✅ done-slug
some other line
❯ leftover instruction text
EOF
MOCKDIR1="$T1/mock"; mkdir -p "$MOCKDIR1"
make_mock_cmux "$MOCKDIR1" "$SCREEN1" "$LOG1"

out1=$(env CMUX_BIN="$MOCKDIR1/cmux" bash "$WRAPPER" reap --pane=workspace:1 --idle=1 --timeout=5 2>&1)
ec1=$?
check "case1: exit 0" "0" "$ec1"
check_contains "case1: 출력에 input-pending — kept" "input-pending — kept" "$out1"
check "case1: kill(close-workspace/close-surface) 미호출 (log empty)" "" "$(cat "$LOG1")"

# ============================================================================
# 케이스 2: 빈 프롬프트 — ✅ + "❯"(빈) → reaped, kill 호출됨
# ============================================================================
echo ""
echo "[2] 빈 프롬프트 — reaped, kill 호출됨"

T2=$(mktemp -d)
trap 'rm -rf "$T2"' EXIT
LOG2="$T2/close.log"; touch "$LOG2"
SCREEN2="$T2/screen.txt"
cat > "$SCREEN2" <<'EOF'
⏺ ✅ done-slug
❯
EOF
MOCKDIR2="$T2/mock"; mkdir -p "$MOCKDIR2"
make_mock_cmux "$MOCKDIR2" "$SCREEN2" "$LOG2"

out2=$(env CMUX_BIN="$MOCKDIR2/cmux" bash "$WRAPPER" reap --pane=workspace:1 --idle=1 --timeout=5 2>&1)
ec2=$?
check "case2: exit 0" "0" "$ec2"
check_contains "case2: 출력에 reaped" "reaped" "$out2"
check_contains "case2: close-workspace 호출됨" "close-workspace" "$(cat "$LOG2")"

# ============================================================================
# 케이스 3: 테두리 렌더 잔존 구멍 (pinned, known-issue) — "│ > text │" → reaped
# ============================================================================
echo ""
echo "[3] 테두리 렌더(│ > text │) — 프롬프트 라인 미매치 → reaped (잔존 known-issue, 의도된 동작)"

T3=$(mktemp -d)
trap 'rm -rf "$T3"' EXIT
LOG3="$T3/close.log"; touch "$LOG3"
SCREEN3="$T3/screen.txt"
cat > "$SCREEN3" <<'EOF'
⏺ ✅ done-slug
│ > text │
EOF
MOCKDIR3="$T3/mock"; mkdir -p "$MOCKDIR3"
make_mock_cmux "$MOCKDIR3" "$SCREEN3" "$LOG3"

out3=$(env CMUX_BIN="$MOCKDIR3/cmux" bash "$WRAPPER" reap --pane=workspace:1 --idle=1 --timeout=5 2>&1)
ec3=$?
check "case3: exit 0" "0" "$ec3"
check_contains "case3: 출력에 reaped (residual hole)" "reaped" "$out3"
check_contains "case3: close-workspace 호출됨" "close-workspace" "$(cat "$LOG3")"

# ============================================================================
# 케이스 4: escape — CBP_REAP_IGNORE_PENDING=1 + 케이스1 화면 → reaped
# ============================================================================
echo ""
echo "[4] escape CBP_REAP_IGNORE_PENDING=1 — pending 무시하고 reaped"

T4=$(mktemp -d)
trap 'rm -rf "$T4"' EXIT
LOG4="$T4/close.log"; touch "$LOG4"
MOCKDIR4="$T4/mock"; mkdir -p "$MOCKDIR4"
make_mock_cmux "$MOCKDIR4" "$SCREEN1" "$LOG4"

out4=$(env CMUX_BIN="$MOCKDIR4/cmux" CBP_REAP_IGNORE_PENDING=1 bash "$WRAPPER" reap --pane=workspace:1 --idle=1 --timeout=5 2>&1)
ec4=$?
check "case4: exit 0" "0" "$ec4"
check_contains "case4: 출력에 reaped" "reaped" "$out4"
check_contains "case4: close-workspace 호출됨" "close-workspace" "$(cat "$LOG4")"

# ============================================================================
# 케이스 5: --all 요약 — pending 자식 1 → "pending 1" 포함, "kept 1" 미출력(흡수 안 됨)
# ============================================================================
echo ""
echo "[5] --all 요약 — pending 1 포함, kept 로 흡수되지 않음"

T5=$(mktemp -d)
trap 'rm -rf "$T5"' EXIT
LOG5="$T5/close.log"; touch "$LOG5"
MOCKDIR5="$T5/mock"; mkdir -p "$MOCKDIR5"
make_mock_cmux "$MOCKDIR5" "$SCREEN1" "$LOG5"

STATE_FILE5="$T5/children-WS5.json"
OLD_TS=$(( $(date +%s) - 100 ))
cat > "$STATE_FILE5" <<EOF
surface=surface:PEND1|name=cbp-p1|ts=${OLD_TS}|ws=workspace:WS5
EOF

out5=$(env CMUX_BIN="$MOCKDIR5/cmux" CBP_STATE_FILE="$STATE_FILE5" bash "$WRAPPER" reap --all --idle=1 --timeout=5 2>&1)
ec5=$?
check "case5: exit 0" "0" "$ec5"
check_contains "case5: 요약에 pending 1 포함" "pending 1" "$out5"
check_not_contains "case5: pending 이 kept 1 로 흡수 안 됨" "kept 1" "$out5"
check "case5: close 미호출 (pending 은 보존)" "" "$(cat "$LOG5")"

# ============================================================================
# 케이스 6: dry-run — CBP_REAP_DRY_RUN=1 + 케이스1 → would keep (input-pending), kill 미호출
# ============================================================================
echo ""
echo "[6] dry-run — would keep (input-pending), kill 미호출"

T6=$(mktemp -d)
trap 'rm -rf "$T6"' EXIT
LOG6="$T6/close.log"; touch "$LOG6"
MOCKDIR6="$T6/mock"; mkdir -p "$MOCKDIR6"
make_mock_cmux "$MOCKDIR6" "$SCREEN1" "$LOG6"

out6=$(env CMUX_BIN="$MOCKDIR6/cmux" CBP_REAP_DRY_RUN=1 bash "$WRAPPER" reap --pane=workspace:1 --idle=1 --timeout=5 2>&1)
ec6=$?
check "case6: exit 0" "0" "$ec6"
check_contains "case6: 출력에 would keep (input-pending)" "would keep (input-pending)" "$out6"
check "case6: kill 미호출 (log empty)" "" "$(cat "$LOG6")"

# ============================================================================
echo ""
echo "=== 결과: pass=$pass fail=$fail_count ==="
[ "$fail_count" -eq 0 ]
