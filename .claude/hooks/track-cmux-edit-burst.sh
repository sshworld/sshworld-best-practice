#!/usr/bin/env bash
# PreToolUse Write|Edit — cmux 환경에서 Edit/Write 누적 횟수를 카운트하고 임계치 초과 시 advisory.
# 우회: SKIP_CMUX_EDIT_BURST=1 (1회) / DISABLE_CMUX_EDIT_BURST_HOOK=1 (영구)
# 차단: CMUX_EDIT_BURST_STRICT=1 (exit 2)
set -uo pipefail

PAYLOAD=$(cat)

[ "${DISABLE_CMUX_EDIT_BURST_HOOK:-0}" = "1" ] && exit 0
[ "${SKIP_CMUX_EDIT_BURST:-0}" = "1" ] && exit 0

[ -z "${CMUX_WORKSPACE_ID:-}" ] && exit 0

TOOL=$(printf '%s' "$PAYLOAD" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null || echo "")
case "$TOOL" in Write|Edit) ;; *) exit 0 ;; esac

# 카운터 파일 경로 (CBP_BURST_FILE 우선 — 테스트 mock)
if [ -n "${CBP_BURST_FILE:-}" ]; then
  COUNT_FILE="$CBP_BURST_FILE"
else
  _ws_sanitized=$(printf '%s' "$CMUX_WORKSPACE_ID" | tr ':/' '__')
  COUNT_FILE="${HOME}/.cache/cbp/edit-burst-${_ws_sanitized}.count"
fi
mkdir -p "$(dirname "$COUNT_FILE")"

# 자동 리셋: mtime idle
IDLE_SEC="${CMUX_EDIT_BURST_IDLE_SEC:-300}"
NOW=$(date +%s)
if [ -f "$COUNT_FILE" ]; then
  MTIME=$(stat -f %m "$COUNT_FILE" 2>/dev/null || stat -c %Y "$COUNT_FILE" 2>/dev/null || echo 0)
  if [ $((NOW - MTIME)) -ge "$IDLE_SEC" ]; then
    echo 0 > "$COUNT_FILE"
  fi
fi

# 카운터 증가
CUR=$(cat "$COUNT_FILE" 2>/dev/null || echo 0)
CUR=$((CUR + 1))
echo "$CUR" > "$COUNT_FILE"

# 임계치 체크
THRESHOLD="${CMUX_EDIT_BURST_THRESHOLD:-2}"
if [ "$CUR" -lt "$THRESHOLD" ]; then
  exit 0
fi

MSG=$(cat <<EOF
⚠️  cmux 환경 Edit/Write 누적 ${CUR}회 (임계치 ${THRESHOLD}) — dispatch 미사용 의심.
   가시화/병렬 가치가 있으면: scripts/dispatch-slice-pane.sh --mode=cmux --type=<type> --spec-file=<spec.md>
   소규모/직접 편집이 맞으면: 무시 (이 메시지는 advisory).
   ↳ 우회하기 전: dispatch 선택지 (cmux-pane.sh launch) 를 의식적으로 검토했는지 확인.

우회:
  SKIP_CMUX_EDIT_BURST=1         — 1회 우회
  DISABLE_CMUX_EDIT_BURST_HOOK=1 — 영구 비활성
  CMUX_EDIT_BURST_THRESHOLD=N    — 임계치 override
  CMUX_EDIT_BURST_STRICT=1       — 차단 모드 활성화
EOF
)

if [ "${CMUX_EDIT_BURST_STRICT:-0}" = "1" ]; then
  printf '%s\n' "$MSG" >&2
  echo "STRICT 모드 — 차단 (exit 2)" >&2
  exit 2
fi

printf '%s\n' "$MSG" >&2
exit 0
