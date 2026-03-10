import { createReadStream, existsSync, statSync } from 'node:fs';
import { createServer } from 'node:http';
import { extname, join, normalize, resolve } from 'node:path';
import { chromium } from 'playwright';

const root = resolve(process.argv[2] || 'd:\\NeoOptimize\\dist\\NeoOptimize-v1.0.0-win-x64-20260310115936\\App\\WebApp');
const screenshotPath = resolve(process.argv[3] || 'd:\\NeoOptimize\\artifacts\\ui-smoke-quick.png');

if (!existsSync(root)) {
  console.error(`Web root not found: ${root}`);
  process.exit(1);
}

const mimeTypes = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.css': 'text/css',
  '.png': 'image/png'
};

const server = createServer((request, response) => {
  const url = new URL(request.url || '/', 'http://127.0.0.1');
  const relativePath = url.pathname === '/' ? '/index.html' : url.pathname;
  const fullPath = normalize(join(root, relativePath));

  if (!fullPath.startsWith(root) || !existsSync(fullPath) || statSync(fullPath).isDirectory()) {
    response.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
    response.end('Not found');
    return;
  }

  response.writeHead(200, { 'Content-Type': mimeTypes[extname(fullPath).toLowerCase()] || 'application/octet-stream' });
  createReadStream(fullPath).pipe(response);
});

const listen = (port) => new Promise((resolvePromise) => server.listen(port, '127.0.0.1', resolvePromise));
await listen(0);
const address = server.address();
const baseUrl = `http://127.0.0.1:${address.port}/index.html`;

const browser = await chromium.launch({ channel: 'msedge', headless: true });
const context = await browser.newContext({ viewport: { width: 1200, height: 1400 } });
await context.addInitScript(() => {
  window.__postedMessages = [];
  window.chrome = { webview: { postMessage(message) { window.__postedMessages.push(message); }, addEventListener(){} } };
});

const page = await context.newPage();
try {
  await page.goto(baseUrl, { waitUntil: 'domcontentloaded' });

  // wait for buttons to exist in DOM (attached)
  await page.waitForSelector('#smartBoostBtn', { state: 'attached', timeout: 10000 });

  // seed the host bootstrap message so UI renders localized text
  await page.evaluate(() => {
    const evt = new Event('message');
    (window.chrome?.webview?.addEventListener || (()=>{}));
    // directly call handlers if present
    try { window.chrome.webview.addEventListener('message', ()=>{}); } catch {}
  });

  // simulate host messages used by the WebApp
  await page.evaluate(() => {
    for (const cb of window.__webviewListeners || []) {
      try { cb({ data: { type: 'bootstrap' } }); } catch {}
    }
  }).catch(()=>{});

  // fill prompt and click analyze + exercise action buttons
  await page.fill('#chatInput', 'Quick smoke test');
  await page.click('#analyzeBtn').catch(()=>{});
  const buttons = ['#smartBoostBtn', '#smartOptimizeBtn', '#healthCheckBtn', '#integrityScanBtn'];
  for (const sel of buttons) {
    await page.click(sel).catch(()=>{});
    await page.waitForTimeout(200);
  }

  // give app a moment to collect posted messages
  await page.waitForTimeout(1000);

  const posted = await page.evaluate(() => window.__postedMessages || []);
  await page.screenshot({ path: screenshotPath, fullPage: true }).catch(()=>{});

  console.log(JSON.stringify({ postedCount: posted.length, posted }, null, 2));
} finally {
  await browser.close();
  await new Promise((resolvePromise) => server.close(resolvePromise));
}
