import Foundation

/// A thread-safe, retryable lazy reference to a dynamically loaded plugin.
public final class DyLibLazyPlugin<S: DyLibPluginSpec>: @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private let library: () -> DyLibLibrary
    private let loadOperation: (DyLibLibrary) throws -> S.Interface
    /// A `DyLibLoadLogger` metatype, or nil. Stored erased because the protocol
    /// needs `Duration`, which is newer than this class's deployment floor.
    private let logger: Any.Type?
    private var cachedInstance: S.Interface?
    private var loaded = false

    public init(
        loader: DyLibLoader = .shared,
        library: @escaping () -> DyLibLibrary
    ) {
        self.library = library
        self.logger = nil
        loadOperation = { try loader.load(S.self, from: $0) }
    }

    /// `logger` receives one event per real load; cache hits are silent.
    @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
    public init(
        logger: (any DyLibLoadLogger.Type)?,
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
    @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
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
        guard
            #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *),
            let logger = logger as? any DyLibLoadLogger.Type
        else {
            return try loadOperation(library)
        }

        let interface = String(describing: S.Interface.self)
        logger.willLoad(DyLibLoadStart(interface: interface, path: library.path))
        let start = ContinuousClock.now
        do {
            let instance = try loadOperation(library)
            logger.didLoad(DyLibLoadResult(
                interface: interface,
                path: library.path,
                duration: start.duration(to: .now),
                error: nil
            ))
            return instance
        } catch let error as DyLibError {
            logger.didLoad(DyLibLoadResult(
                interface: interface,
                path: library.path,
                duration: start.duration(to: .now),
                error: error
            ))
            throw error
        }
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
