# claude-best-practice

나만의 Claude Code 워크플로 모음. **`/plan-dev` TDD 워크플로 + 컨텍스트 관리 + 강제 가드(하네스)** 한 세트.

`shanraisshan/claude-code-best-practice` 가이드를 베이스로, 실사용 중에 다듬은 규칙을 콘텐츠(commands/agents/skills)와 하네스(settings/hooks) 양쪽으로 구성.

---

## 구성

```
.claude/
├── commands/
│   └── plan-dev.md           # 6단계 워크플로 (Explore → Plan → Review → TDD → Verify → Commit → Context 정리)
├── agents/
│   ├── implementor.md        # TDD Red→Green→Refactor, worktree 격리
│   ├── verifier.md           # Read-only 빌드/테스트 실행 + diff 제안
│   ├── reviewer.md           # 치명적 이슈만 블로킹, 나머지 제안
│   └── commit-advisor.md     # 한글 Conventional Commit + DOC 영향 평가
├── skills/
│   └── fork/SKILL.md         # 자식 컨텍스트에서 처리하고 요약만 반환
├── hooks/
│   ├── enforce-test-first.sh # production 파일 작성 전 테스트 존재 검사
│   ├── enforce-doc-sync.sh   # commit 시점 DOC 영향 평가 강제
│   └── token-stats.sh        # Stop 시 직전 응답 토큰 사용량 + 캐시 히트율 한 줄 노출
└── settings.json             # permissions(allow/deny) + 3 hooks
```

---

## 설치

```bash
# 글로벌 (~/.claude/) — 모든 프로젝트에서 사용
./install.sh user

# 프로젝트 로컬 (현재 디렉토리/.claude/)
./install.sh project

# 특정 디렉토리에 설치
./install.sh project /path/to/your/project

# 제거
./install.sh uninstall user
./install.sh uninstall project [TARGET_DIR]
```

기존 파일이 있으면 `.bak` 확장자로 백업한 뒤 덮어씁니다. `settings.json` 은 자동 병합하지 않고 `settings.example.json` 으로 복사 — 사용자가 수동 병합.

---

## 사용

### 메인 워크플로 — `/plan-dev`

```text
/plan-dev "이메일 인증 회원가입 추가"
```

자동 진행 흐름:
1. **Explore**: 관련 파일 자동 스캔
2. **빈틈 진단**: `AskUserQuestion` 으로 요구사항 명확화 반복
3. **EnterPlanMode**: plan 파일 작성 (200줄 이하 권장)
4. **Staff Engineer Plan Review**: Plan 서브에이전트 비평 (선택)
5. **ExitPlanMode**: 사용자 승인
6. **TDD Execute**: 병렬 implementor → worktree 격리, Red→Green→Refactor
7. **Verify**: verifier 빌드/테스트 (max 5회 루프)
8. **Review**: reviewer 치명적 이슈 점검 (선택)
9. **Commit**: commit-advisor 한글 메시지 추천 + DOC 영향 평가
10. **Context 정리**: 다음 추천 명령 (`/clear` / `/compact` / `/fork`) 노출

### 보조 — `/fork`

현재 흐름의 작업을 격리된 서브에이전트에 위임하고 부모 세션엔 요약만 반환:

```text
/fork
```

---

## 하네스 가드

매 commit / 매 코드 변경 시점에 자동 발동.

### 1) enforce-test-first.sh (PreToolUse: Write|Edit)

production 코드 파일(`src/main/`, `lib/`, `app/`, `internal/`, `pkg/`)을 Write/Edit 하기 직전에 대응 테스트 파일 존재 검사.

```bash
# 기본은 경고만
# strict 모드 (위반 시 차단):
export CLAUDE_TDD_STRICT=1
```

### 2) enforce-doc-sync.sh (PreToolUse: Bash, `git commit`)

매 commit 마다 **DOC 영향 평가를 강제**. 다음 두 가지 중 하나로 명시해야 통과:

```bash
# 영향 없음 (내부 fix·refactor)
DOC_IMPACT=none git commit -m "..."

# 영향 있음 (README/CLAUDE.md 함께 staged)
git add README.md
DOC_IMPACT=updated git commit -m "..."
```

`DOC_IMPACT` 미지정 시 차단. 가드 비활성화: `export DISABLE_DOC_SYNC_HOOK=1`

### 3) token-stats.sh (Stop)


응답이 끝날 때 직전 turn (마지막 user 메시지 이후 모든 assistant 줄) 의 토큰 사용량과 캐시 히트율을 한 줄로 노출:

```
💰 in=15 cache_c=150 cache_r=1.1k out=60 | cache hit 87%
```

`DISABLE_TOKEN_STATS=1` 로 끄기.

### 5) SessionStart inline

세션 시작 시 git worktree 목록 + 미커밋 변경 자동 출력.

---

## 환경변수 정리

| 변수 | 기본 | 효과 |
|---|---|---|
| `CLAUDE_TDD_STRICT=1` | off | TDD 위반 시 Write/Edit 차단 |
| `DOC_IMPACT=none|updated` | (미지정 시 차단) | commit 시 DOC 영향 명시 |
| `SKIP_DOC_SYNC=1` | off | doc-sync hook 1회 우회 (deprecated — DOC_IMPACT 사용) |
| `DISABLE_DOC_SYNC_HOOK=1` | off | doc-sync hook 영구 비활성화 |
| `DISABLE_TOKEN_STATS=1` | off | token-stats hook 비활성화 |

---

## Permissions (settings.json)

기본 allow:
- `git status`, `diff`, `log`, `branch`, `checkout`, `switch`, `fetch`, `pull`, `add`, `commit`, `stash`, `merge`, `rebase`, `remote`, `tag`, `worktree`, `restore`
- `BUILD_CMD` / `TEST_CMD` / `RUN_CMD` TODO 자리 (사용자가 프로젝트 빌드 명령으로 치환)

기본 deny:
- `rm -rf*`, `git push --force*`, `git push -f*`, `git commit --no-verify*`, `git reset --hard*`

---

## 베이스 출처

- GitHub: [shanraisshan/claude-code-best-practice](https://github.com/shanraisshan/claude-code-best-practice)
- 핵심 인용: Boris Cherny (Claude Code), Thariq (세션 관리), Dex Horthy (context % 가이드)

---

## 로드맵

- [ ] Claude Code 플러그인 형태로 패키징
- [ ] BUILD/TEST/RUN 명령 자동 감지 (gradle/npm/pytest 등)
- [ ] reviewer 룰 확장
- [ ] 다른 IDE/터미널 연동 가이드
