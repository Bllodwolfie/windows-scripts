using System.Globalization;
using ScriptSuite.Models;

namespace ScriptSuite.Services;

/// <summary>Pure, deterministic calculation engine for task schedules,
/// start boundaries, next-run previews, and schedule collision warnings.</summary>
public static class ScheduleCalculation
{
    private static readonly string[] ValidDayNames =
    [
        "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"
    ];

    public static bool IsValidDayOfWeekName(string name) =>
        ValidDayNames.Contains(name, StringComparer.OrdinalIgnoreCase);

    public static DayOfWeek ParseDayOfWeek(string name) =>
        Enum.Parse<DayOfWeek>(name, ignoreCase: true);

    public record ScheduleResult(DateTime NextRun, string StartBoundary, string PreviewText);

    /// <summary>Calculates the start boundary (no-Z string for Task Scheduler),
    /// next execution time, and user-facing preview string.</summary>
    public static ScheduleResult ComputeSchedule(ScheduleEntry entry, DateTime? fromTime = null)
    {
        DateTime now = fromTime ?? DateTime.Now;

        if (!TimeSpan.TryParseExact(entry.TimeOfDay, @"h\:mm", CultureInfo.InvariantCulture, out var ts) &&
            !TimeSpan.TryParse(entry.TimeOfDay, out ts))
        {
            ts = new TimeSpan(9, 0, 0);
        }

        string unit = entry.Unit switch
        {
            "Hours" or "Weeks" => entry.Unit,
            _ => "Days",
        };

        int interval = entry.Interval <= 0 ? 1 : entry.Interval;
        if (unit == "Hours" && interval > 24) interval = 24;

        DateTime nextRun;
        DateTime boundaryDate;

        switch (unit)
        {
            case "Hours":
            {
                DateTime anchor = ResolveStartDate(entry.StartDate, now).Date.Add(ts);
                if (anchor > now)
                {
                    nextRun = anchor;
                    boundaryDate = anchor;
                }
                else
                {
                    boundaryDate = anchor;
                    DateTime candidate = anchor;
                    while (candidate <= now)
                    {
                        candidate = candidate.AddHours(interval);
                    }
                    nextRun = candidate;
                }
                break;
            }

            case "Days":
            {
                DateTime anchor = ResolveStartDate(entry.StartDate, now).Date.Add(ts);
                boundaryDate = anchor;
                if (anchor > now)
                {
                    nextRun = anchor;
                }
                else
                {
                    int daysDiff = (now.Date - anchor.Date).Days;
                    int steps = daysDiff / interval;
                    DateTime candidate = anchor.AddDays(steps * interval);
                    while (candidate <= now)
                    {
                        candidate = candidate.AddDays(interval);
                    }
                    nextRun = candidate;
                }
                break;
            }

            case "Weeks":
            default:
            {
                var selectedDays = ParseWeekdays(entry.Weekdays, now.DayOfWeek);
                if (interval <= 1)
                {
                    // Find the earliest upcoming day from selectedDays at timeOfDay strictly after now
                    DateTime candidate = now.Date.Add(ts);
                    while (candidate <= now || !selectedDays.Contains(candidate.DayOfWeek))
                    {
                        candidate = candidate.AddDays(1);
                    }
                    nextRun = candidate;
                    boundaryDate = candidate;
                }
                else
                {
                    // Multi-week: anchored to entry.StartDate
                    DateTime anchorDate = ResolveStartDate(entry.StartDate, now).Date;
                    DateTime anchorMonday = GetMondayOfWeek(anchorDate);
                    boundaryDate = anchorDate.Add(ts);

                    // Find earliest matching date on an active week
                    DateTime candidate = now.Date.Add(ts);
                    while (true)
                    {
                        if (candidate > now && selectedDays.Contains(candidate.DayOfWeek))
                        {
                            DateTime candidateMonday = GetMondayOfWeek(candidate.Date);
                            int weekOffset = (candidateMonday - anchorMonday).Days / 7;
                            if (weekOffset >= 0 && (weekOffset % interval) == 0)
                            {
                                nextRun = candidate;
                                break;
                            }
                        }
                        candidate = candidate.AddDays(1);
                    }
                }
                break;
            }
        }

        string boundaryStr = boundaryDate.ToString("yyyy-MM-ddTHH:mm:ss", CultureInfo.InvariantCulture);
        string previewStr = FormatPreview(nextRun);
        return new ScheduleResult(nextRun, boundaryStr, previewStr);
    }

    public static string FormatPreview(DateTime dt)
    {
        // Format: "Ddd dd.MM.yyyy HH:mm", e.g. "Sun 15.11.2026 18:02"
        string dayName = dt.ToString("ddd", CultureInfo.InvariantCulture);
        return $"Next run: {dayName} {dt:dd.MM.yyyy HH:mm}";
    }

    private static DateTime ResolveStartDate(string? startDateStr, DateTime now)
    {
        if (!string.IsNullOrWhiteSpace(startDateStr) &&
            DateTime.TryParseExact(startDateStr, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var d))
        {
            return d.Date;
        }
        return now.Date;
    }

    private static DateTime GetMondayOfWeek(DateTime dt)
    {
        int diff = (7 + (dt.DayOfWeek - DayOfWeek.Monday)) % 7;
        return dt.Date.AddDays(-diff);
    }

    public static List<DayOfWeek> ParseWeekdays(string[]? weekdays, DayOfWeek defaultDay)
    {
        var list = new List<DayOfWeek>();
        if (weekdays != null)
        {
            foreach (var w in weekdays)
            {
                if (IsValidDayOfWeekName(w))
                {
                    var d = ParseDayOfWeek(w);
                    if (!list.Contains(d)) list.Add(d);
                }
            }
        }
        if (list.Count == 0)
        {
            list.Add(defaultDay);
        }
        return list;
    }

    /// <summary>Checks for a time/day collision with other enabled schedules.
    /// Returns a warning message if a collision is detected, or null if safe.</summary>
    public static string? DetectCollision(ScheduleEntry current, IEnumerable<ScheduleEntry> existingEntries)
    {
        if (string.IsNullOrWhiteSpace(current.TimeOfDay)) return null;

        var currentDays = current.Unit == "Weeks"
            ? ParseWeekdays(current.Weekdays, DateTime.Today.DayOfWeek)
            : Enum.GetValues<DayOfWeek>().ToList();

        foreach (var other in existingEntries)
        {
            if (string.Equals(other.ScriptId, current.ScriptId, StringComparison.OrdinalIgnoreCase)) continue;
            if (!other.Enabled) continue;
            if (!string.Equals(other.TimeOfDay?.Trim(), current.TimeOfDay.Trim(), StringComparison.OrdinalIgnoreCase)) continue;

            var otherDays = other.Unit == "Weeks"
                ? ParseWeekdays(other.Weekdays, DateTime.Today.DayOfWeek)
                : Enum.GetValues<DayOfWeek>().ToList();

            var overlap = currentDays.Intersect(otherDays).ToList();
            if (overlap.Count > 0)
            {
                string daysStr = string.Join(", ", overlap.Select(d => d.ToString()));
                return $"Warning: Conflicts with '{other.ScriptId}' at {current.TimeOfDay} on {daysStr}. ScriptSuite runs tasks with a single-instance lock; overlapping runs will be skipped (SkippedBusy).";
            }
        }

        return null;
    }
}
