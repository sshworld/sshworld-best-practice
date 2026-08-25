#!/usr/bin/env bash
# PreToolUse ExitPlanMode — cmux/orca 환경에서 plan Slice File Map 의 direct-edit 표셀 차단.
#
# 목적: cmux/orca 환경에서 Slice File Map Mode 컬럼에 direct-edit 가 반사적으로 들어가는 걸 하드 차단.
#   ExitPlanMode 시점에 plan 본문을 검사해 파이프로 감싸진 direct-edit 셀이 있으면 exit 2.
#   cmux/orca 환경 기본은 dispatch(해당 멀티플렉서) — 반사적 direct-edit 는 plan mode 게이트에서 잡음.
#
# 판정:
#   - cmux/orca 신호 둘 다 미set → no-op (tmux·비-mux 환경, direct-edit 기본 유지)
#   - tool_name 이 ExitPlanMode 가 아님 → no-op
#   - tool_input.plan 추출 실패 / 비어있음 → conservative exit 0
#   - plan 본문에서 \|[^|]*direct-edit[^|]*\| 매치 없음 → exit 0
#   - 매치 있음 → exit 2 차단 (CBP_DIRECT_EDIT_OK=1 escape 명시 유도)
#
# 멀티플렉서 종류 판정은 직접 신호(env var)만 본다 — 이 훅은 ExitPlanMode 시점에만
# 드물게 발화하므로 지연 문제는 없지만, 어차피 dispatch 대상 세션은 cmux/orca 가
# 셸에 직접 주입한 env var 를 갖고 있어 ping/status 프로브가 필요 없다.
#
# 우회 (기존 CMUX_* 변수는 하위호환으로 계속 동작, CBP_* 는 동급 별칭):
#   CMUX_DIRECT_EDIT_OK=1 / CBP_DIRECT_EDIT_OK=1             — 의식적 escape (ExitPlanMode 게이트 1회 통과)
#   SKIP_CMUX_DISPATCH_GATE=1 / CBP_SKIP_DISPATCH_GATE=1     — 1회 우회
#   DISABLE_CMUX_DISPATCH_GATE_HOOK=1 / CBP_DISABLE_DISPATCH_GATE_HOOK=1 — 영구 비활성
set -uo pipefail

[ "${DISABLE_CMUX_DISPATCH_GATE_HOOK:-0}" = "1" ] && exit 0
[ "${CBP_DISABLE_DISPATCH_GATE_HOOK:-0}" = "1" ] && exit 0
[ "${SKIP_CMUX_DISPATCH_GATE:-0}" = "1" ] && exit 0
[ "${CBP_SKIP_DISPATCH_GATE:-0}" = "1" ] && exit 0
[ "${CMUX_DIRECT_EDIT_OK:-0}" = "1" ] && exit 0
[ "${CBP_DIRECT_EDIT_OK:-0}" = "1" ] && exit 0

# tmux·비-mux 환경 → direct-edit 기본, no-op. cmux 가 orca 보다 우선(기존 동작 보존).
if [ -n "${CMUX_WORKSPACE_ID:-}" ] || [ -n "${CMUX_SURFACE_ID:-}" ] || [ -n "${CMUX_SOCKET:-}" ] || [ -n "${CMUX_SOCKET_PASSWORD:-}" ]; then
  _MUX_NAME="cmux"
  _MODE="cmux"
  _WS_ID="${CMUX_WORKSPACE_ID:-${CMUX_SURFACE_ID:-${CMUX_SOCKET:-}}}"
elif [ -n "${ORCA_TERMINAL_HANDLE:-}" ] || [ -n "${ORCA_WORKSPACE_ID:-}" ] || [ "${TERM_PROGRAM:-}" = "Orca" ]; then
  _MUX_NAME="orca"
  _MODE="orca"
  _WS_ID="${ORCA_WORKSPACE_ID:-${ORCA_TERMINAL_HANDLE:-}}"
else
  exit 0
fi

# skip-once marker-file escape (R1). git-dir 있으면 <git-common-dir>/cbp-skip-once-cmux-dispatch,
# 이 훅은 git 무관하게 발화하므로 git-common-dir 확보 실패 시 비-git cwd 폴백:
#   $HOME/.cache/cbp/cbp-skip-once-cmux-dispatch-<sanitized 현재 워크스페이스 id>
# (cmux 면 CMUX_WORKSPACE_ID, orca 면 ORCA_WORKSPACE_ID — 위에서 정한 $_WS_ID 를 그대로 쓴다.)
_GIT_COMMON=$(git rev-parse --git-common-dir 2>/dev/null || true)
if [ -n "$_GIT_COMMON" ]; then
  _SKIP_ONCE_FILE="${_GIT_COMMON}/cbp-skip-once-cmux-dispatch"
else
  _SANITIZED_WS="${_WS_ID//[:\/]/_}"
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
🛑 [enforce-cmux-dispatch] ${_MUX_NAME} 환경 plan 의 Slice File Map 에 direct-edit Mode 발견.
   ${_MUX_NAME} 는 dispatch(${_MUX_NAME}) 기본 — 슬라이스를 dispatch-slice-pane.sh --mode=${_MODE} 로 돌려라.
   정말 direct-edit 가 맞으면(정책/문서/하네스 파일 자체 편집 등) 의식적으로 선언:
     CBP_DIRECT_EDIT_OK=1 <명령>   — 이번 plan 1회 통과 (구버전 호환: CMUX_DIRECT_EDIT_OK=1)
   또는 skip-once marker-file (이 훅이 실제로 소비하는 경로):
     touch "\$_SKIP_ONCE_FILE"
     # 현재 값: $_SKIP_ONCE_FILE
   우회:
     CBP_SKIP_DISPATCH_GATE=1 (구:SKIP_CMUX_DISPATCH_GATE=1)             — 1회 우회
     CBP_DISABLE_DISPATCH_GATE_HOOK=1 (구:DISABLE_CMUX_DISPATCH_GATE_HOOK=1) — 영구 비활성
EOF
  exit 2
fi

exit 0
