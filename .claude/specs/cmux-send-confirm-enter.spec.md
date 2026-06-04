# Slice S5 — cmux send Enter 미등록(PTY detached) 근본 수정 (type=fix)

## 배경/버그 (사용자 반복 관찰)
cmux 신규 surface 가 PTY detached → `dispatch-slice-pane` 의 spec prompt 가 입력칸에 들어가나
**Enter 가 claude TUI 준비 전 발사돼 유실** → 명령 미제출 → 부모가 수동 `cmux send-key Enter` 쳐야 시작.
`do_send`(scripts/cmux-pane.sh)의 현재 흐름: `send text` → `sleep DELAY(1.5)` → Enter×ENTER_COUNT(0.3s 간격).
ENTER_COUNT=2 라도 둘 다 startup 중 발사돼 둘 다 유실되는 타이밍 레이스.

## 수정 — do_send 에 "제출 확인 재시도" (scripts/cmux-pane.sh)
기존 Enter 송신 루프 **뒤**에 confirm 단계 추가. default ON, knob 으로 우회.

### 동작
1. 기존대로 text 전송 + sleep + Enter×ENTER_COUNT.
2. **confirm 루프** (`CBP_SEND_CONFIRM` != "0" 일 때, 즉 기본 ON):
   - 최대 `CBP_SEND_CONFIRM_TRIES`(기본 3)회: `sleep CBP_SEND_CONFIRM_SLEEP`(기본 0.6) →
     `screen=$("$CMUX_BIN" read-screen "$pane_flag" "$PANE" 2>/dev/null || echo "")`.
   - **제출 판정**: screen 의 마지막 입력 프롬프트 줄이 "비어있음"(제출됨) 이면 break.
     판정 헬퍼: screen 에 입력 프롬프트 마커(`❯` 또는 `>`) 줄이 있고 그 뒤 본문이 **공백뿐**이면 submitted.
     (정규식 예: 마지막 `❯`/`>` 매치 줄이 `^[[:space:]]*[❯>][[:space:]]*$` → submitted.)
   - 미제출(프롬프트 줄에 잔여 텍스트)이면 `send-key Enter` 1회 더.
   - **graceful 폴백**: read-screen 이 빈 문자열/판정 불가(mock·echo 환경)면 → confirm 루프는
     **최대 1회 추가 Enter 만** 보내고 종료 (무한 루프·과도 Enter 금지).
3. confirm 으로 보낸 추가 Enter 는 제출 후 빈 입력에 가므로 claude 에서 no-op (안전).

### Knobs (CLAUDE.md 환경변수 표에도 추가)
- `CBP_SEND_CONFIRM` (기본 unset=ON, `0` 이면 OFF — 기존 동작)
- `CBP_SEND_CONFIRM_TRIES` (기본 3)
- `CBP_SEND_CONFIRM_SLEEP` (기본 0.6)

### 헬퍼 함수
`_send_is_submitted() { local screen="$1"; ... }` — submitted 면 return 0, 아니면 1.
read-screen 결과를 awk/grep 로 마지막 프롬프트 줄 판정.

## 테스트 — tests/unit/cmux-pane-send-confirm.test.sh (chmod +x)
기존 `tests/unit/cmux-pane-send-enter-count.test.sh` 컨벤션. **richer mock** 필요 (echo 로는 read-screen 판정 불가):
- 임시 fake cmux 스크립트 작성 (`$TMP/cmux`): 인자 첫 토큰이 `read-screen` 이면 미리 준비한
  파일(`$TMP/screen.txt`) 내용 출력; `send`/`send-key` 면 호출을 `$TMP/calls.log` 에 append + echo.
- `CMUX_BIN="$TMP/cmux"`.
- **TC1 (미제출→재시도)**: screen.txt 에 `❯ some pending text` (미제출) → do_send 호출 →
  confirm 루프가 추가 Enter 를 보냄 → calls.log 의 send-key Enter 횟수가 기본(ENTER_COUNT) 보다 큼.
  (TRIES 동안 계속 미제출이면 정확히 base+TRIES 회.)
- **TC2 (이미 제출됨→추가 없음)**: screen.txt 에 `❯` (빈 입력=제출됨) → 추가 Enter 0 →
  send-key 횟수 == ENTER_COUNT.
- **TC3 (read-screen 빈값=mock 폴백)**: read-screen 이 빈 출력 → confirm 이 최대 1회 추가 Enter 후 종료.
- **회귀**: `CBP_SEND_CONFIRM=0` 이면 기존 동작(추가 Enter 0).

## 무회귀
- 기존 `tests/unit/cmux-pane-send-enter-count.test.sh` (CMUX_BIN=echo): echo 환경 = read-screen 빈/무의미 →
  confirm 폴백이 "최대 1회 추가" 라 echo 호출 수가 바뀔 수 있음 → **이 회귀 테스트가 깨지지 않도록**:
  echo mock 에선 confirm 이 추가 Enter 를 보내면 기존 기대치(2/4/1)가 어긋남.
  → 해결: 기존 테스트는 `CBP_SEND_CONFIRM=0` 을 안 줌. 따라서 **confirm 폴백 판정에서 "read-screen 출력이
  send-key/send 인자를 그대로 echo 한 것"(즉 의미없는 mock)도 '판정 불가→폴백'** 으로 처리하되,
  폴백 시 **추가 Enter 0 (보수적)** 으로 바꿔 기존 echo 테스트 회귀를 막을 것.
  (즉 폴백 기본은 "추가 0". 단 TC3 는 그 0 을 확인. 위 TC3 문구의 "최대 1회"→**"0회(보수적)"** 로 정정.)
  → **최종 규칙**: read-screen 으로 "명확히 미제출" 확인될 때만 추가 Enter. 불명/빈값/판정불가 → 추가 0.
  이렇게 하면 echo 회귀 안전 + detached 실케이스(미제출 명확)서만 재시도.

## 검증
```bash
bash tests/unit/cmux-pane-send-confirm.test.sh
bash tests/unit/cmux-pane-send-enter-count.test.sh   # 회귀 (CMUX_BIN=echo 무영향)
bash tests/unit/cmux-pane-lifecycle.test.sh 2>/dev/null || true
grep -q "CBP_SEND_CONFIRM" scripts/cmux-pane.sh
```

## 완료 시
신규 테스트 + enter-count 회귀 PASS → `✅ cmux-send-confirm-enter`. 실패 → `❌`+원인.
주의: 기존 do_send 의 ENTER_COUNT/DELAY 동작·시그니처 보존. confirm 은 순수 add-on.
