import Foundation

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Owns the dlopen handles and the one-time entry-symbol invocation per
/// binary. Entries are cached forever and images are never dlclosed: Swift
/// registers type metadata and conformances irreversibly, so unloading a
/// Swift image is unsafe by construction.
final class PluginHandleTable: @unchecked Sendable {
    struct Entry {
        let handle: UnsafeMutableRawPointer
        let descriptor: PluginDescriptor
    }

    private typealias EntryFunction = @convention(c) () -> UnsafeMutableRawPointer

    private let entries = LockedState([String: Entry]())

    /// Serializes dlopen and the entry-symbol call so the retained descriptor
    /// pointer is taken exactly once per path. Kept separate from the cache
    /// lock, which is never held across dlopen/dlsym or the entry invocation.
    private let loadLock = NSLock()

    func entry(forPath path: String) throws -> Entry {
        if let cached = entries.withLock({ $0[path] }) {
            return cached
        }

        loadLock.lock()
        defer { loadLock.unlock() }

        if let cached = entries.withLock({ $0[path] }) {
            return cached
        }

        guard let handle = dlopen(path, RTLD_NOW) else {
            let reason: String
            if let message = dlerror() {
                reason = String(cString: message)
            } else {
                reason = "unknown dlerror"
            }
            throw PluginError.libraryOpenFailed(path: path, reason: reason)
        }
        guard let symbol = dlsym(handle, DyLibPluginABI.entrySymbol) else {
            // Deliberately no dlclose: the image may be a legitimate
            // non-plugin dependency, and dlclosing Swift images is unsafe.
            throw PluginError.notAPlugin(path: path)
        }

        let entryFunction = unsafeBitCast(symbol, to: EntryFunction.self)
        let descriptor = Unmanaged<PluginDescriptor>.fromOpaque(entryFunction()).takeRetainedValue()
        let entry = Entry(handle: handle, descriptor: descriptor)
        entries.withLock { $0[path] = entry }
        return entry
    }
}
