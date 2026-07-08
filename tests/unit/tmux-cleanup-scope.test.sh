#!/usr/bin/env bash
# tmux-cleanup-scope.test.sh — tmux-pane.sh do_cleanup() 의 (2)번 블록 스코프 단위 테스트.
#
# 배경: 구 버전은 `tmux list-panes -a ... | head -1` 로 서버 전체의 첫 active pane 을 잡아
# 그 pane 이 속한 window 의 모든 pane 을 죽였음 — 사용자가 다른 세션에서 dispatch 하면
# 엉뚱한 window 의 수동 pane 을 몰살하는 결함.
#
# 검증: $TMUX_PANE 기준 self window 스코프로 축소 + @cbp_child=1 태깅된 pane 만 kill.
#
# ⚠️ 실 tmux 서버 상대로 실행 금지 — 전체를 fake tmux(PATH mock) 로 대체, 실제 tmux 미필요.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WRAPPER="$REPO/scripts/tmux-pane.sh"

pass=0
fail_count=0

check_contains() {
  local desc="$1" expected="$2" actual="$3"
  if printf '%s' "$actual" | grep -qF -- "$expected"; then
    echo "ok: $desc"
    pass=$((pass + 1))
  else
    echo "FAIL: $desc — expected substring='$expected' in output='$actual'" >&2
    fail_count=$((fail_count + 1))
  fi
}

check_not_contains() {
  local desc="$1" not_expected="$2" actual="$3"
  if printf '%s' "$actual" | grep -qF -- "$not_expected"; then
    echo "FAIL: $desc — unexpected substring='$not_expected' found in output='$actual'" >&2
    fail_count=$((fail_count + 1))
  else
    echo "ok: $desc"
    pass=$((pass + 1))
  fi
}

FAKE_DIR=$(mktemp -d)
STATE="$FAKE_DIR/panes.txt"
TRACE="$FAKE_DIR/trace.txt"

# fake tmux — pane DB 는 "<pane_id> <session:window.idx> <@cbp_child tag>" 형식의
# 텍스트 파일. do_cleanup 이 실제로 부르는 subcommand 만 구현 (has-session, list-panes,
# display-message, kill-pane, kill-session). 그 외는 no-op.
cat > "$FAKE_DIR/tmux" <<EOF
#!/usr/bin/env bash
echo "ARGS: \$*" >> "$TRACE"
STATE="$STATE"

case "\$1" in
  has-session)
    # has-session -t <name> — 이 테스트에선 mgr 세션 항상 부재
    exit 1
    ;;
  display-message)
    shift
    target=""
    while [ \$# -gt 0 ]; do
      case "\$1" in
        -t) target="\$2"; shift 2 ;;
        -p) shift ;;
        *)  shift ;;
      esac
    done
    win=\$(awk -v p="\$target" '\$1==p{print \$2}' "\$STATE" | sed -E 's/\.[0-9]+\$//')
    [ -z "\$win" ] && exit 1
    echo "\$win"
    ;;
  list-panes)
    shift
    target=""
    while [ \$# -gt 0 ]; do
      case "\$1" in
        -t) target="\$2"; shift 2 ;;
        -F) shift 2 ;;
        -s|-a) shift ;;
        *)  shift ;;
      esac
    done
    awk -v w="\$target" '{n=split(\$2,a,"."); win=a[1]; for(i=2;i<n;i++) win=win"."a[i]; if (win==w) print \$1, \$3}' "\$STATE"
    ;;
  kill-pane)
    target="\$3"
    grep -v "^\$target " "\$STATE" > "\$STATE.tmp" 2>/dev/null || true
    mv "\$STATE.tmp" "\$STATE"
    exit 0
    ;;
  kill-session)
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
EOF
chmod +x "$FAKE_DIR/tmux"

trap 'rm -rf "$FAKE_DIR"' EXIT

reset_state() {
  cat > "$STATE" <<'PANES'
%1 sess:0.0 0
%2 sess:0.1 1
%3 sess:0.2 0
%4 sess:1.0 1
PANES
  : > "$TRACE"
}

# ── 시나리오 1: $TMUX_PANE unset → (2) 블록 전체 skip ──
reset_state
unset TMUX_PANE
OUT=$(PATH="$FAKE_DIR:$PATH" "$WRAPPER" cleanup 2>&1)
check_contains "unset TMUX_PANE: cleaning 0 보고" "cleaning 0 child pane" "$OUT"
AFTER=$(cat "$STATE")
check_contains "unset TMUX_PANE: pane DB 불변 (%2 그대로 존재)" "%2 sess:0.1 1" "$AFTER"
check_not_contains "unset TMUX_PANE: list-panes -t 호출 안 함" "list-panes -t sess:0" "$(cat "$TRACE")"

# ── 시나리오 2: $TMUX_PANE=%1 (self, window sess:0) ──
# 기대: sess:0 의 @cbp_child=1 pane(%2) 만 kill.
# %3(같은 window, untagged) 보존. %4(다른 window sess:1, tagged) 보존 — 스코프 검증 핵심.
reset_state
export TMUX_PANE="%1"
OUT=$(PATH="$FAKE_DIR:$PATH" "$WRAPPER" cleanup 2>&1)
unset TMUX_PANE
FINAL_STATE=$(cat "$STATE")

check_contains "set TMUX_PANE: self window(sess:0) 만 조회" "list-panes -t sess:0" "$(cat "$TRACE")"
check_not_contains "set TMUX_PANE: 다른 window(sess:1) 는 조회 안 함" "list-panes -t sess:1" "$(cat "$TRACE")"
check_not_contains "set TMUX_PANE: 태깅된 %2 kill 됨 (DB 에서 제거)" "%2 sess:0.1 1" "$FINAL_STATE"
check_contains "set TMUX_PANE: 미태깅 %3 보존" "%3 sess:0.2 0" "$FINAL_STATE"
check_contains "set TMUX_PANE: self %1 보존" "%1 sess:0.0 0" "$FINAL_STATE"
check_contains "set TMUX_PANE: 다른 window 의 태깅 %4 보존 (스코프 밖)" "%4 sess:1.0 1" "$FINAL_STATE"
check_contains "set TMUX_PANE: cleaning 1 보고" "cleaning 1 child pane" "$OUT"

echo ""
echo "pass=$pass fail=$fail_count"
if [ "$fail_count" -gt 0 ]; then
  echo "❌ FAIL"
  exit 1
fi
echo "OK"
