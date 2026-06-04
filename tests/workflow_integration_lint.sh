#!/usr/bin/env bash
# Workflow 통합 lint — dynamic Workflow 의 plan-dev 통합(A+B+C) 산출물 검증.
#  - plan-dev.md 에 Workflow 통합 섹션(opt-in / A judge·적대 / B 실행모드 / C 대규모) 존재.
#  - .claude/workflows/*.mjs reference 스크립트가 node --check 통과 + meta 보유.
#  - README/CLAUDE.md 동기화 + install.sh 전파.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLAN="$REPO/.claude/commands/plan-dev.md"
README="$REPO/README.md"
CLAUDE="$REPO/CLAUDE.md"
INSTALL="$REPO/install.sh"
WF_DIR="$REPO/.claude/workflows"

step() { echo "[$1] $2"; }
fail() { echo "❌ FAIL: $1" >&2; exit 1; }

step 1 "plan-dev.md Workflow 통합 섹션"
grep -qi "Workflow 통합" "$PLAN" || fail "plan-dev.md missing 'Workflow 통합' 섹션"
grep -qi "opt-in" "$PLAN" || fail "plan-dev.md missing opt-in 설명"
grep -qiE "judge panel|judge-panel" "$PLAN" || fail "plan-dev.md missing judge panel (A)"
grep -qiE "multi-dimension|적대" "$PLAN" || fail "plan-dev.md missing 적대/multi-dimension verify (A)"
grep -qiE "mode=workflow|workflow 실행 모드|workflow 모드" "$PLAN" || fail "plan-dev.md missing workflow 실행 모드 (B)"
grep -qiE "대규모|audit|migration" "$PLAN" || fail "plan-dev.md missing 대규모 escape hatch (C)"
grep -qiE "상호배타|cmux surface 가 아님|cmux 시각화|workflow.*cmux|cmux.*workflow" "$PLAN" || fail "plan-dev.md missing cmux⇄workflow 상호배타 경고"

step 2 ".claude/workflows reference 스크립트"
# Workflow 스크립트는 `export const meta` + top-level await/return 사용 — 런타임이 본문을
# async fn 으로 wrap. raw `node --check` 는 top-level return 을 불법 처리하므로, 런타임과
# 동일하게 export strip + async wrap 한 뒤 syntax check (faithful 검증).
[ -d "$WF_DIR" ] || fail "missing dir .claude/workflows"
shopt -s nullglob
wf_files=("$WF_DIR"/*.mjs)
[ "${#wf_files[@]}" -ge 3 ] || fail ".claude/workflows 에 .mjs 3개 이상 필요 (현재 ${#wf_files[@]})"
for f in "${wf_files[@]}"; do
  grep -q "export const meta" "$f" || fail "meta 누락: $f"
done
for f in "${wf_files[@]}"; do grep -q "model: *'sonnet'" "$f" || fail "model sonnet 누락: $f"; done
if command -v node >/dev/null 2>&1; then
  for f in "${wf_files[@]}"; do
    wrapped=$({ echo '(async function(agent,parallel,pipeline,phase,log,args,budget,workflow){'; \
                sed 's/^export const meta/const meta/' "$f"; \
                echo '});'; })
    printf '%s' "$wrapped" | node --check --input-type=module - 2>/dev/null \
      || printf '%s' "$wrapped" | node --check - \
      || fail "syntax 실패(wrap 후): $f"
  done
  echo "    wrap+syntax + meta OK (${#wf_files[@]} files)"
else
  echo "    ⚠ node 부재 — syntax check skip (meta 만 검사)"
fi

step 3 "README / CLAUDE.md 동기화"
grep -qi "workflow" "$README" || fail "README missing workflow"
grep -qi "workflow" "$CLAUDE" || fail "CLAUDE.md missing workflow"
grep -q ".claude/workflows" "$CLAUDE" || fail "CLAUDE.md missing .claude/workflows 파일책임"

step 4 "install.sh 전파"
grep -q "workflows/" "$INSTALL" || fail "install.sh missing workflows/ 전파"

echo "OK"
