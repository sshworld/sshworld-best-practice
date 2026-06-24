#!/usr/bin/env bash
# PreToolUse ExitPlanMode — cmux 환경에서 plan Slice File Map 의 direct-edit 표셀 차단.
#
# 목적: cmux 환경에서 Slice File Map Mode 컬럼에 direct-edit 가 반사적으로 들어가는 걸 하드 차단.
#   ExitPlanMode 시점에 plan 본문을 검사해 파이프로 감싸진 direct-edit 셀이 있으면 exit 2.
#   cmux 환경 기본은 dispatch(cmux) — 반사적 direct-edit 는 plan mode 게이트에서 잡음.
#
# 판정:
#   - CMUX_WORKSPACE_ID 미set → no-op (비-cmux 환경, direct-edit 기본 유지)
#   - tool_name 이 ExitPlanMode 가 아님 → no-op
#   - tool_input.plan 추출 실패 / 비어있음 → conservative exit 0
#   - plan 본문에서 \|[^|]*direct-edit[^|]*\| 매치 없음 → exit 0
#   - 매치 있음 → exit 2 차단 (CMUX_DIRECT_EDIT_OK=1 escape 명시 유도)
#
# 우회:
#   CMUX_DIRECT_EDIT_OK=1             — 의식적 escape (ExitPlanMode 게이트 1회 통과)
#   SKIP_CMUX_DISPATCH_GATE=1         — 1회 우회
#   DISABLE_CMUX_DISPATCH_GATE_HOOK=1 — 영구 비활성
set -uo pipefail

[ "${DISABLE_CMUX_DISPATCH_GATE_HOOK:-0}" = "1" ] && exit 0
[ "${SKIP_CMUX_DISPATCH_GATE:-0}" = "1" ] && exit 0
[ "${CMUX_DIRECT_EDIT_OK:-0}" = "1" ] && exit 0

# 비-cmux 환경 → direct-edit 기본, no-op
[ -z "${CMUX_WORKSPACE_ID:-}" ] && exit 0

PAYLOAD=$(cat)

TOOL=$(printf '%s' "$PAYLOAD" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null || echo "")
[ "$TOOL" = "ExitPlanMode" ] || exit 0

PLAN=$(printf '%s' "$PAYLOAD" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('plan',''))" 2>/dev/null || echo "")
[ -n "$PLAN" ] || exit 0

# 표셀 direct-edit 매치: 파이프로 감싸진 셀에서만 탐지 (산문 오탐 회피)
if printf '%s' "$PLAN" | grep -Eq '\|[^|]*direct-edit[^|]*\|'; then
  cat >&2 <<'EOF'
🛑 [enforce-cmux-dispatch] cmux 환경 plan 의 Slice File Map 에 direct-edit Mode 발견.
   cmux 는 dispatch(cmux) 기본 — 슬라이스를 dispatch-slice-pane.sh --mode=cmux 로 돌려라.
   정말 direct-edit 가 맞으면(정책/문서/하네스 파일 자체 편집 등) 의식적으로 선언:
     CMUX_DIRECT_EDIT_OK=1 <명령>   — 이번 plan 1회 통과
   우회:
     SKIP_CMUX_DISPATCH_GATE=1          — 1회 우회
     DISABLE_CMUX_DISPATCH_GATE_HOOK=1  — 영구 비활성
EOF
  exit 2
fi

exit 0
