#!/usr/bin/env bash
# Slice C lint — .claude/commands/parallel-consult.md 의 frontmatter + 필수 섹션.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CMD="$REPO/.claude/commands/parallel-consult.md"

step() { echo "[$1] $2"; }
fail() { echo "❌ FAIL: $1" >&2; exit 1; }

step 1 "parallel-consult.md 존재"
[ -f "$CMD" ] || fail "missing: $CMD"

step 2 "frontmatter name 매칭"
grep -E "^name:[[:space:]]*parallel-consult$" "$CMD" > /dev/null || fail "name frontmatter mismatch"

step 3 "필수 섹션"
for sec in "## Prerequisite" "## 흐름 단계" "## 안전 수칙" "## 안티패턴" "## 예시"; do
  grep -F "$sec" "$CMD" > /dev/null || fail "missing section: $sec"
done

step 4 "흐름 단계 키워드"
# tmux-cli 또는 tmux-pane.sh 중 하나는 있어야 (이상적으로 둘 다)
grep -E "tmux-cli|tmux-pane\.sh" "$CMD" > /dev/null || fail "wrapper reference missing"
for kw in "launch zsh" 'send "claude"' "wait-idle" "capture" "사용자에게 묻기"; do
  grep -F "$kw" "$CMD" > /dev/null || fail "flow keyword missing: $kw"
done

step 5 "안전 수칙 키워드"
for kw in "shell 먼저" "wait-idle" "폴링"; do
  grep -F "$kw" "$CMD" > /dev/null || fail "safety keyword missing: $kw"
done

echo "OK"
