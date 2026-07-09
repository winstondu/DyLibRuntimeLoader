import Foundation

enum BinaryLocator {
    /// Resolves a command-line path to the concrete binaries to verify:
    /// a `.framework` directory yields its single binary, an `.xcframework`
    /// yields one binary per framework slice, and anything else is treated
    /// as the binary itself.
    static func binaries(atPath rawPath: String) -> Result<[(name: String, binaryPath: String)], VerificationFailure> {
        var path = rawPath
        while path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        let fileManager = FileManager.default
        var isDirectory = ObjCBool(false)
        let exists = fileManager.fileExists(atPath: path, isDirectory: &isDirectory)

        if path.hasSuffix(".framework"), exists, isDirectory.boolValue {
            return frameworkBinary(inFrameworkAt: path).map { [$0] }
        }
        if path.hasSuffix(".xcframework") {
            guard exists, isDirectory.boolValue else {
                return .failure(VerificationFailure("no xcframework directory at \(path)"))
            }
            return xcframeworkBinaries(at: path)
        }
        guard exists else {
            return .failure(VerificationFailure("no such file: \(path)"))
        }
        guard !isDirectory.boolValue else {
            return .failure(VerificationFailure("\(path) is a directory, not a plugin binary"))
        }
        return .success([(name: URL(fileURLWithPath: path).lastPathComponent, binaryPath: path)])
    }

    private static func frameworkBinary(
        inFrameworkAt path: String
    ) -> Result<(name: String, binaryPath: String), VerificationFailure> {
        let frameworkURL = URL(fileURLWithPath: path)
        let name = frameworkURL.deletingPathExtension().lastPathComponent
        let candidatePaths = [
            frameworkURL.appendingPathComponent(name).path,
            frameworkURL.appendingPathComponent("Versions").appendingPathComponent("A")
                .appendingPathComponent(name).path,
        ]
        for candidatePath in candidatePaths {
            var isDirectory = ObjCBool(false)
            if FileManager.default.fileExists(atPath: candidatePath, isDirectory: &isDirectory),
                !isDirectory.boolValue {
                return .success((name: name, binaryPath: candidatePath))
            }
        }
        return .failure(
            VerificationFailure(
                "framework at \(path) contains no binary named \(name) "
                    + "(checked \(candidatePaths.joined(separator: " and ")))"))
    }

    private static func xcframeworkBinaries(
        at path: String
    ) -> Result<[(name: String, binaryPath: String)], VerificationFailure> {
        let fileManager = FileManager.default
        let xcframeworkURL = URL(fileURLWithPath: path)
        let entryNames: [String]
        do {
            entryNames = try fileManager.contentsOfDirectory(atPath: path).sorted()
        } catch {
            return .failure(VerificationFailure("could not list \(path): \(error.localizedDescription)"))
        }

        var binaries = [(name: String, binaryPath: String)]()
        for entryName in entryNames {
            let sliceURL = xcframeworkURL.appendingPathComponent(entryName)
            var isDirectory = ObjCBool(false)
            guard fileManager.fileExists(atPath: sliceURL.path, isDirectory: &isDirectory),
                isDirectory.boolValue
            else { continue }

            let frameworkNames = ((try? fileManager.contentsOfDirectory(atPath: sliceURL.path)) ?? [])
                .filter { $0.hasSuffix(".framework") }
                .sorted()
            for frameworkName in frameworkNames {
                let frameworkPath = sliceURL.appendingPathComponent(frameworkName).path
                switch frameworkBinary(inFrameworkAt: frameworkPath) {
                case .success(let binary):
                    binaries.append(binary)
                case .failure(let failure):
                    return .failure(failure)
                }
            }
        }
        guard !binaries.isEmpty else {
            return .failure(VerificationFailure("no framework slices found in \(path)"))
        }
        return .success(binaries)
    }
}
