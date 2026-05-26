# NeoOptimize Algorithm Roadmap v1.0

NeoOptimize tidak boleh berhenti sebagai kumpulan tweak. Arah pengembangannya adalah sistem keputusan: mengamati kondisi mesin, memberi skor, memilih tindakan paling aman, mencatat bukti, dan menyediakan rollback.

## 1. Agent-First Architecture

NeoOptimize Agent menjadi otak yang berjalan berulang:

- Collect: ambil snapshot OS, service, registry, disk, RAM, Defender, firewall, update, startup, power, network.
- Detect: jalankan rule engine dengan evidence yang bisa diaudit.
- Score: hitung NeoScore 0-100 dari bobot severity dan confidence.
- Decide: pilih rekomendasi berdasarkan risiko, dampak, dan profil pengguna.
- Remediate: hanya apply rule yang masuk whitelist policy.
- Report: tulis JSON untuk mesin dan HTML untuk teknisi.

## 2. Risk-Aware Rule Engine

Setiap rule wajib punya:

- ID stabil, contoh `NEO-FW-001`.
- Category, severity, impact, confidence.
- Evidence mentah yang membuktikan finding.
- Recommendation yang bisa dipahami teknisi.
- Remediation handler opsional.
- Rollback handler untuk fase berikutnya.

Algoritma scoring saat ini sederhana:

```text
NeoScore = clamp(100 - sum(severityImpact), 0, 100)
```

Fase berikutnya:

```text
Priority = SeverityWeight * Confidence * BlastRadius * BusinessContext
NeoScore = 100 - min(80, WeightedRiskDebt)
```

## 3. Machine Baseline

Agent harus bisa membuat baseline per mesin:

- Baseline service startup type.
- Baseline power plan.
- Baseline firewall profile.
- Baseline installed driver/app versions.
- Baseline startup entries.
- Baseline boot time dan resource idle.

Dengan baseline, NeoOptimize bisa membedakan "konfigurasi memang sengaja" vs "regresi/kerusakan".

## 4. Profile System

Profil jangan hanya Gaming/Home/Minimal. Profil harus memengaruhi policy:

- Home: stabilitas dan update aman.
- Technician: visibility, report, diagnostic retention.
- Gaming: latency, power, background noise, tetapi tidak merusak update/security.
- Workstation: developer service tetap hidup, Hyper-V/WSL/Docker aman.
- Kiosk: minimal apps, locked-down UI, scheduled maintenance.
- Incident Response: jangan hapus log, jangan bersihkan forensic evidence.

## 5. Transactional Remediation

Sebelum perubahan:

- Buat restore point jika tersedia.
- Export registry key yang disentuh.
- Simpan service startup type.
- Backup file seperti hosts.
- Tulis action journal JSON.

Setelah perubahan:

- Verifikasi post-condition.
- Tandai success/failed.
- Tawarkan rollback dari action journal.

## 6. Lab Automation With win-target

Target lab `win-target` dipakai sebagai jalur validasi:

- Copy repo ke VM.
- Jalankan self-test PowerShell parser.
- Jalankan agent audit.
- Ambil JSON/HTML report.
- Jalankan remediation aman di snapshot VM.
- Bandingkan pre/post NeoScore.

Jika QEMU guest agent belum tersedia, gunakan salah satu opsi:

- Aktifkan OpenSSH Server di Windows VM dan pakai PowerShell remoting via SSH.
- Tambahkan QEMU guest agent channel lalu install guest agent di Windows.
- Jalankan test script langsung dari console VM untuk sementara.

## 7. Future Brilliant Ideas

- NeoScore trend: simpan skor harian, deteksi degradasi.
- Driver risk index: tandai driver tua, unsigned, crash-prone, atau vendor rentan.
- Boot health model: korelasi startup entries, service delay, event log boot warnings.
- Update safety window: rekomendasi kapan update aman berdasarkan uptime, pending reboot, battery/AC, dan free disk.
- Network posture map: DNS, firewall, SMB, RDP, LLMNR, NetBIOS, active listeners.
- Privacy posture map: telemetry, suggestions, advertising ID, app permissions.
- Explainable remediation: setiap aksi punya "why", "what changed", "how to rollback".
- Plugin rules: rule eksternal di folder `rules/` agar teknisi bisa menambah policy tanpa edit core.
- Signed release pipeline: checksum, self-test, changelog, dan paket zip yang reproducible.
