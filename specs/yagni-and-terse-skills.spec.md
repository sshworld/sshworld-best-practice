# S3 — yagni-and-terse-skills (feat)

## 목표
토큰절약 2레이어를 **자작 경량 skill** 로 내장. 외부 플러그인 vendor 안 함(라이선스), 사상만 흡수.
- **YAGNI**(ponytail 사상): 코드 쓰기 前 필요성 검사 → 불필요 코드↓ → verify/review 토큰↓.
- **terse-output**(caveman 사상 일부): 응답 간결화 가이드(내부, plugin 의존 아님).

## TDD: 먼저 테스트 (Red)
신규 `tests/unit/skills-yagni-terse.test.sh`:
- `skills/yagni/SKILL.md`, `skills/terse-output/SKILL.md` 존재.
- 각 SKILL.md frontmatter `name:` == 디렉토리명 (yagni / terse-output).
- 각 frontmatter `description:` 한 줄 존재(빈값 아님).
- `agents/implementor.md` 에 YAGNI 참조 존재 (`grep -qi "yagni\|필요성" agents/implementor.md`).
실행 → Red 확인.

## 구현 (Green)

### skills/yagni/SKILL.md
frontmatter:
```
---
name: yagni
description: 코드/추상화 추가 前 "지금 필요한가" 검사. 추측성 일반화·미사용 옵션·조기 추상화를 막아 구현·리뷰·테스트 토큰을 줄인다. 새 함수/클래스/설정/의존성 추가 시 트리거.
---
```
본문(자작, 간결):
- **규칙**: 새 코드 추가 전 3문 자문 — (1) 지금 이 기능이 실제로 호출되는가? (2) 요구에 명시됐는가, 내가 상상한 미래인가? (3) 기존 함수/유틸 재사용으로 대체 가능한가?
- 하나라도 "아니오/불확실" → 추가 보류, 사용자/요구 확인.
- **금지**: 요구 없는 설정 플래그, "나중에 쓸지도" 추상 레이어, 단일 호출처인데 일반화, 미사용 export.
- **예외**: 명시 요청·테스트 fixture·인터페이스 계약상 필요.
- plan-dev 연계: implementor Green 단계에서 통과 코드만, Refactor 에서 YAGNI 위반 제거.

### skills/terse-output/SKILL.md
frontmatter:
```
---
name: terse-output
description: 응답에서 군더더기(인사·중복 요약·hedging) 제거하고 기술 substance 유지. 토큰 절감. 코드/커밋/보안 설명은 정상 산문 유지.
---
```
본문(자작):
- 드롭: 인사말, "기꺼이 돕겠습니다"류, 중복 재진술, 과도한 hedging.
- 유지: 정확한 기술 용어, 코드블록, 에러 원문, 명령.
- 경계: 코드·커밋 메시지·보안 경고·다단계 확인은 명료 산문(축약 금지).
- caveman 플러그인과 독립 — 이건 plan-dev 내장 가이드(외부 의존 0). caveman 설치 시 중복돼도 무해.

### agents/implementor.md
- TDD Refactor 단계 설명에 1줄 추가: "Refactor 시 [[yagni]] 기준 — 요구에 없는 추상화·미사용 코드 제거."

## 문서 동기화
- `README.md` 구성 섹션에 skills 2개(yagni, terse-output) 추가 1줄씩.

## Verify
- `bash tests/unit/skills-yagni-terse.test.sh` PASS.
- `bash tests/**/*.sh` 전체 PASS.

## 금지
- 외부 플러그인(ponytail/caveman) 파일 복사 금지 — 자작 사상만.
- plugin.json/marketplace.json 건드리기 금지(S4).

## 완료 신호
Verify PASS → `✅ yagni-and-terse-skills`. 실패 → `❌ <이유>`.
