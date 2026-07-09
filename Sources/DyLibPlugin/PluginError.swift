import Foundation

public enum PluginError: Error, Sendable, Equatable {
    case frameworkNotFound(name: String, bundle: String)
    case libraryOpenFailed(path: String, reason: String)
    case notAPlugin(path: String)
    case duplicatePlugin(PluginID)
    case pluginNotRegistered(PluginID)
    case notActivated(PluginID)
    case abiMismatch(plugin: PluginID, pluginABI: Int, runtimeABI: Int)
    case missingDependency(required: PluginID, requiredBy: PluginID)
    case versionUnsatisfied(dependency: PluginID, requiredBy: PluginID, requirement: String, found: String)
    case dependencyCycle(path: [PluginID])
    case interfaceNotExported(InterfaceID)
    case interfaceIncompatible(interfaceID: InterfaceID, hostHash: String, pluginHash: String, plugin: PluginID)
    case typeMismatch(expected: String, actual: String)
    case activationFailed(plugin: PluginID, reason: String)
}

extension PluginError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .frameworkNotFound(let name, let bundle):
            return "Framework \"\(name).framework\" was not found in bundle \(bundle). "
                + "Check that the plugin is copied into the app's Frameworks directory by a build phase."
        case .libraryOpenFailed(let path, let reason):
            return "dlopen failed for \(path): \(reason)"
        case .notAPlugin(let path):
            return "The library at \(path) does not export \"\(DyLibPluginABI.entrySymbol)\" and is not a DyLibPlugin. "
                + "Plugin binaries must contain a type annotated with @PluginMain."
        case .duplicatePlugin(let id):
            return "A plugin with id \"\(id)\" is already registered."
        case .pluginNotRegistered(let id):
            return "No plugin with id \"\(id)\" is registered. Call register(_:) or discoverPlugins() first."
        case .notActivated(let id):
            return "Plugin \"\(id)\" is registered but not activated. Call activateAll() before resolving instances."
        case .abiMismatch(let plugin, let pluginABI, let runtimeABI):
            return "Plugin \"\(plugin)\" was built against DyLibPlugin ABI \(pluginABI) but the host runtime is ABI \(runtimeABI). "
                + "Rebuild the plugin against the host's DyLibPlugin version."
        case .missingDependency(let required, let requiredBy):
            return "Plugin \"\(requiredBy)\" depends on \"\(required)\", which is not registered."
        case .versionUnsatisfied(let dependency, let requiredBy, let requirement, let found):
            return "Plugin \"\(requiredBy)\" requires \"\(dependency)\" \(requirement), but version \(found) is registered."
        case .dependencyCycle(let path):
            return "Plugin dependency cycle: \(path.map(\.rawValue).joined(separator: " -> "))"
        case .interfaceNotExported(let interfaceID):
            return "No registered plugin exports interface \"\(interfaceID)\"."
        case .interfaceIncompatible(let interfaceID, let hostHash, let pluginHash, let plugin):
            return "Interface \"\(interfaceID)\" of plugin \"\(plugin)\" is incompatible with the host: "
                + "the plugin was built against requirement hash \(pluginHash) but the host expects \(hostHash). "
                + "Rebuild the plugin against the current interface module."
        case .typeMismatch(let expected, let actual):
            return "Plugin factory returned \(actual), which does not conform to the requested interface \(expected)."
        case .activationFailed(let plugin, let reason):
            return "Activation of plugin \"\(plugin)\" failed: \(reason)"
        }
    }
}

extension PluginError: LocalizedError {
    public var errorDescription: String? { description }
}
