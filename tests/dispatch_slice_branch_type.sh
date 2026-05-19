#!/usr/bin/env bash
# Slice 3 — dispatch-slice-pane.sh --type flag + <type>/<slug> branch 이름 생성 검증.
# DISPATCH_DRY_RUN=1 로 실제 launch 없이 branch 키 값만 검증.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DISPATCH="$REPO/scripts/dispatch-slice-pane.sh"

step() { echo ""; echo "[$1] $2"; }
fail() { echo "FAIL: $1" >&2; exit 1; }

[ -f "$DISPATCH" ] || fail "dispatcher missing: $DISPATCH"

tmpdir=$(mktemp -d)
cleanup() { rm -rf "$tmpdir"; }
trap cleanup EXIT

# 더미 spec 파일 (DRY_RUN 에서는 파일 존재 검사 skip 이지만 있으면 더 안전)
echo "dummy spec" > "$tmpdir/spec.md"

# JSON 에서 branch 값 추출 헬퍼
branch_of() {
  python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d['branch'])"
}

step A "--type 생략 (기본 feat) + DRY_RUN → feat/<slug>"
OUT=$(DISPATCH_DRY_RUN=1 DISPATCH_SKIP_CLEANUP=1 \
  bash "$DISPATCH" \
    --slice=detect-pane-env \
    --spec-file="$tmpdir/spec.md" \
    --mode=tmux 2>/dev/null) || fail "case A: exit non-zero"
BR=$(echo "$OUT" | branch_of) || fail "case A: JSON 파싱 실패: $OUT"
[ "$BR" = "feat/detect-pane-env" ] || fail "case A: branch mismatch: got '$BR', want 'feat/detect-pane-env'"
echo "  branch=$BR OK"

step B "--type=test + DRY_RUN → test/<slug>"
OUT=$(DISPATCH_DRY_RUN=1 DISPATCH_SKIP_CLEANUP=1 \
  bash "$DISPATCH" \
    --slice=session-marker \
    --type=test \
    --spec-file="$tmpdir/spec.md" \
    --mode=tmux 2>/dev/null) || fail "case B: exit non-zero"
BR=$(echo "$OUT" | branch_of) || fail "case B: JSON 파싱 실패: $OUT"
[ "$BR" = "test/session-marker" ] || fail "case B: branch mismatch: got '$BR', want 'test/session-marker'"
echo "  branch=$BR OK"

step C "--type=refactor + DRY_RUN → refactor/<slug>"
OUT=$(DISPATCH_DRY_RUN=1 DISPATCH_SKIP_CLEANUP=1 \
  bash "$DISPATCH" \
    --type=refactor \
    --slice=cleanup \
    --spec-file="$tmpdir/spec.md" \
    --mode=tmux 2>/dev/null) || fail "case C: exit non-zero"
BR=$(echo "$OUT" | branch_of) || fail "case C: JSON 파싱 실패: $OUT"
[ "$BR" = "refactor/cleanup" ] || fail "case C: branch mismatch: got '$BR', want 'refactor/cleanup'"
echo "  branch=$BR OK"

step D "--type=invalid → exit 2"
ERR_OUT=$(DISPATCH_DRY_RUN=1 DISPATCH_SKIP_CLEANUP=1 \
  bash "$DISPATCH" \
    --slice=some-slice \
    --type=invalid \
    --spec-file="$tmpdir/spec.md" \
    --mode=tmux 2>&1) && fail "case D: should have exited non-zero" || EC=$?
[ "${EC:-0}" -eq 2 ] || fail "case D: expected exit 2, got ${EC:-0}"
echo "$ERR_OUT" | grep -q "허용되지 않는 type" || fail "case D: expected '허용되지 않는 type' in stderr: $ERR_OUT"
echo "  exit=${EC:-0}, msg contains '허용되지 않는 type' OK"
unset EC

step E "DISPATCH_DEFAULT_TYPE=fix + DRY_RUN → fix/<slug>"
OUT=$(DISPATCH_DRY_RUN=1 DISPATCH_SKIP_CLEANUP=1 \
  DISPATCH_DEFAULT_TYPE=fix \
  bash "$DISPATCH" \
    --slice=bug-x \
    --spec-file="$tmpdir/spec.md" \
    --mode=tmux 2>/dev/null) || fail "case E: exit non-zero"
BR=$(echo "$OUT" | branch_of) || fail "case E: JSON 파싱 실패: $OUT"
[ "$BR" = "fix/bug-x" ] || fail "case E: branch mismatch: got '$BR', want 'fix/bug-x'"
echo "  branch=$BR OK"

step F "--type=fix 는 DISPATCH_DEFAULT_TYPE 보다 우선"
OUT=$(DISPATCH_DRY_RUN=1 DISPATCH_SKIP_CLEANUP=1 \
  DISPATCH_DEFAULT_TYPE=chore \
  bash "$DISPATCH" \
    --slice=my-slice \
    --type=fix \
    --spec-file="$tmpdir/spec.md" \
    --mode=tmux 2>/dev/null) || fail "case F: exit non-zero"
BR=$(echo "$OUT" | branch_of) || fail "case F: JSON 파싱 실패: $OUT"
[ "$BR" = "fix/my-slice" ] || fail "case F: branch mismatch: got '$BR', want 'fix/my-slice'"
echo "  branch=$BR OK"

step G "--slice 빈 문자열 → exit 2"
DISPATCH_DRY_RUN=1 bash "$DISPATCH" \
  --slice="" \
  --spec-file="$tmpdir/spec.md" \
  --mode=tmux 2>/dev/null && fail "case G: should have exited non-zero" || ECG=$?
[ "${ECG:-0}" -ne 0 ] || fail "case G: expected non-zero exit, got 0"
echo "  exit=${ECG:-0} OK"
unset ECG

step H "--slice 슬래시 포함 → exit 2"
DISPATCH_DRY_RUN=1 bash "$DISPATCH" \
  --slice="foo/bar" \
  --spec-file="$tmpdir/spec.md" \
  --mode=tmux 2>/dev/null && fail "case H: should have exited non-zero" || ECH=$?
[ "${ECH:-0}" -eq 2 ] || fail "case H: expected exit 2, got ${ECH:-0}"
echo "  exit=${ECH:-0} OK"
unset ECH

echo ""
echo "OK"
