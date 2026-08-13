#!/usr/bin/env bash
# finish-plan-dev.sh — plan-dev 종료 시 develop/main 분기 push 자동화.
#
# 사용:
#   finish-plan-dev.sh [--dry-run] [--remote=<name>]
#
# 환경변수:
#   SKIP_PLAN_DEV_FINISH=1           → exit 0 + stdout "skipped (SKIP)"
#   DISABLE_PLAN_DEV_FINISH=1        → exit 0 + stdout "disabled"
#   GIT_PUSH_CMD                     → 디폴트 "git push" (테스트에서 실패 명령 주입 시 사용)
#   PLAN_DEV_SESSION_BIN             → 디폴트 "<repo>/scripts/plan-dev-session.sh"
#                                      없으면 marker 파일 직접 파싱 폴백.
#   SKIP_CMUX_REAP=1                 → push 후 reap-orphans backstop 1회 skip
#   SKIP_PLAN_DEV_CMUX_CLEANUP=1     → push 후 cmux 자식 surface cleanup 1회 skip
#   DESIGN_DOC=none                  → 설계 문서 없는 기계적 변경 선언 (latch 없을 때 게이트 통과)
#   SKIP_DESIGN_DOC=1                → 설계 문서 실측 게이트 1회 우회
#   DISABLE_DESIGN_DOC_GATE=1        → 설계 문서 실측 게이트 영구 비활성화

set -uo pipefail

# ── 상수 / 기본값 ──────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GIT_PUSH_CMD="${GIT_PUSH_CMD:-git push}"
PLAN_DEV_SESSION_BIN="${PLAN_DEV_SESSION_BIN:-$SCRIPT_DIR/plan-dev-session.sh}"
CMUX_PANE_BIN="${CMUX_PANE_BIN:-$SCRIPT_DIR/cmux-pane.sh}"

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
  DESIGN_DOC=none            설계 문서 없는 기계적 변경 선언 (latch 없을 때 게이트 통과)
  SKIP_DESIGN_DOC=1          설계 문서 실측 게이트 1회 우회
  DISABLE_DESIGN_DOC_GATE=1  설계 문서 실측 게이트 영구 비활성화
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
MARKER_ADVISED="${COMMON_DIR}/plan-dev-commit-advised"

if [ ! -f "$MARKER" ]; then
  if [ "${FINISH_AUTO_PUSH_WITHOUT_MARKER:-0}" = "1" ]; then
    _cur_branch=$(git symbolic-ref --short HEAD 2>/dev/null || true)
    if [ -n "$_cur_branch" ]; then
      echo "no marker — FINISH_AUTO_PUSH_WITHOUT_MARKER=1 → push $_cur_branch to origin"
      ${GIT_PUSH_CMD:-git push} -u origin "$_cur_branch"
      exit $?
    fi
  fi
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

# ── clear marker 헬퍼 ─────────────────────────────────────────────

clear_marker() {
  rm -f "$MARKER"
  rm -f "$MARKER_ADVISED"
}

# ── 현재 HEAD branch 확인 ──────────────────────────────────────────

CUR_BRANCH="$(git symbolic-ref --short HEAD 2>/dev/null)" || {
  echo "finish-plan-dev: detached HEAD — push 불가" >&2
  exit 2
}

# ── Range 검증 ─────────────────────────────────────────────────────

REV_LIST_ERR=""
if ! NEW_COMMITS="$(git rev-list --count "${START_REF}..HEAD" 2>&1)"; then
  REV_LIST_ERR="$NEW_COMMITS"
  echo "finish-plan-dev: start_ref 무효 (rebase/GC?) — '${START_REF}' 를 rev-list 로 해석 불가." >&2
  echo "  git error: ${REV_LIST_ERR}" >&2
  echo "  복구: plan-dev-session.sh start 를 재실행해 marker 를 갱신하거나," >&2
  echo "        marker 의 start_ref 를 유효한 SHA 로 직접 수정할 것." >&2
  exit 2
fi

if [ "$NEW_COMMITS" = "0" ]; then
  echo "no new commits since marker — skip"
  clear_marker
  exit 0
fi

# ── 설계 문서 실측 게이트 ──────────────────────────────────────────
#
# 설계 문서(docs/design/<slug>.md) 의 '## 6. 결과' 실측 칸이 채워졌는지 검사.
# commit 시점 hook 이 아니라 여기인 이유: 설계 문서는 기능당 1개 = 세션당 1개라
# 커밋 granularity 와 안 맞고(커밋마다 env prefix = 마찰), 실측값은 작업이 끝난
# 이 시점에만 존재한다.
#
# 차단만 하지 않고 선택지를 준다 — enforce-doc-sync.sh 의 DOC_IMPACT 와 같은
# "판단 강제" 패턴. 일률 차단은 본 repo 원칙 위반.
#
# design_doc 는 query 분기와 무관하게 항상 marker 직독 (PLAN_DEV_SESSION_BIN
# 부재 폴백 경로에서도 게이트가 동작해야 함).

DESIGN_DOC_PATH=$(json_get "$MARKER" "design_doc") || DESIGN_DOC_PATH=""

# 실측 칸 판정 → stdout: OK | PLACEHOLDER | MISSING
#
# 표 형식과 리스트 형식을 따로 다룬다:
#   표   `| 항목 | 목표 | 실측 |` — '실측' 은 컬럼 라벨일 뿐 값이 아니다.
#        컬럼 인덱스를 구해 이후 데이터 행의 같은 컬럼을 본다. 하나라도
#        채워져 있으면 OK (헤더만 있고 데이터 행이 없으면 PLACEHOLDER).
#   리스트 `- 실측: <값>` — '실측' 뒤 텍스트가 곧 값.
design_measure_verdict() {
  awk '
    # 실측 칸의 값이 "실제로 기입된 값" 인지 판정.
    # 반환: 1 = 기입됨(통과) / 0 = 미기입(차단)
    function is_measured(v) {
      # 측정 불가를 명시적으로 자백한 경우는 다른 규칙보다 먼저 통과시킨다 —
      # 감추지 않고 적는 것이 이 칸의 목적이므로 유효한 값이다.
      if (v ~ /미검증/) return 1
      if (v == "") return 0
      # 괄호로 감싼 전체는 자리표시자: "(S4 에서 채움)" "(측정 예정)"
      if (v ~ /^\(.*\)$/) return 0
      u = toupper(v)
      if (u == "TODO" || u == "TBD" || u == "N/A" || u == "NA" || u == "-") return 0
      # 정확 일치만 — 부분 일치로 하면 "회귀 테스트 채움 완료" 같은 정당한
      # 문장까지 자리표시자로 오판한다. 괄호 규칙이 감싼 형태를 이미 잡는다.
      if (v == "—" || v == "미정" || v == "채움" || v == "미측정") return 0
      return 1
    }

    /^##[[:space:]]*6\./          { insec=1; next }
    insec && /^##[[:space:]]/     { insec=0 }
    insec                         { lines[++n]=$0 }

    END {
      verdict="MISSING"
      for (i=1; i<=n; i++) {
        L=lines[i]
        if (L !~ /실측/) continue

        if (L ~ /^[[:space:]]*\|/) {
          # 표 형식 — 실측 컬럼 인덱스 확보
          col=0; m=split(L, a, "|")
          for (j=1; j<=m; j++) {
            gsub(/^[ \t]+|[ \t]+$/, "", a[j])
            if (a[j] == "실측") col=j
          }
          if (col == 0) continue
          verdict="PLACEHOLDER"
          for (k=i+1; k<=n; k++) {
            R=lines[k]
            if (R !~ /^[[:space:]]*\|/) continue
            if (R ~ /^[[:space:]]*\|[-: |]+\|[[:space:]]*$/) continue   # 구분행
            m2=split(R, b, "|")
            if (col > m2) continue
            v=b[col]; gsub(/^[ \t]+|[ \t]+$/, "", v)
            if (is_measured(v)) verdict="OK"
          }
        } else {
          # 리스트 형식
          v=L
          sub(/^.*실측[[:space:]]*[:：]?[[:space:]]*/, "", v)
          gsub(/^[ \t]+|[ \t]+$/, "", v)
          verdict = is_measured(v) ? "OK" : "PLACEHOLDER"
        }
      }
      print verdict
    }
  ' "$1"
}

if [ "${DISABLE_DESIGN_DOC_GATE:-0}" != "1" ] && [ "${SKIP_DESIGN_DOC:-0}" != "1" ]; then
  if [ -n "$DESIGN_DOC_PATH" ]; then
    if [ ! -f "$DESIGN_DOC_PATH" ]; then
      cat >&2 <<MSG
⛔ latch 된 설계 문서를 찾을 수 없음 — push 차단됨.

latch 경로: ${DESIGN_DOC_PATH}

다음 중 하나로 재시도:
  • 경로가 바뀌었으면: plan-dev-session.sh set-design <새 절대경로> 후 재실행
  • 설계 문서가 필요 없어졌으면: DESIGN_DOC=none <명령>

1회 우회: SKIP_DESIGN_DOC=1 / 영구 off: DISABLE_DESIGN_DOC_GATE=1
MSG
      exit 2
    fi

    DESIGN_VERDICT="$(design_measure_verdict "$DESIGN_DOC_PATH")"
    if [ "$DESIGN_VERDICT" != "OK" ]; then
      cat >&2 <<MSG
⛔ 설계 문서 실측 미기입 — push 차단됨.

설계 문서: ${DESIGN_DOC_PATH}
판정: ${DESIGN_VERDICT}

다음 중 하나로 재시도:
  • 실측값을 채웠으면: ${DESIGN_DOC_PATH} 의 '## 6. 결과' 실측 칸 갱신 후 재실행
  • 측정이 불가하면:   실측 칸에 '미검증 — 재발 감시 중' 명시 후 재실행
  • 이번 세션이 기계적 변경이면: DESIGN_DOC=none <명령>

1회 우회: SKIP_DESIGN_DOC=1 / 영구 off: DISABLE_DESIGN_DOC_GATE=1
MSG
      exit 2
    fi
    echo "design-doc gate: 실측 확인 — ${DESIGN_DOC_PATH}"
  else
    if [ "${DESIGN_DOC:-}" = "none" ]; then
      echo "design-doc gate: DESIGN_DOC=none — 설계 문서 없는 기계적 변경으로 선언됨"
    else
      cat >&2 <<'MSG'
⛔ 설계 문서 판단 필요 — push 차단됨.

이 세션에 latch 된 설계 문서가 없다. 다음 중 하나로 재시도:

  • 설계 문서를 만들었으면 (조건부 블록 중 하나라도 필요한 작업):
        plan-dev-session.sh set-design <설계 문서 절대경로>
    후 재실행. 실측 칸까지 채워야 통과한다.

  • 기계적 변경이면 (원인 자명 + 구조 불변 + 대안 없음 + 잴 것 없음
    = rename·문서 이동·설정값·버전 bump):
        DESIGN_DOC=none <명령>

1회 우회: SKIP_DESIGN_DOC=1 / 영구 off: DISABLE_DESIGN_DOC_GATE=1
MSG
      exit 2
    fi
  fi
fi

# ── commit-advisor gate ────────────────────────────────────────────
# push 직전에 commit-advisor(Phase 4) 가 실행됐는지 marker 로 검사.
# 우회: SKIP_COMMIT_ADVISOR_GATE=1 (1회) / DISABLE_COMMIT_ADVISOR_GATE=1 (영구)

if [ "${DISABLE_COMMIT_ADVISOR_GATE:-0}" != "1" ] && [ "${SKIP_COMMIT_ADVISOR_GATE:-0}" != "1" ]; then
  if [ ! -f "$MARKER_ADVISED" ]; then
    echo "⛔ commit-advisor (Phase 4) 미실행 — push 차단." >&2
    echo "   commit-advisor 에이전트를 먼저 호출해 커밋 메시지/브랜치명을 정리하라." >&2
    echo "   우회: SKIP_COMMIT_ADVISOR_GATE=1 (1회) / DISABLE_COMMIT_ADVISOR_GATE=1 (영구)" >&2
    exit 2
  fi
fi

# ── cmux cleanup 헬퍼 (S3) ────────────────────────────────────────
do_cmux_cleanup() {
  # backstop: stale done-marker 파일 정리 (S1 reap fast-path 의 rm 누락/실패 대비, best-effort)
  rm -f "${COMMON_DIR}"/cbp-slice-done-* 2>/dev/null || true

  if [ "${SKIP_PLAN_DEV_CMUX_CLEANUP:-0}" = "1" ]; then
    echo "cmux cleanup skipped (SKIP_PLAN_DEV_CMUX_CLEANUP=1)" >&2
    return 0
  fi
  if [ "${DISABLE_PLAN_DEV_CMUX_CLEANUP:-0}" = "1" ]; then
    echo "cmux cleanup disabled (DISABLE_PLAN_DEV_CMUX_CLEANUP=1)" >&2
    return 0
  fi
  if [ -z "${CMUX_WORKSPACE_ID:-}" ]; then
    return 0  # cmux 환경 아님
  fi
  if [ ! -x "$CMUX_PANE_BIN" ]; then
    echo "cmux-pane.sh 부재 — cleanup skip" >&2
    return 0
  fi
  echo "finish-plan-dev: cmux 자식 surface cleanup 실행" >&2
  "$CMUX_PANE_BIN" cleanup 2>&1 | sed 's/^/  /' >&2 || true

  # reap-orphans backstop: cleanup 후에도 잔존하는 dead surface 회수 (best-effort).
  # SKIP_CMUX_REAP=1 로 우회 가능.
  if [ "${SKIP_CMUX_REAP:-0}" != "1" ]; then
    "$CMUX_PANE_BIN" reap-orphans >/dev/null 2>&1 || true
  fi
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

  # 충돌 검사 & suffix 자동 부여 (remote 존재 + 로컬 브랜치 존재 모두 검사)
  FINAL_BRANCH="$PUSH_BRANCH"
  if git ls-remote --heads "$REMOTE" "$FINAL_BRANCH" 2>/dev/null | grep -q .; then
    # 충돌 → suffix. 후보는 remote 뿐 아니라 로컬 브랜치 선점도 피해야 stale 로컬을
    # rename 대상으로 잘못 골라 그 내용을 push 하는 사고를 막는다.
    local_suffix=2
    while [ "$local_suffix" -le 5 ]; do
      CANDIDATE="${PUSH_BRANCH}-${local_suffix}"
      if ! git ls-remote --heads "$REMOTE" "$CANDIDATE" 2>/dev/null | grep -q . \
        && ! git show-ref --verify --quiet "refs/heads/$CANDIDATE"; then
        FINAL_BRANCH="$CANDIDATE"
        break
      fi
      local_suffix=$(( local_suffix + 1 ))
    done
    if [ "$FINAL_BRANCH" = "$PUSH_BRANCH" ]; then
      echo "finish-plan-dev: branch 이름 충돌 — suffix -2 ~ -5 모두 사용 중 (remote 또는 로컬 선점, $PUSH_BRANCH)" >&2
      exit 2
    fi
    # branch rename (현재 branch → FINAL_BRANCH). 실패 시 stale 브랜치 push 방지 위해 exit 2.
    if [ "$DRY_RUN" = "0" ]; then
      if ! git branch -m "$PUSH_BRANCH" "$FINAL_BRANCH" 2>&1; then
        echo "finish-plan-dev: branch rename 실패 ('$PUSH_BRANCH' → '$FINAL_BRANCH') — push 중단 (stale 브랜치 push 방지)" >&2
        exit 2
      fi
      CUR_BRANCH="$FINAL_BRANCH"
    fi
  fi

  if [ "$DRY_RUN" = "1" ]; then
    echo "${GIT_PUSH_CMD} -u $REMOTE $FINAL_BRANCH"
    exit 0
  fi

  # push 실행
  if ${GIT_PUSH_CMD} -u "$REMOTE" "$FINAL_BRANCH"; then
    do_cmux_cleanup
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
    do_cmux_cleanup
    clear_marker
    echo "pushed: $CUR_BRANCH → $REMOTE (no develop)"
  else
    echo "finish-plan-dev: push 실패 — '${GIT_PUSH_CMD} $REMOTE $CUR_BRANCH'" >&2
    echo "finish-plan-dev: 재시도: ${GIT_PUSH_CMD} $REMOTE $CUR_BRANCH" >&2
    exit 2
  fi
fi
