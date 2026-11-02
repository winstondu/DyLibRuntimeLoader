import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

private struct MacroDiagnostic: DiagnosticMessage {
    let message: String
    let diagnosticID: MessageID
    let severity: DiagnosticSeverity = .error

    init(_ id: String, _ message: String) {
        self.message = message
        self.diagnosticID = MessageID(domain: "DynastyMacros", id: id)
    }
}

private enum PluginNaming {
    static func specName(for protocolName: String) -> String {
        "\(protocolName)PluginSpec"
    }

    static func symbolName(for protocolName: String, version: Int) -> String {
        let base = "__dylib_entry_\(protocolName)"
        return version == 1 ? base : "\(base)_v\(version)"
    }

    static func proxyName(for protocolName: String) -> String {
        "\(protocolName)LazyProxy"
    }

    static func qualifiedSpecName(for interfaceName: String) -> String {
        var components = interfaceName.split(separator: ".").map(String.init)
        guard let protocolName = components.popLast() else { return interfaceName }
        components.append(specName(for: protocolName))
        return components.joined(separator: ".")
    }

    static func qualifiedProxyName(for interfaceName: String) -> String {
        var components = interfaceName.split(separator: ".").map(String.init)
        guard let protocolName = components.popLast() else { return interfaceName }
        components.append(proxyName(for: protocolName))
        return components.joined(separator: ".")
    }

    static func exportFunctionName(for concreteName: String) -> String {
        "__dylib_export_\(concreteName)"
    }
}

private enum MacroArguments {
    static func list(from attribute: AttributeSyntax) -> LabeledExprListSyntax? {
        guard case .argumentList(let arguments) = attribute.arguments else { return nil }
        return arguments
    }

    static func version(
        from attribute: AttributeSyntax,
        in context: some MacroExpansionContext
    ) -> Int? {
        guard let argument = list(from: attribute)?.first(where: { $0.label?.text == "version" }) else {
            return 1
        }
        guard
            let literal = argument.expression.as(IntegerLiteralExprSyntax.self),
            let value = Int(literal.literal.text),
            value >= 1
        else {
            context.diagnose(Diagnostic(
                node: Syntax(argument.expression),
                message: MacroDiagnostic("version.invalid", "version must be an integer literal greater than or equal to 1")
            ))
            return nil
        }
        return value
    }

    static func proxyEnabled(
        from attribute: AttributeSyntax,
        in context: some MacroExpansionContext
    ) -> Bool? {
        guard let argument = list(from: attribute)?.first(where: { $0.label?.text == "proxy" }) else {
            return true
        }
        guard let literal = argument.expression.as(BooleanLiteralExprSyntax.self) else {
            context.diagnose(Diagnostic(
                node: Syntax(argument.expression),
                message: MacroDiagnostic("proxy.invalid", "proxy must be a boolean literal")
            ))
            return nil
        }
        return literal.literal.tokenKind == .keyword(.true)
    }
}

private func isNested(in context: some MacroExpansionContext) -> Bool {
    context.lexicalContext.contains { syntax in
        syntax.is(StructDeclSyntax.self)
            || syntax.is(ClassDeclSyntax.self)
            || syntax.is(EnumDeclSyntax.self)
            || syntax.is(ActorDeclSyntax.self)
            || syntax.is(ProtocolDeclSyntax.self)
            || syntax.is(ExtensionDeclSyntax.self)
    }
}

public struct DyLibInterfaceMacro: PeerMacro {
    private struct ProxyMember {
        let declaration: String
    }

    private struct UnsupportedRequirement {
        let name: String
        let reason: String
        let node: Syntax
    }

    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let protocolDeclaration = declaration.as(ProtocolDeclSyntax.self) else {
            context.diagnose(Diagnostic(
                node: Syntax(declaration),
                message: MacroDiagnostic("interface.notProtocol", "@DyLibInterface can only be attached to a protocol")
            ))
            return []
        }
        guard !isNested(in: context) else {
            context.diagnose(Diagnostic(
                node: Syntax(protocolDeclaration.name),
                message: MacroDiagnostic("interface.notTopLevel", "@DyLibInterface must be applied to a top-level protocol")
            ))
            return []
        }
        guard protocolDeclaration.modifiers.contains(where: { $0.name.text == "public" }) else {
            context.diagnose(Diagnostic(
                node: Syntax(protocolDeclaration.name),
                message: MacroDiagnostic("interface.notPublic", "@DyLibInterface requires a public protocol")
            ))
            return []
        }

        guard
            let version = MacroArguments.version(from: node, in: context),
            let proxyEnabled = MacroArguments.proxyEnabled(from: node, in: context)
        else {
            return []
        }
        let protocolName = protocolDeclaration.name.text
        let specName = PluginNaming.specName(for: protocolName)
        let proxyName = PluginNaming.proxyName(for: protocolName)
        let symbol = PluginNaming.symbolName(for: protocolName, version: version)
        let spec = DeclSyntax(stringLiteral: """
        public enum \(specName): DyLibPluginSpec {
            public typealias Interface = any \(protocolName)
            public static var symbolName: String { "\(symbol)" }
            public static func load(from path: String) throws -> any \(protocolName) {
                try DyLibLoader.shared.load(\(specName).self, from: path)
            }
            public static func load(from library: DyLibLibrary) throws -> any \(protocolName) {
                try DyLibLoader.shared.load(\(specName).self, from: library)
            }
            public static func loadWithHandle(from path: String) throws -> (instance: any \(protocolName), handle: DyLibHandle) {
                try DyLibLoader.shared.loadWithHandle(\(specName).self, from: DyLibLibrary(path: path))
            }
            public static func loadWithHandle(from library: DyLibLibrary) throws -> (instance: any \(protocolName), handle: DyLibHandle) {
                try DyLibLoader.shared.loadWithHandle(\(specName).self, from: library)
            }
        }
        """)
        guard proxyEnabled else { return [spec] }

        var proxyMembers: [ProxyMember] = []
        var unsupportedRequirements: [UnsupportedRequirement] = []
        for member in protocolDeclaration.memberBlock.members {
            if let function = member.decl.as(FunctionDeclSyntax.self) {
                if let unsupported = unsupportedFunction(function) {
                    unsupportedRequirements.append(unsupported)
                } else {
                    proxyMembers.append(forwardingFunction(function))
                }
            } else if let variable = member.decl.as(VariableDeclSyntax.self) {
                let result = forwardingProperties(variable)
                proxyMembers.append(contentsOf: result.members)
                unsupportedRequirements.append(contentsOf: result.unsupported)
            } else if let initializer = member.decl.as(InitializerDeclSyntax.self) {
                unsupportedRequirements.append(UnsupportedRequirement(
                    name: "init",
                    reason: "initializer requirements are unsupported",
                    node: Syntax(initializer.initKeyword)
                ))
            } else if let subscriptDeclaration = member.decl.as(SubscriptDeclSyntax.self) {
                unsupportedRequirements.append(UnsupportedRequirement(
                    name: "subscript",
                    reason: "subscript requirements are unsupported",
                    node: Syntax(subscriptDeclaration.subscriptKeyword)
                ))
            } else if let associatedType = member.decl.as(AssociatedTypeDeclSyntax.self) {
                unsupportedRequirements.append(UnsupportedRequirement(
                    name: associatedType.name.text,
                    reason: "associated type requirements are unsupported",
                    node: Syntax(associatedType.name)
                ))
            }
        }

        if !unsupportedRequirements.isEmpty {
            for requirement in unsupportedRequirements {
                context.diagnose(Diagnostic(
                    node: requirement.node,
                    message: MacroDiagnostic(
                        "interface.unsupportedProxyRequirement",
                        "@DyLibInterface cannot generate a lazy proxy for requirement '\(requirement.name)': \(requirement.reason). Mark the interface @DyLibInterface(proxy: false) to suppress proxy generation."
                    )
                ))
            }
            return [spec]
        }

        let forwardedDeclarations = proxyMembers
            .map(\.declaration)
            .joined(separator: "\n\n")
        let forwardedSection = forwardedDeclarations.isEmpty
            ? ""
            : "\n\n\(forwardedDeclarations)"
        let proxy = DeclSyntax(stringLiteral: """
        public struct \(proxyName): \(protocolName) {
            private let _resolve: () throws -> any \(protocolName)

            public init(_ resolve: @escaping () throws -> any \(protocolName)) {
                self._resolve = resolve
            }

            private func _resolved() -> any \(protocolName) {
                do {
                    return try _resolve()
                } catch {
                    fatalError("DyLib plugin for \(protocolName) failed to load: \\(error.localizedDescription)")
                }
            }\(forwardedSection)
        }
        """)
        return [spec, proxy]
    }

    private static func unsupportedFunction(_ function: FunctionDeclSyntax) -> UnsupportedRequirement? {
        if function.modifiers.contains(where: { ["static", "class"].contains($0.name.text) }) {
            return UnsupportedRequirement(
                name: function.name.text,
                reason: "static requirements are unsupported",
                node: Syntax(function.name)
            )
        }
        if function.modifiers.contains(where: { $0.name.text == "mutating" }) {
            return UnsupportedRequirement(
                name: function.name.text,
                reason: "mutating function requirements are unsupported",
                node: Syntax(function.name)
            )
        }
        return nil
    }

    private static func forwardingFunction(_ function: FunctionDeclSyntax) -> ProxyMember {
        var signature = function.signature
        signature.parameterClause.parameters = FunctionParameterListSyntax(
            signature.parameterClause.parameters.map { parameter in
                guard parameter.defaultValue != nil else { return parameter }
                return parameter
                    .with(\.type, parameter.type.trimmed)
                    .with(\.defaultValue, nil)
            }
        )

        let arguments = function.signature.parameterClause.parameters.map { parameter in
            let localName = (parameter.secondName ?? parameter.firstName).trimmedDescription
            let value = parameter.type.trimmedDescription.hasPrefix("inout ")
                ? "&\(localName)"
                : localName
            if parameter.firstName.text == "_" {
                return value
            }
            return "\(parameter.firstName.trimmedDescription): \(value)"
        }.joined(separator: ", ")

        let effects = function.signature.effectSpecifiers
        let isAsync = effects?.asyncSpecifier != nil
        let isThrowing = effects?.throwsClause != nil
        let resolve = isThrowing ? "(try _resolve())" : "_resolved()"
        let effectPrefix: String
        switch (isAsync, isThrowing) {
        case (true, true): effectPrefix = "try await "
        case (true, false): effectPrefix = "await "
        case (false, true): effectPrefix = "try "
        case (false, false): effectPrefix = ""
        }

        let genericParameters = function.genericParameterClause?.trimmedDescription ?? ""
        let whereClause = function.genericWhereClause.map { " \($0.trimmedDescription)" } ?? ""
        return ProxyMember(declaration: """
            public func \(function.name.trimmedDescription)\(genericParameters)\(signature.trimmedDescription)\(whereClause) {
                \(effectPrefix)\(resolve).\(function.name.trimmedDescription)(\(arguments))
            }
            """)
    }

    private static func forwardingProperties(
        _ variable: VariableDeclSyntax
    ) -> (members: [ProxyMember], unsupported: [UnsupportedRequirement]) {
        var members: [ProxyMember] = []
        var unsupported: [UnsupportedRequirement] = []
        let isStatic = variable.modifiers.contains(where: { ["static", "class"].contains($0.name.text) })

        for binding in variable.bindings {
            let identifier = binding.pattern.as(IdentifierPatternSyntax.self)
            let name = identifier?.identifier.text ?? binding.pattern.trimmedDescription
            let diagnosticNode = identifier.map { Syntax($0.identifier) } ?? Syntax(binding.pattern)
            guard !isStatic else {
                unsupported.append(UnsupportedRequirement(
                    name: name,
                    reason: "static requirements are unsupported",
                    node: diagnosticNode
                ))
                continue
            }
            guard
                let type = binding.typeAnnotation?.type.trimmedDescription,
                let accessorBlock = binding.accessorBlock,
                case .accessors(let accessors) = accessorBlock.accessors,
                let getter = accessors.first(where: { $0.accessorSpecifier.text == "get" })
            else {
                unsupported.append(UnsupportedRequirement(
                    name: name,
                    reason: "only get-only property requirements are supported",
                    node: diagnosticNode
                ))
                continue
            }
            if accessors.contains(where: { $0.accessorSpecifier.text == "set" }) {
                unsupported.append(UnsupportedRequirement(
                    name: name,
                    reason: "settable property requirements are unsupported",
                    node: diagnosticNode
                ))
                continue
            }

            let isAsync = getter.effectSpecifiers?.asyncSpecifier != nil
            let isThrowing = getter.effectSpecifiers?.throwsClause != nil
            let resolve = isThrowing ? "(try _resolve())" : "_resolved()"
            let effectPrefix: String
            switch (isAsync, isThrowing) {
            case (true, true): effectPrefix = "try await "
            case (true, false): effectPrefix = "await "
            case (false, true): effectPrefix = "try "
            case (false, false): effectPrefix = ""
            }
            let getterEffects = getter.effectSpecifiers.map { " \($0.trimmedDescription)" } ?? ""
            if getterEffects.isEmpty {
                members.append(ProxyMember(declaration: """
                    public var \(name): \(type) {
                        \(effectPrefix)\(resolve).\(name)
                    }
                    """))
            } else {
                members.append(ProxyMember(declaration: """
                    public var \(name): \(type) {
                        get\(getterEffects) {
                            \(effectPrefix)\(resolve).\(name)
                        }
                    }
                    """))
            }
        }
        return (members, unsupported)
    }
}

public struct DyLibExportMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard !isNested(in: context) else {
            context.diagnose(Diagnostic(
                node: Syntax(declaration),
                message: MacroDiagnostic("export.notTopLevel", "@DyLibExport must be applied to a top-level type")
            ))
            return []
        }
        guard
            let first = MacroArguments.list(from: node)?.first,
            first.label == nil,
            let metatype = first.expression.as(MemberAccessExprSyntax.self),
            metatype.declName.baseName.text == "self",
            let base = metatype.base
        else {
            context.diagnose(Diagnostic(
                node: Syntax(node),
                message: MacroDiagnostic("export.invalidMetatype", "@DyLibExport requires an interface metatype expression such as Animal.self")
            ))
            return []
        }
        guard let concreteName = concreteTypeName(from: declaration) else {
            context.diagnose(Diagnostic(
                node: Syntax(declaration),
                message: MacroDiagnostic("export.invalidDeclaration", "@DyLibExport can only be attached to a concrete type")
            ))
            return []
        }
        guard !isGeneric(declaration) else {
            context.diagnose(Diagnostic(
                node: Syntax(declaration),
                message: MacroDiagnostic("export.generic", "@DyLibExport cannot be applied to a generic type")
            ))
            return []
        }
        guard let version = MacroArguments.version(from: node, in: context) else { return [] }

        let interfaceName = base.trimmedDescription
        let protocolName = interfaceName.split(separator: ".").last.map(String.init) ?? interfaceName
        let specName = PluginNaming.qualifiedSpecName(for: interfaceName)
        let symbol = PluginNaming.symbolName(for: protocolName, version: version)
        let functionName = PluginNaming.exportFunctionName(for: concreteName)
        return [DeclSyntax(stringLiteral: """
        @_cdecl("\(symbol)")
        public func \(functionName)() -> UnsafeMutableRawPointer {
            dyLibMakeEntry(spec: \(specName).self, factory: { \(concreteName)() as any \(interfaceName) })
        }
        """)]
    }

    private static func concreteTypeName(from declaration: some DeclSyntaxProtocol) -> String? {
        if let value = declaration.as(StructDeclSyntax.self) { return value.name.text }
        if let value = declaration.as(ClassDeclSyntax.self) { return value.name.text }
        if let value = declaration.as(EnumDeclSyntax.self) { return value.name.text }
        if let value = declaration.as(ActorDeclSyntax.self) { return value.name.text }
        return nil
    }

    private static func isGeneric(_ declaration: some DeclSyntaxProtocol) -> Bool {
        if let value = declaration.as(StructDeclSyntax.self) { return value.genericParameterClause != nil }
        if let value = declaration.as(ClassDeclSyntax.self) { return value.genericParameterClause != nil }
        if let value = declaration.as(EnumDeclSyntax.self) { return value.genericParameterClause != nil }
        if let value = declaration.as(ActorDeclSyntax.self) { return value.genericParameterClause != nil }
        return false
    }
}

public struct DyLibConnectMacro: MemberMacro, ExtensionMacro {
    private struct Arguments {
        let interfaceName: String
        let frameworkLiteral: String
        let dependencies: [String]
        let bundleExpression: String?
        let loggerName: String?
    }

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let arguments = parseArguments(
            from: node,
            attachedTo: declaration,
            in: context,
            diagnose: true
        ) else {
            return []
        }

        let specName = PluginNaming.qualifiedSpecName(for: arguments.interfaceName)
        let proxyName = PluginNaming.qualifiedProxyName(for: arguments.interfaceName)
        let dependencies = arguments.dependencies
            .map { "\($0).library" }
            .joined(separator: ", ")
        let bundleArgument = arguments.bundleExpression.map { ", bundle: \($0)" } ?? ""
        let loggerArgument = arguments.loggerName.map { "logger: \($0).self, " } ?? ""

        return [
            DeclSyntax(stringLiteral: """
            public static var library: DyLibLibrary {
                .framework(\(arguments.frameworkLiteral)\(bundleArgument), dependencies: [\(dependencies)])
            }
            """),
            DeclSyntax(stringLiteral: """
            private static let _dylibLazy = DyLibLazyPlugin<\(specName)>(\(loggerArgument)library: { library })
            """),
            DeclSyntax(stringLiteral: """
            public static var instance: any \(arguments.interfaceName) {
                \(proxyName) { try _dylibLazy.loadIfNeeded() }
            }
            """),
            DeclSyntax(stringLiteral: """
            public static func loadIfNeeded() throws -> any \(arguments.interfaceName) {
                try _dylibLazy.loadIfNeeded()
            }
            """),
            DeclSyntax(stringLiteral: """
            public static var isLoaded: Bool {
                _dylibLazy.isLoaded
            }
            """),
        ]
    }

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard let arguments = parseArguments(
            from: node,
            attachedTo: declaration,
            in: context,
            diagnose: false
        ) else {
            return []
        }

        let extensionDeclaration = DeclSyntax(stringLiteral: """
        extension \(type.trimmedDescription): DyLibPluginConnection {
            public typealias Interface = any \(arguments.interfaceName)
        }
        """)
        guard let result = extensionDeclaration.as(ExtensionDeclSyntax.self) else {
            return []
        }
        return [result]
    }

    private static func parseArguments(
        from node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext,
        diagnose: Bool
    ) -> Arguments? {
        guard declaration.is(EnumDeclSyntax.self) else {
            if diagnose {
                context.diagnose(Diagnostic(
                    node: Syntax(node),
                    message: MacroDiagnostic("connect.notEnum", "@DyLibConnect must be attached to an enum")
                ))
            }
            return nil
        }
        guard context.lexicalContext.isEmpty else {
            if diagnose {
                context.diagnose(Diagnostic(
                    node: Syntax(node),
                    message: MacroDiagnostic("connect.notTopLevel", "@DyLibConnect must be attached to a top-level enum")
                ))
            }
            return nil
        }
        guard let argumentList = MacroArguments.list(from: node) else {
            return nil
        }
        guard
            let interfaceArgument = argumentList.first,
            interfaceArgument.label == nil,
            let interfaceName = metatypeBaseName(from: interfaceArgument.expression)
        else {
            if diagnose {
                context.diagnose(Diagnostic(
                    node: Syntax(node),
                    message: MacroDiagnostic(
                        "connect.invalidMetatype",
                        "@DyLibConnect requires an interface metatype expression such as Animal.self"
                    )
                ))
            }
            return nil
        }
        guard
            let frameworkArgument = argumentList.first(where: { $0.label?.text == "framework" }),
            let frameworkLiteral = simpleStringLiteral(frameworkArgument.expression)
        else {
            if diagnose {
                let diagnosticNode = argumentList
                    .first(where: { $0.label?.text == "framework" })
                    .map { Syntax($0.expression) } ?? Syntax(node)
                context.diagnose(Diagnostic(
                    node: diagnosticNode,
                    message: MacroDiagnostic("connect.invalidFramework", "framework must be a simple string literal")
                ))
            }
            return nil
        }

        var dependencyNames: [String] = []
        if let dependencyArgument = argumentList.first(where: { $0.label?.text == "dependencies" }) {
            guard let array = dependencyArgument.expression.as(ArrayExprSyntax.self) else {
                if diagnose {
                    diagnoseInvalidDependencies(dependencyArgument.expression, in: context)
                }
                return nil
            }
            for element in array.elements {
                guard let name = metatypeBaseName(from: element.expression) else {
                    if diagnose {
                        diagnoseInvalidDependencies(element.expression, in: context)
                    }
                    return nil
                }
                dependencyNames.append(name)
            }
        }

        let bundleExpression = argumentList
            .first(where: { $0.label?.text == "bundle" })
            .map(\.expression.trimmedDescription)
            .flatMap { $0 == "nil" ? nil : $0 }

        var loggerName: String?
        if let loggerArgument = argumentList.first(where: { $0.label?.text == "logger" }),
           loggerArgument.expression.as(NilLiteralExprSyntax.self) == nil {
            guard let name = metatypeBaseName(from: loggerArgument.expression) else {
                if diagnose {
                    context.diagnose(Diagnostic(
                        node: Syntax(loggerArgument.expression),
                        message: MacroDiagnostic(
                            "connect.invalidLogger",
                            "logger must be a metatype expression of a DyLibLoadLogger type such as PluginLog.self"
                        )
                    ))
                }
                return nil
            }
            loggerName = name
        }

        return Arguments(
            interfaceName: interfaceName,
            frameworkLiteral: frameworkLiteral,
            dependencies: dependencyNames,
            bundleExpression: bundleExpression,
            loggerName: loggerName
        )
    }

    private static func metatypeBaseName(from expression: ExprSyntax) -> String? {
        guard
            let memberAccess = expression.as(MemberAccessExprSyntax.self),
            memberAccess.declName.baseName.text == "self",
            let base = memberAccess.base
        else {
            return nil
        }
        return base.trimmedDescription
    }

    private static func simpleStringLiteral(_ expression: ExprSyntax) -> String? {
        guard
            let literal = expression.as(StringLiteralExprSyntax.self),
            literal.segments.count == 1,
            literal.segments.first?.is(StringSegmentSyntax.self) == true
        else {
            return nil
        }
        return literal.trimmedDescription
    }

    private static func diagnoseInvalidDependencies(
        _ expression: ExprSyntax,
        in context: some MacroExpansionContext
    ) {
        context.diagnose(Diagnostic(
            node: Syntax(expression),
            message: MacroDiagnostic(
                "connect.invalidDependencies",
                "dependencies must be metatype literals of @DyLibConnect types"
            )
        ))
    }
}
