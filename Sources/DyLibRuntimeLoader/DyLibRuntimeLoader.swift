import Darwin
import Foundation

public protocol DyLibPluginSpec {
    associatedtype Interface
    static var symbolName: String { get }
}

public enum DyLibABI {
    public static let current: Int32 = 1
}

final class DyLibPluginEntry {
    let specType: Any.Type
    let makeInstance: () -> Any

    init(specType: Any.Type, makeInstance: @escaping () -> Any) {
        self.specType = specType
        self.makeInstance = makeInstance
    }
}

/// Fixed-layout data returned by every plugin entry point. The host validates
/// this header before interpreting `box` as a Swift object.
@frozen
public struct DyLibEntryHeader {
    public static let expectedMagic: UInt32 = 0x4459_4C42 // "DYLB"

    public var magic: UInt32
    public var abiVersion: Int32
    public var box: UnsafeMutableRawPointer

    public init(magic: UInt32, abiVersion: Int32, box: UnsafeMutableRawPointer) {
        self.magic = magic
        self.abiVersion = abiVersion
        self.box = box
    }
}

public func dyLibMakeEntry<S: DyLibPluginSpec>(
    spec: S.Type,
    factory: @escaping () -> S.Interface
) -> UnsafeMutableRawPointer {
    let box = Unmanaged.passRetained(
        DyLibPluginEntry(specType: S.self, makeInstance: { factory() })
    ).toOpaque()
    let header = UnsafeMutablePointer<DyLibEntryHeader>.allocate(capacity: 1)
    header.initialize(
        to: DyLibEntryHeader(
            magic: DyLibEntryHeader.expectedMagic,
            abiVersion: DyLibABI.current,
            box: box
        )
    )
    return UnsafeMutableRawPointer(header)
}

/// Native `dlopen` options. `.first` confines `dlsym(handle, ...)` to that
/// image instead of allowing an entry point to resolve from a dependency.
public struct DyLibOpenFlags: OptionSet, Sendable {
    public let rawValue: Int32

    public init(rawValue: Int32) {
        self.rawValue = rawValue
    }

    public static let lazy = DyLibOpenFlags(rawValue: RTLD_LAZY)
    public static let now = DyLibOpenFlags(rawValue: RTLD_NOW)
    public static let global = DyLibOpenFlags(rawValue: RTLD_GLOBAL)
    public static let local = DyLibOpenFlags(rawValue: RTLD_LOCAL)
    public static let first = DyLibOpenFlags(rawValue: RTLD_FIRST)
}

public struct DyLibLibrary: Sendable {
    public let path: String
    public let dependencies: [DyLibLibrary]
    /// Flags used when this path is first opened while resident in the registry.
    /// Later opens of the same canonical path reuse the image, so the first flags win.
    public let flags: DyLibOpenFlags

    public init(
        path: String,
        dependencies: [DyLibLibrary] = [],
        flags: DyLibOpenFlags = [.now, .local, .first]
    ) {
        self.path = path
        self.dependencies = dependencies
        self.flags = flags
    }
}

public struct DyLibHandle: Hashable, Sendable {
    public let path: String
    internal let id: UUID
    internal let retainedPaths: [String]

    internal init(path: String, id: UUID, retainedPaths: [String]) {
        self.path = path
        self.id = id
        self.retainedPaths = retainedPaths
    }
}

public enum DyLibError: Error, Equatable {
    case failedToOpen(path: String, reason: String)
    case symbolNotFound(symbol: String, path: String)
    case invalidEntry(symbol: String, path: String)
    case abiMismatch(expected: Int32, found: Int32)
    case specTypeMismatch(expected: String, found: String)
    case dependencyCycle(path: [String])
    case notLoaded(path: String)
}

extension DyLibError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .failedToOpen(let path, let reason):
            return "Failed to open dynamic library at \(path): \(reason)"
        case .symbolNotFound(let symbol, let path):
            return "Symbol \(symbol) was not found in dynamic library at \(path)"
        case .invalidEntry(let symbol, let path):
            return "Symbol \(symbol) in dynamic library at \(path) returned an invalid DyLib entry header"
        case .abiMismatch(let expected, let found):
            return "Dynamic library ABI mismatch: expected \(expected), found \(found)"
        case .specTypeMismatch(let expected, let found):
            return "Plugin spec type mismatch: expected \(expected), found \(found). The interface module may have been statically duplicated or the plugin was built against a different interface version."
        case .dependencyCycle(let path):
            return "Dynamic library dependency cycle: \(path.joined(separator: " -> "))"
        case .notLoaded(let path):
            return "Dynamic library is not loaded: \(path)"
        }
    }
}

/// Process-global, thread-safe ownership for loaded dynamic libraries.
///
/// The runtime and every shared interface module must be dynamically linked and
/// present exactly once. Static duplication creates different Swift metadata;
/// `load` detects that condition through the spec identity check and throws.
///
/// Unloading Swift code is inherently unsafe if any instances, closures, or type
/// metadata from its image remain alive. The recommended policy is load and keep.
public final class DyLibLoader: @unchecked Sendable {
    public static let shared = DyLibLoader()

    private struct Record {
        let rawHandle: UnsafeMutableRawPointer
        let flags: DyLibOpenFlags
        var refCount: Int
    }

    private enum VisitState {
        case visiting
        case visited
    }

    private let lock = NSRecursiveLock()
    private var records: [String: Record] = [:]
    private var liveHandles: Set<UUID> = []

    public init() {}

    @discardableResult
    public func open(_ library: DyLibLibrary) throws -> DyLibHandle {
        let plan = try Self.loadPlan(for: library)
        let paths = plan.map(\.path)
        var retained: [String] = []
        do {
            for item in plan {
                let path = item.path
                let resident = lock.withLock { () -> Bool in
                    if var record = records[path] {
                        record.refCount += 1
                        records[path] = record
                        return true
                    }
                    return false
                }
                if resident {
                    retained.append(path)
                    continue
                }

                _ = dlerror()
                guard let rawHandle = dlopen(path, item.flags.rawValue) else {
                    let reason = dlerror().map { String(cString: $0) } ?? "unknown dlopen error"
                    throw DyLibError.failedToOpen(path: path, reason: reason)
                }

                let raceLoser = lock.withLock { () -> UnsafeMutableRawPointer? in
                    if var winner = records[path] {
                        winner.refCount += 1
                        records[path] = winner
                        return rawHandle
                    }
                    records[path] = Record(rawHandle: rawHandle, flags: item.flags, refCount: 1)
                    return nil
                }
                if let raceLoser {
                    dlclose(raceLoser)
                }
                retained.append(path)
            }
        } catch {
            closeNativeHandles(releaseReferences(retained))
            throw error
        }

        guard let targetPath = paths.last else {
            preconditionFailure("A library load plan always contains its target")
        }
        let handleID = UUID()
        lock.withLock { _ = liveHandles.insert(handleID) }
        return DyLibHandle(path: targetPath, id: handleID, retainedPaths: paths)
    }

    /// Loads a typed instance and returns the handle that owns its registry
    /// reference. Close it only after every value from the image is gone.
    public func loadWithHandle<S: DyLibPluginSpec>(
        _ spec: S.Type,
        from library: DyLibLibrary
    ) throws -> (instance: S.Interface, handle: DyLibHandle) {
        let handle = try open(library)
        do {
            let symbol = try symbolPointer(named: S.symbolName, in: handle)
            typealias EntryFunction = @convention(c) () -> UnsafeMutableRawPointer
            let entryFunction = unsafeBitCast(symbol, to: EntryFunction.self)
            let rawHeader = entryFunction()

            let magic = UnsafeRawPointer(rawHeader).load(
                fromByteOffset: MemoryLayout<DyLibEntryHeader>.offset(of: \.magic)!,
                as: UInt32.self
            )
            guard magic == DyLibEntryHeader.expectedMagic else {
                // Without a valid magic the pointer is not a header this
                // runtime allocated; freeing memory we don't own would
                // corrupt the heap, so the (misbehaving) entry keeps it.
                throw DyLibError.invalidEntry(symbol: S.symbolName, path: handle.path)
            }
            let abiVersion = UnsafeRawPointer(rawHeader).load(
                fromByteOffset: MemoryLayout<DyLibEntryHeader>.offset(of: \.abiVersion)!,
                as: Int32.self
            )
            let box = UnsafeRawPointer(rawHeader).load(
                fromByteOffset: MemoryLayout<DyLibEntryHeader>.offset(of: \.box)!,
                as: UnsafeMutableRawPointer.self
            )
            // A valid magic means dyLibMakeEntry allocated this header and
            // transferred ownership; all fields are read, so free it now.
            rawHeader.deallocate()
            if abiVersion != DyLibABI.current {
                Unmanaged<DyLibPluginEntry>.fromOpaque(box).release()
                throw DyLibError.abiMismatch(expected: DyLibABI.current, found: abiVersion)
            }
            let entry = Unmanaged<DyLibPluginEntry>.fromOpaque(box).takeRetainedValue()
            let expectedName = String(describing: S.self)
            let foundName = String(describing: entry.specType)
            guard ObjectIdentifier(entry.specType) == ObjectIdentifier(S.self) else {
                throw DyLibError.specTypeMismatch(expected: expectedName, found: foundName)
            }
            guard let instance = entry.makeInstance() as? S.Interface else {
                throw DyLibError.specTypeMismatch(expected: expectedName, found: foundName)
            }
            return (instance, handle)
        } catch {
            try? close(handle)
            throw error
        }
    }

    /// Deliberately discards the handle for the recommended load-and-keep
    /// policy. Use `loadWithHandle(_:from:)` when explicit release is needed.
    public func load<S: DyLibPluginSpec>(
        _ spec: S.Type,
        from library: DyLibLibrary
    ) throws -> S.Interface {
        try loadWithHandle(spec, from: library).instance
    }

    public func load<S: DyLibPluginSpec>(_ spec: S.Type, from path: String) throws -> S.Interface {
        try load(spec, from: DyLibLibrary(path: path))
    }

    /// Decrements this image's refcount and calls `dlclose` at zero.
    /// All Swift values and metadata from the image must already be dead.
    public func close(_ handle: DyLibHandle) throws {
        let nativeHandles = try lock.withLock { () throws -> [UnsafeMutableRawPointer] in
            guard liveHandles.remove(handle.id) != nil else {
                throw DyLibError.notLoaded(path: handle.path)
            }
            precondition(records[handle.path] != nil, "A live handle must reference a loaded image")
            return releaseReferencesLocked(handle.retainedPaths)
        }
        closeNativeHandles(nativeHandles)
    }

    internal func symbolPointer(named symbol: String, in handle: DyLibHandle) throws -> UnsafeMutableRawPointer {
        try lock.withLock {
            guard liveHandles.contains(handle.id), let record = records[handle.path] else {
                throw DyLibError.notLoaded(path: handle.path)
            }
            _ = dlerror()
            guard let pointer = dlsym(record.rawHandle, symbol) else {
                throw DyLibError.symbolNotFound(symbol: symbol, path: handle.path)
            }
            return pointer
        }
    }

    internal static func loadOrder(for library: DyLibLibrary) throws -> [String] {
        try loadPlan(for: library).map(\.path)
    }

    private static func loadPlan(for library: DyLibLibrary) throws -> [(path: String, flags: DyLibOpenFlags)] {
        var states: [String: VisitState] = [:]
        var stack: [String] = []
        var order: [(path: String, flags: DyLibOpenFlags)] = []

        func visit(_ node: DyLibLibrary) throws {
            let path = canonicalPath(node.path)
            if let state = states[path] {
                if case .visiting = state {
                    let start = stack.firstIndex(of: path) ?? 0
                    throw DyLibError.dependencyCycle(path: Array(stack[start...]) + [path])
                }
                return
            }
            states[path] = .visiting
            stack.append(path)
            for dependency in node.dependencies {
                try visit(dependency)
            }
            _ = stack.popLast()
            states[path] = .visited
            order.append((path, node.flags))
        }

        try visit(library)
        return order
    }

    /// Returns whether this loader currently owns a registry reference for `path`.
    internal func isLoaded(_ path: String) -> Bool {
        lock.withLock { records[Self.canonicalPath(path)] != nil }
    }

    internal static func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
    }

    private func releaseReferences(_ paths: [String]) -> [UnsafeMutableRawPointer] {
        lock.withLock { releaseReferencesLocked(paths) }
    }

    private func releaseReferencesLocked(_ paths: [String]) -> [UnsafeMutableRawPointer] {
        var nativeHandles: [UnsafeMutableRawPointer] = []
        for path in paths.reversed() {
            guard var record = records[path] else { continue }
            if record.refCount > 1 {
                record.refCount -= 1
                records[path] = record
            } else {
                records.removeValue(forKey: path)
                nativeHandles.append(record.rawHandle)
            }
        }
        return nativeHandles
    }

    private func closeNativeHandles(_ handles: [UnsafeMutableRawPointer]) {
        for handle in handles {
            dlclose(handle)
        }
    }
}
