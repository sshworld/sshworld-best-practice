#!/usr/bin/env bash
# finish-plan-dev.sh — plan-dev 종료 시 develop/main 분기 push 자동화.
#
# 사용:
#   finish-plan-dev.sh [--dry-run] [--remote=<name>]
#
# 환경변수:
#   SKIP_PLAN_DEV_FINISH=1      → exit 0 + stdout "skipped (SKIP)"
#   DISABLE_PLAN_DEV_FINISH=1   → exit 0 + stdout "disabled"
#   GIT_PUSH_CMD                → 디폴트 "git push" (테스트에서 실패 명령 주입 시 사용)
#   PLAN_DEV_SESSION_BIN        → 디폴트 "<repo>/scripts/plan-dev-session.sh"
#                                 없으면 marker 파일 직접 파싱 폴백.

set -uo pipefail

# ── 상수 / 기본값 ──────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GIT_PUSH_CMD="${GIT_PUSH_CMD:-git push}"
PLAN_DEV_SESSION_BIN="${PLAN_DEV_SESSION_BIN:-$SCRIPT_DIR/plan-dev-session.sh}"

DRY_RUN=0
REMOTE="origin"

# ── 인자 파싱 ──────────────────────────────────────────────────────

for arg in "$@"; do
  case "$arg" in
    --dry-run)      DRY_RUN=1 ;;
    --remote=*)     REMOTE="${arg#*=}" ;;
    -h|--help)
      cat >&2 <<'USAGE'
finish-plan-dev.sh [--dry-run] [--remote=<name>]

  --dry-run      실제 git 명령 대신 실행할 명령 stdout 출력 후 exit 0
  --remote=<n>   push 대상 remote (디폴트: origin)

환경변수:
  SKIP_PLAN_DEV_FINISH=1     1회 우회 (exit 0 + "skipped (SKIP)")
  DISABLE_PLAN_DEV_FINISH=1  영구 비활성화 (exit 0 + "disabled")
  GIT_PUSH_CMD               push 명령 override (테스트용)
  PLAN_DEV_SESSION_BIN       plan-dev-session.sh 경로 override
USAGE
      exit 0 ;;
    *) ;;
  esac
done

# ── 우회 체크 ──────────────────────────────────────────────────────

if [ "${SKIP_PLAN_DEV_FINISH:-}" = "1" ]; then
  echo "skipped (SKIP)"
  exit 0
fi

if [ "${DISABLE_PLAN_DEV_FINISH:-}" = "1" ]; then
  echo "disabled"
  exit 0
fi

# ── JSON 파싱 헬퍼 (jq → python3 폴백) ────────────────────────────

json_get() {
  local file="$1" key="$2"
  if command -v jq >/dev/null 2>&1; then
    jq -r ".$key // empty" "$file"
  else
    python3 - "$file" "$key" <<'PYEOF'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    v = d.get(sys.argv[2], '')
    if v is None:
        v = ''
    # bool → lowercase string
    if isinstance(v, bool):
        print(str(v).lower())
    else:
        print(v)
except Exception:
    sys.exit(1)
PYEOF
  fi
}

# ── marker 위치 결정 ────────────────────────────────────────────────

COMMON_DIR="$(git rev-parse --git-common-dir 2>/dev/null)" || {
  echo "finish-plan-dev: git repo 가 아님" >&2
  exit 2
}
MARKER="${COMMON_DIR}/plan-dev-session.json"

if [ ! -f "$MARKER" ]; then
  echo "no marker — skip"
  exit 0
fi

# ── marker 파싱 ────────────────────────────────────────────────────

# plan-dev-session.sh query 사용 우선, 없으면 직접 파싱
if [ -x "$PLAN_DEV_SESSION_BIN" ]; then
  START_REF=$(  "$PLAN_DEV_SESSION_BIN" query --key=start_ref   2>/dev/null) || START_REF=""
  BASE_BRANCH=$(  "$PLAN_DEV_SESSION_BIN" query --key=base_branch 2>/dev/null) || BASE_BRANCH=""
  WORK_BRANCH=$(  "$PLAN_DEV_SESSION_BIN" query --key=work_branch 2>/dev/null) || WORK_BRANCH=""
  AUTO_BRANCH=$(  "$PLAN_DEV_SESSION_BIN" query --key=auto_branch 2>/dev/null) || AUTO_BRANCH="false"
else
  # 직접 파싱 폴백
  START_REF=$(  json_get "$MARKER" "start_ref")   || START_REF=""
  BASE_BRANCH=$(json_get "$MARKER" "base_branch") || BASE_BRANCH=""
  WORK_BRANCH=$(json_get "$MARKER" "work_branch") || WORK_BRANCH=""
  AUTO_BRANCH=$(json_get "$MARKER" "auto_branch") || AUTO_BRANCH="false"
fi

if [ -z "$START_REF" ] || [ -z "$BASE_BRANCH" ]; then
  echo "finish-plan-dev: marker 파싱 실패 (start_ref 또는 base_branch 없음)" >&2
  exit 2
fi

# ── 현재 HEAD branch 확인 ──────────────────────────────────────────

CUR_BRANCH="$(git symbolic-ref --short HEAD 2>/dev/null)" || {
  echo "finish-plan-dev: detached HEAD — push 불가" >&2
  exit 2
}

# ── Range 검증 ─────────────────────────────────────────────────────

NEW_COMMITS="$(git rev-list --count "${START_REF}..HEAD" 2>/dev/null)" || NEW_COMMITS="0"

if [ "$NEW_COMMITS" = "0" ]; then
  echo "no new commits since marker — skip"
  rm -f "$MARKER"
  exit 0
fi

# ── clear marker 헬퍼 ─────────────────────────────────────────────

clear_marker() {
  rm -f "$MARKER"
}

# ── develop 또는 main-only 분기 ────────────────────────────────────

# base_branch 의 local part (origin/develop → develop, develop → develop)
BASE_LOCAL="${BASE_BRANCH#origin/}"

# origin/develop 존재 여부로 develop case 판단
HAS_ORIGIN_DEVELOP=0
if git ls-remote --heads "$REMOTE" develop 2>/dev/null | grep -q develop; then
  HAS_ORIGIN_DEVELOP=1
fi

# base_branch 자체가 develop 이거나 origin/develop 이 있으면 develop case
USE_DEVELOP_CASE=0
if [ "$BASE_LOCAL" = "develop" ] || [ "$HAS_ORIGIN_DEVELOP" = "1" ]; then
  USE_DEVELOP_CASE=1
fi

if [ "$USE_DEVELOP_CASE" = "1" ]; then
  # ── Develop case ─────────────────────────────────────────────────

  # 현재 branch 가 base_branch (develop/main) 와 같으면 안 됨
  if [ "$CUR_BRANCH" = "$BASE_LOCAL" ] || [ "$CUR_BRANCH" = "develop" ] || [ "$CUR_BRANCH" = "$BASE_BRANCH" ]; then
    echo "finish-plan-dev: 현재 branch 가 base 와 동일 — Phase 0 의 작업 branch 분기가 누락됨" >&2
    exit 2
  fi

  # push 할 branch 이름 결정 (현재 branch 명 그대로 사용)
  PUSH_BRANCH="$CUR_BRANCH"

  # 충돌 검사 & suffix 자동 부여
  FINAL_BRANCH="$PUSH_BRANCH"
  if git ls-remote --heads "$REMOTE" "$FINAL_BRANCH" 2>/dev/null | grep -q .; then
    # 충돌 → suffix
    local_suffix=2
    while [ "$local_suffix" -le 5 ]; do
      CANDIDATE="${PUSH_BRANCH}-${local_suffix}"
      if ! git ls-remote --heads "$REMOTE" "$CANDIDATE" 2>/dev/null | grep -q .; then
        FINAL_BRANCH="$CANDIDATE"
        break
      fi
      local_suffix=$(( local_suffix + 1 ))
    done
    if [ "$FINAL_BRANCH" = "$PUSH_BRANCH" ]; then
      echo "finish-plan-dev: branch 이름 충돌 — suffix -2 ~ -5 모두 사용 중 ($PUSH_BRANCH)" >&2
      exit 2
    fi
    # branch rename (현재 branch → FINAL_BRANCH)
    if [ "$DRY_RUN" = "0" ]; then
      git branch -m "$PUSH_BRANCH" "$FINAL_BRANCH" 2>/dev/null || true
    fi
  fi

  if [ "$DRY_RUN" = "1" ]; then
    echo "${GIT_PUSH_CMD} -u $REMOTE $FINAL_BRANCH"
    exit 0
  fi

  # push 실행
  if ${GIT_PUSH_CMD} -u "$REMOTE" "$FINAL_BRANCH"; then
    clear_marker
    echo "pushed: $FINAL_BRANCH → $REMOTE (base=develop)"
  else
    echo "finish-plan-dev: push 실패 — '${GIT_PUSH_CMD} -u $REMOTE $FINAL_BRANCH'" >&2
    echo "finish-plan-dev: 재시도: ${GIT_PUSH_CMD} -u $REMOTE $FINAL_BRANCH" >&2
    exit 2
  fi

else
  # ── Main-only case ────────────────────────────────────────────────

  # 현재 branch 가 main/master 여야 함
  case "$CUR_BRANCH" in
    main|master) ;;
    *)
      echo "finish-plan-dev: main-only case 에서 현재 branch 가 main/master 가 아님: $CUR_BRANCH" >&2
      exit 2 ;;
  esac

  if [ "$DRY_RUN" = "1" ]; then
    echo "${GIT_PUSH_CMD} $REMOTE $CUR_BRANCH"
    exit 0
  fi

  if ${GIT_PUSH_CMD} "$REMOTE" "$CUR_BRANCH"; then
    clear_marker
    echo "pushed: $CUR_BRANCH → $REMOTE (no develop)"
  else
    echo "finish-plan-dev: push 실패 — '${GIT_PUSH_CMD} $REMOTE $CUR_BRANCH'" >&2
    echo "finish-plan-dev: 재시도: ${GIT_PUSH_CMD} $REMOTE $CUR_BRANCH" >&2
    exit 2
  fi
fi
