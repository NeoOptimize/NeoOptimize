const state = {
  lang: 'en',
  theme: 'system',
  clientId: '',
  backendUrl: '',
  appVersion: '-',
  stats: {
    cpu: null,
    ram: null,
    disk: null,
    networkMbps: null,
    healthState: 'unknown',
    integrityStatus: 'pending',
    alerts: [],
    overallScore: null,
    recommendations: [],
    issues: [],
    processCount: 0,
    topProcesses: [],
    machineName: '-',
    os: '-',
    recordedAt: '-'
  },
  reports: [],
  activity: [],
  update: {
    status: 'idle',
    currentVersion: '-',
    latestVersion: '-',
    hasUpdate: false,
    releaseUrl: 'https://github.com/NeoOptimize/NeoOptimize/releases',
    publishedAt: '',
    summary: ''
  },
  chatMessages: []
};

const translations = {
  en: {
    smartBoost: 'Smart Boost',
    smartBoostDesc: 'Instant optimization for maximum performance',
    smartOptimize: 'Smart Optimize',
    smartOptimizeDesc: 'Comprehensive system optimization',
    healthCheck: 'Health Check',
    healthCheckDesc: 'System health diagnosis',
    integrityScan: 'Integrity Scan',
    integrityScanDesc: 'Check system file integrity',
    neoAI: 'Neo AI',
    welcomeMessage: "Hello! I'm Neo AI, your real Windows system assistant.",
    autoExecute: 'Execute suggested actions',
    analyzeBtn: 'Analyze with Neo AI',
    recentActivity: 'Recent Activity',
    viewAllReports: 'View All Reports →',
    checkUpdate: 'Check Update',
    loginTitle: 'NeoOptimize Profile',
    loginDesc: 'Desktop identity, backend connection, and release channel.',
    signInGoogle: 'Connect Supabase Auth',
    savedReports: 'Saved Reports',
    profileName: 'NeoOptimize Desktop',
    profileClose: 'Close',
    noActivity: 'No activity has been recorded yet.',
    noReports: 'No local reports have been generated yet.',
    noFile: 'No report file is attached to this activity.',
    promptRequired: 'Type a message for Neo AI first.',
    updateReady: 'Update available',
    upToDate: 'Already up to date',
    clearChat: 'Clear Chat'
  },
  id: {
    smartBoost: 'Smart Boost',
    smartBoostDesc: 'Optimasi instan untuk performa maksimal',
    smartOptimize: 'Smart Optimize',
    smartOptimizeDesc: 'Optimasi menyeluruh sistem',
    healthCheck: 'Health Check',
    healthCheckDesc: 'Diagnosa kesehatan sistem',
    integrityScan: 'Integrity Scan',
    integrityScanDesc: 'Periksa integritas file sistem',
    neoAI: 'Neo AI',
    welcomeMessage: 'Halo! Saya Neo AI, asisten sistem Windows Anda yang terhubung real ke backend.',
    autoExecute: 'Eksekusi tindakan yang disarankan',
    analyzeBtn: 'Analisa dengan Neo AI',
    recentActivity: 'Aktivitas Terbaru',
    viewAllReports: 'Lihat Semua Laporan →',
    checkUpdate: 'Cek Update',
    loginTitle: 'Profil NeoOptimize',
    loginDesc: 'Identitas desktop, koneksi backend, dan jalur release.',
    signInGoogle: 'Hubungkan Supabase Auth',
    savedReports: 'Laporan Tersimpan',
    profileName: 'NeoOptimize Desktop',
    profileClose: 'Tutup',
    noActivity: 'Belum ada aktivitas yang tercatat.',
    noReports: 'Belum ada laporan lokal yang dibuat.',
    noFile: 'Aktivitas ini belum memiliki file laporan.',
    promptRequired: 'Isi pesan untuk Neo AI terlebih dahulu.',
    updateReady: 'Update tersedia',
    upToDate: 'Sudah versi terbaru',
    clearChat: 'Bersihkan Chat'
  }
};

const actionLabels = {
  smartBoost: 'Smart Boost',
  smartOptimize: 'Smart Optimize',
  healthCheck: 'Health Check',
  integrityScan: 'Integrity Scan'
};

function post(message) {
  window.chrome?.webview?.postMessage(message);
}

function getText(key) {
  return translations[state.lang]?.[key] ?? translations.en[key] ?? key;
}

function escapeHtml(value) {
  return String(value ?? '').replace(/[&<>"']/g, (character) => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#39;'
  }[character]));
}

function readSetting(key, fallback) {
  try {
    return window.localStorage.getItem(key) || fallback;
  } catch {
    return fallback;
  }
}

function writeSetting(key, value) {
  try {
    window.localStorage.setItem(key, value);
  } catch {
    // Ignore persistence failures.
  }
}

function abbreviate(value, maxLength = 64) {
  const text = String(value ?? '');
  if (!text || text.length <= maxLength) {
    return text;
  }

  return `${text.slice(0, maxLength - 3)}...`;
}

function formatPercent(value) {
  if (value === null || value === undefined || Number.isNaN(Number(value))) {
    return 'N/A';
  }

  return `${Math.round(Number(value))}%`;
}

function formatNetworkMbps(value) {
  if (value === null || value === undefined || Number.isNaN(Number(value))) {
    return 'N/A';
  }

  return `${Number(value).toFixed(1)} Mbps`;
}

function formatScore(value) {
  if (value === null || value === undefined || Number.isNaN(Number(value))) {
    return 'N/A';
  }

  return String(Math.round(Number(value)));
}

function normalizeMetric(value) {
  if (value === null || value === undefined || Number.isNaN(Number(value))) {
    return 0;
  }

  return Math.max(0, Math.min(Number(value), 100));
}

function showToast(message, tone = 'info') {
  let host = document.getElementById('toastHost');
  if (!host) {
    host = document.createElement('div');
    host.id = 'toastHost';
    host.className = 'toast-host';
    document.body.appendChild(host);
  }

  const item = document.createElement('div');
  item.className = `toast-item ${tone}`;
  item.textContent = message;
  host.appendChild(item);

  window.setTimeout(() => {
    item.remove();
    if (!host.childElementCount) {
      host.remove();
    }
  }, 4200);
}

function animateGlass() {
  if (!window.anime) {
    return;
  }

  window.anime({
    targets: '.glass',
    opacity: [0, 1],
    translateY: [30, 0],
    duration: 1000,
    delay: window.anime.stagger(100),
    easing: 'easeOutExpo'
  });
}

function setLanguage(lang) {
  state.lang = lang;
  writeSetting('neooptimize.lang', lang);
  document.documentElement.lang = lang;
  document.querySelectorAll('#langToggle span').forEach((button) => {
    button.classList.toggle('active', button.dataset.lang === lang);
  });

  document.querySelectorAll('[data-i18n]').forEach((element) => {
    const key = element.getAttribute('data-i18n');
    const text = getText(key);
    if (element.tagName === 'INPUT' || element.tagName === 'TEXTAREA') {
      element.placeholder = text;
      return;
    }

    element.textContent = text;
  });

  document.getElementById('chatInput').placeholder = lang === 'en'
    ? 'e.g., PC feels slow at startup...'
    : 'Contoh: PC terasa lambat saat startup...';

  renderStats();
  renderLogs();
  renderReports();
  renderChatMessages();
  updateProfilePanel();
  updateUpdateButton();
}

function applyTheme(theme) {
  const body = document.body;
  body.classList.remove('light-theme', 'night-theme');

  if (theme === 'light') {
    body.classList.add('light-theme');
    return;
  }

  if (theme === 'night') {
    body.classList.add('night-theme');
    return;
  }

  if (window.matchMedia && window.matchMedia('(prefers-color-scheme: light)').matches) {
    body.classList.add('light-theme');
  } else {
    body.classList.add('night-theme');
  }
}

function setTheme(theme) {
  state.theme = theme;
  writeSetting('neooptimize.theme', theme);
  document.querySelectorAll('#themeToggle span').forEach((button) => {
    button.classList.toggle('active', button.dataset.theme === theme);
  });
  applyTheme(theme);
}

function buildStatsCards() {
  const recommendation = state.stats.recommendations[0] || state.stats.healthState || 'standby';
  const alertSummary = state.stats.alerts.length ? state.stats.alerts.join(', ') : 'Normal';
  const recordedAt = state.stats.recordedAt || '-';
  const machineName = state.stats.machineName || 'Windows';
  const os = abbreviate(state.stats.os || 'Windows', 18);

  return [
    {
      icon: 'microchip',
      title: 'CPU Usage',
      value: formatPercent(state.stats.cpu),
      width: normalizeMetric(state.stats.cpu),
      footerLeft: alertSummary,
      footerRight: machineName
    },
    {
      icon: 'memory',
      title: 'RAM Usage',
      value: formatPercent(state.stats.ram),
      width: normalizeMetric(state.stats.ram),
      footerLeft: `Score ${formatScore(state.stats.overallScore)}`,
      footerRight: abbreviate(recommendation, 20) || 'Memory'
    },
    {
      icon: 'hdd',
      title: 'Disk Usage',
      value: formatPercent(state.stats.disk),
      width: normalizeMetric(state.stats.disk),
      footerLeft: state.stats.integrityStatus || 'pending',
      footerRight: os
    },
    {
      icon: 'network-wired',
      title: 'Network',
      value: formatNetworkMbps(state.stats.networkMbps),
      width: normalizeMetric(state.stats.networkMbps),
      footerLeft: state.stats.healthState || 'unknown',
      footerRight: recordedAt
    }
  ];
}

function renderStats() {
  const grid = document.getElementById('statsGrid');
  const cards = buildStatsCards();
  grid.innerHTML = cards.map((card) => `
    <div class="stat-card glass">
      <div class="stat-header">
        <div class="stat-icon"><i class="fas fa-${escapeHtml(card.icon)}"></i></div>
        <div>
          <div class="stat-title">${escapeHtml(card.title)}</div>
          <div class="stat-value">${escapeHtml(card.value)}</div>
        </div>
      </div>
      <div class="progress-bar"><div class="progress-fill" style="width:${card.width}%"></div></div>
      <div class="stat-footer"><span>${escapeHtml(card.footerLeft)}</span><span>${escapeHtml(card.footerRight)}</span></div>
    </div>
  `).join('');
}

function inferLogIcon(title) {
  const value = String(title || '').toLowerCase();
  if (value.includes('boost')) {
    return 'bolt';
  }
  if (value.includes('health')) {
    return 'heartbeat';
  }
  if (value.includes('integrity')) {
    return 'shield-alt';
  }
  if (value.includes('optimize')) {
    return 'microchip';
  }
  if (value.includes('ai')) {
    return 'robot';
  }
  if (value.includes('report') || value.includes('scan')) {
    return 'file-alt';
  }
  return 'history';
}

function buildLogs() {
  if (!state.activity.length) {
    return [];
  }

  return state.activity.map((item) => ({
    icon: inferLogIcon(item.title),
    title: item.title,
    time: item.timestamp,
    summary: item.summary,
    file: item.file || item.reportFile || null
  }));
}

function renderLogs() {
  const list = document.getElementById('logsList');
  const logs = buildLogs();
  if (!logs.length) {
    list.innerHTML = `<li class="log-item"><div class="log-details"><div class="log-title">${escapeHtml(getText('noActivity'))}</div></div></li>`;
    return;
  }

  list.innerHTML = logs.map((log) => `
    <li class="log-item">
      <div class="log-info">
        <div class="log-icon"><i class="fas fa-${escapeHtml(log.icon)}"></i></div>
        <div class="log-details">
          <div class="log-title">${escapeHtml(log.title)}</div>
          <div class="log-time">${escapeHtml(log.time)}${log.summary ? ` · ${escapeHtml(abbreviate(log.summary, 72))}` : ''}</div>
        </div>
      </div>
      <div class="log-actions">
        <i class="fas fa-eye ${log.file ? '' : 'disabled'}" onclick="openReport('${escapeHtml(log.file || '')}')"></i>
        <i class="fas fa-trash ${log.file ? '' : 'disabled'}" onclick="deleteReport('${escapeHtml(log.file || '')}')"></i>
      </div>
    </li>
  `).join('');
}

function renderReports() {
  const container = document.getElementById('reportsList');
  if (!state.reports.length) {
    container.innerHTML = `<div class="empty-state">${escapeHtml(getText('noReports'))}</div>`;
    return;
  }

  container.innerHTML = state.reports.map((report) => `
    <div class="report-card">
      <div class="report-date">${escapeHtml(report.title || report.fileName)}</div>
      <div class="report-size">${escapeHtml(report.createdAt)} · ${escapeHtml(report.sizeLabel)}</div>
      <div class="report-actions">
        <i class="fas fa-eye" onclick="openReport('${escapeHtml(report.fileName)}')"></i>
        <i class="fas fa-trash" onclick="deleteReport('${escapeHtml(report.fileName)}')"></i>
      </div>
    </div>
  `).join('');
}

function renderChatMessages() {
  const container = document.getElementById('chatMessages');
  if (!state.chatMessages.length) {
    container.innerHTML = `<div class="message ai">${escapeHtml(getText('welcomeMessage'))}</div>`;
    return;
  }

  container.innerHTML = state.chatMessages.map((message) => `
    <div class="message ${escapeHtml(message.role)}">
      <div>${escapeHtml(message.text)}</div>
      ${message.meta ? `<div class="message-meta">${escapeHtml(message.meta)}</div>` : ''}
    </div>
  `).join('');
  container.scrollTop = container.scrollHeight;
}

function addChatMessage(role, text, meta = '') {
  state.chatMessages.push({ role, text, meta });
  if (state.chatMessages.length > 18) {
    state.chatMessages = state.chatMessages.slice(-18);
  }
  renderChatMessages();
}

function buildProfileEmail() {
  const parts = [];
  if (state.clientId) {
    parts.push(abbreviate(state.clientId, 24));
  }
  if (state.appVersion && state.appVersion !== '-') {
    parts.push(`v${state.appVersion}`);
  }
  if (state.backendUrl) {
    parts.push(abbreviate(state.backendUrl, 36));
  }
  return parts.join(' · ') || 'NeoOptimize';
}

function updateProfilePanel() {
  const loginContent = document.getElementById('loginContent');
  const userProfile = document.getElementById('userProfile');
  const userAvatar = document.getElementById('userAvatar');
  const userName = document.getElementById('userName');
  const userEmail = document.getElementById('userEmail');
  const closeButton = document.getElementById('logoutBtn');
  const hiddenGoogleButton = document.getElementById('googleLoginBtn');

  loginContent.style.display = 'none';
  userProfile.style.display = 'block';
  hiddenGoogleButton.style.display = 'none';
  userAvatar.src = './assets/neooptimize.ico';
  userName.textContent = getText('profileName');
  userEmail.textContent = buildProfileEmail();
  closeButton.innerHTML = `<i class="fas fa-times-circle"></i> ${escapeHtml(getText('profileClose'))}`;
}

function updateClientBadge() {
  document.getElementById('clientIdDisplay').textContent = state.clientId || 'Belum terdaftar';
}

function updateUpdateButton() {
  const label = document.querySelector('#updateBtn span[data-i18n="checkUpdate"]');
  if (!label) {
    return;
  }

  if (state.update.status === 'update-available') {
    label.textContent = getText('updateReady');
    return;
  }

  if (state.update.status === 'up-to-date') {
    label.textContent = getText('upToDate');
    return;
  }

  label.textContent = getText('checkUpdate');
}

function clearChat() {
  state.chatMessages = [];
  renderChatMessages();
}

function sendPrompt(overrideMessage) {
  const input = document.getElementById('chatInput');
  const message = (overrideMessage ?? input.value).trim();
  if (!message) {
    showToast(getText('promptRequired'), 'error');
    return;
  }

  addChatMessage('user', message, state.stats.recordedAt || state.stats.machineName || 'desktop');
  post({
    type: 'aiChat',
    message,
    dispatchActions: document.getElementById('autoExecute').checked
  });
  input.value = '';
}

function runAction(action) {
  const element = document.getElementById(`${action}Btn`);
  if (window.anime && element) {
    window.anime({
      targets: element,
      scale: [1, 1.03, 1],
      duration: 500,
      easing: 'easeInOutSine'
    });
  }

  addChatMessage('user', `${actionLabels[action] || action} requested`, state.clientId || 'desktop');
  post({ type: 'runAction', action });
}

function openReportsModal() {
  renderReports();
  document.getElementById('reportsModal').style.display = 'flex';
}

function closeModal() {
  document.getElementById('reportsModal').style.display = 'none';
}

function closeLoginModal() {
  document.getElementById('loginModal').style.display = 'none';
}

function openReport(fileName) {
  if (!fileName) {
    showToast(getText('noFile'), 'info');
    return;
  }

  post({ type: 'openReport', fileName });
}

function deleteReport(fileName) {
  if (!fileName) {
    showToast(getText('noFile'), 'info');
    return;
  }

  if (!window.confirm('Hapus laporan ini?')) {
    return;
  }

  post({ type: 'deleteReport', fileName });
}

function applyBootstrap(payload) {
  state.clientId = payload.clientId || state.clientId;
  state.backendUrl = payload.backendUrl || state.backendUrl;
  state.appVersion = payload.appVersion || state.appVersion;
  state.update.currentVersion = state.appVersion;
  state.reports = Array.isArray(payload.reports) ? payload.reports : state.reports;
  updateClientBadge();
  updateProfilePanel();
  renderReports();

  if (!state.chatMessages.length) {
    addChatMessage('ai', getText('welcomeMessage'), buildProfileEmail());
  }
}

function appendPlannedActions(plannedActions) {
  if (!Array.isArray(plannedActions) || !plannedActions.length) {
    return '';
  }

  const actions = plannedActions.map((item) => `${item.commandName}${item.dispatched ? ' queued' : ''}`).join(', ');
  return `Planned: ${actions}`;
}

function handleMessage(data) {
  switch (data.type) {
    case 'bootstrap':
      applyBootstrap(data.payload || {});
      break;
    case 'stats':
      state.stats = {
        ...state.stats,
        ...data.payload,
        alerts: Array.isArray(data.payload?.alerts) ? data.payload.alerts : [],
        recommendations: Array.isArray(data.payload?.recommendations) ? data.payload.recommendations : [],
        issues: Array.isArray(data.payload?.issues) ? data.payload.issues : [],
        topProcesses: Array.isArray(data.payload?.topProcesses) ? data.payload.topProcesses : []
      };
      renderStats();
      break;
    case 'reports':
      state.reports = Array.isArray(data.payload) ? data.payload : [];
      renderReports();
      break;
    case 'activity':
      state.activity = Array.isArray(data.payload) ? data.payload : [];
      renderLogs();
      break;
    case 'toast':
      showToast(data.payload?.message || '', data.payload?.tone || 'info');
      break;
    case 'actionResult':
      addChatMessage('ai', data.payload?.summary || 'Action completed.', data.payload?.reportFile || 'local execution');
      showToast(data.payload?.summary || 'Action completed.', 'success');
      break;
    case 'aiResponse': {
      const plannedSummary = appendPlannedActions(data.payload?.plannedActions);
      const memorySummary = Array.isArray(data.payload?.memoryHits) && data.payload.memoryHits.length
        ? `Memory hits: ${data.payload.memoryHits.length}`
        : '';
      const meta = [data.payload?.correlationId ? `Correlation ${data.payload.correlationId}` : '', plannedSummary, memorySummary]
        .filter(Boolean)
        .join(' · ');
      addChatMessage('ai', data.payload?.reply || 'Neo AI returned an empty response.', meta);
      break;
    }
    case 'updateStatus':
      state.update = {
        ...state.update,
        ...data.payload
      };
      updateUpdateButton();
      if (state.update.summary) {
        showToast(state.update.summary, state.update.status === 'check-failed' ? 'error' : 'info');
      }
      break;
    default:
      break;
  }

  renderStats();
  renderLogs();
  renderReports();
  updateClientBadge();
  updateProfilePanel();
}

function bindThemeControls() {
  document.querySelectorAll('#themeToggle span').forEach((button) => {
    button.addEventListener('click', () => {
      setTheme(button.dataset.theme);
    });
  });

  if (window.matchMedia) {
    window.matchMedia('(prefers-color-scheme: light)').addEventListener('change', () => {
      if (state.theme === 'system') {
        applyTheme('system');
      }
    });
  }
}

function bindLanguageControls() {
  document.querySelectorAll('#langToggle span').forEach((button) => {
    button.addEventListener('click', () => {
      setLanguage(button.dataset.lang);
    });
  });
}

function init() {
  animateGlass();
  bindThemeControls();
  bindLanguageControls();

  document.getElementById('profileBtn').addEventListener('click', () => {
    updateProfilePanel();
    document.getElementById('loginModal').style.display = 'flex';
  });

  document.getElementById('logoutBtn').addEventListener('click', closeLoginModal);
  document.getElementById('updateBtn').addEventListener('click', () => post({ type: 'checkUpdate' }));
  document.getElementById('smartBoostBtn').addEventListener('click', () => runAction('smartBoost'));
  document.getElementById('smartOptimizeBtn').addEventListener('click', () => runAction('smartOptimize'));
  document.getElementById('healthCheckBtn').addEventListener('click', () => runAction('healthCheck'));
  document.getElementById('integrityScanBtn').addEventListener('click', () => runAction('integrityScan'));
  document.getElementById('sendChat').addEventListener('click', sendPrompt);
  document.getElementById('clearChatBtn').addEventListener('click', clearChat);
  document.getElementById('analyzeBtn').addEventListener('click', sendPrompt);
  document.getElementById('chatInput').addEventListener('keydown', (event) => {
    if (event.key === 'Enter') {
      event.preventDefault();
      sendPrompt();
    }
  });

  document.getElementById('loginModal').addEventListener('click', (event) => {
    if (event.target.id === 'loginModal') {
      closeLoginModal();
    }
  });

  document.getElementById('reportsModal').addEventListener('click', (event) => {
    if (event.target.id === 'reportsModal') {
      closeModal();
    }
  });

  state.lang = readSetting('neooptimize.lang', 'en');
  state.theme = readSetting('neooptimize.theme', 'system');
  setTheme(state.theme);
  setLanguage(state.lang);
  updateProfilePanel();
  renderStats();
  renderLogs();
  renderReports();
  renderChatMessages();

  if (window.chrome?.webview) {
    window.chrome.webview.addEventListener('message', (event) => {
      handleMessage(event.data);
    });
    post({ type: 'bootstrap' });
  }
}

window.openReportsModal = openReportsModal;
window.closeModal = closeModal;
window.closeLoginModal = closeLoginModal;
window.openReport = openReport;
window.deleteReport = deleteReport;
window.setTheme = setTheme;
window.setLanguage = setLanguage;

window.addEventListener('DOMContentLoaded', init);
