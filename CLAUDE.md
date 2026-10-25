# my-machina — 1인 개발 워크스페이스 하네스

> Deus ex machina.

1인 개발. 이 repo를 clone한 디렉토리 = 워크스페이스 루트. 하위 디렉토리는 각자 독립 git repo이고, 이 파일과 `.claude/`만 이 repo가 관리한다.
**세션은 워크스페이스 루트에서 시작한다** — 하위 repo에서 시작하면 이 파일만 로드되고 `.claude/`의 hook·env·스킬·에이전트는 빠진다.

## 원칙
- 사용자 명시 지시가 최우선. 요청된 변경만 한다(무관한 정리·리팩터링 금지).
- **결정은 누구의 것인가**: 제품·도메인 결정은 사용자에게 묻고, 기술 결정은 선택지·트레이드오프·추천을 제시해 고르게 한다. 코드·관례로 이미 정해진 건 묻지 않는다.
- 즉시 멈추고 확인: 요구 모호, breaking change, 사용자 데이터 삭제·이동, 배포물 공개, 남의 repo로 push.
- **자기 채점 불신**: "됐다"의 근거는 캡처한 exit code·실측(스냅샷·로그·테스트 출력)뿐이다. 평가하지 못한 체크는 통과가 아니라 "미검증 — 사유"로 보고한다.
- 유지보수 주석: 비직관적 결정·외부 제약에만 한 줄 한국어 주석.

## 작업 루프
- 비자명한 작업(결정 갈림길·여러 파일·되돌리기 비싼 변경)은 `/ready → /go → (/qa) → /ship` — `/qa`는 실행·화면으로만 판정 가능한 `[run]` 확인 포인트가 있을 때 @qabot이 독립 실측. 산출물 = `<project>/.specs/<slug>/spec.md`(git 미추적). "무엇을 만들지"가 안 굳은 작업(새 프로젝트·제품 재량 큰 기능)은 `intent.md`(draft→confirmed)가 먼저이고, confirmed 전에는 구현하지 않는다. 한두 파일짜리 명확한 수정은 루프 없이 바로 한다.
- **메인 세션 = 결정·검증**. 구현은 위험도로 가른다: MECHANICAL(패턴 반복·명확한 수정)은 직접, RISKY(파급 큼·상태/동시성·외부 계약) 또는 독립 병렬 작업은 `@coder`.
- 서브에이전트 스폰 시 모델을 명시한다 — 정의에 모델이 없는 타입(Explore·general-purpose·Plan)은 미지정 시 세션 모델을 상속한다. 탐색·패턴 작업은 `model: "sonnet"`.
- 위임 규율: 스펙에 `파일:라인` 좌표, 질문 왕복 최대 1회(2회째면 직접 착수), 추가 지시는 SendMessage(재스폰 금지), 미도착 결과 예측 금지, diff·검증은 메인이 직접 확인.
- 범위 밖에서 발견한 문제는 고치지 말고 `<project>/.specs/findings.md`에 한 줄로 남긴다.

## git·계정
- 워크스페이스 계정 = `.claude/settings.local.json` env의 `MACHINA_EMAIL`·`MACHINA_GH`(gitignore, 설정 시 git-guard가 강제). 커밋 신원은 `~/.gitconfig` `includeIf "gitdir:<workspace>/"`가 적용한다 — repo 로컬 `user.*`·`core.sshCommand` 덮어쓰기 금지. `gh`는 같은 파일 env의 `GH_CONFIG_DIR`을 쓴다.
- 1인 개발이라 main 직접 커밋이 기본. 커밋·push는 요청 시에만, add는 파일 명시.
- 남의 repo는 push 금지, 기여는 사용자 결정. 개인 계정·남의 repo 목록·프로젝트 맵은 `CLAUDE.local.md`(gitignore)에 둔다.
- `git-guard` hook이 신원 불일치·다른 계정 gh(설정 시 면제 불가)와 세션 작업장 혼선·다른 브랜치 push·남의 repo push를 deny한다. deny 시 우회 금지, 사유를 보고한다 — 탈출 토큰(`GIT_GUARD_REBIND=1`·`GIT_GUARD_OK=1`, 명령 맨 앞 접두만 유효)은 사용자가 그 명령을 명시 승인한 뒤에만 붙인다.

## 프로젝트 맵
- 프로젝트별 스택·검증 명령(= `/go` 완료 증거)은 `CLAUDE.local.md`의 프로젝트 맵이 정본이다.

## 기억의 역할 분담
- auto-memory = 세션을 넘는 사실·선호. 이 파일 = 행동 규칙. 프로젝트 `CLAUDE.md` = 코드로 알 수 없는 검증법·함정만, `docs/decisions.md` = 결정 이유(ship이 승격). spec = 작업 1건 인수인계.

## 하네스 변경 규칙
- 무언가 추가하기 전 상시 비용을 따진다: 이 파일 전량·스킬/에이전트 description은 매 세션, 스킬 본문은 호출 시, hook은 0토큰. 진짜 사고 위험만 hook으로 강제하고 나머지는 스킬로.
- 하네스 변경은 `python3 .claude/ci/harness_ci.py` 통과가 전제다(push마다 GitHub Actions에서도 돈다). hook 판정을 바꾸면 테스트 케이스도 같이 추가하고, 예산(`.claude/ci/budget.json`) 상향은 사유를 남긴다.
- 스킬·에이전트 트리거의 정본은 frontmatter description — 이 파일에 키워드 표를 두지 않는다. 부작용 있는 스킬(go·qa·ship)은 `disable-model-invocation: true`.
