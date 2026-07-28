import Darwin
import Dispatch
import Foundation
import Testing
@testable import DyLibRuntimeLoader

private enum MissingEntrySpec: DyLibPluginSpec {
    typealias Interface = Any
    static let symbolName = "__no_such_dylib_runtime_loader_entry__"
}

private enum HeaderTestSpec: DyLibPluginSpec {
    typealias Interface = String
    static let symbolName = "unused"
}

private final class LazyTestPlugin: @unchecked Sendable {}

private enum LazyTestSpec: DyLibPluginSpec {
    typealias Interface = LazyTestPlugin
    static let symbolName = "unused"
}

private enum LazyTestError: Error {
    case expectedFailure
}

@DyLibInterface
public protocol Widget {
    func ping() -> String
    func fetch() throws -> String
}

private struct TestWidget: Widget {
    let value: String

    func ping() -> String { value }
    func fetch() throws -> String { value }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() -> Int {
        lock.withLock {
            value += 1
            return value
        }
    }

    var current: Int {
        lock.withLock { value }
    }
}

private final class LockedPlugins: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [LazyTestPlugin] = []

    func append(_ value: LazyTestPlugin) {
        lock.withLock { values.append(value) }
    }

    var snapshot: [LazyTestPlugin] {
        lock.withLock { values }
    }
}

@Suite struct DyLibRuntimeLoaderTests {
    @Test func generatedLazyProxyDefersAndCachesResolution() throws {
        let counter = LockedCounter()
        let expected = TestWidget(value: "ready")
        let lazy = DyLibLazyPlugin<WidgetPluginSpec>(loadOperation: {
            _ = counter.increment()
            return expected
        })
        let proxy = WidgetLazyProxy { try lazy.loadIfNeeded() }

        #expect(counter.current == 0)
        #expect(proxy.ping() == "ready")
        #expect(try proxy.fetch() == "ready")
        #expect(counter.current == 1)
    }

    @Test func generatedLazyProxyPropagatesThrowingResolutionFailure() {
        let counter = LockedCounter()
        let lazy = DyLibLazyPlugin<WidgetPluginSpec>(loadOperation: {
            _ = counter.increment()
            throw LazyTestError.expectedFailure
        })
        let proxy = WidgetLazyProxy { try lazy.loadIfNeeded() }

        do {
            _ = try proxy.fetch()
            Issue.record("Expected the proxy resolver failure to propagate")
        } catch LazyTestError.expectedFailure {
            #expect(counter.current == 1)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func makeEntryUsesValidatedBoundaryHeader() {
        let rawHeader = dyLibMakeEntry(spec: HeaderTestSpec.self) { "value" }
        let header = rawHeader.load(as: DyLibEntryHeader.self)
        #expect(header.magic == DyLibEntryHeader.expectedMagic)
        #expect(header.abiVersion == DyLibABI.current)

        let entry = Unmanaged<DyLibPluginEntry>.fromOpaque(header.box).takeRetainedValue()
        #expect(entry.makeInstance() as? String == "value")
        rawHeader.assumingMemoryBound(to: DyLibEntryHeader.self).deinitialize(count: 1)
        rawHeader.deallocate()
    }

    @Test func dependencyOrderIsPostOrderAndDeduplicated() throws {
        let shared = DyLibLibrary(path: "/tmp/shared.dylib")
        let left = DyLibLibrary(path: "/tmp/left.dylib", dependencies: [shared])
        let right = DyLibLibrary(path: "/tmp/right.dylib", dependencies: [shared])
        let root = DyLibLibrary(path: "/tmp/root.dylib", dependencies: [left, right])

        #expect(try DyLibLoader.loadOrder(for: root) == [
            DyLibLoader.canonicalPath(shared.path),
            DyLibLoader.canonicalPath(left.path),
            DyLibLoader.canonicalPath(right.path),
            DyLibLoader.canonicalPath(root.path),
        ])
    }

    @Test func dependencyCycleIncludesClosedPath() {
        let graph = DyLibLibrary(
            path: "/tmp/a.dylib",
            dependencies: [
                DyLibLibrary(
                    path: "/tmp/b.dylib",
                    dependencies: [DyLibLibrary(path: "/tmp/a.dylib")]
                ),
            ]
        )

        do {
            _ = try DyLibLoader.loadOrder(for: graph)
            Issue.record("Expected a dependency cycle")
        } catch {
            #expect(error as? DyLibError == .dependencyCycle(
                path: ["/tmp/a.dylib", "/tmp/b.dylib", "/tmp/a.dylib"]
            ))
        }
    }

    @Test func wrongPathThrowsFailedToOpen() {
        let path = "/definitely/not/a/real/DyLibRuntimeLoader-test.dylib"
        do {
            _ = try DyLibLoader().open(DyLibLibrary(path: path))
            Issue.record("Expected dlopen to fail")
        } catch let DyLibError.failedToOpen(actualPath, reason) {
            #expect(actualPath == path)
            #expect(!reason.isEmpty)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func missingSymbolThrowsSymbolNotFound() throws {
        let loader = DyLibLoader()
        let handle = try loader.open(DyLibLibrary(path: "/usr/lib/libSystem.B.dylib"))
        defer { try? loader.close(handle) }

        do {
            _ = try loader.symbolPointer(
                named: "__no_such_dylib_runtime_loader_symbol__",
                in: handle
            )
            Issue.record("Expected dlsym to fail")
        } catch {
            #expect(error as? DyLibError == .symbolNotFound(
                symbol: "__no_such_dylib_runtime_loader_symbol__",
                path: handle.path
            ))
        }
    }

    @Test func eachOpenIssuesDistinctRefcountedHandle() throws {
        let loader = DyLibLoader()
        let library = DyLibLibrary(path: "/usr/lib/libSystem.B.dylib")
        let first = try loader.open(library)
        let second = try loader.open(library)
        #expect(first != second)

        try loader.close(first)
        _ = try loader.symbolPointer(named: "malloc", in: second)
        try loader.close(second)
    }

    @Test func doubleCloseFailsWhileDependencyKeepsImageLoaded() throws {
        let loader = DyLibLoader()
        let dependencyPath = "/usr/lib/libSystem.B.dylib"
        let dependent = DyLibLibrary(
            path: "/usr/lib/libobjc.A.dylib",
            dependencies: [DyLibLibrary(path: dependencyPath)]
        )
        let dependentHandle = try loader.open(dependent)
        let directHandle = try loader.open(DyLibLibrary(path: dependencyPath))

        try loader.close(directHandle)
        #expect(loader.isLoaded(dependencyPath))

        do {
            try loader.close(directHandle)
            Issue.record("Expected double-close to fail")
        } catch {
            #expect(error as? DyLibError == .notLoaded(path: directHandle.path))
        }
        #expect(loader.isLoaded(dependencyPath))

        try loader.close(dependentHandle)
        #expect(!loader.isLoaded(dependencyPath))
    }

    @Test func failedLoadReleasesItsHandleAndRegistryReferences() throws {
        let loader = DyLibLoader()
        let path = "/usr/lib/libSystem.B.dylib"

        do {
            _ = try loader.load(MissingEntrySpec.self, from: path)
            Issue.record("Expected the entry symbol lookup to fail")
        } catch {
            #expect(error as? DyLibError == .symbolNotFound(
                symbol: MissingEntrySpec.symbolName,
                path: DyLibLoader.canonicalPath(path)
            ))
        }
        #expect(!loader.isLoaded(path))

        let handle = try loader.open(DyLibLibrary(path: path))
        try loader.close(handle)
        #expect(!loader.isLoaded(path))
    }

    @Test func openFlagRawValuesMatchDarwin() {
        #expect(DyLibOpenFlags.lazy.rawValue == RTLD_LAZY)
        #expect(DyLibOpenFlags.now.rawValue == RTLD_NOW)
        #expect(DyLibOpenFlags.global.rawValue == RTLD_GLOBAL)
        #expect(DyLibOpenFlags.local.rawValue == RTLD_LOCAL)
        #expect(DyLibOpenFlags.first.rawValue == RTLD_FIRST)
        #expect(DyLibLibrary(path: "/tmp/plugin.dylib").flags == [.now, .local, .first])
    }

    @available(*, deprecated, message: "Exercises the deprecated compatibility API")
    @Test func legacyMissingSymbolMapsToLegacyError() {
        do {
            let _: Int = try dyLibLoad(
                withSymbol: "__missing_legacy_symbol__",
                fromPath: "/usr/lib/libSystem.B.dylib",
                forType: Int.self
            )
            Issue.record("Expected legacy symbol lookup to fail")
        } catch let error as DynamicFrameworkLoaderError {
            guard case .symbolNotFound = error else {
                Issue.record("Unexpected legacy error: \(error)")
                return
            }
        } catch {
            Issue.record("Expected DynamicFrameworkLoaderError, got \(error)")
        }
    }

    @Test func specMismatchDescriptionExplainsDuplicateMetadata() {
        let error = DyLibError.specTypeMismatch(
            expected: "AnimalPluginSpec",
            found: "AnimalPluginSpec"
        )
        #expect(error.errorDescription?.contains("statically duplicated") == true)
        #expect(error.errorDescription?.contains("different interface version") == true)
    }

    @Test func lazyPluginLoadsOnce() throws {
        let counter = LockedCounter()
        let expected = LazyTestPlugin()
        let connection = DyLibLazyPlugin<LazyTestSpec>(loadOperation: {
            _ = counter.increment()
            return expected
        })

        #expect(!connection.isLoaded)
        let first = try connection.loadIfNeeded()
        #expect(connection.isLoaded)
        let second = try connection.loadIfNeeded()

        #expect(first === expected)
        #expect(second === expected)
        #expect(counter.current == 1)
    }

    @Test func lazyPluginIsLoadedTransitionsAfterSuccess() throws {
        let connection = DyLibLazyPlugin<LazyTestSpec>(loadOperation: {
            LazyTestPlugin()
        })

        #expect(!connection.isLoaded)
        _ = try connection.loadIfNeeded()
        #expect(connection.isLoaded)
    }

    @Test func lazyPluginRetriesAfterFailure() throws {
        let counter = LockedCounter()
        let expected = LazyTestPlugin()
        let connection = DyLibLazyPlugin<LazyTestSpec>(loadOperation: {
            if counter.increment() == 1 {
                throw LazyTestError.expectedFailure
            }
            return expected
        })

        do {
            _ = try connection.loadIfNeeded()
            Issue.record("Expected the first lazy load to fail")
        } catch LazyTestError.expectedFailure {
            #expect(!connection.isLoaded)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        let result = try connection.loadIfNeeded()
        #expect(result === expected)
        #expect(connection.isLoaded)
        #expect(counter.current == 2)
    }

    @Test func lazyPluginConcurrentCallsCollapseToOneLoad() {
        let counter = LockedCounter()
        let expected = LazyTestPlugin()
        let connection = DyLibLazyPlugin<LazyTestSpec>(loadOperation: {
            _ = counter.increment()
            Thread.sleep(forTimeInterval: 0.05)
            return expected
        })
        let results = LockedPlugins()
        let group = DispatchGroup()
        let queue = DispatchQueue(
            label: "DyLibLazyPlugin.concurrent-test",
            attributes: .concurrent
        )

        for _ in 0..<2 {
            group.enter()
            queue.async {
                defer { group.leave() }
                if let plugin = try? connection.loadIfNeeded() {
                    results.append(plugin)
                }
            }
        }
        group.wait()

        let loadedPlugins = results.snapshot
        #expect(loadedPlugins.count == 2)
        #expect(loadedPlugins.allSatisfy { $0 === expected })
        #expect(counter.current == 1)
        #expect(connection.isLoaded)
    }
}
