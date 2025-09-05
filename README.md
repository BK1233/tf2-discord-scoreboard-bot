# TF2 Discord Scoreboard Bot

This repository contains two pieces:

1. **SourceMod plugin** (`tf2_discord_scoreboard.sp`) that periodically writes your TF2 server's scoreboard to a JSON file (`addons/sourcemod/data/scoreboard.json`). The plugin can be compiled with the SourceMod compiler and installed on any TF2 server.

2. **Discord bot** (written in Python) that reads the JSON file and provides slash commands (`/score`, `/top`, `/server`) to display live stats in Discord. The bot can also post automatic updates to a channel when the file changes. It runs in a Docker container.

## Features

- Server info: map, player count, max slots, last update.
- Top players list: score, kills, deaths, team, bot indicator.
- Slash commands using Discord's interactions API (no privileged intents).
- Optional automatic posting when the scoreboard file changes (see `AUTO_CHANNEL_ID`).

## Getting started

### SourceMod plugin

1. Compile `tf2_discord_scoreboard.sp` with the [SourceMod compiler](https://www.sourcemod.net/downloads.php) matching your server version.
2. Copy the resulting `.smx` to `tf/addons/sourcemod/plugins/` on your TF2 server.
3. Restart your server or reload the plugin (`sm plugins load tf2_discord_scoreboard`).
4. Ensure the scoreboard JSON file appears at `tf/addons/sourcemod/data/scoreboard.json`.
5. Configure the interval and enable output via console:
   ```
   sm_tds_json_enable 1
   sm_tds_json_interval 15.0
   ```
   Use `sm_tds_server_name` to override the server name if desired.

### Discord bot

This bot uses [discord.py](https://discordpy.readthedocs.io/) and [watchdog](https://python-watchdog.readthedocs.io/) and is packaged for Docker.

1. Copy the `bot/` directory to a host with Docker installed.
2. Create a `.env` file (based on `.env.example`) and set your `DISCORD_TOKEN`. Optionally set `GUILD_ID` and `AUTO_CHANNEL_ID`.
3. Edit `bot/docker-compose.yml` and update the volume mapping so that `/data/scoreboard.json` inside the container points to the absolute path of `scoreboard.json` on your TF2 server host.
4. Build and run the container:
   ```sh
   docker compose up -d --build
   ```
5. Invite the bot to your Discord server via the OAuth2 URL generator in the Discord developer portal. Grant `bot` and `applications.commands` scopes, and the permissions "Send Messages" and "Embed Links".

### Windows setup script (optional)

A helper script `setup-tf2scorebot.ps1` is provided to automate creating a virtual environment, installing dependencies, and generating a Docker compose file on Windows. Adjust the parameters at the top of the script to suit your environment.

## License

This project is provided under the MIT License. See [LICENSE](LICENSE) for details.
