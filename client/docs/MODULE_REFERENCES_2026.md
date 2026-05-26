# NeoOptimize Windows Module References 2026

Dokumen ini menjadi dasar referensi modul Windows maintenance dan optimasi yang ditambahkan untuk rilis NeoOptimize. Semua modul baru dibuat audit-first: mode non-interaktif hanya membaca state dan menulis report, sedangkan perubahan sistem memerlukan konfirmasi eksplisit atau jalur `-Enforce`.

## Module Coverage

| Area | NeoOptimize module | Behavior |
|---|---|---|
| System cleanup | `01_Cleaner.ps1`, `20_ComponentCleanup.ps1` | Cleanup ringan, DISM component store analysis, `StartComponentCleanup` setelah approval |
| Performance tuning | `02_Performance.ps1`, `25_BenchmarkReport.ps1`, `35_PowerPlanTuning.ps1` | Baseline before/after, power profile tuning, performance audit |
| Privacy review | `26_PrivacyReview.ps1`, `03_Privacy.ps1` | Audit privacy. Camera, Microphone, dan Location tetap user-controlled dan tidak dikunci via organization policy |
| Network diagnostics | `27_NetworkDiagnostics.ps1`, `23_NetworkRepairToolkit.ps1` | Connectivity, DNS, route, TCP setting, flush DNS/renew DHCP/reset stack only by approval |
| Containerization and Hyper-V | `28_ContainerHyperVTuning.ps1` | Audit WSL2/Hyper-V and optional `.wslconfig` memory policy |
| Zero-Trust Security | `29_ZeroTrustSecurity.ps1`, `36_SecurityAudit.ps1` | Defender, ASR, firewall, SMB, LSA, VBS/HVCI audit; hardening only by approval |
| Game Mode Ultra | `30_GameModeUltra.ps1` | Game Mode/GameDVR/HAGS audit and safe tuning; no automatic BCDEdit/HPET changes |
| AI and NPU cache limits | `31_AINPUCaching.ps1` | NPU/GPU inventory, model cache sizing, optional local NeoOptimize cache policy |
| NVMe DirectStorage | `32_StorageTiering.ps1` | BypassIO audit, SSD/volume report, optional ReTrim/TierOptimize |
| Windows repair | `34_UpdateRepair.ps1`, `10_SystemRepair.ps1`, `18_NeoWindowsDoctor.ps1` | DISM/SFC audit and repair; Windows Update component reset only by high-risk consent |
| Device snapshot | `24_DeviceSnapshot.ps1` | Hardware, OS, disk, network, TPM, Secure Boot, BitLocker report |
| Remote readiness | `33_RemoteAccessReadiness.ps1` | WinRM/OpenSSH/RDP/QEMU/RMM status only; does not open ports or enable remote services |

## Official References

| Topic | Official reference |
|---|---|
| DISM repair for Windows Update corruption | https://learn.microsoft.com/en-us/troubleshoot/windows-server/installing-updates-features-roles/fix-windows-update-errors |
| SFC syntax and admin requirement | https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/sfc |
| Remove Appx packages | https://learn.microsoft.com/en-us/powershell/module/appx/remove-appxpackage |
| DISM provisioned Appx removal | https://learn.microsoft.com/en-us/powershell/module/dism/remove-appxprovisionedpackage |
| Attack Surface Reduction rules | https://learn.microsoft.com/en-us/defender-endpoint/attack-surface-reduction-rules-configure |
| WSL `.wslconfig` advanced settings | https://learn.microsoft.com/en-us/windows/wsl/wsl-config |
| Hyper-V requirements and optional feature install | https://learn.microsoft.com/en-us/windows-server/virtualization/hyper-v/get-started/Install-Hyper-V |
| Windows optional feature management | https://learn.microsoft.com/en-us/windows/client-management/client-tools/add-remove-hide-features |
| Powercfg command-line options | https://learn.microsoft.com/en-us/windows-hardware/design/device-experiences/powercfg-command-line-options |
| Event log export/query/clear with wevtutil | https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/wevtutil |
| Network diagnostics with Test-NetConnection | https://learn.microsoft.com/en-us/powershell/module/nettcpip/test-netconnection |
| Optimize-Volume ReTrim/TierOptimize | https://learn.microsoft.com/en-us/powershell/module/storage/optimize-volume |
| Repair-Volume | https://learn.microsoft.com/en-us/powershell/module/storage/repair-volume |
| DirectStorage and BypassIO storage path | https://learn.microsoft.com/en-us/windows-hardware/drivers/storage/bypassio |
| Windows privacy documentation | https://learn.microsoft.com/en-us/windows/privacy/ |

## Release Safety Rules

- Do not set `LetAppsAccessCamera`, `LetAppsAccessMicrophone`, or `LetAppsAccessLocation` to organization-blocked values.
- Do not set `DisableLocation`, `DisableLocationScripting`, or `DisableSensors` through organization policy.
- Do not suppress UAC prompts or disable Secure Desktop.
- Do not enable RDP, WinRM, RemoteRegistry, wildcard TrustedHosts, or administrative shares from permission preflight modules.
- Do not run BCDEdit, HPET, dynamic tick, adapter disablement, or storage repair commands silently.
- Use reports under `reports\` as the evidence trail for before/after comparison and release QA.
