#!/usr/bin/env bash
# Slice G — launch 가 in-tmux 시 'split-window -h' + 'select-layout main-vertical'
# 두 명령을 정확히 호출하는지 검증 (mock tmux 로 인자 trace).
# TMUX_PANE_NO_LAYOUT=1 시 select-layout 호출 안 함도 검증.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WRAPPER="$REPO/scripts/tmux-pane.sh"

step() { echo "[$1] $2"; }
fail() { echo "❌ FAIL: $1" >&2; exit 1; }

if ! command -v tmux > /dev/null 2>&1; then
  echo "SKIP: tmux not installed"
  exit 0
fi

REAL_TMUX="$(command -v tmux)"

# fake tmux: 인자를 trace 파일에 append. split-window 는 가짜 pane id 출력.
# 그 외는 실제 tmux 로 패스스루 (display-message 등 wrapper 가 쓰는 명령은 동작해야).
make_fake_tmux() {
  local dir="$1"
  local trace="$2"
  cat > "$dir/tmux" <<EOF
#!/usr/bin/env bash
echo "ARGS: \$*" >> "$trace"
case "\$1" in
  split-window)         echo "fake:1.0" ;;
  select-layout)        : ;;
  *)                    "$REAL_TMUX" "\$@" ;;
esac
EOF
  chmod +x "$dir/tmux"
}

FAKE_DIR=$(mktemp -d)
TRACE="$FAKE_DIR/trace.txt"
make_fake_tmux "$FAKE_DIR" "$TRACE"
trap 'rm -rf "$FAKE_DIR"' EXIT

# TMUX env 를 set → wrapper 가 in-tmux 분기 탐
export TMUX="/tmp/fake-socket,0,0"

step 1 "default launch — split-window -h + select-layout main-vertical 모두 호출"
PATH="$FAKE_DIR:$PATH" "$WRAPPER" launch zsh > /dev/null
grep -q 'ARGS: split-window -P -h' "$TRACE" || { echo "--- trace ---"; cat "$TRACE"; fail "split-window -h 누락"; }
grep -q 'ARGS: select-layout main-vertical' "$TRACE" || { echo "--- trace ---"; cat "$TRACE"; fail "select-layout main-vertical 누락"; }

step 2 "TMUX_PANE_NO_LAYOUT=1 — select-layout 호출 안 함"
> "$TRACE"  # 초기화
TMUX_PANE_NO_LAYOUT=1 PATH="$FAKE_DIR:$PATH" "$WRAPPER" launch zsh > /dev/null
grep -q 'ARGS: split-window -P -h' "$TRACE" || fail "NO_LAYOUT 에서도 split-window -h 는 호출돼야"
if grep -q 'ARGS: select-layout' "$TRACE"; then
  echo "--- trace ---"; cat "$TRACE"
  fail "NO_LAYOUT 인데 select-layout 호출됨"
fi

unset TMUX
echo "OK"
