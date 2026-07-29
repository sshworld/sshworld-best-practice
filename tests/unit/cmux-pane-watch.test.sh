#!/usr/bin/env bash
# cmux-pane-watch.test.sh — do_watch (marker fast-path + reap --all 벨트) 감시 루프 검증

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

[ -f "$SCRIPT" ] || { echo "FAIL: $SCRIPT 없음" >&2; exit 1; }

total=15

# marker 경로가 git-common-dir 기반 — TMP 안에 git init 한 디렉토리에서(cd) 실행
GITREPO="$TMP/repo"
mkdir -p "$GITREPO"
(cd "$GITREPO" && git init -q -b main)

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

# ----------------------------------------------------------------
# TC1: marker fast-path — 자식 state 등록(surface:5) + marker(line1=surface:5, line2=ws1)
#      + 화면 ✅ → exit 0, 출력에 reaped, close-surface 1회 호출
STATE1="$TMP/watch1.state"
old_ts=$(( $(date +%s) - 1000 ))
printf 'surface=surface:5|name=cbp-a|ts=%s|ws=ws1\n' "$old_ts" > "$STATE1"
printf '✅ done\n' > "$TMP/screen1.txt"
MARKER1="$GITREPO/.git/cbp-slice-done-test1"
printf 'surface:5\nws1\n' > "$MARKER1"
> "$TMP/calls1.log"

exit_code=99
stdout_out=$(cd "$GITREPO" && CMUX_BIN="$TMP/cmux" \
  CMUX_SCREEN_FILE="$TMP/screen1.txt" \
  CMUX_CALLS_LOG="$TMP/calls1.log" \
  CBP_STATE_FILE="$STATE1" \
  CMUX_WORKSPACE_ID="ws1" \
  bash "$SCRIPT" watch --interval=0 --max-iter=1 --idle=0 --timeout=5 2>/dev/null) && exit_code=0 || exit_code=$?
check "TC1: marker fast-path → exit 0" "0" "$exit_code"
check_contains "TC1: 출력에 'reaped' 포함" "reaped" "$stdout_out"
close_called1=$(grep -c "close-surface --surface surface:5" "$TMP/calls1.log" 2>/dev/null || true)
check "TC1: close-surface surface:5 1회 호출" "1" "$close_called1"

# ----------------------------------------------------------------
# TC2: belt 경로 — marker 없음 + 화면 ✅ 자식 → iter 1 에서 exit 0
STATE2="$TMP/watch2.state"
printf 'surface=surface:6|name=cbp-b|ts=%s|ws=ws1\n' "$old_ts" > "$STATE2"
printf '✅ done\n' > "$TMP/screen2.txt"
> "$TMP/calls2.log"

exit_code=99
stdout_out=$(cd "$GITREPO" && CMUX_BIN="$TMP/cmux" \
  CMUX_SCREEN_FILE="$TMP/screen2.txt" \
  CMUX_CALLS_LOG="$TMP/calls2.log" \
  CBP_STATE_FILE="$STATE2" \
  CMUX_WORKSPACE_ID="ws1" \
  bash "$SCRIPT" watch --interval=0 --max-iter=1 --idle=0 --timeout=5 2>/dev/null) && exit_code=0 || exit_code=$?
check "TC2: belt 경로 → exit 0" "0" "$exit_code"
check_contains "TC2: 출력에 'reaped 1 / kept 0' 요약" "reaped 1 / kept 0" "$stdout_out"
close_called2=$(grep -c "close-surface --surface surface:6" "$TMP/calls2.log" 2>/dev/null || true)
check "TC2: close-surface surface:6 1회 호출" "1" "$close_called2"

# ----------------------------------------------------------------
# TC3: input-pending — 화면 ✅ 뒤 미제출 텍스트 → exit 6
STATE3="$TMP/watch3.state"
printf 'surface=surface:7|name=cbp-c|ts=%s|ws=ws1\n' "$old_ts" > "$STATE3"
printf '✅ done\n❯ 미제출텍스트\n' > "$TMP/screen3.txt"
> "$TMP/calls3.log"

exit_code=0
stdout_out=$(cd "$GITREPO" && CMUX_BIN="$TMP/cmux" \
  CMUX_SCREEN_FILE="$TMP/screen3.txt" \
  CMUX_CALLS_LOG="$TMP/calls3.log" \
  CBP_STATE_FILE="$STATE3" \
  CMUX_WORKSPACE_ID="ws1" \
  bash "$SCRIPT" watch --interval=0 --max-iter=1 --idle=0 --timeout=5 2>/dev/null) || exit_code=$?
check "TC3: input-pending → exit 6" "6" "$exit_code"
check_contains "TC3: 출력에 'input-pending' 포함" "input-pending" "$stdout_out"
close_called3=$(grep -c "close-surface" "$TMP/calls3.log" 2>/dev/null || true)
check "TC3: input-pending → close-surface 미호출" "0" "$close_called3"

# ----------------------------------------------------------------
# TC4: 에러가드 — reap 출력에 error 포함(화면 텍스트 유입) → exit 7
STATE4="$TMP/watch4.state"
printf 'surface=surface:8|name=cbp-d|ts=%s|ws=ws1\n' "$old_ts" > "$STATE4"
printf 'some error occurred\n' > "$TMP/screen4.txt"
> "$TMP/calls4.log"

exit_code=0
CMUX_BIN="$TMP/cmux" \
  CMUX_SCREEN_FILE="$TMP/screen4.txt" \
  CMUX_CALLS_LOG="$TMP/calls4.log" \
  CBP_STATE_FILE="$STATE4" \
  CMUX_WORKSPACE_ID="ws1" \
  bash -c "cd '$GITREPO' && bash '$SCRIPT' watch --interval=0 --max-iter=1 --idle=0 --timeout=5" >/dev/null 2>/dev/null || exit_code=$?
check "TC4: 에러가드 → exit 7" "7" "$exit_code"
close_called4=$(grep -c "close-surface" "$TMP/calls4.log" 2>/dev/null || true)
check "TC4: 에러가드 → close-surface 미호출" "0" "$close_called4"
state_has_8=$(grep -c 'surface=surface:8|' "$STATE4" 2>/dev/null || true)
check "TC4: 에러가드 → state 에 surface:8 보존" "1" "$state_has_8"

# ----------------------------------------------------------------
# TC5: iter cap — 안 끝나는 자식 + --max-iter=2 → exit 4
STATE5="$TMP/watch5.state"
printf 'surface=surface:9|name=cbp-e|ts=%s|ws=ws1\n' "$old_ts" > "$STATE5"
printf '❯\nstill working\n' > "$TMP/screen5.txt"
> "$TMP/calls5.log"

exit_code=0
CMUX_BIN="$TMP/cmux" \
  CMUX_SCREEN_FILE="$TMP/screen5.txt" \
  CMUX_CALLS_LOG="$TMP/calls5.log" \
  CBP_STATE_FILE="$STATE5" \
  CMUX_WORKSPACE_ID="ws1" \
  bash -c "cd '$GITREPO' && bash '$SCRIPT' watch --interval=0 --max-iter=2 --idle=0 --timeout=5" >/dev/null 2>/dev/null || exit_code=$?
check "TC5: iter cap → exit 4" "4" "$exit_code"
close_called5=$(grep -c "close-surface" "$TMP/calls5.log" 2>/dev/null || true)
check "TC5: iter cap → close-surface 미호출" "0" "$close_called5"
state_has_9=$(grep -c 'surface=surface:9|' "$STATE5" 2>/dev/null || true)
check "TC5: iter cap → state 에 surface:9 보존" "1" "$state_has_9"

echo ""
echo "ok: $pass/$total passed"
[ "$fail_count" -gt 0 ] && exit 1
exit 0
