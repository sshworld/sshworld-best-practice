#!/usr/bin/env bash
# 계약 층 lint — spec 작성 규약(cmux-dispatch.md) + implementor 입력/순위.
#
# 설계 문서는 repo 밖(개인 머신)이고 plan 파일은 작업 후 폐기된다.
# dispatch 는 spec 본문을 inline 전송하지 않고 경로만 자식에게 준다(build_spec_prompt).
# 따라서 spec 파일의 `## 계약` 섹션이 계약이 자식에게 도달하는 **유일한 통로**다.
# 이 lint 는 그 통로가 규약으로 남아 있는지만 검사한다 (인스턴스 검사 아님).

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DISPATCH="$REPO/commands/plan-dev/cmux-dispatch.md"
IMPL="$REPO/agents/implementor.md"

step() { echo "[$1] $2"; }
fail() { echo "❌ FAIL: $1" >&2; exit 1; }

[ -f "$DISPATCH" ] || fail "missing $DISPATCH"
[ -f "$IMPL" ] || fail "missing $IMPL"

step 1 "spec 규약에 계약 섹션 필수"
grep -F "계약 섹션" "$DISPATCH" > /dev/null || fail "cmux-dispatch.md 에 '계약 섹션' 규약 없음"
grep -F '`## 계약`' "$DISPATCH" > /dev/null || fail "cmux-dispatch.md 에 '## 계약' 섹션명 명시 없음"

step 2 "계약 4칸 형식 명시"
for kw in "제공자" "소비자" "실패 시"; do
  grep -F -- "$kw" "$DISPATCH" > /dev/null || fail "cmux-dispatch.md 에 계약 칸 없음: $kw"
done

step 3 "왜 spec 이 유일한 통로인지 근거"
grep -F "유일한 통로" "$DISPATCH" > /dev/null \
  || fail "cmux-dispatch.md 에 '유일한 통로' 근거 없음 — 근거가 없으면 규약이 물류로 읽혀 생략된다"

step 4 "implementor 입력 5항목 (계약·에러 정책 포함)"
_n=$(sed -n '/^## 입력/,/^\*\*worktree/p' "$IMPL" | grep -c '^- ')
[ "$_n" -ge 5 ] || fail "implementor.md 입력 항목이 $_n 개 — 계약·에러 정책 추가 필요 (≥5)"
grep -F "계약·에러 정책" "$IMPL" > /dev/null || fail "implementor.md 입력에 '계약·에러 정책' 없음"

step 5 "계약의 에러 경로는 YAGNI 대상이 아니다 (순위 명시)"
grep -F "YAGNI 대상이 아니다" "$IMPL" > /dev/null \
  || fail "implementor.md 에 계약 > YAGNI 순위 문장 없음 — 최소 구현 지시가 에러 경로를 지운다"

step 6 "안 하는 것 — 계약 실패 경로를 최소 구현 명분으로 생략 금지"
grep -F "최소 구현" "$IMPL" > /dev/null || fail "implementor.md '안 하는 것' 에 최소 구현 명분 금지 항목 없음"

echo "OK"
