#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Returns a pointer to a null-terminated ANSI string describing engine version.
__declspec(dllexport) const char* __cdecl NO_GetVersion();

// Progress callback: engine will call this with a UTF-8 JSON string describing progress/events.
// Example: "{\"module\":\"cleaner\",\"progress\":45,\"message\":\"Scanning...\"}"
typedef void(__cdecl *NO_ProgressCallback)(const char* utf8JsonProgress);

// Register/unregister a progress callback. Returns 0 on success.
__declspec(dllexport) int __cdecl NO_RegisterProgressCallback(NO_ProgressCallback cb);
__declspec(dllexport) void __cdecl NO_UnregisterProgressCallback();

// Start a scan/analysis. `categoriesJson` is a UTF-8 JSON string describing requested categories (can be "{}" for defaults).
// Returns 0 on success, negative on error, or 1 if already running.
__declspec(dllexport) int __cdecl NO_StartScan(const char* categoriesJson);

// Request stop of current running operation (if any).
__declspec(dllexport) void __cdecl NO_Stop();

// Cleaner-specific API
__declspec(dllexport) int __cdecl NO_StartCleanerScan(const char* categoriesJson);

// Execute cleaning based on request JSON. Request format example:
// {"categories":["chrome","edge","firefox","recyclebin"],"dryRun":true}
// Returns 0 on success, negative on error.
__declspec(dllexport) int __cdecl NO_ExecuteCleaner(const char* requestJson);

// Optimizer-specific API
__declspec(dllexport) int __cdecl NO_StartOptimizer(const char* optionsJson);

// Security API
// Request format example: {"operations":["clamav_quick_scan","realtime_protection_enable"],"targetPath":"C:\\Users\\User\\Downloads"}
__declspec(dllexport) int __cdecl NO_StartSecurity(const char* optionsJson);

// Scheduler API
// Request format example: {"operations":["startup_delay_5min","periodic_30min"]}
__declspec(dllexport) int __cdecl NO_StartScheduler(const char* optionsJson);

// AppManager operation API
// Request format example: {"operations":["bloatware_microsoft","startup_disable_all","app_cache_all"]}
__declspec(dllexport) int __cdecl NO_StartAppManager(const char* optionsJson);

// AppManager-specific API (list apps as JSON, uninstall by id)
// `outJsonBuf` must be a buffer provided by caller of size `outBufSize`; returns number of bytes written (excluding null) or negative on error.
__declspec(dllexport) int __cdecl NO_ListInstalledApps(char* outJsonBuf, int outBufSize);
__declspec(dllexport) int __cdecl NO_UninstallApp(const char* appIdJson);

#ifdef __cplusplus
}
#endif
