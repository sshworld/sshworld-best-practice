#!/usr/bin/env bash
# trust-dir.test.sh — scripts/trust-dir.sh 단위 테스트
# CBP_CLAUDE_CONFIG 로 실제 ~/.claude.json 안 건드리고 격리 검증.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TRUST="$REPO/scripts/trust-dir.sh"

pass=0; fail_count=0; FAILED=()

ok()       { echo "ok: $1"; pass=$((pass+1)); }
fail_test(){ echo "FAIL: $1" >&2; fail_count=$((fail_count+1)); FAILED+=("$1"); }

[ -f "$TRUST" ] || { echo "FAIL: $TRUST 없음" >&2; exit 1; }
[ -x "$TRUST" ] || { echo "FAIL: $TRUST 실행 권한 없음" >&2; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# ── (a) 기존 json + 새 경로 trust 시딩 ───────────────────────────
cfg_a="$TMP/claude_a.json"
cat > "$cfg_a" <<'JSON'
{"hasCompletedOnboarding": true, "projects": {"/other/path": {"hasTrustDialogAccepted": true}}}
JSON

out_a=$(CBP_CLAUDE_CONFIG="$cfg_a" "$TRUST" "/tmp/foo/wt" 2>/dev/null)
rc_a=$?

if [ "$rc_a" -eq 0 ] && \
   [ "$(jq -r '.projects["/tmp/foo/wt"].hasTrustDialogAccepted' "$cfg_a")" = "true" ] && \
   [ "$(jq -r '.hasCompletedOnboarding' "$cfg_a")" = "true" ]; then
  ok "(a) 새 경로 trust 시딩 + hasCompletedOnboarding=true"
else
  fail_test "(a) 새 경로 trust 시딩 (rc=$rc_a)"
fi

# ── (b) 기존 프로젝트 키 보존 ────────────────────────────────────
if [ "$(jq -r '.projects["/other/path"].hasTrustDialogAccepted' "$cfg_a")" = "true" ]; then
  ok "(b) 기존 프로젝트 키 보존"
else
  fail_test "(b) 기존 프로젝트 키 보존"
fi

# ── (c) idempotent: 2회 실행 → 결과 동일, valid json ─────────────
cfg_c="$TMP/claude_c.json"
cp "$cfg_a" "$cfg_c"
CBP_CLAUDE_CONFIG="$cfg_c" "$TRUST" "/tmp/foo/wt" >/dev/null 2>&1 || true
CBP_CLAUDE_CONFIG="$cfg_c" "$TRUST" "/tmp/foo/wt" >/dev/null 2>&1 || true
rc_c=$?

if jq empty "$cfg_c" 2>/dev/null && \
   [ "$(jq -r '.projects["/tmp/foo/wt"].hasTrustDialogAccepted' "$cfg_c")" = "true" ]; then
  ok "(c) idempotent — 2회 실행 후 valid json + trust 유지"
else
  fail_test "(c) idempotent"
fi

# ── (d) config 파일 부재 → 생성 + valid json + 키 set ───────────
mkdir -p "$TMP/newdir"
cfg_d="$TMP/newdir/claude_d.json"

CBP_CLAUDE_CONFIG="$cfg_d" "$TRUST" "/tmp/newdir" >/dev/null 2>&1
rc_d=$?

if [ "$rc_d" -eq 0 ] && \
   [ -f "$cfg_d" ] && \
   jq empty "$cfg_d" 2>/dev/null && \
   [ "$(jq -r '.projects["/tmp/newdir"].hasTrustDialogAccepted' "$cfg_d")" = "true" ] && \
   [ "$(jq -r '.hasCompletedOnboarding' "$cfg_d")" = "true" ]; then
  ok "(d) config 부재 시 생성 + valid json"
else
  fail_test "(d) config 부재 시 생성 (rc=$rc_d, file=$([ -f "$cfg_d" ] && echo exists || echo missing))"
fi

# ── (e) _TRUST_DIR_NO_JQ=1 → exit 0 + stderr 경고 + config 파괴 안 함 ──
cfg_e="$TMP/claude_e.json"
echo '{"hasCompletedOnboarding":true,"projects":{}}' > "$cfg_e"
BEFORE=$(cat "$cfg_e")

stderr_e=$(CBP_CLAUDE_CONFIG="$cfg_e" _TRUST_DIR_NO_JQ=1 "$TRUST" "/tmp/any" 2>&1 >/dev/null || true)
rc_e=$?
AFTER=$(cat "$cfg_e" 2>/dev/null || echo "MISSING")

if [ "$rc_e" -eq 0 ] && \
   [ "$BEFORE" = "$AFTER" ] && \
   echo "$stderr_e" | grep -qi "jq"; then
  ok "(e) jq 없음 → exit 0 + stderr 경고 + config 파괴 안 함"
else
  fail_test "(e) jq 없음 처리 (rc=$rc_e, changed=$([ "$BEFORE" = "$AFTER" ] && echo no || echo yes), stderr='$stderr_e')"
fi

echo ""
echo "ok: $pass/5 passed"
[ "${#FAILED[@]}" -gt 0 ] && printf 'FAILED: %s\n' "${FAILED[@]}" >&2 && exit 1
exit 0
