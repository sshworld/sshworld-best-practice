#!/usr/bin/env bash
# dispatch-slice-pane.sh — implementor 슬라이스를 tmux pane 에서 실행하기 위한 spawner.
#
# 사용:
#   dispatch-slice-pane.sh --slice=<kebab> --spec-file=<path> \
#                          [--worktree=<path>] [--mode=interactive|background]
#
# 동작:
#   1. tmux + wrapper(tmux-cli 또는 scripts/tmux-pane.sh) 검출
#   2. git worktree 준비 (slice/<kebab> 브랜치, 기본 경로 .worktrees/<kebab>)
#   3. tmux pane 띄움 (zsh) → cd <worktree> → claude 실행 (또는 DISPATCH_CHILD_CMD)
#   4. spec 파일 내용을 prompt 로 전송
#   5. stdout 한 줄 JSON: {"pane":"...","worktree":"...","branch":"slice/<kebab>"}
#
# 완료 감지는 호출자 책임:
#   $wrapper wait-idle --pane=$pane --idle=10 --timeout=1800
#   $wrapper capture   --pane=$pane | tail -50 | grep -E '^(✅|❌)'

set -uo pipefail

SLICE=""
SPEC_FILE=""
WORKTREE=""
MODE="interactive"

usage() {
  cat >&2 <<'USAGE'
dispatch-slice-pane.sh --slice=<kebab> --spec-file=<path> [--worktree=<path>] [--mode=interactive|background]

환경변수:
  DISPATCH_CHILD_CMD=<cmd>   자식 명령 강제 (테스트용 substitute. 기본: claude)
USAGE
  exit 2
}

die() { echo "dispatch: $*" >&2; exit "${2:-1}"; }

# 인자 파싱
while [ $# -gt 0 ]; do
  case "$1" in
    --slice=*)      SLICE="${1#*=}"; shift ;;
    --slice)        SLICE="$2"; shift 2 ;;
    --spec-file=*)  SPEC_FILE="${1#*=}"; shift ;;
    --spec-file)    SPEC_FILE="$2"; shift 2 ;;
    --worktree=*)   WORKTREE="${1#*=}"; shift ;;
    --worktree)     WORKTREE="$2"; shift 2 ;;
    --mode=*)       MODE="${1#*=}"; shift ;;
    --mode)         MODE="$2"; shift 2 ;;
    -h|--help)      usage ;;
    *)              die "unknown arg: $1" 2 ;;
  esac
done

[ -z "$SLICE" ] && { echo "dispatch: --slice 필요" >&2; usage; }
[ -z "$SPEC_FILE" ] && { echo "dispatch: --spec-file 필요" >&2; usage; }
[ ! -f "$SPEC_FILE" ] && die "spec-file 없음: $SPEC_FILE" 2

command -v tmux > /dev/null 2>&1 || die "tmux 미설치 — brew install tmux" 2

# wrapper 결정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRAPPER=""
if command -v tmux-cli > /dev/null 2>&1; then
  WRAPPER="tmux-cli"
elif [ -x "$SCRIPT_DIR/tmux-pane.sh" ]; then
  WRAPPER="$SCRIPT_DIR/tmux-pane.sh"
else
  die "wrapper 미발견 — tmux-cli 설치 또는 scripts/tmux-pane.sh 확인" 2
fi

# worktree 결정 / 생성
[ -z "$WORKTREE" ] && WORKTREE=".worktrees/$SLICE"

if [ ! -d "$WORKTREE" ]; then
  # 브랜치 있나? 없으면 생성, 있으면 reuse
  if git show-ref --verify --quiet "refs/heads/slice/$SLICE"; then
    git worktree add "$WORKTREE" "slice/$SLICE" >&2 || die "worktree add 실패 (기존 브랜치)"
  else
    git worktree add -b "slice/$SLICE" "$WORKTREE" HEAD >&2 || die "worktree add 실패 (신규 브랜치)"
  fi
fi

WORKTREE_ABS="$(cd "$WORKTREE" && pwd)"

# 자식 명령 결정
CHILD_CMD="${DISPATCH_CHILD_CMD:-}"
if [ -z "$CHILD_CMD" ]; then
  case "$MODE" in
    interactive) CHILD_CMD="claude" ;;
    background)
      echo "dispatch: --mode=background 는 현재 stub — interactive 로 폴백" >&2
      CHILD_CMD="claude"
      ;;
    *) die "unknown mode: $MODE" 2 ;;
  esac
fi

# pane 띄우기 — 항상 zsh 먼저, 그 다음 cd + 자식 명령
PANE=$("$WRAPPER" launch zsh) || die "wrapper launch 실패"

"$WRAPPER" send "cd $WORKTREE_ABS" --pane="$PANE" --delay=0.3 >/dev/null || die "send cd 실패"
"$WRAPPER" wait-idle --pane="$PANE" --idle=1 --timeout=10 >/dev/null 2>&1 || true

"$WRAPPER" send "$CHILD_CMD" --pane="$PANE" --delay=0.3 >/dev/null || die "send child 실패"
"$WRAPPER" wait-idle --pane="$PANE" --idle=1 --timeout=15 >/dev/null 2>&1 || true

# spec 내용 주입 (단일 send — 줄바꿈 보존). 길면 tmux send-keys 자체가 처리.
SPEC_BODY=$(cat "$SPEC_FILE")
"$WRAPPER" send "$SPEC_BODY" --pane="$PANE" --delay=0.5 >/dev/null || die "send spec 실패"

# JSON 출력
printf '{"pane":"%s","worktree":"%s","branch":"slice/%s"}\n' "$PANE" "$WORKTREE_ABS" "$SLICE"
