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
  chatMessages: [],
  consents: {
    accepted: false,
    telemetry: true,
    diagnostics: true,
    maintenance: true,
    remoteControl: false,
    autoExecution: false,
    location: false,
    camera: false
  }
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
    clearChat: 'Clear Chat',
    bloatwareTitle: 'Bloatware Removal Library',
    bloatwareSubtitle: 'Recommended packages to remove (safe for most users).',
    cleanerTitle: 'Cleaner & Optimize Toolkit',
    cleanerSubtitle: 'All core optimizations available manually or via Neo AI.',
    trayActive: 'Tray Active',
    miniTrayTitle: 'NeoOptimize Mini Tray',
    miniTraySubtitle: 'Live widgets for chatbot and cleaner.',
    miniChatbot: 'Live Chatbot',
    miniCleaner: 'AI Phone Cleaner',
    voiceNotSupported: 'Voice input is not supported on this device.',
    voiceListening: 'Listening for voice command...',
    voiceError: 'Voice error',
    consentRequired: 'Consent required before using voice commands.',
    diagnosticsConsentRequired: 'Diagnostics consent is required for this action.',
    maintenanceConsentRequired: 'Maintenance consent is required for this action.',
    neoAiVisualTitle: 'Neo AI Visual',
    neoAiModeGreeting: 'Greeting',
    neoAiModeStandby: 'Standby',
    neoAiModeIdle: 'Idle',
    neoAiModeOptimize: 'Optimizing',
    neoAiModeDump: 'Cleaning Dump',
    voiceCommandsTitle: 'Voice Command Library',
    voiceCommandsSubtitle: 'Say a command to trigger actions instantly.',
    voiceCommandsNote: 'Auto-map',
    voiceActionBoost: 'Smart Boost',
    voiceActionOptimize: 'Smart Optimize',
    voiceActionHealth: 'Health Check',
    voiceActionIntegrity: 'Integrity Scan',
    voiceActionDump: 'Dump Cleanup',
    voiceActionFlushDns: 'Flush DNS',
    voiceActionClearTemp: 'Clear Temp Files',
    voiceActionUpdate: 'Check Update',
    voiceActionCleanAll: 'Clean Everything',
    voiceActionFullOptimize: 'Full System Optimization',
    voiceActionMaintenance: 'Maintenance Mode',
    voiceActionAutoMode: 'Auto Mode',
    voiceActionManualMode: 'Manual Mode',
    voiceActionOpenReports: 'Open Reports',
    voiceActionClearChat: 'Clear Chat',
    voiceActionSequence: 'Multi-step',
    voiceActionUi: 'UI Action',
    voiceActionAiAssist: 'AI Assist',
    voiceActionAi: 'AI Assist'
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
    clearChat: 'Bersihkan Chat',
    bloatwareTitle: 'Library Bloatware Removal',
    bloatwareSubtitle: 'Paket yang direkomendasikan untuk dihapus (aman untuk mayoritas user).',
    cleanerTitle: 'Toolkit Cleaner & Optimize',
    cleanerSubtitle: 'Semua optimasi inti tersedia manual atau via Neo AI.',
    trayActive: 'Tray Aktif',
    miniTrayTitle: 'NeoOptimize Mini Tray',
    miniTraySubtitle: 'Widget live untuk chatbot dan cleaner.',
    miniChatbot: 'Live Chatbot',
    miniCleaner: 'AI Phone Cleaner',
    voiceNotSupported: 'Input suara tidak didukung di perangkat ini.',
    voiceListening: 'Mendengarkan perintah suara...',
    voiceError: 'Kesalahan suara',
    consentRequired: 'Consent wajib sebelum menggunakan perintah suara.',
    diagnosticsConsentRequired: 'Consent Diagnostics wajib untuk tindakan ini.',
    maintenanceConsentRequired: 'Consent Maintenance wajib untuk tindakan ini.',
    neoAiVisualTitle: 'Visual Neo AI',
    neoAiModeGreeting: 'Sapaan',
    neoAiModeStandby: 'Siaga',
    neoAiModeIdle: 'Idle',
    neoAiModeOptimize: 'Optimasi',
    neoAiModeDump: 'Bersihkan Dump',
    voiceCommandsTitle: 'Library Perintah Suara',
    voiceCommandsSubtitle: 'Ucapkan perintah untuk mengeksekusi fitur dengan cepat.',
    voiceCommandsNote: 'Auto-map',
    voiceActionBoost: 'Smart Boost',
    voiceActionOptimize: 'Smart Optimize',
    voiceActionHealth: 'Health Check',
    voiceActionIntegrity: 'Integrity Scan',
    voiceActionDump: 'Bersihkan Dump',
    voiceActionFlushDns: 'Flush DNS',
    voiceActionClearTemp: 'Bersihkan Temp',
    voiceActionUpdate: 'Cek Update',
    voiceActionCleanAll: 'Bersihkan Semua',
    voiceActionFullOptimize: 'Optimasi Penuh',
    voiceActionMaintenance: 'Mode Perawatan',
    voiceActionAutoMode: 'Mode Otomatis',
    voiceActionManualMode: 'Mode Manual',
    voiceActionOpenReports: 'Buka Laporan',
    voiceActionClearChat: 'Bersihkan Chat',
    voiceActionSequence: 'Multi-step',
    voiceActionUi: 'Aksi UI',
    voiceActionAiAssist: 'AI Assist',
    voiceActionAi: 'AI Assist'
  }
};

const actionLabels = {
  smartBoost: 'Smart Boost',
  smartOptimize: 'Smart Optimize',
  healthCheck: 'Health Check',
  integrityScan: 'Integrity Scan',
  flushDns: 'Flush DNS',
  clearTempFiles: 'Clear Temp Files'
};

const bloatwareCatalog = [
  {
    labelEn: 'Xbox App Suite',
    labelId: 'Paket Xbox',
    descEn: 'Consumer Xbox apps that are safe to remove on non-gaming PCs.',
    descId: 'Aplikasi Xbox konsumer yang aman dihapus jika bukan gaming PC.',
    packageId: 'Microsoft.XboxApp / Microsoft.XboxGamingOverlay',
    tags: ['Auto', 'Admin']
  },
  {
    labelEn: 'Xbox Game Bar',
    labelId: 'Xbox Game Bar',
    descEn: 'Overlay recording tools; optional for most users.',
    descId: 'Overlay perekam layar; opsional bagi sebagian besar user.',
    packageId: 'Microsoft.XboxGameOverlay / Microsoft.Xbox.TCUI',
    tags: ['Auto', 'Admin']
  },
  {
    labelEn: 'Gaming Services',
    labelId: 'Gaming Services',
    descEn: 'Gaming services component, remove if not using Xbox/Game Pass.',
    descId: 'Komponen Gaming Services; hapus jika tidak memakai Xbox/Game Pass.',
    packageId: 'Microsoft.GamingApp / Microsoft.XboxIdentityProvider',
    tags: ['Auto', 'Admin']
  },
  {
    labelEn: 'Mixed Reality Portal',
    labelId: 'Mixed Reality Portal',
    descEn: 'VR/MR portal; safe to remove if unused.',
    descId: 'Portal VR/MR; aman dihapus jika tidak digunakan.',
    packageId: 'Microsoft.MixedReality.Portal',
    tags: ['Auto']
  },
  {
    labelEn: '3D Viewer',
    labelId: '3D Viewer',
    descEn: '3D viewer utility; optional.',
    descId: 'Utility 3D viewer; opsional.',
    packageId: 'Microsoft.Microsoft3DViewer',
    tags: ['Auto']
  },
  {
    labelEn: 'Skype (UWP)',
    labelId: 'Skype (UWP)',
    descEn: 'Legacy UWP Skype app.',
    descId: 'Aplikasi Skype UWP lama.',
    packageId: 'Microsoft.SkypeApp',
    tags: ['Auto']
  },
  {
    labelEn: 'Zune Music/Video',
    labelId: 'Zune Music/Video',
    descEn: 'Legacy media apps.',
    descId: 'Aplikasi media lama.',
    packageId: 'Microsoft.ZuneMusic / Microsoft.ZuneVideo',
    tags: ['Auto']
  },
  {
    labelEn: 'People & Feedback Hub',
    labelId: 'People & Feedback Hub',
    descEn: 'Contact app and feedback hub; optional.',
    descId: 'Kontak dan feedback hub; opsional.',
    packageId: 'Microsoft.People / Microsoft.WindowsFeedbackHub',
    tags: ['Auto']
  },
  {
    labelEn: 'Bing News/Weather',
    labelId: 'Bing News/Weather',
    descEn: 'Consumer news widgets; optional.',
    descId: 'Widget berita konsumer; opsional.',
    packageId: 'Microsoft.BingNews / Microsoft.BingWeather',
    tags: ['Auto']
  },
  {
    labelEn: 'Your Phone',
    labelId: 'Your Phone',
    descEn: 'Phone linking app; optional.',
    descId: 'Aplikasi link ponsel; opsional.',
    packageId: 'Microsoft.YourPhone',
    tags: ['Auto']
  },
  {
    labelEn: 'Clipchamp',
    labelId: 'Clipchamp',
    descEn: 'Video editor; optional for most users.',
    descId: 'Editor video; opsional untuk sebagian user.',
    packageId: 'Clipchamp.Clipchamp',
    tags: ['Auto']
  },
  {
    labelEn: 'Microsoft Teams (Consumer)',
    labelId: 'Microsoft Teams (Consumer)',
    descEn: 'Consumer Teams app.',
    descId: 'Aplikasi Teams konsumer.',
    packageId: 'MicrosoftTeams',
    tags: ['Auto']
  }
];

const cleanerCatalog = [
  {
    labelEn: 'Flush DNS Cache',
    labelId: 'Flush DNS Cache',
    descEn: 'Clear DNS resolver cache for fresh routing.',
    descId: 'Bersihkan cache DNS untuk koneksi yang segar.',
    tags: ['Manual', 'Auto']
  },
  {
    labelEn: 'Temporary Files Cleanup',
    labelId: 'Pembersihan File Temporary',
    descEn: 'Remove temp files and stale cache safely.',
    descId: 'Hapus file temp dan cache lama secara aman.',
    tags: ['Manual', 'Auto']
  },
  {
    labelEn: 'Crash Dump & WER Cleanup',
    labelId: 'Pembersihan Dump & WER',
    descEn: 'Remove MEMORY.DMP, Minidump, LiveKernel, and WER logs.',
    descId: 'Bersihkan MEMORY.DMP, Minidump, LiveKernel, dan log WER.',
    tags: ['Manual', 'Auto', 'Admin']
  },
  {
    labelEn: 'Trim RAM Working Set',
    labelId: 'Trim Working Set RAM',
    descEn: 'Release unused working set memory.',
    descId: 'Lepaskan working set RAM yang tidak terpakai.',
    tags: ['Manual', 'Auto']
  },
  {
    labelEn: 'Stop Optional Background Apps',
    labelId: 'Hentikan Background Opsional',
    descEn: 'Stop optional apps like OneDrive, Teams, Discord (best effort).',
    descId: 'Hentikan aplikasi opsional seperti OneDrive, Teams, Discord.',
    tags: ['Manual', 'Auto']
  },
  {
    labelEn: 'NeoOptimize Priority Boost',
    labelId: 'Priority Boost NeoOptimize',
    descEn: 'Increase NeoOptimize process priority for stability.',
    descId: 'Naikkan prioritas proses NeoOptimize untuk stabilitas.',
    tags: ['Auto']
  },
  {
    labelEn: 'System Health Check (SFC/DISM)',
    labelId: 'Health Check Sistem (SFC/DISM)',
    descEn: 'Verify integrity with SFC and DISM checks.',
    descId: 'Verifikasi integritas dengan SFC dan DISM.',
    tags: ['Manual', 'Auto', 'Admin']
  },
  {
    labelEn: 'Integrity Scan (SHA-256)',
    labelId: 'Integrity Scan (SHA-256)',
    descEn: 'SHA-256 scan for NeoOptimize installation files.',
    descId: 'Pindai SHA-256 untuk file instalasi NeoOptimize.',
    tags: ['Manual', 'Auto']
  }
];

const neoAiVideoModes = {
  greeting: {
    src: './assets/videos/greeting.mp4',
    labelKey: 'neoAiModeGreeting',
    loop: false
  },
  standby: {
    src: './assets/videos/standby.mp4',
    labelKey: 'neoAiModeStandby',
    loop: true
  },
  idle1: {
    src: './assets/videos/idle-1.mp4',
    labelKey: 'neoAiModeIdle',
    loop: true
  },
  idle2: {
    src: './assets/videos/idle-2.mp4',
    labelKey: 'neoAiModeIdle',
    loop: true
  },
  optimize: {
    src: './assets/videos/optimize.mp4',
    labelKey: 'neoAiModeOptimize',
    loop: true
  },
  dump: {
    src: './assets/videos/cleaning-dump.mp4',
    labelKey: 'neoAiModeDump',
    loop: true
  }
};

const actionModeMap = {
  smartBoost: 'optimize',
  smartOptimize: 'optimize',
  healthCheck: 'standby',
  integrityScan: 'standby',
  flushDns: 'standby',
  clearTempFiles: 'standby'
};

const voiceCommandRules = [
  {
    labelKey: 'voiceActionBoost',
    phrases: [
      'smart boost',
      'jalankan smart boost',
      'boost',
      'boost performa',
      'boost performance',
      'optimasi cepat',
      'percepat pc',
      'free up ram',
      'clear memory cache',
      'bersihkan ram',
      'bebaskan memori',
      'ram boost',
      'turbo',
      'stop background apps',
      'matikan proses background',
      'hentikan aplikasi latar'
    ],
    action: 'smartBoost',
    mode: 'optimize'
  },
  {
    labelKey: 'voiceActionOptimize',
    phrases: [
      'smart optimize',
      'optimasi sistem',
      'optimize system',
      'optimasi menyeluruh',
      'optimasi lengkap',
      'optimasi total',
      'tuning windows',
      'clean pc',
      'bersihkan sistem',
      'maintenance system'
    ],
    action: 'smartOptimize',
    mode: 'optimize'
  },
  {
    labelKey: 'voiceActionHealth',
    phrases: [
      'health check',
      'cek health',
      'cek kesehatan',
      'diagnosa sistem',
      'diagnosa windows',
      'system check',
      'cek sistem',
      'health report',
      'cek sfc',
      'cek dism',
      'health'
    ],
    action: 'healthCheck',
    mode: 'standby'
  },
  {
    labelKey: 'voiceActionIntegrity',
    phrases: [
      'integrity scan',
      'cek integritas',
      'scan integritas',
      'integrity check',
      'scan file',
      'cek file',
      'integrity'
    ],
    action: 'integrityScan',
    mode: 'standby'
  },
  {
    labelKey: 'voiceActionDump',
    phrases: [
      'clean dump',
      'cleaning dump',
      'clean dump file',
      'bersihkan dump',
      'hapus dump',
      'dump file',
      'clean memory dump',
      'hapus memory dump',
      'bersihkan crash dump',
      'scan dump file',
      'scan file dump'
    ],
    action: 'smartOptimize',
    mode: 'dump'
  },
  {
    labelKey: 'voiceActionFlushDns',
    phrases: ['flush dns', 'bersihkan dns', 'reset dns', 'dns flush', 'refresh dns', 'reset internet'],
    action: 'flushDns',
    mode: 'standby'
  },
  {
    labelKey: 'voiceActionClearTemp',
    phrases: [
      'clear temp',
      'bersihkan temp',
      'hapus temp',
      'clean temp files',
      'delete temporary files',
      'remove temp',
      'bersihkan file sementara',
      'bersihkan cache',
      'clear cache',
      'clean temp'
    ],
    action: 'clearTempFiles',
    mode: 'standby'
  },
  {
    labelKey: 'voiceActionUpdate',
    phrases: ['check update', 'cek update', 'periksa update', 'update aplikasi', 'update neooptimize', 'cek versi'],
    command: 'checkUpdate',
    mode: 'standby',
    type: 'system'
  },
  {
    labelKey: 'voiceActionCleanAll',
    phrases: ['clean everything', 'bersihkan semuanya', 'bersihkan semua', 'clean all'],
    sequence: ['clearTempFiles', 'flushDns', 'smartOptimize'],
    mode: 'optimize',
    type: 'sequence'
  },
  {
    labelKey: 'voiceActionFullOptimize',
    phrases: ['full system optimization', 'optimasi penuh', 'optimasi total', 'full optimize'],
    sequence: ['smartBoost', 'smartOptimize', 'healthCheck'],
    mode: 'optimize',
    type: 'sequence'
  },
  {
    labelKey: 'voiceActionMaintenance',
    phrases: ['maintenance mode', 'mode maintenance', 'mode perawatan'],
    sequence: ['integrityScan', 'healthCheck'],
    mode: 'standby',
    type: 'sequence'
  },
  {
    labelKey: 'voiceActionAutoMode',
    phrases: ['switch to auto mode', 'mode otomatis', 'aktifkan auto mode', 'auto mode'],
    type: 'ui',
    uiAction: 'autoOn'
  },
  {
    labelKey: 'voiceActionManualMode',
    phrases: ['switch to manual mode', 'mode manual', 'nonaktifkan auto', 'manual mode'],
    type: 'ui',
    uiAction: 'autoOff'
  },
  {
    labelKey: 'voiceActionOpenReports',
    phrases: ['open reports', 'lihat laporan', 'buka laporan', 'open report'],
    type: 'ui',
    uiAction: 'openReports'
  },
  {
    labelKey: 'voiceActionClearChat',
    phrases: ['clear chat', 'bersihkan chat', 'hapus chat'],
    type: 'ui',
    uiAction: 'clearChat'
  },
  {
    labelKey: 'voiceActionAiAssist',
    phrases: [
      'defrag',
      'defragment',
      'trim ssd',
      'optimize ssd',
      'update driver',
      'update drivers',
      'driver update',
      'backup registry',
      'backup driver',
      'restore system',
      'recycle bin',
      'empty recycle bin',
      'browser cache',
      'chrome cache',
      'firefox cache',
      'edge cache',
      'prefetch',
      'log files',
      'duplicate files',
      'empty folders',
      'reset network',
      'fix network',
      'fix boot',
      'bootloader',
      'startup programs',
      'optimize startup',
      'disable bloatware',
      'wipe free space',
      'scan disk',
      'repair system',
      'fix system crash',
      'optimize services',
      'disable services',
      'clean windows store cache'
    ],
    type: 'ai'
  }
];

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

let speechRecognizer = null;
let isListening = false;

function initVoiceControls() {
  const voiceButton = document.getElementById('voiceBtn');
  if (!voiceButton) {
    return;
  }

  const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
  if (!SpeechRecognition) {
    voiceButton.classList.add('disabled');
    voiceButton.title = getText('voiceNotSupported');
    return;
  }

  speechRecognizer = new SpeechRecognition();
  speechRecognizer.lang = state.lang === 'id' ? 'id-ID' : 'en-US';
  speechRecognizer.interimResults = false;
  speechRecognizer.maxAlternatives = 1;

  speechRecognizer.onstart = () => {
    isListening = true;
    voiceButton.classList.add('listening');
    showToast(getText('voiceListening'), 'info');
  };

  speechRecognizer.onend = () => {
    isListening = false;
    voiceButton.classList.remove('listening');
  };

  speechRecognizer.onerror = (event) => {
    isListening = false;
    voiceButton.classList.remove('listening');
    showToast(`${getText('voiceError')}: ${event.error || 'unknown'}`, 'error');
  };

  speechRecognizer.onresult = (event) => {
    const transcript = event.results?.[0]?.[0]?.transcript || '';
    if (!transcript) {
      return;
    }
    const input = document.getElementById('chatInput');
    input.value = transcript;
    handleVoiceTranscript(transcript);
  };

  voiceButton.addEventListener('click', toggleVoiceRecognition);
}

function toggleVoiceRecognition() {
  if (!speechRecognizer) {
    showToast(getText('voiceNotSupported'), 'error');
    return;
  }

  if (!state.consents.accepted) {
    showToast(getText('consentRequired'), 'error');
    openConsentModal();
    return;
  }

  if (isListening) {
    speechRecognizer.stop();
    return;
  }

  speechRecognizer.lang = state.lang === 'id' ? 'id-ID' : 'en-US';
  try {
    speechRecognizer.start();
  } catch {
    // Ignore duplicate start calls.
  }
}

function normalizeVoiceCommand(value) {
  return String(value || '')
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function resolveVoiceCommand(transcript) {
  const normalized = normalizeVoiceCommand(transcript);
  if (!normalized) {
    return null;
  }

  for (const rule of voiceCommandRules) {
    if (rule.phrases.some((phrase) => normalized.includes(phrase))) {
      return rule;
    }
  }

  return null;
}

function handleVoiceTranscript(transcript) {
  const resolved = resolveVoiceCommand(transcript);
  if (resolved) {
    addChatMessage('user', `Voice: ${transcript}`, state.clientId || 'desktop');
    if (resolved.type === 'system' && resolved.command === 'checkUpdate') {
      if (resolved.mode) {
        setNeoAiMode(resolved.mode, { temporary: true, durationMs: 6000 });
      }
      post({ type: 'checkUpdate' });
      showToast(getText('voiceActionUpdate'), 'success');
      return;
    }

    if (resolved.type === 'sequence') {
      if (resolved.mode) {
        setNeoAiMode(resolved.mode, { temporary: true, durationMs: 16000 });
      }
      runActionSequence(resolved.sequence || []);
      showToast(getText(resolved.labelKey || 'voiceActionSequence'), 'success');
      return;
    }

    if (resolved.type === 'ui') {
      handleUiVoiceCommand(resolved.uiAction);
      showToast(getText(resolved.labelKey || 'voiceActionUi'), 'success');
      return;
    }

    if (resolved.type === 'ai') {
      sendPrompt(transcript);
      showToast(getText('voiceActionAiAssist'), 'info');
      return;
    }

    runAction(resolved.action, resolved.mode);
    showToast(`Voice command: ${resolved.action}`, 'success');
    return;
  }

  sendPrompt(transcript);
}

function runActionSequence(actions) {
  if (!Array.isArray(actions) || !actions.length) {
    return;
  }

  actions.forEach((action, index) => {
    window.setTimeout(() => {
      runAction(action);
    }, index * 1500);
  });
}

function handleUiVoiceCommand(uiAction) {
  switch (uiAction) {
    case 'autoOn': {
      const toggle = document.getElementById('autoExecute');
      if (toggle) {
        toggle.checked = true;
      }
      break;
    }
    case 'autoOff': {
      const toggle = document.getElementById('autoExecute');
      if (toggle) {
        toggle.checked = false;
      }
      break;
    }
    case 'openReports':
      openReportsModal();
      break;
    case 'clearChat':
      clearChat();
      break;
    default:
      break;
  }
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

function animateLibrary() {
  if (!window.anime) {
    return;
  }

  window.anime({
    targets: '.library-item',
    opacity: [0, 1],
    translateY: [12, 0],
    delay: window.anime.stagger(40),
    duration: 600,
    easing: 'easeOutQuad'
  });
}

function animateTray() {
  if (!window.anime) {
    return;
  }

  window.anime({
    targets: '#trayDot',
    scale: [1, 1.4],
    opacity: [0.6, 1],
    direction: 'alternate',
    easing: 'easeInOutSine',
    duration: 900,
    loop: true
  });
}

function initMiniTrayAnimations() {
  if (!window.lottie) {
    return;
  }

  const chatbotContainer = document.getElementById('lottieChatbot');
  const cleanerContainer = document.getElementById('lottieCleaner');

  if (chatbotContainer) {
    window.lottie.loadAnimation({
      container: chatbotContainer,
      renderer: 'svg',
      loop: true,
      autoplay: true,
      path: './assets/lottie/live-chatbot.json'
    });
  }

  if (cleanerContainer) {
    window.lottie.loadAnimation({
      container: cleanerContainer,
      renderer: 'svg',
      loop: true,
      autoplay: true,
      path: './assets/lottie/ai-phone-cleaner.json'
    });
  }
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

  if (speechRecognizer) {
    speechRecognizer.lang = lang === 'id' ? 'id-ID' : 'en-US';
  }

  if (neoAiModeLabel) {
    const modeConfig = neoAiVideoModes[currentNeoAiMode] || neoAiVideoModes.idle1;
    neoAiModeLabel.textContent = getText(modeConfig.labelKey || 'neoAiModeStandby');
  }

  renderStats();
  renderLogs();
  renderReports();
  renderChatMessages();
  renderOptimizationLibrary();
  renderVoiceCommands();
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

function renderOptimizationLibrary() {
  const bloatwareList = document.getElementById('bloatwareList');
  const cleanerList = document.getElementById('cleanerList');
  const bloatwareCount = document.getElementById('bloatwareCount');
  const cleanerCount = document.getElementById('cleanerCount');

  if (!bloatwareList || !cleanerList) {
    return;
  }

  if (bloatwareCount) {
    bloatwareCount.textContent = String(bloatwareCatalog.length);
  }
  if (cleanerCount) {
    cleanerCount.textContent = String(cleanerCatalog.length);
  }

  const buildItem = (item) => `
    <div class="library-item">
      <div class="library-item-main">
        <div class="library-item-title">${escapeHtml(state.lang === 'id' ? item.labelId : item.labelEn)}</div>
        <div class="library-item-desc">${escapeHtml(state.lang === 'id' ? item.descId : item.descEn)}</div>
        ${item.packageId ? `<div class="library-item-meta">${escapeHtml(item.packageId)}</div>` : ''}
      </div>
      <div class="library-tags">
        ${(item.tags || []).map((tag) => `<span class="library-tag">${escapeHtml(tag)}</span>`).join('')}
      </div>
    </div>
  `;

  bloatwareList.innerHTML = bloatwareCatalog.map(buildItem).join('');
  cleanerList.innerHTML = cleanerCatalog.map(buildItem).join('');
}

function renderVoiceCommands() {
  const container = document.getElementById('voiceCommandList');
  if (!container) {
    return;
  }

  const items = voiceCommandRules.map((rule) => {
    const title = rule.labelKey ? getText(rule.labelKey) : (rule.action || rule.command || 'Command');
    const phrases = (rule.phrases || []).slice(0, 5);
    let actionLabel = '';
    if (rule.type === 'system') {
      actionLabel = getText('voiceActionUpdate');
    } else if (rule.type === 'sequence') {
      actionLabel = getText('voiceActionSequence');
    } else if (rule.type === 'ui') {
      actionLabel = getText('voiceActionUi');
    } else if (rule.type === 'ai') {
      actionLabel = getText('voiceActionAi');
    } else {
      actionLabel = actionLabels[rule.action] || (rule.labelKey ? getText(rule.labelKey) : rule.action);
    }

    return `
      <div class="voice-command-item">
        <div class="voice-command-main">
          <div class="voice-command-title">${escapeHtml(title)}</div>
          <div class="voice-command-phrases">
            ${phrases.map((phrase) => `<span class="voice-command-chip">${escapeHtml(phrase)}</span>`).join('')}
          </div>
        </div>
        <div class="voice-command-action">${escapeHtml(actionLabel || '')}</div>
      </div>
    `;
  });

  container.innerHTML = items.join('');
}

let neoAiVideoElement = null;
let neoAiModeLabel = null;
let neoAiModeTimeout = null;
let currentNeoAiMode = 'idle1';

function initNeoAiVideo() {
  neoAiVideoElement = document.getElementById('neoAiVideo');
  neoAiModeLabel = document.getElementById('neoAiModeLabel');

  if (!neoAiVideoElement) {
    return;
  }

  neoAiVideoElement.addEventListener('ended', () => {
    if (currentNeoAiMode === 'greeting') {
      setNeoAiMode('idle');
    }
  });

  setNeoAiMode('greeting');
}

function setNeoAiMode(mode, options = {}) {
  if (!neoAiVideoElement) {
    return;
  }

  const resolvedMode = mode === 'idle'
    ? (Math.random() > 0.5 ? 'idle1' : 'idle2')
    : mode;
  const config = neoAiVideoModes[resolvedMode] || neoAiVideoModes.idle1;

  if (neoAiModeTimeout) {
    window.clearTimeout(neoAiModeTimeout);
    neoAiModeTimeout = null;
  }

  currentNeoAiMode = resolvedMode;
  neoAiVideoElement.loop = config.loop;
  if (neoAiVideoElement.getAttribute('src') !== config.src) {
    neoAiVideoElement.setAttribute('src', config.src);
  }
  neoAiVideoElement.play().catch(() => {
    // Autoplay might be blocked; ignore.
  });

  if (neoAiModeLabel) {
    const labelKey = config.labelKey || 'neoAiModeStandby';
    neoAiModeLabel.textContent = getText(labelKey);
  }

  if (options.temporary) {
    neoAiModeTimeout = window.setTimeout(() => {
      setNeoAiMode('idle');
    }, options.durationMs ?? 8000);
  }
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
    dispatchActions: document.getElementById('autoExecute').checked && state.consents.autoExecution === true
  });
  input.value = '';
}

function runAction(action, modeOverride) {
  const requiresDiagnostics = action === 'healthCheck' || action === 'integrityScan';
  if (!state.consents.accepted) {
    showToast(getText('consentRequired'), 'error');
    return;
  }
  if (requiresDiagnostics && !state.consents.diagnostics) {
    showToast(getText('diagnosticsConsentRequired'), 'error');
    return;
  }
  if (!requiresDiagnostics && !state.consents.maintenance) {
    showToast(getText('maintenanceConsentRequired'), 'error');
    return;
  }

  const mode = modeOverride || actionModeMap[action];
  if (mode) {
    setNeoAiMode(mode, { temporary: true, durationMs: 12000 });
  }

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

function openConsentModal() {
  syncConsentForm();
  document.getElementById('consentModal').style.display = 'flex';
}

function closeConsentModal() {
  document.getElementById('consentModal').style.display = 'none';
}

function syncConsentForm() {
  document.getElementById('consentAccepted').checked = !!state.consents.accepted;
  document.getElementById('consentTelemetry').checked = !!state.consents.telemetry;
  document.getElementById('consentDiagnostics').checked = !!state.consents.diagnostics;
  document.getElementById('consentMaintenance').checked = !!state.consents.maintenance;
  document.getElementById('consentRemote').checked = !!state.consents.remoteControl;
  document.getElementById('consentAutoExecution').checked = !!state.consents.autoExecution;
  document.getElementById('consentLocation').checked = !!state.consents.location;
  document.getElementById('consentCamera').checked = !!state.consents.camera;
}

function saveConsent() {
  const accepted = document.getElementById('consentAccepted').checked;
  if (!accepted) {
    showToast('Consent wajib diaktifkan untuk menggunakan NeoOptimize.', 'error');
    return;
  }

  state.consents = {
    accepted,
    telemetry: document.getElementById('consentTelemetry').checked,
    diagnostics: document.getElementById('consentDiagnostics').checked,
    maintenance: document.getElementById('consentMaintenance').checked,
    remoteControl: document.getElementById('consentRemote').checked,
    autoExecution: document.getElementById('consentAutoExecution').checked,
    location: document.getElementById('consentLocation').checked,
    camera: document.getElementById('consentCamera').checked
  };

  post({
    type: 'updateConsent',
    payload: state.consents
  });
  applyConsentState();
  closeConsentModal();
}

function applyConsentState() {
  const autoExecToggle = document.getElementById('autoExecute');
  const autoExecContainer = document.querySelector('.auto-exec-toggle');
  const actions = document.querySelectorAll('.action-card');
  const autoExecutionAllowed = state.consents.accepted && state.consents.autoExecution;
  const maintenanceAllowed = state.consents.accepted && state.consents.maintenance;

  if (autoExecToggle) {
    autoExecToggle.checked = autoExecutionAllowed && autoExecToggle.checked;
    autoExecToggle.disabled = !autoExecutionAllowed;
  }
  if (autoExecContainer) {
    autoExecContainer.classList.toggle('disabled', !autoExecutionAllowed);
  }
  actions.forEach((card) => {
    card.classList.toggle('disabled', !maintenanceAllowed);
  });

  if (!state.consents.accepted) {
    openConsentModal();
  }
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
  if (payload.consent) {
    state.consents = {
      ...state.consents,
      ...payload.consent
    };
  }
  state.update.currentVersion = state.appVersion;
  state.reports = Array.isArray(payload.reports) ? payload.reports : state.reports;
  updateClientBadge();
  updateProfilePanel();
  renderReports();
  applyConsentState();

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
      setNeoAiMode('idle');
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
    case 'consent':
      state.consents = {
        ...state.consents,
        ...(data.payload || {})
      };
      applyConsentState();
      break;
    default:
      break;
  }

  renderStats();
  renderLogs();
  renderReports();
  renderOptimizationLibrary();
  renderVoiceCommands();
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
  animateTray();
  initMiniTrayAnimations();
  initVoiceControls();
  initNeoAiVideo();
  bindThemeControls();
  bindLanguageControls();

  document.getElementById('profileBtn').addEventListener('click', () => {
    updateProfilePanel();
    document.getElementById('loginModal').style.display = 'flex';
  });
  document.getElementById('consentBtn').addEventListener('click', openConsentModal);
  document.getElementById('saveConsentBtn').addEventListener('click', saveConsent);

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

  document.getElementById('consentModal').addEventListener('click', (event) => {
    if (event.target.id === 'consentModal') {
      closeConsentModal();
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
  renderOptimizationLibrary();
  renderVoiceCommands();
  animateLibrary();
  applyConsentState();

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
window.closeConsentModal = closeConsentModal;

window.addEventListener('DOMContentLoaded', init);
