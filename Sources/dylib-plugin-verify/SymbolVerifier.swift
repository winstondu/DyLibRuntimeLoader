enum SymbolVerifier {
    static let entrySymbol = "dylib_plugin_main"
    static let markerSymbolPrefix = "dylib_plugin_id_"

    /// Pure verification over an already-listed symbol set. Returns one
    /// human-readable failure per unmet requirement; empty means verified.
    static func failures(
        forBinaryAt binaryPath: String,
        exportedSymbols: Set<String>,
        expectedPluginIDs: [String]
    ) -> [String] {
        var failures = [String]()
        if !contains(exportedSymbols, entrySymbol) {
            failures.append(
                "MISSING ENTRY SYMBOL: \(binaryPath) does not export \(entrySymbol). "
                    + "Is the plugin's @PluginMain type compiled into this product, "
                    + "and is the product a dynamic library?")
        }
        for pluginID in expectedPluginIDs {
            let marker = markerSymbolPrefix + Sanitizer.sanitizedSymbolComponent(pluginID)
            if !contains(exportedSymbols, marker) {
                failures.append(
                    "MISSING MARKER: \(binaryPath) does not export \(marker) — "
                        + "expected plugin id \"\(pluginID)\". "
                        + "The embedded plugin may be a different/stale plugin.")
            }
        }
        return failures
    }

    /// Accepts both the ELF spelling (`name`) and the Mach-O symbol-table
    /// spelling with a leading underscore (`_name`).
    static func contains(_ symbols: Set<String>, _ symbol: String) -> Bool {
        symbols.contains(symbol) || symbols.contains("_" + symbol)
    }
}
