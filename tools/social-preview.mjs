// Renders the GitHub social preview image (1280×640) from the website's demo.
//
//   python3 -m http.server 8765 --directory docs &
//   node tools/social-preview.mjs            # writes docs/assets/social-preview.png
//
// Upload it in the repo's Settings › General › Social preview.

import { spawn } from 'node:child_process';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

const URL_ = process.env.URL || 'http://127.0.0.1:8765/';
const CHROME = process.env.CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const OUT = resolve(process.argv[2] || 'docs/assets/social-preview.png');
const PORT = 9334;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const profile = mkdtempSync(join(tmpdir(), 'cw-chrome-'));
const chrome = spawn(CHROME, ['--headless=new', `--remote-debugging-port=${PORT}`, `--user-data-dir=${profile}`,
  '--hide-scrollbars', 'about:blank'], { stdio: 'ignore' });

let wsUrl;
for (let i = 0; i < 50 && !wsUrl; i++) {
  try { wsUrl = (await (await fetch(`http://127.0.0.1:${PORT}/json`)).json()).find((p) => p.type === 'page')?.webSocketDebuggerUrl; } catch {}
  if (!wsUrl) await sleep(200);
}
const ws = new WebSocket(wsUrl);
await new Promise((r) => ws.addEventListener('open', r, { once: true }));
let id = 0; const pending = new Map();
ws.addEventListener('message', (e) => { const m = JSON.parse(e.data); pending.get(m.id)?.(m); pending.delete(m.id); });
const send = (method, params = {}) => new Promise((res, rej) => {
  const n = ++id; pending.set(n, (m) => (m.error ? rej(new Error(m.error.message)) : res(m.result)));
  ws.send(JSON.stringify({ id: n, method, params }));
});

await send('Page.enable');
await send('Emulation.setDeviceMetricsOverride', { width: 1280, height: 640, deviceScaleFactor: 1, mobile: false });
await send('Emulation.setEmulatedMedia', { features: [{ name: 'prefers-color-scheme', value: 'dark' }, { name: 'prefers-reduced-motion', value: 'reduce' }] });
await send('Page.navigate', { url: URL_ });
await sleep(1200);

// Reduce Motion shows the demo's still frame: the menu open, OrcaSlicer highlighted.
await send('Runtime.evaluate', { awaitPromise: true, expression: `(async () => {
  const stage = document.querySelector('.stage');
  const icon = document.querySelector('.hero .icon').src;
  const card = document.createElement('div');
  card.innerHTML = \`
    <style>
      body { margin: 0; overflow: hidden; }
      .sp { width: 1280px; height: 640px; box-sizing: border-box; padding: 64px 64px 64px 80px;
            display: grid; grid-template-columns: 430px 1fr; gap: 48px; align-items: center;
            background: radial-gradient(circle at 15% 20%, #2b3170, transparent 55%), radial-gradient(circle at 90% 90%, #3a2456, transparent 50%), #121318;
            color: #f5f5f7; font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif; }
      .sp img { width: 120px; height: 120px; filter: drop-shadow(0 12px 28px rgb(79 95 240 / 0.45)); }
      .sp h1 { font-size: 68px; letter-spacing: -0.02em; margin: 22px 0 10px; line-height: 1; }
      .sp p { font-size: 30px; color: #b8b9c4; margin: 0 0 30px; line-height: 1.25; font-weight: 500; }
      .sp small { font-size: 20px; color: #8d8e99; }
      .sp .stage { width: 660px; border-radius: 16px; box-shadow: 0 30px 80px rgb(0 0 0 / 0.55), 0 0 0 1px rgb(255 255 255 / 0.08); }
    </style>
    <div class="sp">
      <div>
        <img src="\${icon}" alt="">
        <h1>Choose With</h1>
        <p>Don't just open with.<br>Choose with.</p>
        <small>Free and open source for macOS</small>
      </div>
      <div class="slot"></div>
    </div>\`;
  card.querySelector('.slot').appendChild(stage);
  document.body.replaceChildren(card);
  window.scrollTo(0, 0);
  dispatchEvent(new Event('resize'));          // re-place the still frame in its new size
  await new Promise((r) => setTimeout(r, 500));
})()` });

const { data } = await send('Page.captureScreenshot', { format: 'png', clip: { x: 0, y: 0, width: 1280, height: 640, scale: 1 } });
writeFileSync(OUT, Buffer.from(data, 'base64'));
console.log(OUT);
ws.close(); chrome.kill(); await sleep(300);
rmSync(profile, { recursive: true, force: true });
