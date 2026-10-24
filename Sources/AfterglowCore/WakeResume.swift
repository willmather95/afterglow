/// In-memory intent for one running app session. Launch always remains inactive.
/// Both notification streams may overlap, duplicate, or arrive in either order.
public struct WakeResumeState: Sendable {
    public enum Source: Hashable, Sendable { case system, display }
    private var sleeping: Set<Source> = []
    public private(set) var pending = false
    public var isSleeping: Bool { !sleeping.isEmpty }
    public var canResume: Bool { pending && sleeping.isEmpty }
    public init() {}

    public mutating func sleep(_ source: Source, wasEnabled: Bool) {
        sleeping.insert(source)
        pending = pending || wasEnabled
    }
    public mutating func wake(_ source: Source) { sleeping.remove(source) }
    public mutating func prepareForDisplayChange(wasEnabled: Bool) { pending = pending || wasEnabled }
    public mutating func restorationFinished(confirmed: Bool) { if !confirmed { pending = false } }
    /// Manual Off/Restore, quit, recovery failures and conflicts cancel resume.
    public mutating func cancel() { pending = false }
}
