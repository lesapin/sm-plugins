#pragma semicolon 1

#include <sourcemod>
#include <keyvalues>
#include <clientprefs>
#include <SteamWorks>
#include <morecolors>

#pragma newdecls required

#define PL_VERSION "1.1.2"

public Plugin myinfo =
{
    name        = "Announcer",
    author      = "bzdmn",
    description = "Query and announce player information using ETF2L API",
    version     = PL_VERSION,
    url         = "https://mge.me"
};

#define MAX_TEAM_LENGTH 64
#define TIME_COOKIES_CACHED 3.0

bool    g_bTesting      = false;
bool    plDisabled      = false;
char    API_URL[128]    = "http://api.etf2l.org/player/";

// Update player league information once a week
int     updateInterval  = 7 * 24 * 60 * 60;

Handle  g_ckiName;
Handle  g_ckiTeam;
ConVar  g_cvDisabled;

public void OnPluginStart()
{
    g_ckiName = RegClientCookie
    (
        "leagueannouncer_name", 
        "Use your league name in-game instead of Steam name",
        CookieAccess_Private
    );

    g_ckiTeam = RegClientCookie
    (
        "leagueannouncer_team", 
        "Choose which team name to use (6v6/9v9)",
        CookieAccess_Private
    );

    g_cvDisabled = CreateConVar
    (
        "sm_league_announcer_disabled", "0",
        "Disable player information query and announce", 
        _, 
        true, 0.0, true, 1.0
    );

    CreateConVar
    (
        "sm_league_announcer_version", 
        PL_VERSION,
        "League Announcer version",
            FCVAR_SPONLY | FCVAR_CHEAT
    );

    g_cvDisabled.AddChangeHook(CVar_Disabled);

    HookEvent("player_connect_client", OnPlayerConnect, EventHookMode_Pre);

#if defined DEBUG
    g_bTesting = true;
    RegServerCmd("test_announcer", Test_Announcer);
}

public Action Test_Announcer(int args) 
{
    PrintToServer("Test_Announcer");

    int client = 1;
    char url[256];

    strcopy(url, sizeof(url), API_URL);
    StrCat(url, sizeof(url), "STEAM_0:0:38561341");

    Handle hRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, url);

    if 
    (
        !hRequest
        || !SteamWorks_SetHTTPCallbacks(hRequest, SW_HttpResponseCallback)
        || !SteamWorks_SetHTTPRequestHeaderValue(hRequest, "Accept", "text/vdf")
        || !SteamWorks_SetHTTPRequestContextValue(hRequest, client)
        || !SteamWorks_SendHTTPRequest(hRequest)
    )
    {
        PrintToServer("SteamWorks failed to send HTTP request");
        delete hRequest;
    }

    return Plugin_Continue;
}

#else
}
#endif

public Action OnPlayerConnect(Handle ev, const char[] name, bool dontBroadcast)
{
    SetEventBroadcast(ev, true);
    return Plugin_Continue;
}

public void OnClientAuthorized(int client, const char[] auth)
{
    if (!plDisabled && !StrEqual(auth, "BOT"))
    {
        DataPack pack;
        CreateDataTimer(TIME_COOKIES_CACHED, Timer_AreCookiesCached, pack);

        pack.WriteCell(client);
        pack.WriteString(auth);
        pack.Reset();
    }
    else
    {
        AnnouncePlayer(client, "", "");
    }
}

public Action Timer_AreCookiesCached(Handle timer, Handle data)
{
    DataPack pack = view_as<DataPack>(data);

    char url[256];
    char auth[64];

    int client = pack.ReadCell();
    pack.ReadString(auth, sizeof(auth));

    strcopy(url, sizeof(url), API_URL);
    StrCat(url, sizeof(url), auth);

    Handle hRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, url);

    if 
    (
        !hRequest
        || !SteamWorks_SetHTTPCallbacks(hRequest, SW_HttpResponseCallback)
        || !SteamWorks_SetHTTPRequestHeaderValue(hRequest, "Accept", "text/vdf")
        || !SteamWorks_SetHTTPRequestContextValue(hRequest, client)
    )
    {
        LogError("SteamWorks failed to prepare HTTP request");
        CloseHandle(hRequest);
    }

    if (AreClientCookiesCached(client))
    {
        int lastUpdate = GetClientCookieTime(client, g_ckiTeam);

        if (GetTime() - lastUpdate > updateInterval)
        {
            if (!SteamWorks_SendHTTPRequest(hRequest))
            {
                LogError("SteamWorks failed to send HTTP request");
                CloseHandle(hRequest);
            }
        }
        else
        {
            CloseHandle(hRequest);

            char name[MAX_NAME_LENGTH];
            char team[MAX_TEAM_LENGTH];

            GetClientCookie(client, g_ckiName, name, sizeof(name));
            GetClientCookie(client, g_ckiTeam, team, sizeof(team));

            AnnouncePlayer(client, name, team);
        }
    }
    else
    {
        if (!SteamWorks_SendHTTPRequest(hRequest))
        {
            LogError("SteamWorks failed to send HTTP request");
            CloseHandle(hRequest);
        }
    }
    
    return Plugin_Continue;
}

public void SW_HttpResponseCallback(Handle hRequest, bool failure, bool requestSuccess, EHTTPStatusCode code, any data)
{
    if (!failure && requestSuccess && code == k_EHTTPStatusCode200OK)
    {
        SteamWorks_GetHTTPResponseBodyCallback(hRequest, SW_ResponseBody, data);
    }
    else
    {
        /* status code 500 means that the player is not registered on ETF2L */
        if (code != k_EHTTPStatusCode500InternalServerError)
        {
            LogError("HttpResponseCallback Error (code %d)", code);
        }        

        AnnouncePlayer(view_as<int>(data), "", "");
    }

    CloseHandle(hRequest);
}

public void SW_ResponseBody(const char[] response, any value)
{
    int client = view_as<int>(value);
    char team[MAX_TEAM_LENGTH];
    char name[MAX_NAME_LENGTH];

    if (ParsePlayerInformation(name, team, response))
    {
        if (!g_bTesting) 
        {
            SetClientCookie(client, g_ckiName, name);
            SetClientCookie(client, g_ckiTeam, team);
        }
        else
        {
            PrintToServer("name: %s team: %s", name, team);
        }
    }
    else
    {
        LogError("SW_ResponseBody failed to parse response");
    }
    
    AnnouncePlayer(client, name, team);
}

bool ParsePlayerInformation(char[] name, char[] team, const char[] vdf)
{
    if (g_bTesting)
    {
        PrintToServer("response:\n%s", vdf);
    }

    KeyValues kv = CreateKeyValues("response");

    kv.ImportFromString(vdf, "response");
    kv.JumpToKey("player");
    kv.GetString("name", name, MAX_NAME_LENGTH);

    char type[32];

    kv.JumpToKey("teams");
    kv.JumpToKey("0");

    do
    {
#if defined DEBUG
        char section[128];
        kv.GetSectionName(section, sizeof(section));
        PrintToServer("section: %s", section);
#endif
        kv.GetString("name", team, MAX_TEAM_LENGTH);
        kv.GetString("type", type, sizeof(type));
        if (strcmp(type, "6v6") == 0) break;
    }
    while (kv.GotoNextKey());

    CloseHandle(kv);

    return true;
}

void AnnouncePlayer(int client, const char[] name, const char[] team)
{
    if (!IsClientConnected(client))
    {
        return;
    }

    char realname[MAX_NAME_LENGTH];
    GetClientName(client, realname, sizeof(realname));

    if (strlen(name) != 0)
    {
        if (strlen(team) != 0)
        {
            MC_PrintToChatAll("{default}%s ({lightgreen}%s{default}, {lightgreen}%s{default}) \
                has joined the game", realname, name, team);               
        }
        else
        {
            MC_PrintToChatAll("{default}%s ({lightgreen}%s{default}) \
                has joined the game", realname, name);             
        }
    }
    else
    {
        MC_PrintToChatAll("{default}%s has joined the game", realname);
    }
}

void CVar_Disabled(ConVar cvar, char[] oldval, char[] newval)
{
    plDisabled = StringToInt(newval) == 1 ? true : false;
}
