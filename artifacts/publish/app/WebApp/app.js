const state = {
  lang: 'id',
  theme: 'system',
  clientId: '',
  backendUrl: '',
  appVersion: '-',
  stats: {
    cpu: null,
    ram: null,
    disk: null,
    temp: null,
    healthState: 'unknown',
    integrityStatus: 'pending',
    alerts: [],
    overallScore: null,
    recommendations: [],
    issues: [],
    processCount: 0,
    topProcesses: [],
    machineName: '-',
    recordedAt: '',
    os: ''
  },
  reports: [],
  activity: [],
  plannedActions: [],
  memoryHits: [],
  contextSummary: {},
  aiMessages: [],
  update: {
    status: 'idle',
    currentVersion: '-',
    latestVersion: '-',
    hasUpdate: false,
    releaseUrl: 'https://github.com/NeoOptimize/NeoOptimize/releases',
    summary: 'Belum cek update',
    publishedAt: ''
  },
  chart: {
    labels: [],
    cpu: [],
    ram: [],
    disk: [],
    temp: []
  },
  telemetryChart: null
};

const strings = {
  id: {
    heroSubtitle: 'Client akan register ke Hugging Face Space, memantau kondisi lokal, lalu mengirim insight dan command execution ke Supabase.',
    heroTitle: 'Cockpit real-time untuk optimasi Windows, observability, dan AI execution loop.',
    heroText: 'Semua panel di bawah ditenagai data lokal dari desktop client dan respons live dari backend Neo AI.',
    actionsTitle: 'Eksekusi lokal',
    activityTitle: 'Execution timeline',
    reportsTitle: 'Laporan lokal',
    aiPanelTitle: 'Copilot siap memberi analisis',
    dispatchLabel: 'Eksekusi tindakan yang disarankan',
    aiSubmit: 'Analisa dengan Neo AI',
    telemetryTitle: 'Live metric history',
    checkUpdate: 'Check Update',
    refreshSnapshot: 'Refresh Snapshot',
    reloadReports: 'Reload Reports',
    aiPlaceholder: 'Contoh: PC terasa lambat saat startup, analisa dan sarankan tindakan aman.',
    emptyReports: 'Belum ada report',
    emptyReportsMeta: 'Quick action dan integrity scan akan menulis report lokal di sini.',
    emptyActivity: 'Belum ada aktivitas',
    emptyActivityMeta: 'Timeline akan terisi setelah bootstrap selesai.',
    emptyProcesses: 'Top process akan muncul setelah snapshot pertama selesai.',
    emptyChat: 'Neo AI akan menampilkan percakapan nyata dari backend di panel ini.',
    emptyMemory: 'Belum ada memory hit atau context retrieval.',
    emptyPlan: 'Belum ada rencana aksi dari Neo AI.',
    updateReady: 'Update tersedia',
    updateCurrent: 'Sudah versi terbaru',
    updateFailed: 'Cek update gagal',
    analyzing: 'Menganalisa',
    analysisReady: 'Analisis siap',
    dispatched: 'Command dispatched',
    actionComplete: 'Action complete',
    standby: 'Standby',
    genericError: 'Terjadi kesalahan saat memperbarui UI.',
    promptRequired: 'Prompt AI tidak boleh kosong.',
    lowConfidence: 'Context live belum lengkap, analisis menggunakan data terbaru yang tersedia.'
  },
  en: {
    heroSubtitle: 'The client registers to the Hugging Face Space, monitors local health, and sends live insights plus command execution to Supabase.',
    heroTitle: 'A real-time cockpit for Windows optimization, observability, and AI execution loops.',
    heroText: 'Every panel below is driven by local desktop data and live responses from the Neo AI backend.',
    actionsTitle: 'Local execution',
    activityTitle: 'Execution timeline',
    reportsTitle: 'Local reports',
    aiPanelTitle: 'Copilot is ready to analyze',
    dispatchLabel: 'Execute suggested actions',
    aiSubmit: 'Analyze with Neo AI',
    telemetryTitle: 'Live metric history',
    checkUpdate: 'Check Update',
    refreshSnapshot: 'Refresh Snapshot',
    reloadReports: 'Reload Reports',
    aiPlaceholder: 'Example: the PC feels slow during startup, analyze it and suggest safe actions.',
    emptyReports: 'No reports yet',
    emptyReportsMeta: 'Quick actions and integrity scans will write local reports here.',
    emptyActivity: 'No activity yet',
    emptyActivityMeta: 'The timeline will populate after bootstrap finishes.',
    emptyProcesses: 'Top processes will appear after the first completed snapshot.',
    emptyChat: 'Neo AI will display real backend conversations in this panel.',
    emptyMemory: 'No memory hits or retrieval context yet.',
    emptyPlan: 'Neo AI has not proposed any actions yet.',
    updateReady: 'Update available',
    updateCurrent: 'Already up to date',
    updateFailed: 'Update check failed',
    analyzing: 'Analyzing',
    analysisReady: 'Analysis ready',
    dispatched: 'Command dispatched',
    actionComplete: 'Action complete',
    standby: 'Standby',
    genericError: 'An error occurred while updating the UI.',
    promptRequired: 'AI prompt cannot be empty.',
    lowConfidence: 'Live context is still limited, using the latest available data.'
  }
};

function post(message) {
  window.chrome?.webview?.postMessage(message);
}

function getCopy() {
  return strings[state.lang] || strings.id;
}

function readPreference(key, fallback) {
  try {
    return window.localStorage.getItem(key) || fallback;
  } catch {
    return fallback;
  }
}

function writePreference(key, value) {
  try {
    window.localStorage.setItem(key, value);
  } catch {
    // Best effort only.
  }
}

function escapeHtml(value) {
  return String(value ?? '').replace(/[&<>"']/g, (char) => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#39;'
  }[char]));
}

function formatMetric(value, suffix = '%', digits = 1) {
  if (value === null || value === undefined || Number.isNaN(Number(value))) {
    return 'N/A';
  }

  return `${Number(value).toFixed(digits)}${suffix}`;
}

function formatWhole(value) {
  if (value === null || value === undefined || Number.isNaN(Number(value))) {
    return '0';
  }

  return Number(value).toLocaleString(state.lang === 'id' ? 'id-ID' : 'en-US');
}

function formatMemoryMb(value) {
  if (value === null || value === undefined || Number.isNaN(Number(value))) {
    return 'N/A';
  }

  return `${Number(value).toFixed(1)} MB`;
}

function clampPercent(value) {
  if (value === null || value === undefined || Number.isNaN(Number(value))) {
    return 0;
  }

  return Math.max(0, Math.min(Number(value), 100));
}

function abbreviate(value, length = 18) {
  const text = String(value ?? '');
  if (!text || text.length <= length) {
    return text || '-';
  }

  return `${text.slice(0, length)}...`;
}

function normalizeStatusTone(value) {
  const text = String(value || '').toLowerCase();
  if (text.includes('error') || text.includes('failed') || text.includes('critical')) {
    return 'danger';
  }
  if (text.includes('warning') || text.includes('update')) {
    return 'alert';
  }
  if (text.includes('connected') || text.includes('ready') || text.includes('healthy') || text.includes('complete') || text.includes('standby')) {
    return 'live';
  }
  return 'neutral';
}

function applyChipTone(element, tone) {
  if (!element) {
    return;
  }

  element.classList.remove('status-live', 'status-neutral', 'status-alert', 'status-danger');
  element.classList.add(`status-${tone}`);
}

function setConnectionStatus(text) {
  const element = document.getElementById('connectionStatus');
  element.textContent = text;
  applyChipTone(element, normalizeStatusTone(text));
}

function setAiStatus(text, tone = 'neutral') {
  const element = document.getElementById('aiStatus');
  element.textContent = text;
  applyChipTone(element, tone);
}

function setLanguage(lang) {
  state.lang = lang;
  writePreference('neooptimize.lang', lang);
  document.documentElement.lang = lang;
  document.querySelectorAll('#langGroup .chip').forEach((button) => {
    button.classList.toggle('is-active', button.dataset.lang === lang);
  });

  const copy = getCopy();
  document.getElementById('heroSubtitle').textContent = copy.heroSubtitle;
  document.getElementById('heroTitle').textContent = copy.heroTitle;
  document.getElementById('heroText').textContent = copy.heroText;
  document.getElementById('actionsTitle').textContent = copy.actionsTitle;
  document.getElementById('activityTitle').textContent = copy.activityTitle;
  document.getElementById('reportsTitle').textContent = copy.reportsTitle;
  document.getElementById('aiPanelTitle').textContent = copy.aiPanelTitle;
  document.getElementById('dispatchLabel').textContent = copy.dispatchLabel;
  document.getElementById('aiSubmit').textContent = copy.aiSubmit;
  document.getElementById('telemetryTitle').textContent = copy.telemetryTitle;
  document.getElementById('checkUpdateBtn').textContent = copy.checkUpdate;
  document.getElementById('refreshButton').textContent = copy.refreshSnapshot;
  document.getElementById('reloadReports').textContent = copy.reloadReports;
  document.getElementById('aiPrompt').placeholder = copy.aiPlaceholder;
  renderAll();
}

function setTheme(theme) {
  state.theme = theme;
  writePreference('neooptimize.theme', theme);
  const actualTheme = theme === 'system'
    ? (window.matchMedia('(prefers-color-scheme: light)').matches ? 'light' : 'night')
    : theme;
  document.documentElement.dataset.theme = actualTheme;
  document.querySelectorAll('#themeGroup .chip').forEach((button) => {
    button.classList.toggle('is-active', button.dataset.theme === theme);
  });
}

function buildHealthDetail() {
  const score = state.stats.overallScore;
  const alertCount = Array.isArray(state.stats.alerts) ? state.stats.alerts.length : 0;
  const recommendation = Array.isArray(state.stats.recommendations) && state.stats.recommendations.length
    ? state.stats.recommendations[0]
    : getCopy().lowConfidence;
  const fragments = [];

  if (score !== null && score !== undefined) {
    fragments.push(`Score ${score}`);
  }
  if (alertCount > 0) {
    fragments.push(`${alertCount} alert`);
  }

  fragments.push(recommendation);
  return fragments.filter(Boolean).join(' · ');
}

function buildIntegrityDetail() {
  const issueCount = Array.isArray(state.stats.issues) ? state.stats.issues.length : 0;
  const sampledAt = state.stats.recordedAt || '-';
  return `${issueCount} issue flagged · ${sampledAt}`;
}

function buildProcessDetail() {
  const machine = state.stats.machineName || '-';
  const os = state.stats.os ? abbreviate(state.stats.os, 32) : 'Windows';
  return `${machine} · ${os}`;
}

function buildUpdateDetail() {
  const update = state.update;
  if (update.status === 'update-available') {
    return `${getCopy().updateReady}: ${update.latestVersion}${update.publishedAt ? ` · ${update.publishedAt}` : ''}`;
  }
  if (update.status === 'up-to-date') {
    return `${getCopy().updateCurrent}${update.publishedAt ? ` · ${update.publishedAt}` : ''}`;
  }
  if (update.status === 'check-failed') {
    return update.summary || getCopy().updateFailed;
  }
  return update.summary || 'Belum cek update';
}

function renderHero() {
  document.getElementById('clientId').textContent = state.clientId || 'Belum terdaftar';
  document.getElementById('backendUrl').textContent = state.backendUrl || '-';
  document.getElementById('healthStateBadge').textContent = state.stats.healthState || 'unknown';
  document.getElementById('healthDetail').textContent = buildHealthDetail();
  document.getElementById('integrityBadge').textContent = state.stats.integrityStatus || 'pending';
  document.getElementById('integrityDetail').textContent = buildIntegrityDetail();
  document.getElementById('processCount').textContent = formatWhole(state.stats.processCount);
  document.getElementById('processDetail').textContent = buildProcessDetail();
  document.getElementById('versionBadge').textContent = state.appVersion || state.update.currentVersion || '-';
  document.getElementById('updateDetail').textContent = buildUpdateDetail();
  document.getElementById('lastSample').textContent = state.stats.recordedAt || 'Belum ada sample';
  document.getElementById('machineName').textContent = state.stats.machineName || '-';

  const releaseLink = document.getElementById('releaseLink');
  if (releaseLink) {
    releaseLink.href = state.update.releaseUrl || 'https://github.com/NeoOptimize/NeoOptimize/releases';
    releaseLink.textContent = state.update.hasUpdate ? `Release ${state.update.latestVersion}` : 'Release';
  }

  const updateButton = document.getElementById('checkUpdateBtn');
  if (state.update.status === 'update-available') {
    updateButton.textContent = `${getCopy().updateReady}`;
  } else if (state.update.status === 'up-to-date') {
    updateButton.textContent = getCopy().updateCurrent;
  } else {
    updateButton.textContent = getCopy().checkUpdate;
  }
}

function renderStats() {
  const cards = [
    {
      label: 'CPU Usage',
      value: state.stats.cpu,
      extra: Array.isArray(state.stats.alerts) && state.stats.alerts.includes('CPU') ? 'Alert' : 'Telemetry',
      suffix: '%'
    },
    {
      label: 'RAM Usage',
      value: state.stats.ram,
      extra: state.stats.healthState || 'health',
      suffix: '%'
    },
    {
      label: 'Disk Usage',
      value: state.stats.disk,
      extra: state.stats.integrityStatus || 'storage',
      suffix: '%'
    },
    {
      label: 'Temperature',
      value: state.stats.temp,
      extra: Array.isArray(state.stats.recommendations) && state.stats.recommendations.length ? 'Thermal watch' : 'Thermal',
      suffix: ' C'
    }
  ];

  document.getElementById('statsGrid').innerHTML = cards.map((card) => `
    <article class="stat-card panel">
      <div class="stat-head">
        <div>
          <p class="eyebrow">${escapeHtml(card.label)}</p>
          <div class="stat-value">${escapeHtml(formatMetric(card.value, card.suffix))}</div>
          <div class="stat-extra">${escapeHtml(card.extra)}</div>
        </div>
        <span class="status-chip ${clampPercent(card.value) >= 85 ? 'status-danger' : clampPercent(card.value) >= 65 ? 'status-alert' : 'status-live'}">${escapeHtml(card.value === null || card.value === undefined ? 'N/A' : `${Math.round(clampPercent(card.value))}%`)}</span>
      </div>
      <div class="meter">
        <div class="meter-fill" style="width:${clampPercent(card.value)}%"></div>
      </div>
    </article>
  `).join('');
}

function renderProcesses() {
  const root = document.getElementById('processList');
  const processes = Array.isArray(state.stats.topProcesses) ? state.stats.topProcesses : [];
  if (!processes.length) {
    root.innerHTML = `<div class="empty-state">${escapeHtml(getCopy().emptyProcesses)}</div>`;
    return;
  }

  const maxWorkingSet = Math.max(...processes.map((process) => Number(process.workingSetMb ?? 0)), 1);
  root.innerHTML = processes.map((process) => {
    const workingSet = Number(process.workingSetMb ?? 0);
    return `
      <article class="process-card">
        <strong>${escapeHtml(process.name || 'unknown')}</strong>
        <p class="process-meta">PID ${escapeHtml(process.pid ?? '-') } · ${escapeHtml(formatMemoryMb(workingSet))}</p>
        <div class="process-bar">
          <span style="width:${Math.max(10, Math.min((workingSet / maxWorkingSet) * 100, 100))}%"></span>
        </div>
      </article>
    `;
  }).join('');
}

function renderReports() {
  const root = document.getElementById('reportsGrid');
  if (!state.reports.length) {
    root.innerHTML = `
      <div class="empty-state">
        <strong>${escapeHtml(getCopy().emptyReports)}</strong>
        <p class="report-meta">${escapeHtml(getCopy().emptyReportsMeta)}</p>
      </div>
    `;
    return;
  }

  root.innerHTML = state.reports.map((report) => `
    <article class="report-card">
      <strong>${escapeHtml(report.title)}</strong>
      <p class="report-meta">${escapeHtml(report.createdAt)} · ${escapeHtml(report.sizeLabel)}</p>
      <p class="report-meta">${escapeHtml(report.fileName)}</p>
      <div class="report-actions">
        <button data-open-report="${escapeHtml(report.fileName)}">Open</button>
        <button data-delete-report="${escapeHtml(report.fileName)}">Delete</button>
      </div>
    </article>
  `).join('');
}

function renderActivity() {
  const root = document.getElementById('activityList');
  if (!state.activity.length) {
    root.innerHTML = `
      <div class="empty-state">
        <strong>${escapeHtml(getCopy().emptyActivity)}</strong>
        <p class="activity-meta">${escapeHtml(getCopy().emptyActivityMeta)}</p>
      </div>
    `;
    return;
  }

  root.innerHTML = state.activity.map((item) => `
    <article class="activity-item">
      <strong>${escapeHtml(item.title)}</strong>
      <p class="activity-meta">${escapeHtml(item.summary)}</p>
      <span class="activity-tag">${escapeHtml(item.timestamp)}</span>
    </article>
  `).join('');
}

function renderChat() {
  const root = document.getElementById('chatStream');
  if (!state.aiMessages.length) {
    root.innerHTML = `<div class="empty-state">${escapeHtml(getCopy().emptyChat)}</div>`;
    return;
  }

  root.innerHTML = state.aiMessages.map((message) => `
    <article class="chat-message ${escapeHtml(message.role)}">
      <strong>${escapeHtml(message.role === 'user' ? 'You' : 'Neo AI')}</strong>
      <div>${escapeHtml(message.text)}</div>
      ${message.meta ? `<div class="chat-meta">${escapeHtml(message.meta)}</div>` : ''}
    </article>
  `).join('');
  root.scrollTop = root.scrollHeight;
}

function renderMemory() {
  const root = document.getElementById('memoryStrip');
  const hits = Array.isArray(state.memoryHits) ? state.memoryHits : [];
  const summaryEntries = Object.entries(state.contextSummary || {})
    .filter(([, value]) => value !== null && value !== undefined && value !== '')
    .slice(0, 3);

  if (!hits.length && !summaryEntries.length) {
    root.innerHTML = `<div class="empty-state">${escapeHtml(getCopy().emptyMemory)}</div>`;
    return;
  }

  const memoryChips = hits.map((hit) => {
    const similarity = hit.similarity === null || hit.similarity === undefined
      ? 'match'
      : `${Math.round(Number(hit.similarity) * 100)}% match`;
    const source = hit.userMessage || hit.aiResponse || hit.messageId || 'memory';
    return `
      <div class="memory-chip">
        <strong>${escapeHtml(similarity)}</strong>
        <span>${escapeHtml(abbreviate(source, 60))}</span>
      </div>
    `;
  });

  const contextChips = summaryEntries.map(([key, value]) => `
    <div class="memory-chip">
      <strong>${escapeHtml(key.replace(/_/g, ' '))}</strong>
      <span>${escapeHtml(abbreviate(value, 60))}</span>
    </div>
  `);

  root.innerHTML = [...memoryChips, ...contextChips].join('');
}

function renderPlannedActions() {
  const root = document.getElementById('plannedActions');
  if (!state.plannedActions.length) {
    root.innerHTML = `<div class="empty-state">${escapeHtml(getCopy().emptyPlan)}</div>`;
    return;
  }

  root.innerHTML = state.plannedActions.map((action) => `
    <div class="plan-chip">
      <strong>${escapeHtml(action.commandName || 'action')}</strong>
      <span>${escapeHtml(action.dispatched ? `${action.reason} · queued` : action.reason)}</span>
    </div>
  `).join('');
}

function initChart() {
  if (!window.Chart) {
    return;
  }

  const canvas = document.getElementById('telemetryChart');
  if (!canvas) {
    return;
  }

  state.telemetryChart = new window.Chart(canvas, {
    type: 'line',
    data: {
      labels: [],
      datasets: [
        { label: 'CPU', data: [], borderColor: '#56b4ff', backgroundColor: 'rgba(86, 180, 255, 0.14)', tension: 0.35 },
        { label: 'RAM', data: [], borderColor: '#7ff1c4', backgroundColor: 'rgba(127, 241, 196, 0.14)', tension: 0.35 },
        { label: 'Disk', data: [], borderColor: '#8a8dff', backgroundColor: 'rgba(138, 141, 255, 0.14)', tension: 0.35 },
        { label: 'Temp', data: [], borderColor: '#ffd26c', backgroundColor: 'rgba(255, 210, 108, 0.14)', tension: 0.35 }
      ]
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      interaction: { mode: 'index', intersect: false },
      plugins: {
        legend: {
          labels: {
            color: getComputedStyle(document.documentElement).getPropertyValue('--muted').trim() || '#8ea9c8'
          }
        }
      },
      scales: {
        x: {
          ticks: { color: getComputedStyle(document.documentElement).getPropertyValue('--muted').trim() || '#8ea9c8' },
          grid: { color: 'rgba(255,255,255,0.04)' }
        },
        y: {
          beginAtZero: true,
          suggestedMax: 100,
          ticks: { color: getComputedStyle(document.documentElement).getPropertyValue('--muted').trim() || '#8ea9c8' },
          grid: { color: 'rgba(255,255,255,0.04)' }
        }
      }
    }
  });
}

function pushChartSample(stats) {
  if (!state.telemetryChart) {
    return;
  }

  const label = (stats.recordedAt || '').split(' ').slice(-1)[0] || new Date().toLocaleTimeString();
  state.chart.labels.push(label);
  state.chart.cpu.push(stats.cpu === null || stats.cpu === undefined ? null : Number(stats.cpu));
  state.chart.ram.push(stats.ram === null || stats.ram === undefined ? null : Number(stats.ram));
  state.chart.disk.push(stats.disk === null || stats.disk === undefined ? null : Number(stats.disk));
  state.chart.temp.push(stats.temp === null || stats.temp === undefined ? null : Number(stats.temp));

  while (state.chart.labels.length > 12) {
    state.chart.labels.shift();
    state.chart.cpu.shift();
    state.chart.ram.shift();
    state.chart.disk.shift();
    state.chart.temp.shift();
  }

  state.telemetryChart.data.labels = [...state.chart.labels];
  state.telemetryChart.data.datasets[0].data = [...state.chart.cpu];
  state.telemetryChart.data.datasets[1].data = [...state.chart.ram];
  state.telemetryChart.data.datasets[2].data = [...state.chart.disk];
  state.telemetryChart.data.datasets[3].data = [...state.chart.temp];
  state.telemetryChart.update();
}

function addChatMessage(role, text, meta = '') {
  state.aiMessages.push({ role, text, meta });
  if (state.aiMessages.length > 18) {
    state.aiMessages = state.aiMessages.slice(-18);
  }
  renderChat();
}

function showToast(message, tone = 'info') {
  const toast = document.createElement('div');
  toast.className = `toast ${tone}`;
  toast.textContent = message;
  document.getElementById('toastZone').prepend(toast);
  setTimeout(() => toast.remove(), 5000);
}

function animateIn() {
  if (!window.anime) {
    return;
  }

  window.anime({
    targets: '.reveal',
    opacity: [0, 1],
    translateY: [24, 0],
    easing: 'easeOutExpo',
    duration: 900,
    delay: window.anime.stagger(85)
  });
}

function renderAll() {
  renderHero();
  renderStats();
  renderProcesses();
  renderReports();
  renderActivity();
  renderChat();
  renderMemory();
  renderPlannedActions();
}

function handleMessage(data) {
  switch (data.type) {
    case 'bootstrap': {
      state.clientId = data.payload.clientId;
      state.backendUrl = data.payload.backendUrl;
      state.appVersion = data.payload.appVersion || state.appVersion;
      state.update.currentVersion = state.appVersion;
      state.reports = Array.isArray(data.payload.reports) ? data.payload.reports : [];
      setConnectionStatus(data.payload.status || 'Connected');
      if (!state.aiMessages.length) {
        addChatMessage('ai', `Neo AI terkoneksi ke ${state.backendUrl || 'backend'} untuk client ${abbreviate(state.clientId, 14)}.`, `Desktop v${state.appVersion}`);
      }
      renderHero();
      renderReports();
      break;
    }
    case 'stats':
      state.stats = {
        ...state.stats,
        ...data.payload,
        alerts: Array.isArray(data.payload.alerts) ? data.payload.alerts : [],
        recommendations: Array.isArray(data.payload.recommendations) ? data.payload.recommendations : [],
        issues: Array.isArray(data.payload.issues) ? data.payload.issues : [],
        topProcesses: Array.isArray(data.payload.topProcesses) ? data.payload.topProcesses : []
      };
      pushChartSample(state.stats);
      renderHero();
      renderStats();
      renderProcesses();
      break;
    case 'reports':
      state.reports = Array.isArray(data.payload) ? data.payload : [];
      renderReports();
      break;
    case 'activity':
      state.activity = Array.isArray(data.payload) ? data.payload : [];
      renderActivity();
      break;
    case 'toast':
      showToast(data.payload.message, data.payload.tone);
      break;
    case 'actionResult':
      showToast(data.payload.summary, 'success');
      setAiStatus(getCopy().actionComplete, 'live');
      addChatMessage('ai', `Aksi lokal selesai: ${data.payload.summary}`, data.payload.reportFile ? `Report ${data.payload.reportFile}` : 'Local executor');
      break;
    case 'aiResponse':
      addChatMessage('ai', data.payload.reply, data.payload.correlationId ? `Correlation ${data.payload.correlationId}` : 'Backend response');
      state.plannedActions = Array.isArray(data.payload.plannedActions) ? data.payload.plannedActions : [];
      state.memoryHits = Array.isArray(data.payload.memoryHits) ? data.payload.memoryHits : [];
      state.contextSummary = data.payload.contextSummary || {};
      renderPlannedActions();
      renderMemory();
      setAiStatus(data.payload.dispatched ? getCopy().dispatched : getCopy().analysisReady, data.payload.dispatched ? 'live' : 'neutral');
      break;
    case 'updateStatus':
      state.update = {
        ...state.update,
        ...data.payload,
        currentVersion: data.payload.currentVersion || state.update.currentVersion || state.appVersion,
        releaseUrl: data.payload.releaseUrl || state.update.releaseUrl
      };
      renderHero();
      break;
    default:
      break;
  }
}

window.addEventListener('DOMContentLoaded', () => {
  const initialLang = readPreference('neooptimize.lang', 'id');
  const initialTheme = readPreference('neooptimize.theme', 'system');
  setLanguage(initialLang);
  setTheme(initialTheme);
  initChart();
  setConnectionStatus('Menghubungkan');
  setAiStatus(getCopy().standby, 'neutral');
  renderAll();
  animateIn();

  window.matchMedia('(prefers-color-scheme: light)').addEventListener('change', () => {
    if (state.theme === 'system') {
      setTheme('system');
    }
  });

  document.getElementById('themeGroup').addEventListener('click', (event) => {
    const button = event.target.closest('[data-theme]');
    if (!button) {
      return;
    }
    setTheme(button.dataset.theme);
  });

  document.getElementById('langGroup').addEventListener('click', (event) => {
    const button = event.target.closest('[data-lang]');
    if (!button) {
      return;
    }
    setLanguage(button.dataset.lang);
  });

  document.querySelectorAll('.action-card').forEach((button) => {
    button.addEventListener('click', () => {
      post({ type: 'runAction', action: button.dataset.action });
    });
  });

  document.getElementById('refreshButton').addEventListener('click', () => post({ type: 'refresh' }));
  document.getElementById('reloadReports').addEventListener('click', () => post({ type: 'listReports' }));
  document.getElementById('checkUpdateBtn').addEventListener('click', () => post({ type: 'checkUpdate' }));

  document.getElementById('reportsGrid').addEventListener('click', (event) => {
    const openButton = event.target.closest('[data-open-report]');
    if (openButton) {
      post({ type: 'openReport', fileName: openButton.dataset.openReport });
      return;
    }

    const deleteButton = event.target.closest('[data-delete-report]');
    if (deleteButton) {
      post({ type: 'deleteReport', fileName: deleteButton.dataset.deleteReport });
    }
  });

  document.getElementById('aiForm').addEventListener('submit', (event) => {
    event.preventDefault();
    const input = document.getElementById('aiPrompt');
    const message = input.value.trim();
    if (!message) {
      showToast(getCopy().promptRequired, 'error');
      return;
    }

    addChatMessage('user', message, state.stats.recordedAt || 'Live prompt');
    state.plannedActions = [];
    state.memoryHits = [];
    state.contextSummary = {};
    renderMemory();
    renderPlannedActions();
    setAiStatus(getCopy().analyzing, 'alert');
    post({
      type: 'aiChat',
      message,
      dispatchActions: document.getElementById('dispatchActions').checked
    });
    input.value = '';
  });

  window.chrome?.webview?.addEventListener('message', (event) => {
    try {
      handleMessage(event.data);
    } catch {
      showToast(getCopy().genericError, 'error');
    }
  });

  post({ type: 'bootstrap' });
});
