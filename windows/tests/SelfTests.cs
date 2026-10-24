using System;
using System.IO;

namespace Afterglow.Windows
{
    internal static class SelfTests
    {
        private static int assertions;
        private static void Check(bool value,string label) {assertions++;if(!value)throw new InvalidOperationException("FAIL "+label);}
        private static DateTimeOffset At(int hour,int minute) {return new DateTimeOffset(2026,10,24,hour,minute,0,TimeSpan.Zero);}
        internal static int Run()
        {
            Settings s=new Settings {Scheduled=true};TimeZoneInfo zone=TimeZoneInfo.Utc;
            Check(ComfortSchedule.Output(s,At(12,0),null,zone).Fraction==0,"daylight neutral");
            Check(ComfortSchedule.Output(s,At(23,0),null,zone).Fraction==1,"bedtime full");
            Check(ComfortSchedule.Output(s,At(22,15),null,zone).Fraction==0.5,"evening midpoint");
            Check(ComfortSchedule.Output(s,At(7,15),null,zone).Fraction==0.5,"morning midpoint");
            Check(ComfortSchedule.Output(s,At(7,30),null,zone).Fraction==0,"morning end");
            Check(ComfortSchedule.Output(s,At(12,0),At(12,1),zone).Phase=="Live adjustment","preview during daylight");
            Check(ComfortSchedule.Output(s,At(12,1),At(12,1),zone).Fraction==0,"preview expires");
            Check(s.Bedtime==1380&&s.Wake==420&&s.Scheduled,"preview keeps schedule");
            for(int minute=0;minute<1440;minute++)
            {
                ComfortOutput value=ComfortSchedule.Output(s,At(0,0).AddMinutes(minute),null,zone);
                Check(value.Fraction>=0&&value.Fraction<=1,"fraction bounds");
                OverlayBlend blend=OverlayBlend.Create(s,value.Fraction);
                Check(blend.Opacity>=0&&blend.Opacity<=0.676001,"overlay opacity bounds");
            }
            s.Bedtime=9*60;s.Wake=17*60;
            Check(ComfortSchedule.Output(s,At(12,0),null,zone).Fraction==1,"daytime sleep");
            s.Bedtime=0;s.Wake=8*60;
            Check(ComfortSchedule.Output(s,At(23,15),null,zone).Fraction==0.5,"midnight bedtime fade");
            s.Bedtime=23*60;s.Wake=60;bool invalid=false;try {s.Validate();}catch(InvalidDataException) {invalid=true;}
            Check(invalid,"short sleep rejected");s=new Settings {Scheduled=true};
            TimeZoneInfo chicago=TimeZoneInfo.FindSystemTimeZoneById("Central Standard Time");
            DateTimeOffset gap=ComfortSchedule.Resolve(new DateTime(2026,3,8),150,chicago);
            Check(TimeZoneInfo.ConvertTime(gap,chicago).Hour==3,"DST nonexistent time advanced");
            DateTimeOffset ambiguous=ComfortSchedule.Resolve(new DateTime(2026,11,1),90,chicago);
            Check(ambiguous.Offset==TimeSpan.FromHours(-5),"DST first occurrence selected");
            DateTimeOffset springNow=new DateTimeOffset(2026,3,8,7,30,0,TimeSpan.Zero);
            Check(ComfortSchedule.Output(s,springNow,null,chicago).Fraction==1,"DST sleep remains active");
            s.Warmth=100;s.Dimming=55;OverlayBlend maximum=OverlayBlend.Create(s,1);
            Check(Math.Abs(maximum.Opacity-.676)<.00001,"maximum never opaque");
            s.Warmth=0;s.Dimming=0;Check(OverlayBlend.Create(s,1).Opacity==0,"zero settings clear");
            s.Dimming=55;Check(Math.Abs(OverlayBlend.Create(s,1).Opacity-.55)<.00001,"dimming exact without tint");
            s=new Settings();s.Dimming=-1;invalid=false;try{s.Validate();}catch(InvalidDataException){invalid=true;}Check(invalid,"invalid setting not clamped silently");
            ComfortIntent intent=new ComfortIntent();Check(!intent.Active,"cold start inactive");intent.Enable();intent.Adjust(true,At(12,0));
            intent.Sleep(SleepSource.System);intent.Sleep(SleepSource.Display);intent.Wake(SleepSource.Display);
            Check(!intent.Active&&intent.Enabled&&!intent.PreviewUntil.HasValue,"sleep preserves intent and clears preview");
            intent.Enable();intent.Adjust(true,At(12,0));Check(!intent.Active,"apply now cannot clear missing system wake");
            intent.Wake(SleepSource.System);Check(intent.Active,"all wake sources resume");
            intent.Sleep(SleepSource.Lock);intent.Restore();intent.Wake(SleepSource.Lock);Check(!intent.Active,"manual off cancels resume");
            intent.Enable();intent.Adjust(true,At(12,0));intent.ResumeSchedule();Check(!intent.PreviewUntil.HasValue,"resume schedule clears preview");
            string directory=Path.Combine(Path.GetTempPath(),"afterglow-test-"+Guid.NewGuid().ToString("N"));string path=Path.Combine(directory,"settings.json");
            try
            {
                Settings saved=new Settings {Warmth=72,Dimming=23,Scheduled=true};SettingsStore.Save(path,saved);
                Settings loaded=SettingsStore.Load(path);Check(loaded.Warmth==72&&loaded.Dimming==23&&loaded.Scheduled,"settings roundtrip");
                saved.Warmth=34;SettingsStore.Save(path,saved);Check(SettingsStore.Load(path).Warmth==34,"atomic replacement");
                File.WriteAllText(path,"{}");invalid=false;try{SettingsStore.Load(path);}catch(InvalidDataException){invalid=true;}Check(invalid,"empty document rejected");
            }
            finally {if(Directory.Exists(directory))Directory.Delete(directory,true);}
            Console.WriteLine("PASS "+assertions+" assertions: schedule, DST, blend, wake intent and persistence");return 0;
        }
    }
}
