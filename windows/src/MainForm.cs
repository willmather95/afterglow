using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Runtime.InteropServices;
using System.Runtime.Serialization;
using System.Windows.Forms;
using Microsoft.Win32;

namespace Afterglow.Windows
{
    internal static class Theme
    {
        internal static readonly Color Background = SystemInformation.HighContrast ? SystemColors.Window : Color.FromArgb(24,23,20);
        internal static readonly Color Panel = SystemInformation.HighContrast ? SystemColors.Control : Color.FromArgb(32,31,27);
        internal static readonly Color Ink = SystemInformation.HighContrast ? SystemColors.WindowText : Color.FromArgb(238,232,213);
        internal static readonly Color Muted = SystemInformation.HighContrast ? SystemColors.WindowText : Color.FromArgb(183,175,154);
        internal static readonly Color Amber = SystemInformation.HighContrast ? SystemColors.Highlight : Color.FromArgb(240,174,82);
        internal static readonly Font Heading = new Font("Segoe UI", 24, FontStyle.Regular);
        internal static readonly Font Label = new Font("Consolas", 10, FontStyle.Bold);
        internal static Button Button(string text)
        {
            Button button = new Button { Text = text, AutoSize = true, MinimumSize = new Size(130,44),
                FlatStyle = FlatStyle.Flat, BackColor = Panel, ForeColor = Ink, Padding = new Padding(12,6,12,6),
                Margin = new Padding(0,4,12,4), AccessibleName = text };
            button.FlatAppearance.BorderColor = Muted; return button;
        }
        internal static Label Text(string text, Font font, Color color)
        { return new Label { Text = text, Font = font, ForeColor = color, AutoSize = true, Margin = new Padding(0,6,0,6) }; }
    }

    internal sealed class SunsetPanel : Panel
    {
        internal SunsetPanel() { DoubleBuffered = true; Height = 190; Dock = DockStyle.Top; BackColor = Theme.Panel; AccessibleName = "Afterglow sunset illustration"; }
        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e); e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            int size = Math.Min(150, Math.Min(Width - 40, Height - 40));
            Rectangle sun = new Rectangle((Width-size)/2, (Height-size)/2, size,size);
            using (Brush brush = new LinearGradientBrush(sun, Theme.Amber, Color.FromArgb(198,90,53),90)) e.Graphics.FillEllipse(brush,sun);
            using (Pen gap = new Pen(BackColor,3))
                for (int row=0;row<7;row++) { gap.Width=3+row; int y=sun.Top+size/2+row*size/16; e.Graphics.DrawLine(gap,sun.Left,y,sun.Right,y); }
        }
    }

    internal sealed class MainForm : Form
    {
        private readonly bool smoke;
        private readonly string settingsPath;
        private Settings settings;
        private readonly ComfortIntent intent = new ComfortIntent();
        private readonly OverlaySession overlays = new OverlaySession();
        private readonly System.Windows.Forms.Timer timer = new System.Windows.Forms.Timer();
        private readonly Label status, values, note, restoreHint;
        private readonly Button enable, preview;
        private readonly TrackBar warmth, dimming;
        private readonly CheckBox scheduled;
        private readonly DateTimePicker bedtime, wake;
        private readonly NumericUpDown fade;
        private readonly NotifyIcon tray;
        private bool initializing = true, quitting, hotkey;
        private string persistenceWarning, capabilityWarning;
        private bool powerNotificationsAvailable = true;
        private DateTimeOffset settleUntil;
        private IntPtr powerRegistration;
        private static readonly Guid DisplayPower = new Guid("2B84C20E-AD23-4DDF-93DB-05FFBD7EFCA5");

        internal MainForm(bool smokeTest)
        {
            smoke = smokeTest;
            settingsPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"Afterglow","settings.json");
            settings = new Settings();
            if (!smoke) try { settings = SettingsStore.Load(settingsPath); }
                catch (Exception exception)
                {
                    if (!(exception is InvalidDataException || exception is IOException || exception is UnauthorizedAccessException || exception is SerializationException || exception is ArgumentException)) throw;
                    persistenceWarning = "Saved settings could not be loaded. Adjust a control to save a new setting.";
                }
            Text = "Afterglow"; AccessibleName = "Afterglow screen comfort";
            Font = new Font("Segoe UI",10); BackColor = Theme.Background; ForeColor = Theme.Ink;
            AutoScaleMode = AutoScaleMode.Dpi; MinimumSize = new Size(600,570); ClientSize = new Size(700,800);
            StartPosition = FormStartPosition.CenterScreen;
            Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath);
            Rectangle area = Screen.PrimaryScreen.WorkingArea;
            Size = new Size(Math.Min(Width,area.Width),Math.Min(Height,area.Height));

            Panel footer = new Panel { Dock = DockStyle.Bottom, Height = 130, Padding = new Padding(22,4,22,12) };
            status = Theme.Text("Ready when you are",new Font("Segoe UI",12,FontStyle.Bold),Theme.Ink); status.Dock = DockStyle.Top;
            FlowLayoutPanel actions = new FlowLayoutPanel { Dock = DockStyle.Top, Height=58, WrapContents=false };
            enable = Theme.Button("Enable comfort"); enable.Click += delegate { if (intent.Enabled) Restore(); else Enable(); };
            Button restore = Theme.Button("Restore original"); restore.Click += delegate { Restore(); };
            actions.Controls.Add(enable); actions.Controls.Add(restore);
            restoreHint = Theme.Text("Restore original is always available above.",Font,Theme.Muted); restoreHint.Dock=DockStyle.Bottom;
            footer.Controls.Add(actions); footer.Controls.Add(status); footer.Controls.Add(restoreHint);

            Panel scroll = new Panel { Dock=DockStyle.Fill, AutoScroll=true, Padding=new Padding(24) };
            TableLayoutPanel content = new TableLayoutPanel { Dock=DockStyle.Top, AutoSize=true, ColumnCount=1, GrowStyle=TableLayoutPanelGrowStyle.AddRows };
            content.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,100));
            Add(content, Theme.Text("afterglow",Theme.Heading,Theme.Ink));
            Add(content, Theme.Text("PERSONAL LIGHT / A SOFTER END TO THE DAY",Theme.Label,Theme.Muted));
            Add(content,new SunsetPanel());
            Add(content,Theme.Text("Your evening setting",new Font(Font,FontStyle.Bold),Theme.Ink));
            values=Theme.Text("",new Font("Segoe UI",19),Theme.Ink);Add(content,values);
            Add(content,Theme.Text("WARMTH   /   CLEAR TO CANDLELIT",Theme.Label,Theme.Muted));
            warmth = Slider(100,settings.Warmth,"Warmth");Add(content,warmth);
            Add(content,Theme.Text("EXTRA DIMMING   /   ORIGINAL TO LOW LIGHT",Theme.Label,Theme.Muted));
            dimming=Slider(55,settings.Dimming,"Extra dimming");Add(content,dimming);
            scheduled=new CheckBox { Text="Ease into bedtime",AutoSize=true,Checked=settings.Scheduled,ForeColor=Theme.Ink,Margin=new Padding(0,16,0,8),AccessibleName="Use bedtime schedule" };Add(content,scheduled);
            TableLayoutPanel times=new TableLayoutPanel {AutoSize=true,ColumnCount=3,Dock=DockStyle.Top,Margin=new Padding(0,0,0,12)};
            for(int i=0;i<3;i++)times.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,33.33F));
            times.Controls.Add(Theme.Text("BEDTIME",Theme.Label,Theme.Muted),0,0);
            times.Controls.Add(Theme.Text("WAKE UP",Theme.Label,Theme.Muted),1,0);
            times.Controls.Add(Theme.Text("FADE / MIN",Theme.Label,Theme.Muted),2,0);
            bedtime=TimePicker(settings.Bedtime,"Bedtime");wake=TimePicker(settings.Wake,"Wake time");
            fade=new NumericUpDown {Minimum=30,Maximum=180,Increment=15,Value=settings.Fade,Width=110,AccessibleName="Evening fade minutes",BackColor=Theme.Panel,ForeColor=Theme.Ink};
            times.Controls.Add(bedtime,0,1);times.Controls.Add(wake,1,1);times.Controls.Add(fade,2,1);Add(content,times);
            preview=Theme.Button("Apply now");preview.Click+=delegate {
                if(intent.PreviewUntil.HasValue) intent.ResumeSchedule();
                else { Enable(); intent.Adjust(settings.Scheduled,DateTimeOffset.UtcNow); }
                RefreshComfort();
            };Add(content,preview);
            note=Theme.Text("",Font,Theme.Muted);note.MaximumSize=new Size(620,0);Add(content,note);
            Label explanation=Theme.Text("Windows uses a warm screen overlay. No display calibration or Night light settings are changed.\nClosing this window keeps Afterglow in the system tray. Open it there anytime.",Font,Theme.Muted);
            explanation.MaximumSize=new Size(620,0);Add(content,explanation);
            scroll.Controls.Add(content);Controls.Add(scroll);Controls.Add(footer);
            scroll.SizeChanged+=delegate { content.Width=Math.Max(200,scroll.ClientSize.Width-scroll.Padding.Horizontal-SystemInformation.VerticalScrollBarWidth);note.MaximumSize=new Size(content.Width,0);explanation.MaximumSize=new Size(content.Width,0); };
            ContextMenuStrip menu=new ContextMenuStrip();
            menu.Items.Add("Open Afterglow",null,delegate { ShowControls(); });
            menu.Items.Add("Restore original",null,delegate { Restore(); });
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add("Quit Afterglow",null,delegate { quitting=true;Close(); });
            tray=new NotifyIcon {Icon=Icon,Text="Afterglow: comfort off",ContextMenuStrip=menu,Visible=!smoke};
            tray.DoubleClick+=delegate { ShowControls(); };
            warmth.ValueChanged+=SettingsChanged;dimming.ValueChanged+=SettingsChanged;scheduled.CheckedChanged+=SettingsChanged;
            bedtime.ValueChanged+=SettingsChanged;wake.ValueChanged+=SettingsChanged;fade.ValueChanged+=SettingsChanged;
            timer.Interval=1000;timer.Tick+=delegate { RefreshComfort(); }; initializing=false;
            if(!smoke) timer.Start();RefreshComfort();
        }
        private static void Add(TableLayoutPanel panel,Control control) {control.Anchor=AnchorStyles.Left|AnchorStyles.Right;panel.Controls.Add(control,0,panel.RowCount++);}
        private static TrackBar Slider(int maximum,int value,string label)
        { return new TrackBar {Minimum=0,Maximum=maximum,Value=value,TickStyle=TickStyle.None,Height=42,Dock=DockStyle.Top,AccessibleName=label,BackColor=Theme.Background}; }
        private static DateTimePicker TimePicker(int minute,string label)
        {return new DateTimePicker {Format=DateTimePickerFormat.Custom,CustomFormat="HH:mm",ShowUpDown=true,Value=DateTime.Today.AddMinutes(minute),Width=110,AccessibleName=label};}
        protected override void OnLoad(EventArgs e)
        {
            base.OnLoad(e); if(smoke)return;
            hotkey=Native.RegisterHotKey(Handle,0xAF10,0x4007,0x52);
            Guid guid=DisplayPower;powerRegistration=Native.RegisterPowerSettingNotification(Handle,ref guid,0);
            ConfigureCapabilities(hotkey,powerRegistration!=IntPtr.Zero);
            SystemEvents.DisplaySettingsChanging+=DisplayChanging;SystemEvents.DisplaySettingsChanged+=DisplayChanged;
            SystemEvents.SessionSwitch+=SessionChanged;SystemEvents.TimeChanged+=ClockChanged;
            RefreshComfort();
        }
        private void ConfigureCapabilities(bool shortcutAvailable,bool displayNotifications)
        {
            powerNotificationsAvailable=displayNotifications;
            restoreHint.Text=shortcutAvailable?"Emergency restore: Ctrl+Alt+Shift+R":"Shortcut unavailable. Use Restore original or the tray menu.";
            capabilityWarning=shortcutAvailable?null:"Emergency shortcut unavailable.";
            if(!displayNotifications)capabilityWarning=(capabilityWarning==null?"":capabilityWarning+" ")+"Display sleep tracking unavailable; automatic resume is disabled.";
        }
        private void SettingsChanged(object sender,EventArgs e)
        {
            if(initializing)return;
            settings.Warmth=warmth.Value;settings.Dimming=dimming.Value;settings.Scheduled=scheduled.Checked;
            settings.Bedtime=bedtime.Value.Hour*60+bedtime.Value.Minute;settings.Wake=wake.Value.Hour*60+wake.Value.Minute;settings.Fade=(int)fade.Value;
            intent.ResumeSchedule();
            if(sender==warmth || sender==dimming)intent.Adjust(settings.Scheduled,DateTimeOffset.UtcNow);
            if(!smoke) try { SettingsStore.Save(settingsPath,settings);persistenceWarning=null; }
                catch(Exception error) { if(!(error is InvalidDataException || error is IOException || error is UnauthorizedAccessException || error is SerializationException))throw;persistenceWarning=error is InvalidDataException?error.Message:"Your setting could not be saved. It only applies to this session."; }
            RefreshComfort();
        }
        private void Enable()
        {
            try {settings.Validate();intent.Enable();}
            catch(InvalidDataException e) {persistenceWarning=e.Message;}
            RefreshComfort();
        }
        private void Restore() {intent.Restore();overlays.Clear();RefreshComfort();}
        internal void ShowControls() { Show();ShowInTaskbar=true;WindowState=FormWindowState.Normal;Activate(); }
        private void RefreshComfort()
        {
            if(IsDisposed)return;
            DateTimeOffset now=DateTimeOffset.UtcNow;
            values.Text=String.Format("{0}% warmth    /    {1}% dimming",settings.Warmth,settings.Dimming);
            enable.Text=intent.Enabled?"Turn off":"Enable comfort";enable.AccessibleName=enable.Text;
            preview.Visible=settings.Scheduled;preview.Text=intent.PreviewUntil.HasValue&&intent.PreviewUntil.Value>now?"Resume schedule":"Apply now";
            bedtime.Enabled=wake.Enabled=fade.Enabled=settings.Scheduled;
            string phase="Ready when you are";
            try
            {
                settings.Validate();enable.Enabled=preview.Enabled=true;
                ComfortOutput target=ComfortSchedule.Output(settings,now,intent.PreviewUntil,TimeZoneInfo.Local);
                if(intent.Enabled)
                {
                    phase=intent.Active&&now>=settleUntil?target.Phase:"Resumes after wake";
                    if(!smoke && intent.Active&&now>=settleUntil)overlays.Apply(settings,target.Fraction);
                    else overlays.Clear();
                }
                else overlays.Clear();
            }
            catch(Exception error)
            {
                overlays.Clear();intent.Restore();
                if(!(error is InvalidDataException || error is InvalidOperationException || error is System.ComponentModel.Win32Exception))throw;
                phase=error is InvalidDataException?error.Message:"Comfort could not be applied. Your screen overlay was removed.";
                if(error is InvalidDataException)enable.Enabled=preview.Enabled=false;
                else persistenceWarning=phase;
            }
            status.Text=phase;status.AccessibleName="Comfort status: "+phase;
            tray.Text=("Afterglow: "+phase).Length>63?"Afterglow: needs attention":"Afterglow: "+phase;
            string transientNote=persistenceWarning??(intent.PreviewUntil.HasValue&&intent.PreviewUntil.Value>now?"Applied now. Your schedule resumes in about one minute.":intent.Enabled?"Following your setting. Restore removes the overlay immediately.":"Choose Enable comfort. Your screen is unchanged.");
            note.Text=(String.IsNullOrEmpty(capabilityWarning)?"":capabilityWarning+"\n")+transientNote;
        }
        private void OnUI(Action action) {if(!IsDisposed&&IsHandleCreated)BeginInvoke(new Action(delegate {if(!IsDisposed)action();}));}
        private void Sleep(SleepSource source) {intent.Sleep(source);if(!powerNotificationsAvailable)intent.Restore();overlays.Clear();RefreshComfort();}
        private void Wake(SleepSource source) {intent.Wake(source);settleUntil=DateTimeOffset.UtcNow.AddSeconds(2);RefreshComfort();}
        private void DisplayChanging(object sender,EventArgs e) {OnUI(delegate {overlays.Clear();settleUntil=DateTimeOffset.MaxValue;});}
        private void DisplayChanged(object sender,EventArgs e) {OnUI(delegate {overlays.Clear();settleUntil=DateTimeOffset.UtcNow.AddSeconds(2);RefreshComfort();});}
        private void ClockChanged(object sender,EventArgs e) {OnUI(delegate {intent.ResumeSchedule();RefreshComfort();});}
        private void SessionChanged(object sender,SessionSwitchEventArgs e)
        {if(e.Reason==SessionSwitchReason.SessionLock)OnUI(delegate {Sleep(SleepSource.Lock);});if(e.Reason==SessionSwitchReason.SessionUnlock)OnUI(delegate {Wake(SleepSource.Lock);});}
        protected override void WndProc(ref Message message)
        {
            if(message.Msg==0x0312&&message.WParam.ToInt32()==0xAF10)Restore();
            if(message.Msg==0x0218)
            {
                int kind=message.WParam.ToInt32();
                if(kind==4)Sleep(SleepSource.System);
                if(kind==7||kind==18)Wake(SleepSource.System);
                if(kind==0x8013&&message.LParam!=IntPtr.Zero)
                {
                    Guid id=(Guid)Marshal.PtrToStructure(message.LParam,typeof(Guid));
                    if(id==DisplayPower&&Marshal.ReadInt32(message.LParam,16)==4)
                    {int state=Marshal.ReadInt32(message.LParam,20);if(state==0)Sleep(SleepSource.Display);else if(state==1||state==2)Wake(SleepSource.Display);}
                }
            }
            base.WndProc(ref message);
        }
        protected override void OnFormClosing(FormClosingEventArgs e)
        {
            if(!quitting&&!smoke&&e.CloseReason==CloseReason.UserClosing) {e.Cancel=true;Hide();ShowInTaskbar=false;return;}
            intent.Restore();overlays.Clear();base.OnFormClosing(e);
        }
        protected override void Dispose(bool disposing)
        {
            if(disposing)
            {
                timer.Dispose();overlays.Dispose();tray.Visible=false;tray.ContextMenuStrip.Dispose();tray.Dispose();
                if(hotkey)Native.UnregisterHotKey(Handle,0xAF10);
                if(powerRegistration!=IntPtr.Zero)Native.UnregisterPowerSettingNotification(powerRegistration);
                SystemEvents.DisplaySettingsChanging-=DisplayChanging;SystemEvents.DisplaySettingsChanged-=DisplayChanged;
                SystemEvents.SessionSwitch-=SessionChanged;SystemEvents.TimeChanged-=ClockChanged;
            }
            base.Dispose(disposing);
        }
        internal static int RunUISmoke(string directory)
        {
            Directory.CreateDirectory(directory);
            using(MainForm form=new MainForm(true))
            {
                form.CreateControl();form.Show();Application.DoEvents();form.PerformLayout();
                if(!form.status.Visible||!form.values.Visible)throw new InvalidOperationException("Native render observer has hidden controls.");
                foreach(int width in new int[]{700,600})
                {
                    form.ClientSize=new Size(width,Math.Min(800,Screen.PrimaryScreen.WorkingArea.Height-80));Application.DoEvents();form.PerformLayout();
                    File.AppendAllText(Path.Combine(directory,"layout.txt"),String.Format("window={0} client={1} hint={2} visible={3}\n",form.Size,form.ClientSize,form.restoreHint.Bounds,form.restoreHint.Visible));
                    Rectangle hintBounds=form.RectangleToClient(form.restoreHint.RectangleToScreen(form.restoreHint.ClientRectangle));
                    if(!form.restoreHint.Visible||!form.ClientRectangle.Contains(hintBounds))throw new InvalidOperationException("Restore hint clipped in native layout.");
                    using(Bitmap image=new Bitmap(form.Width,form.Height))
                    {form.DrawToBitmap(image,new Rectangle(0,0,form.Width,form.Height));image.Save(Path.Combine(directory,"afterglow-"+width+".png"));}
                }
                form.ConfigureCapabilities(false,false);form.warmth.Value=60;
                if(!form.note.Text.Contains("shortcut unavailable")||!form.note.Text.Contains("automatic resume is disabled")||form.restoreHint.Text.Contains("Ctrl+Alt+Shift+R"))throw new InvalidOperationException("Capability warning was hidden by a setting change.");
                form.bedtime.Value=DateTime.Today.AddHours(23);form.wake.Value=DateTime.Today.AddHours(1);form.scheduled.Checked=true;
                if(form.enable.Enabled||form.intent.Enabled)throw new InvalidOperationException("Invalid sleep window did not fail closed.");
                form.wake.Value=DateTime.Today.AddHours(7);form.ConfigureCapabilities(true,true);
                form.Enable();form.warmth.Value=70;form.scheduled.Checked=true;form.intent.Adjust(true,DateTimeOffset.UtcNow);form.RefreshComfort();
                if(form.overlays.Count!=0)throw new InvalidOperationException("UI smoke must not tint the desktop.");
                form.intent.Sleep(SleepSource.System);form.intent.Sleep(SleepSource.Display);form.intent.Wake(SleepSource.Display);
                if(form.intent.Active)throw new InvalidOperationException("Display-only wake resumed early.");
                form.intent.Wake(SleepSource.System);form.Restore();
            }
            Console.WriteLine("PASS native UI rendering and non-mutating state smoke");return 0;
        }
    }
}
