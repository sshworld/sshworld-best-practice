#!/usr/bin/env bash
# dispatch-slice-pane.sh — implementor 슬라이스를 tmux pane 에서 실행하기 위한 spawner.
#
# 사용:
#   dispatch-slice-pane.sh --slice=<kebab> --spec-file=<path> \
#                          [--worktree=<path>] [--mode=interactive|background] \
#                          [--model=<alias>]
#
# 동작:
#   1. tmux + wrapper(tmux-cli 또는 scripts/tmux-pane.sh) 검출
#   2. git worktree 준비 (slice/<kebab> 브랜치, 기본 경로 .worktrees/<kebab>)
#   3. tmux pane 띄움 (zsh) → cd <worktree> → claude --model <alias> 실행
#   4. spec 파일 내용을 prompt 로 전송
#   5. stdout 한 줄 JSON: {"pane":"...","worktree":"...","branch":"slice/<kebab>"}
#
# 자식 명령 결정 우선순위 (build_child_cmd):
#   DISPATCH_CHILD_CMD env > --model=<arg> > DISPATCH_DEFAULT_MODEL env > "sonnet"
#
# 완료 감지는 호출자 책임:
#   $wrapper wait-idle --pane=$pane --idle=10 --timeout=1800
#   $wrapper capture   --pane=$pane | tail -50 | grep -E '^(✅|❌)'

set -uo pipefail

usage() {
  cat >&2 <<'USAGE'
dispatch-slice-pane.sh --slice=<kebab> --spec-file=<path> \
                       [--worktree=<path>] [--mode=interactive|background] \
                       [--model=<alias>]

환경변수:
  DISPATCH_CHILD_CMD=<cmd>       자식 명령 강제 (테스트용 substitute. --model 보다 우선).
  DISPATCH_DEFAULT_MODEL=<alias> --model arg 가 없을 때의 기본 model (기본: sonnet).
USAGE
  exit 2
}

die() { echo "dispatch: $*" >&2; exit "${2:-1}"; }

# 순수 함수 — 부수효과 0, stdout 으로 CHILD_CMD 한 줄 반환.
# 우선순위: child_cmd_env > model_arg > default_model_env > hard-coded "sonnet"
build_child_cmd() {
  local child_cmd_env="${1:-}"
  local mode="${2:-interactive}"
  local model_arg="${3:-}"
  local default_model_env="${4:-}"

  if [ -n "$child_cmd_env" ]; then
    printf '%s' "$child_cmd_env"
    return 0
  fi

  local model="$model_arg"
  [ -z "$model" ] && model="$default_model_env"
  [ -z "$model" ] && model="sonnet"

  case "$mode" in
    interactive) printf 'claude --model %s' "$model" ;;
    background)
      echo "dispatch: --mode=background 는 현재 stub — interactive 로 폴백" >&2
      printf 'claude --model %s' "$model"
      ;;
    *) die "unknown mode: $mode" 2 ;;
  esac
}

main() {
  local SLICE=""
  local SPEC_FILE=""
  local WORKTREE=""
  local MODE="interactive"
  local MODEL=""

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
      --model=*)      MODEL="${1#*=}"; shift ;;
      --model)        MODEL="$2"; shift 2 ;;
      -h|--help)      usage ;;
      *)              die "unknown arg: $1" 2 ;;
    esac
  done

  [ -z "$SLICE" ] && { echo "dispatch: --slice 필요" >&2; usage; }
  [ -z "$SPEC_FILE" ] && { echo "dispatch: --spec-file 필요" >&2; usage; }
  [ ! -f "$SPEC_FILE" ] && die "spec-file 없음: $SPEC_FILE" 2

  command -v tmux > /dev/null 2>&1 || die "tmux 미설치 — brew install tmux" 2

  # wrapper 결정
  local SCRIPT_DIR
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local WRAPPER=""
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
    if git show-ref --verify --quiet "refs/heads/slice/$SLICE"; then
      git worktree add "$WORKTREE" "slice/$SLICE" >&2 || die "worktree add 실패 (기존 브랜치)"
    else
      git worktree add -b "slice/$SLICE" "$WORKTREE" HEAD >&2 || die "worktree add 실패 (신규 브랜치)"
    fi
  fi

  local WORKTREE_ABS
  WORKTREE_ABS="$(cd "$WORKTREE" && pwd)"

  # 자식 명령 결정 (순수 함수 호출)
  local CHILD_CMD
  CHILD_CMD=$(build_child_cmd "${DISPATCH_CHILD_CMD:-}" "$MODE" "$MODEL" "${DISPATCH_DEFAULT_MODEL:-}")

  # pane 띄우기 — 항상 zsh 먼저, 그 다음 cd + 자식 명령
  local PANE
  PANE=$("$WRAPPER" launch zsh) || die "wrapper launch 실패"

  "$WRAPPER" send "cd $WORKTREE_ABS" --pane="$PANE" --delay=0.3 >/dev/null || die "send cd 실패"
  "$WRAPPER" wait-idle --pane="$PANE" --idle=1 --timeout=10 >/dev/null 2>&1 || true

  "$WRAPPER" send "$CHILD_CMD" --pane="$PANE" --delay=0.3 >/dev/null || die "send child 실패"
  "$WRAPPER" wait-idle --pane="$PANE" --idle=1 --timeout=15 >/dev/null 2>&1 || true

  local SPEC_BODY
  SPEC_BODY=$(cat "$SPEC_FILE")
  "$WRAPPER" send "$SPEC_BODY" --pane="$PANE" --delay=0.5 >/dev/null || die "send spec 실패"

  printf '{"pane":"%s","worktree":"%s","branch":"slice/%s"}\n' "$PANE" "$WORKTREE_ABS" "$SLICE"
}

# Sourcing guard — 직접 실행 시에만 main 호출. test 가 source 하면 함수만 노출.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
