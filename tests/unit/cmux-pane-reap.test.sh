#!/usr/bin/env bash
# cmux-pane-reap.test.sh — do_reap 완료 자식 자동 회수 검증

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO/scripts/cmux-pane.sh"

pass=0
fail_count=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

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
  local desc="$1" expected="$2" actual="$3"
  if printf '%s' "$actual" | grep -qF -- "$expected"; then
    echo "ok: $desc"
    pass=$((pass + 1))
  else
    echo "FAIL: $desc — expected substring='$expected' in output='$actual'" >&2
    fail_count=$((fail_count + 1))
  fi
}

check_not_contains() {
  local desc="$1" not_expected="$2" actual="$3"
  if printf '%s' "$actual" | grep -qF -- "$not_expected"; then
    echo "FAIL: $desc — unexpected substring='$not_expected' found in output='$actual'" >&2
    fail_count=$((fail_count + 1))
  else
    echo "ok: $desc"
    pass=$((pass + 1))
  fi
}

[ -f "$SCRIPT" ] || { echo "FAIL: $SCRIPT 없음" >&2; exit 1; }

total=35

# fake cmux: read-screen → CMUX_SCREEN_FILE 출력, 그 외 → CMUX_CALLS_LOG 에 append
cat > "$TMP/cmux" << 'EOF'
#!/usr/bin/env bash
cmd="$1"; shift
if [ "$cmd" = "read-screen" ]; then
  cat "${CMUX_SCREEN_FILE:-/dev/null}" 2>/dev/null || true
else
  echo "$cmd $*" >> "${CMUX_CALLS_LOG:-/dev/null}"
fi
EOF
chmod +x "$TMP/cmux"

STATE_FILE="$TMP/reap.state"

# ----------------------------------------------------------------
# TC (a): ✅ done 마커 → close-surface 호출 + "reaped" 출력 + exit 0
printf '✅ done\nsome output\n' > "$TMP/screen.txt"
> "$TMP/calls.log"
> "$STATE_FILE"
exit_code=99
stdout_out=$(CMUX_BIN="$TMP/cmux" \
  CMUX_SCREEN_FILE="$TMP/screen.txt" \
  CMUX_CALLS_LOG="$TMP/calls.log" \
  CBP_STATE_FILE="$STATE_FILE" \
  bash "$SCRIPT" reap --pane=surface:5 --idle=0 --timeout=5 2>/dev/null) && exit_code=0 || exit_code=$?
check "TC-a: done 화면 → exit 0" "0" "$exit_code"
close_called=$(grep -c "close-surface --surface surface:5" "$TMP/calls.log" 2>/dev/null || echo 0)
check "TC-a: close-surface surface:5 호출됨" "1" "$close_called"
check_contains "TC-a: 'reaped' 출력 포함" "reaped" "$stdout_out"

# ----------------------------------------------------------------
# TC (b): 마커 없음(일반 prompt) → close-surface 미호출 + "not done" 출력 + exit 0
printf '❯\nsome regular output\n' > "$TMP/screen.txt"
> "$TMP/calls.log"
exit_code=99
stdout_out=$(CMUX_BIN="$TMP/cmux" \
  CMUX_SCREEN_FILE="$TMP/screen.txt" \
  CMUX_CALLS_LOG="$TMP/calls.log" \
  CBP_STATE_FILE="$STATE_FILE" \
  bash "$SCRIPT" reap --pane=surface:5 --idle=0 --timeout=5 2>/dev/null) && exit_code=0 || exit_code=$?
check "TC-b: 마커 없음 → exit 0" "0" "$exit_code"
close_called=$(grep -c "close-surface" "$TMP/calls.log" 2>/dev/null || true)
check "TC-b: close-surface 미호출" "0" "$close_called"
check_contains "TC-b: 'not done' 출력 포함" "not done" "$stdout_out"

# ----------------------------------------------------------------
# TC (c): CMUX_SURFACE_ID=surface:5 + reap --pane=surface:5 → 자기 surface 거부 (exit 2)
printf '✅ done\n' > "$TMP/screen.txt"
> "$TMP/calls.log"
exit_code=0
CMUX_BIN="$TMP/cmux" \
  CMUX_SCREEN_FILE="$TMP/screen.txt" \
  CMUX_SURFACE_ID="surface:5" \
  CBP_STATE_FILE="$STATE_FILE" \
  bash "$SCRIPT" reap --pane=surface:5 --idle=0 --timeout=5 2>/dev/null || exit_code=$?
check "TC-c: 자기 surface reap → exit 2 거부" "2" "$exit_code"

# ----------------------------------------------------------------
# TC (d): CBP_REAP_DRY_RUN=1 + done 화면 → close 안 함 + "would reap" 출력 + exit 0
printf '✅ done\n' > "$TMP/screen.txt"
> "$TMP/calls.log"
exit_code=99
stdout_out=$(CMUX_BIN="$TMP/cmux" \
  CMUX_SCREEN_FILE="$TMP/screen.txt" \
  CMUX_CALLS_LOG="$TMP/calls.log" \
  CBP_STATE_FILE="$STATE_FILE" \
  CBP_REAP_DRY_RUN=1 \
  bash "$SCRIPT" reap --pane=surface:5 --idle=0 --timeout=5 2>/dev/null) && exit_code=0 || exit_code=$?
check "TC-d: dry-run → exit 0" "0" "$exit_code"
close_called=$(grep -c "close-surface" "$TMP/calls.log" 2>/dev/null || true)
check "TC-d: dry-run → close-surface 미호출" "0" "$close_called"
check_contains "TC-d: dry-run → 'would reap' 출력" "would reap" "$stdout_out"

# ----------------------------------------------------------------
# TC (a2): ⏺ ✅ prefix (Claude TUI 렌더 형식) → reaped
printf '⏺ ✅ reap-done-pattern\n' > "$TMP/screen.txt"
> "$TMP/calls.log"
exit_code=99
stdout_out=$(CMUX_BIN="$TMP/cmux" \
  CMUX_SCREEN_FILE="$TMP/screen.txt" \
  CMUX_CALLS_LOG="$TMP/calls.log" \
  CBP_STATE_FILE="$STATE_FILE" \
  bash "$SCRIPT" reap --pane=surface:5 --idle=0 --timeout=5 2>/dev/null) && exit_code=0 || exit_code=$?
check "TC-a2: ⏺ ✅ prefix → exit 0" "0" "$exit_code"
close_called=$(grep -c "close-surface --surface surface:5" "$TMP/calls.log" 2>/dev/null || echo 0)
check "TC-a2: ⏺ ✅ prefix → close-surface 호출" "1" "$close_called"
check_contains "TC-a2: ⏺ ✅ prefix → 'reaped' 출력" "reaped" "$stdout_out"

# ----------------------------------------------------------------
# TC (a3): 선두 공백 2칸 ✅ (들여쓰기) → reaped
printf '  ✅ reap-done-pattern\n' > "$TMP/screen.txt"
> "$TMP/calls.log"
exit_code=99
stdout_out=$(CMUX_BIN="$TMP/cmux" \
  CMUX_SCREEN_FILE="$TMP/screen.txt" \
  CMUX_CALLS_LOG="$TMP/calls.log" \
  CBP_STATE_FILE="$STATE_FILE" \
  bash "$SCRIPT" reap --pane=surface:5 --idle=0 --timeout=5 2>/dev/null) && exit_code=0 || exit_code=$?
check "TC-a3: 들여쓰기 ✅ → exit 0" "0" "$exit_code"
close_called=$(grep -c "close-surface --surface surface:5" "$TMP/calls.log" 2>/dev/null || echo 0)
check "TC-a3: 들여쓰기 ✅ → close-surface 호출" "1" "$close_called"
check_contains "TC-a3: 들여쓰기 ✅ → 'reaped' 출력" "reaped" "$stdout_out"

# ----------------------------------------------------------------
# TC (e): dead surface — read-screen 가 비0 exit 반환 → stdout "died" 포함 + exit 5
# 별도 cmux mock: read-screen 가 exit 1 (not a terminal)
cat > "$TMP/cmux-dead" << 'DEADEOF'
#!/usr/bin/env bash
cmd="$1"; shift
if [ "$cmd" = "read-screen" ]; then
  echo "Terminal surface not found" >&2
  exit 1
else
  echo "$cmd $*" >> "${CMUX_CALLS_LOG:-/dev/null}"
fi
DEADEOF
chmod +x "$TMP/cmux-dead"

> "$TMP/calls.log"
exit_code=0
stdout_out=$(CMUX_BIN="$TMP/cmux-dead" \
  CMUX_CALLS_LOG="$TMP/calls.log" \
  CBP_STATE_FILE="$STATE_FILE" \
  bash "$SCRIPT" reap --pane=surface:9 --idle=0 --timeout=5 2>/dev/null) || exit_code=$?
check "TC-e: dead surface → exit 5" "5" "$exit_code"
check_contains "TC-e: dead surface → stdout 'died' 포함" "died" "$stdout_out"
close_called=$(grep -c "close-surface" "$TMP/calls.log" 2>/dev/null || true)
check "TC-e: dead surface → close-surface 미호출" "0" "$close_called"

# ----------------------------------------------------------------
# TC (f): dead surface (died exit5) → state file 에서 해당 surface ref 제거됨
cat > "$TMP/cmux-dead2" << 'DEADEOF2'
#!/usr/bin/env bash
cmd="$1"; shift
if [ "$cmd" = "read-screen" ]; then
  echo "Terminal surface not found" >&2
  exit 1
else
  echo "$cmd $*" >> "${CMUX_CALLS_LOG:-/dev/null}"
fi
DEADEOF2
chmod +x "$TMP/cmux-dead2"

STATE_FILE_F="$TMP/reap-f.state"
# state file 에 surface:9 포함시켜 놓음
printf 'surface=surface:9|name=cbp-aaa|ts=1234567890|ws=ws1\nsurface=surface:10|name=cbp-bbb|ts=1234567891|ws=ws1\n' > "$STATE_FILE_F"

> "$TMP/calls-f.log"
exit_code=0
CMUX_BIN="$TMP/cmux-dead2" \
  CMUX_CALLS_LOG="$TMP/calls-f.log" \
  CBP_STATE_FILE="$STATE_FILE_F" \
  bash "$SCRIPT" reap --pane=surface:9 --idle=0 --timeout=5 2>/dev/null || exit_code=$?
check "TC-f: died exit 5 확인" "5" "$exit_code"
# surface:9 가 state 에서 제거됐는지 확인
state_has_9=$(grep 'surface=surface:9|' "$STATE_FILE_F" 2>/dev/null | wc -l | tr -d ' ')
check "TC-f: died → surface:9 state 에서 제거" "0" "$state_has_9"
# surface:10 은 보존돼야 함
state_has_10=$(grep 'surface=surface:10|' "$STATE_FILE_F" 2>/dev/null | wc -l | tr -d ' ')
check "TC-f: died → surface:10 는 state 보존" "1" "$state_has_10"

# ----------------------------------------------------------------
# --all / argless 용 mock cmux: read-screen 은 --surface 인자별 screen 파일을
# CMUX_SCREEN_DIR 에서 찾아 출력 (surface:101 → surface_101.screen). 그 외 명령은
# CMUX_CALLS_LOG 에 (read-screen 포함) 전부 기록 — grace 자식이 probe 안 됐는지 검증용.
cat > "$TMP/cmux-all" << 'ALLEOF'
#!/usr/bin/env bash
cmd="$1"; shift
if [ "$cmd" = "read-screen" ]; then
  echo "read-screen $*" >> "${CMUX_CALLS_LOG:-/dev/null}"
  surface=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --surface) surface="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  sanitized=$(printf '%s' "$surface" | tr ':' '_')
  cat "${CMUX_SCREEN_DIR:-/tmp}/${sanitized}.screen" 2>/dev/null || true
else
  echo "$cmd $*" >> "${CMUX_CALLS_LOG:-/dev/null}"
fi
ALLEOF
chmod +x "$TMP/cmux-all"

SCREEN_DIR="$TMP/screens"
mkdir -p "$SCREEN_DIR"

# ----------------------------------------------------------------
# TC (g): --all — 자식 2 완료(✅/❌) + 1 진행중 → "reaped 2 / kept 1" + state 반영
printf '✅ done\n' > "$SCREEN_DIR/surface_101.screen"
printf '❌ failed\n' > "$SCREEN_DIR/surface_102.screen"
printf '❯\nstill working\n' > "$SCREEN_DIR/surface_103.screen"

STATE_ALL="$TMP/reap-all.state"
old_ts_g=$(( $(date +%s) - 1000 ))
printf 'surface=surface:101|name=cbp-a|ts=%s|ws=ws1\n' "$old_ts_g" > "$STATE_ALL"
printf 'surface=surface:102|name=cbp-b|ts=%s|ws=ws1\n' "$old_ts_g" >> "$STATE_ALL"
printf 'surface=surface:103|name=cbp-c|ts=%s|ws=ws1\n' "$old_ts_g" >> "$STATE_ALL"

> "$TMP/calls-all.log"
exit_code=99
stdout_out=$(CMUX_BIN="$TMP/cmux-all" \
  CMUX_SCREEN_DIR="$SCREEN_DIR" \
  CMUX_CALLS_LOG="$TMP/calls-all.log" \
  CBP_STATE_FILE="$STATE_ALL" \
  bash "$SCRIPT" reap --all --idle=0 --timeout=5 2>/dev/null) && exit_code=0 || exit_code=$?
check "TC-g: --all → exit 0" "0" "$exit_code"
check_contains "TC-g: --all → 'reaped 2 / kept 1' 요약" "reaped 2 / kept 1" "$stdout_out"
state_remaining_g=$(grep -c 'surface=' "$STATE_ALL" 2>/dev/null || true)
check "TC-g: --all → state 에 진행중 자식 1개만 남음" "1" "$state_remaining_g"
check_contains "TC-g: --all → state 에 surface:103(진행중) 잔존" "surface=surface:103|" "$(cat "$STATE_ALL")"

# ----------------------------------------------------------------
# TC (h): argless == --all 동일 동작
printf '✅ done\n' > "$SCREEN_DIR/surface_201.screen"
printf '✅ done\n' > "$SCREEN_DIR/surface_202.screen"

STATE_ARGLESS="$TMP/reap-argless.state"
old_ts_h=$(( $(date +%s) - 1000 ))
printf 'surface=surface:201|name=cbp-d|ts=%s|ws=ws1\n' "$old_ts_h" > "$STATE_ARGLESS"
printf 'surface=surface:202|name=cbp-e|ts=%s|ws=ws1\n' "$old_ts_h" >> "$STATE_ARGLESS"

> "$TMP/calls-argless.log"
exit_code=99
stdout_out=$(CMUX_BIN="$TMP/cmux-all" \
  CMUX_SCREEN_DIR="$SCREEN_DIR" \
  CMUX_CALLS_LOG="$TMP/calls-argless.log" \
  CBP_STATE_FILE="$STATE_ARGLESS" \
  bash "$SCRIPT" reap 2>/dev/null) && exit_code=0 || exit_code=$?
check "TC-h: argless → exit 0" "0" "$exit_code"
check_contains "TC-h: argless → 'reaped 2 / kept 0' 요약 (argless==--all)" "reaped 2 / kept 0" "$stdout_out"
state_remaining_h=$(grep -c 'surface=' "$STATE_ARGLESS" 2>/dev/null || true)
check "TC-h: argless → state 완전 비워짐" "0" "$state_remaining_h"

# ----------------------------------------------------------------
# TC (i): grace skip — ts 가 방금(now)인 자식은 probe 없이 "grace — kept"
printf '✅ done\n' > "$SCREEN_DIR/surface_301.screen"

STATE_GRACE="$TMP/reap-grace.state"
old_ts_i=$(( $(date +%s) - 1000 ))
now_ts_i=$(date +%s)
printf 'surface=surface:301|name=cbp-f|ts=%s|ws=ws1\n' "$old_ts_i" > "$STATE_GRACE"
printf 'surface=surface:302|name=cbp-g|ts=%s|ws=ws1\n' "$now_ts_i" >> "$STATE_GRACE"

> "$TMP/calls-grace.log"
exit_code=99
stdout_out=$(CMUX_BIN="$TMP/cmux-all" \
  CMUX_SCREEN_DIR="$SCREEN_DIR" \
  CMUX_CALLS_LOG="$TMP/calls-grace.log" \
  CBP_STATE_FILE="$STATE_GRACE" \
  bash "$SCRIPT" reap --all --idle=0 --timeout=5 2>/dev/null) && exit_code=0 || exit_code=$?
check "TC-i: grace → exit 0" "0" "$exit_code"
check_contains "TC-i: grace → 'reaped 1 / kept 1' 요약" "reaped 1 / kept 1" "$stdout_out"
check_contains "TC-i: grace → 'grace — kept' 메시지 포함" "grace — kept" "$stdout_out"
grace_probed=$(grep -c "surface:302" "$TMP/calls-grace.log" 2>/dev/null || true)
check "TC-i: grace 자식은 probe 없음 (calls-log 에 surface:302 없음)" "0" "$grace_probed"
# surface:301(완료, non-grace)은 여전히 probe 되어 reap 돼야 함 — state 에서 제거 확인
state_has_301=$(grep -c 'surface=surface:301|' "$STATE_GRACE" 2>/dev/null || true)
check "TC-i: grace → surface:301(완료, probe 대상) state 에서 제거" "0" "$state_has_301"
# surface:302(grace, kept) 는 state 에 보존
state_has_302=$(grep -c 'surface=surface:302|' "$STATE_GRACE" 2>/dev/null || true)
check "TC-i: grace → surface:302(grace, kept) state 보존" "1" "$state_has_302"

echo ""
echo "ok: $pass/$total passed"
[ "$fail_count" -gt 0 ] && exit 1
exit 0
