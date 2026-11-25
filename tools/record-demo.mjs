// Records the homepage demo to GIFs for the README, in light and dark mode.
//
//   python3 -m http.server 8765 --directory docs &   # serve the site
//   node tools/record-demo.mjs                        # writes docs/assets/demo-{light,dark}.gif
//
// Needs Google Chrome and ffmpeg. Frames come from headless Chrome over the
// DevTools protocol; ffmpeg turns them into a GIF with a per-clip palette.

import { spawn, execFileSync } from 'node:child_process';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

const URL_ = process.env.URL || 'http://127.0.0.1:8765/';
const CHROME = process.env.CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const OUT = resolve(process.argv[2] || 'docs/assets');
const SECONDS = 9.2;          // one loop of the demo
const FPS = 20;
const WIDTH = 760;            // GIF width in pixels
const PORT = 9333;
// Matches GitHub's page background, so the rounded corners blend into the README.
const PAGE_BG = { light: '#ffffff', dark: '#0d1117' };

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const profile = mkdtempSync(join(tmpdir(), 'cw-chrome-'));
const chrome = spawn(CHROME, [
  '--headless=new', `--remote-debugging-port=${PORT}`, `--user-data-dir=${profile}`,
  '--hide-scrollbars', '--force-device-scale-factor=2', '--window-size=1000,800', 'about:blank',
], { stdio: 'ignore' });

async function connect() {
  for (let i = 0; i < 50; i++) {
    try {
      const pages = await (await fetch(`http://127.0.0.1:${PORT}/json`)).json();
      const page = pages.find((p) => p.type === 'page');
      if (page) return page.webSocketDebuggerUrl;
    } catch {}
    await sleep(200);
  }
  throw new Error('Chrome did not start');
}

const ws = new WebSocket(await connect());
await new Promise((r) => ws.addEventListener('open', r, { once: true }));
let nextId = 0;
const pending = new Map();
ws.addEventListener('message', (e) => {
  const msg = JSON.parse(e.data);
  if (msg.id && pending.has(msg.id)) { pending.get(msg.id)(msg); pending.delete(msg.id); }
});
const send = (method, params = {}) => new Promise((res, rej) => {
  const id = ++nextId;
  pending.set(id, (m) => (m.error ? rej(new Error(method + ': ' + m.error.message)) : res(m.result)));
  ws.send(JSON.stringify({ id, method, params }));
});
const evaluate = async (expression) =>
  (await send('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true })).result.value;

await send('Page.enable');
await send('Emulation.setDeviceMetricsOverride', { width: 1000, height: 800, deviceScaleFactor: 2, mobile: false });

for (const scheme of ['light', 'dark']) {
  await send('Emulation.setEmulatedMedia', { features: [{ name: 'prefers-color-scheme', value: scheme }] });
  await send('Page.navigate', { url: URL_ });
  await sleep(1200);
  // Show only the demo, pinned to the corner, on GitHub's background; restart its loop from the top.
  const rect = await evaluate(`(async () => {
    document.body.style.background = '${PAGE_BG[scheme]}';
    const stage = document.querySelector('.stage');
    const toggle = document.querySelector('.demo-toggle');
    document.querySelector('.top').remove();
    Object.assign(stage.style, { position: 'fixed', left: '0', top: '0', width: '${WIDTH}px', zIndex: 50 });
    window.scrollTo(0, 0);
    await new Promise((r) => setTimeout(r, 300));
    toggle.click(); toggle.click();          // pause, play: starts a fresh loop
    const r = stage.getBoundingClientRect();
    return { x: r.x, y: r.y, width: r.width, height: r.height };
  })()`);

  const dir = mkdtempSync(join(tmpdir(), 'cw-frames-'));
  const list = [];
  const start = Date.now();
  let n = 0;
  let last = start;
  while (Date.now() - start < SECONDS * 1000) {
    const { data } = await send('Page.captureScreenshot', {
      format: 'png', clip: { ...rect, scale: 1 }, captureBeyondViewport: false,
    });
    const now = Date.now();
    const file = join(dir, `f${String(n++).padStart(4, '0')}.png`);
    writeFileSync(file, Buffer.from(data, 'base64'));
    if (list.length) list[list.length - 1].duration = (now - last) / 1000;
    list.push({ file, duration: 1 / FPS });
    last = now;
    const wait = start + (n * 1000) / FPS - Date.now();
    if (wait > 0) await sleep(wait);
  }
  // Frames are captured in real time; the concat list keeps their real timing.
  const concat = list.map((f) => `file '${f.file}'\nduration ${f.duration.toFixed(4)}`).join('\n') + `\nfile '${list.at(-1).file}'\n`;
  writeFileSync(join(dir, 'list.txt'), concat);
  const out = join(OUT, `demo-${scheme}.gif`);
  execFileSync('ffmpeg', [
    '-y', '-loglevel', 'error', '-f', 'concat', '-safe', '0', '-i', join(dir, 'list.txt'),
    '-vf', `fps=${FPS},scale=${WIDTH * 1}:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=200:stats_mode=diff[p];[b][p]paletteuse=dither=sierra2_4a:diff_mode=rectangle`,
    '-loop', '0', out,
  ]);
  rmSync(dir, { recursive: true, force: true });
  console.log(`${out}  (${n} frames)`);
}

ws.close();
chrome.kill();
await sleep(300);
rmSync(profile, { recursive: true, force: true });
