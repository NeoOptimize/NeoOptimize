const state = {
  lang: 'id',
  theme: 'system',
  clientId: '',
  backendUrl: '',
  stats: {
    cpu: 0,
    ram: 0,
    disk: 0,
    temp: 0,
    healthState: 'unknown',
    integrityStatus: 'unknown',
    alerts: []
  },
  reports: [],
  activity: [],
  plannedActions: []
};

const strings = {
  id: {
    heroTitle: 'Windows optimization cockpit dengan AI, telemetry, dan execution loop real-time.',
    heroSubtitle: 'Client akan register ke Hugging Face Space, memantau kondisi lokal, lalu mendorong insight dan command execution ke Supabase.',
    actionsTitle: 'Eksekusi lokal',
    activityTitle: 'Execution timeline',
    reportsTitle: 'Laporan lokal',
    aiPanelTitle: 'Copilot siap memberi analisis',
    dispatchLabel: 'Eksekusi tindakan yang disarankan',
    aiSubmit: 'Analisa dengan Neo AI'
  },
  en: {
    heroTitle: 'Windows optimization cockpit with AI, telemetry, and a real-time execution loop.',
    heroSubtitle: 'The client registers against the Hugging Face Space, monitors local health, and pushes insights plus command execution to Supabase.',
    actionsTitle: 'Local execution',
    activityTitle: 'Execution timeline',
    reportsTitle: 'Local reports',
    aiPanelTitle: 'Copilot is ready to analyze',
    dispatchLabel: 'Execute suggested actions',
    aiSubmit: 'Analyze with Neo AI'
  }
};

function post(message) {
  window.chrome?.webview?.postMessage(message);
}

function formatPercent(value) {
  return `${Number(value ?? 0).toFixed(1)}%`;
}

function setLanguage(lang) {
  state.lang = lang;
  document.querySelectorAll('#langGroup .chip').forEach((button) => {
    button.classList.toggle('is-active', button.dataset.lang === lang);
  });
  const copy = strings[lang];
  document.getElementById('heroTitle').textContent = copy.heroTitle;
  document.getElementById('heroSubtitle').textContent = copy.heroSubtitle;
  document.getElementById('actionsTitle').textContent = copy.actionsTitle;
  document.getElementById('activityTitle').textContent = copy.activityTitle;
  document.getElementById('reportsTitle').textContent = copy.reportsTitle;
  document.getElementById('aiPanelTitle').textContent = copy.aiPanelTitle;
  document.getElementById('dispatchLabel').textContent = copy.dispatchLabel;
  document.getElementById('aiSubmit').textContent = copy.aiSubmit;
}

function setTheme(theme) {
  state.theme = theme;
  const actualTheme = theme === 'system'
    ? (window.matchMedia('(prefers-color-scheme: light)').matches ? 'light' : 'night')
    : theme;
  document.documentElement.dataset.theme = actualTheme;
  document.querySelectorAll('#themeGroup .chip').forEach((button) => {
    button.classList.toggle('is-active', button.dataset.theme === theme);
  });
}

function renderStats() {
  const cards = [
    { label: 'CPU Usage', value: state.stats.cpu, extra: state.stats.alerts?.includes('CPU') ? 'Alert' : 'Normal' },
    { label: 'RAM Usage', value: state.stats.ram, extra: state.stats.healthState },
    { label: 'Disk Usage', value: state.stats.disk, extra: state.stats.integrityStatus },
    { label: 'Temperature', value: state.stats.temp, extra: 'Thermal' }
  ];

  document.getElementById('statsGrid').innerHTML = cards.map((card) => `
    <article class="stat-card panel">
      <div class="stat-head">
        <div>
          <p class="eyebrow">${card.label}</p>
          <div class="stat-value">${formatPercent(card.value)}</div>
        </div>
        <span class="status-pill">${card.extra}</span>
      </div>
      <div class="meter">
        <div class="meter-fill" style="width:${Math.min(Number(card.value ?? 0), 100)}%"></div>
      </div>
    </article>
  `).join('');
}

function renderReports() {
  const root = document.getElementById('reportsGrid');
  if (!state.reports.length) {
    root.innerHTML = '<div class="report-card"><strong>Belum ada report</strong><p class="report-meta">Quick action dan integrity scan akan menulis report lokal di sini.</p></div>';
    return;
  }

  root.innerHTML = state.reports.map((report) => `
    <article class="report-card">
      <strong>${report.title}</strong>
      <p class="report-meta">${report.createdAt} · ${report.sizeLabel}</p>
      <p class="report-meta">${report.fileName}</p>
      <div class="report-actions">
        <button data-open-report="${report.fileName}">Open</button>
        <button data-delete-report="${report.fileName}">Delete</button>
      </div>
    </article>
  `).join('');
}

function renderActivity() {
  const root = document.getElementById('activityList');
  if (!state.activity.length) {
    root.innerHTML = '<div class="activity-item"><strong>Belum ada aktivitas</strong><p class="activity-meta">Timeline akan terisi setelah bootstrap selesai.</p></div>';
    return;
  }

  root.innerHTML = state.activity.map((item) => `
    <article class="activity-item">
      <strong>${item.title}</strong>
      <p class="activity-meta">${item.summary}</p>
      <span class="activity-tag">${item.timestamp}</span>
    </article>
  `).join('');
}

function renderPlannedActions() {
  const root = document.getElementById('plannedActions');
  if (!state.plannedActions.length) {
    root.innerHTML = '';
    return;
  }

  root.innerHTML = state.plannedActions.map((action) => `
    <div class="plan-chip">
      <strong>${action.commandName}</strong>
      <span>${action.reason}</span>
    </div>
  `).join('');
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
    delay: window.anime.stagger(85),
  });
}

function handleMessage(data) {
  switch (data.type) {
    case 'bootstrap':
      state.clientId = data.payload.clientId;
      state.backendUrl = data.payload.backendUrl;
      document.getElementById('clientId').textContent = data.payload.clientId;
      document.getElementById('backendUrl').textContent = data.payload.backendUrl;
      document.getElementById('connectionStatus').textContent = data.payload.status;
      if (Array.isArray(data.payload.reports)) {
        state.reports = data.payload.reports;
      }
      renderReports();
      break;
    case 'stats':
      state.stats = data.payload;
      renderStats();
      break;
    case 'reports':
      state.reports = data.payload;
      renderReports();
      break;
    case 'activity':
      state.activity = data.payload;
      renderActivity();
      break;
    case 'toast':
      showToast(data.payload.message, data.payload.tone);
      break;
    case 'actionResult':
      showToast(data.payload.summary, 'success');
      document.getElementById('aiStatus').textContent = 'Action complete';
      break;
    case 'aiResponse':
      document.getElementById('aiOutput').textContent = data.payload.reply;
      state.plannedActions = data.payload.plannedActions || [];
      renderPlannedActions();
      document.getElementById('aiStatus').textContent = data.payload.dispatched ? 'Command dispatched' : 'Analysis ready';
      break;
    default:
      break;
  }
}

window.addEventListener('DOMContentLoaded', () => {
  setLanguage('id');
  setTheme('system');
  renderStats();
  renderReports();
  renderActivity();
  animateIn();

  document.getElementById('themeGroup').addEventListener('click', (event) => {
    const button = event.target.closest('[data-theme]');
    if (!button) return;
    setTheme(button.dataset.theme);
  });

  document.getElementById('langGroup').addEventListener('click', (event) => {
    const button = event.target.closest('[data-lang]');
    if (!button) return;
    setLanguage(button.dataset.lang);
  });

  document.querySelectorAll('.action-card').forEach((button) => {
    button.addEventListener('click', () => {
      post({ type: 'runAction', action: button.dataset.action });
    });
  });

  document.getElementById('refreshButton').addEventListener('click', () => post({ type: 'refresh' }));
  document.getElementById('reloadReports').addEventListener('click', () => post({ type: 'listReports' }));

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
    const message = document.getElementById('aiPrompt').value.trim();
    if (!message) {
      showToast('Prompt AI tidak boleh kosong.', 'error');
      return;
    }

    document.getElementById('aiStatus').textContent = 'Analyzing';
    post({
      type: 'aiChat',
      message,
      dispatchActions: document.getElementById('dispatchActions').checked,
    });
  });

  window.chrome?.webview?.addEventListener('message', (event) => handleMessage(event.data));
  post({ type: 'bootstrap' });
});
