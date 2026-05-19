#!/usr/bin/env bash
# Slice 2b — finish-plan-dev.sh 통합 테스트.
# bare repo + file:// remote 로 실제 git push 검증.

set -uo pipefail

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
mp, start_ref, base_branch, work_branch, auto_val = sys.argv[1:]
d = {
    'start_ref':   start_ref,
    'base_branch': base_branch,
    'work_branch': work_branch,
    'start_ts':    '2026-01-01T00:00:00Z',
    'start_pid':   99999,
    'auto_branch': auto_val == 'True',
}
with open(mp, 'w') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
PYEOF
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

echo ""
echo "PASS"
