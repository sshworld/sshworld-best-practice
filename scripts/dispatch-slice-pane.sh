#!/usr/bin/env bash
# dispatch-slice-pane.sh — implementor 슬라이스를 tmux/cmux pane/workspace 에서 실행하기 위한 spawner.
#
# 사용:
#   dispatch-slice-pane.sh --slice=<kebab> --spec-file=.claude/specs/<kebab>.spec.md \
#                          [--worktree=<path>] [--mode=tmux|cmux|pane|auto|subagent] \
#                          [--model=<alias>] [--type=feat|fix|refactor|test|docs|chore]
#
# 권장 spec-file 위치: .claude/specs/<slug>.spec.md (kebab-case slug + .spec.md 접미사).
# /tmp/ 등 repo 밖 위치는 classifier transcript-blind 시 dispatch 거부될 수 있어 비권장.
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
#   5. spec 파일 경로를 Read 지시 prompt 로 전송 (본문 inline 전송 금지)
#   6. stdout 한 줄 JSON:
#        일반:  {"pane":"...","worktree":"...","branch":"<type>/<kebab>","driver":"tmux|cmux"}
#        DRY:   {"driver":"...","wrapper":"...","worktree":"...","branch":"<type>/<kebab>"}
#
# 자식 명령 결정 우선순위 (build_child_cmd):
#   DISPATCH_CHILD_CMD env > --model=<arg> > DISPATCH_DEFAULT_MODEL env > "sonnet"
#
# 완료 감지·회수는 호출자 책임 — 단일 경로 reap (lenient 마커 패턴, ⏺/들여쓰기 prefix 허용):
#   $wrapper reap --pane=$pane --idle=15 --timeout=900
#   (hand-rolled capture + strict-column-0 grep 금지 — 실제 TUI 렌더 ⏺ ✅ 못 잡음)
#
# 환경변수:
#   DISPATCH_DRY_RUN=1              wrapper 호출 직전 driver/wrapper/worktree JSON 출력 후 exit 0.
#                                    테스트에서 실제 launch 없이 분기 검증 시 사용.
#   DISPATCH_CHILD_CMD=<cmd>        자식 명령 강제 (테스트용 substitute. --model 보다 우선).
#   DISPATCH_DEFAULT_MODEL=<alias>  --model arg 가 없을 때의 기본 model (기본: sonnet).
#   DISPATCH_DEFAULT_TYPE=<type>    --type 미지정 시 기본 type (기본: feat).
#   DISPATCH_DEFAULT_MODE=<mode>    --mode 미지정 시 기본 driver mode (기본: auto). 기존 동작 복원: DISPATCH_DEFAULT_MODE=pane.
#   DISPATCH_SKIP_CLEANUP=1         시작 시 자식 pane 자동 정리 끄기.
#   DISPATCH_PERMISSION_MODE=<mode> 자식 claude 에 --permission-mode <mode> flag 전달. "default" 시 flag 생략.
#                                    기본값: bypassPermissions. DISPATCH_CHILD_CMD set 시 무시.
#   DISPATCH_VERIFY=0               cmux 자식 기동 검증 전체 스킵 (기본: on). 기존 동작 보존 시 사용.
#   DISPATCH_VERIFY_TRIES=<n>       claude TUI 기동 검증 최대 재시도 횟수 (기본: 3).

set -uo pipefail

usage() {
  cat >&2 <<'USAGE'
dispatch-slice-pane.sh --slice=<kebab> --spec-file=.claude/specs/<kebab>.spec.md \
                       [--worktree=<path>] [--mode=tmux|cmux|pane|auto|subagent] \
                       [--model=<alias>] [--type=feat|fix|refactor|test|docs|chore]

권장 spec-file 위치: .claude/specs/<slug>.spec.md (kebab-case + .spec.md).

모드:
  tmux / pane  tmux pane dispatch (기본, 기존 호환)
  cmux         cmux workspace dispatch
  auto         환경 자동 감지 (TMUX > CMUX > 에러)
  subagent     안내만 출력 후 exit 0 (plan-dev 기본 흐름에서 직접 호출 불필요)

환경변수:
  DISPATCH_DRY_RUN=1              launch 없이 결정된 driver/wrapper/worktree JSON 출력 후 exit 0.
  DISPATCH_CHILD_CMD=<cmd>        자식 명령 강제 (테스트용. --model 보다 우선).
  DISPATCH_DEFAULT_MODEL=<alias>  --model 미지정 시 기본 model (기본: sonnet).
  DISPATCH_DEFAULT_TYPE=<type>    --type 미지정 시 기본 type (기본: feat).
  DISPATCH_SKIP_CLEANUP=1         자동 pane 정리 끄기.
  DISPATCH_PERMISSION_MODE=<mode> 자식 claude 에 --permission-mode <mode> flag 전달 (기본: bypassPermissions). "default" 시 flag 생략.
  DISPATCH_VERIFY=0               cmux 자식 기동 검증 스킵 (기본: on). 기존 동작 보존 시 사용.
  DISPATCH_VERIFY_TRIES=<n>       TUI 기동 검증 최대 재시도 횟수 (기본: 3).
USAGE
  exit 2
}

die() { echo "dispatch: $*" >&2; exit "${2:-1}"; }

# cmux wrapper launch stdout 검증. 인자: pane_ref. stdout: 트림된 ref (성공 시), exit 1 (실패 시).
# cmux-pane.sh launch 는 "surface:N" 또는 "workspace:N" 단일 토큰 한 줄을 stdout 으로 반환하는 계약.
# 위반 시 fail-fast (silent tail -1 같은 recovery 는 다음 버그를 덮음).
# tmux pane ref (session:window.pane 형식) 는 별도 분기에서 처리 — 이 함수는 cmux 전용.
validate_pane_ref() {
  local pane="$1"
  pane=$(printf '%s' "$pane" | tr -d '\r\n')
  case "$pane" in
    surface:*|workspace:*) printf '%s' "$pane"; return 0 ;;
    *) return 1 ;;
  esac
}

# 순수 함수 — 부수효과 0, stdout 으로 CHILD_CMD 한 줄 반환.
# 우선순위: child_cmd_env > model_arg > default_model_env > hard-coded "sonnet"
# permission_mode_env: DISPATCH_PERMISSION_MODE 전달. "default" 시 flag 생략. 기본: bypassPermissions.
# 참고: mode 인자(interactive/background)는 내부 호환 유지용, 외부 --mode 와 다름.
build_child_cmd() {
  local child_cmd_env="${1:-}"
  local mode="${2:-interactive}"
  local model_arg="${3:-}"
  local default_model_env="${4:-}"
  local permission_mode_env="${5:-}"

  if [ -n "$child_cmd_env" ]; then
    printf '%s' "$child_cmd_env"
    return 0
  fi

  local model="$model_arg"
  [ -z "$model" ] && model="$default_model_env"
  [ -z "$model" ] && model="sonnet"

  local perm="$permission_mode_env"
  [ -z "$perm" ] && perm="bypassPermissions"

  case "$mode" in
    interactive)
      if [ "$perm" = "default" ]; then
        printf 'claude --model %s' "$model"
      else
        printf 'claude --model %s --permission-mode %s' "$model" "$perm"
      fi
      ;;
    background)
      echo "dispatch: background 는 현재 stub — interactive 로 폴백" >&2
      if [ "$perm" = "default" ]; then
        printf 'claude --model %s' "$model"
      else
        printf 'claude --model %s --permission-mode %s' "$model" "$perm"
      fi
      ;;
    *) die "unknown exec mode: $mode" 2 ;;
  esac
}

# 순수 함수 — spec 파일 경로를 자식 Claude 에게 Read 지시하는 짧은 prompt 반환.
# 인자: spec_file_abs_path, slice
# stdout: 자식에게 보낼 짧은 instruction prompt 한 줄.
# 의도: spec 본문을 inline 전송하면 cmux send 에서 timeout 위험 → 경로만 전달 + Read 지시.
build_spec_prompt() {
  local spec_path="$1"
  local slice="$2"
  printf 'Read %s 한 후 그 spec 의 지시대로 TDD (Red→Green→Refactor) 로 작업해. 작업 끝나면 마지막 줄에 `✅ %s` (성공) 또는 `❌ %s <reason>` (실패) 만 출력.' \
    "$spec_path" "$slice" "$slice"
}

# plan-dev 세션 marker 의 start_ts 필드 읽기 (jq 우선, python3 폴백). 실패 시 빈 문자열.
_dispatch_marker_start_ts() {
  local marker="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -r '.start_ts // empty' "$marker" 2>/dev/null
  else
    python3 -c "
import json
try:
    d = json.load(open('$marker'))
    print(d.get('start_ts', '') or '')
except Exception:
    print('')
" 2>/dev/null
  fi
}

# plan-dev 세션당 자동 cleanup 을 1회로 원자화.
# stamp 파일(<git-common-dir>/plan-dev-dispatch-cleaned) 에 현재 marker 의 start_ts 를 기록해
# 같은 세션의 후속/병렬 dispatch 가 방금 뜬 자식을 다시 죽이는 걸 방지.
# marker 부재(비-plan-dev 단독 dispatch) → 기존대로 매회 cleanup (한계 known).
# ⚠️ 순서 엄수: stamp 원자 생성 → cleanup. 반대면 병렬 dispatch race 로 방금 뜬 자식을 죽인다.
_dispatch_maybe_cleanup() {
  local wrapper="$1"
  local git_common
  git_common=$(git rev-parse --git-common-dir 2>/dev/null) || { "$wrapper" cleanup || true; return 0; }

  local marker="${git_common}/plan-dev-session.json"
  if [ ! -f "$marker" ]; then
    "$wrapper" cleanup || true
    return 0
  fi

  local start_ts
  start_ts=$(_dispatch_marker_start_ts "$marker")
  if [ -z "$start_ts" ]; then
    "$wrapper" cleanup || true
    return 0
  fi

  local stamp="${git_common}/plan-dev-dispatch-cleaned"
  if [ -f "$stamp" ]; then
    local stamp_content
    stamp_content=$(cat "$stamp" 2>/dev/null || true)
    if [ "$stamp_content" = "$start_ts" ]; then
      return 0  # 이 세션에서 이미 cleanup 완료 — skip
    fi
    rm -f "$stamp"
  fi

  # noclobber 서브셸로 stamp 원자 생성 — 생성에 성공한 프로세스만 cleanup 실행.
  # 동시 dispatch 가 먼저 생성했으면(경쟁 패배) cleanup skip.
  if (set -o noclobber; echo "$start_ts" > "$stamp") 2>/dev/null; then
    "$wrapper" cleanup || true
  fi
  return 0
}

# plan_file latch — 최초 dispatch 시 marker 의 plan_file 이 없거나(또는 stat 불가) 이면
# PLAN_MODE_PLANS_DIR 에서 start_ts-GRACE 이후 mtime 최신 plan 1개를 골라 set-plan 으로 기록.
# 세션격리를 LLM 의 set-plan 준수에 걸지 않기 위한 결정적 신호 (enforce-dispatch-gate.sh 가 소비).
# best-effort — 실패해도 dispatch 자체를 막지 않음 (호출부에서 || true).
_dispatch_latch_plan_file() {
  local git_common
  git_common=$(git rev-parse --git-common-dir 2>/dev/null) || return 0
  local marker="${git_common}/plan-dev-session.json"
  [ -f "$marker" ] || return 0

  local existing_plan_file
  existing_plan_file=$(python3 -c "
import json
try:
    d = json.load(open('$marker'))
    print(d.get('plan_file', '') or '')
except Exception:
    print('')
" 2>/dev/null || echo "")
  if [ -n "$existing_plan_file" ] && [ -f "$existing_plan_file" ]; then
    return 0  # 이미 latch 됨 + 유효 — 재latch 안 함
  fi

  local start_ts
  start_ts=$(_dispatch_marker_start_ts "$marker")
  [ -z "$start_ts" ] && return 0

  local plans_dir="${PLAN_MODE_PLANS_DIR:-$HOME/.claude/plans}"
  [ -d "$plans_dir" ] || return 0

  local grace=600
  local candidate
  candidate=$(START_TS="$start_ts" GRACE="$grace" PD="$plans_dir" python3 -c "
import os, glob, datetime
try:
    st = datetime.datetime.fromisoformat(os.environ['START_TS'].replace('Z', '+00:00'))
    threshold = st.timestamp() - float(os.environ['GRACE'])
    cands = sorted(
        (os.path.getmtime(p), p)
        for p in glob.glob(os.path.join(os.environ['PD'], '*.md'))
        if os.path.getmtime(p) >= threshold
    )
    if cands:
        print(cands[-1][1])
except Exception:
    pass
" 2>/dev/null || echo "")
  [ -z "$candidate" ] && return 0

  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local session_bin="$script_dir/plan-dev-session.sh"
  [ -x "$session_bin" ] || return 0
  "$session_bin" set-plan "$candidate" >/dev/null 2>&1 || true
  return 0
}

# launch 시작 시 cmux edit-burst 카운터 리셋 (track-cmux-edit-burst hook 과 연동)
_cmux_burst_reset() {
  [ -z "${CMUX_WORKSPACE_ID:-}" ] && return 0
  local f
  if [ -n "${CBP_BURST_FILE:-}" ]; then
    f="$CBP_BURST_FILE"
  else
    local sanitized
    sanitized=$(printf '%s' "$CMUX_WORKSPACE_ID" | tr ':/' '__')
    f="${HOME}/.cache/cbp/edit-burst-${sanitized}.count"
  fi
  [ -f "$f" ] && rm -f "$f"
  return 0
}

main() {
  local SLICE=""
  local SPEC_FILE=""
  local WORKTREE=""
  local DRIVER_MODE=""       # tmux|cmux|pane|auto|subagent — env DISPATCH_DEFAULT_MODE 우선, 미지정 시 auto
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

  # --mode 결정: arg > env DISPATCH_DEFAULT_MODE > auto (환경 자동 감지)
  [ -z "$DRIVER_MODE" ] && DRIVER_MODE="${DISPATCH_DEFAULT_MODE:-auto}"

  # --type 결정: arg > env > 기본값 feat
  [ -z "$TYPE" ] && TYPE="${DISPATCH_DEFAULT_TYPE:-feat}"

  # --type 검증
  case "$TYPE" in
    feat|fix|refactor|test|docs|chore) ;;
    *) die "허용되지 않는 type: $TYPE (allowed: feat|fix|refactor|test|docs|chore)" 2 ;;
  esac

  # branch prefix: commit type 은 conventional 유지(feat), branch 는 feat→feature 매핑
  local BRANCH_TYPE="$TYPE"
  [ "$TYPE" = "feat" ] && BRANCH_TYPE="feature"

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

  # cmux edit-burst 카운터 리셋 — dry-run 포함 항상 실행
  _cmux_burst_reset

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
    # "echo" 는 테스트 mock — 존재 검사 skip. DRY_RUN 도 실제 spawn 없으니 skip.
    if [ "${DISPATCH_DRY_RUN:-0}" != "1" ] && [ "$cmux_bin" != "echo" ] && [ "$cmux_bin" != "$( (command -v echo) 2>/dev/null || true)" ]; then
      command -v "$cmux_bin" > /dev/null 2>&1 || die "cmux 미설치 — brew tap manaflow-ai/cmux && brew install cmux" 2
    fi
    if [ -x "$SCRIPT_DIR/cmux-pane.sh" ]; then
      WRAPPER="$SCRIPT_DIR/cmux-pane.sh"
    else
      die "cmux-pane.sh 미발견 — scripts/cmux-pane.sh 확인" 2
    fi
  fi

  # 비-git 판정은 DRY_RUN 출력보다 **먼저** — dry-run 이 실제 결정과 같은 값을 내야 한다.
  #
  # 비-git 디렉토리(문서 트리·Obsidian vault 등)에서는 worktree 격리가 불가능하다.
  # 예전엔 `git worktree add` 가 실패해 하드 종료했고 우회(--worktree) 안내도 없어,
  # 비-git 대상에는 문서화된 경로로 dispatch 자체가 불가능했다. 격리는 목적이 아니라
  # **슬라이스간 파일 충돌 방지 수단**이고 그 충돌은 plan 의 Slice File Map 이 관리한다.
  local _IS_GIT=1
  git rev-parse --git-dir >/dev/null 2>&1 || _IS_GIT=0
  if [ "$_IS_GIT" = "0" ] && [ -z "$WORKTREE" ]; then
    WORKTREE="$PWD"
    echo "dispatch: 비-git 디렉토리 — worktree 격리 없이 현재 경로로 진행합니다." >&2
    echo "  슬라이스가 같은 파일을 쓰면 충돌합니다. plan 의 Slice File Map 을 확인하세요." >&2
  fi

  # DRY_RUN: worktree 생성 없이 결정 JSON 만 출력
  if [ "${DISPATCH_DRY_RUN:-0}" = "1" ]; then
    local worktree_path="${WORKTREE:-.worktrees/$SLICE}"
    local trust_flag="true"
    [ "${SKIP_DISPATCH_TRUST:-0}" = "1" ] && trust_flag="false"
    printf '{"driver":"%s","wrapper":"%s","worktree":"%s","branch":"%s/%s","trust_seeded":%s}\n' \
      "$DRIVER" "$WRAPPER" "$worktree_path" "$BRANCH_TYPE" "$SLICE" "$trust_flag"
    exit 0
  fi

  # 새 작업 시작 시 기존 자식 pane 일괄 정리 (tmux 전용, tmux-pane.sh wrapper 사용 시)
  # in-tmux 환경에서 spawn 한 split pane 은 사용자가 attach 중일 수 있어 보존.
  # plan-dev 세션 활성 시 세션당 1회만 (병렬/연속 dispatch 가 서로의 작업 중 자식을 죽이는 것 방지).
  # 우회: DISPATCH_SKIP_CLEANUP=1
  if [ "${DISPATCH_SKIP_CLEANUP:-0}" != "1" ] && [ "$DRIVER" = "tmux" ] && [ "$WRAPPER" = "$SCRIPT_DIR/tmux-pane.sh" ]; then
    _dispatch_maybe_cleanup "$WRAPPER"
  fi

  # worktree 결정 / 생성 (비-git 판정은 위 DRY_RUN 앞에서 이미 끝났다)
  [ -z "$WORKTREE" ] && WORKTREE=".worktrees/$SLICE"

  if [ "$_IS_GIT" = "1" ] && [ ! -d "$WORKTREE" ]; then
    # 호환성: 기존 slice/<kebab> 브랜치가 있으면 그것을 재사용, 없으면 <type>/<kebab> 신규 생성
    if git show-ref --verify --quiet "refs/heads/slice/$SLICE"; then
      git worktree add "$WORKTREE" "slice/$SLICE" >&2 || die "worktree add 실패 (기존 slice/ 브랜치)"
    elif git show-ref --verify --quiet "refs/heads/$BRANCH_TYPE/$SLICE"; then
      git worktree add "$WORKTREE" "$BRANCH_TYPE/$SLICE" >&2 || die "worktree add 실패 (기존 branch)"
    else
      git worktree add -b "$BRANCH_TYPE/$SLICE" "$WORKTREE" HEAD >&2 || die "worktree add 실패 (신규 브랜치)"
    fi
  fi

  local WORKTREE_ABS
  WORKTREE_ABS="$(cd "$WORKTREE" && pwd)"

  # worktree trust 자동 시딩 — cross-machine bypass 자동화 (trust 다이얼로그 회피)
  if [ "${SKIP_DISPATCH_TRUST:-0}" != "1" ]; then
    "$SCRIPT_DIR/trust-dir.sh" "$WORKTREE_ABS" >/dev/null 2>&1 || true
  fi

  # plan_file latch — 세션격리, best-effort (실패해도 dispatch 는 계속)
  _dispatch_latch_plan_file || true

  # 자식 명령 결정 (순수 함수 호출) — 내부 실행 모드는 항상 interactive
  local CHILD_CMD
  CHILD_CMD=$(build_child_cmd "${DISPATCH_CHILD_CMD:-}" "interactive" "$MODEL" "${DISPATCH_DEFAULT_MODEL:-}" "${DISPATCH_PERMISSION_MODE:-}")

  # pane/workspace 띄우기 — cmd 없이 빈 surface 생성, 이후 send 로 cd + 자식 명령 전달
  # (launch cmd 인자 제거: nested zsh 회피. grid 경로는 send 시퀀스로 처리)
  local PANE PANE_RAW
  PANE_RAW=$("$WRAPPER" launch) || die "wrapper launch 실패"
  # cmux: surface:N / workspace:N 단일 토큰 strict 계약.
  # tmux: session:window.pane 형식 (driver 외부) — CRLF 트림 + 빈값 거부만.
  if [ "$DRIVER" = "cmux" ]; then
    PANE=$(validate_pane_ref "$PANE_RAW") || \
      die "wrapper launch 계약 위반: PANE='$PANE_RAW' (expected surface:N 또는 workspace:N 단일 토큰). wrapper 의 stdout 격리 확인."
  else
    PANE=$(printf '%s' "$PANE_RAW" | tr -d '\r\n')
    [ -z "$PANE" ] && die "wrapper launch 실패: pane ref 가 비어있음"
  fi

  "$WRAPPER" send "cd $(printf '%q' "$WORKTREE_ABS")" --pane="$PANE" --delay=0.3 >/dev/null || die "send cd 실패"
  "$WRAPPER" wait-idle --pane="$PANE" --idle=1 --timeout=10 >/dev/null 2>&1 || true

  # 자식 셸에 정확한 surface:N ref 를 CBP_SELF_PANE 로 주입 — 자식 claude(및 Stop hook) 가
  # env 상속 → notify-slice-done.sh 의 done-marker line1 이 UUID($CMUX_SURFACE_ID) 대신
  # surface:N namespace 로 기록되어 reap fast-path/wrapper 라우팅과 정합.
  # best-effort (send 유실 시에도 dispatch 계속 — wrapper 의 UUID --surface belt 가 커버).
  "$WRAPPER" send "export CBP_SELF_PANE=$(printf '%q' "$PANE")" --pane="$PANE" --delay=0.3 >/dev/null || true
  "$WRAPPER" wait-idle --pane="$PANE" --idle=1 --timeout=8 >/dev/null 2>&1 || true

  "$WRAPPER" send "$CHILD_CMD" --pane="$PANE" --delay=0.3 >/dev/null || die "send child 실패"
  "$WRAPPER" wait-idle --pane="$PANE" --idle=1 --timeout=15 >/dev/null 2>&1 || true

  # ── cmux 자식 기동 검증 (DISPATCH_VERIFY != 0, DRIVER=cmux 일 때만) ──
  local VERIFY_TRIES="${DISPATCH_VERIFY_TRIES:-3}"
  if [ "$DRIVER" = "cmux" ] && [ "${DISPATCH_VERIFY:-1}" != "0" ]; then
    local tui_ok=0
    local vtry=1
    while [ "$vtry" -le "$VERIFY_TRIES" ]; do
      local cap_out
      cap_out=$("$WRAPPER" capture --pane="$PANE" 2>/dev/null) || true
      if printf '%s' "$cap_out" | grep -qE '(│|╰|╭|[?] for shortcuts|Forming|Undulating|✳|claude|Claude)'; then
        tui_ok=1
        break
      fi
      # 미감지 → CHILD_CMD 재전송 후 재시도
      if [ "$vtry" -lt "$VERIFY_TRIES" ]; then
        "$WRAPPER" send "$CHILD_CMD" --pane="$PANE" --delay=0.3 >/dev/null 2>&1 || true
        sleep 0.5
      fi
      vtry=$((vtry + 1))
    done

    if [ "$tui_ok" -eq 0 ]; then
      # 검증 실패 — surface 정리 best-effort 후 명확 실패
      "$WRAPPER" kill --pane="$PANE" >/dev/null 2>&1 || true
      echo "dispatch: cmux dispatch 자식 기동/생존 검증 실패 (pane=$PANE, tries=$VERIFY_TRIES)" >&2
      echo "dispatch: cmux PTY 불안정 가능. subagent 모드로 폴백 권장:" >&2
      echo "  plan-dev Phase 2 의 Agent(subagent_type=implementor) 호출 또는" >&2
      echo "  dispatch-slice-pane.sh --mode=subagent." >&2
      echo "dispatch: worktree=$WORKTREE_ABS 는 부모가 정리하세요 (git worktree remove --force)." >&2
      exit 3
    fi
  fi
  # ─────────────────────────────────────────────────────────────────────────

  local SPEC_FILE_ABS
  SPEC_FILE_ABS="$(cd "$(dirname "$SPEC_FILE")" && pwd)/$(basename "$SPEC_FILE")"
  local SPEC_PROMPT
  SPEC_PROMPT=$(build_spec_prompt "$SPEC_FILE_ABS" "$SLICE")
  if [ "$DRIVER" = "cmux" ]; then
    "$WRAPPER" send "$SPEC_PROMPT" --pane="$PANE" --delay=0.5 --enter-count=2 >/dev/null || die "send spec-prompt 실패"
  else
    "$WRAPPER" send "$SPEC_PROMPT" --pane="$PANE" --delay=0.5 >/dev/null || die "send spec-prompt 실패"
  fi
  "$WRAPPER" wait-idle --pane="$PANE" --idle=2 --timeout=8 >/dev/null 2>&1 || true

  # ── SPEC 후 surface 생존 확인 (cmux + verify on) ──
  if [ "$DRIVER" = "cmux" ] && [ "${DISPATCH_VERIFY:-1}" != "0" ]; then
    local post_cap
    post_cap=$("$WRAPPER" capture --pane="$PANE" 2>/dev/null) || {
      echo "dispatch: spec 전송 후 surface 사망 감지 (pane=$PANE)" >&2
      echo "dispatch: subagent 모드로 폴백 권장: dispatch-slice-pane.sh --mode=subagent." >&2
      exit 3
    }
    if [ -z "$post_cap" ]; then
      echo "dispatch: spec 전송 후 surface 가 비어있음 (pane=$PANE) — PTY 불안정 가능" >&2
      echo "dispatch: subagent 모드로 폴백 권장: dispatch-slice-pane.sh --mode=subagent." >&2
      exit 3
    fi
  fi

  # 계보 원장에 자식 기록 (best-effort — 실패해도 dispatch 는 성공으로 둔다).
  # 회수는 전역 스윕이 아니라 이 원장을 근거로만 한다 → 남의 surface·자기 자신을
  # 건드릴 수 없다. 📎 scripts/reap-agents.sh
  if [ "${SKIP_SPAWN_LEDGER:-0}" != "1" ]; then
    _reaper="$(dirname "${BASH_SOURCE[0]}")/reap-agents.sh"
    if [ -x "$_reaper" ]; then
      "$_reaper" record --kind="$DRIVER" --ref="$PANE" \
        ${CMUX_WORKSPACE_ID:+--ws="$CMUX_WORKSPACE_ID"} --label="$SLICE" >/dev/null 2>&1 || true
    fi
  fi

  printf '{"pane":"%s","worktree":"%s","branch":"%s/%s","driver":"%s"}\n' \
    "$PANE" "$WORKTREE_ABS" "$BRANCH_TYPE" "$SLICE" "$DRIVER"
}

# Sourcing guard — 직접 실행 시에만 main 호출. test 가 source 하면 함수만 노출.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
