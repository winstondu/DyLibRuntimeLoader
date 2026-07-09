public enum VersionRequirement: Hashable, Sendable, Codable {
    /// Exactly the given version.
    case exact(SemanticVersion)
    /// At least the given version and below the next major version.
    case from(SemanticVersion)
    /// At least the given version, with no upper bound.
    case atLeast(SemanticVersion)

    public func isSatisfied(by version: SemanticVersion) -> Bool {
        switch self {
        case .exact(let required):
            return version == required
        case .from(let required):
            return version >= required && version.major == required.major
        case .atLeast(let required):
            return version >= required
        }
    }
}

extension VersionRequirement: CustomStringConvertible {
    public var description: String {
        switch self {
        case .exact(let version):
            return "== \(version)"
        case .from(let version):
            return ">= \(version), < \(version.major + 1).0.0"
        case .atLeast(let version):
            return ">= \(version)"
        }
    }
}
