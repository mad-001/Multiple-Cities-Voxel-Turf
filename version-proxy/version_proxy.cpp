// version.dll — minimal proxy
// Loads real System32\version.dll and forwards all version API calls.
// Bridge launcher lives in winmm.dll.

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <string.h>

static HMODULE g_real = NULL;

typedef BOOL  (WINAPI *tGetFileVersionInfoA)    (LPCSTR,DWORD,DWORD,LPVOID);
typedef BOOL  (WINAPI *tGetFileVersionInfoExA)  (DWORD,LPCSTR,DWORD,DWORD,LPVOID);
typedef BOOL  (WINAPI *tGetFileVersionInfoExW)  (DWORD,LPCWSTR,DWORD,DWORD,LPVOID);
typedef DWORD (WINAPI *tGetFileVersionInfoSizeA)(LPCSTR,LPDWORD);
typedef DWORD (WINAPI *tGetFileVersionInfoSizeExA)(DWORD,LPCSTR,LPDWORD);
typedef DWORD (WINAPI *tGetFileVersionInfoSizeExW)(DWORD,LPCWSTR,LPDWORD);
typedef DWORD (WINAPI *tGetFileVersionInfoSizeW)(LPCWSTR,LPDWORD);
typedef BOOL  (WINAPI *tGetFileVersionInfoW)    (LPCWSTR,DWORD,DWORD,LPVOID);
typedef DWORD (WINAPI *tVerFindFileA)  (DWORD,LPSTR,LPSTR,LPSTR,LPSTR,PUINT,LPSTR,PUINT);
typedef DWORD (WINAPI *tVerFindFileW)  (DWORD,LPWSTR,LPWSTR,LPWSTR,LPWSTR,PUINT,LPWSTR,PUINT);
typedef DWORD (WINAPI *tVerInstallFileA)(DWORD,LPSTR,LPSTR,LPSTR,LPSTR,LPSTR,LPSTR,PUINT);
typedef DWORD (WINAPI *tVerInstallFileW)(DWORD,LPWSTR,LPWSTR,LPWSTR,LPWSTR,LPWSTR,LPWSTR,PUINT);
typedef DWORD (WINAPI *tVerLanguageNameA)(DWORD,LPSTR,DWORD);
typedef DWORD (WINAPI *tVerLanguageNameW)(DWORD,LPWSTR,DWORD);
typedef BOOL  (WINAPI *tVerQueryValueA)(LPCVOID,LPCSTR,LPVOID*,PUINT);
typedef BOOL  (WINAPI *tVerQueryValueW)(LPCVOID,LPCWSTR,LPVOID*,PUINT);

static tGetFileVersionInfoA       fp_GetFileVersionInfoA       = NULL;
static tGetFileVersionInfoExA     fp_GetFileVersionInfoExA     = NULL;
static tGetFileVersionInfoExW     fp_GetFileVersionInfoExW     = NULL;
static tGetFileVersionInfoSizeA   fp_GetFileVersionInfoSizeA   = NULL;
static tGetFileVersionInfoSizeExA fp_GetFileVersionInfoSizeExA = NULL;
static tGetFileVersionInfoSizeExW fp_GetFileVersionInfoSizeExW = NULL;
static tGetFileVersionInfoSizeW   fp_GetFileVersionInfoSizeW   = NULL;
static tGetFileVersionInfoW       fp_GetFileVersionInfoW       = NULL;
static tVerFindFileA              fp_VerFindFileA              = NULL;
static tVerFindFileW              fp_VerFindFileW              = NULL;
static tVerInstallFileA           fp_VerInstallFileA           = NULL;
static tVerInstallFileW           fp_VerInstallFileW           = NULL;
static tVerLanguageNameA          fp_VerLanguageNameA          = NULL;
static tVerLanguageNameW          fp_VerLanguageNameW          = NULL;
static tVerQueryValueA            fp_VerQueryValueA            = NULL;
static tVerQueryValueW            fp_VerQueryValueW            = NULL;

BOOL APIENTRY DllMain(HMODULE hModule, DWORD reason, LPVOID) {
    if (reason == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(hModule);

        char sys[MAX_PATH];
        GetSystemDirectoryA(sys, MAX_PATH);
        char realPath[MAX_PATH];
        _snprintf(realPath, sizeof(realPath), "%s\\version.dll", sys);
        g_real = LoadLibraryA(realPath);

        if (g_real) {
#define LOAD(n) fp_##n = (t##n)GetProcAddress(g_real, #n)
            LOAD(GetFileVersionInfoA);   LOAD(GetFileVersionInfoExA);
            LOAD(GetFileVersionInfoExW); LOAD(GetFileVersionInfoSizeA);
            LOAD(GetFileVersionInfoSizeExA); LOAD(GetFileVersionInfoSizeExW);
            LOAD(GetFileVersionInfoSizeW);   LOAD(GetFileVersionInfoW);
            LOAD(VerFindFileA);  LOAD(VerFindFileW);
            LOAD(VerInstallFileA); LOAD(VerInstallFileW);
            LOAD(VerLanguageNameA); LOAD(VerLanguageNameW);
            LOAD(VerQueryValueA); LOAD(VerQueryValueW);
#undef LOAD
        }

    }
    else if (reason == DLL_PROCESS_DETACH) {
        if (g_real) { FreeLibrary(g_real); g_real = NULL; }
    }
    return TRUE;
}

extern "C" {
BOOL  WINAPI GetFileVersionInfoA(LPCSTR a,DWORD b,DWORD c,LPVOID d)              { return fp_GetFileVersionInfoA    ?fp_GetFileVersionInfoA(a,b,c,d):FALSE; }
BOOL  WINAPI GetFileVersionInfoExA(DWORD a,LPCSTR b,DWORD c,DWORD d,LPVOID e)    { return fp_GetFileVersionInfoExA  ?fp_GetFileVersionInfoExA(a,b,c,d,e):FALSE; }
BOOL  WINAPI GetFileVersionInfoExW(DWORD a,LPCWSTR b,DWORD c,DWORD d,LPVOID e)   { return fp_GetFileVersionInfoExW  ?fp_GetFileVersionInfoExW(a,b,c,d,e):FALSE; }
DWORD WINAPI GetFileVersionInfoSizeA(LPCSTR a,LPDWORD b)                          { return fp_GetFileVersionInfoSizeA?fp_GetFileVersionInfoSizeA(a,b):0; }
DWORD WINAPI GetFileVersionInfoSizeExA(DWORD a,LPCSTR b,LPDWORD c)               { return fp_GetFileVersionInfoSizeExA?fp_GetFileVersionInfoSizeExA(a,b,c):0; }
DWORD WINAPI GetFileVersionInfoSizeExW(DWORD a,LPCWSTR b,LPDWORD c)              { return fp_GetFileVersionInfoSizeExW?fp_GetFileVersionInfoSizeExW(a,b,c):0; }
DWORD WINAPI GetFileVersionInfoSizeW(LPCWSTR a,LPDWORD b)                         { return fp_GetFileVersionInfoSizeW?fp_GetFileVersionInfoSizeW(a,b):0; }
BOOL  WINAPI GetFileVersionInfoW(LPCWSTR a,DWORD b,DWORD c,LPVOID d)             { return fp_GetFileVersionInfoW    ?fp_GetFileVersionInfoW(a,b,c,d):FALSE; }
DWORD WINAPI VerFindFileA(DWORD a,LPSTR b,LPSTR c,LPSTR d,LPSTR e,PUINT f,LPSTR g,PUINT h)      { return fp_VerFindFileA?fp_VerFindFileA(a,b,c,d,e,f,g,h):0; }
DWORD WINAPI VerFindFileW(DWORD a,LPWSTR b,LPWSTR c,LPWSTR d,LPWSTR e,PUINT f,LPWSTR g,PUINT h) { return fp_VerFindFileW?fp_VerFindFileW(a,b,c,d,e,f,g,h):0; }
DWORD WINAPI VerInstallFileA(DWORD a,LPSTR b,LPSTR c,LPSTR d,LPSTR e,LPSTR f,LPSTR g,PUINT h)       { return fp_VerInstallFileA?fp_VerInstallFileA(a,b,c,d,e,f,g,h):0; }
DWORD WINAPI VerInstallFileW(DWORD a,LPWSTR b,LPWSTR c,LPWSTR d,LPWSTR e,LPWSTR f,LPWSTR g,PUINT h) { return fp_VerInstallFileW?fp_VerInstallFileW(a,b,c,d,e,f,g,h):0; }
DWORD WINAPI VerLanguageNameA(DWORD a,LPSTR b,DWORD c)   { return fp_VerLanguageNameA?fp_VerLanguageNameA(a,b,c):0; }
DWORD WINAPI VerLanguageNameW(DWORD a,LPWSTR b,DWORD c)  { return fp_VerLanguageNameW?fp_VerLanguageNameW(a,b,c):0; }
BOOL  WINAPI VerQueryValueA(LPCVOID a,LPCSTR b,LPVOID *c,PUINT d)  { return fp_VerQueryValueA?fp_VerQueryValueA(a,b,c,d):FALSE; }
BOOL  WINAPI VerQueryValueW(LPCVOID a,LPCWSTR b,LPVOID *c,PUINT d) { return fp_VerQueryValueW?fp_VerQueryValueW(a,b,c,d):FALSE; }
}
