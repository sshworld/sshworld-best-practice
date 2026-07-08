#!/usr/bin/env bash
# Slice 2a — plan-dev-session.sh start/query/clear 동작 검증.
# TDD: 이 파일을 먼저 작성 (Red). scripts/plan-dev-session.sh 구현 후 Green.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO/scripts/plan-dev-session.sh"

step() { echo "[$1] $2"; }
fail() { echo "FAIL: $1" >&2; exit 1; }

[ -x "$SCRIPT" ] || fail "script not executable or missing: $SCRIPT"

# 임시 git repo 생성 헬퍼
setup_tmp_repo() {
  local dir
  dir="$(mktemp -d)"
  git -C "$dir" init -q
  git -C "$dir" config user.email "test@example.com"
  git -C "$dir" config user.name "Test"
  # 최초 commit 없으면 HEAD 가 없어 branch 조회가 안 됨
  git -C "$dir" commit --allow-empty -m "init" -q
  echo "$dir"
}

cleanup_tmp() {
  [ -n "${1:-}" ] && rm -rf "$1"
}

# ─────────────────────────────────────────
# TC1: start → marker 존재 + JSON 키 6개
# ─────────────────────────────────────────
step 1 "start → marker 파일 존재 + JSON 키 6개"
TMPDIR1="$(setup_tmp_repo)"
trap 'cleanup_tmp "$TMPDIR1"' EXIT

# 해당 repo 안에서 실행 (base 없으면 경고 + exit 0 — 정상)
(
  cd "$TMPDIR1"
  "$SCRIPT" start --quiet 2>/dev/null || true
)

MARKER_PATH="$TMPDIR1/.git/plan-dev-session.json"
[ -f "$MARKER_PATH" ] || fail "TC1: marker 파일 없음: $MARKER_PATH"

# 키 6개 검사
for KEY in start_ref base_branch work_branch start_ts start_pid auto_branch; do
  python3 -c "
import json, sys
d = json.load(open('$MARKER_PATH'))
if '$KEY' not in d:
    print('missing key: $KEY'); sys.exit(1)
" || fail "TC1: JSON 키 누락: $KEY"
done
echo "  TC1 OK"
trap - EXIT
cleanup_tmp "$TMPDIR1"

# ─────────────────────────────────────────
# TC2: 두 번째 start 즉시 호출 → 기존 marker 유지 + "이미 진행 중" 메시지
# ─────────────────────────────────────────
step 2 "두 번째 start (PID 살아있음) → 기존 marker 유지 + 이미 진행 중"
TMPDIR2="$(setup_tmp_repo)"
trap 'cleanup_tmp "$TMPDIR2"' EXIT

(
  cd "$TMPDIR2"
  "$SCRIPT" start --quiet 2>/dev/null || true
)

MARKER2="$TMPDIR2/.git/plan-dev-session.json"
[ -f "$MARKER2" ] || fail "TC2: 첫 start 후 marker 없음"

# start_pid 를 현재 테스트 스크립트의 PID (살아있음) 로 교체
python3 -c "
import json
f = '$MARKER2'
d = json.load(open(f))
d['start_pid'] = $$
open(f, 'w').write(json.dumps(d, indent=2) + '\n')
"

# mtime 저장
MTIME_BEFORE=$(stat -f "%m" "$MARKER2" 2>/dev/null || stat -c "%Y" "$MARKER2" 2>/dev/null)

# 잠시 기다려 mtime 차이 확보
sleep 1

# 두 번째 start
STDERR2=$(
  cd "$TMPDIR2"
  "$SCRIPT" start 2>&1 || true
)

MTIME_AFTER=$(stat -f "%m" "$MARKER2" 2>/dev/null || stat -c "%Y" "$MARKER2" 2>/dev/null)

# mtime 동일해야 (파일 변경 없음)
[ "$MTIME_BEFORE" = "$MTIME_AFTER" ] || fail "TC2: 기존 marker 가 덮어쓰여짐 (mtime 변경)"

# stderr/stdout 에 "이미 진행" 포함
echo "$STDERR2" | grep -q "이미 진행" || fail "TC2: '이미 진행 중' 메시지 없음. 출력: $STDERR2"
echo "  TC2 OK"
trap - EXIT
cleanup_tmp "$TMPDIR2"

# ─────────────────────────────────────────
# TC3: stale PID → start 다시 → 새 marker + .bak 존재
# ─────────────────────────────────────────
step 3 "stale PID → start 재호출 → 새 marker + .bak"
TMPDIR3="$(setup_tmp_repo)"
trap 'cleanup_tmp "$TMPDIR3"' EXIT

(
  cd "$TMPDIR3"
  "$SCRIPT" start --quiet 2>/dev/null || true
)

MARKER3="$TMPDIR3/.git/plan-dev-session.json"
[ -f "$MARKER3" ] || fail "TC3: 첫 start 후 marker 없음"

# start_pid 를 절대 살아있지 않은 큰 숫자로 교체
python3 -c "
import json
f = '$MARKER3'
d = json.load(open(f))
d['start_pid'] = 9999999
open(f, 'w').write(json.dumps(d))
"

# stale marker 의 start_ts 를 25시간 전으로 설정 (stale 확실히)
python3 -c "
import json
from datetime import datetime, timezone, timedelta
f = '$MARKER3'
d = json.load(open(f))
old_ts = (datetime.now(timezone.utc) - timedelta(hours=25)).strftime('%Y-%m-%dT%H:%M:%SZ')
d['start_ts'] = old_ts
d['start_pid'] = 9999999
open(f, 'w').write(json.dumps(d))
"

sleep 1

(
  cd "$TMPDIR3"
  "$SCRIPT" start --quiet 2>/dev/null || true
)

[ -f "$MARKER3" ] || fail "TC3: 새 marker 없음"
[ -f "${MARKER3}.bak" ] || fail "TC3: .bak 파일 없음"

# 새 marker 의 start_pid 가 9999999 가 아니어야 함
NEW_PID=$(python3 -c "import json; d = json.load(open('$MARKER3')); print(d['start_pid'])")
[ "$NEW_PID" != "9999999" ] || fail "TC3: 새 marker 의 start_pid 가 여전히 stale PID"
echo "  TC3 OK"
trap - EXIT
cleanup_tmp "$TMPDIR3"

# ─────────────────────────────────────────
# TC4: detached HEAD → start → exit 2 + stderr "detached HEAD"
# ─────────────────────────────────────────
step 4 "detached HEAD → exit 2 + detached HEAD 메시지"
TMPDIR4="$(setup_tmp_repo)"
trap 'cleanup_tmp "$TMPDIR4"' EXIT

SHA=$(git -C "$TMPDIR4" rev-parse HEAD)
git -C "$TMPDIR4" checkout --detach "$SHA" -q 2>/dev/null

STDERR4=""
RC4=0
(
  cd "$TMPDIR4"
  "$SCRIPT" start 2>&1
) && RC4=$? || RC4=$?

# exit code 2 확인
[ "$RC4" = "2" ] || fail "TC4: detached HEAD 시 exit 2 기대, 실제 $RC4"

STDERR4=$(
  cd "$TMPDIR4"
  "$SCRIPT" start 2>&1 || true
)
echo "$STDERR4" | grep -qi "detached" || fail "TC4: 'detached HEAD' 메시지 없음. 출력: $STDERR4"
echo "  TC4 OK"
trap - EXIT
cleanup_tmp "$TMPDIR4"

# ─────────────────────────────────────────
# TC5: query --key=base_branch → 정확한 branch 명 출력
# ─────────────────────────────────────────
step 5 "query --key=base_branch → base_branch 값 출력"
TMPDIR5="$(setup_tmp_repo)"
trap 'cleanup_tmp "$TMPDIR5"' EXIT

# main 브랜치로 이름 강제 (git init 디폴트가 master 일 수 있음)
git -C "$TMPDIR5" checkout -b main -q 2>/dev/null || true

(
  cd "$TMPDIR5"
  "$SCRIPT" start --quiet 2>/dev/null || true
)

MARKER5="$TMPDIR5/.git/plan-dev-session.json"
[ -f "$MARKER5" ] || fail "TC5: marker 없음"

# marker 에서 base_branch 직접 읽기
EXPECTED_BASE=$(python3 -c "import json; d=json.load(open('$MARKER5')); print(d['base_branch'])")

# query --key=base_branch 결과
QUERY_OUT=$(
  cd "$TMPDIR5"
  "$SCRIPT" query --key=base_branch 2>/dev/null
)

[ "$QUERY_OUT" = "$EXPECTED_BASE" ] || fail "TC5: query --key=base_branch 결과 불일치. 기대='$EXPECTED_BASE', 실제='$QUERY_OUT'"
echo "  TC5 OK"
trap - EXIT
cleanup_tmp "$TMPDIR5"

# ─────────────────────────────────────────
# TC6: clear → "cleared" + 다시 clear → "no marker"
# ─────────────────────────────────────────
step 6 "clear → cleared. 재호출 → no marker"
TMPDIR6="$(setup_tmp_repo)"
trap 'cleanup_tmp "$TMPDIR6"' EXIT

(
  cd "$TMPDIR6"
  "$SCRIPT" start --quiet 2>/dev/null || true
)

MARKER6="$TMPDIR6/.git/plan-dev-session.json"
[ -f "$MARKER6" ] || fail "TC6: marker 없음"

OUT6a=$(
  cd "$TMPDIR6"
  "$SCRIPT" clear
)
echo "$OUT6a" | grep -q "cleared" || fail "TC6: clear 출력에 'cleared' 없음. 출력: $OUT6a"
[ ! -f "$MARKER6" ] || fail "TC6: clear 후에도 marker 남아있음"

OUT6b=$(
  cd "$TMPDIR6"
  "$SCRIPT" clear
)
echo "$OUT6b" | grep -q "no marker" || fail "TC6: 두 번째 clear 에 'no marker' 없음. 출력: $OUT6b"
echo "  TC6 OK"
trap - EXIT
cleanup_tmp "$TMPDIR6"

# ─────────────────────────────────────────
# TC7: worktree 격리 — 양쪽 worktree 에서 같은 marker
# ─────────────────────────────────────────
step 7 "worktree 격리: 양쪽 worktree 가 같은 marker 공유"
TMPDIR7="$(setup_tmp_repo)"
trap 'cleanup_tmp "$TMPDIR7"; rm -rf "${TMPDIR7}_wt2"' EXIT

WT2="${TMPDIR7}_wt2"
git -C "$TMPDIR7" worktree add "$WT2" -b feature/x -q 2>/dev/null

# 메인 worktree 에서 start
(
  cd "$TMPDIR7"
  "$SCRIPT" start --quiet 2>/dev/null || true
)

MARKER7="$TMPDIR7/.git/plan-dev-session.json"
[ -f "$MARKER7" ] || fail "TC7: 메인 worktree marker 없음"

# 다른 worktree 에서 query
QUERY_WB=$(
  cd "$WT2"
  "$SCRIPT" query --key=work_branch 2>/dev/null
)

# work_branch 는 메인 worktree 의 branch 여야 함 (main 또는 master)
[ -n "$QUERY_WB" ] || fail "TC7: 다른 worktree 에서 query 결과 비어있음"

# 두 worktree 에서 같은 JSON 이 보여야 함
JSON_FROM_MAIN=$(
  cd "$TMPDIR7"
  "$SCRIPT" query --json 2>/dev/null
)
JSON_FROM_WT2=$(
  cd "$WT2"
  "$SCRIPT" query --json 2>/dev/null
)
[ "$JSON_FROM_MAIN" = "$JSON_FROM_WT2" ] || fail "TC7: 두 worktree 에서 다른 JSON. main='$JSON_FROM_MAIN', wt2='$JSON_FROM_WT2'"
echo "  TC7 OK"
trap - EXIT
cleanup_tmp "$TMPDIR7"
rm -rf "${TMPDIR7}_wt2" 2>/dev/null || true

# ─────────────────────────────────────────
# TC8: 브랜치명에 홑따옴표 포함 → marker 정상 기록 (S3 R1)
# ─────────────────────────────────────────
step 8 "브랜치명에 홑따옴표 포함 → marker 정상 기록"
TMPDIR8="$(setup_tmp_repo)"
trap 'cleanup_tmp "$TMPDIR8"' EXIT

git -C "$TMPDIR8" checkout -b "feat/it's-fine" -q

(
  cd "$TMPDIR8"
  "$SCRIPT" start --quiet 2>/dev/null || true
)

MARKER8="$TMPDIR8/.git/plan-dev-session.json"
[ -f "$MARKER8" ] || fail "TC8: marker 파일 없음"

WORK_BRANCH=$(python3 -c "import json; print(json.load(open('$MARKER8'))['work_branch'])") \
  || fail "TC8: marker JSON 파싱 실패 (SyntaxError 가능성)"
[ "$WORK_BRANCH" = "feat/it's-fine" ] || fail "TC8: work_branch 불일치. 실제='$WORK_BRANCH'"
echo "  TC8 OK"
trap - EXIT
cleanup_tmp "$TMPDIR8"

# ─────────────────────────────────────────
# TC9: python3 강제 실패 → exit 2 + .bak 원복 (S3 R1)
# ─────────────────────────────────────────
step 9 "python3 강제 실패 → exit 2 + .bak 원복"
TMPDIR9="$(setup_tmp_repo)"
trap 'cleanup_tmp "$TMPDIR9"' EXIT

(
  cd "$TMPDIR9"
  "$SCRIPT" start --quiet 2>/dev/null || true
)

MARKER9="$TMPDIR9/.git/plan-dev-session.json"
[ -f "$MARKER9" ] || fail "TC9: 첫 start 후 marker 없음"

# stale 하게 만들어 재진입(→ mv .bak) 유도
python3 -c "
import json
from datetime import datetime, timezone, timedelta
f = '$MARKER9'
d = json.load(open(f))
d['start_pid'] = 9999999
d['start_ts'] = (datetime.now(timezone.utc) - timedelta(hours=25)).strftime('%Y-%m-%dT%H:%M:%SZ')
open(f, 'w').write(json.dumps(d))
"
ORIG_CONTENT=$(cat "$MARKER9")

# python3 를 강제로 실패시키는 fake bin 준비 (PATH 최우선)
FAKEBIN="$(mktemp -d)"
cat > "$FAKEBIN/python3" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$FAKEBIN/python3"

set +e
STDERR9=$(
  cd "$TMPDIR9"
  PATH="$FAKEBIN:$PATH" "$SCRIPT" start 2>&1
)
RC9=$?
set -e
rm -rf "$FAKEBIN"

[ "$RC9" = "2" ] || fail "TC9: exit 2 기대, 실제 $RC9. 출력: $STDERR9"
[ -f "$MARKER9" ] || fail "TC9: 원복된 marker 없음"
[ ! -f "${MARKER9}.bak" ] || fail "TC9: .bak 이 원복 후에도 남아있음"

RESTORED_CONTENT=$(cat "$MARKER9")
[ "$RESTORED_CONTENT" = "$ORIG_CONTENT" ] || fail "TC9: 원복된 marker 내용 불일치"
echo "  TC9 OK"
trap - EXIT
cleanup_tmp "$TMPDIR9"

echo ""
echo "PASS"
