# infra-setup — 선택적 인프라 설정

plan-dev core(plan/TDD/dispatch)는 이 인프라 없이도 정상 동작합니다.
무거운 인프라는 **환경별 선택** — 필요할 때만 활성화하세요.

---

## codegraph (컨텍스트 검색)

grep/read 루프 대신 인덱스 기반 심볼 검색 → 입력 토큰 절감.
API 키 불필요, 100% 로컬.

### 자동 선언

`/plugin install plan-dev` 시 `mcpServers.codegraph` 가 자동으로 선언됩니다.
`npx -y` 로 미설치 시 자동 fetch — npm/네트워크 부재 시 MCP 서버만 실패(plan-dev core 정상).

### per-project 인덱스 빌드 (수동, 1회)

```bash
cd <your-project>
npx -y @colbymchenry/codegraph init
```

인덱스 빌드는 자동화 불가(프로젝트 경로가 다양) — 새 프로젝트마다 한 번 실행하세요.

### 비활성화

```json
// plugin.json 에서 mcpServers.codegraph 제거
// 또는: /plugin disable plan-dev
```

### 주의

- 인덱스 파일이 프로젝트 디스크 공간 사용.
- `npx` 첫 실행 시 패키지 다운로드 지연 있음.

---

## headroom (컨텍스트 압축 프록시)

대화 컨텍스트를 60~95% 압축하는 별도 프록시 서버.
강제 미포함 — plan-dev 와 독립적으로 opt-in.

### 설치 (별도 서버 필요)

프로젝트: [chopratejas/headroom](https://github.com/chopratejas/headroom)

- Python(`pip`) 또는 Rust 빌드 필요.
- API 키 + 별도 라우팅 설정 필요.
- Claude Code 의 API base URL 을 headroom 프록시로 변경하는 방식.

### 적합 상황

- 장시간 세션에서 컨텍스트 창 고갈이 반복될 때.
- 입력 토큰 비용을 추가로 줄이고 싶을 때.

> headroom 은 별도 인프라이므로 이 플러그인의 mcpServers 에 포함되지 않습니다.

---

## 토큰 절약 레이어 요약

| 레이어 | 수단 | 비고 |
|---|---|---|
| 출력 | caveman (opt-in) | 응답 스타일 압축 |
| 스코프 | yagni skill | 추측성 코드 방지 |
| 검색 | codegraph (이 문서) | 인덱스 기반, npx auto-fetch |
| 압축 | headroom (이 문서) | 별도 서버, opt-in |
