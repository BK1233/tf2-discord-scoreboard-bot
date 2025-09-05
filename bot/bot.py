import json
import os
import time
import asyncio
from pathlib import Path
from typing import Optional, Dict, List

import discord
from discord import app_commands
from discord.ext import commands
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

# Path to the scoreboard file inside the container. Override via SCOREBOARD_PATH env.
SCOREBOARD_PATH = os.getenv("SCOREBOARD_PATH", "/data/scoreboard.json")
# Optionally restrict slash command sync to a single guild
GUILD_ID = int(os.getenv("GUILD_ID", "0"))

intents = discord.Intents.none()
bot = commands.Bot(command_prefix="!", intents=intents)


def load_scoreboard() -> Optional[Dict]:
    """Load scoreboard JSON from disk."""
    try:
        with open(SCOREBOARD_PATH, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None


def format_embed(data: Dict) -> discord.Embed:
    """Convert scoreboard dict into a Discord embed."""
    server = data.get("server", {})
    players = data.get("players", [])
    title = f"{server.get('name','TF2 Server')} — {server.get('map','Unknown')}"
    desc = f"Players: {server.get('players','?')}/{server.get('maxPlayers','?')} • Updated <t:{int(server.get('timestamp', time.time()))}:R>"
    embed = discord.Embed(title=title, description=desc)
    # Top 10 players by score
    top = sorted(players, key=lambda p: p.get('score', 0), reverse=True)[:10]
    lines: List[str] = []
    for i, p in enumerate(top, 1):
        flag = "🤖 " if p.get('isBot') else ""
        lines.append(
            f"**{i}.** {flag}`{p.get('name','?')}` — **{p.get('score',0)}** ({p.get('kills',0)}/{p.get('deaths',0)}) [{p.get('team','?')}]"
        )
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
    topn = sorted(players, key=lambda p: p.get('score', 0), reverse=True)[:n]
    lines: List[str] = []
    for i, p in enumerate(topn, 1):
        flag = "🤖 " if p.get('isBot') else ""
        lines.append(
            f"**{i}.** {flag}`{p.get('name','?')}` — **{p.get('score',0)}** ({p.get('kills',0)}/{p.get('deaths',0)}) [{p.get('team','?')}]"
        )
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
    """Watch for modifications to the scoreboard file and post updates."""
    def __init__(self):
        self._last_emit = 0
        self.channel_id = int(os.getenv("AUTO_CHANNEL_ID", "0"))

    async def post_update(self):
        if not self.channel_id:
            return
        channel = bot.get_channel(self.channel_id)
        if not channel:
            return
        data = load_scoreboard()
        if not data:
            return
        await channel.send(embed=format_embed(data))

    def on_modified(self, event):
        if not event.is_directory and event.src_path.replace("\\", "/").endswith("scoreboard.json"):
            now = time.time()
            if now - self._last_emit >= 30:  # debounce
                self._last_emit = now
                asyncio.run_coroutine_threadsafe(self.post_update(), bot.loop)


def start_watcher():
    path = Path(SCOREBOARD_PATH)
    if not path.exists():
        return None
    observer = Observer()
    handler = ScoreboardHandler()
    observer.schedule(handler, str(path.parent), recursive=False)
    observer.start()
    return observer


if __name__ == "__main__":
    observer = start_watcher()
    try:
        bot.run(os.getenv("DISCORD_TOKEN"))
    finally:
        if observer:
            observer.stop()
            observer.join()
