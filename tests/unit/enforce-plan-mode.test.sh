#!/usr/bin/env bash
# enforce-plan-mode.sh hook 단위 테스트.
# PreToolUse Write|Edit — plan-dev 마커 활성 + plan mode 미진입 시 Edit/Write 차단.
# "plan mode 거침" 판정 = marker 보다 newer 한 plan 파일이 PLANS_DIR 에 존재.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$REPO/hooks/enforce-plan-mode.sh"
PASS=0; FAIL=0; FAILED=()
run() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then echo "✔ $name"; PASS=$((PASS+1)); else echo "✘ $name"; FAIL=$((FAIL+1)); FAILED+=("$name"); fi; }

# hook 을 plain git repo (non-worktree) 에서 실행 — worktree 감지 skip 우회
_plain_repo_hook() {
  local tmpbase; tmpbase=$(mktemp -d)
  local repo="$tmpbase/repo"; mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" commit --allow-empty -q -m init 2>/dev/null
  local ec=0; ( cd "$repo" && "$@" ) || ec=$?
  rm -rf "$tmpbase"
  return $ec
}

# tmp 에 marker(start_ts 포함) + plans dir 구성. $2=plan_state(none|newer|older). echo "marker|plans".
# 판정은 marker 파일 mtime 이 아니라 start_ts JSON 필드 기준.
mk_env() {
  local tmp="$1" state="$2"
  local marker="$tmp/marker.json" plans="$tmp/plans"
  mkdir -p "$plans"
  local now; now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  case "$state" in
    none)  printf '{"start_ts":"%s"}' "$now" > "$marker" ;;
    older) echo '{}' > "$plans/p.md"; sleep 2; now=$(date -u +%Y-%m-%dT%H:%M:%SZ); printf '{"start_ts":"%s"}' "$now" > "$marker" ;;
    newer) printf '{"start_ts":"%s"}' "$now" > "$marker"; sleep 2; echo '{}' > "$plans/p.md" ;;
  esac
  echo "$marker|$plans"
}

t_no_marker_allows() {
  local tmp; tmp=$(mktemp -d)
  echo '{"tool_name":"Edit","permission_mode":"default"}' | \
    PLAN_MODE_SESSION_FILE="$tmp/nope.json" PLAN_MODE_PLANS_DIR="$tmp/plans" bash "$HOOK"
  local ec=$?; rm -rf "$tmp"; [ "$ec" = "0" ]
}

t_newer_plan_allows() {
  local tmp; tmp=$(mktemp -d); local e; e=$(mk_env "$tmp" newer)
  echo '{"tool_name":"Edit","permission_mode":"default"}' | \
    PLAN_MODE_SESSION_FILE="${e%|*}" PLAN_MODE_PLANS_DIR="${e#*|}" bash "$HOOK"
  local ec=$?; rm -rf "$tmp"; [ "$ec" = "0" ]
}

t_no_plan_blocks() {
  local tmp; tmp=$(mktemp -d); local e; e=$(mk_env "$tmp" none)
  local ec=0
  echo '{"tool_name":"Edit","permission_mode":"default"}' | \
    PLAN_MODE_SESSION_FILE="${e%|*}" PLAN_MODE_PLANS_DIR="${e#*|}" _plain_repo_hook bash "$HOOK" || ec=$?
  rm -rf "$tmp"; [ "$ec" = "2" ]
}

t_older_plan_blocks() {
  local tmp; tmp=$(mktemp -d); local e; e=$(mk_env "$tmp" older)
  local ec=0
  echo '{"tool_name":"Edit","permission_mode":"default"}' | \
    PLAN_MODE_SESSION_FILE="${e%|*}" PLAN_MODE_PLANS_DIR="${e#*|}" _plain_repo_hook bash "$HOOK" || ec=$?
  rm -rf "$tmp"; [ "$ec" = "2" ]
}

t_plan_mode_allows_even_no_plan() {
  local tmp; tmp=$(mktemp -d); local e; e=$(mk_env "$tmp" none)
  echo '{"tool_name":"Write","permission_mode":"plan"}' | \
    PLAN_MODE_SESSION_FILE="${e%|*}" PLAN_MODE_PLANS_DIR="${e#*|}" bash "$HOOK"
  local ec=$?; rm -rf "$tmp"; [ "$ec" = "0" ]
}

t_bypass_allows() {
  local tmp; tmp=$(mktemp -d); local e; e=$(mk_env "$tmp" none)
  echo '{"tool_name":"Edit","permission_mode":"bypassPermissions"}' | \
    PLAN_MODE_SESSION_FILE="${e%|*}" PLAN_MODE_PLANS_DIR="${e#*|}" bash "$HOOK"
  local ec=$?; rm -rf "$tmp"; [ "$ec" = "0" ]
}

t_skip_env_allows() {
  local tmp; tmp=$(mktemp -d); local e; e=$(mk_env "$tmp" none)
  echo '{"tool_name":"Edit","permission_mode":"default"}' | \
    SKIP_PLAN_MODE_ENFORCE=1 PLAN_MODE_SESSION_FILE="${e%|*}" PLAN_MODE_PLANS_DIR="${e#*|}" bash "$HOOK"
  local ec=$?; rm -rf "$tmp"; [ "$ec" = "0" ]
}

t_disable_env_allows() {
  local tmp; tmp=$(mktemp -d); local e; e=$(mk_env "$tmp" none)
  echo '{"tool_name":"Edit","permission_mode":"default"}' | \
    DISABLE_PLAN_MODE_ENFORCE_HOOK=1 PLAN_MODE_SESSION_FILE="${e%|*}" PLAN_MODE_PLANS_DIR="${e#*|}" bash "$HOOK"
  local ec=$?; rm -rf "$tmp"; [ "$ec" = "0" ]
}

t_non_write_allows() {
  local tmp; tmp=$(mktemp -d); local e; e=$(mk_env "$tmp" none)
  echo '{"tool_name":"Bash","permission_mode":"default"}' | \
    PLAN_MODE_SESSION_FILE="${e%|*}" PLAN_MODE_PLANS_DIR="${e#*|}" bash "$HOOK"
  local ec=$?; rm -rf "$tmp"; [ "$ec" = "0" ]
}

# start_ts 가 now-25h (24h 초과) → stale 판정 → allow(0), plan 파일 없어도.
t_stale_24h_allows() {
  local tmp; tmp=$(mktemp -d)
  local marker="$tmp/marker.json" plans="$tmp/plans"
  mkdir -p "$plans"
  local old_ts; old_ts=$(python3 -c "from datetime import datetime,timezone,timedelta; print((datetime.now(timezone.utc)-timedelta(hours=25)).strftime('%Y-%m-%dT%H:%M:%SZ'))")
  printf '{"start_ts":"%s"}' "$old_ts" > "$marker"
  local ec=0
  echo '{"tool_name":"Edit","permission_mode":"default"}' | \
    PLAN_MODE_SESSION_FILE="$marker" PLAN_MODE_PLANS_DIR="$plans" _plain_repo_hook bash "$HOOK" || ec=$?
  rm -rf "$tmp"; [ "$ec" = "0" ]
}

# tool_input.file_path 가 CLAUDE_PROJECT_DIR 밖 → allow(0) (plan 없어도, marker 활성이어도)
t_outside_project_file_path_allows() {
  local tmp; tmp=$(mktemp -d)
  local repo="$tmp/repo"; mkdir -p "$repo"
  git -C "$repo" init -q; git -C "$repo" commit --allow-empty -q -m init 2>/dev/null
  local e; e=$(mk_env "$tmp" none)
  local outside="$tmp/outside/scratch.md"; mkdir -p "$(dirname "$outside")"; touch "$outside"
  local ec=0
  printf '{"tool_name":"Edit","permission_mode":"default","tool_input":{"file_path":"%s"}}' "$outside" | \
    CLAUDE_PROJECT_DIR="$repo" PLAN_MODE_SESSION_FILE="${e%|*}" PLAN_MODE_PLANS_DIR="${e#*|}" \
    sh -c "cd '$repo' && bash '$HOOK'" || ec=$?
  rm -rf "$tmp"; [ "$ec" = "0" ]
}

# skip-once marker-file: repo 의 git-common-dir 에 cbp-skip-once-plan-mode 존재 → 1회 소비+allow, 2번째는 다시 차단
t_skip_once_consumed_once() {
  local tmp; tmp=$(mktemp -d)
  local repo="$tmp/repo"; mkdir -p "$repo"
  git -C "$repo" init -q; git -C "$repo" commit --allow-empty -q -m init 2>/dev/null
  local e; e=$(mk_env "$tmp" none)
  touch "$repo/.git/cbp-skip-once-plan-mode"
  local ec1=0 ec2=0
  echo '{"tool_name":"Edit","permission_mode":"default"}' | \
    PLAN_MODE_SESSION_FILE="${e%|*}" PLAN_MODE_PLANS_DIR="${e#*|}" sh -c "cd '$repo' && bash '$HOOK'" || ec1=$?
  echo '{"tool_name":"Edit","permission_mode":"default"}' | \
    PLAN_MODE_SESSION_FILE="${e%|*}" PLAN_MODE_PLANS_DIR="${e#*|}" sh -c "cd '$repo' && bash '$HOOK'" || ec2=$?
  rm -rf "$tmp"
  [ "$ec1" = "0" ] && [ "$ec2" = "2" ]
}

# 차단 안내문에 git-common-dir 기반 escape 안내 포함 (literal .git/ 하드코딩 금지)
t_block_message_uses_git_common_dir() {
  local tmp; tmp=$(mktemp -d); local e; e=$(mk_env "$tmp" none)
  local stderr_out
  stderr_out=$(echo '{"tool_name":"Edit","permission_mode":"default"}' | \
    PLAN_MODE_SESSION_FILE="${e%|*}" PLAN_MODE_PLANS_DIR="${e#*|}" _plain_repo_hook bash "$HOOK" 2>&1 >/dev/null)
  rm -rf "$tmp"
  printf '%s' "$stderr_out" | grep -qF "git rev-parse --git-common-dir"
}

run "마커 없음 → allow(0)"                          t_no_marker_allows
run "newer plan 존재 → allow(0)"                    t_newer_plan_allows
run "plan 없음 → block(2)"                          t_no_plan_blocks
run "older plan(marker 가 newer) → block(2)"        t_older_plan_blocks
run "permission_mode=plan → allow(0) (plan 없어도)" t_plan_mode_allows_even_no_plan
run "bypassPermissions → allow(0)"                  t_bypass_allows
run "SKIP_PLAN_MODE_ENFORCE=1 → allow(0)"            t_skip_env_allows
run "DISABLE_PLAN_MODE_ENFORCE_HOOK=1 → allow(0)"    t_disable_env_allows
run "비 Write|Edit(Bash) → allow(0)"                t_non_write_allows
run "stale 24h(start_ts now-25h) → allow(0)"        t_stale_24h_allows
run "file_path 프로젝트 밖 → allow(0)"              t_outside_project_file_path_allows
run "skip-once 파일 1회 소비 (2번째는 block)"       t_skip_once_consumed_once
run "차단 안내문에 git-common-dir 사용"             t_block_message_uses_git_common_dir

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && echo "✅ all pass" || { echo "❌ FAILED: ${FAILED[*]}"; exit 1; }
