ZZZZZZZZZ EEEEEEEEE NN    NN TTTTTTTTT HH    HH RRRRRRR     AAA     LL        IIIII XX    XX
       ZZ EE        NNN   NN    TTT    HH    HH RR    RR   AA AA    LL         III   XX  XX
      ZZ  EE        NNNN  NN    TTT    HH    HH RR    RR  AA   AA   LL         III    XXXX
     ZZ   EEEEEEE   NN NN NN    TTT    HHHHHHHH RRRRRRR  AAAAAAAAA  LL         III     XX
    ZZ    EE        NN  NNNN    TTT    HH    HH RR   RR   AA   AA   LL         III    XXXX
   ZZ     EE        NN   NNN    TTT    HH    HH RR    RR  AA   AA   LL         III   XX  XX
ZZZZZZZZZ EEEEEEEEE NN    NN    TTT    HH    HH RR     RR AA   AA   LLLLLLLL IIIII XX    XX

zenthralix-lab
NeoOptimize System Optimization Console

Built at zenthralix-lab with Codex.

What changed in this release:

- The main UI now opens in a larger responsive window and pages scroll instead
  of clipping controls at the bottom or right edge.
- The Optimizer page exposes the full module catalog: cleanup, performance,
  privacy review, app debloat choices, storage, network diagnostics, repair,
  update repair, power tuning, device snapshot, benchmark report, remote access
  readiness, container and Hyper-V tuning, Zero-Trust security, Game Mode Ultra,
  AI/NPU cache limits, and NEO AI tools.
- NEO Mini chat has instant local fallback answers for status, modules, voice,
  and health questions while the full local AI provider starts.
- Voice command now returns a transcript to NEO Mini when Windows speech
  recognition is available. If speech runtime or microphone permission is not
  available, typed chat remains active.
- Background service checks are hidden so sc.exe/CMD windows do not keep
  appearing during telemetry polling.
- Installer and runtime maintenance workers use hidden process execution for
  PowerShell, taskkill, cmd/chkdsk helpers, update repair, and Ollama setup.
  No CMD window should pop up during normal GUI use.
- Local AI setup now downloads the official Ollama Windows installer when it
  is not bundled, installs it silently, starts the API hidden, and prepares
  neo-light:latest, neo:latest, plus the neo-latest compatibility alias.

Installed components:

- NeoOptimize optimizer GUI
- Full PowerShell module bundle
- NEO AI Doctor, Script Forge, AI provider status, model setup, and local
  guidance
- Ollama local setup helper with hidden installer/download/model bootstrap
- NEO Capability Catalog for safe diagnostics, cleanup, repair, security,
  storage, networking, updates, AI scripting, and operator workflows
- Safety manifest verification data
- SHA-256 update and repair workflow
- Lightweight CPU, RAM, disk, network, device, debug, and anomaly telemetry
- Local report and transcript files for user-approved maintenance actions

Privacy and permissions:

- Camera, microphone, and location are not locked through organization policy
  by NeoOptimize privacy review modules.
- Public builds do not collect secrets, documents, browser credentials, camera
  streams, microphone streams, biometric data, or private keys by default.
- Remote/RMM operations require explicit enrollment and signed commands.

Support:

Email: neooptimizeofficial@gmail.com
Buy Me a Coffee support: https://buymeacoffee.com/nol.eight
Saweria support: https://saweria.co/dtechtive
Dana support: https://ik.imagekit.io/dtechtive/Dana

Security note:

High-impact maintenance actions should be reviewed before execution. Update
packages are expected to be verified with SHA-256 before installation.
