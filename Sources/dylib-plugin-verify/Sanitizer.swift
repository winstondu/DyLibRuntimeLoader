enum Sanitizer {
    /// Maps an arbitrary identifier onto the C symbol character set.
    /// Must stay in sync with `DyLibPluginABI.sanitizedSymbolComponent(_:)`.
    static func sanitizedSymbolComponent(_ identifier: String) -> String {
        String(identifier.map { character in
            character.isASCII && (character.isLetter || character.isNumber) ? character : "_"
        })
    }
}
