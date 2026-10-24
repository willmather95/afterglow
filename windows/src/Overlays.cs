using System;
using System.Collections.Generic;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace Afterglow.Windows
{
    internal sealed class TintWindow : Form
    {
        internal TintWindow(Rectangle bounds)
        {
            FormBorderStyle = FormBorderStyle.None; ShowInTaskbar = false;
            AutoScaleMode = AutoScaleMode.None; TopMost = true; Bounds = bounds;
            AccessibleName = "Afterglow visual comfort layer";
        }
        protected override bool ShowWithoutActivation { get { return true; } }
        protected override CreateParams CreateParams
        {
            get
            {
                CreateParams value = base.CreateParams;
                // Layered + transparent: mouse input passes through; never activate or appear in Alt+Tab.
                value.ExStyle |= 0x00080000 | 0x00000020 | 0x08000000 | 0x00000080;
                return value;
            }
        }
        protected override void WndProc(ref Message message)
        {
            if (message.Msg == 0x0084) { message.Result = new IntPtr(-1); return; }
            if (message.Msg == 0x0021) { message.Result = new IntPtr(3); return; }
            base.WndProc(ref message);
        }
    }

    internal sealed class OverlaySession : IDisposable
    {
        private readonly List<TintWindow> windows = new List<TintWindow>();
        internal int Count { get { return windows.Count; } }
        internal void Apply(Settings settings, double fraction)
        {
            OverlayBlend blend = OverlayBlend.Create(settings, fraction);
            if (blend.Opacity < 0.0001) { Clear(); return; }
            try
            {
                if (windows.Count == 0)
                    foreach (Screen screen in Screen.AllScreens) windows.Add(new TintWindow(screen.Bounds));
                foreach (TintWindow window in windows)
                {
                    window.BackColor = blend.Color; window.Opacity = blend.Opacity;
                    if (!window.Visible) window.Show();
                }
            }
            catch { Clear(); throw; }
        }
        internal bool VerifyNativeStyles()
        {
            foreach (TintWindow window in windows)
            {
                long style = Native.GetWindowLong(window.Handle, -20).ToInt64();
                if ((style & 0x080800A0L) != 0x080800A0L || window.ShowInTaskbar) return false;
            }
            return windows.Count > 0;
        }
        internal string[] Handles()
        {
            List<string> result = new List<string>();
            foreach (TintWindow window in windows) result.Add(window.Handle.ToInt64().ToString(System.Globalization.CultureInfo.InvariantCulture));
            return result.ToArray();
        }
        internal void Clear()
        {
            foreach (TintWindow window in windows) window.Dispose();
            windows.Clear();
        }
        public void Dispose() { Clear(); }
    }

    internal static class Native
    {
        [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
        internal static extern IntPtr GetWindowLong(IntPtr window, int index);
        [DllImport("user32.dll", SetLastError = true)]
        internal static extern bool RegisterHotKey(IntPtr window, int id, uint modifiers, uint key);
        [DllImport("user32.dll")]
        internal static extern bool UnregisterHotKey(IntPtr window, int id);
        [DllImport("user32.dll", SetLastError = true)]
        internal static extern IntPtr RegisterPowerSettingNotification(IntPtr recipient, ref Guid setting, uint flags);
        [DllImport("user32.dll")]
        internal static extern bool UnregisterPowerSettingNotification(IntPtr registration);
    }
}
