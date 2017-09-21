#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <geoip>
#include <kento_csgocolors>
#include <clientprefs>
#include <cstrike>

#pragma newdecls required

int killstreaks[MAXPLAYERS + 1];
int kills[MAXPLAYERS + 1];
int deaths[MAXPLAYERS + 1];

Handle killcookie;
Handle deadcookie;
Handle db = INVALID_HANDLE;

public Plugin myinfo =
{
	name = "[CS:GO] KD Tag",
	author = "Kento",
	version = "1.1",
	description = "Show players KD and country on scoreboard.",
	url = "http://steamcommunity.com/id/kentomatoryoshika/"
};

public void OnPluginStart() 
{
	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("round_end", Event_RoundEnd);
	
	killcookie = RegClientCookie("kdtag_kills", "Kills in dm server", CookieAccess_Private);
	deadcookie = RegClientCookie("kdtag_deaths", "Deaths in dm server", CookieAccess_Private);
	
	RegConsoleCmd("sm_kd", Command_KD, "Print your KD");
	RegAdminCmd("sm_resetkd", Command_Reset, ADMFLAG_ROOT, "Reset KD");
	
	LoadTranslations("kento.kdtag.phrases");
	
	for(int i = 1; i <= MaxClients; i++)
	{ 
		if(IsValidClient(i))	OnClientCookiesCached(i);
	}
}

// https://github.com/rogeraabbccdd/auramenu/blob/master/scripting/dominoaura-menu.sp
public void OnMapStart()
{
	char[] error = new char[PLATFORM_MAX_PATH];
	db = SQL_Connect("clientprefs", true, error, PLATFORM_MAX_PATH);
	
	if (!LibraryExists("clientprefs") || db == INVALID_HANDLE)
		SetFailState("clientpref error: %s", error);
}

public void OnClientPutInServer(int client)
{
	if (IsValidClient(client))	OnClientCookiesCached(client);
}

public void OnClientCookiesCached(int client)
{
	if(!IsValidClient(client))
		return;
	
	// Not bot
	if(!IsFakeClient(client))
	{
		// Get kill
		char scookie[8];
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
		char scookie2[8];
		GetClientCookie(client, deadcookie, scookie2, sizeof(scookie2));
		if(!StrEqual(scookie2, ""))
		{
			int icookie2 = StringToInt(scookie2);
			kills[client] = icookie2;
		}
		else if(StrEqual(scookie2,""))
		{
			deaths[client] = 0;
		}
	}
	
	// Bot only count kd in this map.
	else if(IsFakeClient(client))
	{
		kills[client] = 0;
		deaths[client] = 0;
	}
	
	CreateTimer(3.0, SetTags, client, TIMER_FLAG_NO_MAPCHANGE);
}

public Action SetTags(Handle tmr, int client)
{
	// prevent player disconnect in 3 sec
	if(IsValidClient(client))	UpdateTags(client);
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
			killstreaks[attacker]++;
			
			// player kill player
			if(!IsFakeClient(attacker) && !IsFakeClient(client))
			{
				kills[attacker]++;
			}
			
			/* player kill bot
			else if(!IsFakeClient(attacker) && IsFakeClient(client))
			{
				// do nothing
			}
			*/
			
			// bot kill bot
			else if(IsFakeClient(attacker) && IsFakeClient(client))
			{
				kills[attacker]++;
			}
			
			// bot kill player
			else if(IsFakeClient(attacker) && !IsFakeClient(client))
			{
				kills[attacker]++;
			}
		}
		
		//PrintToChat(attacker, "kills %d, streak %d", kills[attacker], killstreaks[attacker]);
		
		// Tag
		UpdateTags(attacker);
		
		// Announce
		if(killstreaks[attacker] == 5 || killstreaks[attacker] == 10 || killstreaks[attacker] == 15 || killstreaks[attacker] == 20)
		{
			for(int i = 1; i <= MaxClients; i++)
			{
				if(IsValidClient(i) && !IsFakeClient(i))	CPrintToChat(i, "%T", "Kill streak", i, attacker, killstreaks[attacker]);
			}
		}
	}
	
	// dead
	if (IsValidClient(client))
	{
		if (killstreaks[client] > 5)
		{
			CPrintToChat(client, "%t", "Kill streak break");
			PrintHintText(client, "%t", "Kill streak break hint");
		}
		
		// Rest killstrak when player dead.
		killstreaks[client] = 0;
		
		// player kill player
		if(!IsFakeClient(attacker) && !IsFakeClient(client))
		{
			deaths[client]++;
		}
		
		// player kill bot
		else if(!IsFakeClient(attacker) && IsFakeClient(client))
		{
			deaths[client]++;
		}
		
		// bot kill bot
		else if(IsFakeClient(attacker) && IsFakeClient(client))
		{
			deaths[client]++;
		}
		
		/* bot kill player
		else if(IsFakeClient(attacker) && !IsFakeClient(client))
		{
			// do nothing
		}
		*/
		
		//PrintToChat(client, "dead %d", deaths[client]);
		
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
			if(IsValidClient(i))
			{
				deaths[i] = 0;
				kills[i] = 0;
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
	if (deaths[client] == 0)	dead = 1;
	
	// Get country
	char country[3];
	char ip[14];
	GetClientIP(client, ip, sizeof(ip)); 
	if (!GeoipCode2(ip, country))
	{
		country = "??";
	}
	
	// Set client tag
	char clienttag[128];
	Format(clienttag, sizeof(clienttag), "[%.2f | %s]", kill / dead, country);
	CS_SetClientClanTag(client, clienttag);
}

void SetCookies(int client)
{
	char killscookie[128];
	IntToString(kills[client], killscookie, sizeof(killscookie));
	SetClientCookie(client, killcookie, killscookie);
			
	char deadscookie[128];
	IntToString(deaths[client], deadscookie, sizeof(deadscookie));
	SetClientCookie(client, deadcookie, deadscookie);
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