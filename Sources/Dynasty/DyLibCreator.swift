//
//
//  Created by Winston Du on 17/7/26.
//

import Foundation

/// Use the attribute `@_cdecl(symbol_name)` for the method which call this method.
///
/// Example:
///  ```
///    @_cdecl("create_foo")
///    public func createFoo() -> UnsafeMutableRawPointer {
///       return dyLibCreator(factory: FooClass(), forType: FooProtocol.self)
///    }
///  ```
/// - Parameters:
///   - factory: Return the concrete implementation of protocol type
///   - forType: Protocol type
/// - Returns: `UnsafeMutableRawPointer` which will be handle of the loader later
@available(*, deprecated, message: "Use @DyLibInterface/@DyLibExport with DyLibLoader")
public func dyLibCreator<T>(factory: @autoclosure @escaping () -> T, forType: T.Type) -> UnsafeMutableRawPointer {
    return Unmanaged.passRetained(DyLibBuilder<T>(factory: factory())).toOpaque()
}
