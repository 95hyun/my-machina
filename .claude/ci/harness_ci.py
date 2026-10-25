#!/usr/bin/env python3
"""my-machina 하네스 CI — 구조 정합 · hook 회귀 테스트 · 성능 예산(상시 컨텍스트, hook 지연).

사용: python3 .claude/ci/harness_ci.py [--base <git-ref>] [--summary <file>] [--replay [--replay-dir <dir>]]
  --base    비교 기준 커밋. 상시 바이트와 hook 지연의 변화량을 같이 보고한다(파일은 git 객체에서 읽어 체크아웃 불필요).
  --summary 마크다운 리포트를 쓸 경로(GitHub Actions의 $GITHUB_STEP_SUMMARY 등).
  --replay  로컬 전용: 과거 transcript의 git/gh 명령을 기준 ref(없으면 HEAD) git-guard와 현재 git-guard에 입력해 판정 비교(실행 안 함).
            --replay-dir로 transcript 디렉토리 지정.
표준 라이브러리만 사용 — macOS 기본 python3와 GitHub macos 러너에서 그대로 돈다.
"""
import argparse, glob, json, os, re, shutil, statistics, subprocess, sys, tempfile, time

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
CI = os.path.join(ROOT, ".claude", "ci")
BUDGET = json.load(open(os.path.join(CI, "budget.json"), encoding="utf-8"))
ME_EMAIL, ME_GH = "me@example.com", "me-gh"  # 샌드박스 가짜 계정 — 실제 계정에 의존하지 않는다

failures, warnings, report = [], [], []


def fail(msg): failures.append(msg)
def warn(msg): warnings.append(msg)
def rel(p): return os.path.relpath(p, ROOT)


def frontmatter(text):
    m = re.match(r"^---\n(.*?)\n---", text, re.S)
    if not m:
        return None
    d = {}
    for line in m.group(1).splitlines():
        if ":" in line and not line.startswith(" "):
            k, _, v = line.partition(":")
            d[k.strip()] = v.strip()
    return d


def read(p):
    with open(p, encoding="utf-8") as f:
        return f.read()


def git_show(ref, path):
    r = subprocess.run(["git", "-C", ROOT, "show", f"{ref}:{path}"], capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else None


# ── 1. 구조 정합 ─────────────────────────────────────────────────────────────
def lint():
    skills = sorted(glob.glob(os.path.join(ROOT, ".claude/skills/*/SKILL.md")))
    agents = sorted(glob.glob(os.path.join(ROOT, ".claude/agents/*.md")))
    hooks = sorted(glob.glob(os.path.join(ROOT, ".claude/hooks/*.sh")))
    agent_names = {os.path.splitext(os.path.basename(a))[0] for a in agents}

    for p in skills:
        d = frontmatter(read(p)) or {}
        name = os.path.basename(os.path.dirname(p))
        if d.get("name") != name:
            fail(f"{rel(p)}: frontmatter name '{d.get('name')}' ≠ 디렉토리 '{name}'")
        if not d.get("description"):
            fail(f"{rel(p)}: description 없음")
        if name in BUDGET["side_effect_skills"] and d.get("disable-model-invocation") != "true":
            fail(f"{rel(p)}: 부작용 스킬인데 disable-model-invocation: true 없음")
        # 같은 폴더 템플릿 참조 실존
        for ref in set(re.findall(r"`([\w.-]+-template\.md)`", read(p))):
            if not os.path.exists(os.path.join(os.path.dirname(p), ref)):
                fail(f"{rel(p)}: 참조 템플릿 {ref} 없음")

    for p in agents:
        d = frontmatter(read(p)) or {}
        stem = os.path.splitext(os.path.basename(p))[0]
        if d.get("name") != stem:
            fail(f"{rel(p)}: frontmatter name '{d.get('name')}' ≠ 파일명 '{stem}'")
        for key in ("description", "tools", "model"):
            if not d.get(key):
                fail(f"{rel(p)}: {key} 없음" + (" — 세션 모델을 상속함" if key == "model" else ""))

    # settings.json ↔ hooks 배선
    try:
        settings = json.load(open(os.path.join(ROOT, ".claude/settings.json"), encoding="utf-8"))
    except Exception as e:
        fail(f".claude/settings.json 파싱 실패: {e}")
        settings = {}
    wired = set()
    for groups in settings.get("hooks", {}).values():
        for g in groups:
            for h in g.get("hooks", []):
                for m in re.findall(r"\.claude/hooks/([\w.-]+\.sh)", h.get("command", "")):
                    wired.add(m)
    for m in wired:
        if not os.path.exists(os.path.join(ROOT, ".claude/hooks", m)):
            fail(f"settings.json이 없는 hook을 가리킴: {m}")
    for h in hooks:
        b = os.path.basename(h)
        if b not in wired:
            fail(f"{rel(h)}: settings.json에 배선되지 않은 hook(고아)")
        r = subprocess.run(["bash", "-n", h], capture_output=True, text=True)
        if r.returncode != 0:
            fail(f"{rel(h)}: bash 문법 오류 {r.stderr.strip()}")

    docs = [os.path.join(ROOT, "CLAUDE.md"), os.path.join(ROOT, "README.md")] + skills + agents
    hook_src = "".join(read(h) for h in hooks)
    status_vocab = set()
    for t in glob.glob(os.path.join(ROOT, ".claude/skills/*/*-template.md")):
        m = re.search(r"^status:\s*\S+\s*#\s*(.+)$", read(t), re.M)
        if m:
            status_vocab |= {s.strip() for s in m.group(1).split("→")}

    for p in docs:
        text = read(p)
        # @에이전트 언급 실존 (이메일·패키지 스코프 제외)
        for m in re.finditer(r"(?<![\w.])@([a-z][a-z0-9-]+)", text):
            if m.group(1) not in agent_names:
                fail(f"{rel(p)}: 없는 에이전트 @{m.group(1)} 참조")
        # hook 주입 태그는 실제로 어떤 hook이 주입해야 한다
        for tag in set(re.findall(r"\[([a-z]+-hint)\]", text)):
            if f"[{tag}]" not in hook_src:
                fail(f"{rel(p)}: [{tag}]를 주입하는 hook 없음")
        # 상태 어휘는 템플릿 정의 안에서만
        if status_vocab and ".claude/" in p:
            for s in re.findall(r"status:\s*`?([a-z][a-z-]+)`?", text):
                if s not in status_vocab:
                    fail(f"{rel(p)}: 템플릿에 없는 상태 '{s}' (정의: {' / '.join(sorted(status_vocab))})")

    # 워크스페이스 고정값 누수 (clone 위치 = 워크스페이스 루트)
    hack = [p for p in glob.glob(os.path.join(ROOT, "hackathon/**/*"), recursive=True) if os.path.isfile(p) and "/runs/" not in p]
    extra = [p for d in (".claude/skills", ".github") for p in glob.glob(os.path.join(ROOT, d, "**/*"), recursive=True)
             if os.path.isfile(p) and p not in skills and "__pycache__" not in p]
    for p in skills + agents + hooks + hack + extra + [os.path.join(ROOT, f) for f in ("CLAUDE.md", "README.md", ".claude/settings.json")]:
        if not os.path.exists(p) or rel(p) in BUDGET["path_leak_allow"]:
            continue
        for m in re.finditer(r"/Users/[\w.-]+|~/my-dev", read(p)):
            fail(f"{rel(p)}: 머신 고정 경로 '{m.group(0)}' — $CLAUDE_PROJECT_DIR·<workspace> 표기 사용")

    # 해커톤 스킬·에이전트·규칙이 가리키는 hackathon/ 경로가 실재해야 한다 (runs/ 산출물·<자리표시자> 제외)
    for p in skills + agents + [os.path.join(ROOT, "hackathon/RULES.md")]:
        if not os.path.exists(p):
            continue
        for m in set(re.findall(r"hackathon/(?:bin|templates)/[\w.-]+|hackathon/RULES\.md", read(p))):
            if not os.path.exists(os.path.join(ROOT, m)):
                fail(f"{rel(p)}: 없는 해커톤 경로 '{m}' 참조")


# ── 2. 상시 컨텍스트 비용 ────────────────────────────────────────────────────
def always_on(reader):
    """reader(path)->text|None. 매 세션 로드되는 바이트: CLAUDE.md + 자동 호출 가능한 스킬·에이전트 description."""
    cm = reader("CLAUDE.md") or ""
    desc = 0
    paths = [rel(p) for p in glob.glob(os.path.join(ROOT, ".claude/skills/*/SKILL.md")) + glob.glob(os.path.join(ROOT, ".claude/agents/*.md"))]
    for p in paths:
        t = reader(p)
        if t is None:
            continue
        d = frontmatter(t) or {}
        if d.get("disable-model-invocation") == "true":
            continue
        desc += len(d.get("description", "").encode())
    c = len(cm.encode())
    return {"CLAUDE.md": c, "descriptions": desc, "total": c + desc}


def budget_check(base_ref):
    cur = always_on(lambda p: read(os.path.join(ROOT, p)) if os.path.exists(os.path.join(ROOT, p)) else None)
    base = always_on(lambda p: git_show(base_ref, p)) if base_ref else None
    lim = BUDGET["always_on_bytes"]
    rows = []
    for k in ("CLAUDE.md", "descriptions", "total"):
        delta = f"{cur[k] - base[k]:+d}" if base else "—"
        ok = cur[k] <= lim[k]
        rows.append(f"| {k} | {cur[k]} | {delta} | {lim[k]} | {'✅' if ok else '❌'} |")
        if not ok:
            fail(f"상시 컨텍스트 예산 초과: {k} {cur[k]}B > {lim[k]}B")
    report.append("### 상시 컨텍스트 (bytes)\n| 항목 | 현재 | 변화 | 예산 | |\n|---|---|---|---|---|\n" + "\n".join(rows))


# ── 3. hook 회귀 테스트 + 지연 측정 (격리 샌드박스) ─────────────────────────
def sh(args, cwd=None, env=None):
    subprocess.run(args, cwd=cwd, env=env, check=True, capture_output=True, text=True)


def make_sandbox():
    sb = tempfile.mkdtemp(prefix="machina-ci-")
    home, ws = os.path.join(sb, "home"), os.path.join(sb, "ws")
    os.makedirs(home); os.makedirs(os.path.join(ws, ".claude"))
    env = {"HOME": home, "PATH": os.environ.get("PATH", "/usr/bin:/bin"), "GIT_CONFIG_NOSYSTEM": "1"}
    with open(os.path.join(home, ".gitconfig"), "w") as f:
        f.write(f"[user]\n\tname = {ME_GH}\n\temail = {ME_EMAIL}\n[init]\n\tdefaultBranch = main\n")
    gh_me, gh_corp = os.path.join(sb, "gh-me"), os.path.join(sb, "gh-corp")
    for d, user in ((gh_me, ME_GH), (gh_corp, "corp-account")):
        os.makedirs(d)
        with open(os.path.join(d, "hosts.yml"), "w") as f:
            f.write(f"github.com:\n    users:\n        {user}:\n    git_protocol: ssh\n    user: {user}\n")
    # 계정 값은 hook env로 주입(id_env). ws/.claude에는 설정 파일을 두지 않는다 — '미설정' 케이스가 이 ws를 쓴다

    def repo(name, remote, email=None):
        p = os.path.join(ws, name)
        os.makedirs(p)
        sh(["git", "init", "-q", "-b", "main"], p, env)
        if email:
            sh(["git", "config", "user.email", email], p, env)
        sh(["git", "commit", "-q", "--allow-empty", "-m", "init"], p, env)
        if remote:
            sh(["git", "remote", "add", "origin", remote], p, env)
        return p

    r = {
        "mine": repo("mine", f"git@github.com:{ME_GH}/mine.git"),
        "fork": repo("fork", "git@github.com:someone/fork.git"),
        "https": repo("https", "https://github.com/someone/https.git"),
        "corp": repo("corp", f"git@github.com:{ME_GH}/corp.git", email="me@company.example"),
    }
    wt = os.path.join(ws, "mine-wt")
    sh(["git", "-C", r["mine"], "worktree", "add", "-q", "-b", "wt", wt], None, env)
    r["mine-wt"] = wt
    return sb, home, ws, env, r, gh_me, gh_corp


def id_env(env, ws, gh_me):
    """기본 hook env: 계정 값(MACHINA_*·GH_CONFIG_DIR)을 프로세스 env로 주입."""
    return dict(env, CLAUDE_PROJECT_DIR=ws, MACHINA_EMAIL=ME_EMAIL, MACHINA_GH=ME_GH, GH_CONFIG_DIR=gh_me)


def run_hook(hook_path, payload, env):
    t0 = time.perf_counter()
    p = subprocess.run(["bash", hook_path], input=json.dumps(payload), env=env, capture_output=True, text=True)
    ms = (time.perf_counter() - t0) * 1000
    out = {}
    if p.stdout.strip():
        try:
            out = json.loads(p.stdout).get("hookSpecificOutput", {})
        except json.JSONDecodeError:
            fail(f"{os.path.basename(hook_path)}: JSON 아닌 출력 {p.stdout[:80]!r}")
    if p.returncode != 0:
        fail(f"{os.path.basename(hook_path)}: exit {p.returncode} (fail-open 위반) {p.stderr[:120]}")
    return out, ms


def hook_tests(sb, home, ws, env, r, gh_me, gh_corp):
    gg = os.path.join(ROOT, ".claude/hooks/git-guard.sh")
    rs = os.path.join(ROOT, ".claude/hooks/review-suggest.sh")
    henv = id_env(env, ws, gh_me)

    # 계정 값 변형 env — 새 케이스는 별도 session id(u*)로 기존 바인딩과 간섭하지 않는다
    assert not os.path.exists(os.path.join(home, ".config/gh")), "샌드박스 HOME에 전역 gh 설정이 있으면 '미설정' 케이스가 오염됨"
    ws_local = os.path.join(sb, "ws-local")  # 설정 파일에만 값이 있는 프로젝트 디렉토리 — hook은 파일을 읽지 않아야 한다
    os.makedirs(os.path.join(ws_local, ".claude"))
    with open(os.path.join(ws_local, ".claude/settings.local.json"), "w") as f:
        json.dump({"permissions": {"allow": []}, "env": {"MACHINA_EMAIL": ME_EMAIL, "MACHINA_GH": ME_GH, "GH_CONFIG_DIR": gh_me}}, f)
    with open(os.path.join(ws_local, ".claude/settings.json"), "w") as f:
        json.dump({"env": {"MACHINA_EMAIL": "wrong@example.com", "MACHINA_GH": "wrong-gh"}}, f)
    gh_someone = os.path.join(sb, "gh-someone")  # push owner 우회 시도용: fork 소유자 계정이 활성인 gh 설정
    os.makedirs(gh_someone)
    with open(os.path.join(gh_someone, "hosts.yml"), "w") as f:
        f.write("github.com:\n    users:\n        someone:\n    git_protocol: ssh\n    user: someone\n")
    home_g = os.path.join(sb, "home-globalgh")  # 전역 ~/.config/gh 폴백용 HOME
    os.makedirs(os.path.join(home_g, ".config/gh"))
    shutil.copy(os.path.join(home, ".gitconfig"), home_g)
    shutil.copy(os.path.join(gh_me, "hosts.yml"), os.path.join(home_g, ".config/gh"))
    envs = {
        "base": henv,
        "unset": dict(env, CLAUDE_PROJECT_DIR=ws),
        "local": dict(env, CLAUDE_PROJECT_DIR=ws_local),
        "ghdir": dict(env, CLAUDE_PROJECT_DIR=ws, GH_CONFIG_DIR=gh_me),
        "globalgh": dict(env, HOME=home_g, CLAUDE_PROJECT_DIR=ws),
        "corpdir": dict(henv, GH_CONFIG_DIR=gh_corp),  # env gh 설정이 회사 계정 — 접두로 개인 설정을 지정하는 경우
    }

    def g(cmd, cwd, sid="s1", ev="base"):
        out, _ = run_hook(gg, {"tool_input": {"command": cmd}, "cwd": cwd, "session_id": sid}, envs[ev])
        return out.get("permissionDecision", "allow")

    # (이름, 명령, cwd, session, 기대) — 순서 의존: 세션은 repo별 첫 git 쓰기 위치에 바인딩된다
    corp_git = os.path.join(r["corp"], ".git")
    cases = [
        ("무관한 명령", "ls -la", ws, "s1", "allow"),
        ("내 repo 커밋", "git commit -m x", r["mine"], "s1", "allow"),
        ("회사 신원 커밋", "git commit -m x", r["corp"], "s1", "deny"),
        ("내 repo push HEAD", "git push origin HEAD", r["mine"], "s1", "allow"),
        ("남의 repo push(ssh)", "git push origin HEAD", r["fork"], "s1", "deny"),
        ("남의 repo push(https)", "git push", r["https"], "s1", "deny"),
        ("남의 repo push + OK 접두(사용자 승인)", "GIT_GUARD_OK=1 git push origin HEAD", r["fork"], "s1", "allow"),
        ("다른 브랜치 push", "git push origin other", r["mine"], "s1", "deny"),
        ("다른 브랜치 push + OK 접두", "GIT_GUARD_OK=1 git push origin other", r["mine"], "s1", "allow"),
        ("OK가 접두가 아님(명령 끝)", "git push origin other GIT_GUARD_OK=1", r["mine"], "s1", "deny"),
        ("force push", "git push --force origin HEAD", r["mine"], "s1", "ask"),
        ("mirror push", "git push --mirror origin", r["mine"], "s1", "ask"),
        ("원격 브랜치 삭제(--delete)", "git push origin --delete old", r["mine"], "s1", "ask"),
        ("원격 브랜치 삭제(:ref)", "git push origin :old", r["mine"], "s1", "ask"),
        ("문자열 속 push(쌍따옴표)", 't x "git push origin HEAD"', r["mine"], "s1", "allow"),
        ("문자열 속 push(홑따옴표)", "echo 'git push origin HEAD'", r["mine"], "s1", "allow"),
        ("문자열 속 다른 브랜치 push", 'echo "git push origin feature-x"', r["mine"], "s1", "allow"),
        ("OK 접두로 신원 우회 불가", "GIT_GUARD_OK=1 git commit -m x", r["corp"], "s1", "deny"),
        ("메시지 속 OK로 신원 우회 불가", 'git commit -m "x GIT_GUARD_OK=1"', r["corp"], "s1", "deny"),
        ("-c user.email 위조", "git -c user.email=evil@corp.example commit -m x", r["mine"], "s1", "deny"),
        ("GIT_AUTHOR_EMAIL 위조", "GIT_AUTHOR_EMAIL=evil@corp.example git commit -m x", r["mine"], "s1", "deny"),
        ("--git-dir로 회사 repo 커밋", f"git --git-dir={corp_git} commit -m x", ws, "s1", "deny"),
        ("서브셸 cd로 회사 repo 커밋", f"(cd {r['corp']}; git commit -m x)", ws, "s1", "deny"),
        ("바인딩: 첫 쓰기", "git commit -m x", r["mine"], "s3", "allow"),
        ("바인딩 위반(같은 repo 다른 worktree)", "git commit -m x", r["mine-wt"], "s3", "deny"),
        ("메시지 속 REBIND로 우회 불가", 'git commit -m "GIT_GUARD_REBIND=1"', r["mine-wt"], "s3", "deny"),
        ("REBIND 접두(사용자 승인)", "GIT_GUARD_REBIND=1 git commit -m x", r["mine-wt"], "s3", "allow"),
        ("add -A 단독 세션", "git add -A", r["fork"], "s1", "allow"),
        ("add -A 타 세션 같은 작업장", "git add -A", r["fork"], "s2", "ask"),
        ("stash 타 세션 같은 작업장", "git stash", r["fork"], "s2", "ask"),
        ("stash list(읽기)", "git stash list", r["fork"], "s2", "allow"),
        ("gh 개인 설정", "gh pr list", ws, "s1", "allow"),
        ("gh 회사 설정 강제", f"GH_CONFIG_DIR={gh_corp} gh pr create", ws, "s1", "deny"),
        ("gh 회사 설정 + OK 접두도 불가", f"GIT_GUARD_OK=1 GH_CONFIG_DIR={gh_corp} gh pr create", ws, "s1", "deny"),
        ("gh 읽기(auth status)", "gh auth status", ws, "s1", "allow"),
        # 계정 값 미설정(env·로컬 파일·전역 gh 모두 없음): 신원·gh·owner 검사 생략, 브랜치 검사는 유지
        ("미설정: 다른 이메일 repo 커밋", "git commit -m x", r["corp"], "u1", "allow", "unset"),
        ("미설정: 회사 gh로 pr create", f"GH_CONFIG_DIR={gh_corp} gh pr create", ws, "u1", "allow", "unset"),
        ("미설정: 남의 repo push(owner 검사 생략)", "git push origin HEAD", r["fork"], "u1", "allow", "unset"),
        ("미설정: 다른 브랜치 push", "git push origin other", r["mine"], "u1", "deny", "unset"),
        # env 미주입 + settings*.json에만 값 있음 → 파일은 판정에 영향 없음(신원·gh·owner 검사 생략)
        ("env 미주입+파일만: 다른 이메일 repo 커밋", "git commit -m x", r["corp"], "u2", "allow", "local"),
        ("env 미주입+파일만: GIT_AUTHOR_EMAIL 위조", "GIT_AUTHOR_EMAIL=evil@corp.example git commit -m x", r["mine"], "u2", "allow", "local"),
        ("env 미주입+파일만: 회사 gh로 pr create", f"GH_CONFIG_DIR={gh_corp} gh pr create", ws, "u2", "allow", "local"),
        ("env 미주입+파일만: 남의 repo push(owner 검사 생략)", "git push origin HEAD", r["fork"], "u2", "allow", "local"),
        ("env 미주입+파일만: 다른 브랜치 push", "git push origin other", r["mine"], "u2", "deny", "local"),
        # gh 검사 접두 GH_CONFIG_DIR 따옴표 제거
        ("gh 접두 GH_CONFIG_DIR 쌍따옴표(개인)", f'GH_CONFIG_DIR="{gh_me}" gh pr create', ws, "s1", "allow", "corpdir"),
        ("gh 접두 GH_CONFIG_DIR 홑따옴표(개인)", f"GH_CONFIG_DIR='{gh_me}' gh pr create", ws, "s1", "allow", "corpdir"),
        # MACHINA_GH 미설정 → GH_CONFIG_DIR hosts.yml 활성 계정이 내 계정
        ("MACHINA_GH 없음+GH_CONFIG_DIR: 남의 repo push", "git push origin HEAD", r["fork"], "u3", "deny", "ghdir"),
        ("MACHINA_GH 없음+GH_CONFIG_DIR: 내 repo push", "git push origin HEAD", r["mine"], "u3", "allow", "ghdir"),
        ("MACHINA_GH 없음+GH_CONFIG_DIR: 다른 브랜치 push", "git push origin other", r["mine"], "u3", "deny", "ghdir"),
        ("MACHINA_GH 없음: 접두 GH_CONFIG_DIR(남의 계정)로 owner 우회 불가", f"GH_CONFIG_DIR={gh_someone} git push origin HEAD", r["fork"], "u3", "deny", "ghdir"),
        # 전부 미설정이지만 전역 ~/.config/gh가 있으면 그 활성 계정으로 owner 판정
        ("전역 gh 폴백: 남의 repo push", "git push origin HEAD", r["fork"], "u4", "deny", "globalgh"),
        ("전역 gh 폴백: 내 repo push", "git push origin HEAD", r["mine"], "u4", "allow", "globalgh"),
        ("전역 gh 폴백: 접두 GH_CONFIG_DIR(남의 계정)로 owner 우회 불가", f"GH_CONFIG_DIR={gh_someone} git push origin HEAD", r["fork"], "u4", "deny", "globalgh"),
    ]
    rows, bad = [], 0
    for name, cmd, cwd, sid, exp, *ev in cases:
        got = g(cmd, cwd, sid, *ev)
        ok = got == exp
        bad += not ok
        rows.append(f"| git-guard | {name} | {exp} | {got} | {'✅' if ok else '❌'} |")
        if not ok:
            fail(f"git-guard 회귀: '{name}' 기대 {exp}, 실제 {got}")

    def rv(path, sid="r1"):
        out, _ = run_hook(rs, {"tool_input": {"file_path": path}, "session_id": sid}, henv)
        return out.get("additionalContext", "")

    rcases = [
        ("워크스페이스 밖 파일", os.path.join(sb, "elsewhere.sh"), lambda o: o == ""),
        (".specs 문서", os.path.join(ws, "mine/.specs/a/spec.md"), lambda o: o == ""),
        ("비코드 파일", os.path.join(ws, "mine/README.md"), lambda o: o == ""),
        ("코드 파일 → 프로젝트명 힌트(go 4단계 정본)", os.path.join(ws, "mine/Sources/A.swift"), lambda o: "[review-hint] mine " in o and "go 스킬 4단계" in o),
        ("같은 프로젝트 재수정 dedup", os.path.join(ws, "mine/Sources/B.swift"), lambda o: o == ""),
        ("하네스 파일 → @harco 힌트", os.path.join(ws, ".claude/hooks/x.sh"), lambda o: "@harco" in o),
        ("권한·배포 설정 파일(tauri json)", os.path.join(ws, "fork/src-tauri/capabilities/default.json"), lambda o: "[review-hint] fork " in o),
    ]
    for name, path, check in rcases:
        o = rv(path)
        ok = check(o)
        bad += not ok
        rows.append(f"| review-suggest | {name} | — | {'(침묵)' if not o else o[:28] + '…'} | {'✅' if ok else '❌'} |")
        if not ok:
            fail(f"review-suggest 회귀: '{name}' 출력 {o[:60]!r}")
    qg = os.path.join(ROOT, ".claude/hooks/role-guard.sh")
    rep = os.path.join(ws, "mine/.specs/qa/reports/2026-01-01-a.md")
    src = os.path.join(ws, "mine/Sources/A.swift")
    sp = lambda p: os.path.join(ws, "mine/.specs", p)
    qcases = [
        ("qabot → 리포트 경로", {"agent_type": "qabot", "file_path": rep}, "allow"),
        ("qabot → recipe.md", {"agent_type": "qabot", "file_path": sp("qa/recipe.md")}, "deny"),
        ("qabot → reports/../ 우회", {"agent_type": "qabot", "file_path": sp("qa/reports/../recipe.md")}, "deny"),
        ("qabot → 소스", {"agent_type": "qabot", "file_path": src}, "deny"),
        ("pm → <slug>/intent.md", {"agent_type": "pm", "file_path": sp("app/intent.md")}, "allow"),
        ("pm → <slug>/research.md", {"agent_type": "pm", "file_path": sp("app/research.md")}, "allow"),
        ("pm → <slug>/design.md", {"agent_type": "pm", "file_path": sp("app/design.md")}, "deny"),
        ("pm → <slug>/spec.md", {"agent_type": "pm", "file_path": sp("app/spec.md")}, "deny"),
        ("pm → 소스", {"agent_type": "pm", "file_path": src}, "deny"),
        ("pm → qa/intent.md(qa는 slug 아님)", {"agent_type": "pm", "file_path": sp("qa/intent.md")}, "deny"),
        ("pm → _archive/<날짜-slug>/intent.md", {"agent_type": "pm", "file_path": sp("_archive/2026-01-01-app/intent.md")}, "deny"),
        ("pm → <slug>/../<slug>/ 우회", {"agent_type": "pm", "file_path": sp("app/../app/intent.md")}, "deny"),
        ("pm → 상대경로", {"agent_type": "pm", "file_path": ".specs/app/intent.md"}, "deny"),
        ("pm → NotebookEdit .ipynb", {"agent_type": "pm", "notebook_path": sp("app/x.ipynb")}, "deny"),
        ("pd → <slug>/design.md", {"agent_type": "pd", "file_path": sp("app/design.md")}, "allow"),
        ("pd → <slug>/design/flow.png", {"agent_type": "pd", "file_path": sp("app/design/flow.png")}, "allow"),
        ("pd → <slug>/intent.md", {"agent_type": "pd", "file_path": sp("app/intent.md")}, "deny"),
        ("pd → 소스", {"agent_type": "pd", "file_path": src}, "deny"),
        ("pd → <slug>/design.md.bak", {"agent_type": "pd", "file_path": sp("app/design.md.bak")}, "deny"),
        ("pd → /./ 세그먼트 우회", {"agent_type": "pd", "file_path": sp("app/./design.md")}, "deny"),
        ("메인 세션(agent_type 없음) → 소스", {"file_path": src}, "allow"),
        ("coder → 소스", {"agent_type": "coder", "file_path": src}, "allow"),
        ("pd → Artifact(env 없음)", {"agent_type": "pd", "tool": "Artifact"}, "deny"),
        ("pd → ArtifactComments(env 없음)", {"agent_type": "pd", "tool": "ArtifactComments"}, "deny"),
        ("pm → Artifact(env 없음)", {"agent_type": "pm", "tool": "Artifact"}, "deny"),
        ("pm → ArtifactComments(env 없음)", {"agent_type": "pm", "tool": "ArtifactComments"}, "deny"),
        ("pd → Artifact(MACHINA_PD_ARTIFACT=1, 소스 file_path)", {"agent_type": "pd", "tool": "Artifact", "file_path": src, "art": 1}, "allow"),
        ("qabot → Artifact(env 없음, 무개입)", {"agent_type": "qabot", "tool": "Artifact"}, "allow"),
        ("메인 세션(agent_type 없음) → Artifact", {"tool": "Artifact"}, "allow"),
        ("pd → ArtifactData(env 없음)", {"agent_type": "pd", "tool": "ArtifactData"}, "deny"),
        ("pm → Artifact(MACHINA_PD_ARTIFACT=1)", {"agent_type": "pm", "tool": "Artifact", "art": 1}, "allow"),
        ("pd → design/render/ 쓰기(조율자 렌더 결과)", {"agent_type": "pd", "file_path": sp("app/design/render/S1-x-mobile.png")}, "deny"),
        ("pd → design/screens/ 쓰기", {"agent_type": "pd", "file_path": sp("app/design/screens/S1-x.html")}, "allow"),
        ("pd → design//render/ 우회(// 표기)", {"agent_type": "pd", "file_path": sp("app/design//render/S1.png")}, "deny"),
        ("pd → design/Render/ 우회(대소문자)", {"agent_type": "pd", "file_path": sp("app/design/Render/S1.png")}, "deny"),
    ]
    for name, c, exp in qcases:
        payload = {"tool_input": {k: c[k] for k in ("file_path", "notebook_path") if k in c}, "session_id": "q1"}
        if "agent_type" in c:
            payload["agent_type"] = c["agent_type"]
        if "tool" in c:
            payload["tool_name"] = c["tool"]
        out, _ = run_hook(qg, payload, dict(henv, MACHINA_PD_ARTIFACT="1") if c.get("art") else henv)
        got = out.get("permissionDecision", "allow")
        ok = got == exp
        bad += not ok
        rows.append(f"| role-guard | {name} | {exp} | {got} | {'✅' if ok else '❌'} |")
        if not ok:
            fail(f"role-guard 회귀: '{name}' 기대 {exp}, 실제 {got}")
    row, ok = replay_selftest(sb, env, ws, r, gh_me)
    bad += not ok
    rows.append(row)
    report.append(f"### hook 회귀 테스트 ({len(rows) - bad}/{len(rows)})\n| hook | 케이스 | 기대 | 실제 | |\n|---|---|---|---|---|\n" + "\n".join(rows))


# ── 3b. hook 과거 명령 재생 (기준 ref hook vs 현재 hook) ─────────────────────
RANK = {"allow": 0, "ask": 1, "deny": 2}  # 클수록 차단 방향. 그 외 값은 ask와 같은 중간으로 본다


def extract_replay(src_dir):
    """transcript *.jsonl(최상위만)에서 git/gh 단어가 든 Bash 명령을 세션별 원래 순서로. 반환 {sid: [(cwd, cmd)]}."""
    sessions = {}
    for f in sorted(glob.glob(os.path.join(src_dir, "*.jsonl"))):
        try:
            lines = open(f, encoding="utf-8").read().splitlines()
        except OSError:
            continue
        for line in lines:
            try:
                d = json.loads(line)
            except ValueError:
                continue
            content = (d.get("message") or {}).get("content") if d.get("type") == "assistant" else None
            if not isinstance(content, list):
                continue
            for c in content:
                if not (isinstance(c, dict) and c.get("type") == "tool_use" and c.get("name") == "Bash"):
                    continue
                cmd = (c.get("input") or {}).get("command") or ""
                if not re.search(r"\b(git|gh)\b", cmd):
                    continue
                sid = d.get("sessionId") or "unknown"
                sessions.setdefault(sid, []).append((d.get("timestamp") or "", d.get("cwd") or "", cmd))
    out = {}
    for sid, items in sessions.items():
        items.sort(key=lambda x: x[0])  # 안정 정렬 — 같은 timestamp(한 메시지의 병렬 호출)는 원래 순서 유지
        seq = []
        for _, cwd, cmd in items:
            if not seq or seq[-1] != (cwd, cmd):
                seq.append((cwd, cmd))
        out[sid] = seq
    return out


def replay(sessions, base_hook, cur_hook, env, gitconfig):
    """양쪽 hook에 같은 입력·순서를 넣어 판정 목록 반환. 명령은 실행하지 않는다.
    세션마다 별도 임시 HOME — 공유 HOME을 병렬로 쓰면 타 세션 바인딩(ask) 판정이 실행 타이밍에 따라 흔들린다."""
    from concurrent.futures import ThreadPoolExecutor
    root = tempfile.mkdtemp(prefix="machina-replay-")
    try:
        def run(side, hook, idx, sid):
            home = os.path.join(root, side, str(idx))
            os.makedirs(home)
            if gitconfig is not None:
                with open(os.path.join(home, ".gitconfig"), "w") as f:
                    f.write(gitconfig)
            henv = dict(env, HOME=home)
            res = []
            for cwd, cmd in sessions[sid]:
                out, _ = run_hook(hook, {"tool_input": {"command": cmd}, "cwd": cwd, "session_id": sid}, henv)
                res.append(out.get("permissionDecision", "allow"))
            return res

        sids = list(sessions)
        with ThreadPoolExecutor(max_workers=max(2, os.cpu_count() or 2)) as ex:
            futs = {(side, sid): ex.submit(run, side, hook, i, sid)
                    for side, hook in (("base", base_hook), ("cur", cur_hook)) for i, sid in enumerate(sids)}
            decided = {k: f.result() for k, f in futs.items()}
    finally:
        shutil.rmtree(root, ignore_errors=True)
    return [(sid, cwd, cmd, b, c) for sid in sids
            for (cwd, cmd), b, c in zip(sessions[sid], decided[("base", sid)], decided[("cur", sid)])]


def replay_diff(results):
    """(차단 방향 변화, 완화 변화)."""
    tighter = [x for x in results if RANK.get(x[4], 1) > RANK.get(x[3], 1)]
    looser = [x for x in results if RANK.get(x[4], 1) < RANK.get(x[3], 1)]
    return tighter, looser


def replay_selftest(sb, env, ws, r, gh_me):
    """재생 검사기가 신규 차단을 실제로 잡는지: 가짜 transcript + 'push면 무조건 deny' 변형 hook."""
    d = tempfile.mkdtemp(prefix="replay-self-", dir=sb)
    with open(os.path.join(d, "fake.jsonl"), "w") as f:
        for cmd, cwd in (("git push origin HEAD", r["mine"]), ("ls", ws)):
            f.write(json.dumps({"type": "assistant", "cwd": cwd, "sessionId": "replay-self", "timestamp": "",
                                "message": {"content": [{"type": "tool_use", "name": "Bash", "input": {"command": cmd}}]}}) + "\n")
    gg = os.path.join(ROOT, ".claude/hooks/git-guard.sh")
    src = read(gg).split("\n", 1)
    # 입력을 읽어 판정한 뒤 stdin을 되돌려 원본 본문이 그대로 이어서 돌게 한다
    inject = ('INPUT=$(cat)\n'
              'case "$INPUT" in *"git push"*) echo \'{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"mutant"}}\'; exit 0 ;; esac\n'
              'exec 0<<<"$INPUT"\n')
    mut = os.path.join(d, "git-guard-mutant.sh")
    with open(mut, "w") as f:
        f.write(src[0] + "\n" + inject + src[1])
    sandbox_cfg = read(os.path.join(sb, "home", ".gitconfig"))
    henv = {k: v for k, v in id_env(env, ws, gh_me).items() if k != "HOME"}
    results = replay(extract_replay(d), gg, mut, henv, sandbox_cfg)
    tighter, _ = replay_diff(results)
    got = sum(1 for x in tighter if x[3] == "allow" and x[4] == "deny")
    ok = len(results) == 1 and got == 1 and len(tighter) == 1
    if not ok:
        fail(f"재생 자체 검증: 변형 hook의 allow→deny 1건을 못 잡음(재생 {len(results)}건, 포착 {got}건, 차단 변화 {len(tighter)}건)")
    return f"| replay | 변형 hook(push 무조건 deny) → allow→deny 포착 | 1 | {got} | {'✅' if ok else '❌'} |", ok


def replay_check(base_ref, src_dir):
    title = "### hook 재생 (과거 명령)"
    if not os.path.isdir(src_dir):
        warn(f"재생 생략 — transcript 디렉토리 없음 ({src_dir})")
        return
    sessions = extract_replay(src_dir)
    total = sum(len(v) for v in sessions.values())
    if not total:
        warn(f"재생 생략 — git/gh 명령 0건 ({src_dir})")
        return
    ref = base_ref or "HEAD"
    src = git_show(ref, ".claude/hooks/git-guard.sh")
    if src is None:
        warn(f"재생 생략 — 기준 ref '{ref}'에 git-guard.sh 없음")
        return
    real_home = os.path.expanduser("~")
    gitconfig = None
    gc = os.path.join(real_home, ".gitconfig")
    if os.path.exists(gc):
        # 임시 HOME에서도 includeIf gitdir:~/…·path = ~/… 가 실제 경로를 가리키도록 전개
        gitconfig = re.sub(r'(^|[\s=:"\'])~(?=/)', lambda m: m.group(1) + real_home, read(gc), flags=re.M)
    env = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "CLAUDE_PROJECT_DIR": ROOT}
    try:
        lenv = json.load(open(os.path.join(ROOT, ".claude/settings.local.json"), encoding="utf-8")).get("env", {})
    except (OSError, ValueError):
        lenv = {}
    for k in ("MACHINA_EMAIL", "MACHINA_GH", "GH_CONFIG_DIR"):
        if lenv.get(k):
            env[k] = re.sub(r"^~(?=/|$)", real_home, lenv[k])
    base_dir = tempfile.mkdtemp(prefix="machina-replay-base-")
    try:
        bp = os.path.join(base_dir, "git-guard.sh")
        with open(bp, "w") as f:
            f.write(src)
        t0 = time.perf_counter()
        results = replay(sessions, bp, os.path.join(ROOT, ".claude/hooks/git-guard.sh"), env, gitconfig)
        secs = time.perf_counter() - t0
    finally:
        shutil.rmtree(base_dir, ignore_errors=True)

    def dist(i):
        c = {}
        for x in results:
            c[x[i]] = c.get(x[i], 0) + 1
        return ", ".join(f"{k} {c[k]}" for k in sorted(c, key=lambda k: (RANK.get(k, 1), k)))

    tighter, looser = replay_diff(results)
    if tighter:
        fail(f"hook 재생: 기준 `{ref}` 대비 신규 차단 {len(tighter)}건 (변화 표 참고)")
    if looser:
        warn(f"hook 재생: 기준 `{ref}` 대비 완화 {len(looser)}건 (변화 표 참고)")
    injected = [k for k in ("MACHINA_EMAIL", "MACHINA_GH", "GH_CONFIG_DIR") if k in env]
    lines = [title,
             f"- 소스: transcript 최상위 *.jsonl (subagents 제외) · 재생 {total}건 · 세션 {len(sessions)}개 · 소요 {secs:.1f}s",
             f"- 신원 재현: ~/.gitconfig {'사본(~ 전개)' if gitconfig is not None else '없음'} · env 주입 {', '.join(injected) or '없음'}",
             f"- 기준(`{ref}`) 판정: {dist(3)}",
             f"- 현재 판정: {dist(4)}"]
    changes = tighter + looser
    if changes:
        lines.append("\n| 세션 | 기준 | 현재 | 명령 |\n|---|---|---|---|")
        for sid, _, cmd, b, c in changes[:30]:
            short = " ".join(cmd.split())[:120].replace("|", "\\|").replace("`", "'")
            lines.append(f"| {sid[:8]} | {b} | {c} | `{short}` |")
        if len(changes) > 30:
            lines.append(f"\n외 {len(changes) - 30}건")
    else:
        lines.append("- 판정 변화 0건")
    report.append("\n".join(lines))


def doctor_tests(sb, env, gh_me):
    """doctor.sh: 문법 + 샌드박스 워크스페이스(이 repo의 .claude 사본 + 최소 hackathon + 하위 repo 1개)에서 exit code."""
    src = os.path.join(ROOT, ".claude/skills/doctor/doctor.sh")
    rows, bad = [], 0

    def row(name, exp, got, detail=""):
        nonlocal bad
        ok = exp == got
        bad += not ok
        rows.append(f"| doctor | {name} | {exp} | {got} | {'✅' if ok else '❌'} |")
        if not ok:
            fail(f"doctor 회귀: '{name}' 기대 {exp}, 실제 {got} {detail}".rstrip())

    if not os.path.exists(src):
        fail("doctor.sh 없음: .claude/skills/doctor/doctor.sh")
        return
    r = subprocess.run(["bash", "-n", src], capture_output=True, text=True)
    row("bash -n", "ok", "ok" if r.returncode == 0 else "error", r.stderr.strip()[:120])

    dws = os.path.join(sb, "doctor-ws")
    # 개인 파일·작업 임시물은 복사하지 않는다 — 새 clone과 같은 조건
    shutil.copytree(os.path.join(ROOT, ".claude"), os.path.join(dws, ".claude"),
                    ignore=shutil.ignore_patterns("settings.local.json", "tmp", "__pycache__"))
    hk = os.path.join(dws, "hackathon")
    for d in ("bin", "templates", "runs"):
        os.makedirs(os.path.join(hk, d))
    for b in ("newrun", "mark", "ideas", "share"):
        bp = os.path.join(hk, "bin", b)
        open(bp, "w").write("#!/bin/bash\n")
        os.chmod(bp, 0o755)
    for t in ("input-card", "onepager", "rubric", "final"):
        open(os.path.join(hk, "templates", f"{t}.md"), "w").write("x\n")
    open(os.path.join(hk, "RULES.md"), "w").write("x\n")
    sh(["git", "init", "-q", "-b", "main"], dws, env)
    sub = os.path.join(dws, "app")
    os.makedirs(sub)
    sh(["git", "init", "-q", "-b", "main"], sub, env)

    denv = dict(env, CLAUDE_PROJECT_DIR=dws, MACHINA_EMAIL=ME_EMAIL, MACHINA_GH=ME_GH, GH_CONFIG_DIR=gh_me)
    dsh = os.path.join(dws, ".claude/skills/doctor/doctor.sh")

    def run():
        p = subprocess.run(["bash", dsh], env=denv, capture_output=True, text=True, timeout=30)
        return p.returncode, p.stdout

    code, out = run()
    row("정상 워크스페이스(MACHINA_* env) → exit 0", 0, code, out.strip()[-300:])
    sh(["git", "config", "user.email", "other@company.example"], sub, env)
    code, out = run()
    got = code if "❌ 계정(커밋 신원)" in out else f"{code}(신원 ❌ 없음)"
    row("하위 repo user.email ≠ MACHINA_EMAIL → exit 1 + 신원 ❌", 1, got, out.strip()[-300:])
    report.append(f"### doctor ({len(rows) - bad}/{len(rows)})\n| 대상 | 케이스 | 기대 | 실제 | |\n|---|---|---|---|---|\n" + "\n".join(rows))


def latency(hook_path, payload, env, n=15):
    """payload가 함수면 회차별로 새 입력을 만든다(dedup 경로를 피해 주입 경로를 재기 위해)."""
    mk = payload if callable(payload) else (lambda i: payload)
    run_hook(hook_path, mk(-1), env)  # 워밍업
    return statistics.median(run_hook(hook_path, mk(i), env)[1] for i in range(n))


def latency_check(ws, env, r, gh_me, base_ref):
    henv = id_env(env, ws, gh_me)  # 기본 케이스와 같은 조건(계정 값 env 주입 → jq 폴백 0회)
    scen = {
        "git-guard.sh:noop": ("git-guard.sh", {"tool_input": {"command": "ls -la"}, "cwd": ws, "session_id": "lat"}),
        "git-guard.sh:git": ("git-guard.sh", {"tool_input": {"command": "git commit -m x"}, "cwd": r["mine"], "session_id": "lat"}),
        "review-suggest.sh:noop": ("review-suggest.sh", {"tool_input": {"file_path": os.path.join(ws, "mine/README.md")}, "session_id": "lat"}),
        "review-suggest.sh:hit": ("review-suggest.sh", lambda i: {"tool_input": {"file_path": os.path.join(ws, "mine/A.swift")}, "session_id": f"lat-hit-{i}"}),
        "role-guard.sh:noop": ("role-guard.sh", {"tool_input": {"file_path": os.path.join(ws, "mine/A.swift")}, "session_id": "lat"}),
        "role-guard.sh:deny": ("role-guard.sh", {"tool_input": {"file_path": os.path.join(ws, "mine/A.swift")}, "agent_type": "qabot", "session_id": "lat"}),
    }
    base_dir = tempfile.mkdtemp(prefix="machina-base-") if base_ref else None
    lim, ratio, rows = BUDGET["hook_latency_ms_median"], BUDGET["latency_regression_ratio"], []
    for key, (hook, payload) in scen.items():
        cur = latency(os.path.join(ROOT, ".claude/hooks", hook), payload, henv)
        base_ms = None
        if base_dir:
            src = git_show(base_ref, f".claude/hooks/{hook}")
            if src:
                bp = os.path.join(base_dir, hook)
                open(bp, "w").write(src)
                base_ms = latency(bp, payload, henv)
        ok = cur <= lim[key]
        delta = f"{cur / base_ms:.2f}×" if base_ms else "—"
        if base_ms and cur > base_ms * ratio and cur - base_ms > 20:
            fail(f"hook 지연 회귀: {key} {base_ms:.0f}ms → {cur:.0f}ms (>{ratio}×)")
        if not ok:
            fail(f"hook 지연 예산 초과: {key} 중앙값 {cur:.0f}ms > {lim[key]}ms")
        rows.append(f"| {key} | {cur:.0f} | {delta} | {lim[key]} | {'✅' if ok else '❌'} |")
    if base_dir:
        shutil.rmtree(base_dir, ignore_errors=True)
    report.append("### hook 지연 (ms, 중앙값 15회)\n| 시나리오 | 현재 | 기준 대비 | 예산 | |\n|---|---|---|---|---|\n" + "\n".join(rows))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base")
    ap.add_argument("--summary")
    ap.add_argument("--replay", action="store_true")
    ap.add_argument("--replay-dir")
    a = ap.parse_args()
    base = a.base if a.base and git_show(a.base, "CLAUDE.md") is not None else None
    if a.base and not base:
        warn(f"기준 ref '{a.base}'를 읽을 수 없어 변화량 비교를 생략")

    for tool in ("jq", "git", "bash"):
        if not shutil.which(tool):
            fail(f"필수 도구 없음: {tool}")
    lint()
    budget_check(base)
    sb, home, ws, env, r, gh_me, gh_corp = make_sandbox()
    try:
        hook_tests(sb, home, ws, env, r, gh_me, gh_corp)
        latency_check(ws, env, r, gh_me, base)
        doctor_tests(sb, env, gh_me)
    finally:
        shutil.rmtree(sb, ignore_errors=True)
    if a.replay:
        # transcript 디렉토리 = ~/.claude/projects/<워크스페이스 절대경로의 '/'를 '-'로>
        replay_check(base, a.replay_dir or os.path.join(os.path.expanduser("~"), ".claude", "projects", re.sub(r"[^A-Za-z0-9]", "-", ROOT)))

    head = f"## my-machina harness CI — {'❌ 실패 ' + str(len(failures)) + '건' if failures else '✅ 통과'}"
    if base:
        head += f" (기준: `{base}`)"
    body = [head]
    if failures:
        body.append("### 실패\n" + "\n".join(f"- {f}" for f in failures))
    if warnings:
        body.append("### 경고\n" + "\n".join(f"- {w}" for w in warnings))
    body += report
    md = "\n\n".join(body) + "\n"
    print(md)
    if a.summary:
        with open(a.summary, "a", encoding="utf-8") as f:
            f.write(md)
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
