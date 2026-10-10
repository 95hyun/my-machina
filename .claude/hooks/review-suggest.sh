#!/bin/bash
# review-suggest (my-machina) — PostToolUse hook (Edit|Write|MultiEdit)
# 코드·하네스 파일 수정 시 "일단락되면 리뷰" 힌트를 Claude 컨텍스트에만 주입한다(사용자 화면 출력 0, 비차단).
# 세션당 프로젝트별 1회만(dedup) — 컨텍스트 낭비 방지. 리뷰 기준(code-review·security-review·@secuman)은 go 스킬 4단계가 정본 — 여기서 재서술하지 않는다.

INPUT=$(cat 2>/dev/null) || exit 0
[ -z "$INPUT" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0
ROOT="${CLAUDE_PROJECT_DIR:-$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)}"
[ -z "$ROOT" ] && exit 0

case "$FILE" in
  "$ROOT"/*) ;;
  *) exit 0 ;;   # 워크스페이스 밖(스크래치패드 등)은 침묵
esac

case "$FILE" in
  */.specs/*) exit 0 ;;
  "$ROOT/CLAUDE.md"|"$ROOT"/.claude/*)
    KEY="harness"
    MSG="[review-hint] 하네스 파일이 수정됨. 일단락되면 @harco로 하네스 리뷰를 받으세요(작성자 자기 점검으로 대체 금지). 이미 했으면 생략." ;;
  # 권한·배포 설정(tauri capabilities, Package.swift, Cargo.toml, plist, entitlements)도 루프 밖 수정 시 유일한 리뷰 신호라 포함
  *.swift|*.rs|*.ts|*.tsx|*.js|*.jsx|*.py|*.sh|*.json|*.toml|*.plist|*.entitlements)
    REL="${FILE#"$ROOT"/}"
    KEY="${REL%%/*}"
    MSG="[review-hint] $KEY 코드·설정이 수정됨. 작업이 일단락되면 go 스킬 4단계 리뷰 기준(code-review·security-review·@secuman)으로 리뷰 여부를 판단하세요(작성자 자기 평가로 대체 금지). 이미 했으면 생략." ;;
  *) exit 0 ;;
esac

SID=$(printf '%s' "$INPUT" | jq -r '.session_id // "nosess"' 2>/dev/null)
TMP="$ROOT/.claude/tmp"
mkdir -p "$TMP" 2>/dev/null
find "$TMP" -maxdepth 1 -type f -name '.review-seen-*' -mtime +7 -delete 2>/dev/null
SEEN="$TMP/.review-seen-$SID"
grep -qxF "$KEY" "$SEEN" 2>/dev/null && exit 0
printf '%s\n' "$KEY" >> "$SEEN" 2>/dev/null

jq -n --arg m "$MSG" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$m}}' 2>/dev/null
exit 0
