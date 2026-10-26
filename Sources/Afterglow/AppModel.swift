import AppKit
import SwiftUI
import AfterglowCore

@MainActor
final class AppModel: ObservableObject {
    @Published var settings: ComfortSettings {
        didSet {
            if oldValue.scheduled != settings.scheduled {
                previewUntil = enabled && settings.scheduled ? ComfortSchedule.nextWake(settings: settings, date: Date()) : nil
            }
            else if oldValue.wake != settings.wake, previewUntil != nil {
                previewUntil = ComfortSchedule.nextWake(settings: settings, date: Date())
            }
            do { defaults.set(try JSONEncoder().encode(settings.normalized), forKey: "comfortSettings") }
            catch { errorMessage = "Your settings could not be saved." }
            refresh()
        }
    }
    @Published private(set) var enabled = false
    @Published private(set) var recoveryPending = false
    @Published private(set) var restorationUnconfirmed = false
    @Published private(set) var waitingForWake = false
    @Published private(set) var previewUntil: Date?
    @Published var emergencyShortcutAvailable = true
    @Published var darkInterface = true {
        didSet { defaults.set(darkInterface, forKey: "darkInterface") }
    }
    @Published private(set) var output = ComfortOutput.neutral
    @Published private(set) var clock = Date()
    @Published var errorMessage: String?
    @Published private(set) var notice = "Turn on now applies your chosen warmth immediately."
    let isPreview: Bool
    private let defaults: UserDefaults
    private let engine = DisplayEngine()
    private var clockTimer: Timer?
    private var tokens: [NSObjectProtocol] = []
    private var lastTarget: ComfortOutput?
    private var sleepState = WakeResumeState()
    private var wakeTimer: Timer?
    private var wakeGraceDeadline: TimeInterval = 0

    init(preview: Bool = false) {
        isPreview = preview
        // The app's bundle domain is already owned by .standard; a same-name suite is invalid on macOS.
        defaults = preview ? UserDefaults(suiteName: "local.afterglow.preview")! : UserDefaults.standard
        if !preview, let data = defaults.data(forKey: "comfortSettings"),
           let saved = try? JSONDecoder().decode(ComfortSettings.self, from: data) {
            settings = saved.normalized
        } else { settings = ComfortSettings() }
        if !preview, defaults.object(forKey: "darkInterface") != nil {
            darkInterface = defaults.bool(forKey: "darkInterface")
        }
        output = ComfortSchedule.output(settings: settings, date: Date())
        if !preview {
            clockTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            clockTimer?.tolerance = 2
            let workspace = NSWorkspace.shared.notificationCenter
            for (name, source) in [(NSWorkspace.willSleepNotification, WakeResumeState.Source.system),
                                   (NSWorkspace.screensDidSleepNotification, .display)] {
                tokens.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.handleSleep(source) }
                })
            }
            for (name, source) in [(NSWorkspace.didWakeNotification, WakeResumeState.Source.system),
                                   (NSWorkspace.screensDidWakeNotification, .display)] {
                tokens.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.handleWake(source) }
                })
            }
            tokens.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.handleDisplayChange()
                    }
                })
            tokens.append(workspace.addObserver(forName: NSWorkspace.didLaunchApplicationNotification,
                object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.refresh() }
                })
        }
    }
    // Synthetic UI states never acquire a display session or change real settings.
    func configurePreview(_ state: String, dimming: Double = 0.11) {
        guard isPreview else { return }
        settings = ComfortSettings(kelvin: state == "neutral" ? 6500 : 5000, dimming: min(0.55, max(0, dimming)), scheduled: state != "off")
        enabled = state == "on" || state == "waiting" || state == "neutral"
        previewUntil = state == "on" || state == "neutral" ? ComfortSchedule.nextWake(settings: settings, date: clock) : nil
        output = state == "waiting" ? .neutral : ComfortSchedule.effectiveOutput(settings: settings, date: clock, previewUntil: previewUntil)
        if state == "unconfirmed" {
            restorationUnconfirmed = true
            notice = "Connected displays restored. A disconnected display could not be checked. Extra dimming is off."
        }
        if state == "error" {
            recoveryPending = true
            errorMessage = "A display disconnected before its colors could be restored. Reconnect it, then choose Retry Restore."
        }
    }
    var displayed: ComfortOutput {
        enabled ? output : .init(kelvin: settings.kelvin, dimming: settings.dimming, phase: "Evening preview", fraction: 1)
    }
    var fluxRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: "org.herf.Flux").isEmpty }
    var testWakeGraceDeadline: TimeInterval { wakeGraceDeadline }
    var testRuntimeState: (guardian: Bool, overlays: Int, baseline: Bool) {
        (engine.guardianIsAlive, engine.overlayCount, engine.hasBaseline)
    }
    var scheduleError: String? {
        settings.scheduled && !settings.scheduleIsValid ? "Choose a sleep window between 4 and 14 hours." : nil
    }
    var isScheduledWaiting: Bool { enabled && settings.scheduled && !isLiveAdjustment && output.fraction == 0 }
    var statusTitle: String {
        if recoveryPending { return "Restore needs attention" }
        if restorationUnconfirmed { return "A display could not be checked" }
        if waitingForWake { return "Paused for sleep" }
        if !enabled { return "Off" }
        if isScheduledWaiting { return "Waiting for bedtime schedule" }
        if output.kelvin >= 6499 { return output.dimming > 0 ? "Dimming on · warmth off" : "Original screen settings" }
        return isLiveAdjustment || !settings.scheduled ? "Blue-light reduction on now" : "Blue-light reduction · scheduled"
    }
    var statusDetail: String {
        if recoveryPending { return "Restore original colors before turning on again." }
        if restorationUnconfirmed {
            return enabled ? "Your current setting is on. An earlier disconnected display's original colors remain unconfirmed." : notice
        }
        if waitingForWake { return "Your setting resumes automatically after waking." }
        if !enabled { return notice }
        if isScheduledWaiting { return "Starts at \(timeLabel(fadeStart)). Choose Turn on now to apply it sooner." }
        if output.kelvin >= 6499 { return "Move Blue-light reduction toward More for a warmer screen." }
        if isLiveAdjustment, let end = previewUntil {
            return "Applied until your next wake time, \(end.formatted(date: .omitted, time: .shortened)). Choose Follow schedule to return sooner."
        }
        return settings.scheduled ? "\(output.phase). Returns to normal by \(timeLabel(settings.wake))." : "Your chosen setting stays on until you turn it off."
    }
    var scheduleExplanation: String {
        if settings.kelvin >= 6499 && settings.dimming == 0 { return "Choose warmer colors or extra dimming to give this schedule an effect." }
        return "Starts \(settings.kelvin >= 6499 ? "dimming" : "warming") at \(timeLabel(fadeStart)), reaches your setting at \(timeLabel(settings.bedtime)), and returns to normal by \(timeLabel(settings.wake))."
    }
    var dimmingPercent: Int { Int((settings.dimming * 100).rounded()) }
    var formattedKelvin: String { String(Int((settings.kelvin / 50).rounded()) * 50) }
    var isLiveAdjustment: Bool { settings.scheduled && (previewUntil.map { $0 > clock } ?? false) }
    func adjustKelvin(_ value: Double) { beginLiveAdjustment(); settings.kelvin = value }
    func adjustDimming(_ value: Double) { beginLiveAdjustment(); settings.dimming = value }
    private func beginLiveAdjustment() {
        guard enabled, settings.scheduled, !recoveryPending, !waitingForWake else { return }
        previewUntil = ComfortSchedule.nextWake(settings: settings, date: Date())
        notice = "Your setting is applied now until your next wake time."
    }
    func previewSetting() {
        guard !isPreview, !recoveryPending, !waitingForWake else { return }
        if !enabled { enable() }
        beginLiveAdjustment()
        refresh()
    }
    func resumeSchedule() {
        previewUntil = nil
        if !enabled { enable(applyNow: false) }
        if enabled { notice = "Following your bedtime schedule." }
        refresh()
    }
    var fadeStart: Int { ComfortSchedule.wrapped(settings.bedtime - settings.fadeMinutes) }
    var nextTransition: String {
        guard settings.scheduled, settings.scheduleIsValid else { return "Enable the schedule to follow your bedtime." }
        guard let next = ComfortSchedule.nextTransition(settings: settings, date: clock) else { return "Schedule unavailable." }
        return "\(enabled ? "Next" : "When enabled"): \(next.1) at \(next.0.formatted(date: .omitted, time: .shortened))."
    }
    func timeLabel(_ minute: Int) -> String {
        let cal = Calendar.current
        let date = cal.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: clock) ?? clock
        return date.formatted(date: .omitted, time: .shortened)
    }
    func dateBinding(for key: WritableKeyPath<ComfortSettings, Int>) -> Binding<Date> {
        Binding(get: {
            let m = self.settings[keyPath: key]
            return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: self.clock) ?? self.clock
        }, set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            self.settings[keyPath: key] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        })
    }
    func toggle() {
        if enabled || waitingForWake || recoveryPending || engine.hasBaseline { restore() } else { enable() }
    }
    func enable(applyNow: Bool = true) {
        guard !isPreview, !recoveryPending else { return }
        guard !sleepState.isSleeping else {
            notice = "Your display is sleeping. Comfort resumes after wake if it was on."
            return
        }
        cancelWakeResume()
        errorMessage = nil
        guard !fluxRunning else {
            errorMessage = "f.lux is running. Quit it yourself before enabling Afterglow. Pause Night Shift too, to keep one app in control."
            return
        }
        guard NSRunningApplication.runningApplications(withBundleIdentifier: "local.afterglow.app").count <= 1 else {
            errorMessage = "Another Afterglow window is running. Quit that copy before enabling this one."; return
        }
        guard scheduleError == nil else { errorMessage = scheduleError; return }
        do {
            try engine.begin { [weak self] message in
                self?.restore()
                if self?.recoveryPending == false { self?.notice = message }
            }
            if applyNow { previewUntil = settings.scheduled ? ComfortSchedule.nextWake(settings: settings, date: Date()) : nil }
            enabled = true; recoveryPending = false; lastTarget = nil
            notice = "Comfort is on. Restore returns your captured colors immediately."
            refresh()
        } catch { errorMessage = error.localizedDescription; enabled = false; recoveryPending = engine.hasBaseline }
    }
    func restore() {
        previewUntil = nil
        cancelWakeResume()
        restoreDisplay()
    }
    @discardableResult private func restoreDisplay() -> Bool {
        enabled = false; lastTarget = nil
        do {
            let disconnected = try engine.restore()
            recoveryPending = false
            // An empty/no-op restore cannot prove an earlier disconnected display was restored.
            restorationUnconfirmed = restorationUnconfirmed || !disconnected.isEmpty
            errorMessage = nil
            notice = restorationUnconfirmed ?
                "An earlier disconnected display's original colors remain unconfirmed. Extra dimming is off." :
                "Original colors restored. Extra dimming is off."
            return !restorationUnconfirmed
        } catch { recoveryPending = engine.hasBaseline; errorMessage = error.localizedDescription; return false }
    }
    func handleSleep(_ source: WakeResumeState.Source) {
        guard !isPreview else { return }
        // Keep a still-valid Turn on now deadline across sleep. Restore cancels it explicitly.
        wakeTimer?.invalidate(); wakeTimer = nil
        wakeGraceDeadline = 0
        sleepState.sleep(source, wasEnabled: enabled)
        waitingForWake = sleepState.pending
        var confirmed = true
        if enabled || engine.hasBaseline { confirmed = restoreDisplay() }
        sleepState.restorationFinished(confirmed: confirmed)
        if !confirmed || recoveryPending || errorMessage != nil {
            cancelWakeResume()
        } else if waitingForWake {
            notice = "Paused for sleep. Comfort resumes automatically after wake."
        }
    }
    func handleWake(_ source: WakeResumeState.Source) {
        guard !isPreview else { return }
        sleepState.wake(source)
        if sleepState.canResume && wakeGraceDeadline == 0 {
            wakeGraceDeadline = ProcessInfo.processInfo.systemUptime + 30
        }
        scheduleWakeResume()
    }
    private func cancelWakeResume() {
        wakeTimer?.invalidate(); wakeTimer = nil
        sleepState.cancel()
        waitingForWake = false
        wakeGraceDeadline = 0
    }
    func handleDisplayChange() {
        if sleepState.pending {
            scheduleWakeResume()
        } else if enabled && ProcessInfo.processInfo.systemUptime < wakeGraceDeadline {
            // Docks can enumerate after the first resume. During this bounded
            // wake window, restore again before capturing the new topology.
            sleepState.prepareForDisplayChange(wasEnabled: true)
            waitingForWake = true
            let confirmed = restoreDisplay()
            sleepState.restorationFinished(confirmed: confirmed)
            if confirmed && !recoveryPending {
                notice = "Your displays are settling after wake. Comfort will resume automatically."
                scheduleWakeResume()
            } else { cancelWakeResume() }
        } else {
            pauseForSystemChange("Your displays changed. Afterglow paused so you can start a fresh session.")
        }
    }
    private func scheduleWakeResume() {
        wakeTimer?.invalidate(); wakeTimer = nil
        guard sleepState.canResume, !recoveryPending else { return }
        // Screen configuration notifications can follow wake. Debounce them before
        // capturing a new baseline so no old display IDs/calibration are reused.
        wakeTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.resumeAfterWake() }
        }
    }
    private func resumeAfterWake() {
        guard sleepState.canResume, !recoveryPending, !isPreview else { return }
        guard !NSScreen.screens.isEmpty else {
            cancelWakeResume()
            errorMessage = "No display is available after wake. Enable comfort when your display returns."
            return
        }
        // enable() reruns conflicts/schedule checks and refreshes from Date(),
        // rather than replaying the output that was active before sleep.
        let settlingUntil = wakeGraceDeadline
        enable(applyNow: false)
        if enabled {
            wakeGraceDeadline = settlingUntil
            notice = "Comfort resumed after wake and is following your current setting."
        }
    }
    private func pauseForSystemChange(_ message: String) {
        guard enabled || engine.hasBaseline else { return }
        restore()
        if errorMessage == nil { notice = message + " " + notice }
    }
    private func refresh() {
        clock = Date()
        if let end = previewUntil, clock >= end {
            previewUntil = nil
            if enabled { notice = "Your bedtime schedule resumed automatically." }
        }
        output = ComfortSchedule.effectiveOutput(settings: settings, date: clock, previewUntil: previewUntil)
        if waitingForWake, let error = scheduleError {
            restore(); errorMessage = error; return
        }
        guard enabled, !isPreview else { return }
        if fluxRunning { pauseForSystemChange("f.lux opened. Afterglow restored your settings and paused."); return }
        if let error = scheduleError { restore(); errorMessage = error; return }
        guard engine.guardianIsAlive else {
            restore()
            if !recoveryPending { errorMessage = "The recovery helper stopped. Afterglow paused. Enable to retry." }
            return
        }
        guard lastTarget != output else { return }
        lastTarget = output
        engine.transition(to: output, reducedMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) { [weak self] message in
            self?.restore()
            if self?.recoveryPending == false { self?.errorMessage = message }
        }
    }
}
