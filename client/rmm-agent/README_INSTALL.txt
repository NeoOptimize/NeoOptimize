NeoOptimize RMM Agent - Windows VM install

1. Open PowerShell as Administrator.
2. Change to the mounted ISO drive, for example:
   D:
3. Run:
   Set-ExecutionPolicy -Scope Process Bypass -Force
   .\NeoOptimize.Agent.Install.ps1

The bundled appsettings.json points this lab agent to:
http://192.168.122.1:3000

The installer will fall back to the first reachable server URL in config.
If the server requires enrollment, set `EnrollmentToken` in appsettings.json or pass `-EnrollmentToken` to the installer.
Camera, microphone, and biometric collection stay disabled unless explicitly enabled in config.

After installation, the dashboard should show the VM under Agents.
