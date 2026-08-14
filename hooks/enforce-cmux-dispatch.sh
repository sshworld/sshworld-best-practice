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

# skip-once marker-file escape (R1). git-dir 있으면 <git-common-dir>/cbp-skip-once-cmux-dispatch,
# 이 훅은 git 무관하게 발화하므로 git-common-dir 확보 실패 시 비-git cwd 폴백:
#   $HOME/.cache/cbp/cbp-skip-once-cmux-dispatch-<sanitized CMUX_WORKSPACE_ID>
_GIT_COMMON=$(git rev-parse --git-common-dir 2>/dev/null || true)
if [ -n "$_GIT_COMMON" ]; then
  _SKIP_ONCE_FILE="${_GIT_COMMON}/cbp-skip-once-cmux-dispatch"
else
  _SANITIZED_WS="${CMUX_WORKSPACE_ID//[:\/]/_}"
  _SKIP_ONCE_FILE="$HOME/.cache/cbp/cbp-skip-once-cmux-dispatch-${_SANITIZED_WS}"
fi
if rm "$_SKIP_ONCE_FILE" 2>/dev/null; then
  exit 0
fi

PAYLOAD=$(cat)

TOOL=$(printf '%s' "$PAYLOAD" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null || echo "")
[ "$TOOL" = "ExitPlanMode" ] || exit 0

PLAN=$(printf '%s' "$PAYLOAD" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('plan',''))" 2>/dev/null || echo "")
[ -n "$PLAN" ] || exit 0

# 표셀 direct-edit 매치: 파이프로 감싸진 셀에서만 탐지 (산문 오탐 회피)
if printf '%s' "$PLAN" | grep -Eq '\|[^|]*direct-edit[^|]*\|'; then
  # 안내 경로는 **훅이 실제로 소비하는 변수를 그대로 출력**한다.
  # 예전엔 여기서 경로를 하드코딩해, 비-git 폴백의 `-<sanitized WS>` 접미사가 빠진
  # 안내가 나갔다. 그대로 touch 하면 훅이 절대 보지 않는 파일이 생겨 재시도해도
  # 같은 자리에서 다시 차단됐다 (실측으로 밟은 함정).
  cat >&2 <<EOF
🛑 [enforce-cmux-dispatch] cmux 환경 plan 의 Slice File Map 에 direct-edit Mode 발견.
   cmux 는 dispatch(cmux) 기본 — 슬라이스를 dispatch-slice-pane.sh --mode=cmux 로 돌려라.
   정말 direct-edit 가 맞으면(정책/문서/하네스 파일 자체 편집 등) 의식적으로 선언:
     CMUX_DIRECT_EDIT_OK=1 <명령>   — 이번 plan 1회 통과
   또는 skip-once marker-file (이 훅이 실제로 소비하는 경로):
     touch "\$_SKIP_ONCE_FILE"
     # 현재 값: $_SKIP_ONCE_FILE
   우회:
     SKIP_CMUX_DISPATCH_GATE=1          — 1회 우회
     DISABLE_CMUX_DISPATCH_GATE_HOOK=1  — 영구 비활성
EOF
  exit 2
fi

exit 0
