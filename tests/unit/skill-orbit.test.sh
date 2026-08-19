#!/usr/bin/env bash
# orbit 스킬 lint — SKILL.md 계약 + 픽스처(결함 4건 + 오탐 유발 요소 3종) 검증.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SK="$REPO_ROOT/skills/orbit/SKILL.md"
FX="$REPO_ROOT/skills/orbit/fixture"
pass=0; fail=0

check() {
  local desc="$1"; shift
  if eval "$@" &>/dev/null; then
    echo "PASS: $desc"; pass=$((pass+1))
  else
    echo "FAIL: $desc"; fail=$((fail+1))
  fi
}

# ── SKILL.md 구조 / frontmatter ──────────────────────────────────
check "SKILL.md exists"            "test -f '$SK'"
check "name matches dir"           "grep -q '^name: orbit$' '$SK'"
check "description: 흐름 점검"      "grep -q '흐름 점검' '$SK'"
check "description: 사이클"        "grep -q '사이클' '$SK'"
check "description: 도달"          "grep -q '도달' '$SK'"
check "description: 갇히"          "grep -q '갇히' '$SK'"

# ── 검사 4종 이름 ─────────────────────────────────────────────────
check "검사명 dangling 존재"       "grep -q 'dangling' '$SK'"
check "검사명 orphan 존재"         "grep -q 'orphan' '$SK'"
check "검사명 sink 존재"           "grep -q 'sink' '$SK'"
check "검사명 미폐쇄 존재"         "grep -q '미폐쇄' '$SK'"

# ── 단정 금지 회귀 ────────────────────────────────────────────────
check "프레임워크 렌더 위치 단정 문구 없음" \
  "! grep -q '공통 레이아웃 밖에서' '$SK'"

# ── 엣지 추출 체크리스트 ─────────────────────────────────────────
check "템플릿 리터럴 href 언급"    "grep -q 'href={\`' '$SK'"
check "router.push 언급"           "grep -q 'router.push' '$SK'"
check "redirect() 언급"            "grep -q 'redirect()' '$SK'"
check "middleware 언급"            "grep -q 'middleware' '$SK'"
check "상수 파일 언급"             "grep -qE 'NAV_LINKS|상수' '$SK'"

# ── 오탐 가드 3종 ─────────────────────────────────────────────────
check "오탐 가드: inbound 언급"    "grep -q 'inbound' '$SK'"
check "오탐 가드: 레이아웃 언급"    "grep -q '레이아웃' '$SK'"
check "오탐 가드: 복구 경로 언급"  "grep -q '복구 경로' '$SK'"

# ── 상시 규칙 섹션 ────────────────────────────────────────────────
check "상시 규칙 섹션 제목 존재"   "grep -q '## 프로젝트에 심을 상시 규칙' '$SK'"
check "상시 규칙에 not-found.tsx 언급" "grep -q 'not-found.tsx' '$SK'"

# ── 범위 명시 ─────────────────────────────────────────────────────
check "수정은 별도 요청 문구 존재" "grep -q '수정은 별도 요청' '$SK'"

# ── 픽스처: 파일 존재 (10개) ──────────────────────────────────────
check "middleware.ts 존재"         "test -f '$FX/middleware.ts'"
check "lib/nav.ts 존재"            "test -f '$FX/lib/nav.ts'"
check "components/nav.tsx 존재"    "test -f '$FX/components/nav.tsx'"
check "app/page.tsx 존재"          "test -f '$FX/app/page.tsx'"
check "app/login/page.tsx 존재"    "test -f '$FX/app/login/page.tsx'"
check "app/dash/layout.tsx 존재"   "test -f '$FX/app/dash/layout.tsx'"
check "app/dash/page.tsx 존재"     "test -f '$FX/app/dash/page.tsx'"
check "app/dash/items/page.tsx 존재" "test -f '$FX/app/dash/items/page.tsx'"
check "app/dash/items/[id]/page.tsx 존재" "test -f '$FX/app/dash/items/[id]/page.tsx'"
check "app/reports/page.tsx 존재"  "test -f '$FX/app/reports/page.tsx'"

# ── 픽스처: 부재해야 할 것 ────────────────────────────────────────
check "app/settings/page.tsx 부재 (dangling 대상)" "! test -f '$FX/app/settings/page.tsx'"
check "not-found.tsx 어디에도 없음 (sink 대상)" \
  "[ \$(find '$FX' -name 'not-found.tsx' | wc -l | tr -d ' ') -eq 0 ]"

# ── 픽스처: 내용 패턴 ─────────────────────────────────────────────
check "lib/nav.ts 에 /settings 포함"    "grep -q '/settings' '$FX/lib/nav.ts'"
check "[id]/page.tsx 에 notFound() 포함" "grep -q 'notFound()' '$FX/app/dash/items/[id]/page.tsx'"
check "middleware.ts 에 /login 포함"    "grep -q '/login' '$FX/middleware.ts'"
check "dash/layout.tsx 에 Nav 포함"     "grep -q 'Nav' '$FX/app/dash/layout.tsx'"

# ── orphan 오탐 방지: /reports 링크가 자신 외 어디에도 없음 ───────
check "/reports href 가 app/reports/page.tsx 외 없음" \
  "[ \$(grep -rl '/reports' '$FX' | grep -v 'app/reports/page.tsx' | wc -l | tr -d ' ') -eq 0 ]"

echo ""
# 진입점 오탐 가드 — 루트 app/page.tsx 는 inbound 0 이지만 orphan 이 아니다.
# 픽스처 실행에서 실제로 드러난 빈틈(2026-08-19). 면제가 blanket 이 되지 않도록
# "근거를 적는다" 요구가 함께 있어야 한다.
check "진입점 orphan 예외"      "grep -q '진입점' '$SK'"
check "진입점 예외에 근거 요구"  "grep -q '근거' '$SK'"

echo "ok: $pass/$((pass+fail)) passed, fail: $fail"
[ "$fail" -eq 0 ]
