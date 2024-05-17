#include <tf2_stocks>
#include <sdkhooks>

#pragma newdecls required
#pragma semicolon 1


#define PLUGIN_VERSION "0.0.1"

#define ERROR_UNEXPECTED "[Spy Duel] An unexpected error occoured!"
#define ERROR_PLAYER_NOT_FOUND "[Spy Duel] Unable to find player!"
#define ERROR_WAITING_FOR_RESPONSE "[Spy Duel] You already challenged a player and need to wait for a response. To cancel type !spyduelexit"
#define ERROR_NOT_DUELING "[Spy Duel] You are not dueling anyone!"
#define ERROR_CHANGE_CLASS_IN_DUEL "[Spy Duel] You cannot change class during a spy duel! To cancel type !spyduelexit"
#define ERROR_NO_PLAYER_FOUND "[Spy Duel] No suitable players found!"
#define ERROR_CHALLENGER_CANCELLED "[Spy Duel] You challenger has cancelled the duel before you accepted it!"

#define NOTIFY_IN_DUEL_DAMAGE "[Spy Duel] You cannot attack this player as they are in a spy duel!"
#define NOTIFY_IN_DUEL_DAMAGE_NOT_PARTNER "[Spy Duel] You cannot attack this player as they are not your duel partner!"

#define EVENT_DUEL_END_PARTNER "[Spy Duel] Duel ended because your partner has exited the duel!"
#define EVENT_DUEL_END "[Spy Duel] Successfully exited Duel!"
#define EVENT_DUEL_CHALLENGER_CANCELLED "[Spy Duel] Successfully cancelled the duel request!"

#define SOUND_DUEL_CHALLENGE "ui/duel_challenge_with_restriction.wav"
#define SOUND_DUEL_CHALLENGE_ACCEPT "ui/duel_challenge_accepted_with_restriction.wav"
#define SOUND_DUEL_CHALLENGE_REJECT "ui/duel_challenge_rejected_with_restriction.wav"
#define SOUND_DUEL_EVENT "ui/duel_event.wav"

public Plugin myinfo =
{
	name = "[TF2] Spy Knife Duel",
	author = "kingo",
	description = "Duel against another player that only allows backstabs",
	version = PLUGIN_VERSION,
	url = "https://github.com/kingofings/spy_duel"
};

enum struct PlayerData
{
	int duelPartner;
	int butterKnife;
	int backstabs;
	bool isAwaitingResponse;

	void Clear()
	{
		this.duelPartner = 0;
		this.isAwaitingResponse = false;
		this.butterKnife = 0;
		this.backstabs = 0;
	}
}

PlayerData g_PlayerData[MAXPLAYERS + 1];

public void OnPluginStart()
{
	HookEvent("teamplay_round_win", Event_RoundEndPost, EventHookMode_Post);
	HookEvent("teamplay_round_stalemate", Event_RoundEndPost, EventHookMode_Post);
	RegConsoleCmd("sm_spyduel", Command_SpyDuel);
	RegConsoleCmd("sm_spyduelexit", Command_SpyDuelExit);
	AddCommandListener(Command_JoinClass, "joinclass");
	AddCommandListener(Command_JoinClass, "join_class");

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))OnClientPutInServer(i);
	}
}

public void OnClientPutInServer(int client)
{
	g_PlayerData[client].Clear();
	SDKHook(client, SDKHook_OnTakeDamageAlive, OnTakeDamageAlive);
}

public void OnMapStart()
{
	PrecacheSound(SOUND_DUEL_CHALLENGE);
	PrecacheSound(SOUND_DUEL_CHALLENGE_ACCEPT);
	PrecacheSound(SOUND_DUEL_CHALLENGE_REJECT);
	PrecacheSound(SOUND_DUEL_EVENT);
}

public void OnClientDisconnect(int client)
{
	EndSpyDuel(client);
}

void Event_RoundEndPost(Event event, const char[] name, bool dontBroadcast)
{
	EndAllDuels();
}

Action OnTakeDamageAlive(int victim, int &attacker, int &inflictor, float &damage, int &damageType, int &weapon, float damageForce[3], float damagePosition[3], int damageCustom)
{
	if (attacker < 1 || attacker > MaxClients || victim < 1 || victim > MaxClients)return Plugin_Continue;
	if (g_PlayerData[victim].duelPartner == GetClientUserId(attacker))
	{
		if (damageCustom == TF_CUSTOM_BACKSTAB)
		{
			g_PlayerData[attacker].backstabs++;
			return Plugin_Continue;
		}

		SetEntProp(victim, Prop_Send, "m_iHealth", GetEntProp(victim, Prop_Send, "m_iHealth") + RoundToNearest(damage));
		if (!(damageType & DMG_BULLET))g_PlayerData[attacker].butterKnife++;
	}

	if (g_PlayerData[attacker].duelPartner == 0 && g_PlayerData[victim].duelPartner != 0)
	{
		PrintCenterText(attacker, NOTIFY_IN_DUEL_DAMAGE);
		damage = 0.0;
		return Plugin_Changed;
	}

	if (g_PlayerData[victim].duelPartner == 0 && g_PlayerData[attacker].duelPartner != 0)
	{
		PrintCenterText(attacker, NOTIFY_IN_DUEL_DAMAGE_NOT_PARTNER);
		damage = 0.0;
		return Plugin_Changed;
	}

	return Plugin_Continue;
}

Action Command_SpyDuel(int client, int args)
{
	if (g_PlayerData[client].isAwaitingResponse)
	{
		ReplyToCommand(client, ERROR_WAITING_FOR_RESPONSE);
		return Plugin_Handled;
	}

	Menu menu = new Menu(Menu_DuelPartner);

	menu.SetTitle("Select your opponent");

	TFTeam clientTeam = TF2_GetClientTeam(client);
	char nameBuffer[MAX_NAME_LENGTH];
	char infoBuffer[8];

	int count = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))continue;
		TFTeam iTeam = TF2_GetClientTeam(i);
		if (iTeam == clientTeam || iTeam == TFTeam_Spectator || iTeam == TFTeam_Unassigned)continue;

		GetClientName(i, nameBuffer, sizeof(nameBuffer));
		FormatEx(infoBuffer, sizeof(infoBuffer), "%d", GetClientUserId(i));
		menu.AddItem(infoBuffer, nameBuffer);
		count++;
	}

	if (count == 0)
	{
		ReplyToCommand(client, ERROR_NO_PLAYER_FOUND);
		return Plugin_Handled;
	}
	menu.Display(client, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

Action Command_SpyDuelExit(int client, int args)
{
	if (g_PlayerData[client].duelPartner == 0)
	{
		if (g_PlayerData[client].isAwaitingResponse)
		{
			g_PlayerData[client].Clear();
			ReplyToCommand(client, EVENT_DUEL_CHALLENGER_CANCELLED);
			return Plugin_Handled;
		}
		ReplyToCommand(client, ERROR_NOT_DUELING);
		return Plugin_Handled;
	}

	EndSpyDuel(client);
	return Plugin_Handled;
}

Action Command_JoinClass(int client, const char[] command, int argc)
{
	if (g_PlayerData[client].duelPartner != 0)
	{
		PrintCenterText(client, ERROR_CHANGE_CLASS_IN_DUEL);
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

int Menu_DuelPartner(Menu menu, MenuAction action, int client, int item)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char itemString[8];
			menu.GetItem(item, itemString, sizeof(itemString));

			int userId = StringToInt(itemString);

			if (userId <= 0)
			{
				PrintToChat(client, ERROR_UNEXPECTED);
				return -1;
			}

			int player = GetClientOfUserId(userId);
			if (player <= 0)
			{
				PrintToChat(client, ERROR_PLAYER_NOT_FOUND);
				return -1;
			}

			AskPlayerForDuel(client, player);
		}

		case MenuAction_End:
		{
			delete menu;
		}
	}

	return 0;
}


int Menu_AskPlayerForDuel(Menu menu, MenuAction action, int client, int item)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char playerIndexstring[8];
			menu.GetItem(item, playerIndexstring, sizeof(playerIndexstring));
			int player = StringToInt(playerIndexstring);

			if (item == 0)
			{
				if (g_PlayerData[player].isAwaitingResponse)
				{
					PrintToChat(client, ERROR_CHALLENGER_CANCELLED);
					g_PlayerData[client].Clear();

					return -1;
				}
				PlayDuelSound(client, player, SOUND_DUEL_CHALLENGE_ACCEPT);
				g_PlayerData[client].Clear();
				g_PlayerData[client].duelPartner = GetClientUserId(player);
				g_PlayerData[player].Clear();
				g_PlayerData[player].duelPartner = GetClientUserId(client);
				PrintToChatAll("%N has accepted %N's Spy Duel", client, player);

				SDKHooks_TakeDamage(client, client, client, 100000.0, DMG_GENERIC, client, NULL_VECTOR, NULL_VECTOR, true);
				TF2_SetPlayerClass(client, TFClass_Spy, true);
				SDKHooks_TakeDamage(player, player, player, 100000.0, DMG_GENERIC, player, NULL_VECTOR, NULL_VECTOR, true);
				TF2_SetPlayerClass(player, TFClass_Spy, true);
			}
			else
			{
				PlayDuelSound(client, player, SOUND_DUEL_CHALLENGE_REJECT);
				PrintToChatAll("%N has rejected %N's Spy Duel", client, player);
				g_PlayerData[client].Clear();
				g_PlayerData[client].Clear();
			}
		}

		case MenuAction_End:
		{
			delete menu;
		}
	}


	return 0;
}

void AskPlayerForDuel(int client, int player)
{
	g_PlayerData[client].isAwaitingResponse = true;
	g_PlayerData[player].isAwaitingResponse = true;
	Menu menu = new Menu(Menu_AskPlayerForDuel);

	char initiatorName[MAX_NAME_LENGTH];
	char initiatorIndex[8];
	GetClientName(client, initiatorName, sizeof(initiatorName));
	IntToString(client, initiatorIndex, sizeof(initiatorIndex));

	menu.SetTitle("%N wants to Spy duel you!", client);
	menu.AddItem(initiatorIndex, "Accept Duel");
	menu.AddItem("decline", "Decline Duel");

	menu.ExitButton = false;
	menu.Display(player, MENU_TIME_FOREVER);

	PlayDuelSound(client, player, SOUND_DUEL_CHALLENGE);
	PrintToChatAll("%N has challenged %N to a spy duel!", client, player);
}

void PlayDuelSound(int player1, int player2, char[] sound)
{
	if (player1 > 0 && player1 <= MaxClients && IsClientInGame(player1))EmitSoundToClient(player1, sound);
	if (player2 > 0 && player2 <= MaxClients && IsClientInGame(player2))EmitSoundToClient(player2, sound);
}

void PrintDuelResults(int player1, int player2)
{
	char player1Name[MAX_NAME_LENGTH];
	char player2Name[MAX_NAME_LENGTH];

	if (player1 > 0 && player1 <= MaxClients && IsClientInGame(player1))GetClientName(player1, player1Name, sizeof(player1Name));
	else player1Name = "ERRORNAME";

	if (player2 > 0 && player2 <= MaxClients && IsClientInGame(player2))GetClientName(player2, player2Name, sizeof(player2Name));
	else player2Name = "ERRORNAME";

	PrintToChatAll("[Spy Duel] %s vs %s results:", player1Name, player2Name);
	if (player1 <= MaxClients)PrintToChatAll("%s:\nButter Knife: %d\nBackstabs: %d", player1Name, g_PlayerData[player1].butterKnife, g_PlayerData[player1].backstabs);
	if (player2 <= MaxClients)PrintToChatAll("%s:\nButter Knife: %d\nBackstabs: %d", player2Name, g_PlayerData[player2].butterKnife, g_PlayerData[player2].backstabs);
}

void EndSpyDuel(int client)
{
	int partner = GetClientOfUserId(g_PlayerData[client].duelPartner);

	PlayDuelSound(client, partner, SOUND_DUEL_EVENT);
	PrintDuelResults(client, partner);
	if (partner > 0)
	{
		g_PlayerData[partner].Clear();
		PrintCenterText(partner, EVENT_DUEL_END_PARTNER);
	}

	g_PlayerData[client].Clear();
	PrintCenterText(client, EVENT_DUEL_END);
}

void EndAllDuels()
{
	for (int i = 1 ; i <= sizeof(g_PlayerData) - 1; i++)
	{
		if (g_PlayerData[i].duelPartner != 0)EndSpyDuel(i);
	}
}