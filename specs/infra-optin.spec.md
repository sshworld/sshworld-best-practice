# S5 — infra-optin (feat)

## 목표
무거운 인프라(codegraph 컨텍스트 검색)를 **graceful 자동**으로 선언 + 셋업 문서화. 키/서버 부재 시 core(plan-dev) 정상 = clone-and-go 안 깨짐.

## 확정 값 (검증 완료)
- codegraph MCP: `codegraph serve --mcp`, npm `@colbymchenry/codegraph`, **API 키 불필요·100% 로컬**.
- per-project 인덱스 빌드 `codegraph init` 필요(자동화 불가 — 문서 안내).
- headroom = 컨텍스트 압축 프록시(서버+라우팅) → 강제 부적합. docs opt-in 안내만.

## TDD: 먼저 테스트 (Red)
신규 `tests/unit/infra-optin.test.sh`:
- `.claude-plugin/plugin.json` `mcpServers.codegraph` 존재 + JSON valid.
- codegraph command 가 `npx`(auto-fetch) 또는 `codegraph` — graceful(하드 경로 아님).
- `docs/infra-setup.md` 존재 + `codegraph init` 와 `headroom` 둘 다 언급.
실행 → Red.

## 구현 (Green)

### .claude-plugin/plugin.json (mcpServers 추가, 기존 필드 보존)
```json
"mcpServers": {
  "codegraph": {
    "type": "stdio",
    "command": "npx",
    "args": ["-y", "@colbymchenry/codegraph", "serve", "--mcp"]
  }
}
```
- `npx -y` = 미설치 시 자동 fetch(자동 셋업 근접). npm/네트워크 부재 시 MCP 만 실패(/plugin Errors 표시), **plan-dev core 정상** = graceful.
- 키 불필요(codegraph 로컬). headroom 은 mcpServers 에 **넣지 말 것**(프록시, 강제 부적합).

### docs/infra-setup.md (신규)
- **codegraph**(컨텍스트 검색, grep/read 루프 대신 인덱스 → 입력 토큰↓):
  - 플러그인 설치 시 mcpServers 자동 선언(npx auto-fetch).
  - per-project 1회: `cd <project> && npx -y @colbymchenry/codegraph init` (인덱스 빌드 — 자동 불가, 수동).
  - 비활성: plugin.json mcpServers 제거 또는 plugin disable.
  - 키 불필요·100% 로컬.
- **headroom**(컨텍스트 압축 프록시, 60~95%):
  - opt-in 인프라 — 별도 서버+API 키+라우팅 필요(`pip`/Rust 빌드). 강제 미포함.
  - 설치/연동 링크 안내(chopratejas/headroom). plan-dev 와 독립.
- **비용/주의**: codegraph 인덱스 디스크, npx 첫 실행 지연. 무거운 인프라는 환경별 선택.

## 문서 동기화 (README.md)
- 토큰절약 레이어 표(출력=caveman opt-in / 스코프=yagni / 검색=codegraph / 압축=headroom) + "infra 상세: docs/infra-setup.md" 링크.

## Verify
- `bash tests/unit/infra-optin.test.sh` PASS.
- `bash tests/**/*.sh` 전체 PASS.
- `python3 -c "import json;json.load(open('.claude-plugin/plugin.json'))"` valid + dependencies(S4) 보존 확인.

## 금지
- headroom 을 mcpServers 에 강제 추가 금지.
- S1~S4 결과(레이아웃/skills/deps) 건드리기 금지.
- codegraph 에 가짜 API 키 env 추가 금지(불필요).

## 완료 신호
Verify PASS → `✅ infra-optin`. 실패 → `❌ <이유>`.
