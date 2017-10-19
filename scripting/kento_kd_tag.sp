#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <geoip>
#include <kento_csgocolors>
#include <clientprefs>
#include <cstrike>

#pragma newdecls required

int kills[MAXPLAYERS + 1];
int deaths[MAXPLAYERS + 1];

Handle killcookie;
Handle deadcookie;
Handle db = INVALID_HANDLE;

public Plugin myinfo =
{
	name = "[CS:GO] KD Tag",
	author = "Kento",
	version = "1.3",
	description = "Show players KD and country on scoreboard.",
	url = "http://steamcommunity.com/id/kentomatoryoshika/"
};

public void OnPluginStart() 
{
	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("round_end", Event_RoundEnd);
	
	killcookie = RegClientCookie("kdtag_kills", "Kills in server", CookieAccess_Private);
	deadcookie = RegClientCookie("kdtag_deaths", "Deaths in server", CookieAccess_Private);
	
	RegConsoleCmd("sm_kd", Command_KD, "Print your KD");
	RegAdminCmd("sm_resetkd", Command_Reset, ADMFLAG_ROOT, "Reset KD");
	//RegAdminCmd("sm_allkd", Command_All, ADMFLAG_ROOT, "All KD");
	
	LoadTranslations("kento.kdtag.phrases");
	
	for(int i = 1; i <= MaxClients; i++)
	{ 
		if(IsValidClient(i) && !IsFakeClient(i))	OnClientCookiesCached(i);
	}
	
	CreateConVar("sm_kdtag_country", "1", "Show players country?", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	 
	AutoExecConfig();
}

// https://github.com/rogeraabbccdd/auramenu/blob/master/scripting/dominoaura-menu.sp
public void OnMapStart()
{
	char[] error = new char[PLATFORM_MAX_PATH];
	db = SQL_Connect("clientprefs", true, error, PLATFORM_MAX_PATH);
	
	if (!LibraryExists("clientprefs") || db == INVALID_HANDLE)	SetFailState("clientpref error: %s", error);
}

public void OnClientPutInServer(int client)
{
	if (IsValidClient(client))	OnClientCookiesCached(client);
}

public void OnClientCookiesCached(int client)
{
	if(!IsValidClient(client) || IsFakeClient(client))	return;
	
	char scookie[128];
	GetClientCookie(client, killcookie, scookie, sizeof(scookie));
	if(!StrEqual(scookie, ""))
	{
		int icookie = StringToInt(scookie);
		kills[client] = icookie;
	}
	else if(StrEqual(scookie,""))
	{
		kills[client] = 0;
	}
	
	// Get death
	char scookie2[128];
	GetClientCookie(client, deadcookie, scookie2, sizeof(scookie2));
	if(!StrEqual(scookie2, ""))
	{
		int icookie2 = StringToInt(scookie2);
		deaths[client] = icookie2;
	}
	else if(StrEqual(scookie2,""))
	{
		deaths[client] = 0;
	}
	
	UpdateTags(client);
}

public void OnClientDisconnect(int client)
{
	if(IsValidClient(client) && !IsFakeClient(client))
	{
		SetCookies(client);
	}
}

public Action Event_RoundEnd(Handle event, const char[] name, bool dontBroadcast)
{
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsValidClient(i) && !IsFakeClient(i))
		{
			SetCookies(i);
		}
	}
}
	
public Action Event_PlayerDeath(Handle event, const char[] name, bool dontBroadcast)
{
	int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	
	// kill
	if (IsValidClient(attacker))	
	{
		// prevent suicide
		if(attacker != client && attacker != 0)
		{
			// player kill player
			if(!IsFakeClient(attacker) && !IsFakeClient(client))
			{
				kills[attacker]++;
			}
		}
		
		// Tag
		UpdateTags(attacker);
	}
	
	// dead
	if (IsValidClient(client))
	{
		// player kill player
		if(!IsFakeClient(attacker) && !IsFakeClient(client))
		{
			deaths[client]++;
		}
		
		// Tag
		UpdateTags(client);
	}
}

public Action Command_KD (int client, int args)
{
	if(IsValidClient(client))
	{
		float kill = IntToFloat(kills[client]);
		int dead = deaths[client];
		if (deaths[client] == 0)	dead = 1;
		CPrintToChat(client, "%T", "CMD KD", client, kills[client], deaths[client], kill / dead);
	}
}

/*
public Action Command_All (int client, int args)
{
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsValidClient(i) && !IsFakeClient(i))
		{
			float kill = IntToFloat(kills[i]);
			int dead = deaths[i];
			if (deaths[i] == 0)	dead = 1;
			PrintToChat(client, "%N - %d kills, %d deaths, kd %.2f", i, kills[i], deaths[i], kill / dead);
		}
	}	
}
*/

public Action Command_Reset (int client, int args)
{
	if(IsValidClient(client))
	{
		// Delete database
		// https://github.com/rogeraabbccdd/auramenu/blob/master/scripting/dominoaura-menu.sp#L215
		char[] query = new char[512];
		FormatEx(query, 512, "DELETE FROM sm_cookie_cache WHERE EXISTS( SELECT * FROM sm_cookies WHERE sm_cookie_cache.cookie_id = sm_cookies.id AND sm_cookies.name = 'kdtag_kills');");
		SQL_TQuery(db, ClientPref_PurgeCallback, query);
		
		char[] query2 = new char[512];
		FormatEx(query2, 512, "DELETE FROM sm_cookie_cache WHERE EXISTS( SELECT * FROM sm_cookies WHERE sm_cookie_cache.cookie_id = sm_cookies.id AND sm_cookies.name = 'kdtag_deaths');");
		SQL_TQuery(db, ClientPref_PurgeCallback, query2);
		
		// Reset player in server kd
		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsValidClient(i) && !IsFakeClient(i))
			{
				deaths[i] = 0;
				kills[i] = 0;
				UpdateTags(client);
			}
		}
	}
}

public void ClientPref_PurgeCallback(Handle owner, Handle handle, const char[] error, any data)
{
	if (SQL_GetAffectedRows(owner))
	{
		LogMessage("KD has been reset.");
	}
}

public void OnMapEnd()
{
	CloseHandle(db);
}

void UpdateTags(int client)
{
	// Get kd
	float kill = IntToFloat(kills[client]);
	int dead = deaths[client];
	if (dead == 0)	dead = 1;
	
	// Set client tag
	if(GetConVarBool(FindConVar("sm_kdtag_country")))
	{
		char country[3];
		char ip[14];
		GetClientIP(client, ip, sizeof(ip)); 
		if (!GeoipCode2(ip, country))	country = "??";
		
		char clienttag[128];
		Format(clienttag, sizeof(clienttag), "[%.2f | %s]", kill / dead, country);
		CS_SetClientClanTag(client, clienttag);
	}
	else
	{
		char clienttag[128];
		Format(clienttag, sizeof(clienttag), "[%.2f]", kill / dead);
		CS_SetClientClanTag(client, clienttag);
	}
}

void SetCookies(int client)
{
	char killvalue[128];
	IntToString(kills[client], killvalue, sizeof(killvalue));
	SetClientCookie(client, killcookie, killvalue);
			
	char deadvalue[128];
	IntToString(deaths[client], deadvalue, sizeof(deadvalue));
	SetClientCookie(client, deadcookie, deadvalue);
}

stock bool IsValidClient(int client)
{
	if (client <= 0) return false;
	if (client > MaxClients) return false;
	if (!IsClientConnected(client)) return false;
	return IsClientInGame(client);
}

public float IntToFloat(int integer)
{
	char s[300];
	IntToString(integer,s,sizeof(s));
	return StringToFloat(s);
}