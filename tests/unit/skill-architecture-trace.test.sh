#!/usr/bin/env bash
# architecture-trace 스킬 lint — SKILL.md 계약 + 템플릿 asset 자기완결성.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SK="$REPO_ROOT/skills/architecture-trace/SKILL.md"
TPL="$REPO_ROOT/skills/architecture-trace/assets/trace-template.html"
pass=0; fail=0

check() {
  local desc="$1"; shift
  if eval "$@" &>/dev/null; then
    echo "PASS: $desc"; pass=$((pass+1))
  else
    echo "FAIL: $desc"; fail=$((fail+1))
  fi
}

# ── 구조 ──────────────────────────────────────────────────────────
check "SKILL.md exists"        "test -f '$SK'"
check "template asset exists"  "test -f '$TPL'"
check "name matches dir"       "grep -q '^name: architecture-trace$' '$SK'"
check "description non-empty"  "grep -E '^description: .+' '$SK'"

# ── 설계 문서 규약과의 경계 (조건 3개) ─────────────────────────────
# 이 스킬이 plan-dev 설계 문서의 mermaid 원본을 대체하지 않는다는 계약.
check "구조 델타를 대체하지 않음 명시" "grep -q '대체하지 않는다' '$SK'"
check "생성물·동기화 의무 없음 명시"   "grep -q '동기화 의무' '$SK'"
check "mermaid 가 원본임 명시"         "grep -q 'mermaid' '$SK'"

# ── 핵심 설계 규칙 ────────────────────────────────────────────────
check "NODES/EDGES/SCENARIOS 분리 규칙" \
  "grep -q 'SCENARIOS' '$SK' && grep -q 'NODES' '$SK' && grep -q 'EDGES' '$SK'"
check "실패 시나리오 필수"        "grep -q '실패' '$SK'"
check "ride 자기 점 생성/제거 규칙" "grep -q 'ride' '$SK'"
check "par 는 진짜 동시일 때만"     "grep -q '거짓말' '$SK'"
check "노드 상한 규칙 없음" \
  "! grep -qE '노드 (5|6|7)개 (이하|이내)' '$SK'"

# ── 템플릿 자기완결성 ─────────────────────────────────────────────
check "템플릿에 외부 스크립트/스타일 없음" \
  "! grep -qE '<script[^>]+src=|<link[^>]+href=' '$TPL'"
# SVG 네임스페이스 상수(http://www.w3.org/2000/svg)는 네트워크 요청이 아니다.
check "템플릿에 외부 네트워크 URL 없음" \
  "! grep -oE 'https?://[^\"'\'' ]+' '$TPL' | grep -qv 'www.w3.org/2000/svg'"
check "템플릿 세 구조 존재" \
  "grep -q 'const NODES' '$TPL' && grep -q 'const EDGES' '$TPL' && grep -q 'const SCENARIOS' '$TPL'"
check "템플릿 시나리오 3개 이상" \
  "test \$(grep -cE \"^  '.+': \\[\" '$TPL') -ge 3"
check "템플릿에 실패 레그(err) 존재"   "grep -q 'err:1' '$TPL'"
check "템플릿에 응답 역주행(back) 존재" "grep -q 'back:1' '$TPL'"
check "템플릿에 par 동시 구간 존재"     "grep -q 'par:\[' '$TPL'"
check "ride 가 dot 을 만들고 제거"      "grep -q 'dotsG.appendChild(dot)' '$TPL' && grep -q 'dot.remove()' '$TPL'"
check "reduced-motion 존중"             "grep -q 'prefers-reduced-motion' '$TPL'"
check "상태 색 4종 (활성/성공/실패)" \
  "grep -q '#0ff' '$TPL' && grep -q '#1fd18a' '$TPL' && grep -q '#ff4d7d' '$TPL'"

# ── README 노출 ───────────────────────────────────────────────────
check "README 에 스킬 등재" "grep -q 'architecture-trace' '$REPO_ROOT/README.md'"

echo ""
echo "Results: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
