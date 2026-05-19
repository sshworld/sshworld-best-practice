#!/usr/bin/env bash
# dispatch-slice-pane.sh — implementor 슬라이스를 tmux/cmux pane/workspace 에서 실행하기 위한 spawner.
#
# 사용:
#   dispatch-slice-pane.sh --slice=<kebab> --spec-file=<path> \
#                          [--worktree=<path>] [--mode=tmux|cmux|pane|auto|subagent] \
#                          [--model=<alias>] [--type=feat|fix|refactor|test|docs|chore]
#
# --mode 옵션 (driver 선택):
#   tmux      — tmux pane dispatch (tmux-cli 또는 tmux-pane.sh wrapper)
#   pane      — tmux 의 alias (기존 호환)
#   cmux      — cmux workspace dispatch (cmux-pane.sh wrapper)
#   auto      — detect-pane-env.sh 결과로 자동 선택 (tmux > cmux > error)
#   subagent  — 안내 메시지만 출력 후 exit 0 (subagent 모드는 이 스크립트 불필요)
#   (미지정)  — pane (tmux) 이 기본값 (기존 호환)
#
# 동작:
#   1. driver 결정 (--mode 또는 detect_pane_env)
#   2. wrapper 결정 (tmux: tmux-cli 또는 tmux-pane.sh / cmux: cmux-pane.sh)
#   3. git worktree 준비 (<type>/<kebab> 브랜치, 기본 경로 .worktrees/<kebab>)
#   4. pane/workspace 띄움 (zsh) → cd <worktree> → 자식 명령 실행
#   5. spec 파일 내용을 prompt 로 전송
#   6. stdout 한 줄 JSON:
#        일반:  {"pane":"...","worktree":"...","branch":"<type>/<kebab>","driver":"tmux|cmux"}
#        DRY:   {"driver":"...","wrapper":"...","worktree":"...","branch":"<type>/<kebab>"}
#
# 자식 명령 결정 우선순위 (build_child_cmd):
#   DISPATCH_CHILD_CMD env > --model=<arg> > DISPATCH_DEFAULT_MODEL env > "sonnet"
#
# 완료 감지는 호출자 책임:
#   $wrapper wait-idle --pane=$pane --idle=10 --timeout=1800
#   $wrapper capture   --pane=$pane | tail -50 | grep -E '^(✅|❌)'
#
# 환경변수:
#   DISPATCH_DRY_RUN=1             wrapper 호출 직전 driver/wrapper/worktree JSON 출력 후 exit 0.
#                                   테스트에서 실제 launch 없이 분기 검증 시 사용.
#   DISPATCH_CHILD_CMD=<cmd>       자식 명령 강제 (테스트용 substitute. --model 보다 우선).
#   DISPATCH_DEFAULT_MODEL=<alias> --model arg 가 없을 때의 기본 model (기본: sonnet).
#   DISPATCH_DEFAULT_TYPE=<type>   --type 미지정 시 기본 type (기본: feat).
#   DISPATCH_SKIP_CLEANUP=1        시작 시 자식 pane 자동 정리 끄기.

set -uo pipefail

usage() {
  cat >&2 <<'USAGE'
dispatch-slice-pane.sh --slice=<kebab> --spec-file=<path> \
                       [--worktree=<path>] [--mode=tmux|cmux|pane|auto|subagent] \
                       [--model=<alias>] [--type=feat|fix|refactor|test|docs|chore]

모드:
  tmux / pane  tmux pane dispatch (기본, 기존 호환)
  cmux         cmux workspace dispatch
  auto         환경 자동 감지 (TMUX > CMUX > 에러)
  subagent     안내만 출력 후 exit 0 (plan-dev 기본 흐름에서 직접 호출 불필요)

환경변수:
  DISPATCH_DRY_RUN=1             launch 없이 결정된 driver/wrapper/worktree JSON 출력 후 exit 0.
  DISPATCH_CHILD_CMD=<cmd>       자식 명령 강제 (테스트용. --model 보다 우선).
  DISPATCH_DEFAULT_MODEL=<alias> --model 미지정 시 기본 model (기본: sonnet).
  DISPATCH_DEFAULT_TYPE=<type>   --type 미지정 시 기본 type (기본: feat).
  DISPATCH_SKIP_CLEANUP=1        자동 pane 정리 끄기.
USAGE
  exit 2
}

die() { echo "dispatch: $*" >&2; exit "${2:-1}"; }

# 순수 함수 — 부수효과 0, stdout 으로 CHILD_CMD 한 줄 반환.
# 우선순위: child_cmd_env > model_arg > default_model_env > hard-coded "sonnet"
# 참고: mode 인자(interactive/background)는 내부 호환 유지용, 외부 --mode 와 다름.
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
      echo "dispatch: background 는 현재 stub — interactive 로 폴백" >&2
      printf 'claude --model %s' "$model"
      ;;
    *) die "unknown exec mode: $mode" 2 ;;
  esac
}

main() {
  local SLICE=""
  local SPEC_FILE=""
  local WORKTREE=""
  local DRIVER_MODE="pane"   # tmux|cmux|pane|auto|subagent
  local MODEL=""
  local TYPE=""              # feat|fix|refactor|test|docs|chore (기본: feat)

  while [ $# -gt 0 ]; do
    case "$1" in
      --slice=*)      SLICE="${1#*=}"; shift ;;
      --slice)        SLICE="$2"; shift 2 ;;
      --spec-file=*)  SPEC_FILE="${1#*=}"; shift ;;
      --spec-file)    SPEC_FILE="$2"; shift 2 ;;
      --worktree=*)   WORKTREE="${1#*=}"; shift ;;
      --worktree)     WORKTREE="$2"; shift 2 ;;
      --mode=*)       DRIVER_MODE="${1#*=}"; shift ;;
      --mode)         DRIVER_MODE="$2"; shift 2 ;;
      --driver=*)     DRIVER_MODE="${1#*=}"; shift ;;
      --driver)       DRIVER_MODE="$2"; shift 2 ;;
      --model=*)      MODEL="${1#*=}"; shift ;;
      --model)        MODEL="$2"; shift 2 ;;
      --type=*)       TYPE="${1#*=}"; shift ;;
      --type)         TYPE="$2"; shift 2 ;;
      -h|--help)      usage ;;
      *)              die "unknown arg: $1" 2 ;;
    esac
  done

  # --type 결정: arg > env > 기본값 feat
  [ -z "$TYPE" ] && TYPE="${DISPATCH_DEFAULT_TYPE:-feat}"

  # --type 검증
  case "$TYPE" in
    feat|fix|refactor|test|docs|chore) ;;
    *) die "허용되지 않는 type: $TYPE (allowed: feat|fix|refactor|test|docs|chore)" 2 ;;
  esac

  [ -z "$SLICE" ] && { echo "dispatch: --slice 필요" >&2; usage; }
  [ -z "$SPEC_FILE" ] && { echo "dispatch: --spec-file 필요" >&2; usage; }

  # --slice 검증: 빈 문자열 / 슬래시 포함 불가
  [ -z "$SLICE" ] && die "--slice 값이 비어있습니다" 2
  case "$SLICE" in
    */*) die "--slice 에 슬래시를 포함할 수 없습니다: $SLICE" 2 ;;
  esac

  # subagent 모드 — 안내만, exit 0
  if [ "$DRIVER_MODE" = "subagent" ]; then
    echo "dispatch: subagent 모드는 dispatch-slice-pane.sh 미사용 — plan-dev Phase 2 의 Agent 호출로 진행" >&2
    exit 0
  fi

  # DRY_RUN 아닐 때만 spec-file 존재 검사
  if [ "${DISPATCH_DRY_RUN:-0}" != "1" ]; then
    [ ! -f "$SPEC_FILE" ] && die "spec-file 없음: $SPEC_FILE" 2
  fi

  local SCRIPT_DIR
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  # driver 결정
  local DRIVER=""
  case "$DRIVER_MODE" in
    tmux|pane)
      DRIVER="tmux"
      ;;
    cmux)
      DRIVER="cmux"
      ;;
    auto)
      # detect-pane-env.sh 로 환경 자동 감지
      local env_result
      env_result=$(bash "$SCRIPT_DIR/detect-pane-env.sh")
      case "$env_result" in
        tmux)    DRIVER="tmux" ;;
        cmux)    DRIVER="cmux" ;;
        default) die "auto 감지: tmux/cmux 환경 아님 — --mode=subagent (plan-dev 기본) 또는 --mode=tmux/cmux 를 명시하세요" 2 ;;
        *)       die "auto 감지: 알 수 없는 결과 '$env_result'" 2 ;;
      esac
      ;;
    *)
      die "알 수 없는 --mode: $DRIVER_MODE (tmux|cmux|pane|auto|subagent 중 하나)" 2
      ;;
  esac

  # wrapper 결정
  local WRAPPER=""
  if [ "$DRIVER" = "tmux" ]; then
    command -v tmux > /dev/null 2>&1 || die "tmux 미설치 — brew install tmux" 2
    if command -v tmux-cli > /dev/null 2>&1; then
      WRAPPER="tmux-cli"
    elif [ -x "$SCRIPT_DIR/tmux-pane.sh" ]; then
      WRAPPER="$SCRIPT_DIR/tmux-pane.sh"
    else
      die "wrapper 미발견 — tmux-cli 설치 또는 scripts/tmux-pane.sh 확인" 2
    fi
  elif [ "$DRIVER" = "cmux" ]; then
    local cmux_bin="${CMUX_BIN:-cmux}"
    # "echo" 는 테스트 mock — 존재 검사 skip
    if [ "$cmux_bin" != "echo" ] && [ "$cmux_bin" != "$( (command -v echo) 2>/dev/null || true)" ]; then
      command -v "$cmux_bin" > /dev/null 2>&1 || die "cmux 미설치 — brew tap manaflow-ai/cmux && brew install cmux" 2
    fi
    if [ -x "$SCRIPT_DIR/cmux-pane.sh" ]; then
      WRAPPER="$SCRIPT_DIR/cmux-pane.sh"
    else
      die "cmux-pane.sh 미발견 — scripts/cmux-pane.sh 확인" 2
    fi
  fi

  # DRY_RUN: worktree 생성 없이 결정 JSON 만 출력
  if [ "${DISPATCH_DRY_RUN:-0}" = "1" ]; then
    local worktree_path="${WORKTREE:-.worktrees/$SLICE}"
    printf '{"driver":"%s","wrapper":"%s","worktree":"%s","branch":"%s/%s"}\n' \
      "$DRIVER" "$WRAPPER" "$worktree_path" "$TYPE" "$SLICE"
    exit 0
  fi

  # 새 작업 시작 시 기존 자식 pane 일괄 정리 (tmux 전용, tmux-pane.sh wrapper 사용 시)
  # in-tmux 환경에서 spawn 한 split pane 은 사용자가 attach 중일 수 있어 보존.
  # 우회: DISPATCH_SKIP_CLEANUP=1
  if [ "${DISPATCH_SKIP_CLEANUP:-0}" != "1" ] && [ "$DRIVER" = "tmux" ] && [ "$WRAPPER" = "$SCRIPT_DIR/tmux-pane.sh" ]; then
    "$WRAPPER" cleanup || true
  fi

  # worktree 결정 / 생성
  [ -z "$WORKTREE" ] && WORKTREE=".worktrees/$SLICE"

  if [ ! -d "$WORKTREE" ]; then
    # 호환성: 기존 slice/<kebab> 브랜치가 있으면 그것을 재사용, 없으면 <type>/<kebab> 신규 생성
    if git show-ref --verify --quiet "refs/heads/slice/$SLICE"; then
      git worktree add "$WORKTREE" "slice/$SLICE" >&2 || die "worktree add 실패 (기존 slice/ 브랜치)"
    elif git show-ref --verify --quiet "refs/heads/$TYPE/$SLICE"; then
      git worktree add "$WORKTREE" "$TYPE/$SLICE" >&2 || die "worktree add 실패 (기존 type/ 브랜치)"
    else
      git worktree add -b "$TYPE/$SLICE" "$WORKTREE" HEAD >&2 || die "worktree add 실패 (신규 브랜치)"
    fi
  fi

  local WORKTREE_ABS
  WORKTREE_ABS="$(cd "$WORKTREE" && pwd)"

  # 자식 명령 결정 (순수 함수 호출) — 내부 실행 모드는 항상 interactive
  local CHILD_CMD
  CHILD_CMD=$(build_child_cmd "${DISPATCH_CHILD_CMD:-}" "interactive" "$MODEL" "${DISPATCH_DEFAULT_MODEL:-}")

  # pane/workspace 띄우기 — 항상 zsh 먼저, 그 다음 cd + 자식 명령
  local PANE
  PANE=$("$WRAPPER" launch zsh) || die "wrapper launch 실패"

  "$WRAPPER" send "cd $WORKTREE_ABS" --pane="$PANE" --delay=0.3 >/dev/null || die "send cd 실패"
  "$WRAPPER" wait-idle --pane="$PANE" --idle=1 --timeout=10 >/dev/null 2>&1 || true

  "$WRAPPER" send "$CHILD_CMD" --pane="$PANE" --delay=0.3 >/dev/null || die "send child 실패"
  "$WRAPPER" wait-idle --pane="$PANE" --idle=1 --timeout=15 >/dev/null 2>&1 || true

  local SPEC_BODY
  SPEC_BODY=$(cat "$SPEC_FILE")
  "$WRAPPER" send "$SPEC_BODY" --pane="$PANE" --delay=0.5 >/dev/null || die "send spec 실패"

  printf '{"pane":"%s","worktree":"%s","branch":"%s/%s","driver":"%s"}\n' \
    "$PANE" "$WORKTREE_ABS" "$TYPE" "$SLICE" "$DRIVER"
}

# Sourcing guard — 직접 실행 시에만 main 호출. test 가 source 하면 함수만 노출.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
