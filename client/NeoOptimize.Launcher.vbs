Option Explicit

Dim shell, wsh, fso, root, ps, ui, setup, console, args
Set shell = CreateObject("Shell.Application")
Set wsh   = CreateObject("WScript.Shell")
Set fso   = CreateObject("Scripting.FileSystemObject")

root    = fso.GetParentFolderName(WScript.ScriptFullName)
ps      = wsh.ExpandEnvironmentStrings("%WINDIR%") & "\System32\WindowsPowerShell\v1.0\powershell.exe"
ui      = root & "\NeoOptimize.UI.ps1"
setup   = root & "\NeoOptimize.Setup.ps1"
console = root & "\NeoOptimize.ps1"

If fso.FileExists(ui) Then
  args = "-Sta -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & ui & """"
  shell.ShellExecute ps, args, root, "runas", 1
ElseIf fso.FileExists(console) Then
  args = "-NoProfile -ExecutionPolicy Bypass -File """ & console & """"
  shell.ShellExecute ps, args, root, "runas", 1
End If
