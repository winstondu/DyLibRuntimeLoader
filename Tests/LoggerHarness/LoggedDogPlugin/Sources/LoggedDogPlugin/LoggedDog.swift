import AnimalInterface
import DyLibRuntimeLoader
import Foundation
import TrickInterface

/// The plugin's own logger for its own (plugin-to-plugin) connection.
enum DogLog: DyLibLoadLogger {
    static func willLoad(_ e: DyLibLoadStart) {
        fputs("DOGLOG willLoad interface=\(e.interface) path=\(e.path)\n", stderr)
    }
    static func didLoad(_ e: DyLibLoadResult) {
        fputs("DOGLOG didLoad interface=\(e.interface) path=\(e.path) duration=\(e.duration) error=\(e.error.map { "\($0)" } ?? "nil")\n", stderr)
    }
}

@DyLibConnect(Trick.self, framework: "BackflipPlugin", logger: DogLog.self)
enum TrickConn {}

@DyLibExport(Animal.self)
public struct LoggedDog: Animal {
    public init() {}
    public func speak() -> String { "Woof! (and does a \(TrickConn.instance.perform()))" }
}
