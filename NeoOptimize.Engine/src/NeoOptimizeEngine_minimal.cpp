#include "../include/NeoOptimizeEngine.h"
#include <thread>
#include <atomic>
#include <chrono>
#include <string>
#include <mutex>
#include <sstream>
#include <cstring>
#include <vector>
#include <windows.h>

static std::atomic<bool> g_running(false);
static std::string g_version = "NeoOptimize.Engine minimal v0.1";
static NO_ProgressCallback g_progressCb = nullptr;
static std::mutex g_cbMutex;

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
    g_running.store(true);
    std::thread([categoriesJson]() {
        (void)categoriesJson;
        for (int i = 0; i <= 100 && g_running.load(); i += 20) {
            std::this_thread::sleep_for(std::chrono::milliseconds(300));
            std::lock_guard<std::mutex> lk(g_cbMutex);
            if (g_progressCb) {
                std::ostringstream ss;
                ss << "{\"module\":\"scan\",\"progress\":" << i << ",\"message\":\"scanning\"}";
                std::string s = ss.str();
                g_progressCb(s.c_str());
            }
        }
        g_running.store(false);
    }).detach();
    return 0;
}

void __cdecl NO_Stop() {
    g_running.store(false);
}

int __cdecl NO_StartCleanerScan(const char* categoriesJson) {
    return NO_StartScan(categoriesJson);
}

int __cdecl NO_ExecuteCleaner(const char* requestJson) {
    (void)requestJson;
    if (g_running.load()) return 1;
    g_running.store(true);
    std::thread([]() {
        for (int i = 0; i <= 100 && g_running.load(); i += 25) {
            std::this_thread::sleep_for(std::chrono::milliseconds(400));
            std::lock_guard<std::mutex> lk(g_cbMutex);
            if (g_progressCb) {
                std::ostringstream ss;
                ss << "{\"module\":\"cleaner\",\"progress\":" << i << ",\"message\":\"working\"}";
                std::string s = ss.str();
                g_progressCb(s.c_str());
            }
        }
        g_running.store(false);
    }).detach();
    return 0;
}

int __cdecl NO_StartOptimizer(const char* optionsJson) {
    (void)optionsJson;
    return NO_StartScan("{}");
}

int __cdecl NO_ListInstalledApps(char* outJsonBuf, int outBufSize) {
    const char* sample = "[]";
    int len = (int)strlen(sample);
    if (outBufSize <= len) return -1;
    memcpy(outJsonBuf, sample, len+1);
    return len;
}

int __cdecl NO_UninstallApp(const char* appIdJson) {
    (void)appIdJson;
    return 0;
}

}
