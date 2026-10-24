# Afterglow

A warmer, dimmer screen for a softer evening. Available for Mac and Windows.

## Download Afterglow

### [Download Afterglow for Mac](https://github.com/willmather95/afterglow/releases/download/v0.1.3/Afterglow-0.1.3-Mac.zip)

Free. No account or Terminal commands needed.

**You need:** a Mac with an Apple M-series chip and macOS Sonoma (14) or newer. To check, click the Apple menu in the top-left corner of your screen, then **About This Mac**. This download does not work on Intel Macs, Windows PCs, iPhones or iPads.

### [Download Afterglow for Windows](https://github.com/willmather95/afterglow/releases/download/windows-v0.1.0/Afterglow-Windows-x64.zip)

For Windows 11 on a 64-bit Intel or AMD PC. Free. No account, Terminal or administrator permission needed.

1. Right-click the downloaded **Afterglow-Windows-x64.zip** and choose **Extract All**.
2. Open the extracted folder and double-click **Afterglow.exe**, the sunset icon.
3. Click **Enable comfort**. Adjust **Warmth** and **Extra dimming**, or turn on **Ease into bedtime**.

Closing the window keeps Afterglow beside the clock in the system tray. Open the app again to reopen its controls. **Restore original** removes the effect; **Quit** stops the app. It does not install automatic startup.

The Windows preview adds an amber tint using desktop overlays. It does not change Windows Night light or display calibration. It follows the bedtime schedule while running and handles Windows sleep/wake notifications when available. Physical sleep/wake, HDR, pointer behavior and mixed-monitor testing remain separate device checks. See the [Windows guide](windows/README.md).

This preview is unsigned. Windows or a work computer may block it. Use your organization's approved process if that happens.

## Install on a Mac

1. Click **Download Afterglow for Mac** above.
2. Open **Downloads** in Finder. Double-click **Afterglow-0.1.3-Mac.zip** to unpack it. If you already see the Afterglow app, it is unpacked.
3. Drag **Afterglow** into **Applications** in the Finder sidebar.
4. Open **Applications**, then double-click **Afterglow**, the orange sunset icon.

You do not need GitHub's green **Code** button or either **Source code** download.

### If your Mac stops it from opening

This is an early version. It has not been notarized by Apple, so your Mac may say it cannot verify the developer or check the app for harmful software.

If you downloaded it from the link above and choose to open it:

1. Try opening Afterglow once, then dismiss the warning.
2. Open the Apple menu > **System Settings** > **Privacy & Security**.
3. Scroll to the message about Afterglow and click **Open Anyway**.
4. Confirm that you want to open Afterglow. Your Mac may ask for your password or Touch ID.

[Apple's guide to opening downloaded apps](https://support.apple.com/en-us/102445) explains this check. If your Mac says the app contains malware or will damage your computer, leave it closed.

## Make your Mac screen comfortable

1. If you use f.lux or Night Shift, turn them off first.
2. Open Afterglow and click **Enable comfort**. Your screen stays unchanged until you enable it.
3. Move **Warmth** toward **Candlelit** for a warmer screen. Move **Extra dimming** toward **Low light** for a darker screen.

Want your usual screen back? Click **Restore original** or **Turn off**.

### Follow your bedtime

Turn on **Ease into bedtime**, then choose your bedtime and wake-up time. **Fade in** is how long the screen takes to warm up before bedtime.

During the day, the screen stays at its usual color. Click **Apply now** to try your evening setting for about a minute. Moving a slider while comfort is on also starts this preview. **Resume schedule** ends the preview early.

For warmth that stays on right now, turn **Ease into bedtime** off and leave comfort enabled.

### Next time you use your Mac

- Closing the window keeps Afterglow running. Click its sun icon at the top of your screen to reopen it.
- If comfort is on when your Mac sleeps, Afterglow resumes after waking with your current setting or bedtime schedule.
- After quitting Afterglow or restarting your Mac, open it from **Applications** and click **Enable comfort** again. It does not start automatically.
- To keep the icon in your Dock, right-click it while the app is running and choose **Options > Keep in Dock**.

## Privacy and cost

Afterglow runs on your computer. It sends no data, has no account and has no subscription. It is free and open source under the MIT license.

Warmth is an approximate color adjustment, not a calibrated display setting. Extra dimming adds a dark layer; your normal screen-brightness keys still work. Afterglow makes no medical or sleep-treatment claims.

<details>
<summary>For developers: build, tests and technical details</summary>

## Build and verify

Requires the installed Apple Command Line Tools with Swift 6, macOS 14+ and Apple system frameworks. Tested on this Mac with Swift 6.1.2 and an internal M5 Liquid Retina XDR display. App is locally ad-hoc signed, not notarized or App Store distributed.

```
./scripts/build.sh
.build/release/AfterglowChecks
python3 scripts/verify-guardian.py build/Afterglow.app/Contents/MacOS/Afterglow
build/Afterglow.app/Contents/MacOS/Afterglow --probe
```

The Mac's Command Line Tools omit XCTest. The project uses a dependency-free executable assertion harness; `swift test` is not its test command.

Explicit hardware tests change the display briefly, require f.lux to be absent, and must run sequentially with no other Afterglow instance enabled:

```
build/Afterglow.app/Contents/MacOS/Afterglow --hardware-smoke
build/Afterglow.app/Contents/MacOS/Afterglow --exercise-app
python3 scripts/verify-hardware-crash.py build/Afterglow.app/Contents/MacOS/Afterglow
```

`--hardware-smoke` tests gamma apply/read-back/restore. `--exercise-app` tests the real app model, click-through dimming panels, re-enable, interrupted fade and restoration. It calls our own model, not mouse/keyboard events. The crash test deliberately SIGKILLs its owned test process and verifies the original table digest returns through the independent helper. Never run these while another controller is changing the display.

## Evidence boundaries

Automated evidence can establish calculations, native panel properties, API read-back and process recovery. It cannot establish calibrated physical color, reduced eye strain or sleep benefits. Real external monitors, actual sleep/wake and hotplug, concurrent Night Shift and full VoiceOver/navigation testing remain separate hands-on checks. Native inspection and clicks were verified after fixing an app startup error. Bedtime expansion, slider adjustment and Enable succeeded. The emergency keyboard test was interrupted by user interaction and is not claimed. Full VoiceOver and keyboard navigation remain unverified.

The app uses documented CoreGraphics APIs. REA informed the investigation approach; no f.lux code was copied or incorporated. No system preferences, protected infrastructure or existing apps were modified.


### Display restoration

The app captures original display color tables before enabling comfort and restores them when you turn it off, quit, or sleep. A separate helper attempts restoration if the app crashes. Failed restoration shows Retry Restore. Disconnected displays and other apps changing color settings can limit restoration; the app reports these conditions rather than claiming success.

The app uses documented CoreGraphics APIs. No f.lux code was copied or incorporated. No third-party packages are required. This project is independent of f.lux and Apple.

</details>

## License

[MIT](LICENSE). Copyright 2026 Will Mather.
