#!/usr/bin/env bash
# plan_dev_session_startts_preserve.sh — dead pid + within_24h 재진입 시 start_ts/start_ref 보존 검증.
# TDD Red: 먼저 작성 후 scripts/plan-dev-session.sh 수정으로 Green.

set -uo pipefail

# ⚠️ 이 스위트는 plan-dev-session.sh start 를 실제 실행한다. start 는 cmux 환경
# (CMUX_WORKSPACE_ID set)이면 best-effort 로 실제 `cmux-pane.sh reap-orphans` 를
# 호출한다 — 전 workspace 의 자식 state 를 훑어 dead 판정 surface 를 닫는다.
# plan-dev 세션 중 이 테스트를 돌리면 살아있는 자식 surface 가 회수될 수 있다.
export SKIP_CMUX_REAP=1

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO/scripts/plan-dev-session.sh"

step() { echo "[$1] $2"; }
fail() { echo "FAIL: $1" >&2; exit 1; }

[ -x "$SCRIPT" ] || fail "script not executable or missing: $SCRIPT"

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

# ─────────────────────────────────────────
# TC-P1: dead pid + within_24h → start_ts/start_ref 보존
# ─────────────────────────────────────────
step P1 "dead pid + within_24h → start_ts 보존"
TMPDIR1="$(setup_tmp_repo)"
trap 'cleanup_tmp "$TMPDIR1"' EXIT

(
  cd "$TMPDIR1"
  "$SCRIPT" start --quiet 2>/dev/null || true
)

MARKER1="$TMPDIR1/.git/plan-dev-session.json"
[ -f "$MARKER1" ] || fail "TC-P1: 첫 start 후 marker 없음"

# start_pid 를 절대 죽어있는 PID 로 교체 (recent ts 유지)
python3 -c "
import json
f = '$MARKER1'
d = json.load(open(f))
d['start_pid'] = 9999999
open(f, 'w').write(json.dumps(d, indent=2) + '\n')
"

# TS1, REF1 읽기
TS1=$(
  cd "$TMPDIR1"
  "$SCRIPT" query --key=start_ts 2>/dev/null
)
REF1=$(
  cd "$TMPDIR1"
  "$SCRIPT" query --key=start_ref 2>/dev/null
)
[ -n "$TS1" ] || fail "TC-P1: TS1 빈값"
[ -n "$REF1" ] || fail "TC-P1: REF1 빈값"

# dead pid 지만 within_24h → 재진입 → start_ts/start_ref 보존 확인
sleep 1

(
  cd "$TMPDIR1"
  "$SCRIPT" start --quiet 2>/dev/null || true
)

TS2=$(
  cd "$TMPDIR1"
  "$SCRIPT" query --key=start_ts 2>/dev/null
)
REF2=$(
  cd "$TMPDIR1"
  "$SCRIPT" query --key=start_ref 2>/dev/null
)

[ "$TS1" = "$TS2" ] || fail "TC-P1: start_ts 변경됨 (clobbered). TS1='$TS1', TS2='$TS2'"
[ "$REF1" = "$REF2" ] || fail "TC-P1: start_ref 변경됨. REF1='$REF1', REF2='$REF2'"
echo "  TC-P1 OK"
trap - EXIT
cleanup_tmp "$TMPDIR1"

# ─────────────────────────────────────────
# TC-P2: dead pid + stale (25h) → start_ts 갱신 (보존 안 됨)
# ─────────────────────────────────────────
step P2 "dead pid + stale 25h → start_ts 갱신 (보존 안 됨)"
TMPDIR2="$(setup_tmp_repo)"
trap 'cleanup_tmp "$TMPDIR2"' EXIT

(
  cd "$TMPDIR2"
  "$SCRIPT" start --quiet 2>/dev/null || true
)

MARKER2="$TMPDIR2/.git/plan-dev-session.json"
[ -f "$MARKER2" ] || fail "TC-P2: 첫 start 후 marker 없음"

# start_ts 를 25시간 전, pid = dead 로 변경
python3 -c "
import json
from datetime import datetime, timezone, timedelta
f = '$MARKER2'
d = json.load(open(f))
old_ts = (datetime.now(timezone.utc) - timedelta(hours=25)).strftime('%Y-%m-%dT%H:%M:%SZ')
d['start_ts'] = old_ts
d['start_pid'] = 9999999
open(f, 'w').write(json.dumps(d, indent=2) + '\n')
"

STALE_TS=$(
  cd "$TMPDIR2"
  "$SCRIPT" query --key=start_ts 2>/dev/null
)

sleep 1

(
  cd "$TMPDIR2"
  "$SCRIPT" start --quiet 2>/dev/null || true
)

TS2b=$(
  cd "$TMPDIR2"
  "$SCRIPT" query --key=start_ts 2>/dev/null
)
[ -f "${MARKER2}.bak" ] || fail "TC-P2: .bak 파일 없음 (stale → fresh 재시작 기대)"
[ "$STALE_TS" != "$TS2b" ] || fail "TC-P2: stale start_ts 가 보존됨 (갱신 기대)"
echo "  TC-P2 OK"
trap - EXIT
cleanup_tmp "$TMPDIR2"

echo ""
echo "OK"
