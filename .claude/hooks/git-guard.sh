#!/bin/bash
# git-guard (my-machina) — PreToolUse hook (matcher: Bash)
# 1인 개발 + 가끔 병렬 세션 전제. 회사 하네스(agent-docs git-guard)에서 보호 브랜치 규칙을 빼고 계정 검사를 더한 축소판.
#   deny: 커밋 신원≠95hyun · 세션↔작업장 바인딩 위반 · 현재 브랜치와 다른 브랜치 push · 개인 계정 아닌 gh 쓰기
#   ask : 남의 repo push · force/삭제 push · 다른 세션이 쓰는 작업장에서 checkout/reset/clean/add -A
# 탈출구(명령 문자열에 포함): GIT_GUARD_REBIND=1 → 현 위치로 재바인딩 / GIT_GUARD_OK=1 → 1회 통과(사용자 승인 하에만).
# 항상 exit 0, 판단 불가 시 무개입 — 무관한 Bash 호출을 깨뜨리지 않는다.

ME_EMAIL="kingmandoo95@gmail.com"
ME_GH="95hyun"

INPUT=$(cat 2>/dev/null) || exit 0
[ -z "$INPUT" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$CMD" ] && exit 0
case "$CMD" in *git*|*gh*) ;; *) exit 0 ;; esac
case "$CMD" in *GIT_GUARD_OK=1*) exit 0 ;; esac

has() { printf '%s' "$CMD" | grep -qE "$1"; }
deny() { jq -cn --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'; exit 0; }
ask()  { jq -cn --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}'; exit 0; }

# ── gh: 회사 계정으로 PR·repo·release가 나가는 사고 방지 ──────────────────
# 전역 gh는 회사 계정이라, 워크스페이스 세션은 settings.json env.GH_CONFIG_DIR(개인 설정)로 분리한다.
if has '(^|[;&|(][[:space:]]*|[[:space:]])gh[[:space:]]+(pr|repo|release|issue|gist|api|workflow|secret)([[:space:]]|$)'; then
  GH_DIR=$(printf '%s' "$CMD" | grep -oE 'GH_CONFIG_DIR=[^[:space:]]+' | tail -1 | cut -d= -f2-)
  [ -z "$GH_DIR" ] && GH_DIR="$GH_CONFIG_DIR"
  [ -z "$GH_DIR" ] && [ -n "$CLAUDE_PROJECT_DIR" ] && \
    GH_DIR=$(jq -r '.env.GH_CONFIG_DIR // empty' "$CLAUDE_PROJECT_DIR/.claude/settings.json" 2>/dev/null)
  [ -z "$GH_DIR" ] && GH_DIR="$HOME/.config/gh"
  GH_DIR="${GH_DIR/#\~/$HOME}"
  # hosts.yml의 github.com 블록 최상위 user: = 활성 계정
  GH_USER=$(awk '/^github\.com:/{f=1;next} /^[^[:space:]]/{f=0} f && /^    user:/{print $2; exit}' "$GH_DIR/hosts.yml" 2>/dev/null)
  if [ "$GH_USER" != "$ME_GH" ]; then
    deny "[git-guard] gh 활성 계정이 '${GH_USER:-없음}'(설정: $GH_DIR) — 이 워크스페이스는 $ME_GH 전용. 사용자가 직접 '! GH_CONFIG_DIR=$GH_DIR gh auth login'으로 $ME_GH 로그인 후 재시도."
  fi
fi

# ── git 쓰기 명령 분류 ──────────────────────────────────────────────────────
G='git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+'
HAS_PUSH=;     has "${G}push([[:space:]]|$)" && HAS_PUSH=1
HAS_COMMIT=;   has "${G}commit([[:space:]]|$)" && HAS_COMMIT=1
HAS_SWITCH=;   has "${G}(checkout|switch)([[:space:]]|$)" && HAS_SWITCH=1
HAS_DESTROY=;  has "${G}(reset[[:space:]]+--hard|clean[[:space:]]+-[a-zA-Z]*f|restore[[:space:]])" && HAS_DESTROY=1
HAS_ADD=;      has "${G}add([[:space:]]|$)" && HAS_ADD=1
HAS_ADD_ALL=;  has "${G}add[[:space:]]+(-A|--all|\.)([[:space:]]|$)" && HAS_ADD_ALL=1
has "${G}commit[[:space:]]+-[a-zA-Z]*a" && HAS_ADD_ALL=1
[ -z "$HAS_PUSH$HAS_COMMIT$HAS_SWITCH$HAS_DESTROY$HAS_ADD" ] && exit 0

# 실행 디렉토리 추정: git -C > 마지막 cd > 세션 cwd
DIR=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
C_PATH=$(printf '%s' "$CMD" | grep -oE 'git[[:space:]]+-C[[:space:]]+[^[:space:]]+' | tail -1 | awk '{print $3}')
CD_PATH=$(printf '%s' "$CMD" | grep -oE '(^|&&|;)[[:space:]]*cd[[:space:]]+[^[:space:];&|]+' | tail -1 | sed -E 's/^(&&|;)?[[:space:]]*cd[[:space:]]+//')
[ -n "$CD_PATH" ] && DIR="$CD_PATH"
[ -n "$C_PATH" ] && DIR="$C_PATH"
DIR="${DIR/#\~/$HOME}"
[ -d "$DIR" ] || exit 0

TOP=$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -z "$TOP" ] && exit 0
COMMON=$(git -C "$DIR" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
[ -z "$COMMON" ] && COMMON="$TOP/.git"
BRANCH=$(git -C "$DIR" branch --show-current 2>/dev/null)

# ── 커밋 신원 ──────────────────────────────────────────────────────────────
if [ -n "$HAS_COMMIT" ]; then
  EMAIL=$(git -C "$DIR" config user.email 2>/dev/null)
  if [ "$EMAIL" != "$ME_EMAIL" ]; then
    deny "[git-guard] 커밋 신원이 '$EMAIL' — 이 워크스페이스는 $ME_EMAIL 전용. ~/.gitconfig includeIf(gitdir:<workspace>/)와 repo 로컬 user.email 덮어쓰기 여부를 확인(로컬 config로 땜질 금지)."
  fi
fi

# ── 세션↔작업장 바인딩 (병렬 세션 커밋 섞임 방지) ─────────────────────────
SESSION=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
STATE_DIR="$HOME/.claude/git-guard"
mkdir -p "$STATE_DIR" 2>/dev/null
find "$STATE_DIR" -name '*.tsv' -mtime +1 -delete 2>/dev/null
STATE="$STATE_DIR/$SESSION.tsv"   # 형식: <git-common-dir>\t<worktree-toplevel>
TAB=$(printf '\t')
touch "$STATE" 2>/dev/null

BOUND=$(grep -F "$COMMON$TAB" "$STATE" 2>/dev/null | head -1 | cut -f2)
case "$CMD" in
  *GIT_GUARD_REBIND=1*)
    grep -vF "$COMMON$TAB" "$STATE" > "$STATE.tmp" 2>/dev/null; mv -f "$STATE.tmp" "$STATE" 2>/dev/null
    printf '%s\t%s\n' "$COMMON" "$TOP" >> "$STATE" 2>/dev/null ;;
  *)
    if [ -n "$BOUND" ] && [ "$BOUND" != "$TOP" ]; then
      deny "[git-guard] 세션 바인딩 위반: 이 세션은 $BOUND 에서 작업 중인데 같은 repo의 다른 worktree($TOP)에 git 쓰기 감지. 의도된 전환이면 명령 앞에 GIT_GUARD_REBIND=1."
    fi
    [ -z "$BOUND" ] && printf '%s\t%s\n' "$COMMON" "$TOP" >> "$STATE" 2>/dev/null ;;
esac

OTHER=$(grep -lF "$COMMON$TAB$TOP" "$STATE_DIR"/*.tsv 2>/dev/null | grep -vF "$STATE" | head -1)
if [ -n "$OTHER" ] && [ -n "$HAS_DESTROY$HAS_SWITCH$HAS_ADD_ALL" ]; then
  ask "[git-guard] 다른 Claude 세션($(basename "$OTHER" .tsv | cut -c1-8)…)이 같은 작업장($TOP)을 사용 중 — checkout/reset/clean/add -A는 그 세션의 변경을 깨거나 흡수할 수 있음. 파일 명시 add 권장."
fi

# ── push ───────────────────────────────────────────────────────────────────
if [ -n "$HAS_PUSH" ]; then
  PUSH_SEG=$(printf '%s' "$CMD" | grep -oE 'git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+push[^;&|]*' | head -1)
  # 따옴표 제거: 문자열 인자 안의 push(테스트·echo)가 `HEAD"` 같은 refspec으로 오파싱되는 것 방지
  ARGS=$(printf '%s' "$PUSH_SEG" | tr -d "\"'" | sed -E 's/-C[[:space:]]+[^[:space:]]+//' | tr '[:space:]' '\n' | grep -v '^$' | grep -vE '^(git|push|-.*)$')
  REMOTE=$(printf '%s\n' "$ARGS" | head -1)
  if [ -n "$REMOTE" ] && git -C "$DIR" remote | grep -qx "$REMOTE"; then
    REFSPEC=$(printf '%s\n' "$ARGS" | sed -n 2p)
  else
    REFSPEC="$REMOTE"; REMOTE=origin
  fi

  URL=$(git -C "$DIR" remote get-url "$REMOTE" 2>/dev/null)
  OWNER=$(printf '%s' "$URL" | sed -nE 's#.*github\.com[:/]([^/]+)/.*#\1#p')
  if [ "$OWNER" != "$ME_GH" ]; then
    ask "[git-guard] push 대상 '$REMOTE'($URL)가 $ME_GH 소유가 아님 — 남의 repo로 push하려는 게 맞는지 확인."
  fi

  SRC="${REFSPEC%%:*}"; DST="${REFSPEC#*:}"; [ "$REFSPEC" = "$DST" ] && DST="$SRC"
  { [ -z "$REFSPEC" ] || [ "$SRC" = "HEAD" ]; } && SRC="$BRANCH"
  [ -n "$SRC" ] && git -C "$DIR" rev-parse -q --verify "refs/tags/$SRC" >/dev/null 2>&1 && SRC="$BRANCH"
  if [ -n "$SRC" ] && [ -n "$BRANCH" ] && [ "$SRC" != "$BRANCH" ]; then
    deny "[git-guard] 현재 브랜치($BRANCH)와 다른 브랜치($SRC) push — 병렬 세션 오push 방지. 'git push origin HEAD'를 쓰거나, 의도라면 사용자 승인 하에 GIT_GUARD_OK=1."
  fi
  printf '%s' "$PUSH_SEG" | grep -qE '(^|[[:space:]])(-f|--force|--force-with-lease[^[:space:]]*)([[:space:]]|$)' && \
    ask "[git-guard] force-push 감지 — 원격 이력을 덮어씀. 의도 확인."
  printf '%s' "$PUSH_SEG" | grep -qE '(^|[[:space:]])(--delete|-d)([[:space:]]|$)' && \
    ask "[git-guard] 원격 브랜치 삭제 push 감지 — 의도 확인."
fi

exit 0
