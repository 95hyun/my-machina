---
name: doctor
description: '클론한 워크스페이스에서 하네스를 쓸 수 있는지 진단 — 실행 위치·도구·hook·개인 설정·계정·해커톤·누수.'
disable-model-invocation: true
---

# Doctor — 하네스 사용 가능 진단

진단과 해결 명령 안내만 한다. 파일은 고치지 않는다(사용자가 요청하면 그때).

1. 워크스페이스 루트(세션 cwd)에서 `bash .claude/skills/doctor/doctor.sh` 실행 — 파일이 없다는 오류면 세션을 루트가 아닌 곳에서 연 것이니 그대로 알린다(`$CLAUDE_PROJECT_DIR`는 Bash 도구 env에 없을 수 있어 쓰지 않는다). exit code를 함께 기록한다.
2. 출력 원문을 그대로 붙이지 않는다. ❌·⚠️ 항목만 `이름 — 원인 → 해결 명령` 한 줄씩 정리하고, 마지막에 요약 줄(`❌ N · ⚠️ M`)을 옮긴다. 모두 ✅면 "문제 없음" 한 줄.
3. ❌가 있으면 하네스 일부(hook·계정 강제·해커톤 스킬)가 동작하지 않는다는 점을 한 줄로 덧붙인다. 터미널에서 다시 보려면 `bash .claude/skills/doctor/doctor.sh`.
