# Discord Chat

SourceMod plugin that relays chat between your game server and a Discord channel.

## Installation

1. Install extension [SM-RIPExt](https://github.com/ErikMinekus/sm-ripext).
2. Upload `DiscordChat.smx` to `addons/sourcemod/plugins/`.
3. Restart the server or run `sm plugins load DiscordChat`.
4. Edit `cfg/sourcemod/DiscordChat.cfg` and fill in your webhook URL, bot token and channel ID.

## ConVars

| ConVar | Default | Description |
|---|---|---|
| `sm_discord_webhook` | `""` | Discord webhook URL |
| `sm_discord_bottoken` | `""` | Discord bot token |
| `sm_discord_channelid` | `""` | Discord channel ID to monitor |
| `sm_discord_pollinterval` | `5.0` | Interval for polling Discord messages (seconds) |
| `sm_discord_enablerelay` | `1` | Enable Discord to game relay (1 = enable) |
| `sm_discord_botname` | `Server Chat` | Webhook sender name shown in Discord |
| `sm_discord_avatar` | *(logo URL)* | Webhook avatar image URL |
| `sm_discord_bot_url` | `""` | URL of the companion bot program (empty = disabled) |
| `sm_discord_bot_secret` | `""` | Shared secret, must match `SECRET` in the bot's `.env` |
| `sm_discord_bot_interval` | `30.0` | Seconds between heartbeats sent to the bot program |
