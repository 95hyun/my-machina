---
name: ship
description: 'go 완료 후 마무리 — 신원 확인→작업 단위 커밋(컨펌)→push→spec 보관.'
argument-hint: '[project/slug]'
disable-model-invocation: true
---

# Ship — 커밋 → push → 보관

작업 루프 3단계. 커밋 내용은 사용자 컨펌을 받는다. 릴리스(DMG 빌드·배포)는 명시 요청 시에만.

## 0. 프리플라이트
- spec이 있으면 status가 `implemented`인지 확인(아니면 경고 후 계속 여부). 루프 밖 호출이면 spec 관련 단계만 생략.
- 신원: `git -C <repo> config user.email`이 `kingmandoo95@gmail.com`이 아니면 중단하고 보고(로컬 config로 덮지 않는다 — includeIf가 왜 안 먹었는지 원인부터).
- `git -C <repo> status --short` + `git diff --cached --name-only`로 staged까지 확인. 이 세션이 만들지 않은 변경은 커밋도 원복도 하지 않고 사용자에게 알린다.

## 1. 커밋
- `git -C <repo> log --oneline -10`으로 그 repo의 메시지 스타일을 따른다.
- 작업 단위로 나눠 파일 명시 add. 메시지·포함 파일 목록을 보여주고 컨펌받은 뒤 커밋.

## 2. push
- origin이 95hyun 소유일 때만 `git push origin HEAD`. remote가 없으면 로컬 커밋으로 끝(remote 생성은 사용자 결정).
- 남의 repo(logic-pro-mcp, PalworldModManager 등)는 push하지 않는다 — fork·PR 여부를 사용자에게 묻는다.

## 3. 보관
- spec `status: shipped`, 커밋 해시를 `## 결과`에 추가.
- `.specs/<slug>/` → `.specs/_archive/<YYYY-MM-DD>-<slug>/` 이동(날짜는 `date +%F` 실출력). 기능 intent는 같이 이동, 프로젝트 전체 `.specs/intent.md`는 그대로 둔다.
- `.specs/findings.md`에 이번 작업 중 쌓인 항목이 있으면 한 줄로 상기시킨다.

## DO NOT
❌ force-push ❌ 커밋 컨펌 생략 ❌ `git add -A`·`commit -a` ❌ 로컬 `user.*`·`core.sshCommand` 설정
