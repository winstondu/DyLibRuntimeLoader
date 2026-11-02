import Foundation

/// A thread-safe, retryable lazy reference to a dynamically loaded plugin.
public final class DyLibLazyPlugin<S: DyLibPluginSpec>: @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private let library: () -> DyLibLibrary
    private let loadOperation: (DyLibLibrary) throws -> S.Interface
    private let logger: (any DyLibLoadLogger.Type)?
    private var cachedInstance: S.Interface?
    private var loaded = false

    /// `logger` receives one event per real load; cache hits are silent.
    public init(
        logger: (any DyLibLoadLogger.Type)? = nil,
        loader: DyLibLoader = .shared,
        library: @escaping () -> DyLibLibrary
    ) {
        self.library = library
        self.logger = logger
        loadOperation = { try loader.load(S.self, from: $0) }
    }

    internal init(loadOperation: @escaping () throws -> S.Interface) {
        self.library = { DyLibLibrary(path: "") }
        self.logger = nil
        self.loadOperation = { _ in try loadOperation() }
    }

    /// Test seam. `loadOperation` must throw `DyLibError`, as `DyLibLoader` does.
    internal init(
        logger: (any DyLibLoadLogger.Type)?,
        path: String,
        loadOperation: @escaping () throws -> S.Interface
    ) {
        self.library = { DyLibLibrary(path: path) }
        self.logger = logger
        self.loadOperation = { _ in try loadOperation() }
    }

    public func loadIfNeeded() throws -> S.Interface {
        try lock.withLock {
            if loaded {
                return cachedInstance!
            }

            let instance = try performLoad()
            cachedInstance = instance
            loaded = true
            return instance
        }
    }

    /// Runs one real load. The logger, when set, sees both outcomes; the clock
    /// is read only when it is set. `DyLibLoader` never holds its lock here.
    private func performLoad() throws -> S.Interface {
        let library = library()
        guard let logger else {
            return try loadOperation(library)
        }

        let interface = String(describing: S.Interface.self)
        logger.willLoad(DyLibLoadStart(interface: interface, path: library.path))
        let start = DispatchTime.now().uptimeNanoseconds
        do {
            let instance = try loadOperation(library)
            logger.didLoad(DyLibLoadResult(
                interface: interface,
                path: library.path,
                duration: Self.seconds(since: start),
                error: nil
            ))
            return instance
        } catch let error as DyLibError {
            logger.didLoad(DyLibLoadResult(
                interface: interface,
                path: library.path,
                duration: Self.seconds(since: start),
                error: error
            ))
            throw error
        }
    }

    private static func seconds(since start: UInt64) -> TimeInterval {
        let elapsed = DispatchTime.now().uptimeNanoseconds &- start
        return TimeInterval(elapsed) / 1_000_000_000
    }

    public var isLoaded: Bool {
        lock.withLock { loaded }
    }
}

public protocol DyLibPluginConnection {
    associatedtype Interface

    static var library: DyLibLibrary { get }
    static func loadIfNeeded() throws -> Interface
    static var isLoaded: Bool { get }
}

public extension DyLibLibrary {
    static func framework(
        _ name: String,
        bundle: Bundle = .main,
        dependencies: [DyLibLibrary] = [],
        flags: DyLibOpenFlags = [.now, .local, .first]
    ) -> DyLibLibrary {
        let frameworksURL = bundle.privateFrameworksURL
            ?? bundle.bundleURL.appendingPathComponent("Frameworks", isDirectory: true)
        let executableURL = frameworksURL
            .appendingPathComponent("\(name).framework", isDirectory: true)
            .appendingPathComponent(name, isDirectory: false)
        return DyLibLibrary(
            path: executableURL.path,
            dependencies: dependencies,
            flags: flags
        )
    }
}
