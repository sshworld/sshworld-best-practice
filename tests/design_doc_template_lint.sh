#!/usr/bin/env bash
# 설계 문서 템플릿(commands/plan-dev/design-doc.md) + 첫 사례(docs/design/plan-presentation.md) lint.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TPL="$REPO/commands/plan-dev/design-doc.md"
DOC="$REPO/docs/design/plan-presentation.md"

step() { echo "[$1] $2"; }
fail() { echo "❌ FAIL: $1" >&2; exit 1; }

[ -f "$TPL" ] || fail "missing $TPL"
[ -f "$DOC" ] || fail "missing $DOC"

step 1 "조건부 블록 4개 이름"
for kw in "원인 분석" "구조 델타" "결정 갈림길" "기준선"; do
  grep -F -- "$kw" "$TPL" > /dev/null || fail "design-doc.md missing 블록: $kw"
done

step 2 "기준선 3형태"
for kw in "수치" "재현 절차" "관측 증거"; do
  grep -F -- "$kw" "$TPL" > /dev/null || fail "design-doc.md missing 기준선 형태: $kw"
done

step 3 "결정 갈림길 표 — 뒤집는 비용 칸"
grep -F "뒤집는 비용" "$TPL" > /dev/null || fail "design-doc.md missing '뒤집는 비용'"

step 4 "결과 — 목표/실측 + 미검증 문구"
grep -F "목표" "$TPL" > /dev/null || fail "design-doc.md missing '목표' 칸"
grep -F "실측" "$TPL" > /dev/null || fail "design-doc.md missing '실측' 칸"
grep -F "미검증 — 재발 감시 중" "$TPL" > /dev/null || fail "design-doc.md missing '미검증 — 재발 감시 중' 문구"

step 5 "mermaid config 블록"
for kw in "rankSpacing" "nodeSpacing" "layout: elk"; do
  grep -F -- "$kw" "$TPL" > /dev/null || fail "design-doc.md missing mermaid config: $kw"
done

step 6 "렌더러별 elk 실측 안내 (GitHub 은 조용히 dagre 폴백)"
grep -F "GitHub" "$TPL" > /dev/null || fail "design-doc.md missing GitHub 언급 (렌더러별 실측)"
grep -F "dagre" "$TPL" > /dev/null || fail "design-doc.md missing dagre 폴백 실측 — '깨지면 지워라' 는 조용한 열화를 못 잡는다"

step 6b "라벨에 <> 금지 규칙 — mermaid 가 HTML 태그로 먹는다"
grep -F "[slug]" "$TPL" > /dev/null || fail "design-doc.md missing 대괄호 라벨 권장 ([slug])"
# 실측: 라벨 안 <slug> 는 'docs/design/.md' 로 렌더되어 slug 가 사라진다.
# 산문에서는 이 문자열을 예시로 언급할 수 있으므로 **mermaid 펜스 안쪽만** 검사한다.
_MFENCE=$(awk '/^```mermaid$/{f=1;next} /^```$/{f=0} f' "$REPO/docs/design/plan-presentation.md")
printf '%s' "$_MFENCE" | grep -F "&lt;" > /dev/null \
  && fail "plan-presentation.md 의 mermaid 라벨에 <> 잔존 — 렌더 시 통째로 사라진다 ([slug] 로 교체)"

step 7 "노드 수 상한 규칙 없음 — 엣지 교차 기준 존재"
grep -F "노드 5개" "$TPL" > /dev/null && fail "design-doc.md 에 '노드 5개' 상한 규칙 잔존"
grep -F "노드 수 상한" "$TPL" > /dev/null && fail "design-doc.md 에 '노드 수 상한' 규칙 잔존"
grep -F "엣지 교차" "$TPL" > /dev/null || fail "design-doc.md missing '엣지 교차' 기준"

step 8 "파일 단위 판정 3단계"
for kw in "롤백 단위" "수치 공유" "한 줄 서술"; do
  grep -F -- "$kw" "$TPL" > /dev/null || fail "design-doc.md missing 판정 단계: $kw"
done

step 9 "포함: 줄 형식 문서화"
grep -F "포함:" "$TPL" > /dev/null || fail "design-doc.md missing '포함:' 줄 형식 문서"

step 10 "CBP_DESIGN_DIR + 기본 경로 docs/design"
grep -F "CBP_DESIGN_DIR" "$TPL" > /dev/null || fail "design-doc.md missing 'CBP_DESIGN_DIR'"
grep -F "docs/design" "$TPL" > /dev/null || fail "design-doc.md missing 기본 경로 'docs/design'"

step 11 "plan-presentation.md 필수 헤딩"
for kw in "포함:" "기준선" "결정 갈림길" "목표" "실측"; do
  grep -F -- "$kw" "$DOC" > /dev/null || fail "plan-presentation.md missing: $kw"
done

echo "OK"
