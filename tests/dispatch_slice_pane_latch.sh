#!/usr/bin/env bash
# dispatch_slice_pane_latch.sh — dispatch-slice-pane.sh 의 _dispatch_latch_plan_file 단위 테스트.
# dispatcher 를 source 해서 함수만 사용 (sourcing guard — main flow 실행 안 함).
#
# 케이스:
#   L1: marker 활성 + plan_file 없음 + GRACE 내 후보 존재 → set-plan 으로 latch
#   L2: marker 에 이미 유효한 plan_file 있음 → 재latch 안 함 (기존 값 유지)
#   L3: marker 없음 → no-op (에러 없이 조용히 통과)
#   L4: 후보 여럿 → 가장 최근(mtime 최대) 선택

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DISPATCH="$REPO/scripts/dispatch-slice-pane.sh"
SESSION_SCRIPT="$REPO/scripts/plan-dev-session.sh"

step() { echo "[$1] $2"; }
fail() { echo "❌ FAIL: $1" >&2; exit 1; }

[ -f "$DISPATCH" ] || fail "dispatcher missing"

source "$DISPATCH" 2>/dev/null || true
type _dispatch_latch_plan_file > /dev/null 2>&1 || fail "_dispatch_latch_plan_file 함수 미정의"

setup_tmp_repo() {
  local dir
  dir="$(mktemp -d)"
  git -C "$dir" init -q
  git -C "$dir" config user.email "test@example.com"
  git -C "$dir" config user.name "Test"
  git -C "$dir" commit --allow-empty -m "init" -q
  echo "$dir"
}

cleanup_tmp() { [ -n "${1:-}" ] && rm -rf "$1"; }

# ─────────────────────────────────────────
# L1: 후보 존재 → latch
# ─────────────────────────────────────────
step L1 "marker 활성 + plan_file 없음 + GRACE 내 후보 존재 → latch"
TMPDIR1="$(setup_tmp_repo)"
trap 'cleanup_tmp "$TMPDIR1"' EXIT

(cd "$TMPDIR1" && "$SESSION_SCRIPT" start --quiet 2>/dev/null || true)

PLANS_DIR1="$TMPDIR1/plans"
mkdir -p "$PLANS_DIR1"
CAND1="$PLANS_DIR1/candidate.md"
echo "# plan" > "$CAND1"

(
  cd "$TMPDIR1"
  PLAN_MODE_PLANS_DIR="$PLANS_DIR1" _dispatch_latch_plan_file
)

GOT1=$(cd "$TMPDIR1" && "$SESSION_SCRIPT" query --key=plan_file 2>/dev/null)
[ "$GOT1" = "$CAND1" ] || fail "L1: latch 안 됨. got='$GOT1' expected='$CAND1'"
echo "  L1 OK"
trap - EXIT
cleanup_tmp "$TMPDIR1"

# ─────────────────────────────────────────
# L2: 이미 유효한 plan_file 존재 → 재latch 안 함
# ─────────────────────────────────────────
step L2 "marker 에 이미 유효한 plan_file 존재 → 재latch 안 함"
TMPDIR2="$(setup_tmp_repo)"
trap 'cleanup_tmp "$TMPDIR2"' EXIT

(cd "$TMPDIR2" && "$SESSION_SCRIPT" start --quiet 2>/dev/null || true)

PLANS_DIR2="$TMPDIR2/plans"
mkdir -p "$PLANS_DIR2"
EXISTING2="$TMPDIR2/existing-plan.md"
echo "# existing" > "$EXISTING2"
(cd "$TMPDIR2" && "$SESSION_SCRIPT" set-plan "$EXISTING2" 2>/dev/null)

OTHER2="$PLANS_DIR2/other-candidate.md"
echo "# other" > "$OTHER2"

(
  cd "$TMPDIR2"
  PLAN_MODE_PLANS_DIR="$PLANS_DIR2" _dispatch_latch_plan_file
)

GOT2=$(cd "$TMPDIR2" && "$SESSION_SCRIPT" query --key=plan_file 2>/dev/null)
[ "$GOT2" = "$EXISTING2" ] || fail "L2: 기존 plan_file 이 덮어써짐. got='$GOT2' expected='$EXISTING2'"
echo "  L2 OK"
trap - EXIT
cleanup_tmp "$TMPDIR2"

# ─────────────────────────────────────────
# L3: marker 없음 → no-op
# ─────────────────────────────────────────
step L3 "marker 없음 → no-op (에러 없이 통과)"
TMPDIR3="$(setup_tmp_repo)"
trap 'cleanup_tmp "$TMPDIR3"' EXIT

PLANS_DIR3="$TMPDIR3/plans"
mkdir -p "$PLANS_DIR3"
touch "$PLANS_DIR3/some.md"

(
  cd "$TMPDIR3"
  PLAN_MODE_PLANS_DIR="$PLANS_DIR3" _dispatch_latch_plan_file
) || fail "L3: 함수가 실패해선 안 됨 (best-effort)"
echo "  L3 OK"
trap - EXIT
cleanup_tmp "$TMPDIR3"

# ─────────────────────────────────────────
# L4: 후보 여럿 → 가장 최근 선택
# ─────────────────────────────────────────
step L4 "후보 여럿 → mtime 최대(가장 최근) 선택"
TMPDIR4="$(setup_tmp_repo)"
trap 'cleanup_tmp "$TMPDIR4"' EXIT

(cd "$TMPDIR4" && "$SESSION_SCRIPT" start --quiet 2>/dev/null || true)

PLANS_DIR4="$TMPDIR4/plans"
mkdir -p "$PLANS_DIR4"
OLDER4="$PLANS_DIR4/older.md"
NEWER4="$PLANS_DIR4/newer.md"
touch "$OLDER4"
sleep 1
touch "$NEWER4"

(
  cd "$TMPDIR4"
  PLAN_MODE_PLANS_DIR="$PLANS_DIR4" _dispatch_latch_plan_file
)

GOT4=$(cd "$TMPDIR4" && "$SESSION_SCRIPT" query --key=plan_file 2>/dev/null)
[ "$GOT4" = "$NEWER4" ] || fail "L4: 최신 후보 선택 안 됨. got='$GOT4' expected='$NEWER4'"
echo "  L4 OK"
trap - EXIT
cleanup_tmp "$TMPDIR4"

echo ""
echo "OK"
