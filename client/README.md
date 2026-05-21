
<div align="center">

```
███╗   ██╗███████╗ ██████╗  ██████╗ ██████╗ ████████╗██╗███╗   ███╗██╗███████╗███████╗
████╗  ██║██╔════╝██╔═══██╗██╔═══██╗██╔══██╗╚══██╔══╝██║████╗ ████║██║╚══███╔╝██╔════╝
██╔██╗ ██║█████╗  ██║   ██║██║   ██║██████╔╝   ██║   ██║██╔████╔██║██║  ███╔╝ █████╗  
██║╚██╗██║██╔══╝  ██║   ██║██║   ██║██╔═══╝    ██║   ██║██║╚██╔╝██║██║ ███╔╝  ██╔══╝  
██║ ╚████║███████╗╚██████╔╝╚██████╔╝██║        ██║   ██║██║ ╚═╝ ██║██║███████╗███████╗
╚═╝  ╚═══╝╚══════╝ ╚═════╝  ╚═════╝ ╚═╝        ╚═╝   ╚═╝╚═╝     ╚═╝╚═╝╚══════╝╚══════╝
```

**⚡ Windows Optimizer & Agent v1.0**

*Professional Tool for Computer Technicians — One-Stop Solution*

[![Email](https://img.shields.io/badge/Email-neooptimizeofficial%40gmail.com-blue?style=flat-square&logo=gmail)](mailto:neooptimizeofficial@gmail.com)
[![BuyMeACoffee](https://img.shields.io/badge/☕-BuyMeACoffee-yellow?style=flat-square)](https://buymeacoffee.com/nol.eight)
[![Saweria](https://img.shields.io/badge/🙏-Saweria-orange?style=flat-square)](https://saweria.co/dtechtive)
[![Dana](https://img.shields.io/badge/💰-Dana-blue?style=flat-square)](https://ik.imagekit.io/dtechtive/Dana)

</div>

---

## 📋 Deskripsi

**NeoOptimize Versi 1.0** adalah control center optimasi Windows untuk teknisi:
cleanup, performance tuning, privacy/security hardening, update/driver audit,
power tuning, maintenance disk, NeoCore AI advisor lokal, dan NeoMonitor/RMM agent.

---

## 📁 Struktur Folder

```
NeoOptimize/
│
├── 📄 LAUNCH.bat                    ← 🚀 JALANKAN INI (auto-elevate)
├── 📄 Install.bat                   ← Installer Windows GUI (buat shortcut & Start Menu)
├── 📄 Uninstall.bat                 ← Uninstaller Windows
├── 📄 QuickStart.bat                ← Quick launcher (elevasi otomatis)
├── 📄 NeoOptimize.ps1               ← Main launcher & menu utama
├── 📄 NeoOptimizeAgent.ps1          ← Agent audit, scoring, report, remediation aman
├── 📄 NeoOptimize.AIAgent.ps1       ← NeoCore AI advisor lokal
├── 📄 NeoOptimize.UI.ps1            ← UI control center EN/IN, light/dark/system
├── 📄 CREATE_RESTORE_POINT.ps1      ← Buat restore point sebelum optimasi
├── 📂 config/
│   ├── NeoOptimize.AgentPolicy.json ← Policy threshold/scoring agent
│   ├── NeoOptimize.ModelAgent.json  ← Urutan provider NeoCore/Ollama/NullClaw/rules
│   └── NeoOptimize.UI.json          ← Preferensi bahasa dan tema
├── 📂 models/
│   └── NeoCore.Policy.json          ← Model policy lokal NeoOptimize
├── 📂 datasets/
│   └── neocore_training_seed.jsonl  ← Data seed training NeoCore
├── 📂 docs/
│   └── ROADMAP_ALGORITMA.md         ← Ide algoritma pengembangan NeoOptimize
├── 📂 tools/
│   ├── Invoke-NeoOptimizeSelfTest.ps1 ← Self-test statis sebelum rilis
│   └── Invoke-WinTargetLabTest.sh     ← Harness host untuk test VM win-target
│
├── 📂 lib/
│   └── Common.ps1                   ← Library bersama (UI, log, helper)
│
├── 📂 modules/
│   ├── 01_Cleaner.ps1               ← 🧹 System Cleaner
│   ├── 02_Performance.ps1           ← ⚡ Performance Optimizer
│   ├── 03_Privacy.ps1               ← 🔒 Privacy & Telemetry Killer
│   ├── 04_Network.ps1               ← 🌐 Network Optimizer
│   ├── 05_Security.ps1              ← 🛡️  Security Hardening
│   ├── 06_Services.ps1              ← ⚙️  Services Manager
│   ├── 07_Updates.ps1               ← 🔄 Update & Driver Manager
│   ├── 08_Power.ps1                 ← 🔋 Power Plan & Gaming Mode
│   └── 09_Maintenance.ps1           ← 🧰 Smart cleanup, disk scan/repair, defrag/TRIM
│
├── 📂 reports/                      ← Log & laporan HTML (auto-generated)
└── 📂 backup/                       ← Backup registry (untuk restore)
```

---

## 🚀 Cara Menggunakan

### Langkah 1 — Buat Restore Point (Sangat Disarankan)
```
Double-click: CREATE_RESTORE_POINT.ps1
→ Approve UAC
```

### Langkah 2 — Jalankan NeoOptimize
```
Double-click: LAUNCH.bat
→ Klik "Yes" pada UAC prompt
→ Menu utama akan tampil
```

### Langkah 3 — Pilih Modul
```
[0] Dashboard    → Lihat status sistem real-time
[1-8]            → Pilih modul individual
[9] Agent        → Audit, scoring, report, scheduled task
[M] Maintenance  → Clean all junk, schedule cleanup, smart optimize, disk manager
[A] Safe Care    → Audit, deep scan, cleanup ringan, dan report
[I]  About       → Info & link donasi
```

> **Alternatif:** Klik kanan `NeoOptimize.ps1` → `Run with PowerShell` (as Admin)

### Mode CLI untuk teknisi
```
powershell -NoProfile -ExecutionPolicy RemoteSigned -File .\NeoOptimize.ps1 -FullAuto
powershell -NoProfile -ExecutionPolicy RemoteSigned -File .\NeoOptimizeAgent.ps1 -Mode Audit
powershell -NoProfile -ExecutionPolicy RemoteSigned -File .\NeoOptimizeAgent.ps1 -Mode Install
powershell -NoProfile -ExecutionPolicy RemoteSigned -File .\tools\Invoke-NeoOptimizeSelfTest.ps1
```

`-FullAuto` sekarang berarti Safe Care Plan: audit, deep scan, cleanup ringan, dan laporan. Modul high-risk seperti Performance, Privacy, Network, Security, Services, Power, dan System Repair tetap terkunci sampai operator menjalankan aksi spesifik dengan persetujuan eksplisit atau parameter `-Enforce`.

### NeoOptimize Agent
| Mode | Fungsi |
|------|--------|
| Audit | Mengambil snapshot, menjalankan rule engine, menghitung score 0-100, export JSON/HTML |
| Remediate | Menjalankan remediation aman untuk rule yang masuk whitelist policy |
| Install | Membuat scheduled task harian `NeoOptimize-Agent-Audit` sebagai SYSTEM |
| Status | Menampilkan status task dan report terakhir |
| Uninstall | Menghapus scheduled task agent |

Agent memakai policy di `config\NeoOptimize.AgentPolicy.json`: threshold disk/RAM/temp/startup, bobot severity, daftar rule yang boleh diremediasi otomatis, dan retensi report.

### NeoCore AI

NeoOptimize sekarang punya model lokal sendiri: **NeoCore.Policy 1.0**.
Model ini membaca snapshot endpoint, menghitung health score, memberi confidence
per modul, dan bisa dilatih ulang secara offline dari data audit/report lokal.
Provider dicoba berurutan:

1. NeoCore local policy model
2. Ollama local models, opsional
3. NullClaw CLI, opsional
4. NeoOptimize safety rule engine

Config: `config\NeoOptimize.ModelAgent.json`

Jalankan dari Modern UI lewat `NeoCore AI`, atau dari console:

```powershell
powershell -NoProfile -ExecutionPolicy RemoteSigned -File .\NeoOptimize.AIAgent.ps1
powershell -NoProfile -ExecutionPolicy RemoteSigned -File .\NeoOptimize.AIAgent.ps1 -Mode Providers
powershell -NoProfile -ExecutionPolicy RemoteSigned -File .\NeoOptimize.AIAgent.ps1 -Mode TrainNeoCore
```

Layer ini tidak mengeksekusi shell command, tidak mengambil secret/token,
tidak merekam camera/microphone, dan tidak mengambil data biometric.

### Test Lab win-target
Di host Linux/libvirt:
```
tools/Invoke-WinTargetLabTest.sh
SSH_TARGET='Administrator@10.10.10.120' tools/Invoke-WinTargetLabTest.sh
```

Tanpa `SSH_TARGET`, script hanya mengecek status VM, QEMU guest agent, dan DHCP lease. Dengan `SSH_TARGET`, script copy repo ke VM, menjalankan self-test, lalu menjalankan Agent Audit.

---

## 🔥 Fitur Detail

### 🧹 Module 01 — System Cleaner
| Fitur | Keterangan |
|-------|------------|
| Windows Temp | `%TEMP%`, `%TMP%`, `C:\Windows\Temp`, Prefetch |
| Browser Cache | Chrome, Edge, Firefox cache-only, Brave, Opera |
| WU Cache | SoftwareDistribution\Download |
| Event Logs | Opsional, dengan konfirmasi |
| WER | Windows Error Reports & crash dumps |
| System Caches | DNS, ARP, Font, Icon, Thumbnail |
| Recycle Bin | Auto empty semua drive |
| CleanMgr | 22+ kategori disk cleanup otomatis |
| **Report** | Total MB yang dibebaskan |

### ⚡ Module 02 — Performance Optimizer
| Fitur | Keterangan |
|-------|------------|
| Visual Effects | Best Performance mode |
| RAM Flush | EmptyWorkingSet via Win32 API |
| PageFile | Default system-managed; custom dengan konfirmasi |
| NTFS Tweaks | 8.3 off, last-access off, MFT zone 2 |
| Processor Sched | Foreground priority (Win32=38) |
| SysMain | Disable (optimal SSD) |
| Memory Compression | Toggle untuk kurangi CPU overhead |
| Boot Config | Quiet boot, no debug, standard menu |
| Startup Audit | Listing semua startup entry |

### 🔒 Module 03 — Privacy & Telemetry Killer
| Fitur | Keterangan |
|-------|------------|
| Telemetry | Level 0 (Security only) |
| DiagTrack | Stop & disable |
| Cortana | Full disable + remove UWP |
| Advertising ID | Off |
| Activity History | Off |
| App Permissions | 14 permission dikunci |
| Location | Off |
| Hosts Block | 20 telemetry endpoints, dengan backup hosts |
| Content Manager | 12 suggestion keys off |
| Bloatware | 30+ UWP apps, opsional dengan konfirmasi |
| OneDrive | Auto-start disabled |

### 🌐 Module 04 — Network Optimizer
| Fitur | Keterangan |
|-------|------------|
| TCP/IP Stack | TTL, SACK, RFC1323, KeepAlive |
| TCP Global | RSS, FastOpen, AutoTuning, DCA |
| Nagle's Algorithm | Disable (latency ↓) |
| DNS | Pilih: Cloudflare / Google / Quad9 / CF Family |
| DNS-over-HTTPS | Enable DoH |
| QoS | Remove 20% bandwidth reserve |
| NetworkThrottle | Off |
| IPv6 Tunnel | Teredo, 6to4, ISATAP off; native IPv6 tetap aktif |
| NetBIOS | Disable over TCP/IP |
| Winsock | Reset catalog |
| NIC | RSS enable, power saving off |
| Hosts File | 20 ad/tracker domains blocked, idempotent dan dibackup |

### 🛡️ Module 05 — Security Hardening
| Fitur | Keterangan |
|-------|------------|
| Defender | Cloud=High, PUA=on, CFolderAccess=on |
| UAC | Maximum + Secure Desktop |
| SMBv1 | DISABLED (EternalBlue protection) |
| SMB Signing | ENABLED (MITM prevention) |
| Firewall | All profiles ON + block inbound |
| Port Blocking | 14 dangerous ports |
| RDP | Disable atau enforce NLA |
| AutoRun | DISABLED (USB attack prevention) |
| LLMNR/WPAD | DISABLED |
| Windows Script Host | DISABLED |
| TLS/SSL | SSL2/3, TLS1.0/1.1 off; TLS1.2/1.3 on |
| NTLMv2 | Only, LM hash disabled |
| SEHOP/DEP | Enabled |

### ⚙️ Module 06 — Services Manager
**5 Profil tersedia:**

| Profil | Untuk Siapa |
|--------|-------------|
| 🏠 Home | Penggunaan sehari-hari |
| 🎮 Gaming | FPS maksimal, latency minimum |
| 💼 Workstation | Developer & IT professional |
| 🔒 Minimal | Keamanan maksimal |
| 🔄 Restore | Kembalikan dari backup service startup terakhir |

### 🔄 Module 07 — Update & Driver Manager
| Opsi | Keterangan |
|------|------------|
| Cek Update | Via PSWindowsUpdate module |
| Manual Mode | No auto-download & no auto-restart |
| Pause 35 Hari | Pause feature + quality updates |
| Block Feature | Kunci versi sekarang, security tetap mengalir |
| Driver Audit | List semua driver + versi + tanggal |
| Clean Old Drivers | Hapus orphaned OEM packages dengan konfirmasi |
| Winget | List & upgrade semua software |
| Export HTML | Laporan driver lengkap |
| Restore Default | Kembalikan ke pengaturan asal |

### 🔋 Module 08 — Power Plan & Gaming Mode
| Fitur | Keterangan |
|-------|------------|
| Ultimate Performance | Hidden Windows plan |
| NeoOptimize God Mode | Custom: CPU 100%, sleep off, ASPM off |
| MMCSS | GPU Priority=8, Scheduling=High |
| Hardware GPU Sched | Enable WDDM 2.7+ |
| bcdedit | Hanya diterapkan saat memilih profil performance/gaming |
| Mouse | Raw input, precision off |
| Xbox DVR | DISABLED |
| Fast Startup | Hybrid boot enable |
| Power Audit | Generate HTML report |

---

## 💻 Persyaratan Sistem

| Komponen | Minimum |
|----------|---------|
| **OS** | Windows 10 21H2 / Windows 11 |
| **PowerShell** | 5.1+ (bawaan Win10/11) |
| **Hak Akses** | Administrator |
| **RAM** | 4GB+ |
| **Koneksi** | Opsional (untuk winget/PSWindowsUpdate) |

## ✅ Kompatibilitas

| OS | Status |
|----|--------|
| Windows 11 (22H2, 23H2, 24H2) | ✅ Full |
| Windows 10 (21H2, 22H2) | ✅ Full |
| Windows 10 (20H1, 20H2) | ⚠️ Mostly |
| Windows Server 2019/2022 | ⚠️ Review dulu |
| Windows 7/8/8.1 | ❌ Tidak didukung |

---

## 📝 Log & Laporan

- **Log text** → `reports\NeoOptimize_YYYYMMDD_HHMMSS.log`
- **Laporan HTML driver** → `reports\DriverReport_*.html`
- **Power audit** → `reports\PowerAudit_*.html`
- **God Mode report** → `reports\GodMode_*.html`
- **Backup registry** → `backup\registry\*.reg`
- **Backup service startup** → `backup\ServiceStartup_*.csv`
- **Backup hosts/file penting** → `backup\files\*.bak`

---

## ⚠️ Disclaimer

> Tool ini dibuat untuk **teknisi komputer berpengalaman**.
> Selalu buat **System Restore Point** sebelum menjalankan optimasi.
> Penggunaan atas risiko pengguna sendiri.

---

## 💖 Donasi & Support

Tool ini gratis dan open-source. Jika bermanfaat, mohon dukung pengembangannya:

| Platform | Link |
|----------|------|
| ☕ BuyMeACoffee | https://buymeacoffee.com/nol.eight |
| 🙏 Saweria | https://saweria.co/dtechtive |
| 💰 Dana (QR) | https://ik.imagekit.io/dtechtive/Dana |
| 📧 Email | neooptimizeofficial@gmail.com |

---

<div align="center">

**NeoOptimize v1.0** — *Dibuat gratis dengan ❤ untuk komunitas teknisi Indonesia*

</div>
