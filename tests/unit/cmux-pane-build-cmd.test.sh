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

[ -f "$SCRIPT" ] || { echo "FAIL: $SCRIPT 없음" >&2; exit 1; }

# ----------------------------------------------------------------
# mock cmux binary: new-pane/new-split 은 "OK surface:0 pane:0 workspace:0" 반환
# 그 외 명령은 인자 그대로 echo
MOCK_CMUX="/tmp/mock-cmux-$$"
cat > "$MOCK_CMUX" <<'MOCK'
#!/usr/bin/env bash
case "$1" in
  new-pane|new-split)
    echo "OK surface:0 pane:0 workspace:0"
    ;;
  rename-tab)
    echo "OK action=rename tab=tab:0 surface:0"
    exit 0
    ;;
  *)
    echo "$@"
    ;;
esac
MOCK
chmod +x "$MOCK_CMUX"

# noisy mock A: new-pane 이 stderr 로 부수 메시지 출력
MOCK_CMUX_NOISY_A="/tmp/mock-cmux-noisy-a-$$"
cat > "$MOCK_CMUX_NOISY_A" <<'MOCK'
#!/usr/bin/env bash
case "$1" in
  new-pane|new-split)
    echo "info: opened pane" >&2
    echo "OK surface:0 pane:0 workspace:0"
    ;;
  rename-tab)
    echo "OK action=rename tab=tab:0 surface:0"
    exit 0
    ;;
  *)
    echo "$@"
    ;;
esac
MOCK
chmod +x "$MOCK_CMUX_NOISY_A"

# noisy mock B: new-pane 이 stdout 에 두 번째 줄(trailing noise) 출력
MOCK_CMUX_NOISY_B="/tmp/mock-cmux-noisy-b-$$"
cat > "$MOCK_CMUX_NOISY_B" <<'MOCK'
#!/usr/bin/env bash
case "$1" in
  new-pane|new-split)
    printf 'OK surface:0 pane:0 workspace:0\ntrailing-event line\n'
    ;;
  rename-tab)
    echo "OK action=rename tab=tab:0 surface:0"
    exit 0
    ;;
  *)
    echo "$@"
    ;;
esac
MOCK
chmod +x "$MOCK_CMUX_NOISY_B"

trap 'rm -f "$MOCK_CMUX" "$MOCK_CMUX_NOISY_A" "$MOCK_CMUX_NOISY_B" "$STATE_A"' EXIT

STATE_A="/tmp/test-A2-cmd-$$.state"

total=18

# ----------------------------------------------------------------
# 기존 회귀 케이스 (CMUX_WORKSPACE_ID unset — new-workspace 흐름)
# 주의: 테스트 환경 자체가 cmux 안일 수 있으므로 env -i 로 명시적 격리
# ----------------------------------------------------------------

# 1. launch — new-workspace + --cwd + --name cbp- + --command
result=$(env -i PATH="$PATH" HOME="${HOME:-/tmp}" \
  CMUX_BIN=echo \
  bash -c 'cd /tmp && bash '"$SCRIPT"' launch zsh' 2>/dev/null)
check_contains "launch: new-workspace 포함" "new-workspace" "$result"
check_contains "launch: --cwd /tmp 포함" "--cwd /tmp" "$result"
check_contains "launch: --name cbp- 포함" "--name cbp-" "$result"
check_contains "launch: --command zsh 포함" "--command zsh" "$result"

# 2. send — send --workspace <ref> <text>
result=$(env -i PATH="$PATH" HOME="${HOME:-/tmp}" \
  CMUX_BIN=echo \
  bash "$SCRIPT" send "hi" --pane=workspace:1 2>/dev/null)
check_contains "send: send --workspace workspace:1 hi 포함" "send --workspace workspace:1 hi" "$result"

# 3. capture — read-screen --workspace <ref>
result=$(env -i PATH="$PATH" HOME="${HOME:-/tmp}" \
  CMUX_BIN=echo \
  bash "$SCRIPT" capture --pane=workspace:1 2>/dev/null)
check_contains "capture: read-screen --workspace workspace:1 포함" "read-screen --workspace workspace:1" "$result"

# ----------------------------------------------------------------
# 신규 케이스: CMUX_WORKSPACE_ID set — grid split 흐름
# ----------------------------------------------------------------

# 4. 첫 launch in cmux (state 없음) → state file 에 1줄 추가됨 + stdout = surface ref
rm -f "$STATE_A"
first_out=$(env -i PATH="$PATH" HOME="${HOME:-/tmp}" \
  CMUX_BIN="$MOCK_CMUX" \
  CMUX_WORKSPACE_ID="workspace:1" \
  CBP_STATE_FILE="$STATE_A" \
  CBP_WORKSPACE_PREFIX="cbp-" \
  bash "$SCRIPT" launch zsh 2>/dev/null)
line_count=$(wc -l < "$STATE_A" 2>/dev/null | tr -d ' ')
check "launch in cmux (첫 번째): state 1줄 추가" "1" "$line_count"
check_contains "launch in cmux (첫 번째): stdout = surface ref" "surface:" "$first_out"

# 5. 첫 launch cmux stdout 에 new-pane 명령 사용됨 (mock 이 surface:0 반환)
# mock cmux 가 "OK surface:0 ..." 반환하므로 do_launch 가 awk '/^OK /{print $2;exit}' → "surface:0"
check "launch in cmux (첫 번째): stdout = surface:0" "surface:0" "$first_out"

# T2: launch stdout 이 정확히 한 줄 — rename-tab 의 stdout noise 가 섞이지 않아야 함
# $first_out 에 개행이 없으면 단일 줄임 (echo 로 줄 수 세기)
first_out_lines=$(echo "$first_out" | wc -l | tr -d ' ')
check "launch in cmux (첫 번째): stdout 정확히 1줄" "1" "$first_out_lines"

# 6. 두 번째 launch in cmux (state 에 1줄 있음) → state 2줄 + new-split down 사용
# prev_surface 는 첫 번째 launch 결과 = surface:0
second_out=$(env -i PATH="$PATH" HOME="${HOME:-/tmp}" \
  CMUX_BIN="$MOCK_CMUX" \
  CMUX_WORKSPACE_ID="workspace:1" \
  CBP_STATE_FILE="$STATE_A" \
  CBP_WORKSPACE_PREFIX="cbp-" \
  bash "$SCRIPT" launch zsh 2>/dev/null)
line_count=$(wc -l < "$STATE_A" 2>/dev/null | tr -d ' ')
check "launch in cmux (두 번째): state 2줄" "2" "$line_count"
check_contains "launch in cmux (두 번째): stdout = surface ref" "surface:" "$second_out"

# 7. 세 번째 launch → state 3줄 + new-split right (count=2 → dir=right)
third_out=$(env -i PATH="$PATH" HOME="${HOME:-/tmp}" \
  CMUX_BIN="$MOCK_CMUX" \
  CMUX_WORKSPACE_ID="workspace:1" \
  CBP_STATE_FILE="$STATE_A" \
  CBP_WORKSPACE_PREFIX="cbp-" \
  bash "$SCRIPT" launch zsh 2>/dev/null)
line_count=$(wc -l < "$STATE_A" 2>/dev/null | tr -d ' ')
check "launch in cmux (세 번째): state 3줄" "3" "$line_count"

# T3-A: noisy mock (stderr noise) → launch stdout 은 surface:0 한 줄
rm -f "$STATE_A"
noisy_a_out=$(env -i PATH="$PATH" HOME="${HOME:-/tmp}" \
  CMUX_BIN="$MOCK_CMUX_NOISY_A" \
  CMUX_WORKSPACE_ID="workspace:1" \
  CBP_STATE_FILE="$STATE_A" \
  CBP_WORKSPACE_PREFIX="cbp-" \
  bash "$SCRIPT" launch zsh 2>/dev/null)
check "T3-A: noisy stderr mock — launch stdout = surface:0" "surface:0" "$noisy_a_out"

# T3-B: noisy mock (stdout trailing line) → launch stdout 은 surface:0 한 줄
rm -f "$STATE_A"
noisy_b_out=$(env -i PATH="$PATH" HOME="${HOME:-/tmp}" \
  CMUX_BIN="$MOCK_CMUX_NOISY_B" \
  CMUX_WORKSPACE_ID="workspace:1" \
  CBP_STATE_FILE="$STATE_A" \
  CBP_WORKSPACE_PREFIX="cbp-" \
  bash "$SCRIPT" launch zsh 2>/dev/null)
check "T3-B: noisy stdout trailing mock — launch stdout = surface:0" "surface:0" "$noisy_b_out"

# ----------------------------------------------------------------
# 8. kill surface ref → close-surface + state remove
rm -f "$STATE_A"
env -i PATH="$PATH" HOME="${HOME:-/tmp}" \
  CMUX_BIN="$MOCK_CMUX" \
  CMUX_WORKSPACE_ID="workspace:1" \
  CBP_STATE_FILE="$STATE_A" \
  CBP_WORKSPACE_PREFIX="cbp-" \
  bash "$SCRIPT" launch zsh 2>/dev/null > /dev/null
# state 에 surface:0 등록됨
kill_out=$(env -i PATH="$PATH" HOME="${HOME:-/tmp}" \
  FORCE_SELF_KILL=1 \
  CMUX_BIN=echo \
  CMUX_WORKSPACE_ID="workspace:1" \
  CBP_STATE_FILE="$STATE_A" \
  bash "$SCRIPT" kill --pane=surface:0 2>/dev/null)
check_contains "kill surface ref: close-surface --surface surface:0 포함" \
  "close-surface --surface surface:0" "$kill_out"

# 9. kill surface ref → state 에서 제거됨
# cbp_state_list 를 통해 surface:0 이 없어야 함
LOADER_SCRIPT="/tmp/cbp-loader-kill-$$.sh"
sed '$d' "$SCRIPT" > "$LOADER_SCRIPT"
echo "# loader: main call removed" >> "$LOADER_SCRIPT"
trap 'rm -f "$MOCK_CMUX" "$MOCK_CMUX_NOISY_A" "$MOCK_CMUX_NOISY_B" "$STATE_A" "$LOADER_SCRIPT"' EXIT
list_after_kill=$(env -i PATH="$PATH" HOME="${HOME:-/tmp}" \
    CBP_STATE_FILE="$STATE_A" \
    CMUX_WORKSPACE_ID="workspace:1" \
    CMUX_BIN=echo \
    CBP_WORKSPACE_PREFIX="cbp-" \
    bash -c "source '$LOADER_SCRIPT'; cbp_state_list")
check "kill surface: state 에서 surface:0 제거됨" "" "$list_after_kill"

# ----------------------------------------------------------------
# 10. kill workspace ref → close-workspace (기존 흐름)
kill_ws_out=$(env -i PATH="$PATH" HOME="${HOME:-/tmp}" \
  FORCE_SELF_KILL=1 \
  CMUX_BIN=echo \
  bash "$SCRIPT" kill --pane=workspace:9 2>/dev/null)
check_contains "kill workspace ref: close-workspace --workspace workspace:9 포함" \
  "close-workspace --workspace workspace:9" "$kill_ws_out"

echo ""
echo "ok: $pass/$total passed"
[ "$fail_count" -gt 0 ] && exit 1
exit 0
