#!/usr/bin/env bash
# cmux_pane_uuid_ref.sh — CMUX_SURFACE_ID 가 cmux 실측 UUID(예: 1A1EDE2A-EB58-...)일 때도
# cmux-pane.sh 의 send/capture/wait-idle/kill 이 --surface 로 라우팅하는지 검증 (belt 해법).
# 현행(수정 전)은 UUID ref 가 surface:* case 미매치 → --workspace 오라우팅 (Red).
# 회귀 가드: 기존 surface:N / workspace:N 라우팅은 그대로 보존.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WRAPPER="$REPO/scripts/cmux-pane.sh"

UUID_REF="1A1EDE2A-EB58-4DDD-A309-E750F1DE8999"

pass=0
fail_count=0

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

# 모든 호출 인자를 logfile 에 기록하는 mock. read-screen 은 정적 화면 반환(wait-idle 수렴용).
make_mock_cmux_logger() {
  local mockdir="$1" logfile="$2"
  cat > "$mockdir/cmux" <<MOCKEOF
#!/usr/bin/env bash
echo "\$@" >> "$logfile"
case "\$1" in
  read-screen) echo "static-screen"; exit 0 ;;
  *) exit 0 ;;
esac
MOCKEOF
  chmod +x "$mockdir/cmux"
}

# ============================================================================
# [1] capture --pane=<UUID> -> read-screen --surface <UUID>
# ============================================================================
echo ""
echo "[1] capture UUID ref -> --surface 라우팅"

T1=$(mktemp -d); trap 'rm -rf "$T1"' EXIT
LOG1="$T1/calls.log"; touch "$LOG1"
mkdir -p "$T1/mock"
make_mock_cmux_logger "$T1/mock" "$LOG1"

CMUX_BIN="$T1/mock/cmux" bash "$WRAPPER" capture --pane="$UUID_REF" >/dev/null 2>&1
check_contains "case1: capture UUID -> --surface" "read-screen --surface $UUID_REF" "$(cat "$LOG1")"
check_not_contains "case1: capture UUID -> --workspace 미사용" "--workspace $UUID_REF" "$(cat "$LOG1")"

# ============================================================================
# [2] send <text> --pane=<UUID> -> send --surface <UUID> <text>
# ============================================================================
echo ""
echo "[2] send UUID ref -> --surface 라우팅"

T2=$(mktemp -d); trap 'rm -rf "$T2"' EXIT
LOG2="$T2/calls.log"; touch "$LOG2"
mkdir -p "$T2/mock"
make_mock_cmux_logger "$T2/mock" "$LOG2"

CMUX_BIN="$T2/mock/cmux" CBP_SEND_CONFIRM=0 bash "$WRAPPER" send "hello" --pane="$UUID_REF" --enter=false >/dev/null 2>&1
check_contains "case2: send UUID -> --surface" "send --surface $UUID_REF hello" "$(cat "$LOG2")"

# ============================================================================
# [3] wait-idle --pane=<UUID> -> read-screen --surface <UUID>
# ============================================================================
echo ""
echo "[3] wait-idle UUID ref -> --surface 라우팅"

T3=$(mktemp -d); trap 'rm -rf "$T3"' EXIT
LOG3="$T3/calls.log"; touch "$LOG3"
mkdir -p "$T3/mock"
make_mock_cmux_logger "$T3/mock" "$LOG3"

CMUX_BIN="$T3/mock/cmux" bash "$WRAPPER" wait-idle --pane="$UUID_REF" --idle=0 --timeout=5 >/dev/null 2>&1
check_contains "case3: wait-idle UUID -> --surface" "read-screen --surface $UUID_REF" "$(cat "$LOG3")"

# ============================================================================
# [4] kill --pane=<UUID> -> close-surface --surface <UUID>
# ============================================================================
echo ""
echo "[4] kill UUID ref -> close-surface --surface 라우팅"

T4=$(mktemp -d); trap 'rm -rf "$T4"' EXIT
LOG4="$T4/calls.log"; touch "$LOG4"
mkdir -p "$T4/mock"
make_mock_cmux_logger "$T4/mock" "$LOG4"
STATE4="$T4/state.json"

CMUX_BIN="$T4/mock/cmux" CBP_STATE_FILE="$STATE4" bash "$WRAPPER" kill --pane="$UUID_REF" >/dev/null 2>&1
check_contains "case4: kill UUID -> close-surface --surface" "close-surface --surface $UUID_REF" "$(cat "$LOG4")"

# ============================================================================
# [5] 회귀 가드 — surface:7 -> --surface
# ============================================================================
echo ""
echo "[5] 회귀 — surface:7 -> --surface 그대로"

T5=$(mktemp -d); trap 'rm -rf "$T5"' EXIT
LOG5="$T5/calls.log"; touch "$LOG5"
mkdir -p "$T5/mock"
make_mock_cmux_logger "$T5/mock" "$LOG5"

CMUX_BIN="$T5/mock/cmux" bash "$WRAPPER" capture --pane="surface:7" >/dev/null 2>&1
check_contains "case5: surface:7 -> --surface (회귀)" "read-screen --surface surface:7" "$(cat "$LOG5")"

# ============================================================================
# [6] 회귀 가드 — workspace:cbp-x -> --workspace
# ============================================================================
echo ""
echo "[6] 회귀 — workspace:cbp-x -> --workspace 그대로"

T6=$(mktemp -d); trap 'rm -rf "$T6"' EXIT
LOG6="$T6/calls.log"; touch "$LOG6"
mkdir -p "$T6/mock"
make_mock_cmux_logger "$T6/mock" "$LOG6"

CMUX_BIN="$T6/mock/cmux" bash "$WRAPPER" capture --pane="workspace:cbp-x" >/dev/null 2>&1
check_contains "case6: workspace:cbp-x -> --workspace (회귀)" "read-screen --workspace workspace:cbp-x" "$(cat "$LOG6")"

echo ""
echo "=== 결과: pass=$pass fail=$fail_count ==="
[ "$fail_count" -eq 0 ]
