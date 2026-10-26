import Foundation
import Darwin
import AfterglowCore

struct ComfortTests {
    func testWakeIntentHandlesBothStreamsAndDuplicateSleep() {
        var state = WakeResumeState()
        expectFalse(state.pending); expectFalse(state.canResume)
        state.sleep(.display, wasEnabled: true)
        state.sleep(.system, wasEnabled: false)
        state.sleep(.display, wasEnabled: false)
        expect(state.pending); expectFalse(state.canResume)
        state.wake(.system)
        expectFalse(state.canResume)
        state.wake(.display)
        expect(state.canResume)
        state.wake(.display)
        expect(state.canResume)
        state.cancel()
        expectFalse(state.pending); expectFalse(state.canResume)
    }
    func testWakeIntentDoesNotEnableOffSessions() {
        var state = WakeResumeState()
        state.sleep(.system, wasEnabled: false); state.wake(.system)
        expectFalse(state.canResume)
        state.sleep(.display, wasEnabled: true)
        state.cancel(); state.wake(.display)
        expectFalse(state.pending); expectFalse(state.canResume)
        state.sleep(.display, wasEnabled: true); state.wake(.display)
        expect(state.canResume)
        state.sleep(.system, wasEnabled: false)
        expectFalse(state.canResume)
        state.wake(.system)
        expect(state.canResume)
    }
    func testWakeRecomputesScheduleForDifferentTimeAndDay() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try require(TimeZone(identifier: "America/Chicago"))
        let s = ComfortSettings(scheduled: true)
        let formatter = ISO8601DateFormatter()
        let night = try require(formatter.date(from: "2026-10-24T04:00:00Z"))
        let day = try require(formatter.date(from: "2026-10-24T17:00:00Z"))
        let nextNight = try require(formatter.date(from: "2026-10-25T04:00:00Z"))
        expectEqual(ComfortSchedule.output(settings: s, date: night, calendar: cal).fraction, 1)
        expectEqual(ComfortSchedule.output(settings: s, date: day, calendar: cal).fraction, 0)
        expectEqual(ComfortSchedule.output(settings: s, date: nextNight, calendar: cal).fraction, 1)
    }
    func testUnconfirmedRestorationCancelsWakeAndKeepsOff() throws {
        let driver = FakeDriver([snapshot]); let session = GammaSession(driver: driver)
        try session.capture(); try session.apply(kelvin: 2700)
        driver.offline = [snapshot.displayID]
        var state = WakeResumeState()
        state.sleep(.system, wasEnabled: true)
        state.restorationFinished(confirmed: try session.restore().isEmpty)
        expectFalse(state.pending)
        state.sleep(.display, wasEnabled: false)
        state.wake(.system); state.wake(.display)
        expectFalse(state.canResume)
        state.prepareForDisplayChange(wasEnabled: true)
        expect(state.canResume)
        state.restorationFinished(confirmed: false)
        expectFalse(state.canResume)
    }
    func testNowLastsUntilNextWakeAndHandlesDST() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try require(TimeZone(identifier: "America/Chicago"))
        let iso = ISO8601DateFormatter()
        let settings = ComfortSettings(kelvin: 3200, dimming: 0.2, scheduled: true)
        for (start, wake) in [("2026-10-26T17:00:00Z", "2026-10-27T12:00:00Z"),
                              ("2026-03-07T18:00:00Z", "2026-03-08T12:00:00Z"),
                              ("2026-10-31T17:00:00Z", "2026-11-01T13:00:00Z")] {
            let now = try require(iso.date(from: start)), expected = try require(iso.date(from: wake))
            let end = try require(ComfortSchedule.nextWake(settings: settings, date: now, calendar: cal))
            expectEqual(end, expected)
            let later = ComfortSchedule.effectiveOutput(settings: settings, date: now.addingTimeInterval(120), previewUntil: end, calendar: cal)
            expectEqual(later.kelvin, 3200); expectEqual(later.dimming, 0.2)
            expectEqual(ComfortSchedule.effectiveOutput(settings: settings, date: end, previewUntil: end, calendar: cal), .neutral)
        }
        let now = try require(iso.date(from: "2026-10-27T12:00:00Z"))
        expectEqual(ComfortSchedule.nextWake(settings: settings, date: now, calendar: cal), iso.date(from: "2026-10-28T12:00:00Z"))
        expectEqual(ComfortSchedule.nextWake(settings: ComfortSettings(scheduled: true, bedtime: 0, wake: 60), date: now, calendar: cal), nil)
    }
    func testLiveAdjustmentIsTemporaryAndPreservesSchedule() throws {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = try require(TimeZone(identifier: "America/Chicago"))
        let now = try require(ISO8601DateFormatter().date(from: "2026-10-24T17:00:00Z"))
        let settings = ComfortSettings(kelvin: 3200, dimming: 0.2, scheduled: true)
        let end = now.addingTimeInterval(60)
        let preview = ComfortSchedule.effectiveOutput(settings: settings, date: now, previewUntil: end, calendar: cal)
        expectEqual(preview.kelvin, 3200); expectEqual(preview.dimming, 0.2)
        expectEqual(preview.phase, "Live adjustment")
        expectEqual(ComfortSchedule.effectiveOutput(settings: settings, date: end, previewUntil: end, calendar: cal), .neutral)
        expectEqual(ComfortSchedule.effectiveOutput(settings: settings, date: end.addingTimeInterval(100), previewUntil: end, calendar: cal), .neutral)
        expect(settings.scheduled); expectEqual(settings.bedtime, 1380); expectEqual(settings.wake, 420)
        let invalid = ComfortSettings(scheduled: true, bedtime: 0, wake: 60)
        expectEqual(ComfortSchedule.effectiveOutput(settings: invalid, date: now, previewUntil: end, calendar: cal), .neutral)
    }
    func testUntrustedSettingsAreBounded() {
        let s = ComfortSettings(kelvin: .nan, dimming: .infinity, bedtime: -1, wake: 2000, fadeMinutes: 900)
        expectEqual(s.kelvin, 3800); expectEqual(s.dimming, 0.18)
        expectEqual(s.bedtime, 0); expectEqual(s.wake, 1439); expectEqual(s.fadeMinutes, 180)
        var decoded = ComfortSettings(); decoded.kelvin = -999; decoded.dimming = 40
        expectEqual(decoded.normalized.kelvin, 2700); expectEqual(decoded.normalized.dimming, 0.55)
    }
    func testManualDoesNotDependOnClock() {
        let s = ComfortSettings()
        expectEqual(ComfortSchedule.output(settings: s, minute: 0).kelvin, 3800)
        expectEqual(ComfortSchedule.output(settings: s, minute: 800).dimming, 0.18)
    }
    func testMidnightScheduleBoundaries() {
        let s = ComfortSettings(scheduled: true)
        expectEqual(ComfortSchedule.output(settings: s, minute: 21 * 60 + 30).fraction, 0)
        expectEqual(ComfortSchedule.output(settings: s, minute: 22 * 60 + 15).fraction, 0.5, accuracy: 0.0001)
        expectEqual(ComfortSchedule.output(settings: s, minute: 23 * 60).fraction, 1)
        expectEqual(ComfortSchedule.output(settings: s, minute: 0).fraction, 1)
        expectEqual(ComfortSchedule.output(settings: s, minute: 6 * 60 + 30).fraction, 1)
        expectEqual(ComfortSchedule.output(settings: s, minute: 6 * 60 + 45).fraction, 0.5, accuracy: 0.0001)
        expectEqual(ComfortSchedule.output(settings: s, minute: 7 * 60).fraction, 0)
        expectEqual(ComfortSchedule.output(settings: s, minute: 12 * 60).fraction, 0)
    }
    func testBedtimeAfterMidnightAndDaySleeper() {
        let s = ComfortSettings(scheduled: true, bedtime: 30, wake: 8 * 60)
        expectEqual(ComfortSchedule.output(settings: s, minute: 23 * 60 + 45).fraction, 0.5, accuracy: 0.0001)
        let day = ComfortSettings(scheduled: true, bedtime: 9 * 60, wake: 17 * 60)
        expectEqual(ComfortSchedule.output(settings: day, minute: 12 * 60).fraction, 1)
        expectEqual(ComfortSchedule.output(settings: day, minute: 22 * 60).fraction, 0)
    }
    func testInvalidSchedulesFailToNeutral() {
        let s = ComfortSettings(scheduled: true, bedtime: 0, wake: 60)
        expectFalse(s.scheduleIsValid)
        expectEqual(ComfortSchedule.output(settings: s, minute: 30), .neutral)
        expectEqual(ComfortSchedule.output(settings: .init(), minute: .nan), .neutral)
    }
    func testScheduleUsesLocalTimeAcrossDST() throws {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = try require(TimeZone(identifier: "America/Chicago"))
        let s = ComfortSettings(scheduled: true)
        for text in ["2026-11-01T06:30:00Z", "2026-11-01T07:30:00Z", "2026-03-08T08:30:00Z"] {
            let date = try require(ISO8601DateFormatter().date(from: text))
            expectEqual(ComfortSchedule.output(settings: s, date: date, calendar: cal).fraction, 1)
        }
    }
    func testScheduleHasNoStepAtBoundaries() {
        let s = ComfortSettings(scheduled: true)
        for boundary in [1290.0, 1380, 390, 420] {
            let left = ComfortSchedule.output(settings: s, minute: boundary - 0.001).fraction
            let right = ComfortSchedule.output(settings: s, minute: boundary + 0.001).fraction
            expectLess(abs(left - right), 0.00001)
        }
    }
    func testFadeDoesNotJumpOrReverseAtDSTClockChange() throws {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = try require(TimeZone(identifier: "America/Chicago"))
        let spring = ComfortSettings(scheduled: true, bedtime: 210, wake: 660)
        let fall = ComfortSettings(scheduled: true, bedtime: 150, wake: 600)
        for (s, beforeText, afterText) in [
            (spring, "2026-03-08T07:59:30Z", "2026-03-08T08:00:30Z"),
            (fall, "2026-11-01T06:59:30Z", "2026-11-01T07:00:30Z")
        ] {
            let beforeDate = try require(ISO8601DateFormatter().date(from: beforeText))
            let afterDate = try require(ISO8601DateFormatter().date(from: afterText))
            let before = ComfortSchedule.output(settings: s, date: beforeDate, calendar: cal).fraction
            let after = ComfortSchedule.output(settings: s, date: afterDate, calendar: cal).fraction
            expect(after >= before); expectLess(after - before, 0.03)
            let next = try require(ComfortSchedule.nextTransition(settings: s, date: afterDate, calendar: cal))
            expect(next.0 > afterDate)
        }
    }
    func testGammaGainsStayBoundedAndNeutralIsIdentity() {
        for k in stride(from: 2700.0, through: 6500, by: 50) {
            let g = RGBGains.forKelvin(k)
            expectEqual(g.red, 1); expect((0...1).contains(g.green)); expect((0...1).contains(g.blue))
        }
        let g = RGBGains.forKelvin(6500); expectEqual(g.green, 1); expectEqual(g.blue, 1)
    }
    private let snapshot = GammaSnapshot(displayID: 1, red: [0, 0.4, 1], green: [0, 0.5, 1], blue: [0, 0.6, 1])
    func testOriginalCalibrationIsPreserved() {
        let adjusted = snapshot.applying(.forKelvin(2700))
        expectEqual(adjusted.red, snapshot.red)
        expectEqual(adjusted.blue[1], 0.6 * 0.35, accuracy: 0.0001)
        expect(adjusted.isValid)
    }
    func testSessionDoesNotCompoundAndRestoresExactly() throws {
        let driver = FakeDriver([snapshot]); let session = GammaSession(driver: driver)
        try session.capture(); try session.apply(kelvin: 2700); let first = driver.writes.last
        try session.apply(kelvin: 2700); expectEqual(driver.writes.last, first)
        expectThrows(try session.capture())
        try session.restore(); expectEqual(driver.writes.last, snapshot); expect(session.originals.isEmpty)
    }
    func testPartialApplyRestoresAllDisplays() throws {
        let second = GammaSnapshot(displayID: 2, red: [0, 1], green: [0, 1], blue: [0, 1])
        let driver = FakeDriver([snapshot, second]); let session = GammaSession(driver: driver)
        try session.capture(); driver.failOnceAt = 2
        expectThrows(try session.apply(kelvin: 2700))
        expectEqual(Array(driver.writes.suffix(2)), [snapshot, second]); expect(session.originals.isEmpty)
    }
    func testFailedRestoreKeepsBaselineForRetry() throws {
        let driver = FakeDriver([snapshot]); let session = GammaSession(driver: driver)
        try session.capture(); driver.failOnceAt = 1
        expectThrows(try session.restore()); expectFalse(session.originals.isEmpty)
        try session.restore(); expect(session.originals.isEmpty)
    }
    func testInvalidAndDuplicateBaselinesRejected() {
        for snapshots in [[GammaSnapshot](), [snapshot, snapshot], [.init(displayID: 1, red: [.nan], green: [1], blue: [1])]] {
            let driver = FakeDriver(snapshots)
            expectThrows(try GammaSession(driver: driver).capture()); expect(driver.writes.isEmpty)
        }
    }
    func testPersistentDisconnectDoesNotBlockConnectedRestoration() throws {
        let absent = GammaSnapshot(displayID: 2, red: [0, 1], green: [0, 1], blue: [0, 1])
        let driver = FakeDriver([snapshot, absent]); let session = GammaSession(driver: driver)
        try session.capture(); try session.apply(kelvin: 2700)
        driver.offline = [2]
        let unknown = try session.restore()
        expectEqual(unknown, [2]); expectEqual(driver.writes.last, snapshot)
        expect(session.originals.isEmpty)
        driver.snapshots = [snapshot]
        try session.capture(); try session.restore()
        expect(session.originals.isEmpty)
    }
}

private final class FakeDriver: GammaDriver {
    var snapshots: [GammaSnapshot]; var writes: [GammaSnapshot] = []; var attempts = 0; var failOnceAt: Int?
    var offline: Set<UInt32> = []
    init(_ snapshots: [GammaSnapshot]) { self.snapshots = snapshots }
    func capture() throws -> [GammaSnapshot] { snapshots }
    func isOnline(_ displayID: UInt32) -> Bool { !offline.contains(displayID) }
    func write(_ snapshot: GammaSnapshot) throws {
        attempts += 1
        if failOnceAt == attempts { failOnceAt = nil; throw ComfortError.message("Injected write failure") }
        writes.append(snapshot)
    }
}


private var failedAssertions = 0
private var assertions = 0
private func record(_ passed: Bool, _ detail: String, file: StaticString, line: UInt) {
    assertions += 1
    if !passed { failedAssertions += 1; fputs("FAIL \(file):\(line): \(detail)\n", stderr) }
}
private func expect(_ condition: @autoclosure () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
    record(condition(), "expected true", file: file, line: line)
}
private func expectFalse(_ condition: @autoclosure () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
    record(!condition(), "expected false", file: file, line: line)
}
private func expectEqual<T: Equatable>(_ left: T, _ right: T, file: StaticString = #filePath, line: UInt = #line) {
    record(left == right, "\(left) != \(right)", file: file, line: line)
}
private func expectEqual<T: BinaryFloatingPoint>(_ left: T, _ right: T, accuracy: T, file: StaticString = #filePath, line: UInt = #line) {
    record(abs(left - right) <= accuracy, "\(left) differs from \(right)", file: file, line: line)
}
private func expectLess<T: Comparable>(_ left: T, _ right: T, file: StaticString = #filePath, line: UInt = #line) {
    record(left < right, "\(left) is not less than \(right)", file: file, line: line)
}
private func expectThrows<T>(_ expression: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
    do { _ = try expression(); record(false, "expected an error", file: file, line: line) }
    catch { record(true, "error observed", file: file, line: line) }
}
private func require<T>(_ value: T?) throws -> T {
    guard let value else { throw ComfortError.message("Required test fixture unavailable") }; return value
}

@main enum ChecksMain {
    static func main() {
        let checks = ComfortTests()
        let tests: [(String, () throws -> Void)] = [
            ("now lasts to next wake across DST", checks.testNowLastsUntilNextWakeAndHandlesDST),
            ("live adjustment expires without changing schedule", checks.testLiveAdjustmentIsTemporaryAndPreservesSchedule),
            ("unconfirmed restoration cancels resume", checks.testUnconfirmedRestorationCancelsWakeAndKeepsOff),
            ("sleep and wake streams", checks.testWakeIntentHandlesBothStreamsAndDuplicateSleep),
            ("manual off cancels wake intent", checks.testWakeIntentDoesNotEnableOffSessions),
            ("wake uses current schedule date", checks.testWakeRecomputesScheduleForDifferentTimeAndDay),
            ("settings bounds", checks.testUntrustedSettingsAreBounded),
            ("manual control", checks.testManualDoesNotDependOnClock),
            ("midnight boundaries", checks.testMidnightScheduleBoundaries),
            ("after midnight and daytime bedtime", checks.testBedtimeAfterMidnightAndDaySleeper),
            ("invalid schedule", checks.testInvalidSchedulesFailToNeutral),
            ("local DST", checks.testScheduleUsesLocalTimeAcrossDST),
            ("continuous boundaries", checks.testScheduleHasNoStepAtBoundaries),
            ("RGB limits and neutral", checks.testGammaGainsStayBoundedAndNeutralIsIdentity),
            ("original calibration", checks.testOriginalCalibrationIsPreserved),
            ("noncompounding and exact restoration", checks.testSessionDoesNotCompoundAndRestoresExactly),
            ("partial-apply rollback", checks.testPartialApplyRestoresAllDisplays),
            ("restoration retry", checks.testFailedRestoreKeepsBaselineForRetry),
            ("invalid baselines", checks.testInvalidAndDuplicateBaselinesRejected),
            ("persistent disconnect and new session", checks.testPersistentDisconnectDoesNotBlockConnectedRestoration),
            ("DST fade continuity and next transition", checks.testFadeDoesNotJumpOrReverseAtDSTClockChange)
        ]
        for (name, test) in tests {
            let before = failedAssertions
            do { try test() } catch { failedAssertions += 1; fputs("FAIL \(name): \(error)\n", stderr) }
            print("\(failedAssertions == before ? "PASS" : "FAIL") \(name)")
        }
        print("\(tests.count) scenarios, \(assertions) assertions, \(failedAssertions) failures")
        exit(failedAssertions == 0 ? 0 : 1)
    }
}
