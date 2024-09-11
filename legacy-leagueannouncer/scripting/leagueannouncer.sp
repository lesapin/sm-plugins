#pragma semicolon 1

#include <sourcemod>
#include <clientprefs>
#include <SteamWorks>
#include <smjansson>
#include <morecolors>

#pragma newdecls required

#define PL_VERSION "0.9.7"

public Plugin myinfo =
{
    name = "League Announcer",
    author = "bzdmn",
    description = "Query league API for player information",
    version = PL_VERSION,
    url = "https://mge.me"
};

#define MAX_TEAM_LENGTH 64
#define TIME_COOKIES_CACHED 3.0

enum League
{
    ETF2L = 0,
    RGL = 1,
    OZF = 2
};

League targetLeague;

Handle g_ckiName;
Handle g_ckiTeam;

ConVar g_cvDisabled;
ConVar g_cvLeague;

bool plDisabled = false;

// Update player league information once a week
int updateInterval = 7 * 24 * 60 * 60;

#define ETF2L_API "http://api.etf2l.org/player/"
#define RGL_API ""
#define OZF_API ""

char API_URL[256] = ETF2L_API;

public void OnPluginStart()
{
    HookEvent("player_connect_client", Event_PlayerConnect, EventHookMode_Pre);

    // Initialize client cookies

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

    // Initialize ConVars

    g_cvDisabled = CreateConVar
    (
        "sm_league_announcer_disabled", "0",
        "Disable player information query and announce", 
        _, 
        true, 0.0, true, 1.0
    );

    g_cvLeague = CreateConVar
    (
        "sm_league_announcer", "0",
        "Query ETF2L (=0), RGL (=1) or OZF (=2) for player information", 
        _, 
        true, 0.0, true, 2.0
    );

    CreateConVar
    (
        "sm_league_announcer_version", 
        PL_VERSION,
        "League Announcer version",
            FCVAR_SPONLY | FCVAR_CHEAT
    );

    g_cvDisabled.AddChangeHook(CVar_Disabled);
    g_cvLeague.AddChangeHook(CVar_League);
}

public Action Event_PlayerConnect(Handle ev, const char[] name, bool dontBroadcast)
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
        || !SteamWorks_SetHTTPRequestHeaderValue(hRequest, "Accept", "application/json")
        || !SteamWorks_SetHTTPRequestContextValue(hRequest, client)
    )
    {
        LogError("SteamWorks failed to prepare HTTP request");
        delete hRequest;
    }

    if (AreClientCookiesCached(client))
    {
        int lastUpdate = GetClientCookieTime(client, g_ckiTeam);

        if (GetTime() - lastUpdate > updateInterval)
        {
            if (!SteamWorks_SendHTTPRequest(hRequest))
            {
                LogError("SteamWorks failed to send HTTP request");
                delete hRequest;
            }
        }
        else
        {
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
            delete hRequest;
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
        LogError("HttpResponseCallback Error (code %d)", code);
        AnnouncePlayer(view_as<int>(data), "", "");
    }

    delete hRequest;
}

public void SW_ResponseBody(const char[] response, any value)
{
    int client = view_as<int>(value);
    char team[MAX_TEAM_LENGTH];
    char name[MAX_NAME_LENGTH];

    if (ParsePlayerInformation(name, team, response))
    {
        SetClientCookie(client, g_ckiName, name);
        SetClientCookie(client, g_ckiTeam, team);
    }
    else
    {
        LogError("SW_ResponseBody failed to parse response");
    }
    
    AnnouncePlayer(client, name, team);
}

void CVar_Disabled(ConVar cvar, char[] oldval, char[] newval)
{
    plDisabled = StringToInt(newval) == 1 ? true : false;
}

void CVar_League(ConVar cvar, char[] oldval, char[] newval)
{
    targetLeague = view_as<League>(StringToInt(newval));

    switch (targetLeague)
    {
        case ETF2L:
        {
            strcopy(API_URL, sizeof(API_URL), ETF2L_API);
        }
        case RGL:
        {
            strcopy(API_URL, sizeof(API_URL), RGL_API);
        }
        case OZF:
        {
            strcopy(API_URL, sizeof(API_URL), OZF_API);
        }
    }
}

bool ParsePlayerInformation(char[] name, char[] team, const char[] json)
{
    Handle obj = json_load(json);
    Handle iter = json_object_iter(obj);

    char key[32];
    json_object_iter_key(iter, key, sizeof(key));

    if (StrEqual("status", key))
    {
        iter = json_object_iter_next(obj, iter);
        json_object_iter_key(iter, key, sizeof(key));
    }

    if (StrEqual("player", key))
    {
        Handle player = json_object_iter_value(iter);
        Handle player_iter = json_object_iter(player);

        /*
        CloseHandle(iter);
        iter = json_object_iter(player);
        */

        while (player_iter != INVALID_HANDLE)
        {
            json_object_iter_key(player_iter, key, sizeof(key));
            Handle value = json_object_iter_value(player_iter);

            if (StrEqual(key, "name"))
            {
                json_string_value(value, name, MAX_NAME_LENGTH);
            }
            else if (StrEqual(key, "teams"))
            {
                ParseTeam(team, value);
            }
        
            player_iter = json_object_iter_next(player, player_iter);
            delete value;
        }

        delete player;
        delete player_iter;
    }
    else
    {
        delete obj;
        delete iter;
        
        return false;
    }

    delete obj;
    delete iter;
        
    return true;
}

void ParseTeam(char[] team, Handle obj)
{
    char type[32];
    
    for (int elem = 0; elem < json_array_size(obj) && !StrEqual(type, "6v6"); elem++)
    {
        Handle entry = json_array_get(obj, elem);
        Handle iter = json_object_iter(entry);
        
        char key[32];

        while (iter != INVALID_HANDLE)
        {
            json_object_iter_key(iter, key, sizeof(key));
            Handle value = json_object_iter_value(iter);

            if (StrEqual(key, "name"))
            {
                json_string_value(value, team, MAX_TEAM_LENGTH);
            }
            else if (StrEqual(key, "type"))
            {
                json_string_value(value, type, sizeof(type));
            }

            delete value;
            iter = json_object_iter_next(entry, iter);
        }

        delete entry;
        delete iter;
    }
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
