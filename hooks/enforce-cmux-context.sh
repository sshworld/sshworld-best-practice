#!/usr/bin/env bash
# enforce-cmux-context.sh — PreToolUse Bash matcher.
# cmux 안 (CMUX_WORKSPACE_ID set) 에서 부모가 tmux 계열 명령 시도 시 advisory warning.
# STRICT 모드(CMUX_CONTEXT_HOOK_STRICT=1)에서만 차단(exit 2).
#
# stdin: {"tool_name":"Bash","tool_input":{"command":"..."}, ...}
# exit 0: 통과 (advisory 포함 가능) / exit 2: 차단 (STRICT 모드만)
#
# 우회:
#   SKIP_CMUX_CONTEXT_HOOK=1    — 1회 우회 (advisory 억제)
#   DISABLE_CMUX_CONTEXT_HOOK=1 — 영구 비활성화
#   CMUX_CONTEXT_HOOK_STRICT=1  — 반대로 차단 모드 활성화

set -uo pipefail

# stdin 항상 흡수
PAYLOAD=$(cat)

# 우회 환경변수 검사
if [ "${SKIP_CMUX_CONTEXT_HOOK:-0}" = "1" ] || [ "${DISABLE_CMUX_CONTEXT_HOOK:-0}" = "1" ]; then
  exit 0
fi

# tool_name 이 Bash 인지 확인 (그 외 exit 0)
TOOL_NAME=$(echo "$PAYLOAD" | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    print(d.get('tool_name',''))
except Exception:
    pass
" 2>/dev/null)

if [ "$TOOL_NAME" != "Bash" ]; then
  exit 0
fi

# command 추출
CMD=$(echo "$PAYLOAD" | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    print(d.get('tool_input',{}).get('command',''))
except Exception:
    pass
" 2>/dev/null)

# cmux 환경 검사: CMUX_WORKSPACE_ID 가 set 되어 있어야 함
if [ -z "${CMUX_WORKSPACE_ID:-}" ]; then
  exit 0
fi

# 명령을 세미콜론 / && / || / 파이프 기준으로 분할해 각 segment 의 첫 토큰을 검사
# POSIX sh 호환 방식으로 처리
MATCHED=0

# 구분자로 split: ; && || |
# sed 로 구분자를 newline 으로 치환 후 첫 토큰 추출
while IFS= read -r segment; do
  # leading whitespace 제거
  token=$(echo "$segment" | sed 's/^[[:space:]]*//' | awk '{print $1}')
  case "$token" in
    tmux|tmux-cli|tmux-pane.sh|./scripts/tmux-pane.sh|scripts/tmux-pane.sh)
      MATCHED=1
      break
      ;;
  esac
done < <(echo "$CMD" | sed 's/;/\n/g; s/&&/\n/g; s/||/\n/g; s/|/\n/g')

if [ "$MATCHED" -eq 0 ]; then
  exit 0
fi

# 매치된 경우 처리
if [ "${CMUX_CONTEXT_HOOK_STRICT:-0}" = "1" ]; then
  cat >&2 <<'EOF'
enforce-cmux-context: [STRICT] cmux 안에서 tmux 계열 명령 차단.
  cmux 환경에선 ${CLAUDE_PLUGIN_ROOT}/scripts/cmux-pane.sh 를 사용하세요.

우회:
  SKIP_CMUX_CONTEXT_HOOK=1    — 1회 우회
  DISABLE_CMUX_CONTEXT_HOOK=1 — 영구 비활성화
  CMUX_CONTEXT_HOOK_STRICT=   — (unset) strict 모드 해제
EOF
  exit 2
fi

# Advisory 모드 (기본): 경고만 출력하고 통과
cat >&2 <<'EOF'
⚠️  cmux 안에서 tmux 계열 명령 시도 — cmux 환경에선 ${CLAUDE_PLUGIN_ROOT}/scripts/cmux-pane.sh 사용 권장.
   (이번엔 통과. 차단 모드: CMUX_CONTEXT_HOOK_STRICT=1, 영구 비활성화: DISABLE_CMUX_CONTEXT_HOOK=1)
EOF

exit 0
