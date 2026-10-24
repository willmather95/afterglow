using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Threading;
using System.Windows.Forms;

[assembly: AssemblyTitle("Afterglow")]
[assembly: AssemblyProduct("Afterglow for Windows")]
[assembly: AssemblyVersion("0.1.0.0")]
[assembly: AssemblyFileVersion("0.1.0.0")]

namespace Afterglow.Windows
{
    internal static class Program
    {
        [STAThread] internal static int Main(string[] args)
        {
            try
            {
                if(args.Length==1&&args[0]=="--self-test")return SelfTests.Run();
                if(args.Length==1&&args[0]=="--version") {Console.WriteLine("Afterglow for Windows preview 0.1.0");return 0;}
                Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);
                Application.SetUnhandledExceptionMode(UnhandledExceptionMode.ThrowException);
                if(args.Length==2&&args[0]=="--ui-smoke")return MainForm.RunUISmoke(args[1]);
                if(args.Length==2&&args[0]=="--overlay-smoke")return NativeSmoke(args[1]);
                if(args.Length==2&&args[0]=="--overlay-fixture")return OverlayFixture(args[1]);
                if(args.Length!=0)return 64;
                bool first;
                using(EventWaitHandle show=new EventWaitHandle(false,EventResetMode.AutoReset,"Local\\Afterglow.Windows.Show"))
                using(Mutex single=new Mutex(true,"Local\\Afterglow.Windows.Instance",out first))
                {
                    if(!first) {show.Set();return 0;}
                    try
                    {
                        using(MainForm form=new MainForm(false))
                        {
                            form.CreateControl();if(form.Handle==IntPtr.Zero)throw new InvalidOperationException("App window unavailable");
                            RegisteredWaitHandle wait=ThreadPool.RegisterWaitForSingleObject(show,delegate {
                                if(!form.IsDisposed&&form.IsHandleCreated)try {form.BeginInvoke(new Action(delegate {if(!form.IsDisposed)form.ShowControls();}));}catch(InvalidOperationException) { }
                            },null,Timeout.Infinite,false);
                            try {Application.Run(form);}finally {wait.Unregister(null);}
                        }
                    }
                    finally {single.ReleaseMutex();}
                }
                return 0;
            }
            catch(Exception error)
            {
                Console.Error.WriteLine("Afterglow stopped: "+error.GetType().Name);
                if(args.Length==0)MessageBox.Show("Afterglow could not continue. Its screen overlays have been removed. Reopen the app to try again.","Afterglow",MessageBoxButtons.OK,MessageBoxIcon.Error);
                return 1;
            }
        }
        private static int NativeSmoke(string directory)
        {
            Directory.CreateDirectory(directory);
            using(OverlaySession session=new OverlaySession())
            {
                session.Apply(new Settings {Warmth=20,Dimming=2},1);Application.DoEvents();
                if(session.Count!=Screen.AllScreens.Length||!session.VerifyNativeStyles())throw new InvalidOperationException("Native overlay style check failed");
                session.Clear();if(session.Count!=0)throw new InvalidOperationException("Overlay removal failed");
            }
            File.WriteAllText(Path.Combine(directory,"overlay-smoke.txt"),"PASS real native layered/click-through/no-activate windows, one per display; removed after test. Physical appearance not tested.");
            return 0;
        }
        private static int OverlayFixture(string output)
        {
            using(OverlaySession session=new OverlaySession())
            {
                session.Apply(new Settings {Warmth=10,Dimming=1},1);Application.DoEvents();
                File.WriteAllLines(output,session.Handles());
                // Only for a disposable CI test: the parent kills this owned fixture and verifies HWND destruction.
                DateTime end=DateTime.UtcNow.AddSeconds(15);
                while(DateTime.UtcNow<end) {Application.DoEvents();Thread.Sleep(20);}
            }
            return 0;
        }
    }
}
