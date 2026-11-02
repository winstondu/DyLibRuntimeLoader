import DyLibRuntimeLoader
import Foundation

/// Prints one line per real lazy load in Debug builds and nothing in Release.
///
/// Shared by the app and every plugin that declares a connection, so it ships
/// as one framework that the app links and embeds, like the interfaces (the
/// golden rule).
public enum DebugLogger: DyLibLoadLogger {
    public static func didLoad(_ event: DyLibLoadResult) {
        #if DEBUG
        let framework = (event.path as NSString).lastPathComponent
        let milliseconds = String(format: "%.2f", event.duration * 1000)
        let outcome = event.error.map { "error: \($0.localizedDescription)" } ?? "ok"
        NSLog("[DyLib] %@ from %@ in %@ ms (%@)", event.interface, framework, milliseconds, outcome)
        #endif
    }
}
