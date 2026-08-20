using System.IO;
using System.Text.RegularExpressions;
using Microsoft.Data.Sqlite;
using ScriptSuite.Models;

namespace ScriptSuite.Services;

/// <summary>
/// Run history persistence (Milestone 8 writes entries on every executed run;
/// Milestone 10 adds the list UI and Phase 4 builds search/filter on top).
/// SQLite per the spec, stored at %LocalAppData%\ScriptSuite\history.db.
/// The schema matches the spec's minimum RunHistory table exactly so no
/// migration is needed later.
/// </summary>
public sealed class RunHistoryStore
{
    private readonly string _dbPath;

    public RunHistoryStore(string dbPath)
    {
        _dbPath = dbPath;
        Directory.CreateDirectory(Path.GetDirectoryName(dbPath)!);
        using var conn = Open();
        using var cmd = conn.CreateCommand();
        cmd.CommandText = """
            CREATE TABLE IF NOT EXISTS RunHistory (
                Id INTEGER PRIMARY KEY AUTOINCREMENT,
                ScriptId TEXT NOT NULL,
                StartedAt TEXT NOT NULL,
                FinishedAt TEXT,
                Outcome TEXT NOT NULL,
                Summary TEXT
            );
            """;
        cmd.ExecuteNonQuery();
    }

    /// <summary>Records one completed run. Returns the new row's Id.</summary>
    public long Insert(string scriptId, DateTime startedAt, DateTime finishedAt, RunOutcome outcome, string? summary)
    {
        using var conn = Open();
        using var cmd = conn.CreateCommand();
        cmd.CommandText = """
            INSERT INTO RunHistory (ScriptId, StartedAt, FinishedAt, Outcome, Summary)
            VALUES ($scriptId, $startedAt, $finishedAt, $outcome, $summary);
            SELECT last_insert_rowid();
            """;
        cmd.Parameters.AddWithValue("$scriptId", scriptId);
        cmd.Parameters.AddWithValue("$startedAt", startedAt.ToString("yyyy-MM-dd HH:mm:ss"));
        cmd.Parameters.AddWithValue("$finishedAt", finishedAt.ToString("yyyy-MM-dd HH:mm:ss"));
        cmd.Parameters.AddWithValue("$outcome", OutcomeToText(outcome));
        cmd.Parameters.AddWithValue("$summary", (object?)summary ?? DBNull.Value);
        return (long)cmd.ExecuteScalar()!;
    }

    /// <summary>Most recent runs first. Used by the Milestone 10 history list.</summary>
    public List<RunHistoryEntry> GetRecent(int limit = 200)
    {
        var rows = new List<RunHistoryEntry>();
        using var conn = Open();
        using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT Id, ScriptId, StartedAt, FinishedAt, Outcome, Summary FROM RunHistory ORDER BY Id DESC LIMIT $limit;";
        cmd.Parameters.AddWithValue("$limit", limit);
        using var reader = cmd.ExecuteReader();
        while (reader.Read())
        {
            rows.Add(new RunHistoryEntry
            {
                Id = reader.GetInt64(0),
                ScriptId = reader.GetString(1),
                StartedAt = reader.IsDBNull(2) ? null : reader.GetString(2),
                FinishedAt = reader.IsDBNull(3) ? null : reader.GetString(3),
                Outcome = reader.GetString(4),
                Summary = reader.IsDBNull(5) ? null : reader.GetString(5),
            });
        }
        return rows;
    }

    private SqliteConnection Open()
    {
        var conn = new SqliteConnection($"Data Source={_dbPath}");
        conn.Open();
        return conn;
    }

    /// <summary>Short human-readable summary for a history row (e.g. "12 files
    /// deleted"). Prefers the script's final Write-Host summary line; falls
    /// back to the last log line, then null. Shared by every run path (single
    /// manual run and Run All) so history rows read consistently.</summary>
    public static string? BuildSummary(IReadOnlyList<string> logs)
    {
        foreach (var raw in logs.Reverse())
        {
            var line = raw.StartsWith("INFO: ") ? raw[6..] : raw;
            if (Regex.IsMatch(line, @":\s*\d+\s"))
                return line.Length <= 120 ? line : line[..117] + "...";
        }
        var last = logs.LastOrDefault(l => !string.IsNullOrWhiteSpace(l));
        if (last is null) return null;
        return last.Length <= 120 ? last : last[..117] + "...";
    }

    private static string OutcomeToText(RunOutcome o) => o switch
    {
        RunOutcome.Success => "Success",
        RunOutcome.Warning => "Warning",
        RunOutcome.Failed => "Failed",
        RunOutcome.Cancelled => "Cancelled",
        _ => "Failed",
    };
}

/// <summary>One run history row (Milestone 10 storage foundation).</summary>
public sealed class RunHistoryEntry
{
    public long Id { get; set; }
    public string ScriptId { get; set; } = "";
    public string? StartedAt { get; set; }
    public string? FinishedAt { get; set; }
    public string Outcome { get; set; } = "";
    public string? Summary { get; set; }
}