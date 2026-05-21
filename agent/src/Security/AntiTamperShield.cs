using System;
using System.Diagnostics;
using System.IO;
using System.Security.AccessControl;
using System.Security.Principal;
using System.ServiceProcess;
using Microsoft.Win32;

namespace NeoOptimize.Agent.Security;

public class AntiTamperShield
{
    private const string ServiceName = "NeoOptimize RMM Agent";

    public void LockdownServiceAndRegistry()
    {
        try
        {
            // 1. Lock the Registry Key to prevent manipulation of Service settings
            string regPath = $@"SYSTEM\CurrentControlSet\Services\{ServiceName}";
            using var key = Registry.LocalMachine.OpenSubKey(regPath, RegistryKeyPermissionCheck.ReadWriteSubTree, RegistryRights.ChangePermissions);
            if (key != null)
            {
                var security = key.GetAccessControl();

                // Remove generic write access from Administrators
                var adminSid = new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null);
                security.AddAccessRule(new RegistryAccessRule(adminSid,
                    RegistryRights.WriteKey | RegistryRights.Delete,
                    InheritanceFlags.ContainerInherit, PropagationFlags.None, AccessControlType.Deny));

                // Ensure SYSTEM still has full control to run the service
                var systemSid = new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null);
                security.AddAccessRule(new RegistryAccessRule(systemSid, RegistryRights.FullControl, AccessControlType.Allow));

                key.SetAccessControl(security);
            }

            // 2. Lock the physical agent directory to prevent deletion
            string? exePath = Process.GetCurrentProcess().MainModule?.FileName;
            if (!string.IsNullOrEmpty(exePath))
            {
                string? dirPath = Path.GetDirectoryName(exePath);
                if (string.IsNullOrEmpty(dirPath)) return;

                var dirInfo = new DirectoryInfo(dirPath);
                var dirSecurity = dirInfo.GetAccessControl();

                // Prevent users and administrators from deleting the files or folder
                dirSecurity.AddAccessRule(new FileSystemAccessRule(
                    new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null),
                    FileSystemRights.Delete | FileSystemRights.DeleteSubdirectoriesAndFiles,
                    InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit,
                    PropagationFlags.None,
                    AccessControlType.Deny));

                dirInfo.SetAccessControl(dirSecurity);
            }
        }
        catch (Exception ex)
        {
            // Log silently or ignore if it fails due to permissions
            Debug.WriteLine("Anti-Tamper Lockdown Failed: " + ex.Message);
        }
    }
}
