#!/usr/bin/env bash
# 설계 문서 템플릿(commands/plan-dev/design-doc.md) lint.
#
# 설계 문서 **인스턴스**는 repo 에 두지 않는다 — 개인 작업 기록이므로
# `~/.claude/design/<repo>/` (기본값)에 남는다. 공개 저장소에 커밋하면 개인 노트가
# 공개되고 팀 저장소에서는 타인에게 강요된다. 그래서 이 lint 는 템플릿만 검증하고,
# repo 에 인스턴스가 다시 커밋되는 회귀를 막는다.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TPL="$REPO/commands/plan-dev/design-doc.md"

step() { echo "[$1] $2"; }
fail() { echo "❌ FAIL: $1" >&2; exit 1; }

[ -f "$TPL" ] || fail "missing $TPL"
# 인스턴스 존재 검사는 없다 — repo 에 두지 않는 것이 기본이다 (step 11 이 그 회귀를 막는다).

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
# 실측 근거(라벨 안 <slug> 가 통째로 사라진다)가 규약 본문에 남아 있어야 한다.
# 예전엔 커밋된 인스턴스의 mermaid 펜스를 검사했는데, 인스턴스는 이제 repo 에 없다.
grep -F "HTML 태그" "$TPL" > /dev/null || fail "design-doc.md 에 라벨 <> 금지 근거(HTML 태그로 먹힘) 없음"

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

step 10 "CBP_DESIGN_DIR override 설명 존재"
grep -F "CBP_DESIGN_DIR" "$TPL" > /dev/null || fail "design-doc.md missing 'CBP_DESIGN_DIR'"

step 11 "설계 문서 인스턴스는 repo 에 없어야 한다 (개인 기록)"
if [ -d "$REPO/docs/design" ] && [ -n "$(ls -A "$REPO/docs/design" 2>/dev/null)" ]; then
  fail "docs/design/ 에 설계 문서가 커밋돼 있다 — 개인 기록은 ~/.claude/design/<repo>/ 로"
fi

step 12 "기본 경로가 개인 머신, 프레이밍이 '개인 기록'"
grep -F -- ".claude/design" "$TPL" > /dev/null || fail "design-doc.md 에 기본 경로(~/.claude/design) 없음"
grep -F -- "개인" "$TPL" > /dev/null || fail "design-doc.md 에 '개인 기록' 프레이밍 없음"
grep -F -- "CBP_DESIGN_DIR" "$TPL" > /dev/null || fail "design-doc.md 에 CBP_DESIGN_DIR override 설명 없음"


step 13 "인터페이스 계약 블록 이름"
grep -F "인터페이스 계약" "$TPL" > /dev/null || fail "design-doc.md missing 블록: 인터페이스 계약"

step 14 "계약 4칸 헤더"
for kw in "제공자" "소비자" "시그니처·불변식·소유권" "실패 시"; do
  grep -F -- "$kw" "$TPL" > /dev/null || fail "design-doc.md missing 계약 칸: $kw"
done

step 15 "계약 행 + 생략 표기"
grep -F "계약 생략(슬라이스 1개)" "$TPL" > /dev/null || fail "design-doc.md missing 계약 생략 표기"

step 16 "계약은 게이트 트리거가 아니다 — 트리거 열거는 4개 유지"
grep -F "원인분석 / 구조 델타 / 결정 갈림길 / 기준선" "$TPL" > /dev/null \
  || fail "게이트 트리거 열거(4개) 가 훼손됨 — 계약을 트리거에 넣으면 fast path 가 소멸한다"
grep -F "게이트 트리거가 아니다" "$TPL" > /dev/null \
  || fail "design-doc.md 에 '계약은 게이트 트리거가 아니다' 근거 없음"

step 17 "섹션 번호 보존 — finish-plan-dev.sh 가 '## 6. 결과' 를 파싱한다"
grep -F "## 6. 결과" "$TPL" > /dev/null || fail "'## 6. 결과' 소실 — Phase 5 실측 게이트가 깨진다"
grep -F "## 3.5" "$TPL" > /dev/null || fail "계약 블록이 '## 3.5' 로 삽입되지 않음 (번호 재정렬 금지)"

echo "OK"
