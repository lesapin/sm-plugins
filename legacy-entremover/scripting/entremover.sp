#include <dhooks>

#define PLUGIN_VERSION "1.2.0"

public Plugin myinfo = 
{
    name = "Entity Remover",
    author = "bezdmn",
    description = "Clean up orphaned entities such as projectiles after their owner dies",
    version = PLUGIN_VERSION,
    url = "https://forums.alliedmods.net/showthread.php?t=344992"
};

#define GAMEDATA        "entremover.plugin"
#define REMOVE_ALL_ENTS "CTFPlayer::RemoveAllOwnedEntitiesFromWorld"
#define DEATH_SOUND     "CTFPlayer::DeathSound"

Handle  g_hGameData,
        g_hRemoveAllEnts,
        g_hPlayerKilled;

public void OnPluginStart()
{
    g_hGameData = LoadGameConfigFile(GAMEDATA);
    if (!g_hGameData)
        SetFailState("Couldn't load \"gamedata/%s.txt\"", GAMEDATA);

    g_hPlayerKilled = DHookCreateDetour(Address_Null, CallConv_THISCALL, 
                                        ReturnType_Void, ThisPointer_Address);

    if (!g_hPlayerKilled)
        SetFailState("Couldn't setup detour for %s", DEATH_SOUND);

    if (!DHookSetFromConf(g_hPlayerKilled, g_hGameData, SDKConf_Signature, DEATH_SOUND))
        SetFailState("Couldn't load signature for %s", DEATH_SOUND);

    DHookAddParam(g_hPlayerKilled, HookParamType_ObjectPtr);

    if (!DHookEnableDetour(g_hPlayerKilled, false, Detour_DeathSound))
        SetFailState("Couldn't detour %s", DEATH_SOUND);
    else
        LogMessage("%s --> detoured", DEATH_SOUND);

    StartPrepSDKCall(SDKCall_Raw);
    PrepSDKCall_SetFromConf(g_hGameData, SDKConf_Signature, REMOVE_ALL_ENTS);
    PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_Plain);
    g_hRemoveAllEnts = EndPrepSDKCall();
}

public MRESReturn Detour_DeathSound(Address pThis, Handle hParams)
{
    SDKCall(g_hRemoveAllEnts, pThis, false);
    return MRES_Ignored;
}
