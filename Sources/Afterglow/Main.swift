import AppKit
import SwiftUI
import CoreGraphics
import Carbon
import Combine
import CryptoKit
import AfterglowCore
import Darwin

@main
struct AfterglowMain {
    @MainActor static func main() {
        signal(SIGPIPE, SIG_IGN)
        if CommandLine.arguments.contains("--guardian") { exit(runGuardian(fixture: false)) }
        if CommandLine.arguments.contains("--guardian-fixture") { exit(runGuardian(fixture: true)) }
        if CommandLine.arguments.contains("--hardware-smoke") || CommandLine.arguments.contains("--hardware-crash-smoke") {
            guard NSRunningApplication.runningApplications(withBundleIdentifier: "org.herf.Flux").isEmpty else {
                fputs("afterglow: f.lux is running; hardware smoke held with zero display writes\n", stderr); exit(4)
            }
            let driver = SystemGammaDriver(), session = GammaSession(driver: SystemGammaDriver()), guardian = RestorationGuardian()
            do {
                try session.capture(); let originals = session.originals
                try guardian.start(snapshots: originals)
                try session.apply(kelvin: 6000)
                if CommandLine.arguments.contains("--hardware-crash-smoke") {
                    print("CRASH-TEST-ARMED"); fflush(stdout)
                    kill(getpid(), SIGKILL)
                    exit(1)
                }
                let adjusted = try driver.capture()
                try session.restore(); try guardian.finish()
                let restored = try driver.capture()
                func maximumDelta(_ a: [GammaSnapshot], _ b: [GammaSnapshot]) -> Double {
                    guard a.count == b.count else { return .infinity }
                    var maximum: Float = 0
                    for original in a {
                        guard let other = b.first(where: { $0.displayID == original.displayID }),
                              original.red.count == other.red.count else { return .infinity }
                        for (left, right) in zip(original.red + original.green + original.blue, other.red + other.green + other.blue) {
                            maximum = max(maximum, abs(left - right))
                        }
                    }
                    return Double(maximum)
                }
                let appliedDelta = maximumDelta(originals, adjusted), restoreDelta = maximumDelta(originals, restored)
                let report: [String: Any] = ["displayCount": originals.count,
                    "appliedTableDelta": appliedDelta, "restoredTableDelta": restoreDelta,
                    "gammaReadBack": appliedDelta > 0.005 ? "changed" : "no measurable change",
                    "restoration": restoreDelta < 0.005 ? "pass" : "fail", "physicalAppearance": "requires human observation"]
                let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                print(String(decoding: data, as: UTF8.self)); exit(restoreDelta < 0.005 ? 0 : 1)
            } catch {
                do { try session.restore(); try guardian.finish() }
                catch { fputs("afterglow smoke restoration: \(error.localizedDescription)\n", stderr) }
                fputs("afterglow smoke: \(error.localizedDescription)\n", stderr); exit(1)
            }
        }
        if CommandLine.arguments.contains("--probe") {
            do {
                let snapshots = try SystemGammaDriver().capture()
                guard snapshots.allSatisfy(\.isValid), !snapshots.isEmpty else {
                    throw ComfortError.message("Display returned invalid gamma tables.")
                }
                let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
                let digest = SHA256.hash(data: try encoder.encode(snapshots)).map { String(format: "%02x", $0) }.joined()
                let result: [String: Any] = ["mode": "read-only", "displayCount": snapshots.count,
                    "tables": snapshots.map { ["displayID": $0.displayID, "entries": $0.red.count] },
                    "tableSHA256": digest, "displayWrites": 0, "physicalAppearance": "not tested"]
                let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
                print(String(decoding: data, as: UTF8.self)); exit(0)
            } catch { fputs("afterglow probe: \(error.localizedDescription)\n", stderr); exit(1) }
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static weak var shared: AppDelegate?
    let preview = CommandLine.arguments.contains("--render-preview")
    lazy var model = AppModel(preview: preview)
    var window: NSWindow!
    private var statusItem: NSStatusItem?
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var statusSubscription: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        if let iconURL = Bundle.main.url(forResource: "Afterglow", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
        buildMenus()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 840),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.title = "Afterglow"
        window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        NSApp.appearance = NSAppearance(named: model.darkInterface ? .darkAqua : .aqua)
        window.backgroundColor = .windowBackgroundColor
        window.minSize = NSSize(width: 640, height: 740)
        window.isReleasedWhenClosed = false; window.delegate = self
        window.contentView = NSHostingView(rootView: MainView(model: model).padding(.top, 12).background(Palette.paper))
        window.center(); showWindow()
        if !preview { registerEmergencyShortcut() }
        if CommandLine.arguments.contains("--exercise-app") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.exerciseApp() }
        }
        if CommandLine.arguments.contains("--paper") { model.darkInterface = false }
        if CommandLine.arguments.contains("--schedule") { model.settings.scheduled = true }
        if CommandLine.arguments.contains("--compact") { window.setContentSize(NSSize(width: 640, height: 720)) }
        if preview, let index = CommandLine.arguments.firstIndex(of: "--render-preview"), index + 1 < CommandLine.arguments.count {
            let path = CommandLine.arguments[index + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.renderPreview(path: path) }
        }
    }
    private func buildMenus() {
        let main = NSMenu()
        let applicationItem = NSMenuItem(); let appMenu = NSMenu(title: "Afterglow")
        appMenu.addItem(item("Show Afterglow", action: #selector(showWindow), key: "1"))
        let reset = item("Restore original colors", action: #selector(restoreColors), key: "0")
        reset.keyEquivalentModifierMask = [.command, .shift]; appMenu.addItem(reset)
        appMenu.addItem(.separator())
        appMenu.addItem(item("Quit Afterglow", action: #selector(quitApp), key: "q"))
        applicationItem.submenu = appMenu; main.addItem(applicationItem)
        let editItem = NSMenuItem(); let edit = NSMenu(title: "Edit")
        for (label, selector, key) in [("Undo", Selector(("undo:")), "z"), ("Cut", #selector(NSText.cut(_:)), "x"),
                                       ("Copy", #selector(NSText.copy(_:)), "c"), ("Paste", #selector(NSText.paste(_:)), "v"),
                                       ("Select All", #selector(NSText.selectAll(_:)), "a")] {
            edit.addItem(NSMenuItem(title: label, action: selector, keyEquivalent: key))
        }
        editItem.submenu = edit; main.addItem(editItem); NSApp.mainMenu = main
        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "sun.horizon", accessibilityDescription: "Afterglow display comfort")
        status.button?.toolTip = "Afterglow"
        let menu = NSMenu()
        menu.addItem(item("Show Afterglow", action: #selector(showWindow)))
        menu.addItem(item("Restore original colors", action: #selector(restoreColors)))
        menu.addItem(.separator())
        menu.addItem(item("Quit Afterglow", action: #selector(quitApp)))
        status.menu = menu; statusItem = status
        statusSubscription = model.$enabled.combineLatest(model.$recoveryPending, model.$waitingForWake).sink { [weak status] enabled, recovery, waiting in
            status?.button?.image = NSImage(systemSymbolName: recovery ? "exclamationmark.circle" : enabled ? "sun.horizon.fill" : "sun.horizon",
                                            accessibilityDescription: "Afterglow")
            status?.button?.toolTip = recovery ? "Afterglow: restoration needs attention" : waiting ? "Afterglow: resumes after wake" : enabled ? "Afterglow: comfort on" : "Afterglow: comfort off"
        }
    }
    private func item(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let result = NSMenuItem(title: title, action: action, keyEquivalent: key)
        result.target = self; return result
    }
    @objc func showWindow() { window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc func restoreColors() { model.restore() }
    @objc func quitApp() { NSApp.terminate(nil) }
    private func registerEmergencyShortcut() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { AppDelegate.shared?.restoreColors() }
            return noErr
        }, 1, &spec, nil, &eventHandler)
        let identifier = EventHotKeyID(signature: OSType(0x4146474C), id: 1)
        let registered = installed == noErr ? RegisterEventHotKey(UInt32(kVK_ANSI_R), UInt32(controlKey | optionKey | cmdKey),
                                    identifier, GetApplicationEventTarget(), 0, &hotKey) : installed
        if registered != noErr {
            model.emergencyShortcutAvailable = false
        }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model.restore()
        if model.errorMessage != nil { showWindow(); return .terminateCancel }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        return .terminateNow
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow(); return true
    }
    private func renderPreview(path: String) {
        guard let view = window.contentView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            fputs("afterglow: cannot render preview\n", stderr); exit(1)
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
        do { try data.write(to: URL(fileURLWithPath: path), options: .atomic) }
        catch { fputs("afterglow preview: \(error.localizedDescription)\n", stderr); exit(1) }
        NSApp.terminate(nil)
    }
}
