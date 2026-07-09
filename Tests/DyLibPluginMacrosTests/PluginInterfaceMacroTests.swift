import SwiftDiagnostics
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

@testable import DyLibPluginMacros

private let testMacros: [String: Macro.Type] = [
    "PluginInterface": PluginInterfaceMacro.self,
    "PluginMain": PluginMainMacro.self,
]

final class PluginInterfaceMacroTests: XCTestCase {
    func testExpandsContractForPublicProtocol() {
        let hash = RequirementHasher.hash(
            normalizedRequirements: ["func speak() -> String"],
            inheritedTypes: [])
        assertMacroExpansion(
            """
            @PluginInterface
            public protocol Animal {
                func speak() -> String
            }
            """,
            expandedSource: """
            public protocol Animal {
                func speak() -> String
            }

            public struct AnimalContract: PluginContract {
                public typealias Interface = Animal
                @inlinable public static var interfaceID: InterfaceID { InterfaceID("Animal") }
                @inlinable public static var compatibilityHash: String { \"\(hash)\" }
            }
            """,
            macros: testMacros)
    }

    func testCustomIdentifierOverridesProtocolName() {
        let hash = RequirementHasher.hash(
            normalizedRequirements: ["func speak() -> String"],
            inheritedTypes: [])
        assertMacroExpansion(
            """
            @PluginInterface(id: "demo.animal")
            public protocol Animal {
                func speak() -> String
            }
            """,
            expandedSource: """
            public protocol Animal {
                func speak() -> String
            }

            public struct AnimalContract: PluginContract {
                public typealias Interface = Animal
                @inlinable public static var interfaceID: InterfaceID { InterfaceID("demo.animal") }
                @inlinable public static var compatibilityHash: String { \"\(hash)\" }
            }
            """,
            macros: testMacros)
    }

    func testStructEmitsError() {
        assertMacroExpansion(
            """
            @PluginInterface
            public struct Animal {
            }
            """,
            expandedSource: """
            public struct Animal {
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@PluginInterface can only be applied to a protocol",
                    line: 1,
                    column: 1)
            ],
            macros: testMacros)
    }

    func testNonPublicProtocolEmitsError() {
        assertMacroExpansion(
            """
            @PluginInterface
            protocol Animal {
                func speak() -> String
            }
            """,
            expandedSource: """
            protocol Animal {
                func speak() -> String
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@PluginInterface requires the protocol to be public (host and plugins must both see it)",
                    line: 1,
                    column: 1)
            ],
            macros: testMacros)
    }

    func testNonLiteralIdentifierEmitsError() {
        assertMacroExpansion(
            """
            @PluginInterface(id: someVariable)
            public protocol Animal {
                func speak() -> String
            }
            """,
            expandedSource: """
            public protocol Animal {
                func speak() -> String
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "The 'id' argument must be a string literal",
                    line: 1,
                    column: 22)
            ],
            macros: testMacros)
    }

    func testEmptyProtocolEmitsWarningButStillExpands() {
        let hash = RequirementHasher.hash(normalizedRequirements: [], inheritedTypes: [])
        assertMacroExpansion(
            """
            @PluginInterface
            public protocol Animal {
            }
            """,
            expandedSource: """
            public protocol Animal {
            }

            public struct AnimalContract: PluginContract {
                public typealias Interface = Animal
                @inlinable public static var interfaceID: InterfaceID { InterfaceID("Animal") }
                @inlinable public static var compatibilityHash: String { \"\(hash)\" }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "Protocol has no requirements; the compatibility hash will not detect drift",
                    line: 1,
                    column: 1,
                    severity: .warning)
            ],
            macros: testMacros)
    }

    func testHashMatchesPinnedValue() {
        XCTAssertEqual(
            RequirementHasher.hash(
                normalizedRequirements: ["func speak() -> String"],
                inheritedTypes: []),
            "fnv1a:de00227ae9e20b96")
        XCTAssertEqual(
            RequirementHasher.hash(normalizedRequirements: [], inheritedTypes: []),
            "fnv1a:cbf29ce484222325")
    }

    func testHashIsDeterministicAcrossCalls() {
        let first = RequirementHasher.hash(
            normalizedRequirements: ["func speak() -> String", "var name: String { get }"],
            inheritedTypes: ["Sendable"])
        let second = RequirementHasher.hash(
            normalizedRequirements: ["func speak() -> String", "var name: String { get }"],
            inheritedTypes: ["Sendable"])
        XCTAssertEqual(first, second)
    }

    func testHashIgnoresRequirementOrder() {
        let forward = RequirementHasher.hash(
            normalizedRequirements: ["func speak() -> String", "var name: String { get }"],
            inheritedTypes: [])
        let reversed = RequirementHasher.hash(
            normalizedRequirements: ["var name: String { get }", "func speak() -> String"],
            inheritedTypes: [])
        XCTAssertEqual(forward, reversed)
    }

    func testHashChangesWithRequirements() {
        let original = RequirementHasher.hash(
            normalizedRequirements: ["func speak() -> String"],
            inheritedTypes: [])
        let changed = RequirementHasher.hash(
            normalizedRequirements: ["func speak() -> Int"],
            inheritedTypes: [])
        XCTAssertNotEqual(original, changed)
    }

    func testHashChangesWithInheritedTypes() {
        let original = RequirementHasher.hash(
            normalizedRequirements: ["func speak() -> String"],
            inheritedTypes: [])
        let inherited = RequirementHasher.hash(
            normalizedRequirements: ["func speak() -> String"],
            inheritedTypes: ["Sendable"])
        XCTAssertNotEqual(original, inherited)
    }

    func testNormalizeCollapsesWhitespace() {
        XCTAssertEqual(
            RequirementHasher.normalize("func  speak()  ->  String"),
            "func speak() -> String")
        XCTAssertEqual(
            RequirementHasher.normalize("  func speak()\n    -> String  "),
            "func speak() -> String")
    }
}
