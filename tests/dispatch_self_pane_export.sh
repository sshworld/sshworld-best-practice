#!/usr/bin/env bash
# dispatch_self_pane_export.sh — dispatch-slice-pane.sh 가 자식 셸에 정확한 surface:N ref 를
# CBP_SELF_PANE 로 export 하는지, 그리고 그 send 가 CHILD_CMD send 보다 먼저 발생하는지 검증.
#
# 시나리오:
#   T1: mock CMUX_BIN 으로 launch → surface:1 반환. 모든 호출을 calls.log 에 순서대로 기록.
#       DISPATCH_CHILD_CMD 에 고유 마커 텍스트 사용 → 로그에서
#       "export CBP_SELF_PANE=surface:1" 줄과 마커 줄의 순서를 비교.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DISPATCH="$REPO/scripts/dispatch-slice-pane.sh"

PASS=0; FAIL=0; FAILED=()

run() {
  local name="$1"; shift
  echo ""
  echo "[$name]"
  if "$@"; then
    PASS=$((PASS+1))
    echo "  OK"
  else
    FAIL=$((FAIL+1))
    FAILED+=("$name")
    echo "  FAILED" >&2
  fi
}

[ -f "$DISPATCH" ] || { echo "dispatcher missing: $DISPATCH" >&2; exit 1; }

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

(
  cd "$tmpdir"
  git init -b main -q
  git config user.email t@e.local
  git config user.name tester
  echo dummy > README
  git add README
  git -c commit.gpgsign=false commit -m base -q
) 2>/dev/null

echo "spec content" > "$tmpdir/spec.md"

# ─────────────────────────────────────────────
# T1: CBP_SELF_PANE export send 가 CHILD_CMD send 보다 먼저 기록됨
# ─────────────────────────────────────────────
t1_self_pane_exported_before_child_cmd() {
  local mock_cmux="$tmpdir/cmux-t1"
  local calls_log="$tmpdir/t1-calls.log"
  : > "$calls_log"

  cat > "$mock_cmux" <<MOCK
#!/usr/bin/env bash
echo "\$@" >> "$calls_log"
case "\$1" in
  ping) echo "PONG"; exit 0 ;;
  new-pane|new-split) echo "OK surface:1"; exit 0 ;;
  rename-tab) exit 0 ;;
  send|send-key) exit 0 ;;
  wait-idle) exit 0 ;;
  capture|read-screen) echo "static-screen-content"; exit 0 ;;
  close-surface|kill) exit 0 ;;
  identify) echo "workspace:1"; exit 0 ;;
  *) exit 0 ;;
esac
MOCK
  chmod +x "$mock_cmux"

  # CMUX_WORKSPACE_ID 명시 — dispatch 의 grid-split launch 경로(_do_launch_grid) 를
  # 결정적으로 태워 실제 dispatch(부모 workspace 안 자식 surface) 흐름을 재현.
  # CBP_STATE_FILE 은 tmp 격리 — 실 호스트의 ~/.cache/cbp state 오염/의존 방지.
  local out ec=0
  out=$(cd "$tmpdir" && \
    CMUX_BIN="$mock_cmux" \
    CMUX_WORKSPACE_ID="parentws1" \
    CBP_STATE_FILE="$tmpdir/state.json" \
    DISPATCH_CHILD_CMD="MYCHILDCMD_MARKER_XYZ" \
    DISPATCH_SKIP_CLEANUP=1 \
    DISPATCH_VERIFY=0 \
    CBP_WARMUP_SLEEP=0 \
    CBP_SEND_CONFIRM=0 \
    bash "$DISPATCH" \
      --slice=self-pane-t1 \
      --spec-file="$tmpdir/spec.md" \
      --worktree="$tmpdir/.worktrees/self-pane-t1" \
      --mode=cmux 2>"$tmpdir/t1-stderr") || ec=$?

  if [ "$ec" -ne 0 ]; then
    echo "  FAIL: exit code $ec (expected 0)" >&2
    cat "$tmpdir/t1-stderr" >&2
    return 1
  fi

  # 1. calls log 에 export CBP_SELF_PANE=surface:1 존재
  if ! grep -qF 'export CBP_SELF_PANE=surface:1' "$calls_log"; then
    echo "  FAIL: calls log 에 'export CBP_SELF_PANE=surface:1' 없음" >&2
    cat "$calls_log" >&2
    return 1
  fi

  # 2. 그 send 가 CHILD_CMD send 보다 앞
  local export_line child_line
  export_line=$(grep -nF 'export CBP_SELF_PANE=surface:1' "$calls_log" | head -1 | cut -d: -f1)
  child_line=$(grep -nF 'MYCHILDCMD_MARKER_XYZ' "$calls_log" | head -1 | cut -d: -f1)

  if [ -z "$export_line" ] || [ -z "$child_line" ]; then
    echo "  FAIL: export_line='$export_line' child_line='$child_line'" >&2
    cat "$calls_log" >&2
    return 1
  fi

  if [ "$export_line" -ge "$child_line" ]; then
    echo "  FAIL: export send(line $export_line) 가 child send(line $child_line) 보다 앞이 아님" >&2
    cat "$calls_log" >&2
    return 1
  fi

  echo "  export_line=$export_line < child_line=$child_line OK"
  return 0
}

run "T1 CBP_SELF_PANE export send -> CHILD_CMD send 이전" t1_self_pane_exported_before_child_cmd

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && echo "✅ all pass" || { echo "❌ FAILED: ${FAILED[*]}"; exit 1; }
