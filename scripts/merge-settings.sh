#!/usr/bin/env bash
# merge-settings.sh — Claude Code settings.json 2개를 병합해 stdout 출력.
#
# 사용: merge-settings.sh <cur.json> <new.json>
#   cur = 기존(설치 대상) settings, new = repo(소스) settings.
#
# 병합 정책:
#   - permissions.allow / deny: union (unique).
#   - hooks.<event>: matcher 단위 union (order-preserving). 같은 matcher 의 hooks 는
#     command 키 기준 dedup — cur 내부 중복 + cur-vs-new 중복 모두 제거, new 가 키 충돌 시 winner.
#   - 그 외 top-level 키: 기존(cur) 우선.
#
# dedup 키: command 에서 `hooks/<name>.(sh|js)` 캡처, 없으면 full command 문자열.
#
# ⚠️ 과거 버그(수정됨): matcher 목록을 unique 안 하고 reduce 순회 → cur 에 같은 matcher
#    그룹이 여러 개면 hooks 가 곱셈 누적(SessionStart caveman 1024× doubling). 아래 jq 는
#    matcher order-preserving unique + cur 내부 dedup 으로 idempotent 보장.
#
# 실패(잘못된 JSON 등) 시 비-0 exit → 호출측(install.sh)이 example 폴백.
set -uo pipefail

CUR="${1:?usage: merge-settings.sh <cur.json> <new.json>}"
NEW="${2:?usage: merge-settings.sh <cur.json> <new.json>}"

command -v jq >/dev/null 2>&1 || { echo "merge-settings: jq 필요" >&2; exit 3; }

jq -s '
  def k: (try (.command | capture("hooks/(?<n>[A-Za-z0-9_.-]+\\.(sh|js))").n)) // .command;
  # order-preserving unique (스칼라 배열)
  def ouniq: reduce .[] as $x ([]; if any(.[]; . == $x) then . else . + [$x] end);
  # hook 객체 배열 first-seen dedup (키 기준)
  def dedup_hooks: reduce .[] as $h ([]; ($h|k) as $kk | if any(.[]; (.|k) == $kk) then . else . + [$h] end);

  .[0] as $cur | .[1] as $new
  | $cur
  | .permissions.allow = (((.permissions.allow // []) + ($new.permissions.allow // [])) | unique)
  | .permissions.deny  = (((.permissions.deny  // []) + ($new.permissions.deny  // [])) | unique)
  | .hooks = (
      ($cur.hooks // {}) as $ch
      | ($new.hooks // {}) as $nh
      | (($ch | keys_unsorted) + (($nh | keys_unsorted) - ($ch | keys_unsorted))) as $events
      | reduce $events[] as $e ({}; .[$e] = (
          ($ch[$e] // []) as $cur_arr
          | ($nh[$e] // []) as $new_arr
          | ( ($cur_arr | map(.matcher // "")) + ($new_arr | map(.matcher // "")) | ouniq ) as $matchers
          | reduce $matchers[] as $m ([]; . + [{
              matcher: $m,
              hooks: (
                ( ($cur_arr | map(select((.matcher // "") == $m)) | map(.hooks // []) | add) // [] | dedup_hooks ) as $cur_hooks
                | ( ($new_arr | map(select((.matcher // "") == $m)) | map(.hooks // []) | add) // [] | dedup_hooks ) as $new_hooks
                | ($new_hooks | map(k)) as $new_keys
                | ($cur_hooks | map(. as $h | select(($new_keys | index($h|k)) | not))) + $new_hooks
              )
            }])
        ))
    )
' "$CUR" "$NEW"
