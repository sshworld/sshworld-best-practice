#!/usr/bin/env bash
# Slice C mock e2e — /parallel-consult 가 의존하는 wrapper 호출 시퀀스를 mock pane 으로 검증.
# tmux + scripts/tmux-pane.sh 둘 다 있어야 PASS. 없으면 SKIP exit 0.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WRAPPER="$REPO/scripts/tmux-pane.sh"

step() { echo ""; echo "[$1] $2"; }
fail() { echo "❌ FAIL: $1" >&2; exit 1; }

if ! command -v tmux > /dev/null 2>&1; then
  echo "SKIP: tmux not installed"
  exit 0
fi
if [ ! -x "$WRAPPER" ]; then
  echo "SKIP: $WRAPPER not present (Slice A 머지 전)"
  exit 0
fi

unset TMUX

MOCK=$(mktemp)
cat > "$MOCK" <<'EOF'
#!/usr/bin/env bash
printf "mock-child-claude> "
while IFS= read -r line; do
  printf "MOCK_REPLY:%s\nmock-child-claude> " "$line"
done
EOF
chmod +x "$MOCK"

cleanup() {
  [ -n "${PANE:-}" ] && "$WRAPPER" kill --pane="$PANE" 2>/dev/null || true
  rm -f "$MOCK"
}
trap cleanup EXIT

step 1 "launch mock as child"
PANE=$("$WRAPPER" launch "bash $MOCK") || fail "launch failed"
echo "  pane=$PANE"

step 2 "wait-idle for prompt"
"$WRAPPER" wait-idle --pane="$PANE" --idle=1 --timeout=10 || fail "wait-idle failed"

step 3 "send question"
"$WRAPPER" send "안녕 mock" --pane="$PANE" --delay=0.3 || fail "send failed"

step 4 "wait-idle for reply"
"$WRAPPER" wait-idle --pane="$PANE" --idle=1 --timeout=10 || fail "wait-idle 2 failed"

step 5 "capture contains MOCK_REPLY"
OUT=$("$WRAPPER" capture --pane="$PANE") || fail "capture failed"
echo "$OUT" | grep -q "MOCK_REPLY:안녕 mock" || fail "reply marker missing in: $OUT"

echo ""
echo "OK"
