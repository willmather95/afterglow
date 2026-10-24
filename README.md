# Afterglow

A local Mac menu-bar app for gentler nighttime viewing. Native SwiftUI/AppKit, with a low-glare interface inspired by 1980s hi-fi instruments. No third-party packages, network requests or telemetry.

## Start

With macOS 14 or newer and a Swift 6 toolchain installed, clone this repository and run `./scripts/build.sh`. Then open `build/Afterglow.app`. The first launch is a preview and does not alter your display. Quit f.lux yourself and pause Night Shift before enabling. Tune Warmth and Extra dimming, then choose Enable comfort. While comfort is on, dragging a slider applies your adjustment immediately, including during scheduled daylight. In scheduled mode this live adjustment lasts about one minute, then returns to your saved bedtime schedule. Apply now starts the same preview; Resume schedule ends it early. The settings are saved on your Mac; activation is never saved.

Warmth uses an approximate white-point curve relative to the display's captured gamma table. Kelvin is not a measured calibration. Extra dimming is a black click-through layer, capped at 55 percent; it does not change hardware backlight brightness. Use your normal brightness keys too.

Switch on Ease into bedtime to set bedtime, wake time and a 30-180 minute evening fade. The morning return lasts 30 minutes. Times are local; event dates resolve through Calendar and fade progress uses elapsed seconds across DST changes. When comfort is disabled the schedule describes what would happen when enabled, not an active service.

The sun button switches between low-glare and paper appearance. The menu-bar icon fills while comfort is active and changes to an alert symbol if restoration needs attention.

## Restore

- Use Restore original or Turn off in the window.
- Use Restore original colors from the menu bar.
- Press Shift-Command-0 while Afterglow is active.
- Use Control-Option-Command-R globally if registration succeeded. The app shows the fallback if the shortcut is unavailable.
- Quit normally to restore and remove dimming.

Closing the main window keeps the app in the menu bar. If comfort was enabled, the app restores original colors for display/system sleep, then automatically resumes after the wake notifications and display configuration settle. It captures a fresh baseline and computes the current schedule, including daylight after your wake time. Turn off, Restore, emergency restore or Quit cancels pending resume. A standalone display configuration change, f.lux conflict or recovery error still pauses safely for manual attention. Cold launch stays inactive. There is no login item and no background installation.

A separate child process holds the captured color tables. An unexpected parent exit closes its pipe and triggers restoration. Normal restoration disarms the child before a new session can begin. Helper failure stops further writes and attempts restoration. Failed restoration shows Retry Restore rather than claiming the screen is unchanged. Disconnected displays cannot be verified; connected displays are restored and the limitation remains visible. A simultaneous external gamma controller, display driver failure, shutdown or failure of both processes can exceed these protections.

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

## Open-source license

MIT. This is an independent personal display utility, not affiliated with f.lux or Apple. Source and tests are open; physical appearance depends on the display and other color controls. It makes no medical or sleep-treatment claim.
