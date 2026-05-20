#!/usr/bin/env bash
# finish_plan_dev_auto_push.sh — FINISH_AUTO_PUSH_WITHOUT_MARKER 옵션 검증
# marker 없는 상태에서의 동작 테스트.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FINISH="$REPO/scripts/finish-plan-dev.sh"

step() { echo ""; echo "[$1] $2"; }
fail() { echo "FAIL: $1" >&2; exit 1; }

[ -x "$FINISH" ] || fail "finish-plan-dev.sh not executable: $FINISH"

# git init with main as default branch
git_init_main() {
  local dir="$1"
  git -c init.defaultBranch=main init "$dir" -q 2>/dev/null \
    || git init "$dir" -q
  if [ "$(git -C "$dir" symbolic-ref --short HEAD 2>/dev/null)" != "main" ]; then
    git -C "$dir" checkout -b main -q 2>/dev/null || true
  fi
}

setup_repo() {
  local src
  src=$(mktemp -d)
  git_init_main "$src"
  git -C "$src" config user.email "t@e.local"
  git -C "$src" config user.name "tester"
  echo "init" > "$src/README"
  git -C "$src" add README
  git -C "$src" -c commit.gpgsign=false commit -m "init" -q
  echo "$src"
}

# ── Case A: FINISH_AUTO_PUSH_WITHOUT_MARKER=1 → push 시도 + exit 0
step A "FINISH_AUTO_PUSH_WITHOUT_MARKER=1 → push <branch> to origin + exit 0"
{
  SRC="$(setup_repo)"

  # marker 없는 상태
  OUT=$(cd "$SRC" && FINISH_AUTO_PUSH_WITHOUT_MARKER=1 GIT_PUSH_CMD=echo PLAN_DEV_SESSION_BIN=/bin/false "$FINISH" 2>/dev/null)
  RC=$?

  [ "$RC" -eq 0 ] || fail "Case A: expected exit 0, got $RC"
  echo "$OUT" | grep -qi "push.*to origin\|to origin" \
    || fail "Case A: expected 'push ... to origin' in stdout, got: $OUT"

  rm -rf "$SRC"
  echo "  Case A OK"
}

# ── Case B: FINISH_AUTO_PUSH_WITHOUT_MARKER 미설정 → no marker — skip + exit 0
step B "FINISH_AUTO_PUSH_WITHOUT_MARKER 미설정 → no marker — skip + exit 0"
{
  SRC="$(setup_repo)"

  OUT=$(cd "$SRC" && PLAN_DEV_SESSION_BIN=/bin/false "$FINISH" 2>/dev/null)
  RC=$?

  [ "$RC" -eq 0 ] || fail "Case B: expected exit 0, got $RC"
  echo "$OUT" | grep -qi "no marker" \
    || fail "Case B: expected 'no marker' in stdout, got: $OUT"

  rm -rf "$SRC"
  echo "  Case B OK"
}

echo ""
echo "PASS"
