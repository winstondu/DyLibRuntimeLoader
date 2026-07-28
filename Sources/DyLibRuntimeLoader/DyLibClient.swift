import Foundation

/// A thread-safe, retryable lazy reference to a dynamically loaded plugin.
public final class DyLibLazyPlugin<S: DyLibPluginSpec>: @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private let loadOperation: () throws -> S.Interface
    private var cachedInstance: S.Interface?
    private var loaded = false

    public init(
        loader: DyLibLoader = .shared,
        library: @escaping () -> DyLibLibrary
    ) {
        loadOperation = {
            try loader.load(S.self, from: library())
        }
    }

    internal init(loadOperation: @escaping () throws -> S.Interface) {
        self.loadOperation = loadOperation
    }

    public func loadIfNeeded() throws -> S.Interface {
        try lock.withLock {
            if loaded {
                return cachedInstance!
            }

            let instance = try loadOperation()
            cachedInstance = instance
            loaded = true
            return instance
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
