// Adversarial tests for the lazy-load logger (feature/dylib-load-logger).
// Written against the agreed API: DyLibLoadLogger { willLoad(_:), didLoad(_:) },
// DyLibLoadStart { interface, path }, DyLibLoadResult { interface, path, duration, error },
// DyLibLazyPlugin(logger:loader:library:) (argument order as implemented in bcb95c1).
//
// A successful in-process load is achieved by exporting a plugin entry from this
// test image and dlopen-ing the image's own path (found with dladdr).

import Darwin
import Dispatch
import Foundation
import Testing
@testable import Dynasty

@DyLibInterface
public protocol LoggerProbe {
    func value() -> String
}

@DyLibExport(LoggerProbe.self)
public struct ExportedLoggerProbe: LoggerProbe {
    public init() {}
    public func value() -> String { "probe" }
}

private func ownImagePath() -> String {
    var info = Dl_info()
    let ok = dladdr(#dsohandle, &info)
    precondition(ok != 0 && info.dli_fname != nil, "dladdr failed")
    return String(cString: info.dli_fname)
}

// MARK: - Recording

struct AdvEvent: Sendable {
    enum Kind: Sendable { case will, did }
    let kind: Kind
    let interface: String
    let path: String
    let seconds: Double?
    let error: DyLibError?
    let thread: String
}

final class AdvEventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [AdvEvent] = []
    func append(_ e: AdvEvent) { lock.withLock { events.append(e) } }
    var all: [AdvEvent] { lock.withLock { events } }
    var dids: [AdvEvent] { all.filter { $0.kind == .did } }
    var wills: [AdvEvent] { all.filter { $0.kind == .will } }
}

// Overloads so the harness compiles whatever concrete type `duration` ends up being.
@available(macOS 13, iOS 16, *)
func advSeconds(_ d: Duration) -> Double {
    let c = d.components
    return Double(c.seconds) + Double(c.attoseconds) / 1e18
}
func advSeconds(_ d: Double) -> Double { d }
func advSeconds(_ d: UInt64) -> Double { Double(d) / 1e9 }

protocol AdvRecordingLogger: DyLibLoadLogger {
    static var log: AdvEventLog { get }
}

extension AdvRecordingLogger {
    static func willLoad(_ event: DyLibLoadStart) {
        log.append(AdvEvent(kind: .will, interface: event.interface, path: event.path,
                                 seconds: nil, error: nil, thread: Thread.current.description))
    }
    static func didLoad(_ event: DyLibLoadResult) {
        log.append(AdvEvent(kind: .did, interface: event.interface, path: event.path,
                                 seconds: advSeconds(event.duration), error: event.error,
                                 thread: Thread.current.description))
    }
}

// One logger type per test: Swift Testing runs tests in parallel and logger state is static.
enum SuccessLog: AdvRecordingLogger { static let log = AdvEventLog() }
enum CacheLog: AdvRecordingLogger { static let log = AdvEventLog() }
enum FailOpenLog: AdvRecordingLogger { static let log = AdvEventLog() }
enum FailSymbolLog: AdvRecordingLogger { static let log = AdvEventLog() }
enum RetryLog: AdvRecordingLogger { static let log = AdvEventLog() }
enum ConcurrentLog: AdvRecordingLogger { static let log = AdvEventLog() }
enum ConcurrentFailLog: AdvRecordingLogger { static let log = AdvEventLog() }
enum ProxyLog: AdvRecordingLogger { static let log = AdvEventLog() }

/// A logger that only implements `didLoad`, relying on the protocol's default `willLoad`.
enum AdvDidOnlyLog: DyLibLoadLogger {
    static let log = AdvEventLog()
    static func didLoad(_ event: DyLibLoadResult) {
        log.append(AdvEvent(kind: .did, interface: event.interface, path: event.path,
                                 seconds: advSeconds(event.duration), error: event.error, thread: ""))
    }
}

/// Calls back into DyLibLoader from inside the logger, on the same thread and on another
/// thread (the recursive lock would hide a same-thread violation).
enum AdvReentrantLog: DyLibLoadLogger {
    static let log = AdvEventLog()
    static let deadlocks = AdvEventLog()
    nonisolated(unsafe) static var loader: DyLibLoader = .shared

    static func exercise(_ tag: String) {
        let lib = DyLibLibrary(path: "/usr/lib/libobjc.A.dylib")
        // Same thread.
        if let h = try? loader.open(lib) { try? loader.close(h) }
        if let h = try? DyLibLoader.shared.open(lib) { try? DyLibLoader.shared.close(h) }
        // Another thread, bounded wait: if the loader lock were held here, this times out.
        let done = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            if let h = try? loader.open(lib) { try? loader.close(h) }
            if let h = try? DyLibLoader.shared.open(lib) { try? DyLibLoader.shared.close(h) }
            done.signal()
        }
        if done.wait(timeout: .now() + 5) == .timedOut {
            deadlocks.append(AdvEvent(kind: .did, interface: tag, path: "", seconds: nil, error: nil, thread: ""))
        }
    }

    static func willLoad(_ event: DyLibLoadStart) {
        exercise("will")
        log.append(AdvEvent(kind: .will, interface: event.interface, path: event.path, seconds: nil, error: nil, thread: ""))
    }
    static func didLoad(_ event: DyLibLoadResult) {
        exercise("did")
        log.append(AdvEvent(kind: .did, interface: event.interface, path: event.path,
                                 seconds: advSeconds(event.duration), error: event.error, thread: ""))
    }
}

private enum MissingProbeSpec: DyLibPluginSpec {
    typealias Interface = any LoggerProbe
    static let symbolName = "__no_such_logger_probe_entry__"
}

private final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [T] = []
    func append(_ t: T) { lock.withLock { items.append(t) } }
    var all: [T] { lock.withLock { items } }
}

@Suite struct LoggerAdversarialTests {
    let image = ownImagePath()

    @Test func successEventHasInterfacePathAndPlausibleDuration() throws {
        let lazy = DyLibLazyPlugin<LoggerProbePluginSpec>(
            logger: SuccessLog.self, loader: DyLibLoader(), library: { DyLibLibrary(path: image) })
        #expect(SuccessLog.log.all.isEmpty, "constructing the connection must not log")
        let probe = try lazy.loadIfNeeded()
        #expect(probe.value() == "probe")

        let all = SuccessLog.log.all
        #expect(all.map(\.kind) == [.will, .did], "expected willLoad then didLoad, got \(all.map(\.kind))")
        let did = try #require(SuccessLog.log.dids.first)
        #expect(did.error == nil)
        #expect(did.interface == "LoggerProbe")
        #expect(did.path == image || DyLibLoader.canonicalPath(did.path) == DyLibLoader.canonicalPath(image),
                "path was \(did.path), expected \(image)")
        let s = try #require(did.seconds)
        #expect(s > 0, "duration must be non-zero, got \(s)")
        #expect(s < 10, "duration implausibly large: \(s)")
        if let will = SuccessLog.log.wills.first {
            #expect(will.interface == did.interface)
            #expect(will.path == did.path)
        }
    }

    @Test func cacheHitDoesNotLog() throws {
        let lazy = DyLibLazyPlugin<LoggerProbePluginSpec>(
            logger: CacheLog.self, loader: DyLibLoader(), library: { DyLibLibrary(path: image) })
        for _ in 0..<5 { _ = try lazy.loadIfNeeded() }
        _ = lazy.isLoaded
        #expect(CacheLog.log.dids.count == 1)
        #expect(CacheLog.log.wills.count == 1)
    }

    @Test func failedOpenEventCarriesDyLibError() {
        let path = "/definitely/not/here/LoggerProbe.framework/LoggerProbe"
        let lazy = DyLibLazyPlugin<LoggerProbePluginSpec>(
            logger: FailOpenLog.self, loader: DyLibLoader(), library: { DyLibLibrary(path: path) })
        var thrown: Error?
        do { _ = try lazy.loadIfNeeded() } catch { thrown = error }
        #expect(thrown != nil)
        #expect(FailOpenLog.log.dids.count == 1)
        guard let did = FailOpenLog.log.dids.first else { return }
        guard case .failedToOpen(let p, let reason)? = did.error else {
            Issue.record("expected failedToOpen, got \(String(describing: did.error))"); return
        }
        #expect(p == path)
        #expect(!reason.isEmpty)
        #expect(did.error == thrown as? DyLibError, "logged error must equal the thrown error")
        #expect(did.path == path)
        #expect((did.seconds ?? -1) >= 0)
    }

    @Test func failedSymbolEventCarriesDyLibError() {
        let lazy = DyLibLazyPlugin<MissingProbeSpec>(
            logger: FailSymbolLog.self, loader: DyLibLoader(),
            library: { DyLibLibrary(path: "/usr/lib/libSystem.B.dylib") })
        _ = try? lazy.loadIfNeeded()
        let did = FailSymbolLog.log.dids.first
        guard case .symbolNotFound(let sym, _)? = did?.error else {
            Issue.record("expected symbolNotFound, got \(String(describing: did?.error))"); return
        }
        #expect(sym == MissingProbeSpec.symbolName)
    }

    @Test func retryAfterFailureEmitsSecondEvent() throws {
        let counter = Box<Int>()
        let lazy = DyLibLazyPlugin<LoggerProbePluginSpec>(
            logger: RetryLog.self, loader: DyLibLoader(),
            library: {
                counter.append(1)
                return counter.all.count == 1
                    ? DyLibLibrary(path: "/definitely/not/here/x")
                    : DyLibLibrary(path: image)
            })
        #expect(throws: (any Error).self) { try lazy.loadIfNeeded() }
        #expect(!lazy.isLoaded)
        _ = try lazy.loadIfNeeded()
        _ = try lazy.loadIfNeeded() // cache hit
        let dids = RetryLog.log.dids
        #expect(dids.count == 2, "expected one event per real attempt, got \(dids.count)")
        #expect(dids.first?.error != nil)
        #expect(dids.last?.error == nil)
        #expect(RetryLog.log.wills.count == 2)
    }

    @Test func concurrentFirstCallsEmitExactlyOneEvent() {
        let lazy = DyLibLazyPlugin<LoggerProbePluginSpec>(
            logger: ConcurrentLog.self, loader: DyLibLoader(), library: { DyLibLibrary(path: image) })
        let results = Box<Bool>()
        let start = DispatchSemaphore(value: 0)
        let group = DispatchGroup()
        for _ in 0..<64 {
            group.enter()
            Thread.detachNewThread {
                start.wait()
                results.append((try? lazy.loadIfNeeded()) != nil)
                group.leave()
            }
        }
        for _ in 0..<64 { start.signal() }
        #expect(group.wait(timeout: .now() + 30) == .success, "concurrent loads hung")
        #expect(results.all.count == 64)
        #expect(results.all.allSatisfy { $0 })
        #expect(ConcurrentLog.log.dids.count == 1)
        #expect(ConcurrentLog.log.wills.count <= 1)
    }

    @Test func concurrentFailuresAreSerializedOneEventPerAttempt() {
        let lazy = DyLibLazyPlugin<LoggerProbePluginSpec>(
            logger: ConcurrentFailLog.self, loader: DyLibLoader(),
            library: { DyLibLibrary(path: "/definitely/not/here/y") })
        DispatchQueue.concurrentPerform(iterations: 16) { _ in _ = try? lazy.loadIfNeeded() }
        // Failures are not cached, so each of the 16 attempts is a real load.
        #expect(ConcurrentFailLog.log.dids.count == 16)
        #expect(ConcurrentFailLog.log.dids.allSatisfy { $0.error != nil })
    }

    @Test func defaultWillLoadIsOptional() throws {
        let lazy = DyLibLazyPlugin<LoggerProbePluginSpec>(
            logger: AdvDidOnlyLog.self, loader: DyLibLoader(), library: { DyLibLibrary(path: image) })
        _ = try lazy.loadIfNeeded()
        #expect(AdvDidOnlyLog.log.dids.count == 1)
    }

    @Test func loggerIsNeverCalledUnderLoaderLock() throws {
        let loader = DyLibLoader()
        AdvReentrantLog.loader = loader
        let lazy = DyLibLazyPlugin<LoggerProbePluginSpec>(
            logger: AdvReentrantLog.self, loader: loader, library: { DyLibLibrary(path: image) })
        _ = try lazy.loadIfNeeded()
        let failing = DyLibLazyPlugin<LoggerProbePluginSpec>(
            logger: AdvReentrantLog.self, loader: loader, library: { DyLibLibrary(path: "/nope/z") })
        _ = try? failing.loadIfNeeded()
        let shared = DyLibLazyPlugin<LoggerProbePluginSpec>(
            logger: AdvReentrantLog.self, library: { DyLibLibrary(path: image) })
        _ = try shared.loadIfNeeded()
        #expect(AdvReentrantLog.deadlocks.all.isEmpty,
                "logger blocked on DyLibLoader lock in: \(AdvReentrantLog.deadlocks.all.map(\.interface))")
        #expect(AdvReentrantLog.log.dids.count == 3)
    }

    @Test func throwingProxyPathLogsFailure() {
        let lazy = DyLibLazyPlugin<LoggerProbePluginSpec>(
            logger: ProxyLog.self, loader: DyLibLoader(), library: { DyLibLibrary(path: "/nope/proxy") })
        let proxy = LoggerProbeLazyProxy { try lazy.loadIfNeeded() }
        _ = proxy // non-throwing method would trap; covered by the subprocess harness.
        _ = try? lazy.loadIfNeeded()
        #expect(ProxyLog.log.dids.count == 1)
    }

    @Test func noLoggerConnectionStillWorks() throws {
        let lazy = DyLibLazyPlugin<LoggerProbePluginSpec>(
            loader: DyLibLoader(), library: { DyLibLibrary(path: image) })
        #expect(try lazy.loadIfNeeded().value() == "probe")
    }
}
