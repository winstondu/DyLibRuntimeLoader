import Foundation

@available(*, deprecated, message: "Use DyLibError")
public enum DynamicFrameworkLoaderError: Error {
    case symbolNotFound
    case failedToOpenFile(reason: String)
    case unknown
}

@available(*, deprecated, message: "Use DyLibError")
extension DynamicFrameworkLoaderError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .symbolNotFound:
            return "Symbol is not found"
        case .failedToOpenFile(let reason):
            return "Failed to open file with reason: \(reason)"
        case .unknown:
            return "Unknown error"
        }
    }
}
