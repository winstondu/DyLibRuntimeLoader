import Foundation

@available(*, deprecated, message: "Use DyLibLibrary(path:dependencies:)")
public enum Directory {
    case frameworks
    case resources
    case executables
    case custom(folder: String)

    public var rawValue: String {
        switch self {
        case .frameworks: return "Frameworks"
        case .resources: return ""
        case .executables: return "Executables"
        case .custom(let folder): return folder
        }
    }
}

@available(*, deprecated, message: "Use DyLibLibrary(path:dependencies:)")
public enum FrameworkName {
    case xcFramework(name: String, bundle: Bundle = .main, directory: Directory = .frameworks)
    case framework(name: String, Bundle: Bundle = .main, directory: Directory = .frameworks)

    var fileExtension: String {
        switch self {
        case .xcFramework: return "xcframework"
        case .framework: return "framework"
        }
    }

    public func getAppendFilePath() throws -> String {
        switch self {
        case .xcFramework(let name, let bundle, let directory):
            let root = try filePath(
                name: name,
                extension: fileExtension,
                bundle: bundle,
                directory: directory
            )
            let infoURL = URL(fileURLWithPath: root).appendingPathComponent("Info.plist")
            let data: Data
            do {
                data = try Data(contentsOf: infoURL)
            } catch {
                throw DynamicFrameworkLoaderError.failedToOpenFile(reason: "Could not read \(infoURL.path): \(error)")
            }
            let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
            guard
                let dictionary = plist as? [String: Any],
                let libraries = dictionary["AvailableLibraries"] as? [[String: Any]],
                let library = libraries.first(where: Self.matchesCurrentPlatform),
                let identifier = library["LibraryIdentifier"] as? String,
                let libraryPath = library["LibraryPath"] as? String
            else {
                throw DynamicFrameworkLoaderError.failedToOpenFile(
                    reason: "No XCFramework slice matches platform \(Self.platform), architecture \(Self.architecture), variant \(Self.variant ?? "none")"
                )
            }
            let selected = URL(fileURLWithPath: root)
                .appendingPathComponent(identifier)
                .appendingPathComponent(libraryPath)
            if selected.pathExtension == "framework" {
                return selected.appendingPathComponent(selected.deletingPathExtension().lastPathComponent).path
            }
            return selected.path

        case .framework(let name, let bundle, let directory):
            return try filePath(
                name: name,
                extension: fileExtension,
                bundle: bundle,
                directory: directory
            ) + "/\(name)"
        }
    }

    private static func matchesCurrentPlatform(_ library: [String: Any]) -> Bool {
        guard
            library["SupportedPlatform"] as? String == platform,
            let architectures = library["SupportedArchitectures"] as? [String],
            architectures.contains(architecture)
        else { return false }
        return library["SupportedPlatformVariant"] as? String == variant
    }

    private static var platform: String {
        #if os(macOS)
        return "macos"
        #elseif os(iOS)
        return "ios"
        #else
        return "unknown"
        #endif
    }

    private static var variant: String? {
        #if targetEnvironment(simulator)
        return "simulator"
        #elseif targetEnvironment(macCatalyst)
        return "maccatalyst"
        #else
        return nil
        #endif
    }

    private static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    private func filePath(
        name: String,
        extension fileExtension: String,
        bundle: Bundle,
        directory: Directory
    ) throws -> String {
        guard let path = bundle.path(
            forResource: name,
            ofType: fileExtension,
            inDirectory: directory.rawValue
        ) else {
            throw DynamicFrameworkLoaderError.failedToOpenFile(
                reason: "\"\(name).\(fileExtension)\" is not found in bundle \(bundle.description)"
            )
        }
        return path
    }
}
