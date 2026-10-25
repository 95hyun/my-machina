#!/bin/bash
# role-guard (my-machina) — PreToolUse hook (matcher: Write|Edit|MultiEdit|NotebookEdit)
# 역할 에이전트의 파일 쓰기를 소유 경로로 제한한다. 에이전트 정의의 "Write는 ~에만"을 글이 아니라 판정으로 강제.
#   qabot → */.specs/qa/reports/ 아래
#   pm    → */.specs/<slug>/intent.md, */.specs/<slug>/research.md
#   pd    → */.specs/<slug>/design.md, */.specs/<slug>/design/ 아래
# <slug> = .specs 바로 아래 한 세그먼트, qa·_archive 제외(pm·pd가 QA 자산·보관본을 덮지 못하게).
# 서브에이전트 호출에만 agent_type이 실린다(메인 세션 호출엔 없음 — 2026-10-25 실측). 위 셋이 아니면 무개입.
# Bash 리다이렉트 쓰기는 여기서 보지 않는다(에이전트 정의 금지 규칙 + git-guard 범위 밖).
# 항상 exit 0, 판단 불가 시 무개입.

INPUT=$(cat 2>/dev/null) || exit 0
[ -z "$INPUT" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

AGENT=$(printf '%s' "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null)
case "$AGENT" in qabot|pm|pd) ;; *) exit 0 ;; esac

FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0

case "$AGENT" in
  qabot) ALLOW="<project>/.specs/qa/reports/" ;;
  pm) ALLOW="<project>/.specs/<slug>/intent.md·research.md" ;;
  pd) ALLOW="<project>/.specs/<slug>/design.md·design/" ;;
esac

# bash case의 *는 /도 매칭하므로 정규식으로 세그먼트 단위 판정. 상대경로·./.. 세그먼트는 우회 방지로 deny
SLUG='/\.specs/([^/]+)/'
OK=0
if [[ "$FILE" == /* ]] && ! [[ "$FILE" =~ (^|/)\.\.?(/|$) ]]; then
  case "$AGENT" in
    qabot) [[ "$FILE" =~ /\.specs/qa/reports/.+ ]] && OK=1 ;;
    pm) [[ "$FILE" =~ ${SLUG}(intent|research)\.md$ ]] && OK=1 ;;
    pd) [[ "$FILE" =~ ${SLUG}(design\.md$|design/.+) ]] && OK=1 ;;
  esac
  if [ "$OK" = 1 ] && [ "$AGENT" != qabot ]; then
    case "${BASH_REMATCH[1]}" in qa|_archive) OK=0 ;; esac
  fi
fi
[ "$OK" = 1 ] && exit 0

jq -cn --arg r "$AGENT 은(는) 소유 경로($ALLOW)에만 쓸 수 있습니다: $FILE — 그 밖의 변경은 반환 리포트로 조율자에게 요청하세요." \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
exit 0
