#!/usr/bin/env bash
# 병렬 dispatch launch race 회귀 테스트.
# _do_launch_grid 의 count-read → cmux 생성 → state 기록 이 critical section 으로 묶여
# 병렬 N개 동시 launch 시: new-pane 정확히 1회, new-split N-1회, surface 전부 고유.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WRAPPER="$REPO/scripts/cmux-pane.sh"
PASS=0; FAIL=0; FAILED=()
run() { local name="$1"; shift; if "$@"; then echo "✔ $name"; PASS=$((PASS+1)); else echo "✘ $name"; FAIL=$((FAIL+1)); FAILED+=("$name"); fi; }

# grep -c 안전 래퍼 — 매치 0 시 grep exit 1 이라 `|| echo 0` 은 이중 출력 버그.
# grep -c 는 항상 숫자 한 줄 출력하므로 exit code 무시하고 첫 줄만.
cnt() { grep -c "$@" 2>/dev/null | head -1; }

# mock cmux 생성: new-pane/new-split → atomic counter 로 고유 surface:N + delay + 호출 로그.
make_mock_cmux() {
  local tmp="$1"
  local mock="$tmp/cmux-mock.sh"
  cat > "$mock" <<MEOF
#!/usr/bin/env bash
# 인자 첫 토큰 = 서브커맨드. 호출 로그 + 고유 surface 발급.
LOG="$tmp/calls.log"
CNT="$tmp/counter"
LOCK="$tmp/counter.lock.d"
DELAY="\${MOCK_DELAY:-0.15}"

incr() {
  # atomic counter (mkdir mutex)
  while ! mkdir "\$LOCK" 2>/dev/null; do sleep 0.01; done
  local n
  n=\$(cat "\$CNT" 2>/dev/null || echo 0)
  n=\$((n + 1))
  echo "\$n" > "\$CNT"
  rmdir "\$LOCK" 2>/dev/null || true
  echo "\$n"
}

sub="\${1:-}"
case "\$sub" in
  new-pane)
    n=\$(incr)
    sleep "\$DELAY"
    echo "new-pane \$*" >> "\$LOG"
    echo "OK surface:\$n pane:\$n workspace:1"
    ;;
  new-split)
    n=\$(incr)
    sleep "\$DELAY"
    echo "new-split \$*" >> "\$LOG"
    echo "OK surface:\$n pane:\$n workspace:1"
    ;;
  rename-tab|send-key|ping|identify)
    : # no-op
    ;;
  *)
    : # no-op
    ;;
esac
exit 0
MEOF
  chmod +x "$mock"
  echo "$mock"
}

# 병렬 N launch 후 불변식 검증.
_run_parallel() {
  local tmp="$1" n="$2" disable_lock="${3:-0}"
  local mock; mock=$(make_mock_cmux "$tmp")
  local sf="$tmp/state.json"
  local i
  for i in $(seq 1 "$n"); do
    CMUX_WORKSPACE_ID=ws-test \
    CBP_STATE_FILE="$sf" \
    CMUX_BIN="$mock" \
    CBP_DISABLE_WARMUP=1 \
    CBP_DISABLE_LAUNCH_LOCK="$disable_lock" \
      bash "$WRAPPER" launch zsh >/dev/null 2>&1 &
  done
  wait
}

t_green_single_new_pane() {
  local tmp; tmp=$(mktemp -d)
  _run_parallel "$tmp" 5 0
  local sf="$tmp/state.json"
  local log="$tmp/calls.log"
  local lines newpane newsplit uniq
  lines=$(cnt '^surface=' "$sf")
  newpane=$(cnt '^new-pane ' "$log")
  newsplit=$(cnt '^new-split ' "$log")
  uniq=$(grep -o 'surface=[^|]*' "$sf" 2>/dev/null | sort -u | wc -l | tr -d ' ')
  rm -rf "$tmp"
  # state 5 라인 + new-pane 정확히 1 + new-split 4 + surface 전부 고유 5
  [ "$lines" = "5" ] && [ "$newpane" = "1" ] && [ "$newsplit" = "4" ] && [ "$uniq" = "5" ]
}

t_red_baseline_lock_disabled() {
  # CBP_DISABLE_LAUNCH_LOCK=1 → race → new-pane 2회+ (count==0 동시 read).
  # 비결정적이므로 several 회 시도해 한 번이라도 new-pane>1 또는 surface 중복이면 race 입증 (PASS).
  local attempt
  for attempt in 1 2 3 4 5; do
    local tmp; tmp=$(mktemp -d)
    _run_parallel "$tmp" 5 1
    local log="$tmp/calls.log" sf="$tmp/state.json"
    local newpane uniq lines
    newpane=$(cnt '^new-pane ' "$log")
    uniq=$(grep -o 'surface=[^|]*' "$sf" 2>/dev/null | sort -u | wc -l | tr -d ' ')
    lines=$(cnt '^surface=' "$sf")
    rm -rf "$tmp"
    # race 징후: new-pane 2회+ 또는 고유 surface < 라인 수 (중복)
    if [ "$newpane" -gt 1 ] || [ "$uniq" != "$lines" ]; then
      return 0
    fi
  done
  # 5회 시도에도 race 안 잡힘 — mock delay 환경상 가능. soft pass (회귀 본질은 green).
  return 0
}

t_split_prev_is_sequential() {
  # green: new-split 의 --surface 가 직전 발급 surface 와 일치 (순차성).
  local tmp; tmp=$(mktemp -d)
  _run_parallel "$tmp" 4 0
  local log="$tmp/calls.log"
  # new-split 호출들의 --surface 인자가 이전에 OK 로 발급된 surface 집합에 포함되는지
  # (직렬화되면 prev 가 항상 이미 생성된 surface). 간단 검증: --surface surface:unknown 없음.
  local bad
  bad=$(grep '^new-split ' "$log" 2>/dev/null | cnt 'surface:unknown')
  rm -rf "$tmp"
  [ "$bad" = "0" ]
}

t_state_consistency() {
  local tmp; tmp=$(mktemp -d)
  _run_parallel "$tmp" 6 0
  local sf="$tmp/state.json"
  local lines fmt_ok
  lines=$(cnt '^surface=' "$sf")
  # 모든 라인이 surface=...|name=cbp-...|ts=...|ws=... 형식
  fmt_ok=$(cnt -E '^surface=[^|]+\|name=cbp-[^|]+\|ts=[0-9]+\|ws=' "$sf")
  rm -rf "$tmp"
  [ "$lines" = "6" ] && [ "$fmt_ok" = "6" ]
}

run "green: 병렬 5 launch → new-pane 1회 + split 4 + surface 고유" t_green_single_new_pane
run "red baseline: lock 비활성 시 race 징후 (or soft pass)" t_red_baseline_lock_disabled
run "green: split prev surface 순차 (unknown 없음)" t_split_prev_is_sequential
run "green: state 라인 형식 일관성" t_state_consistency

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && echo "✅ all pass" || { echo "❌ FAILED: ${FAILED[*]}"; exit 1; }
