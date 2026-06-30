#!/usr/bin/env bash
# Slice 2 — cmux dispatch 의 자식 회수 (wait-idle + capture) e2e 안정성 검증.
# mock cmux 로 read-screen 응답 고정 → wait-idle idle 도달 + capture lenient 패턴(⏺/들여쓰기 prefix 허용).

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WRAPPER="$REPO/scripts/cmux-pane.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
step() { echo; echo "[$1] $2"; }

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

# Mock cmux — read-screen 응답 고정 (✅ 라인 포함).
cat > "$tmpdir/cmux-mock" <<'EOF'
#!/bin/bash
case "$1" in
  read-screen) echo "⏺ ✅ test-slice: completed (mock cmux)" ;;
  send|send-key) ;;
  identify)     echo "workspace:1" ;;
  ping)         echo "PONG" ;;
  *)            ;;
esac
exit 0
EOF
chmod +x "$tmpdir/cmux-mock"
export CMUX_BIN="$tmpdir/cmux-mock"

step 1 "wait-idle 가 mock 환경에서 idle 도달 (idle=1 timeout=10)"
start=$(date +%s)
"$WRAPPER" wait-idle --pane=workspace:1 --idle=1 --timeout=10
ec=$?
end=$(date +%s)
[ "$ec" = 0 ] || fail "wait-idle exit=$ec"
elapsed=$((end - start))
[ "$elapsed" -le 5 ] || fail "wait-idle 가 너무 느림: ${elapsed}s (5s 이내)"
echo "  elapsed=${elapsed}s, exit=0 OK"

step 2 "capture 가 ✅ 라인 포함 (⏺ prefix 허용)"
out=$("$WRAPPER" capture --pane=workspace:1 --lines=10) || fail "capture 실패"
echo "$out" | grep -qE '^[[:space:]]*(⏺[[:space:]]*)?(✅|❌)' || fail "no ✅ in capture: $out"
echo "  '$out' 의 ✅ grep OK"

step 3 "wait-idle → capture | lenient grep 회수 패턴 e2e"
"$WRAPPER" wait-idle --pane=workspace:1 --idle=1 --timeout=10 || fail "wait-idle (case 3)"
out=$("$WRAPPER" capture --pane=workspace:1 | tail -50 | grep -E '^[[:space:]]*(⏺[[:space:]]*)?(✅|❌)' || true)
[ -n "$out" ] || fail "회수 패턴 실패: 빈 stdout"
echo "$out" | grep -qE '^[[:space:]]*(⏺[[:space:]]*)?(✅|❌)' || fail "회수 패턴: ✅ 미포함: $out"
echo "  회수 라인: $out"

step 4 "surface:N ref 도 동일 회수 가능"
out=$("$WRAPPER" capture --pane=surface:7 --lines=10) || fail "capture surface 실패"
echo "$out" | grep -qE '^[[:space:]]*(⏺[[:space:]]*)?(✅|❌)' || fail "surface capture 결과에 ✅ 없음"
echo "  surface capture OK"

step 5 "reap (정규 경로) 가 ⏺-prefixed 마커 감지 (dry-run)"
out=$(CBP_REAP_DRY_RUN=1 "$WRAPPER" reap --pane=workspace:1 --idle=1 --timeout=10 2>/dev/null)
echo "$out" | grep -q "would reap" || fail "reap 가 ⏺ ✅ 마커 미감지: $out"
echo "  reap 감지 OK"

step 6 "send 가 (mock) 정상 호출되는지 — error 없이 종료"
"$WRAPPER" send "hello implementor" --pane=workspace:1 --enter=false || fail "send 실패"
echo "  send OK"

# (선택) 실 cmux e2e — CMUX_E2E=1 일 때만, cmux 환경 안에서 부수효과 발생.
if [ "${CMUX_E2E:-0}" = "1" ] && [ -n "${CMUX_WORKSPACE_ID:-}" ]; then
  step 7 "[CMUX_E2E=1] 실 cmux — workspace 안 split + capture (사용자 화면에 surface 1개 추가됨)"
  unset CMUX_BIN
  # 가벼운 자식 cmd: echo + sleep — mock 아닌 실 cmux 명령.
  if ref=$("$WRAPPER" launch "echo '✅ real-cmux-e2e: ok'; sleep 30" --name=cmux-e2e-test 2>&1); then
    echo "  launched: $ref"
    sleep 3
    out=$("$WRAPPER" capture --pane="$ref" --lines=20 2>/dev/null || true)
    echo "$out" | grep -q "real-cmux-e2e" && echo "  capture OK" || echo "  WARN: capture 에 신호 없음 (자식이 아직 출력 안 했을 수 있음)"
    "$WRAPPER" kill --pane="$ref" 2>/dev/null || true
  else
    echo "  WARN: launch 실패 — $ref"
  fi
fi

echo
echo "PASS"
