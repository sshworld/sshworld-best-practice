#!/usr/bin/env bash
# Stop hook — 직전 응답(마지막 user 메시지 이후 모든 assistant 줄)의
# 토큰 사용량 + 캐시 히트율을 한 줄로 출력.
#
# 비활성화:
#   export DISABLE_TOKEN_STATS=1

set -u

[ "${DISABLE_TOKEN_STATS:-0}" = "1" ] && exit 0

command -v jq > /dev/null 2>&1 || exit 0
command -v awk > /dev/null 2>&1 || exit 0

payload=$(cat)
transcript=$(printf '%s' "$payload" | jq -r '.transcript_path // empty' 2>/dev/null || echo "")
[ -z "$transcript" ] && exit 0
[ ! -f "$transcript" ] && exit 0

# 마지막 user 메시지 줄 번호 (없으면 1 — 전체 합산)
# transcript 의 type=user 줄에는 (a) 실제 사용자 prompt, (b) tool_result 두 종류가 있음.
# tool_result 줄은 tool_use_id 키를 가지므로 그걸로 제외 → 진짜 사용자 prompt 만 매칭.
last_user_line=$(grep -n '"type":"user"' "$transcript" 2>/dev/null | grep -v 'tool_use_id' | tail -1 | cut -d: -f1)
last_user_line=${last_user_line:-1}

# 그 이후 assistant 줄의 usage 합산 + cache hit ratio
# transcript jsonl 은 .message.usage 경로에 usage 가 들어 있음 (구버전 .usage 는 fallback)
stats=$(tail -n +"$((last_user_line+1))" "$transcript" 2>/dev/null \
  | jq -s '
    [.[] | select(.type=="assistant") | (.message.usage // .usage) | select(. != null)] as $u
    | {
        i:  ([$u[].input_tokens]                | add // 0),
        cc: ([$u[].cache_creation_input_tokens] | add // 0),
        cr: ([$u[].cache_read_input_tokens]     | add // 0),
        o:  ([$u[].output_tokens]               | add // 0)
      }
    | . + {
        hit: (
          if (.i + .cc + .cr) > 0
          then ((.cr * 1000 / (.i + .cc + .cr)) | round / 10)
          else 0
          end
        )
      }
    | "\(.i)|\(.cc)|\(.cr)|\(.o)|\(.hit)"
  ' -r 2>/dev/null)

[ -z "$stats" ] && stats="0|0|0|0|0"

# 사람이 읽을 메시지 한 줄 생성
msg=$(printf '%s\n' "$stats" | awk -F'|' '
function fmt(n) {
  if (n < 1000)    return sprintf("%d", n)
  if (n < 1000000) return sprintf("%.1fk", n/1000)
  return sprintf("%.1fM", n/1000000)
}
{
  printf "💰 in=%s cache_c=%s cache_r=%s out=%s | cache hit %s%%",
    fmt($1), fmt($2), fmt($3), fmt($4), $5
}')

# Claude Code 는 stdout 의 JSON {"systemMessage": "..."} 만 UI inline 노출
jq -n --arg m "$msg" '{systemMessage: $m}'

exit 0
