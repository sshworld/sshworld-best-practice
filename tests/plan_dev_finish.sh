#!/usr/bin/env bash
# Slice 2b — finish-plan-dev.sh 통합 테스트.
# bare repo + file:// remote 로 실제 git push 검증.

set -uo pipefail

# 설계 문서 실측 게이트(finish-plan-dev.sh)는 이 스위트의 관심사가 아니다 —
# push/branch 분기만 검증한다. 게이트 전용 스위트: tests/plan_dev_design_latch.sh
export DISABLE_DESIGN_DOC_GATE=1

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FINISH="$REPO/scripts/finish-plan-dev.sh"

step() { echo ""; echo "[$1] $2"; }
fail() { echo "FAIL: $1" >&2; exit 1; }

[ -x "$FINISH" ] || fail "finish-plan-dev.sh not executable: $FINISH"

# ── 공통 헬퍼 ─────────────────────────────────────────────────────

# git init with main as default branch (supports both old and new git)
git_init_main() {
  local dir="$1"
  git -c init.defaultBranch=main init "$dir" -q 2>/dev/null \
    || git init "$dir" -q
  # Ensure we are on main
  if [ "$(git -C "$dir" symbolic-ref --short HEAD 2>/dev/null)" != "main" ]; then
    git -C "$dir" checkout -b main -q 2>/dev/null || true
  fi
}

setup_repo() {
  local bare src
  bare=$(mktemp -d)
  src=$(mktemp -d)

  git init --bare "$bare" -q
  git_init_main "$src"
  git -C "$src" config user.email "t@e.local"
  git -C "$src" config user.name "tester"
  git -C "$src" remote add origin "file://$bare"

  # 초기 commit on main
  echo "init" > "$src/README"
  git -C "$src" add README
  git -C "$src" -c commit.gpgsign=false commit -m "init" -q
  git -C "$src" push origin main -q 2>/dev/null

  echo "$src $bare"
}

add_develop_to_origin() {
  local src="$1"
  # origin 에 develop branch 추가 (main 과 동일 ref)
  git -C "$src" push origin "main:develop" -q 2>/dev/null
  git -C "$src" fetch origin -q 2>/dev/null
}

# marker 절대 경로 반환 (git-common-dir 가 상대경로일 수 있으므로 $SRC 기준 보정)
marker_abs_path() {
  local src="$1"
  local common_dir
  common_dir=$(git -C "$src" rev-parse --git-common-dir)
  # common_dir 가 절대경로면 그대로, 상대경로면 $src 기준으로
  case "$common_dir" in
    /*) echo "$common_dir/plan-dev-session.json" ;;
    *)  echo "$src/$common_dir/plan-dev-session.json" ;;
  esac
}

# marker JSON 작성 (python3 사용)
write_marker() {
  local marker_path="$1"
  local start_ref="$2"
  local base_branch="$3"
  local work_branch="$4"
  local auto_branch="$5"
  local auto_val
  [ "$auto_branch" = "true" ] && auto_val="True" || auto_val="False"

  python3 - "$marker_path" "$start_ref" "$base_branch" "$work_branch" "$auto_val" <<'PYEOF'
import json, sys
from datetime import datetime, timezone, timedelta
mp, start_ref, base_branch, work_branch, auto_val = sys.argv[1:]
d = {
    'start_ref':   start_ref,
    'base_branch': base_branch,
    'work_branch': work_branch,
    'start_ts':    (datetime.now(timezone.utc) - timedelta(hours=1)).strftime('%Y-%m-%dT%H:%M:%SZ'),
    'start_pid':   99999,
    'auto_branch': auto_val == 'True',
}
with open(mp, 'w') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
PYEOF
  # commit-advisor gate 통과를 위해 commit-advised marker도 touch
  local repo_dir
  repo_dir="$(dirname "$marker_path")"
  touch "${repo_dir}/plan-dev-commit-advised"
}

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" != "$actual" ]; then
    fail "$label: expected='$expected' actual='$actual'"
  fi
}

# ── Case A: develop 있음, work branch 위에서 push 성공 ────────────
step A "develop 있음 — work branch push 성공"
{
  read -r SRC BARE <<< "$(setup_repo)"
  add_develop_to_origin "$SRC"

  # feat/test-flow 로 전환 + 2 commits
  git -C "$SRC" switch -c feat/test-flow -q
  echo "c1" >> "$SRC/README"; git -C "$SRC" add README
  git -C "$SRC" -c commit.gpgsign=false commit -m "c1" -q
  echo "c2" >> "$SRC/README"; git -C "$SRC" add README
  git -C "$SRC" -c commit.gpgsign=false commit -m "c2" -q

  # marker 작성
  MARKER="$(marker_abs_path "$SRC")"
  OLD_REF=$(git -C "$SRC" rev-parse origin/main)
  write_marker "$MARKER" "$OLD_REF" "develop" "feat/test-flow" "false"

  OUT=$(cd "$SRC" && PLAN_DEV_SESSION_BIN=/bin/false "$FINISH" 2>/dev/null)
  RC=$?
  assert_eq "exit code" "0" "$RC"
  echo "$OUT" | grep -q "pushed" || fail "Case A: stdout should contain 'pushed', got: $OUT"

  # BARE に feat/test-flow が届いているか
  BARE_REF=$(git -C "$BARE" rev-parse refs/heads/feat/test-flow 2>/dev/null) \
    || fail "Case A: feat/test-flow not in bare repo"
  SRC_HEAD=$(git -C "$SRC" rev-parse HEAD)
  assert_eq "bare ref == src HEAD" "$SRC_HEAD" "$BARE_REF"

  # marker 삭제됐는지
  [ ! -f "$MARKER" ] || fail "Case A: marker should be cleared after success"

  rm -rf "$SRC" "$BARE"
  echo "  Case A OK"
}

# ── Case B: main only, main 위에서 push 성공 ─────────────────────
step B "main only — main push 성공"
{
  read -r SRC BARE <<< "$(setup_repo)"
  # develop 없음

  # main に 2 commits (fetch 해서 origin/main 최신화)
  git -C "$SRC" fetch origin -q 2>/dev/null
  OLD_REF=$(git -C "$SRC" rev-parse origin/main)
  echo "d1" >> "$SRC/README"; git -C "$SRC" add README
  git -C "$SRC" -c commit.gpgsign=false commit -m "d1" -q
  echo "d2" >> "$SRC/README"; git -C "$SRC" add README
  git -C "$SRC" -c commit.gpgsign=false commit -m "d2" -q

  MARKER="$(marker_abs_path "$SRC")"
  write_marker "$MARKER" "$OLD_REF" "main" "main" "false"

  OUT=$(cd "$SRC" && PLAN_DEV_SESSION_BIN=/bin/false "$FINISH" 2>/dev/null)
  RC=$?
  assert_eq "exit code" "0" "$RC"
  echo "$OUT" | grep -q "pushed" || fail "Case B: stdout should contain 'pushed', got: $OUT"

  # BARE main が更新されているか
  BARE_REF=$(git -C "$BARE" rev-parse refs/heads/main 2>/dev/null) \
    || fail "Case B: main not in bare repo"
  SRC_HEAD=$(git -C "$SRC" rev-parse HEAD)
  assert_eq "bare main == src HEAD" "$SRC_HEAD" "$BARE_REF"

  [ ! -f "$MARKER" ] || fail "Case B: marker should be cleared"

  rm -rf "$SRC" "$BARE"
  echo "  Case B OK"
}

# ── Case C: marker 없음 ───────────────────────────────────────────
step C "marker 없음 → exit 0 + no marker 메시지"
{
  read -r SRC BARE <<< "$(setup_repo)"

  OUT=$(cd "$SRC" && PLAN_DEV_SESSION_BIN=/bin/false "$FINISH" 2>/dev/null)
  RC=$?
  assert_eq "exit code" "0" "$RC"
  echo "$OUT" | grep -qi "no marker" \
    || fail "Case C: expected 'no marker' in stdout, got: $OUT"

  rm -rf "$SRC" "$BARE"
  echo "  Case C OK"
}

# ── Case D: develop 있음, 현재 branch == base → exit 2 ───────────
step D "develop 있음, 현재 branch == base → exit 2"
{
  read -r SRC BARE <<< "$(setup_repo)"
  add_develop_to_origin "$SRC"

  # SRC 에서 develop 체크아웃 + commit
  git -C "$SRC" switch -c develop -q --track origin/develop 2>/dev/null \
    || git -C "$SRC" switch develop -q 2>/dev/null
  OLD_REF=$(git -C "$SRC" rev-parse origin/develop)
  echo "on-develop" >> "$SRC/README"; git -C "$SRC" add README
  git -C "$SRC" -c commit.gpgsign=false commit -m "on-develop" -q

  MARKER="$(marker_abs_path "$SRC")"
  write_marker "$MARKER" "$OLD_REF" "develop" "develop" "false"

  set +e
  ERR=$(cd "$SRC" && PLAN_DEV_SESSION_BIN=/bin/false "$FINISH" 2>&1 >/dev/null)
  RC=$?
  set -e
  assert_eq "exit code" "2" "$RC"
  echo "$ERR" | grep -qi "base" \
    || fail "Case D: expected 'base' in stderr, got: $ERR"

  rm -rf "$SRC" "$BARE"
  echo "  Case D OK"
}

# ── Case E: branch 이름 충돌 → suffix -2 ─────────────────────────
step E "branch 충돌 → suffix -2"
{
  read -r SRC BARE <<< "$(setup_repo)"
  add_develop_to_origin "$SRC"

  # feat/x を origin に先に push
  git -C "$SRC" switch -c feat/x -q
  echo "x1" >> "$SRC/README"; git -C "$SRC" add README
  git -C "$SRC" -c commit.gpgsign=false commit -m "x1" -q
  git -C "$SRC" push origin feat/x -q 2>/dev/null

  # main に戻って新しい commit + 同じ feat/x という名前のbranch
  git -C "$SRC" switch main -q
  echo "y1" >> "$SRC/README"; git -C "$SRC" add README
  git -C "$SRC" -c commit.gpgsign=false commit -m "y1" -q
  git -C "$SRC" switch -c feat/x -q 2>/dev/null \
    || git -C "$SRC" branch -D feat/x 2>/dev/null && git -C "$SRC" switch -c feat/x -q

  MARKER="$(marker_abs_path "$SRC")"
  OLD_REF=$(git -C "$SRC" rev-parse origin/main)
  write_marker "$MARKER" "$OLD_REF" "develop" "feat/x" "true"

  OUT=$(cd "$SRC" && PLAN_DEV_SESSION_BIN=/bin/false "$FINISH" 2>/dev/null)
  RC=$?
  assert_eq "exit code" "0" "$RC"

  # feat/x-2 が bare に push されているか
  git -C "$BARE" rev-parse refs/heads/feat/x-2 >/dev/null 2>&1 \
    || fail "Case E: feat/x-2 not found in bare repo. stdout: $OUT"

  [ ! -f "$MARKER" ] || fail "Case E: marker should be cleared"

  rm -rf "$SRC" "$BARE"
  echo "  Case E OK"
}

# ── Case F: SKIP env ──────────────────────────────────────────────
step F "SKIP_PLAN_DEV_FINISH=1 → exit 0 + skipped"
{
  read -r SRC BARE <<< "$(setup_repo)"

  OUT=$(cd "$SRC" && SKIP_PLAN_DEV_FINISH=1 "$FINISH" 2>/dev/null)
  RC=$?
  assert_eq "exit code" "0" "$RC"
  echo "$OUT" | grep -qi "skip" \
    || fail "Case F: expected 'skip' in stdout, got: $OUT"

  rm -rf "$SRC" "$BARE"
  echo "  Case F OK"
}

# ── Case G: push 실패 → exit 2 + marker 보존 ─────────────────────
step G "push 실패 → exit 2 + marker 보존"
{
  read -r SRC BARE <<< "$(setup_repo)"
  add_develop_to_origin "$SRC"

  git -C "$SRC" switch -c feat/fail -q
  echo "fail1" >> "$SRC/README"; git -C "$SRC" add README
  git -C "$SRC" -c commit.gpgsign=false commit -m "fail1" -q

  MARKER="$(marker_abs_path "$SRC")"
  OLD_REF=$(git -C "$SRC" rev-parse origin/main)
  write_marker "$MARKER" "$OLD_REF" "develop" "feat/fail" "false"

  set +e
  ERR=$(cd "$SRC" && GIT_PUSH_CMD="false" PLAN_DEV_SESSION_BIN=/bin/false "$FINISH" 2>&1 >/dev/null)
  RC=$?
  set -e
  assert_eq "exit code" "2" "$RC"

  # marker 보존
  [ -f "$MARKER" ] || fail "Case G: marker should be preserved on push failure"
  echo "$ERR" | grep -qiE "push|fail|실패" \
    || fail "Case G: expected push failure message in stderr, got: $ERR"

  rm -rf "$SRC" "$BARE"
  echo "  Case G OK"
}

# ── Case H: start_ref 무효 (SHA 존재하지 않음) → exit 2 + marker 보존 (S3 R2) ──
step H "start_ref 무효 (SHA 존재하지 않음) → exit 2 + marker 보존"
{
  read -r SRC BARE <<< "$(setup_repo)"
  add_develop_to_origin "$SRC"

  git -C "$SRC" switch -c feat/badref -q
  echo "w1" >> "$SRC/README"; git -C "$SRC" add README
  git -C "$SRC" -c commit.gpgsign=false commit -m "w1" -q

  MARKER="$(marker_abs_path "$SRC")"
  FAKE_SHA="0123456789abcdef0123456789abcdef01234567"
  write_marker "$MARKER" "$FAKE_SHA" "develop" "feat/badref" "false"

  set +e
  ERR=$(cd "$SRC" && PLAN_DEV_SESSION_BIN=/bin/false "$FINISH" 2>&1 >/dev/null)
  RC=$?
  set -e
  assert_eq "exit code" "2" "$RC"
  echo "$ERR" | grep -qi "start_ref" \
    || fail "Case H: expected 'start_ref' mention in stderr, got: $ERR"

  [ -f "$MARKER" ] || fail "Case H: marker should be preserved when start_ref invalid"

  rm -rf "$SRC" "$BARE"
  echo "  Case H OK"
}

# ── Case I: 커밋 없음 경로 → marker + MARKER_ADVISED 모두 삭제 (S3 R3) ──
step I "커밋 없음 경로 → marker + MARKER_ADVISED 모두 삭제"
{
  read -r SRC BARE <<< "$(setup_repo)"
  add_develop_to_origin "$SRC"

  git -C "$SRC" switch -c feat/nochg -q

  MARKER="$(marker_abs_path "$SRC")"
  CUR_HEAD=$(git -C "$SRC" rev-parse HEAD)
  write_marker "$MARKER" "$CUR_HEAD" "develop" "feat/nochg" "false"
  MARKER_ADVISED="$(dirname "$MARKER")/plan-dev-commit-advised"
  [ -f "$MARKER_ADVISED" ] || fail "Case I: precondition — advised marker should exist from write_marker"

  OUT=$(cd "$SRC" && PLAN_DEV_SESSION_BIN=/bin/false "$FINISH" 2>/dev/null)
  RC=$?
  assert_eq "exit code" "0" "$RC"
  echo "$OUT" | grep -qi "no new commits" \
    || fail "Case I: expected 'no new commits' message, got: $OUT"

  [ ! -f "$MARKER" ] || fail "Case I: marker should be removed"
  [ ! -f "$MARKER_ADVISED" ] || fail "Case I: MARKER_ADVISED should also be removed"

  rm -rf "$SRC" "$BARE"
  echo "  Case I OK"
}

# ── Case J: FINAL_BRANCH 로컬 선점 → suffix 재검사 + rename 안전 (S3 R4) ──
step J "FINAL_BRANCH 로컬 선점 → suffix 재검사 + rename 안전 (stale 브랜치 push 없음)"
{
  read -r SRC BARE <<< "$(setup_repo)"
  add_develop_to_origin "$SRC"

  # feat/dup 을 원격에 미리 push (충돌 유발용)
  git -C "$SRC" switch -c feat/dup -q
  echo "remote-dup" >> "$SRC/README"; git -C "$SRC" add README
  git -C "$SRC" -c commit.gpgsign=false commit -m "remote-dup" -q
  git -C "$SRC" push origin feat/dup -q 2>/dev/null

  # feat/dup-2 를 로컬에만 만들어 둠 (첫 suffix 후보를 로컬에서 선점 — 버그 재현 조건)
  git -C "$SRC" switch main -q
  git -C "$SRC" switch -c feat/dup-2 -q
  echo "stale-local" >> "$SRC/README"; git -C "$SRC" add README
  git -C "$SRC" -c commit.gpgsign=false commit -m "stale-local" -q
  STALE_SHA=$(git -C "$SRC" rev-parse HEAD)

  # 실제 작업은 feat/dup 위에서 (원격과 이름 충돌)
  git -C "$SRC" switch feat/dup -q
  echo "work1" >> "$SRC/README"; git -C "$SRC" add README
  git -C "$SRC" -c commit.gpgsign=false commit -m "work1" -q
  SRC_HEAD=$(git -C "$SRC" rev-parse HEAD)

  MARKER="$(marker_abs_path "$SRC")"
  OLD_REF=$(git -C "$SRC" rev-parse origin/main)
  write_marker "$MARKER" "$OLD_REF" "develop" "feat/dup" "false"

  OUT=$(cd "$SRC" && PLAN_DEV_SESSION_BIN=/bin/false "$FINISH" 2>/dev/null)
  RC=$?
  assert_eq "exit code" "0" "$RC"

  # 로컬 feat/dup-2 는 그대로 (rename 대상이 되면 안 됨)
  CUR_LOCAL_DUP2=$(git -C "$SRC" rev-parse refs/heads/feat/dup-2)
  assert_eq "local feat/dup-2 unchanged" "$STALE_SHA" "$CUR_LOCAL_DUP2"

  # bare 에는 실제 작업 커밋(SRC_HEAD)이 어떤 후보 이름으로든 push 되어 있어야
  PUSHED_REF=""
  for cand in feat/dup-2 feat/dup-3 feat/dup-4 feat/dup-5; do
    if git -C "$BARE" rev-parse "refs/heads/$cand" >/dev/null 2>&1; then
      CAND_SHA=$(git -C "$BARE" rev-parse "refs/heads/$cand")
      if [ "$CAND_SHA" = "$SRC_HEAD" ]; then
        PUSHED_REF="$cand"
        break
      fi
    fi
  done
  [ -n "$PUSHED_REF" ] || fail "Case J: 실제 작업 커밋이 bare 에 push 되지 않음. stdout: $OUT"

  # feat/dup-2 가 bare 에 push 됐다면 stale 내용이면 안 됨
  if git -C "$BARE" rev-parse refs/heads/feat/dup-2 >/dev/null 2>&1; then
    BARE_DUP2=$(git -C "$BARE" rev-parse refs/heads/feat/dup-2)
    [ "$BARE_DUP2" != "$STALE_SHA" ] || fail "Case J: stale 로컬 브랜치(feat/dup-2)가 그대로 push 됨"
  fi

  [ ! -f "$MARKER" ] || fail "Case J: marker should be cleared after success"

  rm -rf "$SRC" "$BARE"
  echo "  Case J OK"
}

echo ""
echo "PASS"
