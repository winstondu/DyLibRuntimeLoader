// End-to-end adversarial harness for the lazy-load logger.
// Layout expected (built by ../run.sh): <dir>/LoggerHost and
// <dir>/Frameworks/<Name>.framework/<Name> symlinks to the plugin dylibs.
//
// Modes:  LoggerHost checks   -> runs all in-process checks, prints PASS/FAIL, exit 1 on any FAIL
//         LoggerHost trap     -> calls a non-throwing proxy on a missing plugin (must trap AFTER logging)
//         LoggerHost dog      -> plugin-to-plugin: host connection to LoggedDogPlugin, which has its own logger

import AnimalInterface
import Darwin
import DyLibRuntimeLoader
import Foundation

func emit(_ s: String) {
    // stderr is unbuffered, so lines survive a subsequent trap.
    fputs(s + "\n", stderr)
}

func seconds(_ d: Duration) -> Double {
    Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
}
func seconds(_ d: Double) -> Double { d }
func seconds(_ d: UInt64) -> Double { Double(d) / 1e9 }

struct Event {
    let kind: String
    let interface: String
    let path: String
    let secs: Double
    let error: DyLibError?
}

final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [Event] = []
    func add(_ e: Event) { lock.withLock { items.append(e) } }
    var all: [Event] { lock.withLock { items } }
    func dids(_ framework: String) -> [Event] { all.filter { $0.kind == "did" && $0.path.contains("/\(framework).framework/") } }
    func wills(_ framework: String) -> [Event] { all.filter { $0.kind == "will" && $0.path.contains("/\(framework).framework/") } }
}

let recorder = Recorder()

enum HostLog: DyLibLoadLogger {
    static func willLoad(_ e: DyLibLoadStart) {
        recorder.add(Event(kind: "will", interface: e.interface, path: e.path, secs: 0, error: nil))
        emit("HOSTLOG willLoad interface=\(e.interface) path=\(e.path)")
    }
    static func didLoad(_ e: DyLibLoadResult) {
        recorder.add(Event(kind: "did", interface: e.interface, path: e.path, secs: seconds(e.duration), error: e.error))
        emit("HOSTLOG didLoad interface=\(e.interface) path=\(e.path) duration=\(e.duration) error=\(e.error.map { "\($0)" } ?? "nil")")
    }
}

/// Logger that calls back into the loader (same thread + another thread with a timeout)
/// and into another, already-loaded connection.
enum ReentrantLog: DyLibLoadLogger {
    nonisolated(unsafe) static var blocked: [String] = []
    static func poke(_ tag: String) {
        let lib = DyLibLibrary(path: "/usr/lib/libobjc.A.dylib")
        if let h = try? DyLibLoader.shared.open(lib) { try? DyLibLoader.shared.close(h) }
        let done = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            if let h = try? DyLibLoader.shared.open(lib) { try? DyLibLoader.shared.close(h) }
            // Real plugin open/close of another library on another thread.
            let cat = Bundle.main.privateFrameworksURL!.appendingPathComponent("CatPlugin.framework/CatPlugin").path
            if let r = try? DyLibLoader.shared.loadWithHandle(AnimalPluginSpec.self, from: DyLibLibrary(path: cat)) {
                _ = r.instance.speak()
            }
            _ = try? CatConn.loadIfNeeded()
            done.signal()
        }
        if done.wait(timeout: .now() + 5) == .timedOut { blocked.append(tag) }
    }
    static func willLoad(_ e: DyLibLoadStart) { poke("willLoad") }
    static func didLoad(_ e: DyLibLoadResult) {
        poke("didLoad")
        recorder.add(Event(kind: "did", interface: e.interface, path: e.path, secs: seconds(e.duration), error: e.error))
    }
}

@DyLibConnect(Animal.self, framework: "CatPlugin", logger: HostLog.self)
enum CatConn {}

@DyLibConnect(Animal.self, framework: "MissingPlugin", logger: HostLog.self)
enum MissingConn {}

@DyLibConnect(Animal.self, framework: "ConcPlugin", logger: HostLog.self)
enum ConcConn {}

@DyLibConnect(Animal.self, framework: "ReentPlugin", logger: ReentrantLog.self)
enum ReentConn {}

@DyLibConnect(Animal.self, framework: "ReentMissing", logger: ReentrantLog.self)
enum ReentMissingConn {}

@DyLibConnect(Animal.self, framework: "LoggedDogPlugin", logger: HostLog.self)
enum DogConn {}

@DyLibConnect(Animal.self, framework: "SilentPlugin")
enum SilentConn {}

var failures = 0
func check(_ ok: Bool, _ name: String, _ detail: @autoclosure () -> String = "") {
    if ok { print("PASS \(name)") } else { failures += 1; print("FAIL \(name) \(detail())") }
}

let frameworks = Bundle.main.privateFrameworksURL!
func execPath(_ name: String) -> String {
    frameworks.appendingPathComponent("\(name).framework/\(name)").path
}

func runChecks() {
    // 1. Success event.
    check(recorder.all.isEmpty, "no events before first use")
    let cat = CatConn.instance
    check(recorder.all.isEmpty, "obtaining .instance proxy does not load", "\(recorder.all.count)")
    check(cat.speak() == "Meow", "cat speaks")
    let catDid = recorder.dids("CatPlugin")
    check(catDid.count == 1, "success: exactly one didLoad", "\(catDid.count)")
    check(recorder.wills("CatPlugin").count == 1, "success: exactly one willLoad")
    if let e = catDid.first {
        check(e.error == nil, "success: error nil")
        check(e.interface == "Animal", "success: interface == Animal", e.interface)
        check(e.path == execPath("CatPlugin"), "success: path is resolved framework executable", "\(e.path) vs \(execPath("CatPlugin"))")
        check(e.secs > 0 && e.secs < 10, "success: plausible non-zero duration", "\(e.secs)")
    }
    if let w = recorder.all.firstIndex(where: { $0.kind == "will" && $0.path.contains("CatPlugin") }),
       let d = recorder.all.firstIndex(where: { $0.kind == "did" && $0.path.contains("CatPlugin") }) {
        check(w < d, "willLoad precedes didLoad")
    }

    // 2. Cache hit.
    for _ in 0..<10 { _ = cat.speak(); _ = try? CatConn.loadIfNeeded(); _ = CatConn.isLoaded }
    check(recorder.dids("CatPlugin").count == 1, "cache hit: no further events", "\(recorder.dids("CatPlugin").count)")

    // 3. Failure + retry.
    var thrown: [Error] = []
    for _ in 0..<2 { do { _ = try MissingConn.loadIfNeeded() } catch { thrown.append(error) } }
    let miss = recorder.dids("MissingPlugin")
    check(thrown.count == 2, "failure: both attempts throw")
    check(miss.count == 2, "failure+retry: one event per attempt", "\(miss.count)")
    if let e = miss.first {
        if case .failedToOpen(let p, _)? = e.error {
            check(p == execPath("MissingPlugin"), "failure: error path", p)
        } else {
            check(false, "failure: error is failedToOpen", "\(String(describing: e.error))")
        }
        check(e.error == thrown.first as? DyLibError, "failure: logged error == thrown error")
        check(e.secs >= 0 && e.secs < 10, "failure: duration sane", "\(e.secs)")
    }
    check(!MissingConn.isLoaded, "failure: not cached")

    // 4. Concurrency.
    let ok = Recorder()
    let start = DispatchSemaphore(value: 0)
    let group = DispatchGroup()
    let n = 128
    for _ in 0..<n {
        group.enter()
        Thread.detachNewThread {
            start.wait()
            if (try? ConcConn.loadIfNeeded()) != nil { ok.add(Event(kind: "ok", interface: "", path: "", secs: 0, error: nil)) }
            group.leave()
        }
    }
    for _ in 0..<n { start.signal() }
    let finished = group.wait(timeout: .now() + 30) == .success
    check(finished, "concurrency: no hang")
    check(ok.all.count == n, "concurrency: all threads got an instance", "\(ok.all.count)")
    check(recorder.dids("ConcPlugin").count == 1, "concurrency: exactly one load event", "\(recorder.dids("ConcPlugin").count)")
    check(recorder.wills("ConcPlugin").count == 1, "concurrency: exactly one willLoad")

    // 5. Logger re-entering DyLibLoader (open/close/load another library) must not deadlock.
    _ = try? ReentConn.loadIfNeeded()
    _ = try? ReentMissingConn.loadIfNeeded()
    check(ReentrantLog.blocked.isEmpty, "reentrant logger: no deadlock on DyLibLoader lock", "\(ReentrantLog.blocked)")
    check(recorder.dids("ReentPlugin").count == 1 && recorder.dids("ReentMissing").count == 1, "reentrant logger: events delivered")

    // 6. No logger: nothing recorded, still works.
    let before = recorder.all.count
    check(SilentConn.instance.speak() == "Meow", "no logger: works")
    check(recorder.all.count == before, "no logger: silent")
}

switch CommandLine.arguments.dropFirst().first ?? "checks" {
case "trap":
    emit("TRAP calling non-throwing proxy")
    _ = MissingConn.instance.speak()
    emit("TRAP unreachable")
case "dog":
    let first = DogConn.instance.speak()
    let second = DogConn.instance.speak()
    print("DOG \(first)")
    check(first == "Woof! (and does a backflip)", "plugin-to-plugin: speaks", first)
    check(second == first, "plugin-to-plugin: second call same")
    check(recorder.dids("LoggedDogPlugin").count == 1, "plugin-to-plugin: host logged dog once")
    exit(failures == 0 ? 0 : 1)
default:
    runChecks()
    print(failures == 0 ? "ALL CHECKS PASSED" : "\(failures) CHECK(S) FAILED")
    exit(failures == 0 ? 0 : 1)
}
