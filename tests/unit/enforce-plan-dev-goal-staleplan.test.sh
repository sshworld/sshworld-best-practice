#!/usr/bin/env bash
# Unit test: enforce-plan-dev-goal.sh stale-plan fallback 해결 계약.
# marker(SESSION_FILE)보다 새로 수정된 plan 만 평가 대상.
# 옛 동작(`ls -t | head -1`)은 직전 세션 stale plan 을 잘못 평가 → loop.
set -uo pipefail

FAIL=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAIL=1; }

# 해결 로직 = hook fallback 계약 복제 (find -newer marker, count 판정)
# count==1 → 그 plan. count==0 또는 count>=2(모호, 동시 세션) → 빈값.
resolve() {
  local plans_dir="$1" session_file="$2"
  local newer_plans=()
  while IFS= read -r p; do [[ -n "$p" ]] && newer_plans+=("$p"); done < <(
    find "$plans_dir" -maxdepth 1 -name '*.md' -newer "$session_file" 2>/dev/null | sort
  )
  local count=${#newer_plans[@]}
  if [[ "$count" -eq 1 ]]; then
    echo "${newer_plans[0]}"
  fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PLANS="$TMP/plans"; mkdir -p "$PLANS"

# 의도적 far-past sentinel (now>2020 불멸) — relative 화 불필요(비이식 churn)
# stale plan (marker 보다 오래됨)
touch -t 202001010000 "$PLANS/stale.md"
# marker 생성 (중간 시점)
MARKER="$TMP/session.json"; touch -t 202401010000 "$MARKER"

# case 1: newer plan 없음 → 빈값 (stale 평가 안 함)
got=$(resolve "$PLANS" "$MARKER")
[[ -z "$got" ]] && pass "newer plan 없으면 빈값 (stale 제외)" || fail "stale 잘못 해결: '$got'"

# case 2: fresh plan 추가 (marker 보다 새로움) → fresh 해결
sleep 1; : > "$PLANS/fresh.md"   # now > marker(2024)
got=$(resolve "$PLANS" "$MARKER")
[[ "$(basename "$got")" == "fresh.md" ]] && pass "fresh plan 해결" || fail "fresh 해결 실패: '$got'"

# case 3: marker 보다 새로운 plan 2개(동시 세션 모호) → 빈값(게이팅 skip), 특정 plan 아님
sleep 1; : > "$PLANS/fresher.md"
got=$(resolve "$PLANS" "$MARKER")
[[ -z "$got" ]] && pass "newer plan 2개 → 모호 skip(빈값)" || fail "모호 케이스 오판: '$got'"

# grep 가드: hook 이 -newer 기반 해결 포함 + 옛 무조건 ls -t fallback 제거
HOOK="$(cd "$(dirname "$0")/../.." && pwd)/hooks/enforce-plan-dev-goal.sh"
grep -qF '-newer' "$HOOK" && pass "hook -newer 필터 존재" || fail "hook -newer 필터 부재"

# grep 가드: hook 에 모호성(count>1) 분기 존재
grep -qiE 'count|newer_plans|모호|ambig' "$HOOK" && pass "hook 모호성 분기 존재" || fail "hook 모호성 분기 부재"

[[ $FAIL -eq 0 ]] && echo "=== ALL PASS ===" || { echo "=== FAILED ==="; exit 1; }
