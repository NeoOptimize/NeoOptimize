import { createReadStream, existsSync, statSync } from 'node:fs';
import { createServer } from 'node:http';
import { extname, join, normalize, resolve } from 'node:path';
import { chromium } from 'playwright';

const root = resolve(process.argv[2] || 'dist/NeoOptimize-v1.0.0-win-x64-20260310075126/App/WebApp');
const screenshotPath = resolve(process.argv[3] || 'artifacts/ui-smoke/neooptimize-ui-smoke.png');

if (!existsSync(root)) {
  console.error(`Web root not found: ${root}`);
  process.exit(1);
}

const mimeTypes = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon'
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
const context = await browser.newContext({ viewport: { width: 1440, height: 1600 } });
await context.addInitScript(() => {
  window.__postedMessages = [];
  window.__webviewListeners = [];
  window.chrome = {
    webview: {
      postMessage(message) {
        window.__postedMessages.push(message);
      },
      addEventListener(type, callback) {
        if (type === 'message') {
          window.__webviewListeners.push(callback);
        }
      }
    }
  };
});

const page = await context.newPage();
const pageErrors = [];
const consoleErrors = [];
page.on('pageerror', (error) => pageErrors.push(error.message));
page.on('console', (message) => {
  if (message.type() === 'error') {
    consoleErrors.push(message.text());
  }
});

const emitMessage = async (payload) => {
  await page.evaluate((data) => {
    for (const listener of window.__webviewListeners || []) {
      listener({ data });
    }
  }, payload);
};

const assert = async (conditionPromise, description) => {
  const condition = await conditionPromise;
  if (!condition) {
    throw new Error(`Assertion failed: ${description}`);
  }
};

try {
  await page.goto(baseUrl, { waitUntil: 'networkidle' });
  await page.waitForSelector('#smartBoostBtn');
  await page.waitForSelector('#statsGrid');

  const bootstrapPosted = await page.evaluate(() => window.__postedMessages.some((message) => message?.type === 'bootstrap'));
  await assert(Promise.resolve(bootstrapPosted), 'bootstrap message posted to host');

  await emitMessage({
    type: 'bootstrap',
    payload: {
      clientId: 'client-ui-smoke-001',
      backendUrl: 'https://neooptimize-neooptimize.hf.space/',
      appVersion: '1.0.0',
      status: 'Connected',
      reports: [
        {
          fileName: 'neo-health-report.html',
          title: 'Health Check selesai',
          createdAt: '10 Mar 2026 08:01',
          sizeLabel: '12 KB'
        }
      ]
    }
  });

  await emitMessage({
    type: 'stats',
    payload: {
      cpu: 42,
      ram: 58,
      disk: 67,
      temp: 49,
      healthState: 'healthy',
      integrityStatus: 'verified',
      alerts: ['Disk IO'],
      overallScore: 91,
      recommendations: ['Startup apps dalam kondisi aman'],
      issues: [],
      processCount: 162,
      topProcesses: [],
      machineName: 'NEO-DESKTOP',
      os: 'Windows 11 Pro',
      recordedAt: '10 Mar 2026 08:02:11'
    }
  });

  await emitMessage({
    type: 'activity',
    payload: [
      {
        title: 'Neo AI analysis',
        summary: 'Analisis real diterima dari backend.',
        timestamp: '08:02:15'
      },
      {
        title: 'Health Check selesai',
        summary: 'Health report dikirim ke Supabase.',
        timestamp: '08:01:59'
      }
    ]
  });

  await emitMessage({
    type: 'aiResponse',
    payload: {
      reply: 'Neo AI mendeteksi kondisi stabil dan tidak ada throttling.',
      correlationId: 'corr-ui-001',
      plannedActions: [
        {
          commandName: 'health_check',
          dispatched: true
        }
      ],
      memoryHits: [
        {
          similarity: 0.92
        }
      ]
    }
  });

  await emitMessage({
    type: 'updateStatus',
    payload: {
      status: 'up-to-date',
      currentVersion: '1.0.0',
      latestVersion: '1.0.0',
      hasUpdate: false,
      summary: 'Sudah versi terbaru.'
    }
  });

  await page.click('#langToggle span[data-lang="id"]');
  await page.click('#themeToggle span[data-theme="light"]');

  const bodyHasLightTheme = await page.evaluate(() => document.body.classList.contains('light-theme'));
  await assert(Promise.resolve(bodyHasLightTheme), 'light theme applied');

  const analyzeText = await page.locator('#analyzeBtn').textContent();
  await assert(Promise.resolve((analyzeText || '').includes('Analisa')), 'Indonesian translation applied');

  const clientBadge = await page.locator('#clientIdDisplay').textContent();
  await assert(Promise.resolve((clientBadge || '').includes('client-ui-smoke-001')), 'client id rendered');

  const statCardCount = await page.locator('#statsGrid .stat-card').count();
  await assert(Promise.resolve(statCardCount === 4), 'exactly four stat cards rendered');

  const logsCount = await page.locator('#logsList .log-item').count();
  await assert(Promise.resolve(logsCount >= 2), 'activity log rendered');

  await page.click('#profileBtn');
  const profileVisible = await page.locator('#userProfile').evaluate((element) => getComputedStyle(element).display !== 'none');
  await assert(Promise.resolve(profileVisible), 'real profile panel shown');
  await page.evaluate(() => window.closeLoginModal());

  await page.evaluate(() => window.openReportsModal());
  const reportCount = await page.locator('#reportsList .report-card').count();
  await assert(Promise.resolve(reportCount >= 1), 'reports modal rendered real report items');
  await page.evaluate(() => window.closeModal());

  await page.click('#updateBtn');
  await page.check('#autoExecute');
  await page.fill('#chatInput', 'Analisa startup lambat saya.');
  await page.click('#analyzeBtn');

  const postedMessages = await page.evaluate(() => window.__postedMessages);
  const actionPosted = postedMessages.some((message) => message?.type === 'runAction' && message?.action === 'smartBoost');
  const aiPosted = postedMessages.some((message) => message?.type === 'aiChat' && message?.message === 'Analisa startup lambat saya.' && message?.dispatchActions === true);
  const updatePosted = postedMessages.some((message) => message?.type === 'checkUpdate');

  await page.click('#smartBoostBtn');
  const postedAfterAction = await page.evaluate(() => window.__postedMessages);
  const smartBoostPosted = postedAfterAction.some((message) => message?.type === 'runAction' && message?.action === 'smartBoost');

  await assert(Promise.resolve(aiPosted), 'AI prompt posted to host with dispatch flag');
  await assert(Promise.resolve(updatePosted), 'update check posted to host');
  await assert(Promise.resolve(actionPosted || smartBoostPosted), 'action button posted to host');

  await page.screenshot({ path: screenshotPath, fullPage: true });

  const summary = {
    webRoot: root,
    screenshotPath,
    checks: {
      bootstrapPosted,
      bodyHasLightTheme,
      statCardCount,
      logsCount,
      reportCount,
      aiPosted,
      updatePosted,
      smartBoostPosted: actionPosted || smartBoostPosted
    },
    pageErrors,
    consoleErrors
  };

  console.log(JSON.stringify(summary, null, 2));
} finally {
  await browser.close();
  await new Promise((resolvePromise) => server.close(resolvePromise));
}


