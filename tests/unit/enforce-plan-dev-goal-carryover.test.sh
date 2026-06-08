#!/usr/bin/env bash
# Unit test: enforce-plan-dev-goal.sh stale-marker carryover 가드 (session 정체성).
# 계약: marker 를 처음 본 session 이 gate_session_id 로 소유.
#   - 미소유(claim): 현재 session 기록 후 정상 gate
#   - 소유 일치(match): 정상 gate
#   - 소유 불일치(orphan): 다른 session 의 stale marker → skip + .bak 이동 (plan 평가 안 함)
#   - session_id 부재(inert): 기존 동작 (가드 미적용)
set -uo pipefail

HOOK="$(cd "$(dirname "$0")/../.." && pwd)/.claude/hooks/enforce-plan-dev-goal.sh"
FAIL=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAIL=1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# 항상 fail 하는 machine-check → match/claim 은 exit 2 가 기대값(가드 통과 = 평가 도달).
mk_plan() {
  cat > "$TMP/plan.md" <<'EOF'
## Goal Statement
<!-- machine-checks -->
```bash
false
```
<!-- /machine-checks -->

**Semantic goal**: dummy.
EOF
}
mk_plan

run() {  # $1=marker_json  $2=session_id(stdin)  → echo "rc=<N>"
  printf '%s' "$1" > "$TMP/session.json"
  local rc=0
  printf '{"session_id":"%s"}' "$2" \
    | CLAUDE_PROJECT_DIR="$TMP" \
      PLAN_DEV_GOAL_SESSION_FILE="$TMP/session.json" \
      PLAN_DEV_GOAL_PLAN_PATH="$TMP/plan.md" \
      SKIP_GOAL_AGENT=1 \
      "$HOOK" >/dev/null 2>&1 || rc=$?
  echo "rc=$rc"
}

# orphan: 다른 session 소유 → exit 0 + marker .bak 이동
got=$(run '{"gate_session_id":"OLD-SESSION"}' "NEW-SESSION")
[[ "$got" == "rc=0" ]] && pass "orphan → exit 0 (gate skip)" || fail "orphan rc 기대 0, got $got"
[[ -f "$TMP/session.json.bak" && ! -f "$TMP/session.json" ]] \
  && pass "orphan → marker .bak 이동 (plan 보존)" || fail "orphan marker 정리 실패"

# match: 같은 session 소유 → 정상 gate (false check → exit 2)
got=$(run '{"gate_session_id":"SAME"}' "SAME")
[[ "$got" == "rc=2" ]] && pass "match → gate 도달 (exit 2)" || fail "match rc 기대 2, got $got"

# claim: 미소유 → 현재 session 기록 + gate 도달 (exit 2)
got=$(run '{}' "CLAIMER")
[[ "$got" == "rc=2" ]] && pass "claim → gate 도달 (exit 2)" || fail "claim rc 기대 2, got $got"
grep -q '"gate_session_id": "CLAIMER"' "$TMP/session.json" \
  && pass "claim → marker 에 gate_session_id 기록" || fail "claim gate_session_id 미기록"

# inert: session_id 부재(빈 stdin) → 가드 미적용, 기존 동작 (false check → exit 2)
printf '{"gate_session_id":"OLD"}' > "$TMP/session.json"
rc=0
CLAUDE_PROJECT_DIR="$TMP" PLAN_DEV_GOAL_SESSION_FILE="$TMP/session.json" \
  PLAN_DEV_GOAL_PLAN_PATH="$TMP/plan.md" SKIP_GOAL_AGENT=1 \
  "$HOOK" >/dev/null 2>&1 </dev/null || rc=$?
[[ "$rc" == "2" && -f "$TMP/session.json" ]] \
  && pass "inert → session_id 없으면 가드 미적용 (기존 동작)" || fail "inert 기대 exit2+marker유지, rc=$rc"

[[ $FAIL -eq 0 ]] && echo "=== ALL PASS ===" || { echo "=== FAILED ==="; exit 1; }
