// =======================================================================
// TF2 Discord Scoreboard (JSON-only, bot-ready)
// Writes tf/addons/sourcemod/data/scoreboard.json for your Discord bot
// No external extensions required.
// =======================================================================

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

public Plugin myinfo =
{
    name        = "TF2 Discord Scoreboard (JSON)",
    author      = "You + ChatGPT",
    description = "Exports live server/player data to scoreboard.json for a Discord bot",
    version     = "1.0.0",
    url         = "https://github.com/BK1233/tf2-discord-scoreboard"
};

// -------------------------------
// CVars
// -------------------------------
ConVar gCvarJsonEnable;
ConVar gCvarJsonInterval;
ConVar gCvarServerName; // optional override for hostname

Handle g_hJsonTimer = null;

// -------------------------------
// Forwards
// -------------------------------
public void OnPluginStart()
{
    // Configurable CVars
    gCvarJsonEnable   = CreateConVar("sm_tds_json_enable", "1",
        "Enable writing scoreboard.json for the Discord bot (1/0)", FCVAR_NOTIFY, true, 0.0, true, 1.0);

    gCvarJsonInterval = CreateConVar("sm_tds_json_interval", "15.0",
        "Interval in seconds to refresh scoreboard.json (min 5s)", FCVAR_NOTIFY);

    gCvarServerName   = CreateConVar("sm_tds_server_name", "",
        "Optional override for server name (blank = use hostname)", FCVAR_NOTIFY);

    HookConVarChange(gCvarJsonEnable,   CvarChanged_Json);
    HookConVarChange(gCvarJsonInterval, CvarChanged_Json);
    HookConVarChange(gCvarServerName,   CvarChanged_Json);

    RegAdminCmd("sm_tds_savejson", Cmd_SaveJson, ADMFLAG_GENERIC, "Force-write scoreboard.json now.");

    RefreshJsonTimer();
    // Initial write so the bot sees a file quickly
    SaveScoreboard();
}

public void OnMapStart()
{
    RefreshJsonTimer();
    SaveScoreboard();
}

public void OnClientPutInServer(int client)
{
    // Update soon after a player joins
    CreateTimer(1.0, Timer_SaveSoon, _, TIMER_FLAG_NO_MAPCHANGE);
}

public void OnClientDisconnect(int client)
{
    // Update soon after a player leaves
    CreateTimer(1.0, Timer_SaveSoon, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Cmd_SaveJson(int client, int args)
{
    SaveScoreboard();
    ReplyToCommand(client, "[tds] Wrote scoreboard.json");
    return Plugin_Handled;
}

public void CvarChanged_Json(ConVar cvar, const char[] oldValue, const char[] newValue)
{
    RefreshJsonTimer();
}

// -------------------------------
// Timers
// -------------------------------
public void RefreshJsonTimer()
{
    if (g_hJsonTimer != null)
    {
        CloseHandle(g_hJsonTimer);
        g_hJsonTimer = null;
    }

    float interval = gCvarJsonInterval.FloatValue;
    if (interval < 5.0) interval = 5.0;

    if (gCvarJsonEnable.BoolValue)
    {
        g_hJsonTimer = CreateTimer(interval, Timer_SaveScoreboard, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    }
}

public Action Timer_SaveScoreboard(Handle timer)
{
    SaveScoreboard();
    return Plugin_Continue;
}

public Action Timer_SaveSoon(Handle timer)
{
    SaveScoreboard();
    return Plugin_Continue;
}

// -------------------------------
// Helpers
// -------------------------------

// Escape quotes, backslashes, and newlines for JSON strings
void JsonEscape(const char[] src, char[] dst, int outlen)
{
    int pos = 0;
    for (int i = 0; src[i] != '\0' && pos < outlen - 1; i++)
    {
        char c = src[i];
        if (c == '"' || c == '\\')
        {
            if (pos + 2 >= outlen) break;
            dst[pos++] = '\\';
            dst[pos++] = c;
        }
        else if (c == '\n')
        {
            if (pos + 2 >= outlen) break;
            dst[pos++] = '\\';
            dst[pos++] = 'n';
        }
        else
        {
            dst[pos++] = c;
        }
    }
    dst[pos] = '\0';
}

// Resolve team name into a buffer
stock void GetTeamNameTF2(int team, char[] buffer, int maxlen)
{
    if (team == 2) { strcopy(buffer, maxlen, "RED");  return; }
    if (team == 3) { strcopy(buffer, maxlen, "BLU");  return; }
    strcopy(buffer, maxlen, "SPEC");
}

// Safer "score" source. Replace with your real scoring logic if needed.
// Fallback: use frags so it's always non-zero for active players.
int GetPlayerScoreSafe(int client)
{
    return GetClientFrags(client);
}

// Try to get deaths via Prop_Data. If it fails, return 0.
int GetPlayerDeathsSafe(int client)
{
    if (!IsClientInGame(client)) return 0;
    // m_iDeaths exists on CBasePlayer (Prop_Data)
    int deaths = GetEntProp(client, Prop_Data, "m_iDeaths", 0);
    return (deaths < 0) ? 0 : deaths;
}

// Grab server name: sm_tds_server_name (if set) else "hostname" convar else fallback
void GetServerName(char[] buffer, int maxlen)
{
    buffer[0] = '\0';

    // CVar override
    if (gCvarServerName != null)
    {
        gCvarServerName.GetString(buffer, maxlen);
        if (buffer[0] != '\0')
            return;
    }

    // hostname convar
    ConVar cv = FindConVar("hostname");
    if (cv != null)
    {
        cv.GetString(buffer, maxlen);
        if (buffer[0] != '\0')
            return;
    }

    // fallback
    strcopy(buffer, maxlen, "TF2 Server");
}

// Atomic write helper: write to temp, then rename over final.
bool WriteAllAndSwap(const char[] tempPath, const char[] finalPath, const char[] content)
{
    Handle f = OpenFile(tempPath, "w");
    if (f == INVALID_HANDLE)
    {
        LogError("[tds] Failed to open temp scoreboard file: %s", tempPath);
        return false;
    }
    bool ok = WriteFileString(f, content, false);
    CloseHandle(f);

    if (!ok)
    {
        LogError("[tds] Failed to write scoreboard content.");
        return false;
    }

    // Replace existing atomically
    DeleteFile(finalPath);
    if (!RenameFile(finalPath, tempPath))
    {
        LogError("[tds] Failed to rename temp scoreboard to final.");
        return false;
    }
    return true;
}

// -------------------------------
// Core: Build JSON and write file
// -------------------------------
void SaveScoreboard()
{
    if (!gCvarJsonEnable.BoolValue)
        return;

    char tmpPath[PLATFORM_MAX_PATH], finalPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, tmpPath,  sizeof(tmpPath),  "data/scoreboard.json.tmp");
    BuildPath(Path_SM, finalPath, sizeof(finalPath), "data/scoreboard.json");

    // Server info
    char map[64];
    GetCurrentMap(map, sizeof(map));

    int players = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i))
            players++;
    }

    char servername[128];
    GetServerName(servername, sizeof(servername));

    int timestamp = GetTime();

    // Compose JSON (single buffer)
    char buf[65536];
    Format(buf, sizeof(buf), "{\n  \"server\": {\"name\":\"%s\",\"map\":\"%s\",\"players\":%d,\"maxPlayers\":%d,\"timestamp\":%d},\n  \"players\": [\n", servername, map, players, MaxClients, timestamp);

    bool first = true;

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i))
            continue;

        // Name (escaped)
        char rawName[128], nameEsc[256];
        GetClientName(i, rawName, sizeof(rawName));
        JsonEscape(rawName, nameEsc, sizeof(nameEsc));

        // Team
        char team[8];
        GetTeamNameTF2(GetClientTeam(i), team, sizeof(team));

        // Stats
        int kills  = GetClientFrags(i);
        int deaths = GetPlayerDeathsSafe(i);
        int score  = GetPlayerScoreSafe(i);
        bool bot   = IsFakeClient(i);

        // One player line
        char line[1024];
        Format(line, sizeof(line), "%s    {\"name\":\"%s\",\"team\":\"%s\",\"score\":%d,\"kills\":%d,\"deaths\":%d,\"isBot\":%s}",
            first ? "" : ",\n",
            nameEsc, team, score, kills, deaths, bot ? "true" : "false");

        StrCat(buf, sizeof(buf), line);
        first = false;
    }

    StrCat(buf, sizeof(buf), first ? "  ]\n}\n" : "\n  ]\n}\n");

    if (!WriteAllAndSwap(tmpPath, finalPath, buf))
    {
        // Errors already logged
    }
}
