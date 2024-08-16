#pragma semicolon 1

#include <sourcemod>
#include <sdktools>

#pragma newdecls required

#define PL_VERSION "1.1.7"

ConVar g_cvDisabled;
ConVar g_cvKickFull;
ConVar g_cvIdleMaxTime;
ConVar g_cvKeepAdmins;

EngineVersion engineVersion;

bool preventTeamBroadcast = false;

bool timerAlive = false;
bool timerRestart = false;

bool isEnabled = true;
bool kickIdleOnFull = true;
bool keepAdmins = true;

int emptySlots = 4;

// In-game CVars give allowed idle time in minutes.
int idleTime = 0;
int tempIdleTime = 0;

// Reset time is given in seconds.
float resetIdleTime = 0.0;

enum 
{
	TeamNone = 0,
	TeamSpec = 1
};

public Plugin myinfo =
{
	name = "Idle Spectators",
	author = "bzdmn",
	description = "Deal with idle spectators",
	version = PL_VERSION,
	url = "https://mge.me/"
};

/**********************/
//	On-Functions
/**********************/

public void OnPluginStart()
{
	HookEvent("player_team", Event_PlayerTeam, EventHookMode_Pre);
}

public void OnConfigsExecuted()
{
	CVar_Set();
	Timer_Start();
}

public void OnClientConnected(int client)
{
	if (isEnabled && kickIdleOnFull)
	{
		if (GetClientCount() == MaxClients)
		{
			timerAlive = false;
		}
	}
}

public void OnClientDisconnect(int client)
{
	if (isEnabled && !timerAlive)
	{
		// Let the server decongest a little before restarting the timer. 
		if (GetClientCount() <= MaxClients - emptySlots)
		{
			timerAlive = true;
		}
	}
}

/******************/
//	ConVars
/******************/

void CVar_Set()
{
	g_cvDisabled = CreateConVar
	(
		"sm_idlespec_disabled", "0",
		"Enable auto-kick for idle spectators", 
		_, 
		true, 0.0, true, 1.0
	);

	g_cvKickFull = CreateConVar
	(
		"sm_idlespec_kick_full", "4", 
		"Enable auto-kicking idle spectators when the server is full. \
		 Setting this to 0 will disable the feature; anything 1 and \
		 above will enable it and set the player congestation variable", 
		_,
		true, 0.0, true, float(MaxClients)
	);

	g_cvKeepAdmins = CreateConVar
	(
		"sm_idlespec_keep_admins", "1",
		"Never kick idle spectators if they are an admin",
		_, 
		true, 0.0, true, 1.0
	);

	CreateConVar
	(
		"sm_idlespec_version", 
		PL_VERSION,
		"sm_idlespec version",
        	FCVAR_SPONLY | FCVAR_CHEAT
	);

	switch (GetEngineVersion())
	{
		case Engine_TF2:
		{
			g_cvIdleMaxTime = FindConVar("mp_idlemaxtime");
			idleTime = g_cvIdleMaxTime.IntValue;
		}
		case Engine_Left4Dead2:
		{
			g_cvIdleMaxTime = FindConVar("sv_spectatoridletime");
			idleTime = g_cvIdleMaxTime.IntValue;
		}
		case Engine_CSS:
		{
			g_cvIdleMaxTime = FindConVar("sv_timeout");
			idleTime = RoundToCeil(float(g_cvIdleMaxTime.IntValue)/60.0);
		}
		default:
		{
			SetFailState("Engine not supported by this plugin.");
		}
	}
	
	resetIdleTime = (idleTime <= 1 ? 1.0 : float(idleTime) - 1.0) * 60.0;

	g_cvDisabled.AddChangeHook(CVar_DisabledChange);
	g_cvKickFull.AddChangeHook(CVar_KickFullChange);
	g_cvIdleMaxTime.AddChangeHook(CVar_IdleMaxTimeChange);
	g_cvKeepAdmins.AddChangeHook(CVar_KeepAdminsChange);
#if defined DEBUG
	PrintToServer("idleTime: %i, resetIdleTime: %f", idleTime, resetIdleTime);
#endif
}

void CVar_IdleMaxTimeChange(ConVar cvar, char[] oldval, char[] newval)
{
	tempIdleTime = engineVersion == Engine_CSS ? 
		RoundToCeil(StringToFloat(newval)/60.0) : StringToInt(newval);
#if defined DEBUG
	PrintToChatAll("IdleMaxTime changed; tempIdleTime: %i", tempIdleTime);
#endif
	// Let the old timer run its course and restart it as a longer timer.
	if (tempIdleTime >= idleTime)
	{
		timerRestart = true;
	}
	// Create a temporary timer to fill-in the gap before our original timer can restart.
	else
	{	
		timerRestart = true;

		// Prevent spectators from getting insta-kicked if they have been idle for
		// longer than the new mp_idlemaxtime period.
		ResetIdleTimeAll();

		// Temporary timer that expires after at most N steps.
		int N = RoundToFloor(float(idleTime)/float(tempIdleTime));
		if (N <= 0) N = 1;

		CreateTimer
		(
			(tempIdleTime <= 1 ? 1.0 : float(tempIdleTime) - 1.0) * 60.0,
			Timer_RepeatNTimes, 
			N
		);
	}
}

void CVar_DisabledChange(ConVar cvar, char[] oldval, char[] newval)
{
	if (StringToInt(newval) == 1)
	{
		timerAlive = false;
		isEnabled = false;
	}
	else
	{
		timerAlive = true;
		isEnabled = true;		
	}
}

void CVar_KickFullChange(ConVar cvar, char[] oldval, char[] newval)
{
	emptySlots = StringToInt(newval);
	kickIdleOnFull = emptySlots > 0 ? true : false;
}

void CVar_KeepAdminsChange(ConVar cvar, char[] oldval, char[] newval)
{
	keepAdmins = StringToInt(newval) == 1 ? true : false;
}

/******************/
//	Events
/******************/

Action Event_PlayerTeam(Event ev, const char[] name, bool dontBroadcast)
{
	if (preventTeamBroadcast)
	{
		SetEventBroadcast(ev, true);
	}
	else
	{
		SetEventBroadcast(ev, dontBroadcast);
	}

	return Plugin_Continue;
}

/***********************/
//	Core Functions
/***********************/

void ResetClientIdleTime(int client)
{
	if (!(timerAlive || (keepAdmins && GetUserFlagBits(client))))
		return;

	float eyeAngles[3];
	float eyePosition[3];

	// Get all properties of the spectator

	int iObsMode = GetEntProp(client, Prop_Send, "m_iObserverMode");
	int hObsTarget = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");

	GetClientEyeAngles(client, eyeAngles);
	GetClientEyePosition(client, eyePosition);

	ChangeClientTeam(client, TeamNone);
	ChangeClientTeam(client, TeamSpec);

	// Reset the previous spectator state

	TeleportEntity(client, eyePosition, eyeAngles, NULL_VECTOR);

	SetEntProp(client, Prop_Send, "m_iObserverMode", iObsMode);
	SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", hObsTarget);

#if defined DEBUG
	PrintToChat(client, "mode: %i, target: %i", iObsMode, hObsTarget);
	PrintToChat(client, "ang: %f %f %f", eyeAngles[0], eyeAngles[1], eyeAngles[2]);
	PrintToChat(client, "pos: %f %f %f", eyePosition[0], eyePosition[1], eyePosition[2]);
#endif
}

void ResetIdleTimeAll()
{
	preventTeamBroadcast = true;

	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client) && GetClientTeam(client) == TeamSpec)
		{
			ResetClientIdleTime(client);
		}
	}

	preventTeamBroadcast = false;
}

/******************/
//	Timers
/******************/

void Timer_Start()
{
	timerAlive = true;
	CreateTimer(resetIdleTime, Timer_ResetIdle,  _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

Action Timer_RepeatNTimes(Handle timer, int N)
{
	if (timerRestart)
	{
		ResetIdleTimeAll();
#if defined DEBUG
		PrintToChatAll("Timer_RepeatNTimes %.0f fired, N = %i", view_as<float>(timer), N);
#endif
		if (N >= 1)
		{
			CreateTimer
			(
				(tempIdleTime <= 1 ? 1.0 : float(tempIdleTime) - 1.0) * 60.0,
				Timer_RepeatNTimes, 
				N - 1
			);
		}
	}

	return Plugin_Stop;
}

Action Timer_ResetIdle(Handle timer)
{
#if defined DEBUG
	PrintToChatAll("Repeating timer %f fired, T = %.2f", timer, GetTickedTime());
#endif
	ResetIdleTimeAll();

	if (timerRestart)
	{
		timerRestart = false;

		idleTime = tempIdleTime;
		resetIdleTime = (idleTime <= 1 ? 1.0 : float(idleTime) - 1.0) * 60.0;

		Timer_Start();

		LogMessage("resetIdleTime changed to %f seconds", resetIdleTime);

		return Plugin_Stop;
	} 

	return Plugin_Continue;
}
