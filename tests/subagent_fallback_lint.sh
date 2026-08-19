#!/usr/bin/env bash
# subagent 폴백 경로 lint — dispatch 가 불가능한 세션에서 유일한 실행 경로.
#
# 배경: stale CMUX_WORKSPACE_ID 로 cmux launch 가 전멸하는 세션이 있다(bg job 등).
# 그때 문서화된 폴백은 subagent 인데, `.gitignore` 가 `.claude/specs/*.spec.md` 를
# 무시해 spec 이 격리 worktree 로 따라가지 않는다 — 2026-08-14, 08-18 두 번 막혔다.
# 해법은 파일 복사나 gitignore 예외가 아니라 **본문 인라인**이다(subagent 는 cmux send
# 크기 제약이 없다). 이 lint 는 그 절차가 문서·스크립트 안내에 남아 있는지 검사한다.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TS="$REPO/commands/plan-dev/troubleshooting-dispatch.md"
DISPATCH="$REPO/scripts/dispatch-slice-pane.sh"
KNOWN="$REPO/docs/known-issues.md"

step() { echo "[$1] $2"; }
fail() { echo "❌ FAIL: $1" >&2; exit 1; }

for f in "$TS" "$DISPATCH" "$KNOWN"; do [ -f "$f" ] || fail "missing $f"; done

step 1 "폴백 절차 섹션 존재"
grep -F "subagent 폴백" "$TS" > /dev/null || fail "troubleshooting-dispatch.md 에 'subagent 폴백' 절차 섹션 없음"

step 2 "spec 본문 인라인 지시 — gitignore 함정의 실제 해법"
grep -F "본문 인라인" "$TS" > /dev/null || fail "폴백 절차에 'spec 본문 인라인' 지시 없음"
grep -F ".claude/specs/*.spec.md" "$TS" > /dev/null \
  || fail "폴백 절차에 gitignore 함정 근거(.claude/specs/*.spec.md) 없음 — 근거 없으면 다음 세션이 또 파일 복사를 시도한다"

step 3 "worktree 격리 인자 명시"
grep -F 'isolation="worktree"' "$TS" > /dev/null || fail "폴백 절차에 isolation=\"worktree\" 명시 없음"

step 4 "작업 디렉토리 절대경로 요구 (cwd 검증 계약과 짝)"
grep -F "절대경로" "$TS" > /dev/null || fail "폴백 절차에 작업 디렉토리 절대경로 지시 없음"

step 5 "dispatch subagent 안내가 실행 가능한 지시로 연결"
grep -F "troubleshooting-dispatch" "$DISPATCH" > /dev/null \
  || fail "dispatch-slice-pane.sh subagent 안내가 폴백 절차 문서를 가리키지 않음"

step 6 "known-issues #18 의 '검증됨' 오기 제거"
grep -F "subagent 폴백 경로는 검증됨" "$KNOWN" > /dev/null \
  && fail "known-issues 에 'subagent 폴백 경로는 검증됨' 잔존 — 2026-08-14·08-18 두 번 막혔다"

step 7 "known-issues 가 미검증 상태를 명시"
grep -F "미검증" "$KNOWN" > /dev/null || fail "known-issues #18 에 폴백 미검증 상태 표기 없음"

echo "OK"
