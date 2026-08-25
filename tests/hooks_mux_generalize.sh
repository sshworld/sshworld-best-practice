#!/usr/bin/env bash
# tests/hooks_mux_generalize.sh — S4: 6개 훅의 cmux/orca 멀티플렉서 일반화 계약 테스트.
#
# 대상: hooks/cmux-dispatch-hint.sh, hooks/enforce-cmux-dispatch.sh,
#       hooks/enforce-cmux-context.sh, hooks/notify-slice-done.sh,
#       hooks/reap-on-stop.sh, hooks/limit-child-panes.sh
#
# ⚠️ 실제 orca/cmux/tmux 를 절대 호출하지 않는다. 개발 머신이 실제 Orca 세션이라
# (ORCA_TERMINAL_HANDLE/ORCA_WORKSPACE_ID/TERM_PROGRAM=Orca 상시 존재) 매 케이스에서
# 앰비언트 멀티플렉서 신호를 명시적으로 scrub 하고 필요한 것만 다시 주입한다.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HINT="$REPO/hooks/cmux-dispatch-hint.sh"
ENFORCE_DISPATCH="$REPO/hooks/enforce-cmux-dispatch.sh"
REAP_ON_STOP="$REPO/hooks/reap-on-stop.sh"
NOTIFY="$REPO/hooks/notify-slice-done.sh"
LIMIT_PANES="$REPO/hooks/limit-child-panes.sh"
MARKER_RESOLVER="$REPO/scripts/cbp-marker-path.sh"

step() { echo ""; echo "[$1] $2"; }
fail() { echo "❌ FAIL: $1" >&2; exit 1; }

[ -x "$HINT" ]           || fail "hook not executable: $HINT"
[ -x "$ENFORCE_DISPATCH" ] || fail "hook not executable: $ENFORCE_DISPATCH"
[ -x "$REAP_ON_STOP" ]   || fail "hook not executable: $REAP_ON_STOP"
[ -x "$NOTIFY" ]         || fail "hook not executable: $NOTIFY"
[ -x "$LIMIT_PANES" ]    || fail "hook not executable: $LIMIT_PANES"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# 앰비언트 멀티플렉서 신호 scrub 목록 — 모든 케이스에서 이걸 먼저 지우고 필요한
# 신호만 다시 얹는다 (env -u ... VAR=val ... cmd 형태로 사용).
SCRUB=(-u CMUX_WORKSPACE_ID -u CMUX_SURFACE_ID -u CMUX_SOCKET -u CMUX_SOCKET_PASSWORD
       -u ORCA_TERMINAL_HANDLE -u ORCA_WORKSPACE_ID -u ORCA_WORKTREE_ID -u TERM_PROGRAM -u TMUX)

git_init_main() {
  local dir="$1"
  git -c init.defaultBranch=main init "$dir" -q 2>/dev/null || git init "$dir" -q
  git -C "$dir" -c user.email=t@e.local -c user.name=tester commit --allow-empty -q -m init
}

DIRECT_EDIT_PLAN='| S1 | foo.kt | direct-edit | updated |'

mk_plan_payload() {
  local plan="$1"
  python3 -c "import json,sys; print(json.dumps({'tool_name':'ExitPlanMode','tool_input':{'plan':sys.argv[1]}}))" "$plan"
}

# ─────────────────────────────────────────────────────────────────
# 1. enforce-cmux-dispatch: orca 신호 + direct-edit 표셀 → exit 2
step 1 "enforce-cmux-dispatch: orca 신호 + direct-edit 표셀 → exit 2"
REPO1="$TMP/repo1"; git_init_main "$REPO1"
PAYLOAD1=$(mk_plan_payload "$DIRECT_EDIT_PLAN")
RC=0
( cd "$REPO1" && printf '%s' "$PAYLOAD1" | env "${SCRUB[@]}" \
    ORCA_WORKSPACE_ID="ows:1" ORCA_TERMINAL_HANDLE="term_x" \
    "$ENFORCE_DISPATCH" >/dev/null 2>"$TMP/err1" ) || RC=$?
[ "$RC" = "2" ] || fail "case1: exit 2 expected, got $RC ($(cat "$TMP/err1" 2>/dev/null))"

# ─────────────────────────────────────────────────────────────────
# 2. 같은 입력 + CBP_DIRECT_EDIT_OK=1 → exit 0
step 2 "enforce-cmux-dispatch: orca 신호 + CBP_DIRECT_EDIT_OK=1 → exit 0"
REPO2="$TMP/repo2"; git_init_main "$REPO2"
RC=0
( cd "$REPO2" && printf '%s' "$PAYLOAD1" | env "${SCRUB[@]}" \
    ORCA_WORKSPACE_ID="ows:1" ORCA_TERMINAL_HANDLE="term_x" CBP_DIRECT_EDIT_OK=1 \
    "$ENFORCE_DISPATCH" >/dev/null 2>/dev/null ) || RC=$?
[ "$RC" = "0" ] || fail "case2: exit 0 expected, got $RC"

# ─────────────────────────────────────────────────────────────────
# 3. 같은 입력 + CMUX_DIRECT_EDIT_OK=1(구버전) → exit 0
step 3 "enforce-cmux-dispatch: orca 신호 + CMUX_DIRECT_EDIT_OK=1(하위호환) → exit 0"
REPO3="$TMP/repo3"; git_init_main "$REPO3"
RC=0
( cd "$REPO3" && printf '%s' "$PAYLOAD1" | env "${SCRUB[@]}" \
    ORCA_WORKSPACE_ID="ows:1" ORCA_TERMINAL_HANDLE="term_x" CMUX_DIRECT_EDIT_OK=1 \
    "$ENFORCE_DISPATCH" >/dev/null 2>/dev/null ) || RC=$?
[ "$RC" = "0" ] || fail "case3: exit 0 expected, got $RC"

# ─────────────────────────────────────────────────────────────────
# 4. 멀티플렉서 신호 전혀 없음 → exit 0 (비-mux 회귀가드)
step 4 "enforce-cmux-dispatch: 멀티플렉서 신호 없음 → exit 0"
REPO4="$TMP/repo4"; git_init_main "$REPO4"
RC=0
( cd "$REPO4" && printf '%s' "$PAYLOAD1" | env "${SCRUB[@]}" \
    "$ENFORCE_DISPATCH" >/dev/null 2>/dev/null ) || RC=$?
[ "$RC" = "0" ] || fail "case4: exit 0 expected, got $RC"

# ─────────────────────────────────────────────────────────────────
# 5. cmux 신호 + direct-edit → exit 2 (cmux 회귀가드)
step 5 "enforce-cmux-dispatch: cmux 신호 + direct-edit 표셀 → exit 2 (회귀)"
REPO5="$TMP/repo5"; git_init_main "$REPO5"
RC=0
( cd "$REPO5" && printf '%s' "$PAYLOAD1" | env "${SCRUB[@]}" \
    CMUX_WORKSPACE_ID="ws:1" \
    "$ENFORCE_DISPATCH" >/dev/null 2>"$TMP/err5" ) || RC=$?
[ "$RC" = "2" ] || fail "case5: exit 2 expected, got $RC ($(cat "$TMP/err5" 2>/dev/null))"

# ─────────────────────────────────────────────────────────────────
# 6. cmux-dispatch-hint: orca → banner 에 orca 언급 / default → 무출력
step 6 "cmux-dispatch-hint: orca 세션 → banner(orca 언급) / default 세션 → 무출력"
OUT6A=$(env "${SCRUB[@]}" ORCA_WORKSPACE_ID="ows:1" ORCA_TERMINAL_HANDLE="term_x" "$HINT" 2>/dev/null)
RC=$?
[ "$RC" = "0" ] || fail "case6a: exit 0 expected, got $RC"
printf '%s' "$OUT6A" | grep -qi "orca" || fail "case6a: orca 세션인데 배너에 orca 없음: $OUT6A"

OUT6B=$(env "${SCRUB[@]}" "$HINT" 2>/dev/null)
RC=$?
[ "$RC" = "0" ] || fail "case6b: exit 0 expected, got $RC"
[ -z "$OUT6B" ] || fail "case6b: default 세션인데 출력 있음: $OUT6B"

# ─────────────────────────────────────────────────────────────────
# 7. reap-on-stop: orca → 기본 pane 바이너리 orca-pane.sh 선택 / cmux → 여전히 cmux-pane.sh
step 7 "reap-on-stop: orca 세션 → orca-pane.sh 기본 선택 (cmux 는 회귀로 cmux-pane.sh 유지)"

make_fixture_tree() {
  local fx="$1"
  mkdir -p "$fx/hooks" "$fx/scripts"
  cp "$REAP_ON_STOP" "$fx/hooks/reap-on-stop.sh"
  chmod +x "$fx/hooks/reap-on-stop.sh"
  cp "$MARKER_RESOLVER" "$fx/scripts/cbp-marker-path.sh"
  cat > "$fx/scripts/cmux-pane.sh" <<'MOCKEOF'
#!/usr/bin/env bash
echo "cmux-pane called: $*" >> "${PANE_CALLS_FILE:-/dev/null}"
ref=""
for a in "$@"; do case "$a" in --pane=*) ref="${a#--pane=}" ;; esac; done
echo "reaped $ref"
exit 0
MOCKEOF
  chmod +x "$fx/scripts/cmux-pane.sh"
  cat > "$fx/scripts/orca-pane.sh" <<'MOCKEOF'
#!/usr/bin/env bash
echo "orca-pane called: $*" >> "${PANE_CALLS_FILE:-/dev/null}"
ref=""
for a in "$@"; do case "$a" in --pane=*) ref="${a#--pane=}" ;; esac; done
echo "reaped $ref"
exit 0
MOCKEOF
  chmod +x "$fx/scripts/orca-pane.sh"
}

FX7="$TMP/fixture7"
make_fixture_tree "$FX7"

PARENT7A="$TMP/parent7a"; git_init_main "$PARENT7A"
printf 'term_abc\nows:1\n' > "$PARENT7A/.git/cbp-slice-done-x"
CALLS7A="$TMP/calls7a"; : > "$CALLS7A"
( cd "$PARENT7A" && env "${SCRUB[@]}" ORCA_WORKSPACE_ID="ows:1" ORCA_TERMINAL_HANDLE="" \
    PANE_CALLS_FILE="$CALLS7A" "$FX7/hooks/reap-on-stop.sh" </dev/null >/dev/null 2>&1 )
grep -q '^orca-pane called' "$CALLS7A" \
  || fail "case7a: orca 세션인데 orca-pane.sh 가 기본 선택되지 않음: $(cat "$CALLS7A" 2>/dev/null)"

PARENT7B="$TMP/parent7b"; git_init_main "$PARENT7B"
printf 'surface:7\nws:1\n' > "$PARENT7B/.git/cbp-slice-done-x"
CALLS7B="$TMP/calls7b"; : > "$CALLS7B"
( cd "$PARENT7B" && env "${SCRUB[@]}" CMUX_WORKSPACE_ID="ws:1" CMUX_SURFACE_ID="" \
    PANE_CALLS_FILE="$CALLS7B" "$FX7/hooks/reap-on-stop.sh" </dev/null >/dev/null 2>&1 )
grep -q '^cmux-pane called' "$CALLS7B" \
  || fail "case7b(회귀): cmux 세션인데 cmux-pane.sh 가 기본 선택되지 않음: $(cat "$CALLS7B" 2>/dev/null)"

# ─────────────────────────────────────────────────────────────────
# 8. notify-slice-done: orca 세션 + ✅ transcript → marker 기록 + line2==ORCA_WORKSPACE_ID
step 8 "notify-slice-done: orca 세션 + ✅ transcript → marker 기록, line2=ORCA_WORKSPACE_ID"

FAKE_ORCA8="$TMP/fake-orca8.sh"
cat > "$FAKE_ORCA8" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$FAKE_ORCA8"

TRANSCRIPT8="$TMP/transcript8.jsonl"
{
  printf '{"type":"user","message":{"content":"go"}}\n'
  printf '{"type":"assistant","message":{"content":[{"type":"text","text":"작업 끝. ✅ done"}]}}\n'
} > "$TRANSCRIPT8"
PAYLOAD8=$(printf '{"transcript_path":"%s"}' "$TRANSCRIPT8")
MDIR8="$TMP/mdir8"

printf '%s' "$PAYLOAD8" | env "${SCRUB[@]}" \
  ORCA_WORKSPACE_ID="ows:9" ORCA_TERMINAL_HANDLE="term_9" ORCA_BIN="$FAKE_ORCA8" \
  CBP_MARKER_DIR="$MDIR8" "$NOTIFY" >/dev/null 2>&1
RC=$?
[ "$RC" = "0" ] || fail "case8: exit 0 expected, got $RC"

MARKER8=$(ls "$MDIR8"/cbp-slice-done-* 2>/dev/null | head -1)
[ -n "$MARKER8" ] || fail "case8: orca 세션인데 marker 미기록 (dir=$MDIR8: $(ls -A "$MDIR8" 2>/dev/null))"
[ "$(sed -n '2p' "$MARKER8")" = "ows:9" ] || fail "case8: marker line2 != ORCA_WORKSPACE_ID: $(cat "$MARKER8")"

# ─────────────────────────────────────────────────────────────────
# 9. limit-child-panes: orca N개 cbp- 터미널 카운트 + LIMIT 경계 + non-cbp 미카운트
step 9 "limit-child-panes: orca 자식 카운트 = 원장 ∩ 살아있는 terminal"

# 계약 변경 (2026-08-25): 자식 claude TUI 가 터미널 제목을 즉시 덮어쓰므로 title prefix 로는
# 자식을 식별할 수 없다(실측). 카운트 근거는 계보 원장(reap-agents.sh, kind=orca) 이고,
# 그중 지금도 살아있는 terminal 만 센다. 상세 케이스는 tests/orca_child_identity.sh.
LEDGER9="$TMP/ledger9"
mkdir -p "$LEDGER9"
cat > "$LEDGER9/origin9.jsonl" <<'JSONL'
{"kind":"orca","ref":"term_1","ws":null,"pid":null,"label":"s-a","origin":"origin9","ts":1}
{"kind":"orca","ref":"term_2","ws":null,"pid":null,"label":"s-b","origin":"origin9","ts":2}
{"kind":"orca","ref":"term_3","ws":null,"pid":null,"label":"s-c","origin":"origin9","ts":3}
{"kind":"orca","ref":"term_self","ws":null,"pid":null,"label":"self","origin":"origin9","ts":4}
{"kind":"orca","ref":"term_dead","ws":null,"pid":null,"label":"dead","origin":"origin9","ts":5}
JSONL

# 살아있는 terminal 목록: 원장의 term_1..3 + self + 원장에 없는 term_x.
# term_dead 는 원장에 있지만 목록에 없다 → 세면 안 된다.
FAKE_ORCA9="$TMP/fake-orca9.sh"
cat > "$FAKE_ORCA9" <<'EOF'
#!/usr/bin/env bash
cat <<JSON
{"ok":true,"result":{"terminals":[
  {"handle":"term_1","title":"◑ Claude Sonnet with bypass permissions"},
  {"handle":"term_2","title":"◑ Claude Sonnet with bypass permissions"},
  {"handle":"term_3","title":"◑ Claude Sonnet with bypass permissions"},
  {"handle":"term_self","title":"◑ parent"},
  {"handle":"term_x","title":"cbp-남의터미널"}
]}}
JSON
EOF
chmod +x "$FAKE_ORCA9"

PAYLOAD9=$(printf '{"tool_name":"Bash","tool_input":{"command":"./scripts/orca-pane.sh launch zsh"}}')

# 개발 머신에 tmux-pane-mgr 세션이 떠 있을 수 있어 TMUX_COUNT 가 0 이 아닐 수 있다.
# 고정 LIMIT 경계 대신 차단 메시지의 실측 "orca child: N" / "total: T" 를 파싱한다.
RC=0
printf '%s' "$PAYLOAD9" | env "${SCRUB[@]}" CMUX_BIN="/nonexistent-cmux-for-test" ORCA_BIN="$FAKE_ORCA9" \
  CBP_LEDGER_DIR="$LEDGER9" CBP_ORIGIN_ID="origin9" \
  ORCA_TERMINAL_HANDLE="term_self" CLAUDE_MAX_CHILD_PANES=0 "$LIMIT_PANES" >/dev/null 2>"$TMP/err9a" || RC=$?
[ "$RC" = "2" ] || fail "case9a: LIMIT=0 은 항상 차단이어야 함, got $RC"
ORCA_N=$(grep -oE 'orca child: [0-9]+' "$TMP/err9a" | grep -oE '[0-9]+')
TOTAL_N=$(grep -oE 'total: [0-9]+' "$TMP/err9a" | grep -oE '[0-9]+')
[ "$ORCA_N" = "3" ] || fail "case9a: 원장 3개(self 제외, 죽은 ref 제외, 원장 밖 term_x 제외) 기대, got orca child=$ORCA_N ($(cat "$TMP/err9a"))"
echo "ok: case9a: 원장 ∩ 살아있는 terminal = 3 (self·dead·원장밖 전부 제외)"

# 동일 fake + LIMIT=TOTAL_N+1 → 통과
RC=0
printf '%s' "$PAYLOAD9" | env "${SCRUB[@]}" CMUX_BIN="/nonexistent-cmux-for-test" ORCA_BIN="$FAKE_ORCA9" \
  CBP_LEDGER_DIR="$LEDGER9" CBP_ORIGIN_ID="origin9" \
  ORCA_TERMINAL_HANDLE="term_self" CLAUDE_MAX_CHILD_PANES="$((TOTAL_N + 1))" "$LIMIT_PANES" >/dev/null 2>/dev/null || RC=$?
[ "$RC" = "0" ] || fail "case9b: LIMIT=total+1 → exit 0 expected, got $RC"
echo "ok: case9b: 상한 초과 아니면 통과"

# 원장이 비어 있으면(자식 없음) orca 기여 0 — 제목이 cbp- 여도 세지 않는다
LEDGER9E="$TMP/ledger9empty"; mkdir -p "$LEDGER9E"
RC=0
printf '%s' "$PAYLOAD9" | env "${SCRUB[@]}" CMUX_BIN="/nonexistent-cmux-for-test" ORCA_BIN="$FAKE_ORCA9" \
  CBP_LEDGER_DIR="$LEDGER9E" CBP_ORIGIN_ID="origin9" \
  ORCA_TERMINAL_HANDLE="" CLAUDE_MAX_CHILD_PANES=0 "$LIMIT_PANES" >/dev/null 2>"$TMP/err9c" || RC=$?
[ "$RC" = "2" ] || fail "case9c: LIMIT=0 은 항상 차단이어야 함, got $RC"
ORCA_N_C=$(grep -oE 'orca child: [0-9]+' "$TMP/err9c" | grep -oE '[0-9]+')
[ "$ORCA_N_C" = "0" ] || fail "case9c: 원장이 비면 카운트 0 이어야 함(제목 무관), got orca child=$ORCA_N_C ($(cat "$TMP/err9c"))"
echo "ok: case9c: 원장 비면 0 — title 은 더 이상 근거가 아니다"

echo ""
echo "✅ hooks_mux_generalize: all cases pass"
