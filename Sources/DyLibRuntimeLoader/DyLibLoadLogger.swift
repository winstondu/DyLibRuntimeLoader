import Foundation

/// Receives one event per real lazy load performed by a connection.
///
/// Pass a conforming type to `@DyLibConnect(..., logger: PluginLog.self)`.
/// Cache hits never produce events; a failed load produces one and the next
/// call retries, so every attempt is visible. Callbacks run under the
/// connection's own lock, so a logger must not call back into the connection
/// it is logging. `DyLibLoader`'s lock is never held during a callback.
public protocol DyLibLoadLogger {
    /// Called immediately before `dlopen` of the connection's image begins.
    static func willLoad(_ event: DyLibLoadStart)
    /// Called after the load finishes, on success and on failure. A failure is
    /// reported here before a non-throwing proxy requirement traps on it.
    static func didLoad(_ event: DyLibLoadResult)
}

public extension DyLibLoadLogger {
    static func willLoad(_ event: DyLibLoadStart) {}
}

public struct DyLibLoadStart: Sendable {
    /// The interface name, for example `"Animal"`.
    public let interface: String
    /// The resolved path of the connection's framework executable.
    public let path: String

    public init(interface: String, path: String) {
        self.interface = interface
        self.path = path
    }
}

public struct DyLibLoadResult: Sendable {
    public let interface: String
    public let path: String
    /// Seconds from the first call to a usable instance, measured on the
    /// monotonic uptime clock. It covers `dlopen` of the image and its
    /// dependencies, the symbol lookup, header validation, and the factory call.
    public let duration: TimeInterval
    /// `nil` on success.
    public let error: DyLibError?

    public init(interface: String, path: String, duration: TimeInterval, error: DyLibError?) {
        self.interface = interface
        self.path = path
        self.duration = duration
        self.error = error
    }
}
