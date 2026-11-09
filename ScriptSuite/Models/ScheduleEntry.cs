using System.Text.Json.Serialization;

namespace ScriptSuite.Models;

/// <summary>Per-script schedule (Stage 2). Simple recurring interval, no cron.
/// Stored in %LOCALAPPDATA%\ScriptSuite\schedules.json via ScheduleStore.</summary>
public sealed class ScheduleEntry
{
    [JsonPropertyName("scriptId")] public string ScriptId { get; set; } = "";
    [JsonPropertyName("enabled")] public bool Enabled { get; set; } = true;
    // Unit: Days | Hours | Weeks
    [JsonPropertyName("unit")] public string Unit { get; set; } = "Days";
    [JsonPropertyName("interval")] public int Interval { get; set; } = 1;
    // HH:mm 24h
    [JsonPropertyName("timeOfDay")] public string TimeOfDay { get; set; } = "09:00";
    [JsonPropertyName("createdAt")] public string CreatedAt { get; set; } = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss");
    [JsonPropertyName("nextRun")] public string? NextRun { get; set; }

    /// <summary>Selected days of week for Weeks schedule (e.g. ["Monday", "Wednesday"]).
    /// Null/omitted for Days and Hours schedules.</summary>
    [JsonPropertyName("weekdays")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string[]? Weekdays { get; set; }

    /// <summary>Start date anchor (yyyy-MM-dd). For Days/Hours: first run date.
    /// For Weeks with interval > 1: week anchor.</summary>
    [JsonPropertyName("startDate")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? StartDate { get; set; }
}
