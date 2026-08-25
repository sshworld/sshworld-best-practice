#!/usr/bin/env bash
# cmux-pane_notify.sh — notify / set-status subcommand 검증
#
# 실제 cmux 호출 없음 — CMUX_BIN=echo stub 또는 PROGRESS_DRY_RUN=1.
#
# ⚠️ 이 스위트가 "cmux 환경" 을 성립시키는 유일한 근거는 CMUX_BIN 스텁의 ping 성공이다
# (cmux-pane.sh 의 _skip_if_non_cmux 가 detect-pane-env.sh 결과 != cmux 면 통째로 exit 0).
# detect-pane-env 는 orca 주입 변수를 cmux ping 보다 **앞서** 검사하므로, 개발 머신이
# 실제 Orca 세션이면 주변 ORCA_*/TERM_PROGRAM 이 먼저 잡혀 detect 가 orca 를 반환하고
# 모든 케이스가 빈 출력으로 무너진다. 스위트 시작 시 명시적으로 걷어낸다.

set -uo pipefail

unset ORCA_TERMINAL_HANDLE ORCA_WORKSPACE_ID ORCA_WORKTREE_ID ORCA_PANE_KEY ORCA_TAB_ID TERM_PROGRAM 2>/dev/null || true

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO/scripts/cmux-pane.sh"

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
    echo "FAIL: $desc — expected substring='$needle' in output='$haystack'" >&2
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

[ -f "$SCRIPT" ] || { echo "FAIL: $SCRIPT 없음" >&2; exit 1; }

# ----------------------------------------------------------------
# notify — --title 만
result=$(CMUX_BIN=echo bash "$SCRIPT" notify --title="hello" 2>/dev/null)
check_contains "notify --title: cmux notify 호출" "notify" "$result"
check_contains "notify --title: --title hello" "--title hello" "$result"
check_not_contains "notify --title: --body 미포함" "--body" "$result"
check_not_contains "notify --title: --subtitle 미포함" "--subtitle" "$result"

# ----------------------------------------------------------------
# notify --title + --body + --subtitle + --workspace + --surface
result=$(CMUX_BIN=echo bash "$SCRIPT" notify \
  --title="T" --body="B" --subtitle="S" \
  --workspace=workspace:1 --surface=surface:3 2>/dev/null)
check_contains "notify 전체 옵션: --title T" "--title T" "$result"
check_contains "notify 전체 옵션: --body B" "--body B" "$result"
check_contains "notify 전체 옵션: --subtitle S" "--subtitle S" "$result"
check_contains "notify 전체 옵션: --workspace workspace:1" "--workspace workspace:1" "$result"
check_contains "notify 전체 옵션: --surface surface:3" "--surface surface:3" "$result"

# ----------------------------------------------------------------
# notify --title 없음 → exit 2
exit_code=0
CMUX_BIN=echo bash "$SCRIPT" notify --body=only-body 2>/dev/null || exit_code=$?
check "notify --title 누락 → exit 2" "2" "$exit_code"

# ----------------------------------------------------------------
# notify PROGRESS_DRY_RUN — 실제 stub 호출 없음 (side-effect 부재로 검증)
TMPDIR_X=$(mktemp -d)
STUB="$TMPDIR_X/cmux-stub.sh"
cat > "$STUB" <<EOF
#!/usr/bin/env bash
touch "$TMPDIR_X/called"
EOF
chmod +x "$STUB"
result=$(PROGRESS_DRY_RUN=1 CMUX_BIN="$STUB" \
  bash "$SCRIPT" notify --title="dry" --body="run" 2>/dev/null)
check_contains "notify DRY_RUN: DRY_RUN prefix" "DRY_RUN:" "$result"
check_contains "notify DRY_RUN: cmux notify 명령 echo" "notify --title dry --body run" "$result"
if [ -f "$TMPDIR_X/called" ]; then
  echo "FAIL: notify DRY_RUN: stub 호출됨" >&2
  fail_count=$((fail_count + 1))
else
  echo "ok: notify DRY_RUN: stub 호출 없음"
  pass=$((pass + 1))
fi

# ----------------------------------------------------------------
# set-status — 최소 (key value)
result=$(CMUX_BIN=echo bash "$SCRIPT" set-status plan-dev "2/3 (66%)" 2>/dev/null)
check_contains "set-status: cmux set-status 호출" "set-status" "$result"
check_contains "set-status: key plan-dev" "set-status plan-dev" "$result"
check_contains "set-status: value 2/3 (66%)" "2/3 (66%)" "$result"
check_not_contains "set-status: --icon 미포함" "--icon" "$result"
check_not_contains "set-status: --color 미포함" "--color" "$result"

# ----------------------------------------------------------------
# set-status + --icon + --color + --workspace
result=$(CMUX_BIN=echo bash "$SCRIPT" set-status build compiling \
  --icon=hammer --color="#ff9500" --workspace=workspace:2 2>/dev/null)
check_contains "set-status 전체: key+value" "set-status build compiling" "$result"
check_contains "set-status 전체: --icon hammer" "--icon hammer" "$result"
check_contains "set-status 전체: --color #ff9500" "--color #ff9500" "$result"
check_contains "set-status 전체: --workspace workspace:2" "--workspace workspace:2" "$result"

# ----------------------------------------------------------------
# set-status — value 누락 → exit 2
exit_code=0
CMUX_BIN=echo bash "$SCRIPT" set-status only-key 2>/dev/null || exit_code=$?
check "set-status value 누락 → exit 2" "2" "$exit_code"

# ----------------------------------------------------------------
# set-status PROGRESS_DRY_RUN — stub 미호출 (side-effect 부재)
TMPDIR_Y=$(mktemp -d)
STUB_Y="$TMPDIR_Y/cmux-stub.sh"
cat > "$STUB_Y" <<EOF
#!/usr/bin/env bash
touch "$TMPDIR_Y/called"
EOF
chmod +x "$STUB_Y"
result=$(PROGRESS_DRY_RUN=1 CMUX_BIN="$STUB_Y" \
  bash "$SCRIPT" set-status plan-dev "1/1" --icon=sparkle 2>/dev/null)
check_contains "set-status DRY_RUN: DRY_RUN prefix" "DRY_RUN:" "$result"
check_contains "set-status DRY_RUN: 명령 echo" "set-status plan-dev 1/1 --icon sparkle" "$result"
if [ -f "$TMPDIR_Y/called" ]; then
  echo "FAIL: set-status DRY_RUN: stub 호출됨" >&2
  fail_count=$((fail_count + 1))
else
  echo "ok: set-status DRY_RUN: stub 호출 없음"
  pass=$((pass + 1))
fi

total=$((pass + fail_count))
echo
echo "passed: $pass / $total"
if [ "$fail_count" -gt 0 ]; then
  echo "❌ FAIL ($fail_count failures)"
  exit 1
fi
echo "✅"
