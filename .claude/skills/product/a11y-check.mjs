#!/usr/bin/env node
// a11y-check.mjs — /product PD 로컬 디자인(screens/*.html)의 접근성·반응형 자동 점검(텍스트 대비·터치 영역·가로 넘침)
// 사용: node a11y-check.mjs <design 디렉토리>   출력: <design>/render/a11y.json + 화면별 요약 1줄(stdout)
// exit: 0 = 검사 완료(위반이 있어도 0 — 판정은 판정자 몫) / 1 = 입력 오류·검사 실패 / 2 = node 버전 부족·브라우저 없음
// 의존성 0: 설치된 Chrome/Edge 헤드리스를 Node 내장 WebSocket으로 CDP 제어. render.sh와 같은 네트워크 차단·임시 프로필.
// 한계: 대비는 자체 계산(조상의 첫 불투명 배경색만) — 이미지·그라데이션·반투명 겹침·opacity는 판정불가로 분리, 겹쳐 놓인 형제 요소는 못 본다.

import { spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const SCREEN_TIMEOUT_MS = 20000;
const WIDTHS = [320, 390, 768, 1280];
const HEIGHT = 900;
const BASE_WIDTH = 390; // 대비·터치는 모바일 폭에서 본다(터치 영역이 의미 있는 폭)

const fail = (code, msg) => { console.error(`a11y: ${msg}`); process.exit(code); };

if (typeof globalThis.WebSocket !== 'function') fail(2, `Node ${process.version}에 전역 WebSocket이 없음(v22+ 필요) — 접근성 점검 불가`);

const DIR = process.argv[2];
if (!DIR || !fs.existsSync(path.join(DIR, 'screens')) || !fs.statSync(path.join(DIR, 'screens')).isDirectory())
  fail(1, `'${DIR ?? ''}/screens' 디렉토리가 없습니다`);
// 이전 회차 결과가 남아 실패·폴백 때 판정자가 옛 위반을 근거로 쓰지 않게 가장 먼저 지운다
try { fs.rmSync(path.join(DIR, 'render', 'a11y.json'), { force: true }); } catch {}
const screens = fs.readdirSync(path.join(DIR, 'screens')).filter((f) => f.endsWith('.html')).sort();
if (screens.length === 0) fail(1, 'screens/*.html이 없습니다');

// 브라우저 탐색 — render.sh와 같은 순서·override
const isExec = (p) => { try { fs.accessSync(p, fs.constants.X_OK); return fs.statSync(p).isFile(); } catch { return false; } };
const which = (name) => (process.env.PATH || '').split(path.delimiter).map((d) => path.join(d, name)).find(isExec) || '';
let BROWSER = process.env.MACHINA_RENDER_BROWSER || '';
if (!BROWSER) {
  BROWSER = ['/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge',
    '/Applications/Chromium.app/Contents/MacOS/Chromium',
    which('google-chrome'), which('chromium')].find((c) => c && isExec(c)) || '';
}
if (!BROWSER || !isExec(BROWSER)) fail(2, '헤드리스 브라우저 없음 — 접근성 점검 불가');

const OUT = path.join(DIR, 'render');
try { fs.mkdirSync(OUT, { recursive: true }); } catch (e) { fail(1, `${OUT} 생성 실패 — ${e.message}`); }

// ── 브라우저 수명: 어떤 경로로 끝나든 프로세스 그룹 kill + 프로필 삭제 ──
const PROF = fs.mkdtempSync(path.join(os.tmpdir(), 'machina-a11y-'));
let child = null;
const cleanupSync = () => {
  // detached로 띄워 렌더러·GPU 자식까지 그룹째 죽인다
  if (child && child.exitCode === null && child.signalCode === null) { try { process.kill(-child.pid, 'SIGKILL'); } catch {} }
  try { fs.rmSync(PROF, { recursive: true, force: true }); } catch {}
};
process.on('exit', cleanupSync);
for (const sig of ['SIGINT', 'SIGTERM', 'SIGHUP']) process.on(sig, () => process.exit(1));

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const withTimeout = (p, ms, what) => {
  let t;
  return Promise.race([p, new Promise((_, rej) => { t = setTimeout(() => rej(new Error(`${what} 시간 초과(${ms / 1000}초)`)), ms); })])
    .finally(() => clearTimeout(t));
};

async function launch() {
  child = spawn(BROWSER, ['--headless=new', '--disable-gpu', '--hide-scrollbars', '--no-first-run', '--no-default-browser-check',
    '--proxy-server=127.0.0.1:9', '--proxy-bypass-list=<-loopback>', // 원격 요청 송신 경로가 되지 않게(loopback 포함) 죽은 프록시로
    `--user-data-dir=${PROF}`, '--remote-debugging-port=0', 'about:blank'], { detached: true, stdio: 'ignore' });
  child.on('error', () => {});
  const portFile = path.join(PROF, 'DevToolsActivePort');
  for (let i = 0; i < 100; i++) {
    if (child.exitCode !== null || child.signalCode !== null) throw new Error('브라우저가 바로 종료됨');
    try {
      const [port, wsPath] = fs.readFileSync(portFile, 'utf8').split('\n');
      if (port && wsPath) return `ws://127.0.0.1:${port.trim()}${wsPath.trim()}`;
    } catch {}
    await sleep(100);
  }
  throw new Error('DevToolsActivePort가 10초 안에 생기지 않음');
}

async function shutdown(cdp) {
  if (cdp) { try { await withTimeout(cdp.send('Browser.close'), 2000, 'Browser.close'); } catch {} cdp.close(); }
  for (let i = 0; i < 20 && child && child.exitCode === null && child.signalCode === null; i++) await sleep(100);
  cleanupSync();
}

// ── 최소 CDP 클라이언트(flatten 세션) ──
function connect(url) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(url);
    let id = 0;
    const pending = new Map();
    const listeners = new Set();
    const cdp = {
      send(method, params = {}, sessionId) {
        return new Promise((res, rej) => {
          const msgId = ++id;
          pending.set(msgId, { res, rej, method });
          ws.send(JSON.stringify({ id: msgId, method, params, ...(sessionId ? { sessionId } : {}) }));
        });
      },
      waitFor(method, sessionId) {
        return new Promise((res) => {
          const l = (m) => { if (m.method === method && m.sessionId === sessionId) { listeners.delete(l); res(m.params); } };
          listeners.add(l);
        });
      },
      close() { try { ws.close(); } catch {} },
    };
    ws.onopen = () => resolve(cdp);
    ws.onerror = () => reject(new Error('CDP WebSocket 연결 실패'));
    ws.onclose = () => { for (const p of pending.values()) p.rej(new Error('CDP 연결 끊김')); pending.clear(); };
    ws.onmessage = (ev) => {
      const m = JSON.parse(ev.data);
      if (m.id !== undefined) {
        const p = pending.get(m.id);
        if (!p) return;
        pending.delete(m.id);
        m.error ? p.rej(new Error(`${p.method}: ${m.error.message}`)) : p.res(m.result);
      } else for (const l of [...listeners]) l(m);
    };
  });
}

// ── 페이지 안에서 실행할 검사 ──
const PAGE_LIB = String.raw`
const sel = (el) => {
  let s = el.tagName.toLowerCase();
  if (el.id) s += '#' + el.id;
  const cls = typeof el.className === 'string' ? el.className.trim().split(/\s+/).filter(Boolean).slice(0, 2) : [];
  return s + cls.map((c) => '.' + c).join('');
};
const visible = (el) => {
  const r = el.getBoundingClientRect();
  return r.width > 0 && r.height > 0 && el.checkVisibility({ opacityProperty: true, visibilityProperty: true });
};
`;

const OVERFLOW_JS = `(async () => {
${PAGE_LIB}
  await new Promise((r) => { requestAnimationFrame(() => requestAnimationFrame(r)); setTimeout(r, 300); });
  const vw = innerWidth, sw = document.documentElement.scrollWidth;
  if (sw <= vw) return null;
  const over = new Set([...document.body.querySelectorAll('*')].filter((el) => {
    const r = el.getBoundingClientRect();
    return r.width > 0 && (r.right > vw + 0.5 || r.left < -0.5);
  }));
  const top = [...over].filter((el) => !over.has(el.parentElement)).slice(0, 3).map(sel);
  return { scrollWidth: sw, innerWidth: vw, top };
})()`;

const BASE_JS = `(() => {
${PAGE_LIB}
  const ctx = Object.assign(document.createElement('canvas'), { width: 1, height: 1 }).getContext('2d', { willReadFrequently: true });
  const cache = new Map();
  // 캔버스로 정규화 — computed color가 rgb()가 아닌 oklch()·color() 등으로 와도 sRGB로 받는다
  const rgba = (str) => {
    if (cache.has(str)) return cache.get(str);
    ctx.clearRect(0, 0, 1, 1); ctx.fillStyle = '#000'; ctx.fillStyle = str; ctx.fillRect(0, 0, 1, 1);
    const [r, g, b, a] = ctx.getImageData(0, 0, 1, 1).data;
    const v = { r, g, b, a: a / 255 };
    cache.set(str, v);
    return v;
  };
  const lum = ({ r, g, b }) => {
    const f = (c) => { c /= 255; return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4; };
    return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b);
  };
  const hex = ({ r, g, b }) => '#' + [r, g, b].map((c) => c.toString(16).padStart(2, '0')).join('');
  const violations = [], undetermined = [];

  // 1. 텍스트 대비
  const owners = new Set();
  const tw = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
  for (let n; (n = tw.nextNode());) if (n.nodeValue.trim() && n.parentElement) owners.add(n.parentElement);
  for (const el of owners) {
    if (['SCRIPT', 'STYLE', 'NOSCRIPT', 'TEMPLATE'].includes(el.tagName) || !visible(el)) continue;
    const cs = getComputedStyle(el);
    const text = [...el.childNodes].filter((c) => c.nodeType === 3).map((c) => c.nodeValue).join('').trim().replace(/\\s+/g, ' ').slice(0, 24);
    let bg = null, why = null;
    for (let a = el; a; a = a.parentElement) {
      const s = getComputedStyle(a);
      if (parseFloat(s.opacity) < 1) { why = 'opacity ' + s.opacity + ' (' + sel(a) + ')'; break; }
      if (bg) continue; // 배경은 찾았고 위쪽 opacity만 확인 중
      if (s.backgroundImage !== 'none') { why = '배경 이미지·그라데이션 (' + sel(a) + ')'; break; }
      const c = rgba(s.backgroundColor);
      if (c.a >= 1) bg = c;
      else if (c.a > 0) { why = '반투명 배경 겹침 (' + sel(a) + ')'; break; }
    }
    if (why) { undetermined.push({ type: 'undetermined', selector: sel(el), detail: '"' + text + '" — ' + why }); continue; }
    bg = bg || { r: 255, g: 255, b: 255, a: 1 }; // 끝까지 투명이면 캔버스 기본 흰색
    let fg = rgba(cs.color);
    if (fg.a < 1) fg = { r: Math.round(fg.r * fg.a + bg.r * (1 - fg.a)), g: Math.round(fg.g * fg.a + bg.g * (1 - fg.a)), b: Math.round(fg.b * fg.a + bg.b * (1 - fg.a)), a: 1 };
    const L1 = lum(fg), L2 = lum(bg);
    const ratio = (Math.max(L1, L2) + 0.05) / (Math.min(L1, L2) + 0.05);
    const size = parseFloat(cs.fontSize), bold = parseInt(cs.fontWeight, 10) >= 700;
    const large = size >= 24 || (size >= 18.66 && bold);
    const need = large ? 3 : 4.5;
    if (ratio < need) violations.push({ type: 'contrast', selector: sel(el),
      detail: ratio.toFixed(2) + ':1 < ' + need + ':1 (' + hex(fg) + ' on ' + hex(bg) + ', ' + size + 'px' + (bold ? ' bold' : '') + ') "' + text + '"' });
  }

  // 2. 터치 영역
  for (const el of document.querySelectorAll('a, button, input, select, textarea, [role=button], [onclick]')) {
    if (!visible(el)) continue;
    // WCAG 2.5.8 inline 예외: 문장 안의 인라인 링크(같은 블록에 링크 밖 텍스트가 있음)는 줄 높이에 묶이므로 제외
    if (el.tagName === 'A' && getComputedStyle(el).display === 'inline') {
      let blk = el.parentElement;
      while (blk && getComputedStyle(blk).display.startsWith('inline')) blk = blk.parentElement;
      if (blk && blk.textContent.replace(/\\s+/g, '').length > el.textContent.replace(/\\s+/g, '').length) continue;
    }
    const r = el.getBoundingClientRect();
    if (r.width < 44 || r.height < 44)
      violations.push({ type: 'touch', selector: sel(el), detail: Math.round(r.width) + '×' + Math.round(r.height) + ' < 44×44' });
  }
  return { violations, undetermined };
})()`;

async function evaluate(cdp, sid, expression) {
  const r = await cdp.send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true }, sid);
  if (r.exceptionDetails) throw new Error(`페이지 스크립트 오류: ${r.exceptionDetails.exception?.description || r.exceptionDetails.text}`);
  return r.result.value;
}

const metrics = (width) => ({ width, height: HEIGHT, deviceScaleFactor: 1, mobile: false });

async function checkScreen(cdp, file) {
  const { targetId } = await cdp.send('Target.createTarget', { url: 'about:blank' });
  try {
    const { sessionId: sid } = await cdp.send('Target.attachToTarget', { targetId, flatten: true });
    await cdp.send('Page.enable', {}, sid);
    await cdp.send('Emulation.setDeviceMetricsOverride', metrics(BASE_WIDTH), sid);
    const loaded = cdp.waitFor('Page.loadEventFired', sid);
    const nav = await cdp.send('Page.navigate', { url: pathToFileURL(path.resolve(file)).href }, sid);
    if (nav.errorText) throw new Error(`열기 실패 — ${nav.errorText}`);
    await loaded;
    const { violations, undetermined } = await evaluate(cdp, sid, BASE_JS);
    for (const w of WIDTHS) {
      await cdp.send('Emulation.setDeviceMetricsOverride', metrics(w), sid);
      const o = await evaluate(cdp, sid, OVERFLOW_JS);
      if (o) violations.push({ type: 'overflow', width: w, selector: o.top.join(', ') || 'html',
        detail: `scrollWidth ${o.scrollWidth} > ${o.innerWidth}` });
    }
    return { violations, undetermined };
  } finally {
    cdp.send('Target.closeTarget', { targetId }).catch(() => {});
  }
}

function summarize(s) {
  if (s.error) return `${s.screen}: 검사 실패 — ${s.error}`;
  const parts = [];
  const n = (t) => s.violations.filter((v) => v.type === t).length;
  if (n('contrast')) parts.push(`대비 ${n('contrast')}`);
  if (n('touch')) parts.push(`터치 ${n('touch')}`);
  for (const w of WIDTHS) { const k = s.violations.filter((v) => v.type === 'overflow' && v.width === w).length; if (k) parts.push(`넘침(${w}) ${k}`); }
  if (s.undetermined.length) parts.push(`판정불가 ${s.undetermined.length}`);
  return `${s.screen}: ${parts.length ? parts.join(' · ') : '위반 0'}`;
}

let cdp = null, code = 0;
try {
  cdp = await connect(await launch());
  const results = [];
  for (const f of screens) {
    const screen = path.basename(f, '.html');
    try {
      results.push({ screen, file: `screens/${f}`, ...(await withTimeout(checkScreen(cdp, path.join(DIR, 'screens', f)), SCREEN_TIMEOUT_MS, '화면 검사')) });
    } catch (e) {
      results.push({ screen, file: `screens/${f}`, error: e.message, violations: [], undetermined: [] });
      code = 1;
    }
  }
  fs.writeFileSync(path.join(OUT, 'a11y.json'), JSON.stringify({
    generated: new Date().toISOString(),
    criteria: { contrast: 'WCAG AA 4.5:1, 큰 글자(≥24px 또는 ≥18.66px bold) 3:1', touch: '44×44px', overflowWidths: WIDTHS, baseWidth: BASE_WIDTH },
    screens: results,
  }, null, 2) + '\n');
  for (const s of results) console.log(summarize(s));
  console.log(`a11y: ${results.length}개 화면 → ${path.join(OUT, 'a11y.json')}`);
} catch (e) {
  console.error(`a11y: 검사 실패 — ${e.message}`);
  code = 1;
} finally {
  await shutdown(cdp);
}
process.exit(code);
