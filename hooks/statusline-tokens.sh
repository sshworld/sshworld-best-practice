#!/usr/bin/env bash
# statusLine command — 직전 응답의 토큰 사용량 + 캐시 히트율을 한 줄로 stdout.
# Claude Code 의 settings.json 의 statusLine.command 로 등록되어 화면 하단 status bar 에 상시 표시.
#
# stdin: {"session_id": "...", "transcript_path": "...", "cwd": "...", "model": "..."} 등
# stdout: 한 줄 텍스트 (줄바꿈 없음 — status bar 한 줄)
#
# 비활성화: export DISABLE_TOKEN_STATS=1

set -u

[ "${DISABLE_TOKEN_STATS:-0}" = "1" ] && exit 0
command -v jq  > /dev/null 2>&1 || exit 0
command -v awk > /dev/null 2>&1 || exit 0

payload=$(cat)
transcript=$(printf '%s' "$payload" | jq -r '.transcript_path // empty' 2>/dev/null || echo "")
[ -z "$transcript" ] && exit 0
[ ! -f "$transcript" ] && exit 0

# 마지막 user 메시지 줄 (tool_result 가 아닌 진짜 prompt 만)
last_user_line=$(grep -n '"type":"user"' "$transcript" 2>/dev/null | grep -v 'tool_use_id' | tail -1 | cut -d: -f1)
last_user_line=${last_user_line:-1}

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

printf '%s\n' "$stats" | awk -F'|' '
function fmt(n) {
  if (n < 1000)    return sprintf("%d", n)
  if (n < 1000000) return sprintf("%.1fk", n/1000)
  return sprintf("%.1fM", n/1000000)
}
{
  # statusLine 은 한 줄이라 trailing newline 없이 출력
  printf "💰 in=%s cache_c=%s cache_r=%s out=%s | hit %s%%",
    fmt($1), fmt($2), fmt($3), fmt($4), $5
}'
