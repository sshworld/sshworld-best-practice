#!/usr/bin/env bash
# S2 lint — plan-dev.md 의 1-1.5 설계 승인 게이트 신설 검증.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_ALL=$(mktemp); cat "$REPO/commands/plan-dev.md" "$REPO"/commands/plan-dev/*.md > "$_ALL"
PLAN="$_ALL"

step() { echo "[$1] $2"; }
fail() { echo "❌ FAIL: $1" >&2; exit 1; }

step 1 "1-1.5 설계 문서 작성 + 승인 헤딩"
grep -E "^#+ 1-1\.5\." "$PLAN" > /dev/null || fail "1-1.5 heading 없음"

step 2 "게이트 파생 규칙 — 조건부 블록 + 2게이트 + fast path"
grep -F "조건부 블록" "$PLAN" > /dev/null || fail "'조건부 블록' 키워드 없음"
grep -F "2게이트" "$PLAN" > /dev/null || fail "'2게이트' 키워드 없음"
grep -F "fast path" "$PLAN" > /dev/null || fail "'fast path' 키워드 없음"

step 3 "hotfix 골격 승인 예외"
grep -F "hotfix" "$PLAN" > /dev/null || fail "'hotfix' 키워드 없음"
grep -F "골격" "$PLAN" > /dev/null || fail "'골격' 키워드 없음"

step 4 "필수 섹션 목록에 설계 문서 링크"
grep -F "설계 문서" "$PLAN" > /dev/null || fail "필수 섹션 목록에 '설계 문서' 없음"

step 5 "Phase 3.5/4 실측 write-back 지시"
grep -F "실측" "$PLAN" > /dev/null || fail "'실측' write-back 지시 없음"

step 6 "동작 스펙 판정 주체 — 기계/사람"
grep -F "판정 주체" "$PLAN" > /dev/null || fail "'판정 주체' 키워드 없음"
grep -F "기계" "$PLAN" > /dev/null || fail "'기계' 키워드 없음"
grep -F "사람" "$PLAN" > /dev/null || fail "'사람' 키워드 없음"

step 7 "design-doc.md 레퍼런스 링크"
grep -F "design-doc.md" "$PLAN" > /dev/null || fail "'design-doc.md' 링크 없음"

step 8 "set-design 호출 안내"
grep -F "set-design" "$PLAN" > /dev/null || fail "'set-design' 안내 없음"

step 9 "회귀: plan-dev_mode_lint.sh"
bash "$REPO/tests/plan-dev_mode_lint.sh" | tail -1 | grep -F "OK" > /dev/null || fail "plan-dev_mode_lint.sh 회귀 실패"


# --- 이하 step 은 합본($PLAN)이 아니라 plan-dev.md 만 검사한다.
# 격리 worktree 에는 형제 슬라이스(design-doc.md 등)의 변경이 없기 때문.
PLAN_ONLY="$REPO/commands/plan-dev.md"

step 10 "에러 정책 규칙 — 계약의 중단 경로는 동작 스펙에 테스트 케이스가 있어야 한다"
grep -F "에러 정책" "$PLAN_ONLY" > /dev/null || fail "plan-dev.md 에 '에러 정책' 규칙 없음"

step 11 "Slice File Map 은 머지 물류 — 계약과 구분"
grep -F "머지 물류" "$PLAN_ONLY" > /dev/null || fail "plan-dev.md 에 'File Map = 머지 물류' 구분 문장 없음"

step 12 "1-1.5 가 인터페이스 계약을 지시"
grep -F "인터페이스 계약" "$PLAN_ONLY" > /dev/null || fail "plan-dev.md 1-1.5 에 '인터페이스 계약' 지시 없음"

echo "OK"
