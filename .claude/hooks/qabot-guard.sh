#!/bin/bash
# qabot-guard (my-machina) — PreToolUse hook (matcher: Write|Edit|MultiEdit)
# @qabot의 파일 쓰기를 QA 리포트 경로(*/.specs/qa/reports/)로 제한한다. qabot.md의 "Write는 리포트에만"을 글이 아니라 판정으로 강제.
# 서브에이전트 호출에만 agent_type이 실린다(메인 세션 호출엔 없음 — 2026-10-25 실측). qabot이 아니면 무개입.
# Bash 리다이렉트 쓰기는 여기서 보지 않는다(qabot.md 금지 규칙 + git-guard 범위 밖).
# 항상 exit 0, 판단 불가 시 무개입.

INPUT=$(cat 2>/dev/null) || exit 0
[ -z "$INPUT" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

AGENT=$(printf '%s' "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null)
[ "$AGENT" = "qabot" ] || exit 0

FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0

case "$FILE" in
  */.specs/qa/reports/*)
    case "$FILE" in */../*) ;; *) exit 0 ;; esac ;;
esac

jq -cn --arg r "qabot은 QA 리포트 경로(<project>/.specs/qa/reports/)에만 쓸 수 있습니다: $FILE — recipe·시나리오·소스 수정은 리포트의 📌 후보로 남기세요." \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
exit 0
