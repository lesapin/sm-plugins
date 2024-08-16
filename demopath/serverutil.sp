#pragma semicolon 1

#include <sourcemod>

#pragma newdecls required

#define PL_VERSION "0.5.1"

public Plugin myinfo =
{
	name = "ServerUtil",
	author = "bzdmn",
	description = "Utility plugin for mge.me servers",
	version = PL_VERSION,
	url = "https://mge.me"
}

public void OnPluginStart()
{
	HookEvent("tf_game_over", Event_GameOver);
	HookEvent("teamplay_game_over", Event_GameOver);

	AddCommandListener(Who_Callback, "who");
}

public void Event_GameOver(Event ev, const char[] name, bool dontBroadcast)
{
	CreateTimer(2.0, Timer_PrintSTV);
}

Action Timer_PrintSTV(Handle timer)
{
	char urlstart[64];
	char urlend[64];
	char urlfull[258];

	GetConVarString(FindConVar("recordstv_path"), urlstart, sizeof(urlstart));
	GetConVarString(FindConVar("recordstv_filename"), urlend, sizeof(urlend));

	// Assuming recordstv_path begins with "/var/www/mgeme/stv/..."
	Format(urlfull, sizeof(urlfull), "https://mge.me/%s/%s", urlstart[15], urlend);

	PrintToConsoleAll("Download SourceTV replay at: %s", urlfull);

	return Plugin_Continue;
}

Action Who_Callback(int client, const char[] cmd, int argc)
{
	ReplyToCommand(client, "steamcommunity.com/id/bzdmn\nhttps://mge.me");

	return Plugin_Continue;
}
