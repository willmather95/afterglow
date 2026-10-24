import AppKit
import CoreGraphics
import AfterglowCore
import Darwin

final class SystemGammaDriver: GammaDriver {
    func isOnline(_ displayID: UInt32) -> Bool { CGDisplayIsOnline(displayID) != 0 }
    func capture() throws -> [GammaSnapshot] {
        var count: UInt32 = 0
        try check(CGGetOnlineDisplayList(0, nil, &count), action: "list displays")
        guard count > 0 && count <= 32 else { throw ComfortError.message("No supported display is connected.") }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        try check(CGGetOnlineDisplayList(count, &ids, &count), action: "read displays")
        return try ids.prefix(Int(count)).map { id in
            let capacity = CGDisplayGammaTableCapacity(id)
            guard capacity > 0 && capacity <= 16384 else {
                throw ComfortError.message("Display \(id) does not expose a usable color table.")
            }
            var red = [Float](repeating: 0, count: Int(capacity))
            var green = red, blue = red, used: UInt32 = 0
            try check(CGGetDisplayTransferByTable(id, capacity, &red, &green, &blue, &used), action: "capture original colors")
            return GammaSnapshot(displayID: id, red: Array(red.prefix(Int(used))),
                                 green: Array(green.prefix(Int(used))), blue: Array(blue.prefix(Int(used))))
        }
    }
    func write(_ snapshot: GammaSnapshot) throws {
        guard snapshot.isValid else { throw ComfortError.message("The display baseline is invalid.") }
        guard CGDisplayIsOnline(snapshot.displayID) != 0 else {
            throw ComfortError.message("A display disconnected before its colors could be restored.")
        }
        let code = snapshot.red.withUnsafeBufferPointer { r in
            snapshot.green.withUnsafeBufferPointer { g in
                snapshot.blue.withUnsafeBufferPointer { b in
                    CGSetDisplayTransferByTable(snapshot.displayID, UInt32(snapshot.red.count), r.baseAddress, g.baseAddress, b.baseAddress)
                }
            }
        }
        try check(code, action: "set display colors")
    }
    private func check(_ code: CGError, action: String) throws {
        guard code == .success else {
            throw ComfortError.message("macOS could not \(action) (code \(code.rawValue)).")
        }
    }
}

// A separate process waits for the parent's pipe to close, including on SIGKILL.
// It receives only gamma tables, never screen contents or personal information.
final class RestorationGuardian {
    private var process: Process?
    private var input: Pipe?
    private var expectedStop = false
    var onUnexpectedExit: (() -> Void)?
    var isAlive: Bool { process?.isRunning == true }
    var hasProcess: Bool { process != nil }

    func start(snapshots: [GammaSnapshot]) throws {
        guard process == nil else { throw ComfortError.message("The previous recovery helper is still running.") }
        let child = Process(), stdin = Pipe(), stdout = Pipe()
        child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        child.arguments = ["--guardian"]
        child.standardInput = stdin; child.standardOutput = stdout
        child.standardError = FileHandle.standardError
        try child.run()
        // Parent must not retain the child's reader. EOF is the recovery signal.
        try stdin.fileHandleForReading.close()
        try stdout.fileHandleForWriting.close()
        process = child; input = stdin
        expectedStop = false
        child.terminationHandler = { [weak self] ended in
            DispatchQueue.main.async {
                guard let self, !self.expectedStop,
                      self.process?.processIdentifier == ended.processIdentifier else { return }
                self.onUnexpectedExit?()
            }
        }
        do {
            let data = try JSONEncoder().encode(snapshots) + Data([10])
            try stdin.fileHandleForWriting.write(contentsOf: data)
            var descriptor = pollfd(fd: stdout.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
            guard poll(&descriptor, 1, 3000) > 0 else {
                throw ComfortError.message("The recovery helper did not become available. Your display was not changed.")
            }
            // Foundation read(upToCount:) can wait to fill the entire request on a live pipe.
            // A single POSIX read returns the bytes that poll reported, without waiting for EOF.
            var buffer = [UInt8](repeating: 0, count: 64)
            let received = Darwin.read(descriptor.fd, &buffer, buffer.count)
            guard received > 0, String(decoding: buffer.prefix(received), as: UTF8.self).hasPrefix("READY\n") else {
                throw ComfortError.message("The recovery helper returned an invalid handshake. Your display was not changed.")
            }
            try stdout.fileHandleForReading.close()
        } catch { try? finish(); throw error }
    }
    func finish() throws {
        expectedStop = true
        if process?.isRunning == true { try? input?.fileHandleForWriting.write(contentsOf: Data("DISARM\n".utf8)) }
        try? input?.fileHandleForWriting.close()
        input = nil
        // Caller has restored. Disarm avoids a late second write after a new session starts.
        // Never wait indefinitely on the UI thread for a helper or display API.
        if let child = process {
            let deadline = Date().addingTimeInterval(1)
            while child.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
            if child.isRunning {
                child.terminate()
                let grace = Date().addingTimeInterval(0.2)
                while child.isRunning && Date() < grace { Thread.sleep(forTimeInterval: 0.01) }
            }
            if child.isRunning { kill(child.processIdentifier, SIGKILL) }
            let final = Date().addingTimeInterval(0.2)
            while child.isRunning && Date() < final { Thread.sleep(forTimeInterval: 0.01) }
            guard !child.isRunning else { throw ComfortError.message("Recovery helper has not exited. Retry Restore before starting again.") }
        }
        process = nil
    }
}

func runGuardian(fixture: Bool) -> Int32 {
    guard let line = readLine(), line.utf8.count <= 8_000_000,
          let data = line.data(using: .utf8),
          let snapshots = try? JSONDecoder().decode([GammaSnapshot].self, from: data),
          !snapshots.isEmpty, snapshots.count <= 32, snapshots.allSatisfy(\.isValid) else {
        fputs("afterglow: invalid recovery baseline\n", stderr); return 2
    }
    print("READY"); fflush(stdout)
    var disarmed = false
    while let command = readLine() { if command == "DISARM" { disarmed = true } }
    if disarmed {
        if fixture { print("DISARMED"); fflush(stdout) }
        return 0
    }
    if fixture { print("RESTORED \(snapshots.count)"); fflush(stdout); return 0 }
    let driver = SystemGammaDriver()
    var failure = false
    for snapshot in snapshots {
        if !driver.isOnline(snapshot.displayID) {
            fputs("afterglow recovery: disconnected display restoration is unknown\n", stderr); continue
        }
        do { try driver.write(snapshot) }
        catch { failure = true; fputs("afterglow recovery: \(error.localizedDescription)\n", stderr) }
    }
    return failure ? 3 : 0
}

@MainActor
final class DisplayEngine {
    private let session = GammaSession(driver: SystemGammaDriver())
    private let guardian = RestorationGuardian()
    private var overlays: [NSPanel] = []
    private var animation: Timer?
    private var current = ComfortOutput.neutral
    private var active = false
    var hasBaseline: Bool { !session.originals.isEmpty || guardian.hasProcess }
    var guardianIsAlive: Bool { guardian.isAlive }
    var overlayCount: Int { overlays.count }

    func begin(onFailure: @escaping (String) -> Void) throws {
        guard !active, !hasBaseline else { throw ComfortError.message("Restore before starting a new session.") }
        try session.capture()
        guardian.onUnexpectedExit = { onFailure("The recovery helper stopped. Afterglow has paused and restored connected displays.") }
        do { try guardian.start(snapshots: session.originals) }
        catch { _ = try? session.restore(); throw error }
        active = true; current = .neutral
        overlays = NSScreen.screens.map { screen in
            let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.isOpaque = false; panel.backgroundColor = .black; panel.hasShadow = false
            panel.ignoresMouseEvents = true; panel.hidesOnDeactivate = false
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.alphaValue = 0; panel.isReleasedWhenClosed = false
            panel.setAccessibilityElement(false)
            return panel
        }
    }
    func transition(to target: ComfortOutput, reducedMotion: Bool, onFailure: @escaping (String) -> Void) {
        animation?.invalidate(); animation = nil
        guard active else { return }
        guard guardian.isAlive else { onFailure("The recovery helper stopped. Afterglow has paused."); return }
        let start = current, startDate = Date(), duration = reducedMotion ? 0.25 : 0.8
        let timer = Timer(timeInterval: 1 / 24, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, self.active else { timer.invalidate(); return }
                guard self.guardian.isAlive else {
                    timer.invalidate(); self.animation = nil
                    onFailure("The recovery helper stopped. Afterglow has paused."); return
                }
                let t = min(1, Date().timeIntervalSince(startDate) / duration)
                let eased = t * t * (3 - 2 * t)
                let value = ComfortOutput(kelvin: start.kelvin + (target.kelvin - start.kelvin) * eased,
                                          dimming: start.dimming + (target.dimming - start.dimming) * eased,
                                          phase: target.phase, fraction: target.fraction)
                do {
                    try self.session.apply(kelvin: value.kelvin)
                    for overlay in self.overlays {
                        overlay.alphaValue = min(0.55, max(0, value.dimming))
                        if overlay.alphaValue > 0 { overlay.orderFrontRegardless() }
                        else { overlay.orderOut(nil) }
                    }
                    self.current = value
                    if t >= 1 { timer.invalidate(); self.animation = nil }
                } catch { timer.invalidate(); self.animation = nil; onFailure(error.localizedDescription) }
            }
        }
        timer.tolerance = 0.005
        animation = timer; RunLoop.main.add(timer, forMode: .common)
    }
    @discardableResult func restore() throws -> [UInt32] {
        animation?.invalidate(); animation = nil; active = false
        overlays.forEach { $0.orderOut(nil); $0.close() }; overlays = []
        do {
            let disconnected = try session.restore()
            try guardian.finish(); current = .neutral
            return disconnected
        } catch {
            // Retain the live helper and original baseline for explicit retry.
            throw error
        }
    }
}
