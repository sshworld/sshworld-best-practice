#!/usr/bin/env bash
# PostToolUse Task|Agent — commit-advisor subagent 호출 감지 시
# plan-dev-commit-advised marker 를 자동 기록한다.
#
# 문제: finish-plan-dev.sh 의 push 게이트가 이 marker 존재 여부를 검사하는데,
# marker touch 책임이 advisor agent 본인의 지시 준수에 의존해 구조적으로 취약함
# (LLM 이 지시를 빼먹으면 게이트가 오차단됨). 이 hook 이 tool_input 을 직접 보고
# 자동으로 기록해 그 의존을 없앤다.
#
# 어떤 경로든 세션을 막지 않음 — 항상 exit 0.
set -uo pipefail

PAYLOAD=$(cat)

TOOL=$(printf '%s' "$PAYLOAD" | grep -o '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*"([^"]*)"$/\1/')
case "$TOOL" in
  Task|Agent) ;;
  *) exit 0 ;;
esac

SUBAGENT=$(printf '%s' "$PAYLOAD" | grep -o '"subagent_type"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*"([^"]*)"$/\1/')
case "$SUBAGENT" in
  *commit-advisor*) ;;
  *) exit 0 ;;
esac

GIT_COMMON_DIR=$(git rev-parse --git-common-dir 2>/dev/null) || exit 0
touch "$GIT_COMMON_DIR/plan-dev-commit-advised" 2>/dev/null || true

exit 0
