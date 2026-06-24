#!/usr/bin/env bash
# Unit test: enforce-plan-dev-goal.sh Semantic goal 추출 계약
# 인라인 `**Semantic goal**: <텍스트>` (템플릿 형식) 가 non-empty 로 추출되는지 검증.
# 옛 awk(`{flag=1; next}`) 는 인라인 줄을 skip 해 빈값 → false-negative 무한 block.
set -uo pipefail

HOOK="$(cd "$(dirname "$0")/../.." && pwd)/hooks/enforce-plan-dev-goal.sh"
FAIL=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAIL=1; }

# 추출 로직 = hook 의 awk+sed 파이프라인 (계약 복제)
extract() {
  awk '/\*\*[Ss]emantic goal\*\*/{flag=1} flag && /^## /{flag=0} flag' "$1" \
    | sed 's/^\*\*[Ss]emantic goal\*\*:[[:space:]]*//' | head -10
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# fixture 1: 인라인 형식 (템플릿 표준)
cat > "$TMP/inline.md" <<'EOF'
## Goal Statement

**Semantic goal**: foo bar baz 인라인 목표.
EOF
got=$(extract "$TMP/inline.md")
[[ -n "${got//[[:space:]]/}" && "$got" == *"foo bar baz"* ]] \
  && pass "인라인 형식 non-empty 추출" || fail "인라인 형식 추출 실패: '$got'"

# fixture 2: 다음줄 형식 (회귀 안전 — 여전히 캡처)
cat > "$TMP/nextline.md" <<'EOF'
## Goal Statement

**Semantic goal**:
다음줄 목표 텍스트.
EOF
got=$(extract "$TMP/nextline.md")
[[ "$got" == *"다음줄 목표"* ]] \
  && pass "다음줄 형식 캡처" || fail "다음줄 형식 캡처 실패: '$got'"

# fixture 3: goal 없음 → 빈값
cat > "$TMP/none.md" <<'EOF'
## Context
설명만 있고 goal 없음.
EOF
got=$(extract "$TMP/none.md")
[[ -z "${got//[[:space:]]/}" ]] \
  && pass "goal 부재 시 빈값" || fail "goal 부재인데 추출됨: '$got'"

# fixture 4: 본문 ## 오매치 방지 (^## 공백 경계)
cat > "$TMP/hashbody.md" <<'EOF'
**Semantic goal**: 코드 ##주석 포함 목표.
EOF
got=$(extract "$TMP/hashbody.md")
[[ "$got" == *"##주석 포함 목표"* ]] \
  && pass "본문 ## 오매치 안 함" || fail "본문 ## 잘림: '$got'"

# grep 가드: hook 이 fixed awk pattern 포함 + 옛 패턴 부재
grep -qF 'flag && /^## /{flag=0} flag' "$HOOK" \
  && pass "hook fixed awk pattern 존재" || fail "hook fixed awk pattern 부재"
! grep -qF '{flag=1; next}' "$HOOK" \
  && pass "옛 next-skip 패턴 제거됨" || fail "옛 {flag=1; next} 패턴 잔존"
grep -qF 'semantic goal 추출 실패' "$HOOK" \
  && pass "빈-goal 가드 존재" || fail "빈-goal 가드 부재"

[[ $FAIL -eq 0 ]] && echo "=== ALL PASS ===" || { echo "=== FAILED ==="; exit 1; }
