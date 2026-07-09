import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

struct MacroDiagnosticMessage: DiagnosticMessage {
    let message: String
    let diagnosticID: MessageID
    let severity: DiagnosticSeverity

    init(id: String, message: String, severity: DiagnosticSeverity = .error) {
        self.message = message
        self.diagnosticID = MessageID(domain: "DyLibPluginMacros", id: id)
        self.severity = severity
    }
}

extension MacroExpansionContext {
    func diagnose(_ message: MacroDiagnosticMessage, at node: some SyntaxProtocol) {
        diagnose(Diagnostic(node: Syntax(node), message: message))
    }
}
