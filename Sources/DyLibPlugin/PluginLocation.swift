import Foundation

/// A resolved on-disk location of a plugin binary. Resolution happens at
/// construction so the value stays a plain, Sendable path.
public struct PluginLocation: Hashable, Sendable {
    public let path: String

    public init(path: String) {
        self.path = path
    }

    public static func path(_ path: String) -> PluginLocation {
        PluginLocation(path: path)
    }

    /// Resolves the executable inside `<bundle>/Frameworks/<name>.framework`.
    public static func framework(name: String, in bundle: Bundle = .main) throws -> PluginLocation {
        guard let frameworksURL = bundle.privateFrameworksURL else {
            throw PluginError.frameworkNotFound(name: name, bundle: bundle.bundlePath)
        }
        let frameworkURL = frameworksURL.appendingPathComponent("\(name).framework")
        let candidates = [
            frameworkURL.appendingPathComponent(name),
            frameworkURL.appendingPathComponent("Versions/Current/\(name)"),
            frameworkURL.appendingPathComponent("Versions/A/\(name)"),
        ]
        guard let executable = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw PluginError.frameworkNotFound(name: name, bundle: bundle.bundlePath)
        }
        return PluginLocation(path: executable.path)
    }
}
