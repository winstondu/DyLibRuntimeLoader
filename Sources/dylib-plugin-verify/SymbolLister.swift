import Foundation

enum SymbolLister {
    private static let commandCandidates: [[String]] = [
        ["llvm-nm", "-gU"],
        ["nm", "-gU"],
        ["nm", "-gD", "--defined-only"],
        ["nm", "-g", "--defined-only"],
    ]

    static func exportedSymbols(ofBinaryAt path: String) -> Result<Set<String>, VerificationFailure> {
        var lastFailureMessage = ""
        var emptySuccess: Set<String>?
        for candidate in commandCandidates {
            switch run(command: candidate + [path]) {
            case .success(let output):
                let symbols = parseSymbols(fromNMOutput: output)
                if !symbols.isEmpty {
                    return .success(symbols)
                }
                // GNU/llvm nm exit 0 with "no symbols" on stripped ELF
                // binaries whose exports live only in the dynamic symbol
                // table; keep trying the -D variants before giving up.
                emptySuccess = symbols
            case .failure(let failure):
                lastFailureMessage = failure.message
            }
        }
        if let emptySuccess {
            return .success(emptySuccess)
        }
        var message = ""
        if !lastFailureMessage.isEmpty {
            message += lastFailureMessage.hasSuffix("\n") ? lastFailureMessage : lastFailureMessage + "\n"
        }
        message += "could not run nm/llvm-nm — install binutils or Xcode command line tools"
        return .failure(VerificationFailure(message))
    }

    private static func run(command: [String]) -> Result<String, VerificationFailure> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = command
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.standardOutput = standardOutput
        process.standardError = standardError
        do {
            try process.run()
        } catch {
            return .failure(VerificationFailure("\(command[0]): \(error.localizedDescription)"))
        }
        let outputData = standardOutput.fileHandleForReading.readDataToEndOfFile()
        let errorData = standardError.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let errorText = String(decoding: errorData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let message = errorText.isEmpty
                ? "\(command[0]) exited with status \(process.terminationStatus)"
                : errorText
            return .failure(VerificationFailure(message))
        }
        return .success(String(decoding: outputData, as: UTF8.self))
    }

    /// Each meaningful nm line is "ADDR TYPE NAME" (or "TYPE NAME" for
    /// undefined-address entries); the last whitespace-separated token is the
    /// symbol name. Also records a variant with any leading underscore
    /// stripped so Mach-O (`_name`) and ELF (`name`) spellings both match.
    private static func parseSymbols(fromNMOutput output: String) -> Set<String> {
        var symbols = Set<String>()
        for line in output.split(separator: "\n") {
            if line.lowercased().contains("no symbols") { continue }
            let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard tokens.count >= 2, let lastToken = tokens.last else { continue }
            var symbol = String(lastToken)
            // ELF symbol versioning suffixes ("name@@VERSION") are not part
            // of the exported name.
            if let versionMarker = symbol.firstIndex(of: "@") {
                symbol = String(symbol[..<versionMarker])
            }
            guard !symbol.isEmpty else { continue }
            symbols.insert(symbol)
            if symbol.hasPrefix("_") {
                symbols.insert(String(symbol.dropFirst()))
            }
        }
        return symbols
    }
}
