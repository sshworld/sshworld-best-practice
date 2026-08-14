#!/usr/bin/env bash
# plan-dev-progress.sh テスト — TDD end-to-end with stub isolation.

set -uo pipefail

# ⚠️ 이 스위트는 plan-dev-session.sh start 를 실제 실행한다. start 는 cmux 환경
# (CMUX_WORKSPACE_ID set)이면 best-effort 로 실제 `cmux-pane.sh reap-orphans` 를
# 호출한다 — 전 workspace 의 자식 state 를 훑어 dead 판정 surface 를 닫는다.
# plan-dev 세션 중 이 테스트를 돌리면 살아있는 자식 surface 가 회수될 수 있다.
export SKIP_CMUX_REAP=1

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO/scripts/plan-dev-progress.sh"
SESSION_BIN_PATH="$REPO/scripts/plan-dev-session.sh"
CMUX_PANE_BIN_PATH="$REPO/scripts/cmux-pane.sh"

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

[ -x "$SCRIPT" ] || { echo "FAIL: $SCRIPT not executable" >&2; exit 1; }

setup_tmp_repo() {
  local dir
  dir="$(mktemp -d)"
  git -C "$dir" init -q
  git -C "$dir" config user.email "test@example.com"
  git -C "$dir" config user.name "Test"
  git -C "$dir" commit --allow-empty -m "init" -q
  echo "$dir"
}

# ──────────────────────────────────────────────
# Shared setup for TC1-5 (sequential state)
# ──────────────────────────────────────────────
echo "[setup] TC1-5 공유 tmpdir + stub"
SHARED_DIR="$(setup_tmp_repo)"
STUB_LOG="$SHARED_DIR/cmux-calls.txt"
CMUX_STUB="$SHARED_DIR/cmux-stub.sh"
cat > "$CMUX_STUB" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "$STUB_LOG"
EOF
chmod +x "$CMUX_STUB"

run_progress() {
  (cd "$SHARED_DIR"
    TMUX="" CMUX_WORKSPACE_ID=test-ws \
    CMUX_BIN="$CMUX_STUB" \
    PLAN_DEV_SESSION_BIN="$SESSION_BIN_PATH" \
    CMUX_PANE_BIN="$CMUX_PANE_BIN_PATH" \
    "$SCRIPT" "$@"
  )
}

# ──────────────────────────────────────────────
# TC1: start --total=3
# ──────────────────────────────────────────────
echo "[TC1] start --total=3"
run_progress start --total=3 2>/dev/null

TOTAL1=$(cd "$SHARED_DIR"; "$SESSION_BIN_PATH" query --key=total_slices 2>/dev/null)
DONE1=$(cd "$SHARED_DIR"; "$SESSION_BIN_PATH" query --key=done_slices 2>/dev/null)
check "TC1: total_slices=3" "3" "$TOTAL1"
check "TC1: done_slices=0" "0" "$DONE1"

LAST_CALL1=$(tail -1 "$STUB_LOG" 2>/dev/null || echo "")
check_contains "TC1: set-status plan-dev 0/3" "set-status plan-dev 0/3" "$LAST_CALL1"
check_contains "TC1: --icon sparkle" "--icon sparkle" "$LAST_CALL1"

# ──────────────────────────────────────────────
# TC2: tick --slug=foo (done=1)
# ──────────────────────────────────────────────
echo "[TC2] tick --slug=foo"
> "$STUB_LOG"
run_progress tick --slug=foo 2>/dev/null

DONE2=$(cd "$SHARED_DIR"; "$SESSION_BIN_PATH" query --key=done_slices 2>/dev/null)
check "TC2: done_slices=1" "1" "$DONE2"

CALLS2=$(cat "$STUB_LOG" 2>/dev/null || echo "")
check_contains "TC2: set-status 1/3 (33%)" "set-status plan-dev 1/3 (33%) --icon sparkle" "$CALLS2"
check_contains "TC2: notify title slice ✅ foo" "notify --title slice ✅ foo" "$CALLS2"
check_contains "TC2: notify body 1/3 (33%)" "--body 1/3 (33%)" "$CALLS2"

# ──────────────────────────────────────────────
# TC3: tick --slug=bar (done=2) — stdout check
# ──────────────────────────────────────────────
echo "[TC3] tick --slug=bar (stdout check)"
> "$STUB_LOG"
OUT3=$(run_progress tick --slug=bar 2>/dev/null)

DONE3=$(cd "$SHARED_DIR"; "$SESSION_BIN_PATH" query --key=done_slices 2>/dev/null)
check "TC3: done_slices=2" "2" "$DONE3"
check_contains "TC3: stdout 2/3 (66%)" "2/3 (66%)" "$OUT3"

CALLS3=$(cat "$STUB_LOG" 2>/dev/null || echo "")
check_contains "TC3: set-status 2/3 (66%)" "set-status plan-dev 2/3 (66%) --icon sparkle" "$CALLS3"

# ──────────────────────────────────────────────
# TC4: tick (no slug, done=3)
# ──────────────────────────────────────────────
echo "[TC4] tick (no slug, done=3)"
> "$STUB_LOG"
run_progress tick 2>/dev/null

DONE4=$(cd "$SHARED_DIR"; "$SESSION_BIN_PATH" query --key=done_slices 2>/dev/null)
check "TC4: done_slices=3" "3" "$DONE4"

CALLS4=$(cat "$STUB_LOG" 2>/dev/null || echo "")
check_contains "TC4: set-status 3/3 (100%)" "set-status plan-dev 3/3 (100%) --icon sparkle" "$CALLS4"
check_not_contains "TC4: no notify (no slug)" "notify" "$CALLS4"

# ──────────────────────────────────────────────
# TC5: show — substring check
# ──────────────────────────────────────────────
echo "[TC5] show"
SHOW_OUT=$(run_progress show 2>/dev/null)
check_contains "TC5: show work_branch" "work_branch" "$SHOW_OUT"
check_contains "TC5: show total_slices" "total_slices" "$SHOW_OUT"
check_contains "TC5: show done_slices" "done_slices" "$SHOW_OUT"

rm -rf "$SHARED_DIR"

# ──────────────────────────────────────────────
# TC6: PROGRESS_DRY_RUN=1 tick
# ──────────────────────────────────────────────
echo "[TC6] PROGRESS_DRY_RUN=1 tick"
TMPDIR6="$(setup_tmp_repo)"
STUB_LOG6="$TMPDIR6/cmux-calls.txt"
STUB6="$TMPDIR6/cmux-stub.sh"
cat > "$STUB6" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "$STUB_LOG6"
EOF
chmod +x "$STUB6"

# setup: create marker (DRY_RUN suppresses set-status call to stub)
(cd "$TMPDIR6"
  TMUX="" CMUX_WORKSPACE_ID=test-ws \
  CMUX_BIN="$STUB6" \
  PLAN_DEV_SESSION_BIN="$SESSION_BIN_PATH" \
  CMUX_PANE_BIN="$CMUX_PANE_BIN_PATH" \
  PROGRESS_DRY_RUN=1 \
  "$SCRIPT" start --total=3 2>/dev/null
)
> "$STUB_LOG6"

OUT6=$(cd "$TMPDIR6"
  TMUX="" CMUX_WORKSPACE_ID=test-ws \
  CMUX_BIN="$STUB6" \
  PLAN_DEV_SESSION_BIN="$SESSION_BIN_PATH" \
  CMUX_PANE_BIN="$CMUX_PANE_BIN_PATH" \
  PROGRESS_DRY_RUN=1 \
  "$SCRIPT" tick 2>/dev/null
)
check_contains "TC6: stdout DRY_RUN:" "DRY_RUN:" "$OUT6"
if [ -s "$STUB_LOG6" ]; then
  echo "FAIL: TC6: stub called (side-effect file non-empty)" >&2
  fail_count=$((fail_count + 1))
else
  echo "ok: TC6: stub not called"
  pass=$((pass + 1))
fi
rm -rf "$TMPDIR6"

# ──────────────────────────────────────────────
# TC7: non-cmux env mock
# ──────────────────────────────────────────────
echo "[TC7] non-cmux env mock (detect-pane-env → default)"
TMPDIR7="$(setup_tmp_repo)"
STUB_LOG7="$TMPDIR7/cmux-calls.txt"

# stub: ping → exit 1 (non-cmux), other calls → record to log
STUB7="$TMPDIR7/cmux-stub.sh"
cat > "$STUB7" <<EOF
#!/usr/bin/env bash
if [ "\${1:-}" = "ping" ]; then
  exit 1
fi
echo "\$@" >> "$STUB_LOG7"
EOF
chmod +x "$STUB7"

# setup: create marker using cmux env + DRY_RUN (no real cmux calls)
(cd "$TMPDIR7"
  TMUX="" CMUX_WORKSPACE_ID=test-ws \
  CMUX_BIN="$STUB7" \
  PLAN_DEV_SESSION_BIN="$SESSION_BIN_PATH" \
  CMUX_PANE_BIN="$CMUX_PANE_BIN_PATH" \
  PROGRESS_DRY_RUN=1 \
  "$SCRIPT" start --total=3 2>/dev/null
)

# tick in non-cmux env: TMUX unset, CMUX vars unset, ping fails → detect "default"
RC7=0
(cd "$TMPDIR7"
  unset TMUX CMUX_WORKSPACE_ID CMUX_SURFACE_ID CMUX_SOCKET CMUX_SOCKET_PASSWORD 2>/dev/null || true
  CMUX_BIN="$STUB7" \
  PLAN_DEV_SESSION_BIN="$SESSION_BIN_PATH" \
  CMUX_PANE_BIN="$CMUX_PANE_BIN_PATH" \
  "$SCRIPT" tick
) 2>/dev/null || RC7=$?

check "TC7: tick exit 0 in non-cmux" "0" "$RC7"

# set-status / notify must NOT be in stub log (ping calls are not logged)
if [ -f "$STUB_LOG7" ] && grep -qE '^(set-status|notify)' "$STUB_LOG7" 2>/dev/null; then
  echo "FAIL: TC7: stub called with set-status/notify in non-cmux env" >&2
  fail_count=$((fail_count + 1))
else
  echo "ok: TC7: stub not called for set-status/notify"
  pass=$((pass + 1))
fi
rm -rf "$TMPDIR7"

# ──────────────────────────────────────────────
# TC8: tick — marker 부재 (SESSION_BIN stub: 마커 없음 stderr + exit 1)
# ──────────────────────────────────────────────
echo "[TC8] tick marker 부재 → exit 0, skip"
TMPDIR8="$(setup_tmp_repo)"
STUB_LOG8="$TMPDIR8/cmux-calls.txt"
STUB8="$TMPDIR8/cmux-stub.sh"
cat > "$STUB8" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "$STUB_LOG8"
EOF
chmod +x "$STUB8"

SESSION_STUB8="$TMPDIR8/session-stub.sh"
cat > "$SESSION_STUB8" <<'EOF'
#!/usr/bin/env bash
echo "plan-dev-session: 마커 없음" >&2
exit 1
EOF
chmod +x "$SESSION_STUB8"

RC8=0
ERR8=$(cd "$TMPDIR8"
  TMUX="" CMUX_WORKSPACE_ID=test-ws \
  CMUX_BIN="$STUB8" \
  PLAN_DEV_SESSION_BIN="$SESSION_STUB8" \
  CMUX_PANE_BIN="$CMUX_PANE_BIN_PATH" \
  "$SCRIPT" tick 2>&1 1>/dev/null
) || RC8=$?

check "TC8: tick exit 0" "0" "$RC8"
check_contains "TC8: stderr 마커 없음 — tick skip" "마커 없음 — tick skip" "$ERR8"
if [ -s "$STUB_LOG8" ]; then
  echo "FAIL: TC8: cmux stub called (set-status/notify)" >&2
  fail_count=$((fail_count + 1))
else
  echo "ok: TC8: cmux stub not called"
  pass=$((pass + 1))
fi
rm -rf "$TMPDIR8"

# ──────────────────────────────────────────────
# TC9: tick — generic 실패 (SESSION_BIN stub: 다른 stderr + exit 1)
# ──────────────────────────────────────────────
echo "[TC9] tick generic 실패 → exit 0, skip"
TMPDIR9="$(setup_tmp_repo)"
STUB_LOG9="$TMPDIR9/cmux-calls.txt"
STUB9="$TMPDIR9/cmux-stub.sh"
cat > "$STUB9" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "$STUB_LOG9"
EOF
chmod +x "$STUB9"

SESSION_STUB9="$TMPDIR9/session-stub.sh"
cat > "$SESSION_STUB9" <<'EOF'
#!/usr/bin/env bash
echo "plan-dev-session: json_get 파싱 실패" >&2
exit 1
EOF
chmod +x "$SESSION_STUB9"

RC9=0
ERR9=$(cd "$TMPDIR9"
  TMUX="" CMUX_WORKSPACE_ID=test-ws \
  CMUX_BIN="$STUB9" \
  PLAN_DEV_SESSION_BIN="$SESSION_STUB9" \
  CMUX_PANE_BIN="$CMUX_PANE_BIN_PATH" \
  "$SCRIPT" tick 2>&1 1>/dev/null
) || RC9=$?

check "TC9: tick exit 0" "0" "$RC9"
check_contains "TC9: stderr session progress 실패 — tick skip" "session progress 실패 — tick skip" "$ERR9"
check_contains "TC9: stderr 원본 SESSION_BIN 메시지 전달" "json_get 파싱 실패" "$ERR9"
check_not_contains "TC9: 마커 없음 문구 아님" "마커 없음 — tick skip" "$ERR9"
if [ -s "$STUB_LOG9" ]; then
  echo "FAIL: TC9: cmux stub called (set-status/notify)" >&2
  fail_count=$((fail_count + 1))
else
  echo "ok: TC9: cmux stub not called"
  pass=$((pass + 1))
fi
rm -rf "$TMPDIR9"

# ──────────────────────────────────────────────
# TC10: start — SESSION_BIN start 실패(exit 2) → pill 미push, rc 전파
# ──────────────────────────────────────────────
echo "[TC10] start 실패 → rc 전파, pill 미push"
TMPDIR10="$(setup_tmp_repo)"
STUB_LOG10="$TMPDIR10/cmux-calls.txt"
STUB10="$TMPDIR10/cmux-stub.sh"
cat > "$STUB10" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "$STUB_LOG10"
EOF
chmod +x "$STUB10"

SESSION_STUB10="$TMPDIR10/session-stub.sh"
cat > "$SESSION_STUB10" <<'EOF'
#!/usr/bin/env bash
echo "plan-dev-session: detached HEAD" >&2
exit 2
EOF
chmod +x "$SESSION_STUB10"

RC10=0
(cd "$TMPDIR10"
  TMUX="" CMUX_WORKSPACE_ID=test-ws \
  CMUX_BIN="$STUB10" \
  PLAN_DEV_SESSION_BIN="$SESSION_STUB10" \
  CMUX_PANE_BIN="$CMUX_PANE_BIN_PATH" \
  "$SCRIPT" start --total=3 2>/dev/null
) || RC10=$?

check "TC10: start exit 2 전파" "2" "$RC10"
if [ -s "$STUB_LOG10" ]; then
  echo "FAIL: TC10: cmux stub called (pill pushed despite start 실패)" >&2
  fail_count=$((fail_count + 1))
else
  echo "ok: TC10: cmux stub not called"
  pass=$((pass + 1))
fi
rm -rf "$TMPDIR10"

# ──────────────────────────────────────────────
# TC11: tick — tmp_err EXIT-trap 스코프 버그 가드 (unbound variable 없음 + TMPDIR leak 없음)
# ──────────────────────────────────────────────
echo "[TC11] tick — tmp_err unbound/leak 가드"
TMPDIR11="$(setup_tmp_repo)"
STUB_LOG11="$TMPDIR11/cmux-calls.txt"
STUB11="$TMPDIR11/cmux-stub.sh"
cat > "$STUB11" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "$STUB_LOG11"
EOF
chmod +x "$STUB11"

(cd "$TMPDIR11"
  TMUX="" CMUX_WORKSPACE_ID=test-ws \
  CMUX_BIN="$STUB11" \
  PLAN_DEV_SESSION_BIN="$SESSION_BIN_PATH" \
  CMUX_PANE_BIN="$CMUX_PANE_BIN_PATH" \
  "$SCRIPT" start --total=3 2>/dev/null
)

ISOLATED_TMPDIR11="$(mktemp -d)"
ERR11=$(cd "$TMPDIR11"
  TMUX="" CMUX_WORKSPACE_ID=test-ws \
  CMUX_BIN="$STUB11" \
  PLAN_DEV_SESSION_BIN="$SESSION_BIN_PATH" \
  CMUX_PANE_BIN="$CMUX_PANE_BIN_PATH" \
  TMPDIR="$ISOLATED_TMPDIR11" \
  "$SCRIPT" tick --slug=tc11 2>&1 1>/dev/null
)

check_not_contains "TC11: stderr 에 unbound variable 없음" "unbound variable" "$ERR11"

LEFTOVER11="$(find "$ISOLATED_TMPDIR11" -mindepth 1 2>/dev/null)"
check "TC11: 전용 TMPDIR 에 잔여 파일 없음 (leak 가드)" "" "$LEFTOVER11"

DONE11=$(cd "$TMPDIR11"; "$SESSION_BIN_PATH" query --key=done_slices 2>/dev/null)
check "TC11: done_slices=1 (tick 정상 동작)" "1" "$DONE11"

rm -rf "$ISOLATED_TMPDIR11" "$TMPDIR11"

# ──────────────────────────────────────────────
echo ""
total=$((pass + fail_count))
echo "passed: $pass / $total"
if [ "$fail_count" -gt 0 ]; then
  echo "❌ FAIL ($fail_count failures)"
  exit 1
fi
echo "PASS"
