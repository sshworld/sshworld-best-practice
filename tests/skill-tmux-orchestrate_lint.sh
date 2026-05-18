#!/usr/bin/env bash
# Slice B lint — .claude/skills/tmux-orchestrate/SKILL.md 의 frontmatter + 필수 섹션 검사.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL="$REPO/.claude/skills/tmux-orchestrate/SKILL.md"

step() { echo "[$1] $2"; }
fail() { echo "❌ FAIL: $1" >&2; exit 1; }

step 1 "SKILL.md 존재"
[ -f "$SKILL" ] || fail "missing: $SKILL"

step 2 "frontmatter name 매칭"
grep -E "^name:[[:space:]]*tmux-orchestrate$" "$SKILL" > /dev/null || fail "name frontmatter mismatch"

step 3 "필수 섹션 grep"
for sec in "## 핵심 패턴" "## 호출 시퀀스" "## 도구 선택 가이드" "## 안티패턴" "## 환경변수"; do
  grep -F "$sec" "$SKILL" > /dev/null || fail "missing section: $sec"
done

step 4 "안티패턴 본문 키워드"
for kw in "wait-idle" "자기 pane" "tmux-cli"; do
  grep -F "$kw" "$SKILL" > /dev/null || fail "anti-pattern keyword missing: $kw"
done

step 5 "호출 시퀀스 코드블록 키워드"
for kw in "launch zsh" 'send "claude"' "wait-idle" "capture"; do
  grep -F "$kw" "$SKILL" > /dev/null || fail "call-sequence keyword missing: $kw"
done

echo "OK"
