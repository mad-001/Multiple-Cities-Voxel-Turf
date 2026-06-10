// takaro.dll — VoxelTurf Takaro bridge launcher
// Loaded by version.dll when the game starts.
// Spawns mods\TakaroConnector\bridge\bridge.js with the game PID as argv[1].
// The bridge monitors that PID and exits the moment the game process dies.

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <string.h>

static HANDLE g_bridgeProc = NULL;

static DWORD WINAPI LaunchBridgeThread(LPVOID) {
    char gameDir[MAX_PATH];
    GetModuleFileNameA(NULL, gameDir, MAX_PATH);
    char *sl = strrchr(gameDir, '\\');
    if (sl) *sl = '\0';

    char bridge[MAX_PATH * 2];
    _snprintf(bridge, sizeof(bridge),
              "%s\\mods\\TakaroConnector\\bridge\\bridge.js", gameDir);

    if (GetFileAttributesA(bridge) == INVALID_FILE_ATTRIBUTES)
        return 0;

    // Pass our PID so the bridge can monitor us and exit when we do
    char cmd[MAX_PATH * 2 + 32];
    _snprintf(cmd, sizeof(cmd), "node \"%s\" %lu", bridge, GetCurrentProcessId());

    STARTUPINFOA si;
    ZeroMemory(&si, sizeof(si));
    si.cb = sizeof(si);
    PROCESS_INFORMATION pi;
    ZeroMemory(&pi, sizeof(pi));

    if (CreateProcessA(NULL, cmd,
                       NULL, NULL, FALSE,
                       CREATE_NO_WINDOW | DETACHED_PROCESS,
                       NULL, gameDir,
                       &si, &pi)) {
        g_bridgeProc = pi.hProcess;
        CloseHandle(pi.hThread);
    }
    return 0;
}

BOOL APIENTRY DllMain(HMODULE hModule, DWORD reason, LPVOID) {
    if (reason == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(hModule);
        HANDLE t = CreateThread(NULL, 0, LaunchBridgeThread, NULL, 0, NULL);
        if (t) CloseHandle(t);
    }
    else if (reason == DLL_PROCESS_DETACH) {
        if (g_bridgeProc) {
            TerminateProcess(g_bridgeProc, 0);
            CloseHandle(g_bridgeProc);
            g_bridgeProc = NULL;
        }
    }
    return TRUE;
}
