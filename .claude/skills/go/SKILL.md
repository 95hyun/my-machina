---
name: go
description: 'ready가 만든 spec.md대로 구현·검증하고 커밋 전에 멈춘다. spec이 없으면 ready만 하고 멈춘다.'
argument-hint: '[project/slug]'
disable-model-invocation: true
---

# Go — spec 기반 구현·검증 (커밋 전 정지)

작업 루프 2단계. 입력은 `<project>/.specs/<slug>/spec.md`.

## 0. 게이트
- spec 선택: 인자 > 대화 중인 slug > `*/.specs/*/spec.md` 중 `status: ready` 최신(복수면 AskUserQuestion 1회).
- spec이 없으면 `ready` 스킬을 로드해 실행하고 **거기서 종료**한다(준비 턴의 산출물은 spec까지).
- `status: implemented`·`qa-passed`(수정 재진입)는 그대로 진행하되 `qa-passed`면 `[run]` 체크박스를 `[ ]`로 되돌린다(코드가 바뀌면 QA 결과가 무효). `shipped`면 계속 여부 확인.
- **intent 게이트**: spec `intent:`가 가리키는 intent.md — 비어 있어도 `<project>/.specs/intent.md`(프로젝트 전체)가 있으면 그것 — 가 `draft`면 구현하지 않는다.
  - Open questions가 남았으면 그것부터 묻는다(AskUserQuestion).
  - 다 해소됐으면 Problem·Proposed outcome·Non-goals를 3~5줄로 요약해 "이대로 확정"을 첫 옵션으로 AskUserQuestion 1회 → 확정이면 `status: confirmed`·`updated:` 갱신(날짜는 `date +%F`), 수정 요청이면 반영 후 다시 확인.
  - 확정 과정에서 Problem·Proposed outcome이 바뀌어 spec 전제가 흔들리면 spec을 고치지 말고 `/ready` 재실행을 안내하고 종료.

## 1. 작업장
- `git -C <repo> status --short`로 시작 상태를 기록한다. 이 세션이 만들지 않은 변경이 있으면 건드리지 말고 사용자에게 알린다.
- 기본은 현재 브랜치(보통 main) 직접. spec `## 작업장`이 브랜치를 요구하거나 다른 세션이 같은 repo에서 작업 중이면 worktree(`EnterWorktree`)를 제안한다.
- worktree로 옮긴 뒤 첫 git 쓰기에서 git-guard 바인딩 deny가 나면, 전환이 의도된 것인지 사용자에게 확인받고 승인 시에만 그 명령 앞에 `GIT_GUARD_REBIND=1`을 붙인다.

## 2. 구현 — spec `## 작업`의 risk로 분기
- 구현·검증은 4단계 리뷰가 없는 것처럼 끝낸다. 리뷰는 남은 실수를 잡는 보험이지, "리뷰가 잡겠지"로 기준을 낮추는 근거가 아니다.
- risk가 비어 있으면 MECHANICAL로 간주하지 않고 RISKY로 취급한다.
- **MECHANICAL**: 메인이 직접 구현.
- **RISKY 또는 서로 독립인 작업 2개 이상**: `@coder`에 위임. 스펙 상단에 spec.md 경로(+ confirmed intent.md 경로 — 둘 다 구현 전 Read 강제), 해당 작업 번호, `파일:라인` 좌표, 검증 명령을 넣는다. 파급이 크면 `model: "opus"`.
- spec에 없는 결정 갈림길을 만나면 멈추고 묻는다(AskUserQuestion 1회). 범위 확장 금지 — 범위 밖 발견은 `.specs/findings.md`.

## 3. 검증 — 증거만 인정
- spec `## 확인 포인트`의 `[static]` 명령을 실행하고 **exit code를 캡처**한다: `<cmd> 2>&1 | tail -20; echo "exit=${PIPESTATUS[0]}"`.
- 판정 규칙: 0이 아니면 실패. **평가하지 못한 체크(권한·하드웨어·외부 앱 실행 필요 등)는 통과가 아니라 "미검증 — 사유"**. "보기엔 맞다"는 근거가 아니다.
- `[run]` 포인트(실행·화면·외부 앱 상태)는 여기서 판정하지 않는다 — 작성자가 채점하지 않도록 `/qa`(@qabot)로 넘기고 보고에 "QA 대기 N건"으로 적는다.
- 통과한 `[static]` 포인트는 spec 체크박스를 ✅로 바꾼다.
- 실패는 고친 뒤 **전체 확인 포인트를 다시** 돌린다(부분 재실행으로 통과 선언 금지).

## 4. 리뷰
- diff가 30줄을 넘거나 로직 분기·상태·동시성·외부 계약이 바뀌었으면 내장 `code-review` 스킬을 Skill tool로 로드한다. 작성자(메인/coder)의 자기 평가는 리뷰를 대신하지 못한다.
- 규모와 무관하게 추가: 하네스 파일(CLAUDE.md·`.claude/`) 변경 → `@harco` / 셸 호출·권한 승인·IPC(소켓·포트)·민감 데이터(transcript·토큰)·배포 스크립트를 건드림 → 내장 `security-review`(diff 단위), 새 진입점이 생겼으면 `@secuman`(위협 모델 감사).
- intent가 있으면 결과물을 Proposed outcome(빠진 항목)·Non-goals(넘어간 범위)와 대조한다 — 어긋나면 리뷰 지적과 같이 취급.
- 확정된 지적은 반영 후 3단계 재실행. 반영한 CRITICAL·WARNING은 `<project>/.specs/defects.md`에 1줄 append(오탐으로 폐기한 건 제외): `YYYY-MM-DD | <slug> | 심각도 | 실패 메커니즘 | 파일 | 요약 (발견:review)` — ship 4단계 환류의 입력.

## 5. 종료 보고
- spec `status: implemented`, `## 결과`에 검증 명령→exit code·미검증 항목을 기록.
- 보고: 변경 파일(`파일:라인`) · 검증 결과 원문 요약 · 미검증 항목 · 리뷰 결과 · 다음 단계 1줄(`[run]` 포인트가 있으면 "`/qa`로 실측", 없으면 "확인 후 `/ship`").

## DO NOT
❌ 커밋·push(ship 담당) ❌ `git add -A` ❌ spec에 없는 개선·리팩터링 ❌ 실패·미검증을 숨긴 완료 보고
