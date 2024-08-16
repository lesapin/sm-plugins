#include <sdkhooks>
#include <dhooks>
#include <morecolors>
#include <tempstats>

#define PLUGIN_VERSION "2.1.1"

public Plugin myinfo = 
{
    name = "Temporary Stats",
    author = "bezdmn",
    description = "Track players game performance over a set period",
    version = PLUGIN_VERSION,
    url = ""
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    CreateNative("TempStats_Start", Native_TempStats_Start);
    CreateNative("TempStats_Stop", Native_TempStats_Stop);
    CreateNative("TempStats_Reset", Native_TempStats_Reset);
    return APLRes_Success;
}

#define GAMEDATA      "tempstats.plugin"

#define WEAPON_FIRED  "CTFWeaponBaseGun::FireProjectile"
#define WEAPON_SWITCH "CTFPlayer::Weapon_Switch"
#define WEAPON_SLOT   "CBaseCombatWeapon::GetSlot"
#define WEAPON_CHANGE "CTFPlayer::GiveNamedItem"
#define WEAPON_INDEX  "CEconItemView::GetItemDefIndex"

#define NUM_SLOTS 3
#define PRINT_LEN 84

Handle g_hWeaponFired,
       g_hWeaponSwitch,
       g_hWeaponSlot,
       g_hWeaponChange,
       g_hWeaponIndex;

// Player weapon stats
int ActiveSlot  [MAXPLAYERS],
    WeaponId    [MAXPLAYERS][NUM_SLOTS],
    Deaths      [MAXPLAYERS],
    Kills       [MAXPLAYERS][NUM_SLOTS],
    ShotsFired  [MAXPLAYERS][NUM_SLOTS],
    Hits        [MAXPLAYERS][NUM_SLOTS],

    StartTime   [MAXPLAYERS],
    StopTime    [MAXPLAYERS];

float Damage    [MAXPLAYERS][NUM_SLOTS],
      DamageTot [MAXPLAYERS];

bool IsTracked  [MAXPLAYERS];

char LineBreak  [PRINT_LEN];

enum
{
    TEAM_NONE = 0,
    TEAM_SPEC,
    TEAM_RED,
    TEAM_BLU
};

public void OnPluginStart()
{
    RegConsoleCmd("tempstats", Command_TempStats);
    RegConsoleCmd("tempstats2", Command_TempStats);
    RegConsoleCmd("tstats", Command_Toggle_TempStats);

    Handle hGameData = LoadGameConfigFile(GAMEDATA);
    if (!hGameData)
        SetFailState("Couldn't load gamedata \"gamedata/%s.txt\"", GAMEDATA);

    /****** WEAPON FIRED ******/
    
    g_hWeaponFired = DHookCreateDetour(Address_Null, CallConv_THISCALL,
                                       ReturnType_CBaseEntity, ThisPointer_Address);
    if (!g_hWeaponFired)
        SetFailState("CreateDetour failed");

    if (!DHookSetFromConf(g_hWeaponFired, hGameData, SDKConf_Signature, WEAPON_FIRED))
        SetFailState("Couldn't load %s signature", WEAPON_FIRED);

    DHookAddParam(g_hWeaponFired, HookParamType_CBaseEntity);

    if (!DHookEnableDetour(g_hWeaponFired, false, Detour_WeaponFired))
        SetFailState("Couldn't detour %s", WEAPON_FIRED);
    else
        LogMessage("%s --> detoured", WEAPON_FIRED);

    /****** WEAPON SWITCH ******/
    
    g_hWeaponSwitch = DHookCreateDetour(Address_Null, CallConv_THISCALL,
                                        ReturnType_Bool, ThisPointer_CBaseEntity);
    if (!g_hWeaponSwitch)
        SetFailState("CreateDetour failed");

    if (!DHookSetFromConf(g_hWeaponSwitch, hGameData, SDKConf_Signature, WEAPON_SWITCH))
        SetFailState("Couldn't load %s signature", WEAPON_SWITCH);

    DHookAddParam(g_hWeaponSwitch, HookParamType_ObjectPtr);
    DHookAddParam(g_hWeaponSwitch, HookParamType_Int);

    if (!DHookEnableDetour(g_hWeaponSwitch, false, Detour_WeaponSwitch))
        SetFailState("Couldn't detour %s", WEAPON_SWITCH);
    else
        LogMessage("%s --> detoured", WEAPON_SWITCH);

    /****** WEAPON CHANGE ******/
    
    g_hWeaponChange = DHookCreateDetour(Address_Null, CallConv_THISCALL,
                                        ReturnType_CBaseEntity, ThisPointer_CBaseEntity);
    if (!g_hWeaponChange)
        SetFailState("CreateDetour failed");

    if (!DHookSetFromConf(g_hWeaponChange, hGameData, SDKConf_Signature, WEAPON_CHANGE))
        SetFailState("Couldn't load %s signature", WEAPON_CHANGE);

    DHookAddParam(g_hWeaponChange, HookParamType_CharPtr);
    DHookAddParam(g_hWeaponChange, HookParamType_Int);
    DHookAddParam(g_hWeaponChange, HookParamType_ObjectPtr);

    if (!DHookEnableDetour(g_hWeaponChange, false, Detour_WeaponChange))
        SetFailState("Couldn't detour %s", WEAPON_CHANGE);
    else
        LogMessage("%s --> detoured", WEAPON_CHANGE);

    /****** SDK Calls ******/
    
    StartPrepSDKCall(SDKCall_Raw);
    PrepSDKCall_SetFromConf(hGameData, SDKConf_Virtual, WEAPON_SLOT);
    PrepSDKCall_SetReturnInfo(SDKType_Bool, SDKPass_Plain);
    g_hWeaponSlot = EndPrepSDKCall();

    StartPrepSDKCall(SDKCall_Raw);
    PrepSDKCall_SetFromConf(hGameData, SDKConf_Signature, WEAPON_INDEX);
    PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
    g_hWeaponIndex = EndPrepSDKCall();

    /****** EVENT HOOKS ******/

    HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
    HookEvent("player_team", Event_PlayerTeam, EventHookMode_Post);
    HookEvent("player_class", Event_PlayerClass, EventHookMode_Post);

    /****** PRETTY PRINTING ******/
    
    for (int i = 0; i < PRINT_LEN; i++)
    {
        LineBreak[i] = '-';
    }

    delete hGameData;
}

public void OnClientPutInServer(int client)
{
    SDKHook(client, SDKHook_OnTakeDamageAlive, OnTakeDamageAlive);
    ResetClientStats(client);
}

public void OnClientDisconnect(int client)
{
    SDKUnhook(client, SDKHook_OnTakeDamageAlive, OnTakeDamageAlive);
}

/****** NATIVES ******/

public int Native_TempStats_Start(Handle plugin, int nParams)
{
    int client = GetNativeCell(1);

    if (client > 0 && client <= MaxClients && IsClientInGame(client))
    {
        ResetClientStats(client);
        StartTime[client] = GetTime();
        IsTracked[client] = true;
    }

    return 0;
}

public int Native_TempStats_Stop(Handle plugin, int nParams)
{
    int client = GetNativeCell(1);

    if (client > 0 && client <= MaxClients && IsClientInGame(client))
    {
        if (IsTracked[client])
        {
            StopTime[client] = GetTime();
            PrettyPrint(client);
            MC_PrintToChat(client, "{green}[TempStats] {default}See console for a summary");
            IsTracked[client] = false;
        }
    }

    return 0;
}

public int Native_TempStats_Reset(Handle plugin, int nParams)
{
    int client = GetNativeCell(1);
    if (client > 0 && client <= MaxClients && IsClientInGame(client))
    {
        ResetClientStats(client);
    }

    return 0;
}

/****** CALLBACKS ******/

public Action OnTakeDamageAlive(int victim, int &attacker, int &inflictor, float &damage, 
                                int &dtype, int &weapon, float damageForce[3], float damagePos[3],
                                int damagecustom)
{
    if (weapon > 0 && victim != attacker)
    {
        // stop stat tracking on 20 or more deaths
        if (Deaths[victim] >= 20 || Deaths[attacker] >= 20)
        {
	    StopTime[attacker] = GetTime();
	    StopTime[victim] = GetTime();

            if (IsTracked[attacker])
            { 
                PrettyPrint(attacker);
                MC_PrintToChat(attacker, "{green}[TempStats] {default}See console for summary");
            } 
            if (IsTracked[victim])
            {
                PrettyPrint(victim);
                MC_PrintToChat(victim, "{green}[TempStats] {default}See console for summary");
            }

            ResetClientStats(attacker);
            ResetClientStats(victim);
        }

        // start stat tracking on first point of damage
        if ((DamageTot[attacker] == 0 || DamageTot[victim] == 0) && 
            (StartTime[attacker] == 0 || StartTime[victim] == 0)
        ) 
        {
            ResetClientStats(attacker);
            ResetClientStats(victim);
            StartTime[attacker] = GetTime();
            StartTime[victim] = GetTime();
        }

        int itemIndex = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");

        for (int i = 0; i < NUM_SLOTS; i++)
        {
            if (WeaponId[attacker][i] == itemIndex)
            {
                Damage[attacker][i] += damage;
                DamageTot[attacker] += damage;
                Hits[attacker][i]++;
            }
        }
    }

    return Plugin_Continue;
}

public MRESReturn Detour_WeaponFired(Address pThis, Handle hRet, Handle hParams)
{
    int client = DHookGetParam(hParams, 1);
    ShotsFired[client][ActiveSlot[client]]++;

    return MRES_Ignored;
}

// Update active weapon
public MRESReturn Detour_WeaponSwitch(int pThis, Handle hRet, Handle hParams)
{
    if (pThis == 0)
        return MRES_Ignored;

    if (IsTracked[pThis])
    {
        Address pWeapon = DHookGetParamAddress(hParams, 1); // CBaseCombatWeapon

        if (pWeapon != Address_Null)
        {
            int slot = SDKCall(g_hWeaponSlot, pWeapon);
            ActiveSlot[pThis] = slot;
        }
    }

    return MRES_Ignored;
}

public MRESReturn Detour_WeaponChange(int pThis, Handle hRet, Handle hParams)
{
    if (IsTracked[pThis])
    {
    Address pEcon = DHookGetParamAddress(hParams, 3);
    int windex = SDKCall(g_hWeaponIndex, pEcon);

    for (int i = 0; i < NUM_SLOTS; i++)
    {
        int weapon_ent = GetPlayerWeaponSlot(pThis, i);
        if (weapon_ent <= 0) 
        {
            ShotsFired[pThis][i] = 0;
            Kills[pThis][i]      = 0;
            Damage[pThis][i]     = 0.0;
            Hits[pThis][i]       = 0;
            WeaponId[pThis][i]   = windex;
        }
    }
    }

    return MRES_Ignored;
}

/*** EVENTS ***/

void Event_PlayerDeath(Event ev, const char[] name, bool dontBroadcast)
{
    int victim = GetClientOfUserId(ev.GetInt("userid"));
    int attacker = GetClientOfUserId(ev.GetInt("attacker"));

    if (victim != attacker)
    {
        int itemIndex = ev.GetInt("weapon_def_index");
        for (int i = 0; i < NUM_SLOTS; i++)
        {
            if (itemIndex == WeaponId[attacker][i])
            {
                Kills[attacker][i]++;
            }
        }
    }

    Deaths[victim]++;

    if (Deaths[victim] >= 20 && victim != attacker && attacker != 0)
    {
	StopTime[attacker] = GetTime();
	StopTime[victim] = GetTime();

        if (IsTracked[attacker])
        { 
            PrettyPrint(attacker);
            MC_PrintToChat(attacker, "{green}[TempStats] {default}See console for summary");
        } 
        if (IsTracked[victim])
        {
            PrettyPrint(victim);
            MC_PrintToChat(victim, "{green}[TempStats] {default}See console for summary");
        }

        ResetClientStats(attacker);
        ResetClientStats(victim);
    }
}

void Event_PlayerClass(Event ev, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(ev.GetInt("userid"));
    Deaths[client]++;
}

void Event_PlayerTeam(Event ev, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(ev.GetInt("userid"));
    if (!client)
        return;

    int team = ev.GetInt("team");

    // mgemod always places the player in spec before spawning in
    // and when removing from an arena
    if (team == TEAM_SPEC)
    { 
        ResetClientStats(client);
    }
}

/****** UTILITY *******/

void PrettyPrint(int client)
{
    float duration = float(StopTime[client] - StartTime[client]) / 60.0;

    char StartTimeStr[16], StopTimeStr[16];
    FormatTime(StartTimeStr, sizeof(StartTimeStr), "%H:%M", StartTime[client]);
    FormatTime(StopTimeStr, sizeof(StopTimeStr), "%H:%M", StopTime[client]);

    PrintToConsole(client, "");
    PrintToConsole(client, "start: %s\tend: %s\tduration: %0.1f minutes", StartTimeStr, StopTimeStr, duration);
    PrintToConsole(client, "");
    PrintToConsole(client, "\t\tKills\tDamage\tHits\tShotsFired\tAccuracy\tDMGPerHit");
    PrintToConsole(client, LineBreak);

    float totaldmg = 0.0;
    int totalkills = 0;

    for (int slot = 0; slot < NUM_SLOTS; slot++)
    {
        if (Damage[client][slot] > 0.0)
        {
            float accuracy = float(Hits[client][slot]) / float(ShotsFired[client][slot]);
            accuracy = accuracy * 100;
            float dmgpershot = Damage[client][slot] / float(Hits[client][slot]);

            totaldmg += Damage[client][slot];
            totalkills += Kills[client][slot];

            char weapon_name[64];
            int weaponInSlot = GetPlayerWeaponSlot(client, slot);

            if (weaponInSlot > 0)
                GetEdictClassname(weaponInSlot, weapon_name, sizeof(weapon_name));

            PrintToConsole(client, "%s", weapon_name[10]);
            PrintToConsole(client, "\t\t%i\t%0.0f\t%i\t%i\t\t%0.0f\t\t%0.0f", 
                Kills[client][slot],
                Damage[client][slot],
                Hits[client][slot], 
                ShotsFired[client][slot],
                accuracy,
                dmgpershot);
            PrintToConsole(client, LineBreak);
        }
    }

    float dmgperlife = totaldmg / float(Deaths[client]+1);
    //float dmgpermin = totaldmg / duration;

    PrintToConsole(client, "");
    PrintToConsole(client, "kills: %i\tdeaths: %i\ttotal damage: %0.0f\tdmg/life: %0.0f", 
                            totalkills, Deaths[client], totaldmg, dmgperlife);
    PrintToConsole(client, "");
}

void ResetClientStats(int client)
{
    for (int slot = 0; slot < NUM_SLOTS; slot++)
    {
        Kills[client][slot]      = 0;
        Damage[client][slot]     = 0.0;
        Hits[client][slot]       = 0;
        ShotsFired[client][slot] = 0;
    }

    DamageTot[client] = 0.0;
    Deaths[client]    = 0;

    StartTime[client] = 0;
    StopTime[client]  = 0;
}

/*** CON COMMANDS ***/

public Action Command_TempStats(int client, int args)
{
    MC_PrintToChat(client, "{green}[TempStats] {default}Ver. %s", PLUGIN_VERSION);
    MC_PrintToChat(client, "{default}   Track stats and summarize your performance");
    MC_PrintToChat(client, "{default}   Usage: {green}/tstats {default} to toggle tracking");
    MC_PrintToChat(client, "{default}   Plugin by: {lightgreen}Robert");
    MC_PrintToChat(client, "{default}   Thanks to {lightgreen}k046 {default}and {lightgreen}chris_kz");

    return Plugin_Handled;
}

public Action Command_Toggle_TempStats(int client, int args)
{
    if (IsTracked[client])
    {
        IsTracked[client] = false;
        MC_PrintToChat(client, "{green}[TempStats] {default}Stat tracking {green}off");
    }
    else
    { 
        IsTracked[client] = true;
        MC_PrintToChat(client, "{green}[TempStats] {default}Stat tracking {green}on");
    } 

    return Plugin_Handled;
}
