import Darwin
import Foundation

private typealias LegacyInitFunction = @convention(c) () -> UnsafeMutableRawPointer
private let legacyOpenFlags: DyLibOpenFlags = [.lazy, .global]

@available(*, deprecated, message: "Use DyLibError")
private func legacyError(from error: Error) -> DynamicFrameworkLoaderError {
    guard let error = error as? DyLibError else { return .unknown }
    switch error {
    case .symbolNotFound:
        return .symbolNotFound
    case .failedToOpen(_, let reason):
        return .failedToOpenFile(reason: reason)
    default:
        return .unknown
    }
}

@available(*, deprecated, message: "Use @DyLibInterface/@DyLibExport with DyLibLoader")
public func dyLibLoad(fromFramework framework: FrameworkName) throws {
    try dyLibLoad(fromPath: framework.getAppendFilePath())
}

@available(*, deprecated, message: "Use @DyLibInterface/@DyLibExport with DyLibLoader")
public func dyLibLoad(fromPath path: String) throws {
    do {
        _ = try DyLibLoader.shared.open(DyLibLibrary(path: path, flags: legacyOpenFlags))
    } catch {
        throw legacyError(from: error)
    }
}

@available(*, deprecated, message: "Use @DyLibInterface/@DyLibExport with DyLibLoader")
public func dyLibLoad<T>(
    withSymbol symbolName: String,
    fromFramework framework: FrameworkName,
    forType type: T.Type
) throws -> T {
    try dyLibLoad(
        withSymbol: symbolName,
        fromPath: framework.getAppendFilePath(),
        forType: type
    )
}

@available(*, deprecated, message: "Use @DyLibInterface/@DyLibExport with DyLibLoader")
public func dyLibLoad<T>(
    withSymbol symbolName: String,
    fromPath path: String,
    forType type: T.Type
) throws -> T {
    do {
        let library = DyLibLibrary(path: path, flags: legacyOpenFlags)
        let handle = try DyLibLoader.shared.open(library)
        let symbol = try DyLibLoader.shared.symbolPointer(named: symbolName, in: handle)
        let entryFunction = unsafeBitCast(symbol, to: LegacyInitFunction.self)
        return Unmanaged<DyLibBuilder<T>>
            .fromOpaque(entryFunction())
            .takeRetainedValue()
            .build()
    } catch {
        throw legacyError(from: error)
    }
}
