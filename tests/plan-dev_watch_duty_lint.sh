#!/usr/bin/env bash
# plan-dev 문서 계약 — dispatch 후 감시 의무 + 설계 문서 노출.
#
# 배경: 자식 4개가 전부 완료하고 파일까지 썼는데 부모가 받은 자동 통지는 0건이었다.
# 부모는 dispatch 직후 감시를 걸지 않고 턴을 종료했다 — reap-on-stop 자동 체인을
# 전제했기 때문이다. 문서가 dispatch **순서**만 규정하고 감시 **의무**는 말하지
# 않았다. 통지가 조용히 실패할 수 있는 이상 감시는 선택이 아니다.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE="$REPO/commands/plan-dev.md"

step() { echo ""; echo "[$1] $2"; }
fail() { echo "❌ FAIL: $1" >&2; exit 1; }

[ -f "$CORE" ] || fail "코어 문서 없음: $CORE"

# 코어 + 레퍼런스 합본 (상세는 레퍼런스로 밀 수 있어야 한다)
ALL=$(mktemp)
cat "$CORE" "$REPO"/commands/plan-dev/*.md > "$ALL"

step 1 "감시 의무 — '감시' + 의무/필수"
grep -qE '감시' "$ALL" || fail "'감시' 문구 없음"
grep -qE '감시[^。\n]*(의무|필수)|(의무|필수)[^。\n]*감시' "$ALL" \
  || fail "감시를 의무/필수로 규정한 문구 없음"

step 2 "근거 — 통지가 조용히 실패할 수 있음"
grep -qE '조용히' "$ALL" || fail "'조용히' 실패 가능성 언급 없음"
grep -qE '통지' "$ALL" || fail "'통지' 언급 없음"

step 3 "감시 없이 턴 종료 금지"
grep -qE '턴[^。\n]*(종료|끝내)' "$ALL" || fail "턴 종료 관련 금지 문구 없음"

step 4 "설계 문서를 사용자에게 띄우는 지시 (open)"
grep -qE '\bopen\b' "$CORE" || fail "코어에 open 지시 없음"

step 5 "근거 — 못 본 상태의 승인은 승인이 아님"
grep -qE '승인' "$CORE" || fail "승인 관련 문구 없음"

step 6 "회귀 — 코어 200줄 캡"
bash "$REPO/tests/unit/plan-dev-split.test.sh" >/dev/null 2>&1 \
  || fail "plan-dev-split.test.sh 실패 (200줄 캡 초과 가능): $(wc -l < "$CORE")줄"

step 7 "회귀 — mode lint"
bash "$REPO/tests/plan-dev_mode_lint.sh" >/dev/null 2>&1 || fail "plan-dev_mode_lint.sh 실패"

step 8 "회귀 — 설계 게이트 lint"
bash "$REPO/tests/plan-dev_design_gate_lint.sh" >/dev/null 2>&1 || fail "plan-dev_design_gate_lint.sh 실패"

rm -f "$ALL"
echo ""
echo "OK"
