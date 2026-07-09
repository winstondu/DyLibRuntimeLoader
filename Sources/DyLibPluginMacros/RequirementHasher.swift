/// Deterministic FNV-1a 64-bit hashing for interface compatibility hashes.
/// Never use Swift's `Hasher` here: it is seeded per process, so its values
/// cannot be compared across separately compiled binaries or builds.
enum RequirementHasher {
    /// Collapses every run of whitespace to a single space and trims leading
    /// and trailing whitespace, so formatting-only changes to a requirement
    /// do not change the hash.
    static func normalize(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func hash(normalizedRequirements: [String], inheritedTypes: [String]) -> String {
        let components = normalizedRequirements.sorted() + inheritedTypes.sorted()
        let input = components.joined(separator: ";")
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in input.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        let hex = String(hash, radix: 16)
        let padding = String(repeating: "0", count: max(0, 16 - hex.count))
        return "fnv1a:" + padding + hex
    }
}
