#!/usr/bin/env bash
# cmux-pane-build-cmd.test.sh — CMUX_BIN=echo 주입으로 cmux-pane.sh 빌드 명령 검증

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO/scripts/cmux-pane.sh"

pass=0
fail_count=0

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

[ -f "$SCRIPT" ] || { echo "FAIL: $SCRIPT 없음" >&2; exit 1; }

total=6

# 1. launch — new-workspace + --cwd + --name cbp- + --command
# cd /tmp 으로 실제 cwd 변경 후 실행 (bash 는 PWD env override 를 무시하고 getcwd 사용)
result=$(cd /tmp && CMUX_BIN=echo bash "$SCRIPT" launch zsh 2>/dev/null)
check_contains "launch: new-workspace 포함" "new-workspace" "$result"
check_contains "launch: --cwd /tmp 포함" "--cwd /tmp" "$result"
check_contains "launch: --name cbp- 포함" "--name cbp-" "$result"
check_contains "launch: --command zsh 포함" "--command zsh" "$result"

# 2. send — send --workspace <ref> <text>
result=$(CMUX_BIN=echo bash "$SCRIPT" send "hi" --pane=workspace:1 2>/dev/null)
check_contains "send: send --workspace workspace:1 hi 포함" "send --workspace workspace:1 hi" "$result"

# 3. capture — read-screen --workspace <ref>
result=$(CMUX_BIN=echo bash "$SCRIPT" capture --pane=workspace:1 2>/dev/null)
check_contains "capture: read-screen --workspace workspace:1 포함" "read-screen --workspace workspace:1" "$result"

echo ""
echo "ok: $pass/$total passed"
[ "$fail_count" -gt 0 ] && exit 1
exit 0
