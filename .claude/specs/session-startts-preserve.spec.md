# Slice S2 — plan-dev-session do_start start_ts 보존 (type=fix)

## 배경/버그
`scripts/plan-dev-session.sh` 의 `do_start()` 재진입 가드가 `pid_alive "$existing_pid"` 에 의존.
근데 `start_pid=$$` 는 단명 스크립트 PID → 거의 항상 dead → 가드 실패 → 매 `start` 호출이
marker 를 mv .bak 후 **fresh start_ts 로 재작성**. `plan-dev-progress.sh start` 가 내부적으로
`plan-dev-session.sh start` 를 재호출(L53)하므로 그 경로서 start_ts 가 now 로 clobber 됨 →
`enforce-plan-mode.sh` 가 plan 파일을 start_ts 보다 과거(stale)로 오판 → 승인 후 Edit false-positive 차단.

## 수정 (do_start 의 "기존 marker 검사" 블록)
현재 구조 (요지):
```bash
if [ -f "$marker" ]; then
  existing_pid=$(json_get "$marker" "start_pid") ...
  existing_ts=$(json_get "$marker" "start_ts") ...
  if [ -n "$existing_pid" ] && [ -n "$existing_ts" ]; then
    if pid_alive "$existing_pid" && within_24h "$existing_ts"; then
      echo "...이미 진행 중..." >&2; exit 0
    fi
  fi
  mv "$marker" "${marker}.bak"      # ← 여기 도달 시 아래서 fresh ts/ref 재작성 = 버그
fi
...
start_ref=$(git rev-parse HEAD)
...
start_ts="$(iso_ts)"
```

### 변경 내용
1. 기존 marker 에서 `existing_ref` 도 캡처: `existing_ref=$(json_get "$marker" "start_ref" 2>/dev/null) || existing_ref=""`.
2. **dead pid 라도 within_24h 면 같은 세션 재진입으로 간주 → start_ts/start_ref 보존**.
   `mv .bak` 직전 또는 직후에:
   ```bash
   local preserve_ts="" preserve_ref=""
   if [ -n "$existing_ts" ] && within_24h "$existing_ts"; then
     preserve_ts="$existing_ts"; preserve_ref="$existing_ref"
   fi
   ```
   (pid_alive+within_24h 는 위에서 이미 exit 0 처리됨. 여기 도달 = pid dead 또는 stale.)
3. 마커 재작성부에서:
   ```bash
   start_ref=$(git rev-parse HEAD); [ -n "$preserve_ref" ] && start_ref="$preserve_ref"
   start_ts="$(iso_ts)";           [ -n "$preserve_ts" ]  && start_ts="$preserve_ts"
   ```
   (변수 선언 위치는 기존 코드 흐름에 맞춰 자연스럽게. `local` 중복 선언 주의.)

주석에 `# 재진입(dead pid + within_24h): start_ts/start_ref 보존 — progress start 재호출이 clobber 하던 버그 fix` 같은 한 줄 남길 것 (lint 가 `preserve|보존|existing_ts` grep).

### 무회귀 (필수)
- `tests/plan_dev_session.sh` TC2 (pid alive + recent → exit 0, marker 불변) 유지.
- TC3 (dead pid + **25h stale** → 새 marker + .bak) 유지: stale 는 within_24h=false 라 preserve 안 됨 → fresh ts. OK.

## 신규 테스트
`tests/plan_dev_session_startts_preserve.sh` (실행권한 chmod +x). 기존 `tests/plan_dev_session.sh` 컨벤션 따름:
- tmp git repo init + commit.
- `plan-dev-session.sh start --quiet` 1회 → marker 의 start_ts (TS1) 읽기 (query --key=start_ts).
- (자식 프로세스라 prior start_pid 는 종료됨 = dead) `sleep 1` 후 `plan-dev-session.sh start` 재호출.
- marker 의 start_ts (TS2) 다시 읽어 **TS1 == TS2** assert (보존). 다르면 fail.
- 추가로 start_ref 도 동일 assert 권장.
PASS 시 `OK` 출력.

## CLAUDE.md (1줄)
`scripts/plan-dev-session.sh` 파일책임 행에 "재진입(dead pid + within_24h) 시 start_ts/start_ref 보존 — progress start 재호출 clobber 방지(enforce-plan-mode false-positive 제거)" 취지 한 구절 추가.

## 검증
```bash
bash tests/plan_dev_session.sh
bash tests/plan_dev_session_startts_preserve.sh
grep -qE "preserve|보존|existing_ts" scripts/plan-dev-session.sh
```
실증: tmp repo 에서 `start` → `plan-dev-progress.sh start --total=3` → start_ts 불변 확인.

## 완료 시
검증 전부 PASS → `✅ S2 done`. 실패 → `❌` + 원인.
