#include "../include/NeoOptimizeEngine.h"
#include <thread>
#include <atomic>
#include <chrono>
#include <string>
#include <mutex>
#include <cstring>
#include <sstream>
#include <filesystem>
#include <algorithm>
#include <set>
#include <ctime>
#include <cctype>
#include <ShlObj.h>
#include <vector>
#include <windows.h>
#include <winreg.h>

namespace fs = std::filesystem;

static std::atomic<bool> g_running(false);
static std::string g_version = "NeoOptimize.Engine v0.2";
static NO_ProgressCallback g_progressCb = nullptr;
static std::mutex g_cbMutex;

namespace {

struct PathStat {
    uint64_t bytes = 0;
    uint64_t files = 0;
};

std::string EscapeJson(const std::string& input) {
    std::ostringstream ss;
    for (char c : input) {
        switch (c) {
        case '\\':
            ss << "\\\\";
            break;
        case '"':
            ss << "\\\"";
            break;
        case '\n':
            ss << "\\n";
            break;
        case '\r':
            ss << "\\r";
            break;
        case '\t':
            ss << "\\t";
            break;
        default:
            ss << c;
            break;
        }
    }
    return ss.str();
}

void EmitJsonRaw(const std::string& json) {
    std::lock_guard<std::mutex> lk(g_cbMutex);
    if (g_progressCb) {
        g_progressCb(json.c_str());
    }
}

void EmitProgress(const std::string& module, int progress, const std::string& message, const std::string& extra = std::string()) {
    std::ostringstream ss;
    ss << "{\"module\":\"" << module << "\",\"progress\":" << progress
       << ",\"message\":\"" << EscapeJson(message) << "\"";
    if (!extra.empty()) {
        ss << "," << extra;
    }
    ss << "}";
    EmitJsonRaw(ss.str());
}

std::string GetEnvValue(const char* key) {
    char* value = nullptr;
    size_t len = 0;
    if (_dupenv_s(&value, &len, key) == 0 && value) {
        std::string result(value);
        free(value);
        return result;
    }
    return std::string();
}

std::string ToLower(std::string value) {
    std::transform(value.begin(), value.end(), value.begin(), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });
    return value;
}

bool HasToken(const std::string& json, const std::string& token) {
    return json.find(token) != std::string::npos || json.find("\"" + token + "\"") != std::string::npos;
}

bool IsDryRun(const std::string& requestJson) {
    return requestJson.find("\"dryRun\":false") == std::string::npos &&
           requestJson.find("\"dryRun\": false") == std::string::npos;
}

std::string ExtractJsonString(const std::string& json, const std::string& key) {
    const std::string keyPattern = "\"" + key + "\"";
    size_t keyPos = json.find(keyPattern);
    if (keyPos == std::string::npos) return std::string();
    size_t colonPos = json.find(':', keyPos + keyPattern.size());
    if (colonPos == std::string::npos) return std::string();
    size_t q1 = json.find('"', colonPos + 1);
    if (q1 == std::string::npos) return std::string();
    size_t q2 = q1 + 1;
    while (true) {
        q2 = json.find('"', q2);
        if (q2 == std::string::npos) return std::string();
        if (q2 > q1 + 1 && json[q2 - 1] == '\\') {
            ++q2;
            continue;
        }
        break;
    }

    std::string value = json.substr(q1 + 1, q2 - q1 - 1);
    std::string unescaped;
    unescaped.reserve(value.size());
    bool escape = false;
    for (char c : value) {
        if (escape) {
            switch (c) {
            case '"':
                unescaped.push_back('"');
                break;
            case '\\':
                unescaped.push_back('\\');
                break;
            case 'n':
                unescaped.push_back('\n');
                break;
            case 'r':
                unescaped.push_back('\r');
                break;
            case 't':
                unescaped.push_back('\t');
                break;
            default:
                unescaped.push_back(c);
                break;
            }
            escape = false;
        } else if (c == '\\') {
            escape = true;
        } else {
            unescaped.push_back(c);
        }
    }
    return unescaped;
}

std::vector<std::string> ParseCleanerCategories(const std::string& requestJson) {
    std::vector<std::string> categories;
    auto addIf = [&](const std::string& key, const std::string& mapped = std::string()) {
        if (HasToken(requestJson, key)) {
            categories.push_back(mapped.empty() ? key : mapped);
        }
    };

    addIf("temp");
    addIf("browser");
    addIf("recyclebin");
    addIf("logs");
    addIf("prefetch");
    addIf("thumbnail");
    addIf("windowsupdate");
    addIf("appcache");
    addIf("network");

    // legacy/individual browser categories
    addIf("chrome", "browser");
    addIf("edge", "browser");
    addIf("firefox", "browser");

    if (categories.empty()) {
        categories = {
            "temp",
            "browser",
            "recyclebin",
            "logs",
            "prefetch",
            "thumbnail",
            "windowsupdate",
            "appcache"
        };
    }

    std::set<std::string> unique(categories.begin(), categories.end());
    return std::vector<std::string>(unique.begin(), unique.end());
}

PathStat CollectPathStat(const fs::path& path) {
    PathStat stat;
    std::error_code ec;
    if (!fs::exists(path, ec)) return stat;

    if (fs::is_regular_file(path, ec)) {
        stat.files = 1;
        stat.bytes = fs::file_size(path, ec);
        if (ec) stat.bytes = 0;
        return stat;
    }

    for (auto it = fs::recursive_directory_iterator(path, fs::directory_options::skip_permission_denied, ec);
         it != fs::recursive_directory_iterator(); ++it) {
        if (ec) break;
        std::error_code localEc;
        if (it->is_regular_file(localEc)) {
            ++stat.files;
            stat.bytes += fs::file_size(it->path(), localEc);
        }
    }
    return stat;
}

bool EnsureDir(const fs::path& path) {
    std::error_code ec;
    if (fs::exists(path, ec)) return true;
    return fs::create_directories(path, ec);
}

std::string BuildTimestamp() {
    std::time_t now = std::time(nullptr);
    std::tm tmNow{};
#if defined(_WIN32)
    localtime_s(&tmNow, &now);
#else
    tmNow = *std::localtime(&now);
#endif
    char buffer[32];
    std::strftime(buffer, sizeof(buffer), "%Y%m%d_%H%M%S", &tmNow);
    return std::string(buffer);
}

fs::path BuildBackupRoot(const std::string& suffix) {
    std::string appData = GetEnvValue("APPDATA");
    fs::path root;
    if (!appData.empty()) {
        root = fs::path(appData) / "NeoOptimize" / "Backups" / (suffix + "_" + BuildTimestamp());
    } else {
        root = fs::path("C:\\NeoOptimizeBackups") / (suffix + "_" + BuildTimestamp());
    }
    EnsureDir(root);
    return root;
}

void BackupPathIfNeeded(const fs::path& source, const fs::path& backupRoot, const std::string& category, size_t index) {
    if (backupRoot.empty()) return;
    std::error_code ec;
    if (!fs::exists(source, ec)) return;

    fs::path catDir = backupRoot / category;
    EnsureDir(catDir);

    std::ostringstream name;
    name << index << "_" << source.filename().string();
    fs::path target = catDir / name.str();

    if (fs::is_directory(source, ec)) {
        EnsureDir(target);
        fs::copy(source, target, fs::copy_options::recursive | fs::copy_options::overwrite_existing, ec);
    } else {
        EnsureDir(target.parent_path());
        fs::copy_file(source, target, fs::copy_options::overwrite_existing, ec);
    }
}

std::vector<fs::path> CollectBrowserPaths(const std::string& requestJson) {
    std::vector<fs::path> paths;
    std::string localApp = GetEnvValue("LOCALAPPDATA");
    std::string appData = GetEnvValue("APPDATA");

    if (!localApp.empty()) {
        if (HasToken(requestJson, "chrome") || !HasToken(requestJson, "edge")) {
            paths.emplace_back(localApp + "\\Google\\Chrome\\User Data\\Default\\Cache");
            paths.emplace_back(localApp + "\\Google\\Chrome\\User Data\\Default\\Code Cache");
        }
        if (HasToken(requestJson, "edge") || !HasToken(requestJson, "chrome")) {
            paths.emplace_back(localApp + "\\Microsoft\\Edge\\User Data\\Default\\Cache");
            paths.emplace_back(localApp + "\\Microsoft\\Edge\\User Data\\Default\\Code Cache");
        }
    }

    if (!appData.empty() && (HasToken(requestJson, "firefox") || (!HasToken(requestJson, "chrome") && !HasToken(requestJson, "edge")))) {
        fs::path profiles = fs::path(appData) / "Mozilla" / "Firefox" / "Profiles";
        std::error_code ec;
        if (fs::exists(profiles, ec) && fs::is_directory(profiles, ec)) {
            for (auto& entry : fs::directory_iterator(profiles, fs::directory_options::skip_permission_denied, ec)) {
                if (entry.is_directory(ec)) {
                    paths.emplace_back(entry.path() / "cache2");
                }
            }
        }
    }
    return paths;
}

std::vector<fs::path> CollectCleanerPaths(const std::string& category, const std::string& requestJson) {
    std::vector<fs::path> paths;
    std::string localApp = GetEnvValue("LOCALAPPDATA");
    std::string appData = GetEnvValue("APPDATA");
    std::string temp = GetEnvValue("TEMP");
    std::string tmp = GetEnvValue("TMP");
    std::string programData = GetEnvValue("PROGRAMDATA");

    if (category == "temp") {
        if (!temp.empty()) paths.emplace_back(temp);
        if (!tmp.empty() && tmp != temp) paths.emplace_back(tmp);
        if (!localApp.empty()) paths.emplace_back(localApp + "\\Temp");
        paths.emplace_back("C:\\Windows\\Temp");
    } else if (category == "browser") {
        auto browser = CollectBrowserPaths(requestJson);
        paths.insert(paths.end(), browser.begin(), browser.end());
    } else if (category == "logs") {
        paths.emplace_back("C:\\Windows\\Logs");
        if (!localApp.empty()) paths.emplace_back(localApp + "\\CrashDumps");
        if (!programData.empty()) {
            paths.emplace_back(programData + "\\Microsoft\\Windows\\WER\\ReportArchive");
            paths.emplace_back(programData + "\\Microsoft\\Windows\\WER\\ReportQueue");
        }
    } else if (category == "prefetch") {
        paths.emplace_back("C:\\Windows\\Prefetch");
    } else if (category == "thumbnail") {
        if (!localApp.empty()) {
            paths.emplace_back(localApp + "\\Microsoft\\Windows\\Explorer");
        }
    } else if (category == "windowsupdate") {
        paths.emplace_back("C:\\Windows\\SoftwareDistribution\\Download");
    } else if (category == "appcache") {
        if (!appData.empty()) {
            paths.emplace_back(appData + "\\Discord\\Cache");
            paths.emplace_back(appData + "\\Spotify\\Storage");
            paths.emplace_back(appData + "\\npm-cache");
        }
        if (!localApp.empty()) {
            paths.emplace_back(localApp + "\\Steam\\htmlcache");
        }
    }

    return paths;
}

bool RunProcessCapture(const std::string& commandLine, std::string& output, DWORD& exitCode) {
    output.clear();
    exitCode = 1;

    SECURITY_ATTRIBUTES sa{};
    sa.nLength = sizeof(sa);
    sa.bInheritHandle = TRUE;

    HANDLE hRead = nullptr;
    HANDLE hWrite = nullptr;
    if (!CreatePipe(&hRead, &hWrite, &sa, 0)) return false;
    SetHandleInformation(hRead, HANDLE_FLAG_INHERIT, 0);

    STARTUPINFOA si{};
    PROCESS_INFORMATION pi{};
    si.cb = sizeof(si);
    si.dwFlags = STARTF_USESTDHANDLES;
    si.hStdOutput = hWrite;
    si.hStdError = hWrite;

    std::vector<char> mutableCmd(commandLine.begin(), commandLine.end());
    mutableCmd.push_back('\0');

    BOOL created = CreateProcessA(
        nullptr,
        mutableCmd.data(),
        nullptr,
        nullptr,
        TRUE,
        CREATE_NO_WINDOW,
        nullptr,
        nullptr,
        &si,
        &pi);

    CloseHandle(hWrite);
    if (!created) {
        CloseHandle(hRead);
        return false;
    }

    WaitForSingleObject(pi.hProcess, INFINITE);

    char buffer[4096];
    DWORD read = 0;
    while (ReadFile(hRead, buffer, sizeof(buffer), &read, nullptr) && read > 0) {
        output.append(buffer, buffer + read);
    }

    GetExitCodeProcess(pi.hProcess, &exitCode);
    CloseHandle(hRead);
    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);
    return true;
}

bool RunCommand(const std::string& command, std::string& output, DWORD& exitCode) {
    return RunProcessCapture("cmd.exe /C " + command, output, exitCode);
}

bool RunPowerShell(const std::string& command, std::string& output, DWORD& exitCode) {
    return RunProcessCapture("powershell -NoProfile -ExecutionPolicy Bypass -Command \"" + command + "\"", output, exitCode);
}

std::vector<std::string> ParseOptimizerOperations(const std::string& optionsJson) {
    std::vector<std::string> ops;
    auto addIf = [&](const std::string& token) {
        if (HasToken(optionsJson, token)) ops.push_back(token);
    };

    addIf("sfc_scannow");
    addIf("dism_checkhealth");
    addIf("dism_restorehealth");
    addIf("dism_cleanup_components");
    addIf("dism_resetbase");
    addIf("privacy_activity_history");
    addIf("privacy_telemetry");
    addIf("privacy_location");
    addIf("privacy_windows_search");
    addIf("privacy_advertising_id");
    addIf("boot_fixmbr");
    addIf("boot_fixboot");
    addIf("boot_rebuildbcd");
    addIf("boot_bootsect");
    addIf("boot_tweak_tsync");
    addIf("boot_tweak_useplatformtick");
    addIf("reg_tweak_graphics_scheduler");
    addIf("reg_tweak_large_system_cache");
    addIf("reg_tweak_mmcss");
    addIf("reg_tweak_tcp_ack");
    addIf("reg_tweak_priority_separation");
    addIf("backup_system_restore_point");
    addIf("backup_registry_full");
    addIf("backup_drivers");
    addIf("net_reset_winsock");
    addIf("net_flush_dns");
    addIf("perf_visual_effects");
    addIf("perf_power_plan");

    // Backward compatibility
    if (HasToken(optionsJson, "sfc")) ops.push_back("sfc_scannow");
    if (HasToken(optionsJson, "dism")) ops.push_back("dism_restorehealth");

    if (ops.empty()) {
        ops.push_back("sfc_scannow");
        ops.push_back("dism_restorehealth");
    }

    std::set<std::string> unique(ops.begin(), ops.end());
    return std::vector<std::string>(unique.begin(), unique.end());
}

bool SetRegDword(HKEY root, const char* subkey, const char* valueName, DWORD value) {
    HKEY hKey = nullptr;
    if (RegCreateKeyExA(root, subkey, 0, nullptr, 0, KEY_SET_VALUE, nullptr, &hKey, nullptr) != ERROR_SUCCESS) {
        return false;
    }
    LONG rc = RegSetValueExA(hKey, valueName, 0, REG_DWORD, reinterpret_cast<const BYTE*>(&value), sizeof(value));
    RegCloseKey(hKey);
    return rc == ERROR_SUCCESS;
}

bool ExecuteOptimizerOperation(const std::string& op, std::string& output, DWORD& exitCode) {
    if (op == "sfc_scannow") return RunCommand("sfc /scannow", output, exitCode);
    if (op == "dism_checkhealth") return RunCommand("DISM /Online /Cleanup-Image /CheckHealth", output, exitCode);
    if (op == "dism_restorehealth") return RunCommand("DISM /Online /Cleanup-Image /RestoreHealth", output, exitCode);
    if (op == "dism_cleanup_components") return RunCommand("DISM /Online /Cleanup-Image /StartComponentCleanup", output, exitCode);
    if (op == "dism_resetbase") return RunCommand("DISM /Online /Cleanup-Image /StartComponentCleanup /ResetBase", output, exitCode);

    if (op == "privacy_activity_history") return RunCommand("reg delete \"HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\RunMRU\" /f", output, exitCode);
    if (op == "privacy_telemetry") {
        const bool ok = SetRegDword(HKEY_LOCAL_MACHINE, "SOFTWARE\\Policies\\Microsoft\\Windows\\DataCollection", "AllowTelemetry", 0);
        output = ok ? "AllowTelemetry=0" : "Failed to set AllowTelemetry";
        exitCode = ok ? 0 : 1;
        return true;
    }
    if (op == "privacy_location") return RunCommand("reg add \"HKLM\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\CapabilityAccessManager\\ConsentStore\\location\" /v Value /t REG_SZ /d Deny /f", output, exitCode);
    if (op == "privacy_windows_search") return RunCommand("reg delete \"HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\SearchSettings\" /f", output, exitCode);
    if (op == "privacy_advertising_id") return RunCommand("reg add \"HKLM\\SOFTWARE\\Policies\\Microsoft\\Windows\\AdvertisingInfo\" /v DisabledByGroupPolicy /t REG_DWORD /d 1 /f", output, exitCode);

    if (op == "boot_fixmbr") return RunCommand("bootrec /fixmbr", output, exitCode);
    if (op == "boot_fixboot") return RunCommand("bootrec /fixboot", output, exitCode);
    if (op == "boot_rebuildbcd") return RunCommand("bootrec /rebuildbcd", output, exitCode);
    if (op == "boot_bootsect") return RunCommand("bootsect /nt60 SYS /mbr /force", output, exitCode);
    if (op == "boot_tweak_tsync") return RunCommand("bcdedit /set tscsyncpolicy enhanced", output, exitCode);
    if (op == "boot_tweak_useplatformtick") return RunCommand("bcdedit /deletevalue useplatformtick", output, exitCode);

    if (op == "reg_tweak_graphics_scheduler") {
        const bool ok = SetRegDword(HKEY_LOCAL_MACHINE, "SYSTEM\\CurrentControlSet\\Control\\GraphicsDrivers", "HwSchMode", 2);
        output = ok ? "HwSchMode=2" : "Failed to set HwSchMode";
        exitCode = ok ? 0 : 1;
        return true;
    }
    if (op == "reg_tweak_large_system_cache") {
        const bool ok = SetRegDword(HKEY_LOCAL_MACHINE, "SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Memory Management", "LargeSystemCache", 1);
        output = ok ? "LargeSystemCache=1" : "Failed to set LargeSystemCache";
        exitCode = ok ? 0 : 1;
        return true;
    }
    if (op == "reg_tweak_mmcss") {
        const bool ok = SetRegDword(HKEY_LOCAL_MACHINE, "SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Multimedia\\SystemProfile", "SystemResponsiveness", 10);
        output = ok ? "SystemResponsiveness=10" : "Failed to set SystemResponsiveness";
        exitCode = ok ? 0 : 1;
        return true;
    }
    if (op == "reg_tweak_tcp_ack") {
        const bool ok = SetRegDword(HKEY_LOCAL_MACHINE, "SOFTWARE\\Microsoft\\MSMQ\\Parameters", "TCPNoDelay", 1);
        output = ok ? "TCPNoDelay=1" : "Failed to set TCPNoDelay";
        exitCode = ok ? 0 : 1;
        return true;
    }
    if (op == "reg_tweak_priority_separation") {
        const bool ok = SetRegDword(HKEY_LOCAL_MACHINE, "SYSTEM\\CurrentControlSet\\Control\\PriorityControl", "Win32PrioritySeparation", 26);
        output = ok ? "Win32PrioritySeparation=26" : "Failed to set Win32PrioritySeparation";
        exitCode = ok ? 0 : 1;
        return true;
    }

    if (op == "backup_system_restore_point") {
        return RunPowerShell("Checkpoint-Computer -Description 'NeoOptimize Backup' -RestorePointType MODIFY_SETTINGS", output, exitCode);
    }
    if (op == "backup_registry_full") {
        fs::path backupRoot = BuildBackupRoot("registry");
        std::string out1, out2;
        DWORD rc1 = 1, rc2 = 1;
        bool ok1 = RunCommand("reg export HKLM \"" + (backupRoot / "HKLM.reg").string() + "\" /y", out1, rc1);
        bool ok2 = RunCommand("reg export HKCU \"" + (backupRoot / "HKCU.reg").string() + "\" /y", out2, rc2);
        output = out1 + "\n" + out2;
        exitCode = (ok1 && ok2 && rc1 == 0 && rc2 == 0) ? 0 : 1;
        return ok1 && ok2;
    }
    if (op == "backup_drivers") {
        fs::path backupRoot = BuildBackupRoot("drivers");
        return RunCommand("dism /online /export-driver /destination:\"" + backupRoot.string() + "\"", output, exitCode);
    }

    if (op == "net_reset_winsock") return RunCommand("netsh winsock reset", output, exitCode);
    if (op == "net_flush_dns") return RunCommand("ipconfig /flushdns", output, exitCode);
    if (op == "perf_visual_effects") return RunCommand("reg add \"HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\VisualEffects\" /v VisualFXSetting /t REG_DWORD /d 2 /f", output, exitCode);
    if (op == "perf_power_plan") return RunCommand("powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c", output, exitCode);

    output = "Operation not implemented";
    exitCode = 1;
    return false;
}

bool ReadRegString(HKEY hKey, const char* valueName, std::string& out) {
    out.clear();
    DWORD type = 0;
    DWORD size = 0;
    LONG rc = RegQueryValueExA(hKey, valueName, nullptr, &type, nullptr, &size);
    if (rc != ERROR_SUCCESS || (type != REG_SZ && type != REG_EXPAND_SZ) || size == 0) return false;
    std::vector<char> buffer(size + 1, 0);
    rc = RegQueryValueExA(hKey, valueName, nullptr, &type, reinterpret_cast<LPBYTE>(buffer.data()), &size);
    if (rc != ERROR_SUCCESS) return false;
    out.assign(buffer.data());
    return !out.empty();
}

bool TryFindUninstallCommand(HKEY root, const char* subKey, const std::string& appId, std::string& command, std::string& displayName) {
    HKEY hKey = nullptr;
    if (RegOpenKeyExA(root, subKey, 0, KEY_READ, &hKey) != ERROR_SUCCESS) return false;

    // direct key lookup first
    HKEY hDirect = nullptr;
    if (RegOpenKeyExA(hKey, appId.c_str(), 0, KEY_READ, &hDirect) == ERROR_SUCCESS) {
        std::string quiet;
        std::string uninstall;
        ReadRegString(hDirect, "QuietUninstallString", quiet);
        ReadRegString(hDirect, "UninstallString", uninstall);
        ReadRegString(hDirect, "DisplayName", displayName);
        RegCloseKey(hDirect);
        if (!quiet.empty() || !uninstall.empty()) {
            command = quiet.empty() ? uninstall : quiet;
            RegCloseKey(hKey);
            return true;
        }
    }

    // fallback by display name contains
    DWORD idx = 0;
    char name[256];
    while (true) {
        DWORD nameLen = static_cast<DWORD>(sizeof(name));
        FILETIME ft{};
        if (RegEnumKeyExA(hKey, idx++, name, &nameLen, nullptr, nullptr, nullptr, &ft) != ERROR_SUCCESS) break;

        HKEY hSub = nullptr;
        if (RegOpenKeyExA(hKey, name, 0, KEY_READ, &hSub) != ERROR_SUCCESS) continue;

        std::string display;
        std::string uninstall;
        std::string quiet;
        ReadRegString(hSub, "DisplayName", display);
        ReadRegString(hSub, "UninstallString", uninstall);
        ReadRegString(hSub, "QuietUninstallString", quiet);
        RegCloseKey(hSub);

        if (display.empty()) continue;
        std::string displayLower = ToLower(display);
        std::string idLower = ToLower(appId);
        if (displayLower.find(idLower) != std::string::npos) {
            if (!quiet.empty() || !uninstall.empty()) {
                command = quiet.empty() ? uninstall : quiet;
                displayName = display;
                RegCloseKey(hKey);
                return true;
            }
        }
    }

    RegCloseKey(hKey);
    return false;
}

std::string BuildUninstallCommand(std::string uninstallString) {
    std::string lower = ToLower(uninstallString);
    if (lower.find("msiexec") != std::string::npos && lower.find("/quiet") == std::string::npos) {
        uninstallString += " /quiet /norestart";
    }
    return uninstallString;
}

std::string SanitizeId(std::string appId) {
    appId.erase(std::remove_if(appId.begin(), appId.end(), [](char c) {
        return c == '"' || c == '\'' || c == '`';
    }), appId.end());
    return appId;
}

std::vector<std::string> ParseAppManagerOperations(const std::string& optionsJson) {
    std::vector<std::string> ops;
    auto addIf = [&](const std::string& token, const std::string& mapped = std::string()) {
        if (HasToken(optionsJson, token)) ops.push_back(mapped.empty() ? token : mapped);
    };

    addIf("bloatware_microsoft");
    addIf("bloatware_manufacturer");
    addIf("bloatware_games");
    addIf("bloatware_trial_software");
    addIf("startup_disable_all");
    addIf("background_disable_all");
    addIf("app_cache_chrome");
    addIf("app_cache_discord");
    addIf("app_cache_spotify");
    addIf("app_cache_steam");
    addIf("app_cache_npm");
    addIf("app_cache_all");
    addIf("deep_clean_app_data");

    // Backward compatibility aliases
    addIf("microsoft", "bloatware_microsoft");
    addIf("manufacturer", "bloatware_manufacturer");
    addIf("games", "bloatware_games");
    addIf("trial", "bloatware_trial_software");
    addIf("startup", "startup_disable_all");
    addIf("background", "background_disable_all");

    if (ops.empty()) {
        ops = {
            "bloatware_microsoft",
            "startup_disable_all",
            "background_disable_all",
            "app_cache_all",
            "deep_clean_app_data"
        };
    }

    std::set<std::string> unique(ops.begin(), ops.end());
    return std::vector<std::string>(unique.begin(), unique.end());
}

std::vector<fs::path> CollectAppCachePaths(const std::string& operation) {
    std::vector<fs::path> paths;
    const std::string localApp = GetEnvValue("LOCALAPPDATA");
    const std::string appData = GetEnvValue("APPDATA");

    auto addChrome = [&]() {
        if (!localApp.empty()) {
            paths.emplace_back(localApp + "\\Google\\Chrome\\User Data\\Default\\Cache");
            paths.emplace_back(localApp + "\\Google\\Chrome\\User Data\\Default\\Code Cache");
        }
    };
    auto addDiscord = [&]() {
        if (!appData.empty()) {
            paths.emplace_back(appData + "\\Discord\\Cache");
            paths.emplace_back(appData + "\\Discord\\Code Cache");
        }
        if (!localApp.empty()) {
            paths.emplace_back(localApp + "\\Discord\\Cache");
        }
    };
    auto addSpotify = [&]() {
        if (!appData.empty()) {
            paths.emplace_back(appData + "\\Spotify\\Storage");
        }
        if (!localApp.empty()) {
            paths.emplace_back(localApp + "\\Spotify\\Storage");
        }
    };
    auto addSteam = [&]() {
        if (!localApp.empty()) {
            paths.emplace_back(localApp + "\\Steam\\htmlcache");
        }
    };
    auto addNpm = [&]() {
        if (!appData.empty()) {
            paths.emplace_back(appData + "\\npm-cache");
        }
        if (!localApp.empty()) {
            paths.emplace_back(localApp + "\\npm-cache");
        }
    };

    if (operation == "app_cache_chrome") {
        addChrome();
    } else if (operation == "app_cache_discord") {
        addDiscord();
    } else if (operation == "app_cache_spotify") {
        addSpotify();
    } else if (operation == "app_cache_steam") {
        addSteam();
    } else if (operation == "app_cache_npm") {
        addNpm();
    } else {
        addChrome();
        addDiscord();
        addSpotify();
        addSteam();
        addNpm();
        if (!localApp.empty()) {
            paths.emplace_back(localApp + "\\Microsoft\\Edge\\User Data\\Default\\Cache");
            paths.emplace_back(localApp + "\\Microsoft\\Edge\\User Data\\Default\\Code Cache");
        }
    }

    std::set<std::string> unique;
    std::vector<fs::path> normalized;
    for (const auto& p : paths) {
        if (unique.insert(ToLower(p.string())).second) {
            normalized.push_back(p);
        }
    }
    return normalized;
}

bool CleanPathList(const std::vector<fs::path>& paths, uint64_t& bytesFreed, int& itemsAffected, std::string& output) {
    bool ok = true;
    std::ostringstream out;
    for (const auto& path : paths) {
        std::error_code ec;
        if (!fs::exists(path, ec)) continue;
        const PathStat stat = CollectPathStat(path);
        bytesFreed += stat.bytes;
        itemsAffected += static_cast<int>(stat.files);
        fs::remove_all(path, ec);
        out << path.string() << ":" << (ec ? "failed" : "cleaned") << ";";
        if (ec) ok = false;
    }
    output = out.str();
    return ok;
}

bool DisableRunEntries(HKEY root, const char* subKey, int& count) {
    HKEY hKey = nullptr;
    if (RegOpenKeyExA(root, subKey, 0, KEY_QUERY_VALUE | KEY_SET_VALUE, &hKey) != ERROR_SUCCESS) {
        return false;
    }

    std::vector<std::string> valueNames;
    DWORD idx = 0;
    while (true) {
        char valueName[512];
        DWORD valueNameLen = static_cast<DWORD>(sizeof(valueName));
        LONG rc = RegEnumValueA(hKey, idx++, valueName, &valueNameLen, nullptr, nullptr, nullptr, nullptr);
        if (rc == ERROR_NO_MORE_ITEMS) break;
        if (rc == ERROR_SUCCESS && valueNameLen > 0) {
            valueNames.emplace_back(valueName);
        }
    }

    for (const auto& name : valueNames) {
        if (RegDeleteValueA(hKey, name.c_str()) == ERROR_SUCCESS) {
            ++count;
        }
    }

    RegCloseKey(hKey);
    return true;
}

bool DisableAllStartupEntries(int& itemsAffected, std::string& output, DWORD& exitCode) {
    fs::path backupRoot = BuildBackupRoot("appmanager_startup");
    std::string out1;
    std::string out2;
    DWORD rc1 = 1;
    DWORD rc2 = 1;
    RunCommand("reg export HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run \"" + (backupRoot / "hkcu_run.reg").string() + "\" /y", out1, rc1);
    RunCommand("reg export HKLM\\Software\\Microsoft\\Windows\\CurrentVersion\\Run \"" + (backupRoot / "hklm_run.reg").string() + "\" /y", out2, rc2);

    int count = 0;
    bool ok1 = DisableRunEntries(HKEY_CURRENT_USER, "Software\\Microsoft\\Windows\\CurrentVersion\\Run", count);
    bool ok2 = DisableRunEntries(HKEY_LOCAL_MACHINE, "Software\\Microsoft\\Windows\\CurrentVersion\\Run", count);
    bool ok3 = DisableRunEntries(HKEY_LOCAL_MACHINE, "Software\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Run", count);
    itemsAffected += count;
    output = "startup_items_disabled=" + std::to_string(count);
    exitCode = (ok1 || ok2 || ok3) ? 0 : 1;
    return ok1 || ok2 || ok3;
}

bool DisableBackgroundApps(int& itemsAffected, std::string& output, DWORD& exitCode) {
    bool ok = true;
    ok = SetRegDword(HKEY_CURRENT_USER, "Software\\Microsoft\\Windows\\CurrentVersion\\BackgroundAccessApplications", "GlobalUserDisabled", 1) && ok;
    ok = SetRegDword(HKEY_CURRENT_USER, "Software\\Microsoft\\Windows\\CurrentVersion\\Search", "BackgroundAppGlobalToggle", 0) && ok;
    output = ok ? "background_apps_disabled=1" : "failed_background_disable";
    itemsAffected += ok ? 1 : 0;
    exitCode = ok ? 0 : 1;
    return ok;
}

bool UninstallAppxPackages(const std::vector<std::string>& packageNames, int& itemsAffected, std::string& output, DWORD& exitCode) {
    int success = 0;
    std::ostringstream out;
    for (const auto& pkg : packageNames) {
        std::string cmdOut;
        DWORD rc = 1;
        bool ran = RunPowerShell("Get-AppxPackage -Name '" + pkg + "' | Remove-AppxPackage", cmdOut, rc);
        if (ran && rc == 0) {
            ++success;
        }
        out << pkg << ":" << (ran && rc == 0 ? "removed" : "skip") << ";";
    }
    itemsAffected += success;
    output = out.str();
    exitCode = 0;
    return true;
}

bool UninstallByKeywordList(const std::vector<std::string>& keywords, int& itemsAffected, std::string& output, DWORD& exitCode) {
    int success = 0;
    std::ostringstream out;
    for (const auto& keyword : keywords) {
        std::string uninstallCmd;
        std::string displayName;
        bool found = false;
        found = TryFindUninstallCommand(HKEY_LOCAL_MACHINE, "SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall", keyword, uninstallCmd, displayName) || found;
        found = TryFindUninstallCommand(HKEY_LOCAL_MACHINE, "SOFTWARE\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall", keyword, uninstallCmd, displayName) || found;
        found = TryFindUninstallCommand(HKEY_CURRENT_USER, "SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall", keyword, uninstallCmd, displayName) || found;
        if (!found || uninstallCmd.empty()) {
            out << keyword << ":not_found;";
            continue;
        }

        std::string cmdOut;
        DWORD rc = 1;
        bool ran = RunCommand(BuildUninstallCommand(uninstallCmd), cmdOut, rc);
        if (ran && rc == 0) {
            ++success;
            out << keyword << ":removed;";
        } else {
            out << keyword << ":failed;";
        }
    }
    itemsAffected += success;
    output = out.str();
    exitCode = 0;
    return true;
}

bool ExecuteAppManagerOperation(const std::string& op, uint64_t& bytesFreed, int& itemsAffected, std::string& output, DWORD& exitCode) {
    if (op == "bloatware_microsoft") {
        return UninstallAppxPackages({
            "Microsoft.XboxApp",
            "Microsoft.XboxGamingOverlay",
            "Microsoft.XboxSpeechToTextOverlay",
            "Microsoft.XboxGameCallableUI",
            "Microsoft.SkypeApp",
            "Microsoft.Getstarted",
            "Microsoft.MicrosoftSolitaireCollection",
            "Microsoft.BingNews",
            "Microsoft.BingWeather",
            "Microsoft.People",
            "Microsoft.YourPhone",
            "Microsoft.MicrosoftOfficeHub",
            "Microsoft.PowerAutomateDesktop"
        }, itemsAffected, output, exitCode);
    }

    if (op == "bloatware_games") {
        return UninstallAppxPackages({
            "Microsoft.MicrosoftSolitaireCollection",
            "Microsoft.Minesweeper",
            "Microsoft.XboxApp"
        }, itemsAffected, output, exitCode);
    }

    if (op == "bloatware_manufacturer") {
        return UninstallByKeywordList({
            "Dell",
            "HP",
            "Lenovo",
            "ASUS",
            "Acer",
            "SupportAssist"
        }, itemsAffected, output, exitCode);
    }

    if (op == "bloatware_trial_software") {
        return UninstallByKeywordList({
            "McAfee",
            "Norton",
            "WildTangent",
            "Dropbox Promotion"
        }, itemsAffected, output, exitCode);
    }

    if (op == "startup_disable_all") {
        return DisableAllStartupEntries(itemsAffected, output, exitCode);
    }

    if (op == "background_disable_all") {
        return DisableBackgroundApps(itemsAffected, output, exitCode);
    }

    if (op == "app_cache_chrome" || op == "app_cache_discord" || op == "app_cache_spotify" ||
        op == "app_cache_steam" || op == "app_cache_npm" || op == "app_cache_all") {
        auto paths = CollectAppCachePaths(op);
        bool ok = CleanPathList(paths, bytesFreed, itemsAffected, output);
        exitCode = ok ? 0 : 1;
        return true;
    }

    if (op == "deep_clean_app_data") {
        std::vector<fs::path> paths;
        const std::string localApp = GetEnvValue("LOCALAPPDATA");
        const std::string appData = GetEnvValue("APPDATA");
        if (!localApp.empty()) {
            paths.emplace_back(localApp + "\\Discord\\Cache");
            paths.emplace_back(localApp + "\\Discord\\Code Cache");
            paths.emplace_back(localApp + "\\Spotify\\Storage");
            paths.emplace_back(localApp + "\\Steam\\htmlcache");
            paths.emplace_back(localApp + "\\Temp\\npm-cache");
            paths.emplace_back(localApp + "\\Temp\\pip-cache");
        }
        if (!appData.empty()) {
            paths.emplace_back(appData + "\\Discord\\Cache");
            paths.emplace_back(appData + "\\Discord\\Code Cache");
            paths.emplace_back(appData + "\\Spotify\\Storage");
            paths.emplace_back(appData + "\\npm-cache");
        }
        bool ok = CleanPathList(paths, bytesFreed, itemsAffected, output);
        exitCode = ok ? 0 : 1;
        return true;
    }

    output = "Operation not implemented";
    exitCode = 1;
    return false;
}

std::string QuoteForCmd(const std::string& value) {
    return "\"" + value + "\"";
}

std::string GetHostExecutablePath() {
    char buffer[MAX_PATH * 4] = {0};
    DWORD len = GetModuleFileNameA(nullptr, buffer, static_cast<DWORD>(sizeof(buffer)));
    if (len == 0 || len >= sizeof(buffer)) {
        return std::string();
    }
    return std::string(buffer, len);
}

std::string ResolveClamScanPath() {
    std::vector<std::string> candidates = {
        "clamscan.exe",
        "D:\\NeoOptimize\\clamav-1.5.1.win.x64\\clamscan.exe",
        "D:\\NeoOptimize\\clamav-1.5.1.win.win32\\clamscan.exe"
    };

    std::string exeDir = GetHostExecutablePath();
    if (!exeDir.empty()) {
        fs::path p = fs::path(exeDir).parent_path();
        candidates.push_back((p / "clamscan.exe").string());
        candidates.push_back((p / "..\\..\\clamav-1.5.1.win.x64\\clamscan.exe").lexically_normal().string());
        candidates.push_back((p / "..\\..\\clamav-1.5.1.win.win32\\clamscan.exe").lexically_normal().string());
    }

    for (const auto& path : candidates) {
        if (path == "clamscan.exe") return path;
        std::error_code ec;
        if (fs::exists(path, ec)) return path;
    }
    return "clamscan.exe";
}

std::string ResolveKicomavScriptPath() {
    std::vector<std::string> candidates = {
        "D:\\NeoOptimize\\kicomav-master\\kicomav\\k2.py"
    };
    std::string exePath = GetHostExecutablePath();
    if (!exePath.empty()) {
        fs::path p = fs::path(exePath).parent_path();
        candidates.push_back((p / "..\\..\\kicomav-master\\kicomav\\k2.py").lexically_normal().string());
    }
    for (const auto& path : candidates) {
        std::error_code ec;
        if (fs::exists(path, ec)) return path;
    }
    return "D:\\NeoOptimize\\kicomav-master\\kicomav\\k2.py";
}

std::vector<std::string> ParseSecurityOperations(const std::string& optionsJson) {
    std::vector<std::string> ops;
    auto addIf = [&](const std::string& token, const std::string& mapped = std::string()) {
        if (HasToken(optionsJson, token)) ops.push_back(mapped.empty() ? token : mapped);
    };

    addIf("clamav_quick_scan");
    addIf("clamav_full_scan");
    addIf("kicomav_scan_folder");
    addIf("realtime_protection_enable");
    addIf("realtime_protection_disable");

    // aliases
    addIf("quick_scan", "clamav_quick_scan");
    addIf("full_scan", "clamav_full_scan");
    addIf("kicomav", "kicomav_scan_folder");
    addIf("realtime_enable", "realtime_protection_enable");
    addIf("realtime_disable", "realtime_protection_disable");

    if (ops.empty()) {
        ops = {"clamav_quick_scan"};
    }
    std::set<std::string> unique(ops.begin(), ops.end());
    return std::vector<std::string>(unique.begin(), unique.end());
}

bool ExecuteSecurityOperation(const std::string& op, const std::string& optionsJson, std::string& output, DWORD& exitCode) {
    std::string targetPath = ExtractJsonString(optionsJson, "targetPath");
    if (targetPath.empty()) {
        std::string userProfile = GetEnvValue("USERPROFILE");
        if (!userProfile.empty()) {
            targetPath = userProfile + "\\Downloads";
        } else {
            targetPath = "C:\\";
        }
    }

    if (op == "clamav_quick_scan") {
        std::string clamscan = ResolveClamScanPath();
        std::string cmd = QuoteForCmd(clamscan) + " --recursive --infected --no-summary " + QuoteForCmd(targetPath);
        return RunCommand(cmd, output, exitCode);
    }

    if (op == "clamav_full_scan") {
        std::string clamscan = ResolveClamScanPath();
        std::string fullPath = targetPath;
        if (fullPath.empty()) fullPath = "C:\\";
        std::string cmd = QuoteForCmd(clamscan) + " --recursive --infected --no-summary " + QuoteForCmd(fullPath);
        return RunCommand(cmd, output, exitCode);
    }

    if (op == "kicomav_scan_folder") {
        std::string script = ResolveKicomavScriptPath();
        std::string cmd = "python " + QuoteForCmd(script) + " " + QuoteForCmd(targetPath);
        return RunCommand(cmd, output, exitCode);
    }

    if (op == "realtime_protection_enable") {
        bool ok = SetRegDword(HKEY_CURRENT_USER, "Software\\NeoOptimize\\Security", "RealtimeProtection", 1);
        output = ok ? "RealtimeProtection=1" : "failed_realtime_enable";
        exitCode = ok ? 0 : 1;
        return true;
    }

    if (op == "realtime_protection_disable") {
        bool ok = SetRegDword(HKEY_CURRENT_USER, "Software\\NeoOptimize\\Security", "RealtimeProtection", 0);
        output = ok ? "RealtimeProtection=0" : "failed_realtime_disable";
        exitCode = ok ? 0 : 1;
        return true;
    }

    output = "Operation not implemented";
    exitCode = 1;
    return false;
}

std::vector<std::string> ParseSchedulerOperations(const std::string& optionsJson) {
    std::vector<std::string> ops;
    auto addIf = [&](const std::string& token, const std::string& mapped = std::string()) {
        if (HasToken(optionsJson, token)) ops.push_back(mapped.empty() ? token : mapped);
    };

    addIf("startup_delay_5min");
    addIf("clean_before_shutdown");
    addIf("periodic_5min");
    addIf("periodic_10min");
    addIf("periodic_30min");
    addIf("periodic_60min");
    addIf("ai_recommended_schedule");

    // aliases
    addIf("startup_delay", "startup_delay_5min");
    addIf("periodic_clean_5", "periodic_5min");
    addIf("periodic_clean_10", "periodic_10min");
    addIf("periodic_clean_30", "periodic_30min");
    addIf("periodic_clean_60", "periodic_60min");
    addIf("recommended", "ai_recommended_schedule");

    if (ops.empty()) {
        ops = {"ai_recommended_schedule"};
    }
    std::set<std::string> unique(ops.begin(), ops.end());
    return std::vector<std::string>(unique.begin(), unique.end());
}

bool CreateStartupDelayTask(int minutes, std::string& output, DWORD& exitCode) {
    std::string hostExe = GetHostExecutablePath();
    if (hostExe.empty()) {
        output = "host_executable_not_found";
        exitCode = 1;
        return false;
    }
    std::ostringstream delay;
    delay << "000" << minutes << ":00";
    std::string cmd = "schtasks /Create /F /TN \"NeoOptimize\\StartupDelay\" /SC ONLOGON /DELAY " + delay.str() +
                      " /TR \"\\\"" + hostExe + "\\\" --scheduled-clean\"";
    return RunCommand(cmd, output, exitCode);
}

bool CreatePeriodicTask(int minutes, std::string& output, DWORD& exitCode) {
    std::string hostExe = GetHostExecutablePath();
    if (hostExe.empty()) {
        output = "host_executable_not_found";
        exitCode = 1;
        return false;
    }
    std::ostringstream taskName;
    taskName << "NeoOptimize\\PeriodicClean" << minutes;
    std::string cmd = "schtasks /Create /F /TN \"" + taskName.str() + "\" /SC MINUTE /MO " + std::to_string(minutes) +
                      " /TR \"\\\"" + hostExe + "\\\" --scheduled-clean\"";
    return RunCommand(cmd, output, exitCode);
}

bool ExecuteSchedulerOperation(const std::string& op, std::string& output, DWORD& exitCode) {
    if (op == "startup_delay_5min") {
        return CreateStartupDelayTask(5, output, exitCode);
    }

    if (op == "clean_before_shutdown") {
        bool ok = SetRegDword(HKEY_CURRENT_USER, "Software\\NeoOptimize\\Scheduler", "CleanBeforeShutdown", 1);
        output = ok ? "CleanBeforeShutdown=1" : "failed_clean_before_shutdown";
        exitCode = ok ? 0 : 1;
        return true;
    }

    if (op == "periodic_5min") return CreatePeriodicTask(5, output, exitCode);
    if (op == "periodic_10min") return CreatePeriodicTask(10, output, exitCode);
    if (op == "periodic_30min") return CreatePeriodicTask(30, output, exitCode);
    if (op == "periodic_60min") return CreatePeriodicTask(60, output, exitCode);

    if (op == "ai_recommended_schedule") {
        std::string out1, out2;
        DWORD rc1 = 1, rc2 = 1;
        bool ok1 = CreateStartupDelayTask(5, out1, rc1);
        bool ok2 = CreatePeriodicTask(30, out2, rc2);
        bool ok3 = SetRegDword(HKEY_CURRENT_USER, "Software\\NeoOptimize\\Scheduler", "AIRecommended", 1);
        output = out1 + ";" + out2 + ";" + (ok3 ? "AIRecommended=1" : "AIRecommended=0");
        exitCode = (ok1 && ok2 && ok3 && rc1 == 0 && rc2 == 0) ? 0 : 1;
        return true;
    }

    output = "Operation not implemented";
    exitCode = 1;
    return false;
}

} // namespace

extern "C" {

const char* __cdecl NO_GetVersion() {
    return g_version.c_str();
}

int __cdecl NO_RegisterProgressCallback(NO_ProgressCallback cb) {
    std::lock_guard<std::mutex> lk(g_cbMutex);
    g_progressCb = cb;
    return 0;
}

void __cdecl NO_UnregisterProgressCallback() {
    std::lock_guard<std::mutex> lk(g_cbMutex);
    g_progressCb = nullptr;
}

int __cdecl NO_StartScan(const char* categoriesJson) {
    if (g_running.load()) return 1;
    const std::string requestJson = categoriesJson ? std::string(categoriesJson) : std::string("{}");
    const auto categories = ParseCleanerCategories(requestJson);
    g_running.store(true);
    std::thread([categories, requestJson]() {
        uint64_t totalBytes = 0;
        uint64_t totalFiles = 0;
        try {
            for (size_t catIdx = 0; catIdx < categories.size(); ++catIdx) {
                if (!g_running.load()) break;
                const std::string& category = categories[catIdx];
                const int baseProgress = static_cast<int>((catIdx * 100) / (categories.size() == 0 ? 1 : categories.size()));

                if (category == "recyclebin") {
                    SHQUERYRBINFO info{};
                    info.cbSize = sizeof(info);
                    if (SUCCEEDED(SHQueryRecycleBinA(nullptr, &info))) {
                        totalBytes += static_cast<uint64_t>(info.i64Size);
                        totalFiles += static_cast<uint64_t>(info.i64NumItems);
                        std::ostringstream extra;
                        extra << "\"category\":\"recyclebin\",\"bytes\":" << static_cast<uint64_t>(info.i64Size)
                              << ",\"files\":" << static_cast<uint64_t>(info.i64NumItems);
                        EmitProgress("cleaner", baseProgress, "category_scanned", extra.str());
                    }
                    continue;
                }

                if (category == "network") {
                    EmitProgress("cleaner", baseProgress, "network_scan_preview", "\"category\":\"network\"");
                    continue;
                }

                auto paths = CollectCleanerPaths(category, requestJson);
                for (size_t pathIdx = 0; pathIdx < paths.size(); ++pathIdx) {
                    if (!g_running.load()) break;
                    std::error_code ec;
                    if (!fs::exists(paths[pathIdx], ec)) continue;
                    PathStat stat = CollectPathStat(paths[pathIdx]);
                    totalBytes += stat.bytes;
                    totalFiles += stat.files;
                    std::ostringstream extra;
                    extra << "\"category\":\"" << EscapeJson(category) << "\",\"path\":\"" << EscapeJson(paths[pathIdx].string()) << "\""
                          << ",\"bytes\":" << stat.bytes << ",\"files\":" << stat.files;
                    EmitProgress("cleaner", baseProgress + static_cast<int>((pathIdx * 95) / (paths.size() == 0 ? 1 : paths.size())), "path_scanned", extra.str());
                }
            }
            std::ostringstream extra;
            extra << "\"totalBytes\":" << totalBytes << ",\"totalFiles\":" << totalFiles;
            EmitProgress("cleaner", 100, "scan_complete", extra.str());
        } catch (...) {
            EmitProgress("cleaner", 100, "error");
        }
        g_running.store(false);
    }).detach();
    return 0;
}

void __cdecl NO_Stop() {
    g_running.store(false);
}

int __cdecl NO_ExecuteCleaner(const char* requestJson) {
    if (g_running.load()) return 1;
    const std::string request = requestJson ? std::string(requestJson) : std::string("{}");
    const bool dryRun = IsDryRun(request);
    const auto categories = ParseCleanerCategories(request);

    g_running.store(true);
    std::thread([categories, dryRun, request]() {
        uint64_t totalBytes = 0;
        uint64_t totalFiles = 0;
        fs::path backupRoot;
        if (!dryRun) {
            backupRoot = BuildBackupRoot("clean");
        }

        try {
            for (size_t catIdx = 0; catIdx < categories.size(); ++catIdx) {
                if (!g_running.load()) break;
                const std::string& category = categories[catIdx];
                const int baseProgress = static_cast<int>((catIdx * 100) / (categories.size() == 0 ? 1 : categories.size()));

                if (category == "recyclebin") {
                    SHQUERYRBINFO info{};
                    info.cbSize = sizeof(info);
                    if (SUCCEEDED(SHQueryRecycleBinA(nullptr, &info))) {
                        totalBytes += static_cast<uint64_t>(info.i64Size);
                        totalFiles += static_cast<uint64_t>(info.i64NumItems);
                        std::ostringstream extra;
                        extra << "\"category\":\"recyclebin\",\"bytes\":" << static_cast<uint64_t>(info.i64Size)
                              << ",\"files\":" << static_cast<uint64_t>(info.i64NumItems);
                        EmitProgress("cleaner", baseProgress, "recyclebin_scanned", extra.str());
                    }

                    if (!dryRun) {
                        SHEmptyRecycleBinA(nullptr, nullptr, SHERB_NOCONFIRMATION | SHERB_NOPROGRESSUI | SHERB_NOSOUND);
                        EmitProgress("cleaner", baseProgress + 5, "recyclebin_cleaned", "\"category\":\"recyclebin\"");
                    }
                    continue;
                }

                if (category == "network") {
                    if (dryRun) {
                        EmitProgress("cleaner", baseProgress, "network_flushdns_dryrun", "\"category\":\"network\"");
                    } else {
                        std::string output;
                        DWORD exitCode = 1;
                        RunCommand("ipconfig /flushdns", output, exitCode);
                        std::ostringstream extra;
                        extra << "\"category\":\"network\",\"exitCode\":" << exitCode;
                        EmitProgress("cleaner", baseProgress + 5, "network_flushdns", extra.str());
                    }
                    continue;
                }

                auto paths = CollectCleanerPaths(category, request);
                for (size_t pathIdx = 0; pathIdx < paths.size(); ++pathIdx) {
                    if (!g_running.load()) break;
                    const fs::path& path = paths[pathIdx];
                    std::error_code ec;
                    if (!fs::exists(path, ec)) continue;

                    PathStat stat = CollectPathStat(path);
                    totalBytes += stat.bytes;
                    totalFiles += stat.files;

                    std::ostringstream extra;
                    extra << "\"category\":\"" << EscapeJson(category) << "\",\"path\":\"" << EscapeJson(path.string()) << "\""
                          << ",\"bytes\":" << stat.bytes << ",\"files\":" << stat.files;
                    EmitProgress("cleaner", baseProgress + static_cast<int>((pathIdx * 90) / (paths.size() == 0 ? 1 : paths.size())), "path_analyzed", extra.str());

                    if (!dryRun) {
                        BackupPathIfNeeded(path, backupRoot, category, pathIdx);
                        std::error_code removeErr;
                        fs::remove_all(path, removeErr);
                        EmitProgress(
                            "cleaner",
                            baseProgress + static_cast<int>((pathIdx * 90) / (paths.size() == 0 ? 1 : paths.size())) + 5,
                            removeErr ? "path_clean_failed" : "path_cleaned",
                            "\"category\":\"" + EscapeJson(category) + "\",\"path\":\"" + EscapeJson(path.string()) + "\"");
                    }
                }
            }

            std::ostringstream extra;
            extra << "\"totalBytes\":" << totalBytes << ",\"totalFiles\":" << totalFiles;
            EmitProgress("cleaner", 100, dryRun ? "scan_complete" : "execute_complete", extra.str());
        } catch (...) {
            EmitProgress("cleaner", 100, "execute_error");
        }
        g_running.store(false);
    }).detach();
    return 0;
}

int __cdecl NO_StartOptimizer(const char* optionsJson) {
    if (g_running.load()) return 1;
    const std::string options = optionsJson ? std::string(optionsJson) : std::string("{}");
    const auto operations = ParseOptimizerOperations(options);

    g_running.store(true);
    std::thread([operations]() {
        try {
            for (size_t i = 0; i < operations.size(); ++i) {
                if (!g_running.load()) break;
                const std::string& operation = operations[i];
                const int baseProgress = static_cast<int>((i * 100) / (operations.size() == 0 ? 1 : operations.size()));

                EmitProgress("optimizer", baseProgress, "operation_start", "\"operation\":\"" + EscapeJson(operation) + "\"");

                std::string output;
                DWORD exitCode = 1;
                bool launched = ExecuteOptimizerOperation(operation, output, exitCode);

                std::ostringstream extra;
                extra << "\"operation\":\"" << EscapeJson(operation) << "\",\"exitCode\":" << exitCode;
                EmitProgress("optimizer", baseProgress + 5, (launched && exitCode == 0) ? "operation_success" : "operation_failed", extra.str());
            }

            EmitProgress("optimizer", 100, "optimizer_complete");
        } catch (...) {
            EmitProgress("optimizer", 100, "optimizer_error");
        }
        g_running.store(false);
    }).detach();
    return 0;
}

int __cdecl NO_StartSecurity(const char* optionsJson) {
    if (g_running.load()) return 1;
    const std::string options = optionsJson ? std::string(optionsJson) : std::string("{}");
    const auto operations = ParseSecurityOperations(options);

    g_running.store(true);
    std::thread([operations, options]() {
        try {
            for (size_t i = 0; i < operations.size(); ++i) {
                if (!g_running.load()) break;
                const std::string& operation = operations[i];
                const int baseProgress = static_cast<int>((i * 100) / (operations.size() == 0 ? 1 : operations.size()));

                EmitProgress("security", baseProgress, "operation_start", "\"operation\":\"" + EscapeJson(operation) + "\"");

                std::string output;
                DWORD exitCode = 1;
                bool launched = ExecuteSecurityOperation(operation, options, output, exitCode);

                std::ostringstream extra;
                extra << "\"operation\":\"" << EscapeJson(operation) << "\",\"exitCode\":" << exitCode;
                EmitProgress("security", baseProgress + 5, (launched && exitCode == 0) ? "operation_success" : "operation_failed", extra.str());
            }

            EmitProgress("security", 100, "security_complete");
        } catch (...) {
            EmitProgress("security", 100, "security_error");
        }
        g_running.store(false);
    }).detach();

    return 0;
}

int __cdecl NO_StartScheduler(const char* optionsJson) {
    if (g_running.load()) return 1;
    const std::string options = optionsJson ? std::string(optionsJson) : std::string("{}");
    const auto operations = ParseSchedulerOperations(options);

    g_running.store(true);
    std::thread([operations]() {
        try {
            for (size_t i = 0; i < operations.size(); ++i) {
                if (!g_running.load()) break;
                const std::string& operation = operations[i];
                const int baseProgress = static_cast<int>((i * 100) / (operations.size() == 0 ? 1 : operations.size()));

                EmitProgress("scheduler", baseProgress, "operation_start", "\"operation\":\"" + EscapeJson(operation) + "\"");

                std::string output;
                DWORD exitCode = 1;
                bool launched = ExecuteSchedulerOperation(operation, output, exitCode);

                std::ostringstream extra;
                extra << "\"operation\":\"" << EscapeJson(operation) << "\",\"exitCode\":" << exitCode;
                EmitProgress("scheduler", baseProgress + 5, (launched && exitCode == 0) ? "operation_success" : "operation_failed", extra.str());
            }

            EmitProgress("scheduler", 100, "scheduler_complete");
        } catch (...) {
            EmitProgress("scheduler", 100, "scheduler_error");
        }
        g_running.store(false);
    }).detach();

    return 0;
}

int __cdecl NO_StartAppManager(const char* optionsJson) {
    if (g_running.load()) return 1;
    const std::string options = optionsJson ? std::string(optionsJson) : std::string("{}");
    const auto operations = ParseAppManagerOperations(options);

    g_running.store(true);
    std::thread([operations]() {
        try {
            for (size_t i = 0; i < operations.size(); ++i) {
                if (!g_running.load()) break;
                const std::string& operation = operations[i];
                const int baseProgress = static_cast<int>((i * 100) / (operations.size() == 0 ? 1 : operations.size()));

                EmitProgress("appmanager", baseProgress, "operation_start", "\"operation\":\"" + EscapeJson(operation) + "\"");

                uint64_t bytesFreed = 0;
                int itemsAffected = 0;
                std::string output;
                DWORD exitCode = 1;
                bool launched = ExecuteAppManagerOperation(operation, bytesFreed, itemsAffected, output, exitCode);

                std::ostringstream extra;
                extra << "\"operation\":\"" << EscapeJson(operation) << "\",\"exitCode\":" << exitCode
                      << ",\"bytesFreed\":" << bytesFreed << ",\"itemsAffected\":" << itemsAffected;
                EmitProgress("appmanager", baseProgress + 5, (launched && exitCode == 0) ? "operation_success" : "operation_failed", extra.str());
            }

            EmitProgress("appmanager", 100, "appmanager_complete");
        } catch (...) {
            EmitProgress("appmanager", 100, "appmanager_error");
        }
        g_running.store(false);
    }).detach();

    return 0;
}

int __cdecl NO_StartCleanerScan(const char* categoriesJson) {
    return NO_StartScan(categoriesJson);
}

int __cdecl NO_ListInstalledApps(char* outJsonBuf, int outBufSize) {
    if (!outJsonBuf || outBufSize <= 1) return -1;
    std::ostringstream ss;
    ss << "[";
    bool first = true;

    auto readKey = [&](HKEY root, const char* subkey, const char* scope) {
        HKEY hKey;
        if (RegOpenKeyExA(root, subkey, 0, KEY_READ, &hKey) != ERROR_SUCCESS) return;
        DWORD idx = 0;
        char name[256];
        while (true) {
            DWORD nameLen = (DWORD)sizeof(name);
            FILETIME ft;
            LONG r = RegEnumKeyExA(hKey, idx++, name, &nameLen, NULL, NULL, NULL, &ft);
            if (r != ERROR_SUCCESS) break;
            HKEY hSub;
            if (RegOpenKeyExA(hKey, name, 0, KEY_READ, &hSub) != ERROR_SUCCESS) continue;
            std::string displayName;
            std::string publisher;
            std::string uninstallString;
            std::string quietUninstallString;
            ReadRegString(hSub, "DisplayName", displayName);
            ReadRegString(hSub, "Publisher", publisher);
            ReadRegString(hSub, "UninstallString", uninstallString);
            ReadRegString(hSub, "QuietUninstallString", quietUninstallString);
            if (!displayName.empty()) {
                if (!first) ss << ",";
                first = false;
                ss << "{"
                   << "\"id\":\"" << EscapeJson(name) << "\","
                   << "\"name\":\"" << EscapeJson(displayName) << "\","
                   << "\"scope\":\"" << EscapeJson(scope) << "\","
                   << "\"publisher\":\"" << EscapeJson(publisher) << "\","
                   << "\"uninstall\":\"" << EscapeJson(uninstallString) << "\","
                   << "\"quietUninstall\":\"" << EscapeJson(quietUninstallString) << "\""
                   << "}";
            }
            RegCloseKey(hSub);
        }
        RegCloseKey(hKey);
    };

    readKey(HKEY_LOCAL_MACHINE, "SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall", "hklm");
    readKey(HKEY_LOCAL_MACHINE, "SOFTWARE\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall", "hklm_wow64");
    readKey(HKEY_CURRENT_USER, "SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall", "hkcu");

    ss << "]";
    std::string out = ss.str();
    int need = (int)out.size();
    if (need + 1 > outBufSize) return -2;
    std::memcpy(outJsonBuf, out.c_str(), need + 1);
    return need;
}

int __cdecl NO_UninstallApp(const char* appIdJson) {
    if (g_running.load()) return 1;

    std::string request = appIdJson ? std::string(appIdJson) : std::string();
    std::string appId = request;
    if (!request.empty() && request[0] == '{') {
        appId = ExtractJsonString(request, "id");
    }
    appId = SanitizeId(appId);
    if (appId.empty()) return -1;

    g_running.store(true);
    std::thread([appId]() {
        try {
            EmitProgress("appmanager", 5, "uninstall_lookup", "\"id\":\"" + EscapeJson(appId) + "\"");

            std::string uninstallCmd;
            std::string displayName;
            bool found = false;

            found = TryFindUninstallCommand(HKEY_LOCAL_MACHINE, "SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall", appId, uninstallCmd, displayName) || found;
            found = TryFindUninstallCommand(HKEY_LOCAL_MACHINE, "SOFTWARE\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall", appId, uninstallCmd, displayName) || found;
            found = TryFindUninstallCommand(HKEY_CURRENT_USER, "SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall", appId, uninstallCmd, displayName) || found;

            DWORD exitCode = 1;
            std::string output;
            bool launched = false;

            if (found && !uninstallCmd.empty()) {
                std::ostringstream extra;
                extra << "\"id\":\"" << EscapeJson(appId) << "\"";
                if (!displayName.empty()) {
                    extra << ",\"name\":\"" << EscapeJson(displayName) << "\"";
                }
                EmitProgress("appmanager", 30, "uninstall_command_found", extra.str());
                launched = RunCommand(BuildUninstallCommand(uninstallCmd), output, exitCode);
            } else {
                EmitProgress("appmanager", 30, "uninstall_fallback_appx", "\"id\":\"" + EscapeJson(appId) + "\"");
                launched = RunPowerShell("Get-AppxPackage -Name '" + appId + "' | Remove-AppxPackage", output, exitCode);
            }

            std::ostringstream extra;
            extra << "\"id\":\"" << EscapeJson(appId) << "\",\"exitCode\":" << exitCode;
            EmitProgress("appmanager", 100, (launched && exitCode == 0) ? "uninstall_complete" : "uninstall_failed", extra.str());
        } catch (...) {
            EmitProgress("appmanager", 100, "uninstall_error");
        }
        g_running.store(false);
    }).detach();
    return 0;
}

}
