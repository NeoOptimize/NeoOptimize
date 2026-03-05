using System;
using System.Collections.Generic;
using System.IO;
using System.Threading.Tasks;

namespace NeoOptimize.UI.Services
{
    public class BackupInfo
    {
        public string Name { get; set; }
        public string Path { get; set; }
        public DateTime Created { get; set; }
    }

    public class BackupService
    {
        private string GetBackupsRoot()
        {
            var appdata = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
            return System.IO.Path.Combine(appdata, "NeoOptimize", "Backups");
        }

        public Task<List<BackupInfo>> ListBackupsAsync()
        {
            return Task.Run(() => {
                var list = new List<BackupInfo>();
                var root = GetBackupsRoot();
                if (!Directory.Exists(root)) return list;
                foreach (var d in Directory.GetDirectories(root))
                {
                    try
                    {
                        var di = new DirectoryInfo(d);
                        list.Add(new BackupInfo { Name = di.Name, Path = di.FullName, Created = di.CreationTime });
                    }
                    catch { }
                }
                list.Sort((a,b)=>b.Created.CompareTo(a.Created));
                return list;
            });
        }

        public Task<bool> DeleteBackupAsync(string backupPath)
        {
            return Task.Run(() => {
                try
                {
                    if (Directory.Exists(backupPath)) Directory.Delete(backupPath, true);
                    return true;
                }
                catch { return false; }
            });
        }
    }
}
