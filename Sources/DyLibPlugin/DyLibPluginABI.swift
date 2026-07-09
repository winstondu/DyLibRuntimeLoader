public enum DyLibPluginABI {
    /// Bumped whenever the C-boundary contract (entry symbol signature or
    /// descriptor layout) changes incompatibly.
    public static let current = 1

    /// The fixed entry symbol every plugin binary exports. Lookups are scoped
    /// to a dlopen handle, so all plugins can share the same name.
    public static let entrySymbol = "dylib_plugin_main"

    /// Prefix of the per-plugin marker symbol read by the build-time verifier.
    public static let markerSymbolPrefix = "dylib_plugin_id_"

    public static func markerSymbol(forPluginID id: PluginID) -> String {
        markerSymbolPrefix + sanitizedSymbolComponent(id.rawValue)
    }

    /// Maps an arbitrary identifier onto the C symbol character set.
    public static func sanitizedSymbolComponent(_ identifier: String) -> String {
        String(identifier.map { character in
            character.isASCII && (character.isLetter || character.isNumber) ? character : "_"
        })
    }
}
