import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

@main
struct DyLibPluginVerify {
    private static let usage = """
        usage: dylib-plugin-verify [--expect-id <plugin-id>]... <binary-or-framework-path>...

        Verifies that each built plugin binary exports the DyLibPlugin entry symbol
        \(SymbolVerifier.entrySymbol) and, for every --expect-id, the marker symbol
        \(SymbolVerifier.markerSymbolPrefix)<sanitized-id>. Both Mach-O (leading
        underscore) and ELF symbol spellings are accepted.

        Paths may be a raw dylib binary, a .framework directory, or an .xcframework
        (every framework slice is verified).

        Exit codes:
          0  all binaries verified
          1  verification failure
          2  usage or path error
          3  nm/llvm-nm unavailable
        """

    static func main() {
        let parsed: CommandLineArguments
        switch CommandLineArguments.parse(Array(CommandLine.arguments.dropFirst())) {
        case .success(let arguments):
            parsed = arguments
        case .failure(let failure):
            printError("error: \(failure.message)")
            printError(usage)
            exit(2)
        }

        if parsed.showsHelp {
            print(usage)
            exit(0)
        }

        var hadPathError = false
        var hadVerificationFailure = false

        for path in parsed.paths {
            switch BinaryLocator.binaries(atPath: path) {
            case .failure(let failure):
                printError("error: \(failure.message)")
                hadPathError = true
            case .success(let binaries):
                for binary in binaries {
                    switch verify(binaryAt: binary.binaryPath, expectedPluginIDs: parsed.expectedPluginIDs) {
                    case .verified:
                        break
                    case .failed:
                        hadVerificationFailure = true
                    }
                }
            }
        }

        if hadPathError { exit(2) }
        if hadVerificationFailure { exit(1) }
        exit(0)
    }

    private enum BinaryOutcome {
        case verified
        case failed
    }

    private static func verify(binaryAt binaryPath: String, expectedPluginIDs: [String]) -> BinaryOutcome {
        let symbols: Set<String>
        switch SymbolLister.exportedSymbols(ofBinaryAt: binaryPath) {
        case .success(let exportedSymbols):
            symbols = exportedSymbols
        case .failure(let failure):
            printError(failure.message)
            exit(3)
        }

        let failures = SymbolVerifier.failures(
            forBinaryAt: binaryPath,
            exportedSymbols: symbols,
            expectedPluginIDs: expectedPluginIDs)
        guard failures.isEmpty else {
            for failure in failures {
                printError(failure)
            }
            return .failed
        }

        let markerSummary = expectedPluginIDs.map { " and marker for \($0)" }.joined()
        print("OK: \(binaryPath) exports \(SymbolVerifier.entrySymbol)\(markerSummary)")
        return .verified
    }

    private static func printError(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
