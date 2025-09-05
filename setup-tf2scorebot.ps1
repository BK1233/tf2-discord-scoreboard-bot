<# 
  setup-tf2scorebot.ps1
  - Creates a Dockerized Discord bot that reads TF2 scoreboard JSON
  - Defaults:
      Project dir: C:\tf2scorebot
      TF2 path   : F:\tf2
  - Requires: Docker Desktop for Windows (with drive F: shared)
#>

param(
  [string]$ProjectDir = "C:\tf2scorebot",
  [string]$TF2Path    = "F:\tf2",
  [string]$GuildId    = "",                 # optional: speeds up slash command sync
  [string]$AutoChannelId = ""               # optional: channel id for auto-posts
)

$ErrorActionPreference = "Stop"

function Ensure-Folder($Path) {
  if (-not (Test-Path $Path)) {
    New-Item -ItemType Directory -Path $Path | Out-Null
  }
}

Write-Host "==> Checking Docker availability..." -ForegroundColor Cyan
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  Write-Error "Docker is not installed or not in PATH. Install Docker Desktop and re-run."
}

# Sanity paths
$ScoreDir  = Join-Path $TF2Path "tf\addons\sourcemod\data"
$ScoreFile = Join-Path $ScoreDir  "scoreboard.json"

Write-Host "==> Ensuring scoreboard path exists: $ScoreFile" -ForegroundColor Cyan
Ensure-Folder $ScoreDir
if (-not (Test-Path $ScoreFile)) {
  '{}' | Set-Content -Path $ScoreFile -Encoding UTF8
}

Write-Host "==> Creating project at $ProjectDir" -ForegroundColor Cyan
Ensure-Folder $ProjectDir
Set-Location $ProjectDir

# -------- requirements.txt --------
@'
discord.py==2.4.0
watchdog==5.0.2
'@ | Out-File -Encoding UTF8 -FilePath (Join-Path $ProjectDir "requirements.txt")

# -------- bot.py --------
@'
import json, os, time, asyncio
from pathlib import Path
from typing import Optional, Dict, List

import discord
from discord import app_commands
from discord.ext import commands
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

SCOREBOARD_PATH = os.getenv("SCOREBOARD_PATH", "/data/scoreboard.json")
GUILD_ID = int(os.getenv("GUILD_ID", "0"))  # optional
intents = discord.Intents.none()
bot = commands.Bot(command_prefix="!", intents=intents)

def load_scoreboard() -> Optional[Dict]:
    try:
        with open(SCOREBOARD_PATH, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None

def format_embed(data: Dict) -> discord.Embed:
    server = data.get("server", {})
    players = data.get("players", [])
    title = f"{server.get('name','TF2 Server')} — {server.get('map','Unknown')}"
    desc = f"Players: {server.get('players','?')}/{server.get('maxPlayers','?')} • Updated <t:{int(server.get('timestamp', time.time()))}:R>"
    embed = discord.Embed(title=title, description=desc)
    top = sorted(players, key=lambda p: p.get("score", 0), reverse=True)[:10]
    lines: List[str] = []
    for i, p in enumerate(top, 1):
        flag = "🤖 " if p.get("isBot") else ""
        lines.append(f"**{i}.** {flag}`{p.get('name','?')}` — **{p.get('score',0)}** ({p.get('kills',0)}/{p.get('deaths',0)}) [{p.get('team','?')}]")
    embed.add_field(name="Top Players", value="\n".join(lines) or "_no players_", inline=False)
    return embed

@bot.event
async def on_ready():
    try:
        if GUILD_ID:
            guild = bot.get_guild(GUILD_ID)
            if guild:
                await bot.tree.sync(guild=guild)
        else:
            await bot.tree.sync()
    except Exception as e:
        print("Slash sync error:", e)
    print(f"Logged in as {bot.user} (ID: {bot.user.id})")

@bot.tree.command(description="Show the current scoreboard")
async def score(interaction: discord.Interaction):
    data = load_scoreboard()
    if not data:
        await interaction.response.send_message("No scoreboard data found yet.", ephemeral=True)
        return
    await interaction.response.send_message(embed=format_embed(data))

@bot.tree.command(description="Show top N players by score")
@app_commands.describe(n="How many players to list (default 10)")
async def top(interaction: discord.Interaction, n: int = 10):
    data = load_scoreboard()
    if not data:
        await interaction.response.send_message("No scoreboard data found yet.", ephemeral=True)
        return
    players = data.get("players", [])
    n = max(1, min(25, n or 10))
    topn = sorted(players, key=lambda p: p.get("score", 0), reverse=True)[:n]
    lines = []
    for i, p in enumerate(topn, 1):
        flag = "🤖 " if p.get("isBot") else ""
        lines.append(f"**{i}.** {flag}`{p.get('name','?')}` — **{p.get('score',0)}** ({p.get('kills',0)}/{p.get('deaths',0)}) [{p.get('team','?')}]")
    await interaction.response.send_message("\n".join(lines) or "_no players_")

@bot.tree.command(description="Show server info")
async def server(interaction: discord.Interaction):
    data = load_scoreboard()
    if not data:
        await interaction.response.send_message("No scoreboard data found yet.", ephemeral=True)
        return
    s = data.get("server", {})
    msg = (
        f"**Name:** {s.get('name','?')}\n"
        f"**Map:** {s.get('map','?')}\n"
        f"**Players:** {s.get('players','?')}/{s.get('maxPlayers','?')}\n"
        f"**Updated:** <t:{int(s.get('timestamp', time.time()))}:R>"
    )
    await interaction.response.send_message(msg)

class ScoreboardHandler(FileSystemEventHandler):
    def __init__(self):
        self._last_emit = 0
        self._channel_id = int(os.getenv("AUTO_CHANNEL_ID", "0"))

    async def post_update(self):
        if not self._channel_id:
            return
        channel = bot.get_channel(self._channel_id)
        if not channel:
            return
        data = load_scoreboard()
        if not data:
            return
        await channel.send(embed=format_embed(data))

    def on_modified(self, event):
        if not event.is_directory and event.src_path.replace("\\", "/").endswith("scoreboard.json"):
            now = time.time()
            if now - self._last_emit >= 30:
                self._last_emit = now
                asyncio.run_coroutine_threadsafe(self.post_update(), bot.loop)

def start_watcher():
    p = Path(SCOREBOARD_PATH)
    p.parent.mkdir(parents=True, exist_ok=True)
    obs = Observer()
    obs.schedule(ScoreboardHandler(), str(p.parent), recursive=False)
    obs.start()
    return obs

if __name__ == "__main__":
    observer = start_watcher()
    try:
        bot.run(os.getenv("DISCORD_TOKEN"))
    finally:
        observer.stop(); observer.join()
'@ | Out-File -Encoding UTF8 -FilePath (Join-Path $ProjectDir "bot.py")

# -------- Dockerfile --------
@'
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN useradd -m appuser
WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends gcc curl \
 && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY bot.py .

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s CMD python -c "import os,sys; sys.exit(0 if os.getenv('DISCORD_TOKEN') else 1)"

USER appuser

ENV SCOREBOARD_PATH=/data/scoreboard.json

CMD ["python", "bot.py"]
'@ | Out-File -Encoding UTF8 -FilePath (Join-Path $ProjectDir "Dockerfile")

# -------- docker-compose.yml --------
# Use forward slashes and quotes for Windows paths
$compose = @"
version: "3.8"
services:
  tf2scorebot:
    build: .
    environment:
      DISCORD_TOKEN: "\${DISCORD_TOKEN}"
      SCOREBOARD_PATH: "/data/scoreboard.json"
@(if($GuildId){'      GUILD_ID: "'+$GuildId+'"'})
@(if($AutoChannelId){'      AUTO_CHANNEL_ID: "'+$AutoChannelId+'"'})
    volumes:
      - "F:/tf2/tf/addons/sourcemod/data/scoreboard.json:/data/scoreboard.json:ro"
    restart: unless-stopped
"@
$compose | Out-File -Encoding UTF8 -FilePath (Join-Path $ProjectDir "docker-compose.yml")

# -------- .env --------
if (-not (Test-Path (Join-Path $ProjectDir ".env"))) {
@"
# Required
DISCORD_TOKEN=PASTE_YOUR_BOT_TOKEN

# Optional (faster command sync to one guild)
# GUILD_ID=$GuildId

# Optional (auto-post channel id)
# AUTO_CHANNEL_ID=$AutoChannelId
"@ | Out-File -Encoding UTF8 -FilePath (Join-Path $ProjectDir ".env")
}

Write-Host "==> Ensuring Docker Desktop can access drive F:" -ForegroundColor Cyan
Write-Host "   Open Docker Desktop → Settings → Resources → File Sharing, and add F:\ if not already shared." -ForegroundColor Yellow

Write-Host "==> Building and starting the container..." -ForegroundColor Cyan
docker compose up -d --build

Write-Host "`nAll set!" -ForegroundColor Green
Write-Host "1) Put your bot token in $ProjectDir\.env (DISCORD_TOKEN=...)" -ForegroundColor Gray
Write-Host "2) In Discord, try /score, /top, /server" -ForegroundColor Gray
Write-Host "3) View logs:  docker compose -f `"$ProjectDir\docker-compose.yml`" logs -f tf2scorebot" -ForegroundColor Gray
