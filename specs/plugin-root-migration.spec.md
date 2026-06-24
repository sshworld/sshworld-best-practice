# S1 — plugin-root-migration (refactor)

## 목표
sshworld-best-practice 를 **루트 레이아웃 Claude Code 플러그인**으로 전환. install.sh deprecate. 이 세션 글로벌 백업(`~/.claude`,`~/scripts`) 있으니 repo 이동 OK.

## TDD: 먼저 테스트 (Red)
신규 `tests/unit/plugin-layout.test.sh`:
- `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` 존재 + `python3 -c "import json;json.load(...)"` valid + plugin name == "plan-dev" (kebab).
- 루트에 `commands/`, `agents/`, `skills/`, `hooks/` 디렉토리 존재.
- `hooks/hooks.json` 존재 + JSON valid + `${CLAUDE_PLUGIN_ROOT}` 문자열 포함.
- `! grep -rln "/Users/sshworld/scripts" commands agents hooks skills` (잔존 0).
- `grep -rq "CLAUDE_PLUGIN_ROOT" hooks`.
실행 → 전부 Red 확인 후 구현.

## 구현 (Green)

### 1. 디렉토리 이동 (git mv, history 보존)
```
git mv .claude/commands commands
git mv .claude/agents   agents
git mv .claude/skills   skills
git mv .claude/hooks    hooks
git mv .claude/specs    specs
```
- `scripts/` 는 **이미 repo 루트 — 이동 금지**.
- `.claude/workflows`, `.claude/settings.json`, `.claude/settings.local.json` 는 **그대로 둠**(workflows=Workflow 툴 reference, settings=project-scope dogfooding 보존).

### 2. 플러그인 manifest (루트 `.claude-plugin/`)
`.claude-plugin/plugin.json`:
```json
{
  "name": "plan-dev",
  "version": "0.1.0",
  "description": "Plan-driven TDD dev workflow: Phase 0~6, cmux/tmux dispatch, goal-gate Stop hook, vertical slices.",
  "author": { "name": "sshworld" }
}
```
(`dependencies`/`mcpServers` 는 S4/S5 에서 추가 — 지금 넣지 말 것.)

`.claude-plugin/marketplace.json`:
```json
{
  "name": "sshworld",
  "owner": { "name": "sshworld" },
  "plugins": [
    { "name": "plan-dev", "source": ".", "description": "Plan-dev workflow plugin" }
  ]
}
```
(`allowCrossMarketplaceDependenciesOn` 는 S4 에서.)

### 3. `hooks/hooks.json` (settings.json hooks 미러)
`.claude/settings.json` 의 `hooks` 객체(이벤트별 matcher+command)를 **그대로 미러**하되, command 경로만 변환:
- `$CLAUDE_PROJECT_DIR/.claude/hooks/<n>.sh` → `"${CLAUDE_PLUGIN_ROOT}"/hooks/<n>.sh`
- `${CLAUDE_PROJECT_DIR}/scripts/<n>.sh` → `"${CLAUDE_PLUGIN_ROOT}"/scripts/<n>.sh`
- inline env prefix(예: `CMUX_CONTEXT_HOOK_STRICT=1 ...`)·SessionStart inline 명령은 보존.
형식: `{ "hooks": { "<Event>": [ { "matcher": "...", "hooks": [ { "type":"command", "command":"..." } ] } ] } }`.
**주의**: settings.json 의 `permissions`(allow/deny)는 플러그인이 번들 못 함 → hooks.json 엔 hooks 만. permissions 는 4단계(README)에서 문서화.

### 4. 가이드텍스트 경로 토큰화
`commands/`, `agents/`, `hooks/` 내 문자열:
- `/Users/sshworld/scripts` → `${CLAUDE_PLUGIN_ROOT}/scripts`
- `@@SCRIPTS_DIR@@` → `${CLAUDE_PLUGIN_ROOT}/scripts` (이미 있는 경우)
(`scripts/*.sh` 내부의 sibling 호출은 상대경로/`$(dirname)` 유지 — 변경 불필요.)

### 5. 기존 테스트 경로 갱신
`tests/` 안에서 `.claude/hooks` / `.claude/commands` / `.claude/agents` / `.claude/skills` 참조를 새 루트 경로(`hooks`/`commands`/`agents`/`skills`)로 치환. 특히 `HOOK="$(...)/.claude/hooks/..."` → `/hooks/...`. 갱신 후 **기존 테스트 전부 PASS 유지**.

### 6. install.sh → thin shim
install.sh 본문을 짧은 안내로 교체(기능 제거):
```sh
#!/usr/bin/env bash
echo "⚠️  install.sh 는 deprecated. 이제 Claude Code 플러그인으로 설치하세요:"
echo "    /plugin marketplace add sshworld/<repo>"
echo "    /plugin install plan-dev"
echo "기존 ~/.claude 설치본은 수동 정리(또는 /plugin 설치 후 중복 hook 제거) 필요."
exit 0
```
(`scripts/merge-settings.sh` 등 헬퍼는 보존 — 참조만.)

### 7. 문서 동기화
- `README.md`: 설치 섹션을 `/plugin` 방식으로 교체 + **"권장 permissions" 블록**(기존 settings.json allow/deny 를 사용자가 추가하도록 안내, deny `tmux kill-server` 포함).
- `CLAUDE.md`: 파일 경로 표의 `.claude/...` → 루트 경로 반영(이동된 것만). install.sh 책임 줄 deprecate 표기.

## Verify (Green 확인)
- `bash tests/unit/plugin-layout.test.sh` PASS.
- `bash tests/**/*.sh` (기존 포함) 전부 PASS — 특히 enforce-plan-dev-goal, merge-settings 회귀.
- `python3 -c "import json;json.load(open('hooks/hooks.json'))"` valid.
- `git status` 깨끗 + `git mv` 로 history 보존 확인.

## 금지
- `scripts/` 이동 금지(이미 루트).
- `.claude/settings.json`/`workflows` 삭제 금지.
- plugin.json 에 dependencies/mcpServers 추가 금지(S4/S5).
- permissions 를 hooks.json 에 욱여넣기 금지(플러그인 비지원).

## 완료 신호
모든 Verify PASS 면 마지막 줄에 `✅ S1 plugin-root-migration done` 출력. 실패면 `❌ <이유>`.
