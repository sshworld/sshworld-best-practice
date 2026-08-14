#!/usr/bin/env bash
# cbp-marker-path.sh — done-marker 디렉토리 리졸버 (writer/reader 공용 단일 출처).
#
# 왜 있나: marker 를 쓰는 곳 1개(hooks/notify-slice-done.sh)와 읽는 곳 4개
# (scripts/cmux-pane.sh ×3, hooks/reap-on-stop.sh)가 각자 `git rev-parse
# --git-common-dir` 로 경로를 계산했다. 전부 git 전용이라 비-git 디렉토리에서는
# writer 가 조용히 아무것도 안 남기고, 그 결과 reap fast-path·reap-on-stop·
# (폴백인) wait-idle 이 **동시에** 무력화됐다. 한 곳만 고치면 writer 와 reader 가
# 갈라지므로 리졸버를 하나로 모은다.
#
# 우선순위:
#   1) CBP_MARKER_DIR      — 명시 override (테스트/특수 배치)
#   2) git-common-dir      — git 이면 worktree/일반 체크아웃 구분 없이 공용 디렉토리
#   3) $HOME/.cache/cbp/marker-<sanitized CMUX_WORKSPACE_ID>  — 비-git 폴백
#      (규칙은 hooks/enforce-cmux-dispatch.sh 의 skip-once 폴백과 동일 — 새 규칙 X)
#
# 사용:
#   source "$(dirname "$0")/cbp-marker-path.sh"; dir=$(cbp_marker_dir)
#   또는 직접 실행: cbp-marker-path.sh   → 경로 1줄 출력

cbp_marker_dir() {
  # 1) override
  if [ -n "${CBP_MARKER_DIR:-}" ]; then
    mkdir -p "$CBP_MARKER_DIR" 2>/dev/null || true
    printf '%s\n' "$CBP_MARKER_DIR"
    return 0
  fi

  # 2) git — 절대경로 우선, 실패 시 상대경로를 pwd 로 절대화
  local common=""
  common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || common=""
  if [ -z "$common" ]; then
    local rel
    rel=$(git rev-parse --git-common-dir 2>/dev/null) || rel=""
    if [ -n "$rel" ]; then
      common=$(cd "$rel" 2>/dev/null && pwd) || common=""
    fi
  fi
  if [ -n "$common" ] && [ -d "$common" ]; then
    printf '%s\n' "$common"
    return 0
  fi

  # 3) 비-git 폴백
  local ws="${CMUX_WORKSPACE_ID:-nows}"
  ws="${ws//[:\/]/_}"
  local dir="$HOME/.cache/cbp/marker-${ws}"
  mkdir -p "$dir" 2>/dev/null || true
  printf '%s\n' "$dir"
}

# marker 파일명 접미사 키. git 이면 branch, 아니면 surface ref 로 폴백한다.
# (비-git 에는 branch 가 없다 — 예전엔 여기서 조용히 포기했다.)
cbp_marker_key() {
  local key=""
  key=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || key=""
  if [ -z "$key" ] || [ "$key" = "HEAD" ]; then
    key="${CBP_SELF_PANE:-${CMUX_SURFACE_ID:-nokey}}"
  fi
  printf '%s\n' "${key//\//_}"
}

# 화면 해시 전 **변동 라인 마스킹**.
# Claude TUI 는 경과시간·비용·스피너를 매초 갱신하므로, 원본 sha 비교로는
# 자식이 이미 끝났어도 wait-idle 이 idle 에 영원히 도달하지 못한다(실측 timeout 540s).
# 과잉 마스킹은 본문 변화를 삼키므로 아래 3종만 다룬다.
# (cmux-pane.sh 가 source 해 쓴다 — 그쪽은 sourcing guard 가 없어 테스트가
#  함수를 못 꺼내므로, 검증 가능한 이 파일에 둔다.)
cbp_mask_volatile() {
  sed -E \
    -e 's/[0-9]+m[[:space:]]+[0-9]+s/<T>/g' \
    -e 's/[0-9]+(\.[0-9]+)?s/<T>/g' \
    -e 's/^[[:space:]]*[✻✢✽✶✳✺·⏺][[:space:]]*/<SPIN> /' \
    -e 's/💰.*/<COST>/'
}

# 직접 실행 시 경로 출력 (sourcing guard)
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  cbp_marker_dir
fi
