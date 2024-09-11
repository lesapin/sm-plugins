#pragma semicolon 1

#include <sourcemod>
#include <SteamWorks>

#pragma newdecls required

#define PL_VERSION "1.0.4"

public Plugin myinfo = 
{
    name        = "gameupdater",
    author      = "bzdmn",
    description = "Restart the server when an update is released",
    version     = PL_VERSION,
    url         = "https://mge.me"
};

/*  Check SteamWorks WebAPI for new game updates and
 *  restart the server during the next map change phase. 
 * 
 *  Core functionality is adapted from: 
 *  https://forums.alliedmods.net/showthread.php?p=2331846
 */

enum UpdaterState
{
    Update_NotChecked,
    Update_NotNew,
    Update_New,
};

UpdaterState    g_State         = Update_NotChecked;
int             g_iPatchVersion = 0;
int             g_iAppId        = 0;
bool            g_bTesting      = false;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] err, int err_max)
{
    if (GetEngineVersion() == Engine_TF2)
    {
        g_iAppId = 440;
        return APLRes_Success;
    }

    return APLRes_Failure;
}

public void OnPluginStart() 
{
    if (!FileExists("steam.inf"))
    {
        SetFailState("Can't find steam.inf");
    }
    else
    {
        g_iPatchVersion = ParseSteamInf("steam.inf");
        LogMessage("PatchVersion %d", g_iPatchVersion);
    }

    HookEvent("round_end", OnRoundEnd, EventHookMode_Pre);

#if defined DEBUG
    g_bTesting = true;
    RegServerCmd("test_gameupdater", Test_GameUpdater);
    RegServerCmd("test_gameupdater_old_ver", Test_GameUpdater_Old);
    RegServerCmd("test_timelimit_zero", Test_SetTimelimit);
}

public Action Test_GameUpdater(int args)
{
    ISteamApps_UpToDateCheck();
    return Plugin_Continue;
}

public Action Test_GameUpdater_Old(int args)
{
    g_iPatchVersion = 100;
    ISteamApps_UpToDateCheck();
    return Plugin_Continue;
}

public Action Test_SetTimelimit(int args)
{
    ServerCommand("mp_match_end_at_timelimit 1");
    ServerCommand("mp_timelimit 0");
    return Plugin_Continue;
}

#else
}
#endif

public void OnMapEnd()
{
    if (g_State == Update_NotChecked)
    {
        ISteamApps_UpToDateCheck();
    }
}

public Action OnRoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    int timeLeft;

    if (GetMapTimeLeft(timeLeft) && timeLeft == 0)
    {
        ISteamApps_UpToDateCheck();
    }

    return Plugin_Continue;
}

void ISteamApps_UpToDateCheck()
{
    g_State = Update_NotNew;

    char url[256];

    FormatEx
    (
        url, sizeof(url), 
        "http://api.steampowered.com/ISteamApps/UpToDateCheck/v1/?appid=%d&version=%d&format=xml",
        g_iAppId, g_iPatchVersion
    );

    Handle hRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, url);

    if 
    (
        !hRequest
        || !SteamWorks_SetHTTPCallbacks(hRequest, SW_Callback)
        || !SteamWorks_SendHTTPRequest(hRequest)
    )
    {
        LogError("SteamWorks can't send HTTP request");
        delete hRequest;
    }
}

void SW_Callback(Handle hRequest, bool failure, bool success, EHTTPStatusCode code)
{
    if (!failure && success && code == k_EHTTPStatusCode200OK)
    {
        SteamWorks_GetHTTPResponseBodyCallback(hRequest, SW_ParseResponse);
    }
    else
    {
        LogError("SW_Callback failure: %b success: %b status code: %d", failure, success, code);
    }

    delete hRequest;
}

void SW_ParseResponse(const char[] response)
{
    if (g_bTesting)
    {
        PrintToServer("response:\n%s", response);
    }

    if (StrContains(response, "<required_version>") >= 0)
    {
        g_State = Update_New;

        PrintToChatAll("A new game update has released, RESTARTING SERVER on MapEnd");
        ServerCommand("sv_shutdown");
        /* SystemD is configured to automatically restart the server after shutdown */
    }
}

int ParseSteamInf(const char[] path)
{
    int version = -1;
    
    File file = OpenFile(path, "r");
    if (!file)
    {
        LogError("Can't open %s", path);
        return version;
    }

    char identifier[] = "PatchVersion=";

    while (!file.EndOfFile())
    {
        char line[128];
        if (!file.ReadLine(line, sizeof(line))) 
        {
            break;
        }
        
        if (StrContains(line, identifier))
        {
            version = StringToInt(line[sizeof(identifier)]);        
            break;
        }
    }

    file.Close();
    return version;
}
