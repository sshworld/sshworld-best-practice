#!/usr/bin/env bash
# enforce-cmux-context.sh — PreToolUse Bash matcher.
# cmux/orca 안에서 부모가 **다른** 멀티플렉서 계열 명령(tmux, 또는 상대 진영의
# -pane.sh 래퍼)을 시도할 때 advisory warning. 자기 진영 래퍼(cmux 안의
# cmux-pane.sh, orca 안의 orca-pane.sh)는 매치 대상이 아니다.
# STRICT 모드(CMUX_CONTEXT_HOOK_STRICT=1)에서만 차단(exit 2).
#
# stdin: {"tool_name":"Bash","tool_input":{"command":"..."}, ...}
# exit 0: 통과 (advisory 포함 가능) / exit 2: 차단 (STRICT 모드만)
#
# 멀티플렉서 종류 판정은 직접 신호(env var)만 본다 — 이 훅은 **모든 Bash 호출마다**
# 발화하므로(가장 hot 한 hook), scripts/detect-pane-env.sh 의 ping/status 프로브를
# 여기서 쓰면 비-mux 사용자의 매 명령마다 외부 프로세스가 뜬다. 신호가 없으면
# (프로브 없이) 곧장 default 로 간주 — 이 훅의 목적상 "확실한 자기 진영"을 모르면
# 경고할 근거도 없으므로 안전하다.
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

# 멀티플렉서 종류 판정 (직접 신호만 — 프로브 없음, 위 헤더 코멘트 참조)
if [ -n "${CMUX_WORKSPACE_ID:-}" ] || [ -n "${CMUX_SURFACE_ID:-}" ] || [ -n "${CMUX_SOCKET:-}" ] || [ -n "${CMUX_SOCKET_PASSWORD:-}" ]; then
  MUX_KIND="cmux"
elif [ -n "${ORCA_TERMINAL_HANDLE:-}" ] || [ -n "${ORCA_WORKSPACE_ID:-}" ] || [ "${TERM_PROGRAM:-}" = "Orca" ]; then
  MUX_KIND="orca"
else
  exit 0
fi

# 명령을 세미콜론 / && / || / 파이프 기준으로 분할해 각 segment 의 첫 토큰을 검사
# POSIX sh 호환 방식으로 처리
MATCHED=0
MATCH_REASON=""

# 구분자로 split: ; && || |
# sed 로 구분자를 newline 으로 치환 후 첫 토큰 추출
while IFS= read -r segment; do
  # leading whitespace 제거 후 토큰화, 선행 env 할당 토큰(FOO=bar) 은 skip 하고 실제 명령 토큰 탐색
  clean=$(echo "$segment" | sed 's/^[[:space:]]*//')
  set -- $clean
  while [ "$#" -gt 0 ]; do
    case "$1" in
      *=*) shift ;;
      *) break ;;
    esac
  done
  token="${1:-}"
  case "$token" in
    tmux|tmux-cli|tmux-pane.sh|./scripts/tmux-pane.sh|scripts/tmux-pane.sh|*/tmux-pane.sh)
      MATCHED=1
      MATCH_REASON="tmux"
      break
      ;;
    */cmux-pane.sh)
      # cmux 안이면 자기 진영 도구 — 매치 안 함. orca 안이면 "다른 진영" 이므로 매치.
      if [ "$MUX_KIND" = "orca" ]; then
        MATCHED=1
        MATCH_REASON="cmux-pane.sh"
        break
      fi
      ;;
    */orca-pane.sh)
      # orca 안이면 자기 진영 도구 — 매치 안 함. cmux 안이면 "다른 진영" 이므로 매치.
      if [ "$MUX_KIND" = "cmux" ]; then
        MATCHED=1
        MATCH_REASON="orca-pane.sh"
        break
      fi
      ;;
  esac
done < <(echo "$CMD" | sed 's/;/\n/g; s/&&/\n/g; s/||/\n/g; s/|/\n/g')

if [ "$MATCHED" -eq 0 ]; then
  exit 0
fi

if [ "$MATCH_REASON" = "tmux" ]; then
  WHAT="tmux 계열"
else
  WHAT="다른 멀티플렉서 계열($MATCH_REASON)"
fi

# 매치된 경우 처리
if [ "${CMUX_CONTEXT_HOOK_STRICT:-0}" = "1" ]; then
  cat >&2 <<EOF
enforce-cmux-context: [STRICT] ${MUX_KIND} 안에서 ${WHAT} 명령 차단.
  ${MUX_KIND} 환경에선 \${CLAUDE_PLUGIN_ROOT}/scripts/${MUX_KIND}-pane.sh 를 사용하세요.

우회:
  SKIP_CMUX_CONTEXT_HOOK=1    — 1회 우회
  DISABLE_CMUX_CONTEXT_HOOK=1 — 영구 비활성화
  CMUX_CONTEXT_HOOK_STRICT=   — (unset) strict 모드 해제
EOF
  exit 2
fi

# Advisory 모드 (기본): 경고만 출력하고 통과
cat >&2 <<EOF
⚠️  ${MUX_KIND} 안에서 ${WHAT} 명령 시도 — ${MUX_KIND} 환경에선 \${CLAUDE_PLUGIN_ROOT}/scripts/${MUX_KIND}-pane.sh 사용 권장.
   (이번엔 통과. 차단 모드: CMUX_CONTEXT_HOOK_STRICT=1, 영구 비활성화: DISABLE_CMUX_CONTEXT_HOOK=1)
EOF

exit 0
