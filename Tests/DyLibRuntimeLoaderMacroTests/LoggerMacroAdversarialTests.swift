// Adversarial macro tests for `@DyLibConnect(..., logger:)`.
// Golden strings below were captured from ad55dba (pre-logger) and must not change
// when `logger:` is omitted.

import SwiftDiagnostics
import SwiftParser
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import Testing
@testable import DyLibRuntimeLoaderMacros

/// Expands only the member + extension roles of the first attribute on the first enum,
/// returning the printed declarations and the diagnostics produced.
private func expandConnect(_ source: String) throws -> (members: [String], extensions: [String], diagnostics: [Diagnostic]) {
    let file = Parser.parse(source: source)
    let decl = try #require(file.statements.first?.item.as(EnumDeclSyntax.self))
    let attribute = try #require(decl.attributes.first?.as(AttributeSyntax.self))
    let context = BasicMacroExpansionContext()
    let members = try DyLibConnectMacro.expansion(
        of: attribute, providingMembersOf: decl, conformingTo: [], in: context)
    let extensions = try DyLibConnectMacro.expansion(
        of: attribute, attachedTo: decl,
        providingExtensionsOf: TypeSyntax(IdentifierTypeSyntax(name: decl.name)),
        conformingTo: [], in: context)
    return (
        members.map { $0.formatted().description },
        extensions.map { $0.formatted().description },
        context.diagnostics
    )
}

private let goldenBasic: [String] = [
    "public static var library: DyLibLibrary {\n    .framework(\"AnimalImplementation\", dependencies: [])\n}",
    "private static let _dylibLazy = DyLibLazyPlugin<AnimalPluginSpec>(library: {\n        library\n    })",
    "public static var instance: any Animal {\n    AnimalLazyProxy {\n        try _dylibLazy.loadIfNeeded()\n    }\n}",
    "public static func loadIfNeeded() throws -> any Animal {\n    try _dylibLazy.loadIfNeeded()\n}",
    "public static var isLoaded: Bool {\n    _dylibLazy.isLoaded\n}",
]

private let goldenFull: [String] = [
    "public static var library: DyLibLibrary {\n    .framework(\"AnimalImplementation\", bundle: .main, dependencies: [TrickPlugin.library])\n}",
    "private static let _dylibLazy = DyLibLazyPlugin<NS.AnimalPluginSpec>(library: {\n        library\n    })",
    "public static var instance: any NS.Animal {\n    NS.AnimalLazyProxy {\n        try _dylibLazy.loadIfNeeded()\n    }\n}",
    "public static func loadIfNeeded() throws -> any NS.Animal {\n    try _dylibLazy.loadIfNeeded()\n}",
    "public static var isLoaded: Bool {\n    _dylibLazy.isLoaded\n}",
]

private let goldenExtension = "extension DogPlugin: DyLibPluginConnection {\n    public typealias Interface = any Animal\n}"

@Suite struct LoggerMacroAdversarialTests {
    @Test func omittedLoggerIsByteIdenticalToBaseline() throws {
        let r = try expandConnect("""
        @DyLibConnect(Animal.self, framework: "AnimalImplementation")
        public enum DogPlugin {}
        """)
        #expect(r.diagnostics.isEmpty)
        #expect(r.members == goldenBasic)
        #expect(r.extensions == [goldenExtension])
    }

    @Test func omittedLoggerWithAllOtherArgumentsIsByteIdenticalToBaseline() throws {
        let r = try expandConnect("""
        @DyLibConnect(NS.Animal.self, framework: "AnimalImplementation", dependencies: [TrickPlugin.self], bundle: .main)
        enum DogPlugin {}
        """)
        #expect(r.diagnostics.isEmpty)
        #expect(r.members == goldenFull)
    }

    @Test func explicitNilLoggerMatchesOmitted() throws {
        let r = try expandConnect("""
        @DyLibConnect(Animal.self, framework: "AnimalImplementation", logger: nil)
        public enum DogPlugin {}
        """)
        #expect(r.diagnostics.map(\.message).isEmpty)
        #expect(r.members == goldenBasic, "logger: nil should expand like an omitted logger (as bundle: nil does)")
    }

    @Test func loggerOnlyChangesTheLazyLine() throws {
        let r = try expandConnect("""
        @DyLibConnect(Animal.self, framework: "AnimalImplementation", logger: PluginLog.self)
        public enum DogPlugin {}
        """)
        #expect(r.diagnostics.isEmpty)
        #expect(r.members.count == goldenBasic.count)
        for (i, (a, b)) in zip(r.members, goldenBasic).enumerated() where i != 1 {
            #expect(a == b, "member \(i) changed")
        }
        let lazy = r.members.count > 1 ? r.members[1] : ""
        #expect(lazy.contains("logger: PluginLog.self"), "lazy line: \(lazy)")
        #expect(lazy.contains("DyLibLazyPlugin<AnimalPluginSpec>("))
        #expect(r.extensions == [goldenExtension])
    }

    @Test func qualifiedLoggerIsPassedThrough() throws {
        let r = try expandConnect("""
        @DyLibConnect(Animal.self, framework: "AnimalImplementation", logger: App.Logging.PluginLog.self)
        public enum DogPlugin {}
        """)
        #expect(r.diagnostics.isEmpty)
        #expect(r.members.joined().contains("logger: App.Logging.PluginLog.self"))
    }

    @Test func loggerArgumentOrderWithDependenciesAndBundle() throws {
        let r = try expandConnect("""
        @DyLibConnect(Animal.self, framework: "AnimalImplementation", dependencies: [TrickPlugin.self], bundle: .main, logger: PluginLog.self)
        public enum DogPlugin {}
        """)
        #expect(r.diagnostics.isEmpty)
        #expect(r.members.first?.contains("dependencies: [TrickPlugin.library]") == true)
        #expect(r.members.joined().contains("logger: PluginLog.self"))
    }

    @Test(arguments: [
        "PluginLog",                 // missing .self
        "\"PluginLog\"",             // string
        "makeLogger()",              // call
        "PluginLog.init",            // member access, not .self
        "[PluginLog.self]",          // array
        "PluginLog.self.self.foo",   // junk chain
        "true ? A.self : B.self",    // ternary
    ])
    func nonMetatypeLoggerIsDiagnosed(_ expr: String) throws {
        let r = try expandConnect("""
        @DyLibConnect(Animal.self, framework: "AnimalImplementation", logger: \(expr))
        public enum DogPlugin {}
        """)
        #expect(r.diagnostics.count == 1, "logger: \(expr) -> \(r.diagnostics.map(\.message))")
        if let d = r.diagnostics.first {
            #expect(d.diagMessage.severity == .error)
            #expect(d.message.localizedCaseInsensitiveContains("logger"), "message: \(d.message)")
        }
        #expect(!r.members.joined().contains("logger: \(expr)"), "invalid logger must not be emitted")
    }
}
