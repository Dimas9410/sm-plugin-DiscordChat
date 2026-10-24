#include <sourcemod>
#include <ripext>
#include <multicolors>
#include <geoip>

#pragma newdecls required
#pragma semicolon 1

ConVar g_cvWebhookURL;
ConVar g_cvBotToken;
ConVar g_cvChannelID;
ConVar g_cvPollInterval;
ConVar g_cvEnableRelay;
ConVar g_cvBotName;
ConVar g_cvAvatarURL;
ConVar g_cvBotURL;
ConVar g_cvBotSecret;
ConVar g_cvBotInterval;

char g_sLastMessageID[64];
bool g_bFirstPoll = true;
bool g_bPollInFlight = false;
bool g_bFirstMapLoaded = false;
bool g_bBotLinkFailed = false;

public Plugin myinfo =
{
	name        = "Discord Chat",
	author      = "Dimas9410",
	description = "Sends and receives chat messages between the game server and a Discord channel",
	version     = "1.1",
	url         = "amyserver.xyz"
};

public void OnPluginStart()
{
	g_cvWebhookURL   = CreateConVar("sm_discord_webhook", "", "Discord Webhook URL");
	g_cvBotToken     = CreateConVar("sm_discord_bottoken", "", "Discord Bot Token");
	g_cvChannelID    = CreateConVar("sm_discord_channelid", "", "Discord channel ID to monitor");
	g_cvPollInterval = CreateConVar("sm_discord_pollinterval", "5.0", "Interval for polling Discord messages (seconds)", _, true, 3.0);
	g_cvEnableRelay  = CreateConVar("sm_discord_enablerelay", "1", "Enable Discord (1 enable)");
	g_cvBotName     = CreateConVar("sm_discord_botname", "Server Chat", "Webhook sender name shown in Discord (Discord rejects names containing 'discord' or 'clyde')");
	g_cvAvatarURL   = CreateConVar("sm_discord_avatar", "https://media.discordapp.net/attachments/1541220210554437673/1563540123591643287/LOGO_ADS.png?ex=6addffb6&is=6adcae36&hm=fa09c0724de5db3d53a6743e13f6753ae103dcd69cf0897022fe602117aa8bd3&=&format=webp&quality=lossless&width=512&height=512", "Webhook avatar image URL shown in Discord (leave empty to use the webhook's default avatar)");
	g_cvBotURL      = CreateConVar("sm_discord_bot_url", "", "URL of the companion bot program that keeps the bot online, e.g. http://127.0.0.1:3000 (empty = disabled)", FCVAR_PROTECTED);
	g_cvBotSecret   = CreateConVar("sm_discord_bot_secret", "", "Shared secret, must match SECRET in the bot's .env", FCVAR_PROTECTED);
	g_cvBotInterval = CreateConVar("sm_discord_bot_interval", "30.0", "Seconds between heartbeats sent to the bot program", _, true, 5.0);

	AutoExecConfig(true);

	RegConsoleCmd("say", Command_Say);
	RegConsoleCmd("say_team", Command_SayTeam);

	CreateTimer(g_cvPollInterval.FloatValue, Timer_PollDiscord, _, TIMER_REPEAT);
	CreateTimer(g_cvBotInterval.FloatValue, Timer_BotHeartbeat, _, TIMER_REPEAT);
}

public void OnPluginEnd()
{
	/* Tell the bot program to go offline right away. */
	SendBotHeartbeat("/offline");
}

public Action Timer_BotHeartbeat(Handle timer)
{
	SendBotHeartbeat("/heartbeat");
	return Plugin_Continue;
}

void SendBotHeartbeat(const char[] endpoint)
{
	char url[128];
	g_cvBotURL.GetString(url, sizeof(url));
	TrimString(url);

	if (url[0] == '\0')
		return;

	char map[PLATFORM_MAX_PATH], display[128];
	GetCurrentMap(map, sizeof(map));
	GetMapDisplayName(map, display, sizeof(display));

	int players = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i))
			players++;
	}

	JSONObject data = new JSONObject();
	data.SetString("map", display);
	data.SetInt("players", players);
	data.SetInt("maxplayers", GetMaxHumanPlayers());

	char secret[64];
	g_cvBotSecret.GetString(secret, sizeof(secret));

	HTTPClient http = new HTTPClient(url);
	if (secret[0] != '\0')
		http.SetHeader("X-Secret", secret);

	http.Post(endpoint, data, OnBotHeartbeat);

	delete data;
	delete http;
}

void OnBotHeartbeat(HTTPResponse response, any value)
{
	bool ok = (response.Status == HTTPStatus_OK || response.Status == HTTPStatus_NoContent);

	/* Log only when the link goes down, so the log doesn't fill up every 30 seconds. */
	if (!ok && !g_bBotLinkFailed)
		LogError("[Discord] Can't reach the bot program (HTTP %d). Is it running, and do sm_discord_bot_url / sm_discord_bot_secret match?", response.Status);

	g_bBotLinkFailed = !ok;
}

public void OnConfigsExecuted()
{
	/* Configs are loaded by now, so the webhook ConVar already has its real value. */
	SendBotHeartbeat("/heartbeat");

	char map[PLATFORM_MAX_PATH], display[128];
	GetCurrentMap(map, sizeof(map));
	GetMapDisplayName(map, display, sizeof(display));

	char msg[300];

	/* Skip the first map after the plugin loads, only real map changes are announced. */
	if (!g_bFirstMapLoaded)
	{
		g_bFirstMapLoaded = true;
		return;
	}

	FormatEx(msg, sizeof(msg), "Map changed to %s", display);
	SendToDiscord("🗺️", msg);
}

public void OnClientPutInServer(int client)
{
	if (IsFakeClient(client)) return;

	char name[128];
	GetClientName(client, name, sizeof(name));
	EscapeMarkdown(name, sizeof(name));

	char ip[16];
	GetClientIP(client, ip, sizeof(ip));

	char country[64];
	if (!GeoipCountry(ip, country, sizeof(country)) || strlen(country) == 0)
		strcopy(country, sizeof(country), "Indonesia");

	char msg[300];
	FormatEx(msg, sizeof(msg), "%s joined the server from %s", name, country);
	SendToDiscord("✅", msg);
}

public void OnClientDisconnect(int client)
{
	if (IsFakeClient(client)) return;

	char name[128];
	GetClientName(client, name, sizeof(name));
	EscapeMarkdown(name, sizeof(name));

	char msg[256];
	FormatEx(msg, sizeof(msg), "%s left the server", name);
	SendToDiscord("❌", msg);
}

public Action Command_Say(int client, int args)
{
	LogChatToDiscord(client, false);
	return Plugin_Continue;
}

public Action Command_SayTeam(int client, int args)
{
	LogChatToDiscord(client, true);
	return Plugin_Continue;
}

void LogChatToDiscord(int client, bool teamChat)
{
	if (client == 0 || !IsClientInGame(client))
		return;

	char text[256];
	GetCmdArgString(text, sizeof(text));
	StripQuotes(text);
	TrimString(text);

	if (strlen(text) == 0)
		return;

	char teamTag[16];
	teamTag[0] = '\0';

	if (teamChat)
	{
		// CS:GO/CS:S team indices: 2 = T, 3 = CT
		switch (GetClientTeam(client))
		{
			case 2: strcopy(teamTag, sizeof(teamTag), " (TEAM-T)");
			case 3: strcopy(teamTag, sizeof(teamTag), " (TEAM-CT)");
			default: strcopy(teamTag, sizeof(teamTag), " (TEAM)");
		}
	}

	char name[128];
	GetClientName(client, name, sizeof(name));
	EscapeMarkdown(name, sizeof(name));

	char msg[480];
	FormatEx(msg, sizeof(msg), "%s%s: %s", name, teamTag, text);
	SendToDiscord("💬", msg);
}

/* Escape markdown characters in player names so a name like "a*b" can't break the bold text. */
void EscapeMarkdown(char[] text, int maxlen)
{
	ReplaceString(text, maxlen, "\\", "\\\\");
	ReplaceString(text, maxlen, "*", "\\*");
	ReplaceString(text, maxlen, "_", "\\_");
	ReplaceString(text, maxlen, "~", "\\~");
	ReplaceString(text, maxlen, "`", "\\`");
	ReplaceString(text, maxlen, "|", "\\|");
}

void SendToDiscord(const char[] emoji, const char[] message)
{
	// Block anything containing '@' entirely (covers @everyone, @here, and
	// any @user/@role mention) rather than just stripping those two words -
	// this way there's no risk of a raw mention slipping through some other
	// mention format Discord recognizes.
	if (StrContains(message, "@", false) != -1)
	{
		PrintToServer("[Discord] Blocked message containing '@' from being sent to Discord %s", message);
		return;
	}

	char webhook[256];
	g_cvWebhookURL.GetString(webhook, sizeof(webhook));

	if (strlen(webhook) == 0)
		return;

	int apiIndex = StrContains(webhook, "/api/webhooks/", false);
	if (apiIndex == -1)
	{
		LogError("[Discord] Invalid webhook URL format.");
		return;
	}

	char host[64];
	strcopy(host, sizeof(host), "https://discord.com");

	char path[256];
	strcopy(path, sizeof(path), webhook[apiIndex]);

	JSONObject data = new JSONObject();
	/* Timestamp is added after the '@' filter above, since the format itself contains an '@'. */
	char timeStr[48];
	FormatTime(timeStr, sizeof(timeStr), "%d/%m/%Y @ %I:%M %p");

	char content[560];
	FormatEx(content, sizeof(content), "%s **[%s]** %s", emoji, timeStr, message);

	data.SetString("content", content);

	char botName[80];
	g_cvBotName.GetString(botName, sizeof(botName));
	TrimString(botName);
	if (botName[0] != '\0')
		data.SetString("username", botName);

	char avatar[512];
	g_cvAvatarURL.GetString(avatar, sizeof(avatar));
	TrimString(avatar);
	if (avatar[0] != '\0')
		data.SetString("avatar_url", avatar);

	HTTPClient client = new HTTPClient(host);
	client.Post(path, data, OnWebhookSent);

	delete data;
	delete client;
}

void OnWebhookSent(HTTPResponse response, any value)
{
	if (response.Status != HTTPStatus_OK && response.Status != HTTPStatus_NoContent)
	{
		LogError("[Discord] Failed to send message to Discord, status: %d", response.Status);
	}
}

public Action Timer_PollDiscord(Handle timer)
{
	if (!g_cvEnableRelay.BoolValue)
		return Plugin_Continue;

	if (g_bPollInFlight)
		return Plugin_Continue;

	char token[128], channelId[64];
	g_cvBotToken.GetString(token, sizeof(token));
	g_cvChannelID.GetString(channelId, sizeof(channelId));

	if (strlen(token) == 0 || strlen(channelId) == 0)
		return Plugin_Continue;

	char endpoint[256];
	FormatEx(endpoint, sizeof(endpoint), "/api/v10/channels/%s/messages?limit=5", channelId);

	HTTPClient client = new HTTPClient("https://discord.com");

	char authHeader[160];
	FormatEx(authHeader, sizeof(authHeader), "Bot %s", token);
	client.SetHeader("Authorization", authHeader);

	g_bPollInFlight = true;
	client.Get(endpoint, OnMessagesFetched);
	delete client;

	return Plugin_Continue;
}

void OnMessagesFetched(HTTPResponse response, any value)
{
	g_bPollInFlight = false;

	if (response.Status != HTTPStatus_OK)
		return;

	JSONArray messages = view_as<JSONArray>(response.Data);
	if (messages == null)
		return;

	int count = messages.Length;
	if (count == 0)
	{
		delete messages;
		return;
	}

	int newCount = 0;
	for (int i = 0; i < count; i++)
	{
		JSONObject msgObj = view_as<JSONObject>(messages.Get(i));

		char msgId[64];
		msgObj.GetString("id", msgId, sizeof(msgId));

		delete msgObj;

		if (strlen(g_sLastMessageID) > 0 && StrEqual(msgId, g_sLastMessageID))
			break;

		newCount++;
	}

	for (int i = newCount - 1; i >= 0; i--)
	{
		JSONObject msgObj = view_as<JSONObject>(messages.Get(i));

		char msgId[64];
		msgObj.GetString("id", msgId, sizeof(msgId));

		JSONObject author = view_as<JSONObject>(msgObj.Get("author"));

		bool isBot = author.HasKey("bot") && author.GetBool("bot");

		char username[64], content[256];
		author.GetString("username", username, sizeof(username));
		msgObj.GetString("content", content, sizeof(content));

		if (!isBot && !g_bFirstPoll)
		{
			if (strlen(content) > 0)
			{
				char safeUsername[128], safeContent[512];
				strcopy(safeUsername, sizeof(safeUsername), username);
				strcopy(safeContent, sizeof(safeContent), content);
				ReplaceString(safeUsername, sizeof(safeUsername), "%", "%%");
				ReplaceString(safeContent, sizeof(safeContent), "%", "%%");

				char formatted[320];
				FormatEx(formatted, sizeof(formatted), "{aqua}[Discord Chat] {white}%s {gold}: {grey}%s", safeUsername, safeContent);
				CPrintToChatAll(formatted);
				PrintToServer("[Discord Relay] Message from Discord to Game Chat. user='%s' message='%s'", username, content);
			}
		}

		delete author;
		delete msgObj;
	}

	JSONObject latest = view_as<JSONObject>(messages.Get(0));
	latest.GetString("id", g_sLastMessageID, sizeof(g_sLastMessageID));
	delete latest;

	g_bFirstPoll = false;
	delete messages;
}
