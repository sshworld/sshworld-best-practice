#!/usr/bin/env bash
# open-doc.sh — 설계 문서 등을 사용자 화면에 연다.
# orca 세션이면 내장 에디터(`orca file open`)로, 그 외엔 OS 기본 오프너(open/xdg-open)로.
#
# 사용:
#   open-doc.sh <path>
#
# orca 관련 실측 제약:
#   - `orca file open <path> --json` 은 **현재 워크스페이스 안 경로만** 연다
#     (밖이면 ok:false, code:"invalid_relative_path").
#   - 설계 문서 기본 위치(`~/.claude/design/<repo>/`)는 워크스페이스 밖이라 그대로는 안 열린다.
#   - 워크스페이스 안의 **이미 존재하는 심볼릭 링크**를 경유하면 열린다(실측 확인).
#   - 이 스크립트는 심링크를 **자동 생성하지 않는다** — 플러그인으로 배포돼 임의의
#     남의 repo 에서도 돌아가므로, 남의 워크트리에 말없이 파일을 만들지 않는다.
#
# 환경변수:
#   ORCA_BIN            — orca 바이너리 경로 (기본 PATH 의 orca)
#   CBP_DESIGN_LINK      — 워크스페이스-상대 심링크 경로 (기본 `.claude/design`).
#                          이미 존재하는 심링크일 때만 경유 재시도에 사용한다.
#   OPEN_DOC_DRY_RUN=1   — 실제로 열지 않고, 실행하려던 OS 기본 오프너 명령 한 줄만 stdout 출력.
#                          (orca file open 자체는 실제 window 를 띄우지 않으므로 dry-run 대상 아님 —
#                          테스트는 대신 가짜 ORCA_BIN 을 주입한다.)
#
# exit code: 0 성공(연 것으로 간주, 폴백 포함) / 2 usage 오류 / 1 그 외(파일 없음 등).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORCA_BIN="${ORCA_BIN:-orca}"

die() { echo "open-doc: $*" >&2; exit "${2:-1}"; }

usage() {
  echo "usage: open-doc.sh <path>" >&2
  exit 2
}

[ $# -lt 1 ] && usage
TARGET="$1"

[ -e "$TARGET" ] || die "파일 없음: $TARGET"

ABS_TARGET="$(cd "$(dirname -- "$TARGET")" && pwd)/$(basename -- "$TARGET")"

# ----------------------------------------------------------------
# OS 기본 오프너 (darwin: open / 그 외: xdg-open). OPEN_DOC_DRY_RUN=1 이면
# 실행 대신 실행하려던 명령 한 줄만 stdout 출력 (테스트가 실창을 안 띄우게).
# ----------------------------------------------------------------
_os_opener() {
  if [ "$(uname)" = "Darwin" ]; then
    echo "open"
  else
    echo "xdg-open"
  fi
}

_os_open() {
  local path="$1" opener
  opener="$(_os_opener)"
  if [ "${OPEN_DOC_DRY_RUN:-0}" = "1" ]; then
    echo "$opener \"$path\""
    return 0
  fi
  "$opener" "$path"
}

# orca file open 호출. exit: 0 = ok:true / 1 = ok:false 또는 호출 실패.
# 계약: orca CLI 는 ok:false 를 exit code 0 으로도 반환할 수 있다 — exit code 불신,
# 항상 --json 응답의 `.ok` 만 신뢰한다.
_orca_file_open() {
  local path="$1" raw ok
  raw=$("$ORCA_BIN" file open "$path" --json 2>/dev/null)
  [ -z "$raw" ] && return 1
  ok=$(printf '%s' "$raw" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    print("false")
    sys.exit(0)
print("true" if d.get("ok") else "false")
' 2>/dev/null)
  [ "$ok" = "true" ]
}

KIND="$("$SCRIPT_DIR/detect-pane-env.sh")"

if [ "$KIND" != "orca" ]; then
  _os_open "$ABS_TARGET"
  exit 0
fi

if _orca_file_open "$ABS_TARGET"; then
  exit 0
fi

# ── 심링크 경유 재시도 (이미 존재하는 심링크만 — 자동 생성 금지) ──
LINK_REL="${CBP_DESIGN_LINK:-.claude/design}"
WS_ROOT="$(pwd)"
LINK_ABS="$WS_ROOT/$LINK_REL"

if [ -L "$LINK_ABS" ]; then
  # readlink(1단계만) — realpath 전체 해석은 macOS 의 /tmp↔/private/tmp 류 조상
  # 심링크까지 풀어버려 ABS_TARGET(비-해석 논리 경로)과 어긋난다.
  LINK_TARGET="$(readlink "$LINK_ABS")"
  case "$LINK_TARGET" in
    /*) : ;;
    *) LINK_TARGET="$(dirname -- "$LINK_ABS")/$LINK_TARGET" ;;
  esac
  case "$ABS_TARGET" in
    "$LINK_TARGET"/*)
      REL_SUFFIX="${ABS_TARGET#"$LINK_TARGET"/}"
      if _orca_file_open "$LINK_ABS/$REL_SUFFIX"; then
        exit 0
      fi
      ;;
  esac
fi

echo "open-doc: orca file open 실패 — OS 기본으로 폴백. 힌트: '$LINK_ABS' 를 대상 디렉토리로의 심링크로 만들면 다음부터 orca 내장 에디터로 열립니다." >&2
_os_open "$ABS_TARGET"
