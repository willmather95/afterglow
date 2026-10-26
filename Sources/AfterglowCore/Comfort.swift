import Foundation

public struct ComfortSettings: Codable, Equatable {
    public var kelvin: Double
    public var dimming: Double
    public var scheduled: Bool
    public var bedtime: Int
    public var wake: Int
    public var fadeMinutes: Int

    public init(kelvin: Double = 3800, dimming: Double = 0.18, scheduled: Bool = false,
                bedtime: Int = 23 * 60, wake: Int = 7 * 60, fadeMinutes: Int = 90) {
        self.kelvin = kelvin.isFinite ? min(6500, max(2700, kelvin)) : 3800
        self.dimming = dimming.isFinite ? min(0.55, max(0, dimming)) : 0.18
        self.scheduled = scheduled
        self.bedtime = min(1439, max(0, bedtime))
        self.wake = min(1439, max(0, wake))
        self.fadeMinutes = min(180, max(30, fadeMinutes))
    }

    public var normalized: Self {
        Self(kelvin: kelvin, dimming: dimming, scheduled: scheduled,
             bedtime: bedtime, wake: wake, fadeMinutes: fadeMinutes)
    }
    public var scheduleIsValid: Bool {
        let night = ComfortSchedule.wrapped(wake - bedtime)
        return night >= 240 && night <= 840 && (1440 - night) >= fadeMinutes
    }
}

public struct ComfortOutput: Equatable, Sendable {
    public var kelvin: Double
    public var dimming: Double
    public var phase: String
    public var fraction: Double
    public init(kelvin: Double, dimming: Double, phase: String, fraction: Double) {
        self.kelvin = kelvin; self.dimming = dimming; self.phase = phase; self.fraction = fraction
    }
    public static let neutral = Self(kelvin: 6500, dimming: 0, phase: "Daylight", fraction: 0)
}

public enum ComfortSchedule {
    /// An explicit now override never changes the saved bedtime schedule.
    public static func effectiveOutput(settings: ComfortSettings, date: Date, previewUntil: Date?, calendar: Calendar = .current) -> ComfortOutput {
        if settings.scheduled, settings.scheduleIsValid, let end = previewUntil, date < end {
            var manual = settings; manual.scheduled = false
            var output = self.output(settings: manual, date: date, calendar: calendar)
            output.phase = "Live adjustment"
            return output
        }
        return output(settings: settings, date: date, calendar: calendar)
    }
    public static func wrapped(_ minute: Int) -> Int { (minute % 1440 + 1440) % 1440 }
    public static func output(settings raw: ComfortSettings, date: Date, calendar: Calendar = .current) -> ComfortOutput {
        let s = raw.normalized
        guard s.scheduled else { return .init(kelvin: s.kelvin, dimming: s.dimming, phase: "Your setting", fraction: 1) }
        guard s.scheduleIsValid else { return .neutral }
        for (bed, wake) in intervals(settings: s, near: date, calendar: calendar) {
            let start = bed.addingTimeInterval(-Double(s.fadeMinutes) * 60)
            let morning = wake.addingTimeInterval(-30 * 60)
            let fraction: Double
            let phase: String
            if date >= start && date < bed {
                fraction = smooth(date.timeIntervalSince(start) / bed.timeIntervalSince(start))
                phase = "Easing into evening"
            } else if date >= bed && date < wake {
                fraction = date >= morning ? smooth(wake.timeIntervalSince(date) / (30 * 60)) : 1
                phase = date >= morning ? "Returning to daylight" : "Night comfort"
            } else { continue }
            return .init(kelvin: 6500 + (s.kelvin - 6500) * fraction,
                         dimming: s.dimming * fraction, phase: phase, fraction: fraction)
        }
        return .neutral
    }
    private static func intervals(settings s: ComfortSettings, near date: Date, calendar: Calendar) -> [(Date, Date)] {
        (-2...2).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: date)),
                  let bed = calendar.date(bySettingHour: s.bedtime / 60, minute: s.bedtime % 60, second: 0, of: day,
                      matchingPolicy: .nextTime, repeatedTimePolicy: .first),
                  let wakeDay = calendar.date(byAdding: .day, value: s.wake <= s.bedtime ? 1 : 0, to: day),
                  let wake = calendar.date(bySettingHour: s.wake / 60, minute: s.wake % 60, second: 0, of: wakeDay,
                      matchingPolicy: .nextTime, repeatedTimePolicy: .first), wake > bed else { return nil }
            return (bed, wake)
        }
    }
    public static func nextWake(settings raw: ComfortSettings, date: Date, calendar: Calendar = .current) -> Date? {
        let s = raw.normalized
        guard s.scheduled, s.scheduleIsValid else { return nil }
        return intervals(settings: s, near: date, calendar: calendar).map(\.1).filter { $0 > date }.min()
    }
    public static func nextTransition(settings raw: ComfortSettings, date: Date, calendar: Calendar = .current) -> (Date, String)? {
        let s = raw.normalized
        guard s.scheduled, s.scheduleIsValid else { return nil }
        return intervals(settings: s, near: date, calendar: calendar).flatMap { bed, wake in
            [(bed.addingTimeInterval(-Double(s.fadeMinutes) * 60), "evening fade"), (bed, "night comfort"),
             (wake.addingTimeInterval(-30 * 60), "morning fade"), (wake, "daylight")]
        }.filter { $0.0 > date }.min { $0.0 < $1.0 }
    }
    public static func output(settings raw: ComfortSettings, minute: Double) -> ComfortOutput {
        let s = raw.normalized
        guard minute.isFinite else { return .neutral }
        guard s.scheduled else { return .init(kelvin: s.kelvin, dimming: s.dimming, phase: "Your setting", fraction: 1) }
        guard s.scheduleIsValid else { return .neutral }
        let now = (minute.truncatingRemainder(dividingBy: 1440) + 1440).truncatingRemainder(dividingBy: 1440)
        let sinceBed = (now - Double(s.bedtime) + 1440).truncatingRemainder(dividingBy: 1440)
        let untilBed = (Double(s.bedtime) - now + 1440).truncatingRemainder(dividingBy: 1440)
        let night = Double(wrapped(s.wake - s.bedtime))
        let fraction: Double
        let phase: String
        if sinceBed < night {
            if sinceBed >= night - 30 {
                fraction = smooth((night - sinceBed) / 30)
                phase = "Returning to daylight"
            } else { fraction = 1; phase = "Night comfort" }
        } else if untilBed <= Double(s.fadeMinutes) {
            fraction = smooth(1 - untilBed / Double(s.fadeMinutes))
            phase = "Easing into evening"
        } else { fraction = 0; phase = "Daylight" }
        return .init(kelvin: 6500 + (s.kelvin - 6500) * fraction,
                     dimming: s.dimming * fraction, phase: phase, fraction: fraction)
    }
    private static func smooth(_ value: Double) -> Double {
        let t = min(1, max(0, value)); return t * t * (3 - 2 * t)
    }
}

public struct RGBGains: Equatable {
    public var red: Float
    public var green: Float
    public var blue: Float
    // Approximate white-point controls, deliberately neutral at 6500. Not colorimetric calibration.
    public static func forKelvin(_ raw: Double) -> Self {
        let k = raw.isFinite ? min(6500, max(2700, raw)) : 6500
        if k <= 4500 {
            let t = Float((k - 2700) / 1800)
            return .init(red: 1, green: 0.64 + 0.20 * t, blue: 0.35 + 0.33 * t)
        }
        let t = Float((k - 4500) / 2000)
        return .init(red: 1, green: 0.84 + 0.16 * t, blue: 0.68 + 0.32 * t)
    }
}

public struct GammaSnapshot: Codable, Equatable {
    public let displayID: UInt32
    public let red: [Float]
    public let green: [Float]
    public let blue: [Float]
    public init(displayID: UInt32, red: [Float], green: [Float], blue: [Float]) {
        self.displayID = displayID; self.red = red; self.green = green; self.blue = blue
    }
    public var isValid: Bool {
        !red.isEmpty && red.count <= 16384 && red.count == green.count && red.count == blue.count &&
        (red + green + blue).allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 }
    }
    public func applying(_ gains: RGBGains) -> Self {
        .init(displayID: displayID, red: red.map { $0 * gains.red },
              green: green.map { $0 * gains.green }, blue: blue.map { $0 * gains.blue })
    }
}

public protocol GammaDriver: AnyObject {
    func capture() throws -> [GammaSnapshot]
    func write(_ snapshot: GammaSnapshot) throws
    func isOnline(_ displayID: UInt32) -> Bool
}
public extension GammaDriver { func isOnline(_ displayID: UInt32) -> Bool { true } }

public final class GammaSession {
    public private(set) var originals: [GammaSnapshot] = []
    private let driver: GammaDriver
    public init(driver: GammaDriver) { self.driver = driver }
    public func capture() throws {
        guard originals.isEmpty else { throw ComfortError.message("Restore the previous session before starting another.") }
        let candidate = try driver.capture()
        guard !candidate.isEmpty && candidate.allSatisfy(\.isValid) && Set(candidate.map(\.displayID)).count == candidate.count else {
            throw ComfortError.message("This display did not return a usable color baseline. No settings were changed.")
        }
        originals = candidate
    }
    public func apply(kelvin: Double) throws {
        guard !originals.isEmpty else { throw ComfortError.message("No original display settings are available.") }
        let gains = RGBGains.forKelvin(kelvin)
        do { for snapshot in originals { try driver.write(snapshot.applying(gains)) } }
        catch {
            let originalError = error
            do { try restore() }
            catch { throw ComfortError.message("Display change failed and restoration needs retry: \(error.localizedDescription)") }
            throw originalError
        }
    }
    @discardableResult public func restore() throws -> [UInt32] {
        var failures: [String] = []
        var disconnected: [UInt32] = []
        for snapshot in originals {
            // An absent display has no accessible active table. Do not deadlock connected displays or Quit.
            // Its restoration is explicitly unknown, never reported as restored.
            if !driver.isOnline(snapshot.displayID) { disconnected.append(snapshot.displayID); continue }
            do { try driver.write(snapshot) }
            catch { failures.append(error.localizedDescription) }
        }
        if failures.isEmpty { originals = [] }
        else { throw ComfortError.message("Could not restore every display: " + failures.joined(separator: "; ")) }
        return disconnected
    }
}

public enum ComfortError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case let .message(s) = self { return s }; return nil }
}
