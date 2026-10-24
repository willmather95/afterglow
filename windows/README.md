# Afterglow for Windows

A warmer, dimmer desktop with a gentle bedtime transition.

## Download and open

For Windows 11 on an Intel or AMD PC (64-bit/x64).

1. [Download Afterglow for Windows](https://github.com/willmather95/afterglow/releases/download/windows-v0.1.0/Afterglow-Windows-x64.zip).
2. Right-click the ZIP in Downloads and choose Extract All.
3. Open the extracted folder and double-click Afterglow.exe.
4. Choose Enable comfort, then adjust Warmth and Extra dimming.

No account, Terminal, administrator permission, service or extra runtime installation is needed on Windows 11. Keep the folder somewhere you can find it. You can pin Afterglow to Start or the taskbar.

This early preview is unsigned. If Windows or your work computer blocks it, use your organization's approved process. Do not disable security controls or run it as administrator.

## Use it

- Warmth adds a gentle amber tint. Extra dimming darkens the desktop.
- Ease into bedtime gradually applies the setting before bedtime and returns to clear after waking.
- During scheduled daylight, Apply now or a slider adjustment previews your evening setting for about one minute. Resume schedule ends it sooner.
- Turn off Ease into bedtime for continuous manual comfort.
- Restore original removes the effect immediately. Ctrl+Alt+Shift+R also restores if the shortcut was available at startup.
- Closing the window keeps Afterglow running in the system tray beside the clock. Double-click its sun icon to reopen it; it may be under the small hidden-icons arrow. Open the app again to reopen its controls too.
- Quit from the tray menu to stop completely. After quitting or restarting your PC, open Afterglow and enable comfort again. It does not install automatic startup.
- While the app remains open, enabled comfort resumes after system/display sleep or unlocking and follows the current schedule. Display changes wait briefly before rebuilding the effect for connected screens.

## What the Windows effect does

This version uses click-through desktop overlays. Warmth is a tint, not a calibrated white point, and does not change Windows Night light, your graphics driver, hardware brightness or display calibration. It sends no data and makes no medical or sleep-benefit claims.

The effect applies to ordinary desktop windows. Secure Windows screens, exclusive-fullscreen games, HDR appearance and virtual desktops require device testing. Screenshots and screen sharing may include the tint. Other always-on-top applications can appear above it.

Turning off, quitting or an unexpected process exit removes the overlay windows; there is no altered gamma table to recover. This approach follows Microsoft's warning about unreliable gamma-ramp APIs, including undefined HDR behavior: https://learn.microsoft.com/en-us/windows/win32/api/wingdi/nf-wingdi-setdevicegammaramp

## Build and proof boundaries

On Windows, run windows/Package.ps1 from a source checkout. It uses the Windows .NET Framework compiler and system assemblies, with no third-party packages. The packaged app can run --self-test. CI-only windows/Test-Package.ps1 checks the extracted app, renders native UI, verifies layered/no-activate/click-through window styles, and verifies Windows destroys overlays after the owning test process is killed.

The --overlay-smoke and --overlay-fixture modes briefly tint a disposable test desktop. Normal launch starts inactive. Never confuse automated window/API checks with an actual display appearance, mouse/touch, HDR, Narrator, hotplug or physical sleep/wake test on your PC. Those remain separate acceptance checks.

MIT license. Independent of Apple, Microsoft and f.lux.
