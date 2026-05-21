Option Explicit

Dim shell, fso, root, ps, ui, setup, console, args
Set shell = CreateObject("Shell.Application")
Set fso   = CreateObject("Scripting.FileSystemObject")
Set shell  = CreateObject("Shell.Application")

root    = fso.GetParentFolderName(WScript.ScriptFullName)
ps      = CreateObject("WScript.Shell").ExpandEnvironmentStrings("%WINDIR%") & "\System32\WindowsPowerShell\v1.0\powershell.exe"
ui      = root & "\NeoOptimize.UI.ps1"
setup   = root & "\NeoOptimize.Setup.ps1"
console = root & "\NeoOptimize.ps1"

If fso.FileExists(ui) Then
  args = "-Sta -NoProfile -ExecutionPolicy RemoteSigned -File """ & ui & """"
  shell.ShellExecute ps, args, root, "runas", 0
ElseIf fso.FileExists(console) Then
  args = "-NoProfile -ExecutionPolicy RemoteSigned -File """ & console & """"
  shell.ShellExecute ps, args, root, "runas", 1
End If
