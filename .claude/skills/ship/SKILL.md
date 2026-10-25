---
name: ship
description: 'go 완료 후 마무리 — 신원 확인→작업 단위 커밋(컨펌)→push→spec 보관.'
argument-hint: '[project/slug]'
disable-model-invocation: true
---

# Ship — 커밋 → push → 보관

작업 루프 4단계. 커밋 내용은 사용자 컨펌을 받는다. 릴리스(DMG 빌드·배포)는 명시 요청 시에만.

## 0. 프리플라이트
- spec이 있으면 status가 `qa-passed`, 또는 `[run]` 포인트가 없는 `implemented`인지 확인. `[run]` 포인트가 미검증인데 ship하려 하면 "QA 미실시 N건"을 경고하고 계속 여부를 묻는다. 루프 밖 호출이면 spec 관련 단계만 생략.
- 신원: `git -C <repo> config user.email`이 워크스페이스 계정 이메일(`settings.local.json` env `MACHINA_EMAIL`, 미설정이면 이 확인 생략)이 아니면 중단하고 보고(로컬 config로 덮지 않는다 — includeIf가 왜 안 먹었는지 원인부터).
- `git -C <repo> status --short` + `git diff --cached --name-only`로 staged까지 확인. 이 세션이 만들지 않은 변경은 커밋도 원복도 하지 않고 사용자에게 알린다.

## 0.5 결정 승격 (spec이 있을 때, 커밋 전)
`.specs/`는 git 미추적이라 보관하면 결정이 repo에서 사라진다. 커밋 전에 남길 것을 프로젝트로 올린다.
- spec을 다시 읽는다(구현 직후라 코드에 치우친 시야를 의도 쪽으로 되돌리기 위해). 대상 = `## 결정`·`## 결과`·반영한 리뷰 지적 중 **코드만 읽어서는 알 수 없는 것**만.
  - 함정·검증법(다음 작업자가 밟을 지뢰, 판정 명령) → `<project>/CLAUDE.md`
  - 결정 이유(왜 A인가, 기각한 대안과 사유) → `<project>/docs/decisions.md`(없으면 생성). 항목 = `## YYYY-MM-DD <제목>` + 결정·이유·기각 대안 3~6줄, 최신이 위.
  - 이미 있는 항목과 겹치면 새로 쓰지 말고 그 항목을 고친다.
- 남의 repo(`CLAUDE.local.md` 목록)는 repo에 쓰지 않고 auto-memory의 해당 프로젝트 항목으로 보낸다.
- project가 워크스페이스 루트(하네스 자체)면 루트 CLAUDE.md는 상시 규칙 파일이라 승격 목적지가 아니다. 함정은 README "하네스를 바꿀 때", 결정 이유는 README "결정 기록" 소절(없으면 "계보" 아래에 만든다)로 보낸다.
- 승격 diff를 1단계 커밋 컨펌에 같이 보여준다. 0건이면 "승격 0건" 1줄.

## 1. 커밋
- `git -C <repo> log --oneline -10`으로 그 repo의 메시지 스타일을 따른다.
- 작업 단위로 나눠 파일 명시 add. 메시지·포함 파일 목록을 보여주고 컨펌받은 뒤 커밋.

## 2. push
- origin이 워크스페이스 계정(`MACHINA_GH`, 없으면 활성 gh 계정) 소유일 때만 `git push origin HEAD`. 소유를 판단할 수 없으면 push 전에 사용자에게 묻는다. remote가 없으면 로컬 커밋으로 끝(remote 생성은 사용자 결정).
- 남의 repo(`CLAUDE.local.md` 목록 등)는 push하지 않는다 — fork·PR 여부를 사용자에게 묻는다.

## 3. 보관
- spec `status: shipped`, 커밋 해시를 `## 결과`에 추가.
- `.specs/<slug>/` → `.specs/_archive/<YYYY-MM-DD>-<slug>/` 이동(날짜는 `date +%F` 실출력). 기능 intent는 같이 이동, 프로젝트 전체 `.specs/intent.md`는 그대로 둔다.
- `.specs/findings.md`에 이번 작업 중 쌓인 항목이 있으면 한 줄로 상기시킨다.

## 4. 결함 환류 (cron 없음 — ship마다 확인)
- 워크스페이스의 `.specs/defects.md`(루트 = 하네스 자체)와 `*/.specs/defects.md`를 모아 **실패 메커니즘**(태그가 아니라 요약 문장의 원인) 단위로 묶는다. 서로 다른 `<slug>` 3건 이상(발견:review 외의 발견은 2건으로 계산)이면 반영안을 만든다.
  - 프로젝트를 가리지 않고 재발할 함정 → `.claude/agents/coder.md` `## 반복 함정`(하네스 커밋 대상이므로 프로젝트 이름·경로 금지)
  - 한 프로젝트에만 성립 → 그 프로젝트 CLAUDE.md
  - 항목 형식 `- <함정> — 확인: <볼 곳·grep 패턴> (N회, 최근 YYYY-MM-DD)`. 이미 있는 항목에 해당하면 N·최근만 갱신.
- 섹션당 8줄 상한(넘으면 빈도×최근성 하위 교체 제안), `최근`이 8주 넘게 갱신되지 않은 항목은 퇴출 제안.
- 반영안은 AskUserQuestion 1회로 승인받는다. 대상 0건이면 출력하지 않는다.
- 승인된 반영은 대상 repo마다 별도 커밋 컨펌으로 커밋한다. `coder.md`(하네스)는 `harness_ci.py` 통과와 @harco 리뷰를 거친 뒤 커밋한다.

## DO NOT
❌ force-push ❌ 커밋 컨펌 생략 ❌ `git add -A`·`commit -a` ❌ 로컬 `user.*`·`core.sshCommand` 설정
