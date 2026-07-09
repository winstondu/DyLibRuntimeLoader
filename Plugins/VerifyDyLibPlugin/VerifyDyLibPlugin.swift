import Foundation
import PackagePlugin

@main
struct VerifyDyLibPlugin: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        let tool = try context.tool(named: "dylib-plugin-verify")

        guard !arguments.isEmpty else {
            print("""
                usage:
                  swift package verify-dylib-plugin --product MyPlugin [--expect-id com.example.my]
                  swift package verify-dylib-plugin [--expect-id <plugin-id>]... <binary-or-framework-path>...

                With --product, the product is built and its dynamic library artifact is
                verified. Otherwise all arguments are forwarded to dylib-plugin-verify.
                """)
            return
        }

        let toolArguments: [String]
        if arguments.contains("--product") {
            guard let productName = value(after: "--product", in: arguments) else {
                throw VerifyDyLibPluginError(description: "--product requires a product name")
            }
            toolArguments = try verifyArguments(
                forProductNamed: productName,
                expectedPluginIDArguments: expectIDArguments(in: arguments))
        } else {
            toolArguments = arguments
        }

        try run(toolAt: tool.url.path, arguments: toolArguments)
    }

    private func verifyArguments(
        forProductNamed productName: String,
        expectedPluginIDArguments: [String]
    ) throws -> [String] {
        let result = try packageManager.build(.product(productName), parameters: .init())
        guard result.succeeded else {
            throw VerifyDyLibPluginError(
                description: "build of product \"\(productName)\" failed:\n\(result.logText)")
        }
        let libraryPaths = result.builtArtifacts
            .filter { $0.kind == .dynamicLibrary }
            .map { $0.url.path }
        guard !libraryPaths.isEmpty else {
            throw VerifyDyLibPluginError(
                description: "product \"\(productName)\" produced no dynamic library artifact — "
                    + "plugin products must be dynamic libraries (.library(type: .dynamic))")
        }
        return expectedPluginIDArguments + libraryPaths
    }

    private func expectIDArguments(in arguments: [String]) -> [String] {
        var collected = [String]()
        var index = 0
        while index < arguments.count {
            if arguments[index] == "--expect-id", index + 1 < arguments.count {
                collected.append(contentsOf: ["--expect-id", arguments[index + 1]])
                index += 2
            } else {
                index += 1
            }
        }
        return collected
    }

    private func value(after option: String, in arguments: [String]) -> String? {
        guard let optionIndex = arguments.firstIndex(of: option),
            optionIndex + 1 < arguments.count
        else { return nil }
        return arguments[optionIndex + 1]
    }

    private func run(toolAt toolPath: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: toolPath)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw VerifyDyLibPluginError(
                description: "dylib-plugin-verify failed with exit code \(process.terminationStatus)")
        }
    }
}
