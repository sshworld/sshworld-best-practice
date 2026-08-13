#!/usr/bin/env bash
# plan_dev_design_latch.sh — 설계 문서 latch(set-design) + finish-plan-dev.sh
# push 게이트(실측 칸 검사) 테스트.
# TDD Red: 먼저 작성 후 scripts/plan-dev-session.sh, scripts/finish-plan-dev.sh
# 수정으로 Green. 하네스는 tests/plan_dev_session_setplan.sh (plain repo) 와
# tests/plan_dev_finish.sh (bare + file:// remote) 를 그대로 재사용.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SESSION_SCRIPT="$REPO/scripts/plan-dev-session.sh"
FINISH="$REPO/scripts/finish-plan-dev.sh"

step() { echo ""; echo "[$1] $2"; }
fail() { echo "FAIL: $1" >&2; exit 1; }

[ -x "$SESSION_SCRIPT" ] || fail "script not executable or missing: $SESSION_SCRIPT"
[ -x "$FINISH" ] || fail "finish-plan-dev.sh not executable: $FINISH"

# ── plain-repo 하네스 (plan_dev_session_setplan.sh 와 동일) ─────────

setup_tmp_repo() {
  local dir
  dir="$(mktemp -d)"
  git -C "$dir" init -q
  git -C "$dir" config user.email "test@example.com"
  git -C "$dir" config user.name "Test"
  git -C "$dir" commit --allow-empty -m "init" -q
  echo "$dir"
}

cleanup_tmp() {
  [ -n "${1:-}" ] && rm -rf "$1"
}

# ── bare-repo push 하네스 (plan_dev_finish.sh 와 동일) ──────────────

git_init_main() {
  local dir="$1"
  git -c init.defaultBranch=main init "$dir" -q 2>/dev/null \
    || git init "$dir" -q
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

  echo "init" > "$src/README"
  git -C "$src" add README
  git -C "$src" -c commit.gpgsign=false commit -m "init" -q
  git -C "$src" push origin main -q 2>/dev/null

  echo "$src $bare"
}

add_develop_to_origin() {
  local src="$1"
  git -C "$src" push origin "main:develop" -q 2>/dev/null
  git -C "$src" fetch origin -q 2>/dev/null
}

marker_abs_path() {
  local src="$1"
  local common_dir
  common_dir=$(git -C "$src" rev-parse --git-common-dir)
  case "$common_dir" in
    /*) echo "$common_dir/plan-dev-session.json" ;;
    *)  echo "$src/$common_dir/plan-dev-session.json" ;;
  esac
}

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
  local repo_dir
  repo_dir="$(dirname "$marker_path")"
  touch "${repo_dir}/plan-dev-commit-advised"
}

# 설계 문서 fixture 작성: '## 6. 결과' 섹션에 지정한 실측 줄 하나만 삽입
write_design_doc() {
  local path="$1" measure_line="$2"
  cat > "$path" <<EOF
# 설계 문서

## 1. 배경

테스트용.

## 6. 결과

${measure_line}
EOF
}

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" != "$actual" ]; then
    fail "$label: expected='$expected' actual='$actual'"
  fi
}

# ─────────────────────────────────────────
# T1: set-design 실행 후 marker 에 design_doc 필드 기록
# ─────────────────────────────────────────
step T1 "set-design 실행 후 marker json 에 design_doc 필드 기록"
TMPDIR1="$(setup_tmp_repo)"
trap 'cleanup_tmp "$TMPDIR1"' EXIT

(
  cd "$TMPDIR1"
  "$SESSION_SCRIPT" start --quiet 2>/dev/null || true
)

MARKER1="$TMPDIR1/.git/plan-dev-session.json"
[ -f "$MARKER1" ] || fail "T1: start 후 marker 없음"

DESIGN_FILE1="$TMPDIR1/design.md"
write_design_doc "$DESIGN_FILE1" "- 실측: 92ms 개선"

(
  cd "$TMPDIR1"
  "$SESSION_SCRIPT" set-design "$DESIGN_FILE1" 2>/dev/null
) || fail "T1: set-design 실패"

DESIGN_FIELD1=$(cd "$TMPDIR1" && "$SESSION_SCRIPT" query --key=design_doc 2>/dev/null)
[ "$DESIGN_FIELD1" = "$DESIGN_FILE1" ] || fail "T1: design_doc 미기록. got='$DESIGN_FIELD1' expected='$DESIGN_FILE1'"
echo "  T1 OK"
trap - EXIT
cleanup_tmp "$TMPDIR1"

# ─────────────────────────────────────────
# T2: set-design 이 기존 start_ts/start_ref/plan_file 을 clobber 하지 않음
# ─────────────────────────────────────────
step T2 "set-design 이 기존 start_ts/start_ref/plan_file 보존"
TMPDIR2="$(setup_tmp_repo)"
trap 'cleanup_tmp "$TMPDIR2"' EXIT

(
  cd "$TMPDIR2"
  "$SESSION_SCRIPT" start --quiet 2>/dev/null || true
)

MARKER2="$TMPDIR2/.git/plan-dev-session.json"
[ -f "$MARKER2" ] || fail "T2: start 후 marker 없음"

TS_BEFORE=$(cd "$TMPDIR2" && "$SESSION_SCRIPT" query --key=start_ts 2>/dev/null)
REF_BEFORE=$(cd "$TMPDIR2" && "$SESSION_SCRIPT" query --key=start_ref 2>/dev/null)

PLAN_FILE2="$TMPDIR2/my-plan.md"
echo "# plan" > "$PLAN_FILE2"
(
  cd "$TMPDIR2"
  "$SESSION_SCRIPT" set-plan "$PLAN_FILE2" 2>/dev/null
) || fail "T2: set-plan 실패"

DESIGN_FILE2="$TMPDIR2/design.md"
write_design_doc "$DESIGN_FILE2" "- 실측: 값 채워짐"
(
  cd "$TMPDIR2"
  "$SESSION_SCRIPT" set-design "$DESIGN_FILE2" 2>/dev/null
) || fail "T2: set-design 실패"

TS_AFTER=$(cd "$TMPDIR2" && "$SESSION_SCRIPT" query --key=start_ts 2>/dev/null)
REF_AFTER=$(cd "$TMPDIR2" && "$SESSION_SCRIPT" query --key=start_ref 2>/dev/null)
PLAN_FIELD_AFTER=$(cd "$TMPDIR2" && "$SESSION_SCRIPT" query --key=plan_file 2>/dev/null)
DESIGN_FIELD2=$(cd "$TMPDIR2" && "$SESSION_SCRIPT" query --key=design_doc 2>/dev/null)

[ "$TS_BEFORE" = "$TS_AFTER" ] || fail "T2: start_ts 변경됨. before='$TS_BEFORE' after='$TS_AFTER'"
[ "$REF_BEFORE" = "$REF_AFTER" ] || fail "T2: start_ref 변경됨. before='$REF_BEFORE' after='$REF_AFTER'"
[ "$PLAN_FIELD_AFTER" = "$PLAN_FILE2" ] || fail "T2: plan_file 소멸. got='$PLAN_FIELD_AFTER'"
[ "$DESIGN_FIELD2" = "$DESIGN_FILE2" ] || fail "T2: design_doc 미기록. got='$DESIGN_FIELD2'"
echo "  T2 OK"
trap - EXIT
cleanup_tmp "$TMPDIR2"

# ─────────────────────────────────────────
# T3: 인자 없이 set-design → exit 2 + 사용법 출력
# ─────────────────────────────────────────
step T3 "인자 없이 set-design → exit 2 + 사용법"
TMPDIR3="$(setup_tmp_repo)"
trap 'cleanup_tmp "$TMPDIR3"' EXIT

(
  cd "$TMPDIR3"
  "$SESSION_SCRIPT" start --quiet 2>/dev/null || true
)

set +e
ERR=$(cd "$TMPDIR3" && "$SESSION_SCRIPT" set-design 2>&1 >/dev/null)
RC=$?
set -e
assert_eq "T3 exit code" "2" "$RC"
echo "$ERR" | grep -qi "set-design" || fail "T3: 사용법에 'set-design' 언급 없음. got: $ERR"
echo "  T3 OK"
trap - EXIT
cleanup_tmp "$TMPDIR3"

# ─────────────────────────────────────────
# T4: marker 없을 때 set-design → exit 0 + no-op
# ─────────────────────────────────────────
step T4 "marker 부재 시 set-design no-op + exit 0"
TMPDIR4="$(setup_tmp_repo)"
trap 'cleanup_tmp "$TMPDIR4"' EXIT

RC=$(
  cd "$TMPDIR4"
  "$SESSION_SCRIPT" set-design "$TMPDIR4/no-marker-design.md" >/dev/null 2>&1
  echo $?
)
[ "$RC" = "0" ] || fail "T4: exit code should be 0, got $RC"
[ ! -f "$TMPDIR4/.git/plan-dev-session.json" ] || fail "T4: marker 가 생성되면 안 됨"
echo "  T4 OK"
trap - EXIT
cleanup_tmp "$TMPDIR4"

# ─────────────────────────────────────────
# T5: latch 있고 실측 칸 플레이스홀더 → finish exit 2 + 안내
# ─────────────────────────────────────────
step T5 "latch + 실측 플레이스홀더 → finish exit 2"
{
  read -r SRC BARE <<< "$(setup_repo)"
  add_develop_to_origin "$SRC"

  git -C "$SRC" switch -c feat/design-t5 -q
  echo "c1" >> "$SRC/README"; git -C "$SRC" add README
  git -C "$SRC" -c commit.gpgsign=false commit -m "c1" -q

  MARKER="$(marker_abs_path "$SRC")"
  OLD_REF=$(git -C "$SRC" rev-parse origin/main)
  write_marker "$MARKER" "$OLD_REF" "develop" "feat/design-t5" "false"

  DESIGN_FILE5="$SRC/design.md"
  write_design_doc "$DESIGN_FILE5" "| 실측 | 채움 |"
  (cd "$SRC" && "$SESSION_SCRIPT" set-design "$DESIGN_FILE5" >/dev/null 2>&1) \
    || fail "T5: set-design 실패"

  set +e
  ERR=$(cd "$SRC" && PLAN_DEV_SESSION_BIN=/bin/false "$FINISH" 2>&1 >/dev/null)
  RC=$?
  set -e
  assert_eq "T5 exit code" "2" "$RC"
  echo "$ERR" | grep -qi "실측" || fail "T5: stderr 에 '실측' 언급 없음. got: $ERR"
  [ -f "$MARKER" ] || fail "T5: push 실패했으니 marker 보존돼야 함"

  rm -rf "$SRC" "$BARE"
  echo "  T5 OK"
}

# ─────────────────────────────────────────
# T6: latch 있고 실측 칸 채워짐 → 게이트 통과 + push 성공
# ─────────────────────────────────────────
step T6 "latch + 실측 채워짐 → 게이트 통과, push 성공"
{
  read -r SRC BARE <<< "$(setup_repo)"
  add_develop_to_origin "$SRC"

  git -C "$SRC" switch -c feat/design-t6 -q
  echo "c1" >> "$SRC/README"; git -C "$SRC" add README
  git -C "$SRC" -c commit.gpgsign=false commit -m "c1" -q

  MARKER="$(marker_abs_path "$SRC")"
  OLD_REF=$(git -C "$SRC" rev-parse origin/main)
  write_marker "$MARKER" "$OLD_REF" "develop" "feat/design-t6" "false"

  DESIGN_FILE6="$SRC/design.md"
  write_design_doc "$DESIGN_FILE6" "- 실측: p95 120ms → 45ms"
  (cd "$SRC" && "$SESSION_SCRIPT" set-design "$DESIGN_FILE6" >/dev/null 2>&1) \
    || fail "T6: set-design 실패"

  OUT=$(cd "$SRC" && PLAN_DEV_SESSION_BIN=/bin/false "$FINISH" 2>/dev/null)
  RC=$?
  assert_eq "T6 exit code" "0" "$RC"
  echo "$OUT" | grep -q "pushed" || fail "T6: stdout 에 'pushed' 없음. got: $OUT"
  [ ! -f "$MARKER" ] || fail "T6: 성공 후 marker 삭제돼야 함"

  rm -rf "$SRC" "$BARE"
  echo "  T6 OK"
}

# ─────────────────────────────────────────
# T7: latch 있고 실측 칸에 '미검증' 포함 → 통과
# ─────────────────────────────────────────
step T7 "latch + 실측에 '미검증' 포함 → 통과"
{
  read -r SRC BARE <<< "$(setup_repo)"
  add_develop_to_origin "$SRC"

  git -C "$SRC" switch -c feat/design-t7 -q
  echo "c1" >> "$SRC/README"; git -C "$SRC" add README
  git -C "$SRC" -c commit.gpgsign=false commit -m "c1" -q

  MARKER="$(marker_abs_path "$SRC")"
  OLD_REF=$(git -C "$SRC" rev-parse origin/main)
  write_marker "$MARKER" "$OLD_REF" "develop" "feat/design-t7" "false"

  DESIGN_FILE7="$SRC/design.md"
  write_design_doc "$DESIGN_FILE7" "- 실측: 미검증 — 재발 감시 중"
  (cd "$SRC" && "$SESSION_SCRIPT" set-design "$DESIGN_FILE7" >/dev/null 2>&1) \
    || fail "T7: set-design 실패"

  OUT=$(cd "$SRC" && PLAN_DEV_SESSION_BIN=/bin/false "$FINISH" 2>/dev/null)
  RC=$?
  assert_eq "T7 exit code" "0" "$RC"
  echo "$OUT" | grep -q "pushed" || fail "T7: stdout 에 'pushed' 없음. got: $OUT"

  rm -rf "$SRC" "$BARE"
  echo "  T7 OK"
}

# ─────────────────────────────────────────
# T8: latch 있는데 파일이 없음 → exit 2 + 안내
# ─────────────────────────────────────────
step T8 "latch 됐지만 파일 없음 → finish exit 2"
{
  read -r SRC BARE <<< "$(setup_repo)"
  add_develop_to_origin "$SRC"

  git -C "$SRC" switch -c feat/design-t8 -q
  echo "c1" >> "$SRC/README"; git -C "$SRC" add README
  git -C "$SRC" -c commit.gpgsign=false commit -m "c1" -q

  MARKER="$(marker_abs_path "$SRC")"
  OLD_REF=$(git -C "$SRC" rev-parse origin/main)
  write_marker "$MARKER" "$OLD_REF" "develop" "feat/design-t8" "false"

  MISSING_DESIGN="$SRC/does-not-exist.md"
  (cd "$SRC" && "$SESSION_SCRIPT" set-design "$MISSING_DESIGN" >/dev/null 2>&1) \
    || fail "T8: set-design 실패"

  set +e
  ERR=$(cd "$SRC" && PLAN_DEV_SESSION_BIN=/bin/false "$FINISH" 2>&1 >/dev/null)
  RC=$?
  set -e
  assert_eq "T8 exit code" "2" "$RC"
  echo "$ERR" | grep -qi "latch" || fail "T8: stderr 에 'latch' 언급 없음. got: $ERR"
  [ -f "$MARKER" ] || fail "T8: marker 보존돼야 함"

  rm -rf "$SRC" "$BARE"
  echo "  T8 OK"
}

# ─────────────────────────────────────────
# T9: latch 없고 DESIGN_DOC=none → 통과
# ─────────────────────────────────────────
step T9 "latch 없음 + DESIGN_DOC=none → 통과"
{
  read -r SRC BARE <<< "$(setup_repo)"
  add_develop_to_origin "$SRC"

  git -C "$SRC" switch -c feat/design-t9 -q
  echo "c1" >> "$SRC/README"; git -C "$SRC" add README
  git -C "$SRC" -c commit.gpgsign=false commit -m "c1" -q

  MARKER="$(marker_abs_path "$SRC")"
  OLD_REF=$(git -C "$SRC" rev-parse origin/main)
  write_marker "$MARKER" "$OLD_REF" "develop" "feat/design-t9" "false"

  OUT=$(cd "$SRC" && DESIGN_DOC=none PLAN_DEV_SESSION_BIN=/bin/false "$FINISH" 2>/dev/null)
  RC=$?
  assert_eq "T9 exit code" "0" "$RC"
  echo "$OUT" | grep -q "pushed" || fail "T9: stdout 에 'pushed' 없음. got: $OUT"

  rm -rf "$SRC" "$BARE"
  echo "  T9 OK"
}

# ─────────────────────────────────────────
# T10: latch 없고 선언도 없음 → exit 2 + 두 선택지 안내
# ─────────────────────────────────────────
step T10 "latch 없음 + 선언 없음 → exit 2 + 두 선택지"
{
  read -r SRC BARE <<< "$(setup_repo)"
  add_develop_to_origin "$SRC"

  git -C "$SRC" switch -c feat/design-t10 -q
  echo "c1" >> "$SRC/README"; git -C "$SRC" add README
  git -C "$SRC" -c commit.gpgsign=false commit -m "c1" -q

  MARKER="$(marker_abs_path "$SRC")"
  OLD_REF=$(git -C "$SRC" rev-parse origin/main)
  write_marker "$MARKER" "$OLD_REF" "develop" "feat/design-t10" "false"

  set +e
  ERR=$(cd "$SRC" && PLAN_DEV_SESSION_BIN=/bin/false "$FINISH" 2>&1 >/dev/null)
  RC=$?
  set -e
  assert_eq "T10 exit code" "2" "$RC"
  echo "$ERR" | grep -qi "set-design" || fail "T10: 'set-design' 선택지 안내 없음. got: $ERR"
  echo "$ERR" | grep -q "DESIGN_DOC=none" || fail "T10: 'DESIGN_DOC=none' 선택지 안내 없음. got: $ERR"
  [ -f "$MARKER" ] || fail "T10: marker 보존돼야 함"

  rm -rf "$SRC" "$BARE"
  echo "  T10 OK"
}

# ─────────────────────────────────────────
# T11: SKIP_DESIGN_DOC=1 → 게이트 1회 우회
# ─────────────────────────────────────────
step T11 "SKIP_DESIGN_DOC=1 → 게이트 우회, push 성공"
{
  read -r SRC BARE <<< "$(setup_repo)"
  add_develop_to_origin "$SRC"

  git -C "$SRC" switch -c feat/design-t11 -q
  echo "c1" >> "$SRC/README"; git -C "$SRC" add README
  git -C "$SRC" -c commit.gpgsign=false commit -m "c1" -q

  MARKER="$(marker_abs_path "$SRC")"
  OLD_REF=$(git -C "$SRC" rev-parse origin/main)
  write_marker "$MARKER" "$OLD_REF" "develop" "feat/design-t11" "false"

  DESIGN_FILE11="$SRC/design.md"
  write_design_doc "$DESIGN_FILE11" "- 실측: TODO"
  (cd "$SRC" && "$SESSION_SCRIPT" set-design "$DESIGN_FILE11" >/dev/null 2>&1) \
    || fail "T11: set-design 실패"

  OUT=$(cd "$SRC" && SKIP_DESIGN_DOC=1 PLAN_DEV_SESSION_BIN=/bin/false "$FINISH" 2>/dev/null)
  RC=$?
  assert_eq "T11 exit code" "0" "$RC"
  echo "$OUT" | grep -q "pushed" || fail "T11: stdout 에 'pushed' 없음. got: $OUT"

  rm -rf "$SRC" "$BARE"
  echo "  T11 OK"
}

# ─────────────────────────────────────────
# T12: DISABLE_DESIGN_DOC_GATE=1 → 게이트 영구 off
# ─────────────────────────────────────────
step T12 "DISABLE_DESIGN_DOC_GATE=1 → 게이트 off, push 성공"
{
  read -r SRC BARE <<< "$(setup_repo)"
  add_develop_to_origin "$SRC"

  git -C "$SRC" switch -c feat/design-t12 -q
  echo "c1" >> "$SRC/README"; git -C "$SRC" add README
  git -C "$SRC" -c commit.gpgsign=false commit -m "c1" -q

  MARKER="$(marker_abs_path "$SRC")"
  OLD_REF=$(git -C "$SRC" rev-parse origin/main)
  write_marker "$MARKER" "$OLD_REF" "develop" "feat/design-t12" "false"
  # latch 도 선언도 없음 — DISABLE 이 게이트 진입 자체를 막는지 확인

  OUT=$(cd "$SRC" && DISABLE_DESIGN_DOC_GATE=1 PLAN_DEV_SESSION_BIN=/bin/false "$FINISH" 2>/dev/null)
  RC=$?
  assert_eq "T12 exit code" "0" "$RC"
  echo "$OUT" | grep -q "pushed" || fail "T12: stdout 에 'pushed' 없음. got: $OUT"

  rm -rf "$SRC" "$BARE"
  echo "  T12 OK"
}

# ─────────────────────────────────────────
# T13: 회귀 — plan_dev_finish.sh / plan_dev_session_setplan.sh 여전히 통과
# ─────────────────────────────────────────
step T13 "회귀: plan_dev_finish.sh / plan_dev_session_setplan.sh"
{
  OUT_FINISH=$(bash "$REPO/tests/plan_dev_finish.sh" 2>&1)
  echo "$OUT_FINISH" | tail -1 | grep -q "^PASS$" \
    || fail "T13: plan_dev_finish.sh 회귀 실패. tail: $(echo "$OUT_FINISH" | tail -5)"

  OUT_SETPLAN=$(bash "$REPO/tests/plan_dev_session_setplan.sh" 2>&1)
  echo "$OUT_SETPLAN" | tail -1 | grep -q "^OK$" \
    || fail "T13: plan_dev_session_setplan.sh 회귀 실패. tail: $(echo "$OUT_SETPLAN" | tail -5)"

  echo "  T13 OK"
}

echo ""
echo "OK"
