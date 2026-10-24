import AppKit
import AfterglowCore

extension AppDelegate {
    // Integration tests our own model, native panels and real display engine.
    // No synthesized input; only invoked by the explicit --exercise-app flag.
    func exerciseApp() {
        guard !model.fluxRunning else {
            fputs("afterglow integration held: f.lux is running; no display changes\n", stderr)
            exit(4)
        }
        let saved = model.settings
        let original: [GammaSnapshot]
        do { original = try SystemGammaDriver().capture() }
        catch { fputs("afterglow integration: no original baseline\n", stderr); exit(1) }
        model.settings = ComfortSettings(kelvin: 6000, dimming: 0.05)
        model.enable()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [self] in
            checkActiveSession(saved: saved, original: original)
        }
    }

    private func checkActiveSession(saved: ComfortSettings, original: [GammaSnapshot]) {
        var checks: [String: Bool] = [:]
        checks["activeState"] = model.enabled && model.errorMessage == nil
        let state = model.testRuntimeState
        checks["guardianAlive"] = state.guardian
        checks["baselineCaptured"] = state.baseline
        checks["oneOverlayPerScreen"] = state.overlays == NSScreen.screens.count
        let panels = NSApp.windows.filter { $0 is NSPanel && $0.level == .screenSaver }
        var dimmingOK = !panels.isEmpty
        for panel in panels {
            if abs(panel.alphaValue - 0.05) >= 0.002 || !panel.ignoresMouseEvents { dimmingOK = false }
        }
        checks["fivePercentClickThroughDimming"] = dimmingOK
        model.restore()
        checks["restoreState"] = !model.enabled && !model.recoveryPending && model.errorMessage == nil
        checks["overlaysRemoved"] = model.testRuntimeState.overlays == 0
        model.enable()
        let firstChecks = checks
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [self] in
            checkSleepResume(saved: saved, original: original, checks: firstChecks)
        }
    }

    private func checkSleepResume(saved: ComfortSettings, original: [GammaSnapshot], checks initial: [String: Bool]) {
        var checks = initial
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: NSWorkspace.shared)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.screensDidSleepNotification, object: NSWorkspace.shared)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: NSWorkspace.shared)
        checks["sleepPreservesIntent"] = !model.enabled && model.waitingForWake && !model.recoveryPending
        checks["sleepRestoresBaseline"] = model.testRuntimeState.overlays == 0 && !model.testRuntimeState.baseline
            && gammaTablesEqual(original, (try? SystemGammaDriver().capture()) ?? [])
        model.settings = ComfortSettings(kelvin: 5500, dimming: 0.03, scheduled: true)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.screensDidWakeNotification, object: NSWorkspace.shared)
        checks["waitsForSystemWake"] = !model.enabled && model.waitingForWake
        checks["graceWaitsForAllWakeSources"] = model.testWakeGraceDeadline == 0
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: NSWorkspace.shared)
        let sleepChecks = checks
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) { [self] in
            var checks = sleepChecks
            let expected = ComfortSchedule.output(settings: model.settings, date: Date())
            checks["wakeResumesWithFreshBaseline"] = model.enabled && !model.waitingForWake
                && model.testRuntimeState.guardian && model.testRuntimeState.baseline && model.errorMessage == nil
            checks["wakeUsesCurrentSchedule"] = model.output.phase == expected.phase
                && abs(model.output.kelvin - expected.kelvin) < 2
            let dates = descendantViews(window.contentView).compactMap { $0 as? NSDatePicker }
            checks["timeFieldsAreBorderless"] = dates.count == 2 && dates.allSatisfy { !$0.isBordered && !$0.isBezeled && !$0.drawsBackground }
            let scheduledBefore = model.settings.scheduled
            model.adjustKelvin(5200)
            checks["scheduledSliderAppliesImmediately"] = model.isLiveAdjustment && model.output.phase == "Live adjustment"
                && model.output.kelvin == 5200 && model.settings.scheduled == scheduledBefore
            model.resumeSchedule()
            checks["resumeScheduleEndsLiveAdjustment"] = !model.isLiveAdjustment
                && model.output == ComfortSchedule.output(settings: model.settings, date: model.clock)
            // A dock's topology notification may arrive after the first resume.
            NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
            checks["lateDisplayChangeRearmsResume"] = !model.enabled && model.waitingForWake
            let resumedChecks = checks
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) { [self] in
                var checks = resumedChecks
                checks["lateDisplayChangeResumes"] = model.enabled && !model.waitingForWake && model.testRuntimeState.guardian
                model.adjustDimming(0.04)
                checks["scheduledDimmingAppliesImmediately"] = model.isLiveAdjustment && model.output.dimming == 0.04
                NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.screensDidSleepNotification, object: NSWorkspace.shared)
                checks["sleepEndsLiveAdjustment"] = model.previewUntil == nil
                checks["newSleepResetsWakeWindow"] = model.testWakeGraceDeadline == 0
                model.restore() // Turn off, Restore, emergency shortcut and Quit share this path.
                NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.screensDidWakeNotification, object: NSWorkspace.shared)
                let finalChecks = checks
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [self] in
                    var checks = finalChecks
                    checks["manualOffCancelsAutomaticWake"] = !model.enabled && !model.waitingForWake
                        && !model.testRuntimeState.guardian && !model.testRuntimeState.baseline
                    finishExercise(saved: saved, original: original, checks: checks)
                }
            }
        }
    }

    private func finishExercise(saved: ComfortSettings, original: [GammaSnapshot], checks initial: [String: Bool]) {
        var checks = initial
        model.restore()
        checks["rapidReenableAndInterruptedFade"] = !model.enabled && !model.recoveryPending && model.errorMessage == nil
        model.settings = saved
        let restored = (try? SystemGammaDriver().capture()) ?? []
        checks["originalGammaReadback"] = gammaTablesEqual(original, restored)
        do {
            let data = try JSONSerialization.data(withJSONObject: checks, options: [.prettyPrinted, .sortedKeys])
            print(String(decoding: data, as: UTF8.self))
        } catch { fputs("afterglow integration: report encoding failed\n", stderr); exit(1) }
        fflush(stdout)
        if checks.values.contains(false) { exit(1) }
        NSApp.terminate(nil)
    }
}

private func gammaTablesEqual(_ originals: [GammaSnapshot], _ restored: [GammaSnapshot]) -> Bool {
    guard originals.count == restored.count else { return false }
    for first in originals {
        guard let second = restored.first(where: { $0.displayID == first.displayID }) else { return false }
        let a = first.red + first.green + first.blue
        let b = second.red + second.green + second.blue
        guard a.count == b.count else { return false }
        for index in a.indices { if abs(a[index] - b[index]) >= 0.005 { return false } }
    }
    return true
}

private func descendantViews(_ root: NSView?) -> [NSView] {
    guard let root else { return [] }
    return [root] + root.subviews.flatMap { descendantViews($0) }
}
