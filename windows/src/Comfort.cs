using System;
using System.IO;
using System.Runtime.Serialization;
using System.Runtime.Serialization.Json;
using System.Drawing;

namespace Afterglow.Windows
{
    [DataContract]
    internal sealed class Settings
    {
        [DataMember] public int Version = 1;
        [DataMember] public int Warmth = 50;
        [DataMember] public int Dimming = 18;
        [DataMember] public bool Scheduled;
        [DataMember] public int Bedtime = 23 * 60;
        [DataMember] public int Wake = 7 * 60;
        [DataMember] public int Fade = 90;
        internal int SleepMinutes { get { return (Wake - Bedtime + 1440) % 1440; } }
        internal void Validate()
        {
            if (Version != 1 || Warmth < 0 || Warmth > 100 || Dimming < 0 || Dimming > 55
                || Bedtime < 0 || Bedtime >= 1440 || Wake < 0 || Wake >= 1440 || Fade < 30 || Fade > 180)
                throw new InvalidDataException("Saved settings are invalid. Adjust a control to save a new setting.");
            if (Scheduled && (SleepMinutes < 240 || SleepMinutes > 840))
                throw new InvalidDataException("Choose a sleep window between 4 and 14 hours.");
        }
    }

    internal static class SettingsStore
    {
        internal static Settings Load(string path)
        {
            if (!File.Exists(path)) return new Settings();
            using (FileStream input = File.OpenRead(path))
            {
                Settings result = (Settings)new DataContractJsonSerializer(typeof(Settings)).ReadObject(input);
                if (result == null) throw new InvalidDataException("Saved settings are empty.");
                result.Validate(); return result;
            }
        }
        internal static void Save(string path, Settings value)
        {
            value.Validate();
            string directory = Path.GetDirectoryName(path);
            Directory.CreateDirectory(directory);
            string temp = Path.Combine(directory, Guid.NewGuid().ToString("N") + ".tmp");
            try
            {
                using (FileStream output = File.Create(temp))
                    new DataContractJsonSerializer(typeof(Settings)).WriteObject(output, value);
                if (File.Exists(path)) File.Replace(temp, path, null);
                else File.Move(temp, path);
            }
            finally { if (File.Exists(temp)) File.Delete(temp); }
        }
    }

    internal struct ComfortOutput
    {
        internal readonly double Fraction;
        internal readonly string Phase;
        internal ComfortOutput(double fraction, string phase) { Fraction = fraction; Phase = phase; }
    }

    internal static class ComfortSchedule
    {
        internal static double Ease(double t) { t = Math.Max(0, Math.Min(1, t)); return t * t * (3 - 2 * t); }
        internal static DateTimeOffset Resolve(DateTime day, int minute, TimeZoneInfo zone)
        {
            DateTime local = DateTime.SpecifyKind(day.Date.AddMinutes(minute), DateTimeKind.Unspecified);
            int attempts = 0;
            while (zone.IsInvalidTime(local))
            {
                local = local.AddMinutes(1);
                if (++attempts > 180) throw new InvalidOperationException("Local clock could not be resolved.");
            }
            TimeSpan offset = zone.GetUtcOffset(local);
            if (zone.IsAmbiguousTime(local))
            {
                TimeSpan[] choices = zone.GetAmbiguousTimeOffsets(local);
                offset = choices[0] > choices[1] ? choices[0] : choices[1];
            }
            return new DateTimeOffset(local, offset);
        }
        internal static ComfortOutput Output(Settings settings, DateTimeOffset now, DateTimeOffset? previewUntil, TimeZoneInfo zone)
        {
            settings.Validate();
            if (!settings.Scheduled) return new ComfortOutput(1, "Comfort is on");
            if (previewUntil.HasValue && previewUntil.Value > now) return new ComfortOutput(1, "Live adjustment");
            DateTime today = TimeZoneInfo.ConvertTime(now, zone).Date;
            for (int day = -1; day <= 1; day++)
            {
                DateTime date = today.AddDays(day);
                DateTimeOffset bed = Resolve(date, settings.Bedtime, zone);
                DateTimeOffset wake = Resolve(date.AddDays(settings.Wake <= settings.Bedtime ? 1 : 0), settings.Wake, zone);
                DateTimeOffset start = bed.AddMinutes(-settings.Fade), end = wake.AddMinutes(30);
                if (now < start || now >= end) continue;
                if (now < bed) return new ComfortOutput(Ease((now - start).TotalSeconds / (bed - start).TotalSeconds), "Evening fade");
                if (now < wake) return new ComfortOutput(1, "Bedtime");
                return new ComfortOutput(1 - Ease((now - wake).TotalSeconds / (end - wake).TotalSeconds), "Morning return");
            }
            return new ComfortOutput(0, "Daylight");
        }
    }

    internal struct OverlayBlend
    {
        internal readonly double Opacity;
        internal readonly Color Color;
        internal OverlayBlend(double opacity, Color color) { Opacity = opacity; Color = color; }
        internal static OverlayBlend Create(Settings settings, double fraction)
        {
            settings.Validate(); fraction = Math.Max(0, Math.Min(1, fraction));
            double warmth = settings.Warmth / 100.0 * 0.28 * fraction;
            double dim = settings.Dimming / 100.0 * fraction;
            double alpha = 1 - (1 - dim) * (1 - warmth);
            double multiplier = alpha < 0.000001 ? 0 : (1 - dim) * warmth / alpha;
            return new OverlayBlend(alpha, Color.FromArgb((int)Math.Round(255 * multiplier),
                (int)Math.Round(158 * multiplier), (int)Math.Round(58 * multiplier)));
        }
    }

    [Flags] internal enum SleepSource { None = 0, System = 1, Display = 2, Lock = 4 }
    internal sealed class ComfortIntent
    {
        internal bool Enabled { get; private set; }
        internal SleepSource Blocked { get; private set; }
        internal DateTimeOffset? PreviewUntil { get; private set; }
        internal bool Active { get { return Enabled && Blocked == SleepSource.None; } }
        internal void Enable() { Enabled = true; Blocked = SleepSource.None; PreviewUntil = null; }
        internal void Restore() { Enabled = false; PreviewUntil = null; }
        internal void Adjust(bool scheduled, DateTimeOffset now)
        { if (Active && scheduled) PreviewUntil = now.AddMinutes(1); }
        internal void ResumeSchedule() { PreviewUntil = null; }
        internal void Sleep(SleepSource source) { Blocked |= source; PreviewUntil = null; }
        internal void Wake(SleepSource source) { Blocked &= ~source; }
    }
}
