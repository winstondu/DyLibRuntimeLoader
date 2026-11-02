import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing
@testable import DyLibRuntimeLoaderMacros

private let testMacros: [String: MacroSpec] = [
    "DyLibInterface": MacroSpec(type: DyLibInterfaceMacro.self),
    "DyLibExport": MacroSpec(type: DyLibExportMacro.self),
    "DyLibConnect": MacroSpec(
        type: DyLibConnectMacro.self,
        conformances: ["DyLibPluginConnection"]
    ),
]

private func assertExpansion(
    _ originalSource: String,
    expandedSource: String,
    diagnostics: [DiagnosticSpec] = [],
    sourceLocation: SourceLocation = #_sourceLocation
) {
    SwiftSyntaxMacrosGenericTestSupport.assertMacroExpansion(
        originalSource,
        expandedSource: expandedSource,
        diagnostics: diagnostics,
        macroSpecs: testMacros,
        failureHandler: {
            Issue.record(Comment(rawValue: $0.message), sourceLocation: sourceLocation)
        }
    )
}

@Suite struct DyLibRuntimeLoaderMacroTests {
    @Test func interfaceExpansion() {
        assertExpansion(
            """
            @DyLibInterface
            public protocol Animal {
                func speak() -> String
            }
            """,
            expandedSource: """
            public protocol Animal {
                func speak() -> String
            }

            public enum AnimalPluginSpec: DyLibPluginSpec {
                public typealias Interface = any Animal
                public static var symbolName: String {
                    "__dylib_entry_Animal"
                }
                public static func load(from path: String) throws -> any Animal {
                    try DyLibLoader.shared.load(AnimalPluginSpec.self, from: path)
                }
                public static func load(from library: DyLibLibrary) throws -> any Animal {
                    try DyLibLoader.shared.load(AnimalPluginSpec.self, from: library)
                }
                public static func loadWithHandle(from path: String) throws -> (instance: any Animal, handle: DyLibHandle) {
                    try DyLibLoader.shared.loadWithHandle(AnimalPluginSpec.self, from: DyLibLibrary(path: path))
                }
                public static func loadWithHandle(from library: DyLibLibrary) throws -> (instance: any Animal, handle: DyLibHandle) {
                    try DyLibLoader.shared.loadWithHandle(AnimalPluginSpec.self, from: library)
                }
            }

            public struct AnimalLazyProxy: Animal {
                private let _resolve: () throws -> any Animal

                public init(_ resolve: @escaping () throws -> any Animal) {
                    self._resolve = resolve
                }

                private func _resolved() -> any Animal {
                    do {
                        return try _resolve()
                    } catch {
                        fatalError("DyLib plugin for Animal failed to load: \\(error.localizedDescription)")
                    }
                }

                public func speak() -> String {
                    _resolved().speak()
                }
            }
            """
        )
    }

    @Test func interfaceLazyProxySupportedRequirementsExpansion() {
        assertExpansion(
            """
            @DyLibInterface
            public protocol Service {
                func render<T>(_ value: T, count: Int = 1, labeled amount: Int) -> String where T: CustomStringConvertible
                func fetch(_ id: Int) throws -> String
                func refresh() async
                func load() async throws -> Int
                var name: String { get }
                var remoteName: String { get async throws }
            }
            """,
            expandedSource: """
            public protocol Service {
                func render<T>(_ value: T, count: Int = 1, labeled amount: Int) -> String where T: CustomStringConvertible
                func fetch(_ id: Int) throws -> String
                func refresh() async
                func load() async throws -> Int
                var name: String { get }
                var remoteName: String { get async throws }
            }

            public enum ServicePluginSpec: DyLibPluginSpec {
                public typealias Interface = any Service
                public static var symbolName: String {
                    "__dylib_entry_Service"
                }
                public static func load(from path: String) throws -> any Service {
                    try DyLibLoader.shared.load(ServicePluginSpec.self, from: path)
                }
                public static func load(from library: DyLibLibrary) throws -> any Service {
                    try DyLibLoader.shared.load(ServicePluginSpec.self, from: library)
                }
                public static func loadWithHandle(from path: String) throws -> (instance: any Service, handle: DyLibHandle) {
                    try DyLibLoader.shared.loadWithHandle(ServicePluginSpec.self, from: DyLibLibrary(path: path))
                }
                public static func loadWithHandle(from library: DyLibLibrary) throws -> (instance: any Service, handle: DyLibHandle) {
                    try DyLibLoader.shared.loadWithHandle(ServicePluginSpec.self, from: library)
                }
            }

            public struct ServiceLazyProxy: Service {
                private let _resolve: () throws -> any Service

                public init(_ resolve: @escaping () throws -> any Service) {
                    self._resolve = resolve
                }

                private func _resolved() -> any Service {
                    do {
                        return try _resolve()
                    } catch {
                        fatalError("DyLib plugin for Service failed to load: \\(error.localizedDescription)")
                    }
                }

                public func render<T>(_ value: T, count: Int, labeled amount: Int) -> String where T: CustomStringConvertible {
                    _resolved().render(value, count: count, labeled: amount)
                }

                public func fetch(_ id: Int) throws -> String {
                    try (try _resolve()).fetch(id)
                }

                public func refresh() async {
                    await _resolved().refresh()
                }

                public func load() async throws -> Int {
                    try await (try _resolve()).load()
                }

                public var name: String {
                    _resolved().name
                }

                public var remoteName: String {
                    get async throws {
                        try await (try _resolve()).remoteName
                    }
                }
            }
            """
        )
    }

    @Test func interfaceProxyFalseSuppressesProxy() {
        assertExpansion(
            """
            @DyLibInterface(proxy: false)
            public protocol Stateful {
                mutating func update()
            }
            """,
            expandedSource: """
            public protocol Stateful {
                mutating func update()
            }

            public enum StatefulPluginSpec: DyLibPluginSpec {
                public typealias Interface = any Stateful
                public static var symbolName: String {
                    "__dylib_entry_Stateful"
                }
                public static func load(from path: String) throws -> any Stateful {
                    try DyLibLoader.shared.load(StatefulPluginSpec.self, from: path)
                }
                public static func load(from library: DyLibLibrary) throws -> any Stateful {
                    try DyLibLoader.shared.load(StatefulPluginSpec.self, from: library)
                }
                public static func loadWithHandle(from path: String) throws -> (instance: any Stateful, handle: DyLibHandle) {
                    try DyLibLoader.shared.loadWithHandle(StatefulPluginSpec.self, from: DyLibLibrary(path: path))
                }
                public static func loadWithHandle(from library: DyLibLibrary) throws -> (instance: any Stateful, handle: DyLibHandle) {
                    try DyLibLoader.shared.loadWithHandle(StatefulPluginSpec.self, from: library)
                }
            }
            """
        )
    }

    @Test func unsupportedProxyRequirementDiagnosesAndKeepsSpec() {
        assertExpansion(
            """
            @DyLibInterface
            public protocol Stateful {
                mutating func update()
            }
            """,
            expandedSource: """
            public protocol Stateful {
                mutating func update()
            }

            public enum StatefulPluginSpec: DyLibPluginSpec {
                public typealias Interface = any Stateful
                public static var symbolName: String {
                    "__dylib_entry_Stateful"
                }
                public static func load(from path: String) throws -> any Stateful {
                    try DyLibLoader.shared.load(StatefulPluginSpec.self, from: path)
                }
                public static func load(from library: DyLibLibrary) throws -> any Stateful {
                    try DyLibLoader.shared.load(StatefulPluginSpec.self, from: library)
                }
                public static func loadWithHandle(from path: String) throws -> (instance: any Stateful, handle: DyLibHandle) {
                    try DyLibLoader.shared.loadWithHandle(StatefulPluginSpec.self, from: DyLibLibrary(path: path))
                }
                public static func loadWithHandle(from library: DyLibLibrary) throws -> (instance: any Stateful, handle: DyLibHandle) {
                    try DyLibLoader.shared.loadWithHandle(StatefulPluginSpec.self, from: library)
                }
            }
            """,
            diagnostics: [DiagnosticSpec(
                message: "@DyLibInterface cannot generate a lazy proxy for requirement 'update': mutating function requirements are unsupported. Mark the interface @DyLibInterface(proxy: false) to suppress proxy generation.",
                line: 3,
                column: 19
            )]
        )
    }

    @Test func exportExpansion() {
        assertExpansion(
            """
            @DyLibExport(Animal.self)
            public struct Cat: Animal {}
            """,
            expandedSource: """
            public struct Cat: Animal {}

            @_cdecl("__dylib_entry_Animal")
            public func __dylib_export_Cat() -> UnsafeMutableRawPointer {
                dyLibMakeEntry(spec: AnimalPluginSpec.self, factory: {
                        Cat() as any Animal
                    })
            }
            """
        )
    }

    @Test func nonProtocolDiagnostic() {
        assertExpansion(
            """
            @DyLibInterface
            public struct NotAProtocol {}
            """,
            expandedSource: """
            public struct NotAProtocol {}
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@DyLibInterface can only be attached to a protocol",
                    line: 1,
                    column: 1
                ),
            ]
        )
    }

    @Test func exportRequiresMetatypeDiagnostic() {
        assertExpansion(
            """
            @DyLibExport(Animal)
            public struct Cat: Animal {}
            """,
            expandedSource: """
            public struct Cat: Animal {}
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@DyLibExport requires an interface metatype expression such as Animal.self",
                    line: 1,
                    column: 1
                ),
            ]
        )
    }

    @Test func qualifiedInterfaceExpansion() {
        assertExpansion(
            """
            @DyLibExport(Namespace.Animal.self)
            public struct Cat: Namespace.Animal {}
            """,
            expandedSource: """
            public struct Cat: Namespace.Animal {}

            @_cdecl("__dylib_entry_Animal")
            public func __dylib_export_Cat() -> UnsafeMutableRawPointer {
                dyLibMakeEntry(spec: Namespace.AnimalPluginSpec.self, factory: {
                        Cat() as any Namespace.Animal
                    })
            }
            """
        )
    }

    @Test func nestedDeclarationsAreRejected() {
        assertExpansion(
            """
            public enum Namespace {
                @DyLibInterface
                public protocol Animal {}
            }
            """,
            expandedSource: """
            public enum Namespace {
                public protocol Animal {}
            }
            """,
            diagnostics: [DiagnosticSpec(
                message: "@DyLibInterface must be applied to a top-level protocol",
                line: 3,
                column: 21
            )]
        )
        assertExpansion(
            """
            public enum Namespace {
                @DyLibExport(Animal.self)
                public struct Cat: Animal {}
            }
            """,
            expandedSource: """
            public enum Namespace {
                public struct Cat: Animal {}
            }
            """,
            diagnostics: [DiagnosticSpec(
                message: "@DyLibExport must be applied to a top-level type",
                line: 2,
                column: 5
            )]
        )
    }

    @Test func genericExportIsRejected() {
        assertExpansion(
            """
            @DyLibExport(Animal.self)
            public struct Box<T>: Animal {}
            """,
            expandedSource: """
            public struct Box<T>: Animal {}
            """,
            diagnostics: [DiagnosticSpec(
                message: "@DyLibExport cannot be applied to a generic type",
                line: 1,
                column: 1
            )]
        )
    }

    @Test func versionedInterfaceExpansion() {
        assertExpansion(
            """
            @DyLibInterface(version: 2)
            public protocol Animal {}
            """,
            expandedSource: """
            public protocol Animal {}

            public enum AnimalPluginSpec: DyLibPluginSpec {
                public typealias Interface = any Animal
                public static var symbolName: String {
                    "__dylib_entry_Animal_v2"
                }
                public static func load(from path: String) throws -> any Animal {
                    try DyLibLoader.shared.load(AnimalPluginSpec.self, from: path)
                }
                public static func load(from library: DyLibLibrary) throws -> any Animal {
                    try DyLibLoader.shared.load(AnimalPluginSpec.self, from: library)
                }
                public static func loadWithHandle(from path: String) throws -> (instance: any Animal, handle: DyLibHandle) {
                    try DyLibLoader.shared.loadWithHandle(AnimalPluginSpec.self, from: DyLibLibrary(path: path))
                }
                public static func loadWithHandle(from library: DyLibLibrary) throws -> (instance: any Animal, handle: DyLibHandle) {
                    try DyLibLoader.shared.loadWithHandle(AnimalPluginSpec.self, from: library)
                }
            }

            public struct AnimalLazyProxy: Animal {
                private let _resolve: () throws -> any Animal

                public init(_ resolve: @escaping () throws -> any Animal) {
                    self._resolve = resolve
                }

                private func _resolved() -> any Animal {
                    do {
                        return try _resolve()
                    } catch {
                        fatalError("DyLib plugin for Animal failed to load: \\(error.localizedDescription)")
                    }
                }
            }
            """
        )
    }

    @Test func versionedExportExpansion() {
        assertExpansion(
            """
            @DyLibExport(Animal.self, version: 3)
            public struct Cat: Animal {}
            """,
            expandedSource: """
            public struct Cat: Animal {}

            @_cdecl("__dylib_entry_Animal_v3")
            public func __dylib_export_Cat() -> UnsafeMutableRawPointer {
                dyLibMakeEntry(spec: AnimalPluginSpec.self, factory: {
                        Cat() as any Animal
                    })
            }
            """
        )
    }

    @Test func invalidVersionDiagnostic() {
        assertExpansion(
            """
            @DyLibInterface(version: 0)
            public protocol Animal {}
            """,
            expandedSource: """
            public protocol Animal {}
            """,
            diagnostics: [DiagnosticSpec(
                message: "version must be an integer literal greater than or equal to 1",
                line: 1,
                column: 26
            )]
        )
    }

    @Test func basicConnectExpansion() {
        assertExpansion(
            """
            @DyLibConnect(Animal.self, framework: "AnimalImplementation")
            public enum DogPlugin {}
            """,
            expandedSource: """
            public enum DogPlugin {

                public static var library: DyLibLibrary {
                    .framework("AnimalImplementation", dependencies: [])
                }

                private static let _dylibLazy = DyLibLazyPlugin<AnimalPluginSpec>(library: {
                        library
                    })

                public static var instance: any Animal {
                    AnimalLazyProxy {
                        try _dylibLazy.loadIfNeeded()
                    }
                }

                public static func loadIfNeeded() throws -> any Animal {
                    try _dylibLazy.loadIfNeeded()
                }

                public static var isLoaded: Bool {
                    _dylibLazy.isLoaded
                }
            }

            extension DogPlugin: DyLibPluginConnection {
                public typealias Interface = any Animal
            }
            """
        )
    }

    @Test func connectDependenciesExpansion() {
        assertExpansion(
            """
            @DyLibConnect(
                Namespace.Animal.self,
                framework: "AnimalImplementation",
                dependencies: [TrickPlugin.self, Namespace.SoundPlugin.self]
            )
            enum DogPlugin {}
            """,
            expandedSource: """
            enum DogPlugin {

                public static var library: DyLibLibrary {
                    .framework("AnimalImplementation", dependencies: [TrickPlugin.library, Namespace.SoundPlugin.library])
                }

                private static let _dylibLazy = DyLibLazyPlugin<Namespace.AnimalPluginSpec>(library: {
                        library
                    })

                public static var instance: any Namespace.Animal {
                    Namespace.AnimalLazyProxy {
                        try _dylibLazy.loadIfNeeded()
                    }
                }

                public static func loadIfNeeded() throws -> any Namespace.Animal {
                    try _dylibLazy.loadIfNeeded()
                }

                public static var isLoaded: Bool {
                    _dylibLazy.isLoaded
                }
            }

            extension DogPlugin: DyLibPluginConnection {
                public typealias Interface = any Namespace.Animal
            }
            """
        )
    }

    @Test func connectLoggerExpansion() {
        assertExpansion(
            """
            @DyLibConnect(Animal.self, framework: "AnimalImplementation", logger: PluginLog.self)
            enum DogPlugin {}
            """,
            expandedSource: """
            enum DogPlugin {

                public static var library: DyLibLibrary {
                    .framework("AnimalImplementation", dependencies: [])
                }

                private static let _dylibLazy = DyLibLazyPlugin<AnimalPluginSpec>(logger: PluginLog.self, library: {
                        library
                    })

                public static var instance: any Animal {
                    AnimalLazyProxy {
                        try _dylibLazy.loadIfNeeded()
                    }
                }

                public static func loadIfNeeded() throws -> any Animal {
                    try _dylibLazy.loadIfNeeded()
                }

                public static var isLoaded: Bool {
                    _dylibLazy.isLoaded
                }
            }

            extension DogPlugin: DyLibPluginConnection {
                public typealias Interface = any Animal
            }
            """
        )
    }

    @Test func connectInvalidLoggerDiagnostic() {
        assertExpansion(
            """
            @DyLibConnect(Animal.self, framework: "AnimalImplementation", logger: PluginLog())
            enum DogPlugin {}
            """,
            expandedSource: """
            enum DogPlugin {}
            """,
            diagnostics: [DiagnosticSpec(
                message: "logger must be a metatype expression of a DyLibLoadLogger type such as PluginLog.self",
                line: 1,
                column: 71
            )]
        )
    }

    @Test func connectRequiresEnumDiagnostic() {
        assertExpansion(
            """
            @DyLibConnect(Animal.self, framework: "AnimalImplementation")
            struct DogPlugin {}
            """,
            expandedSource: """
            struct DogPlugin {}
            """,
            diagnostics: [DiagnosticSpec(
                message: "@DyLibConnect must be attached to an enum",
                line: 1,
                column: 1
            )]
        )
    }
}
