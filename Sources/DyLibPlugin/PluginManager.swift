import Foundation

/// Owns plugin registration, dependency-ordered activation, and instance
/// resolution. User code (module hooks and factories) is never invoked while
/// the state lock is held.
public final class PluginManager: @unchecked Sendable {
    private struct State {
        var loaded: [PluginID: LoadedPlugin] = [:]
        var activated: Set<PluginID> = []
    }

    private let state = LockedState(State())
    private let handles = PluginHandleTable()

    public init() {}

    public var registeredManifests: [PluginManifest] {
        state.withLock { state in
            state.loaded.values
                .map(\.manifest)
                .sorted { $0.id.rawValue < $1.id.rawValue }
        }
    }

    @discardableResult
    public func register(_ location: PluginLocation) throws -> PluginManifest {
        let entry = try handles.entry(forPath: location.path)
        let manifest = entry.descriptor.manifest
        guard manifest.abiVersion == DyLibPluginABI.current else {
            throw PluginError.abiMismatch(
                plugin: manifest.id,
                pluginABI: manifest.abiVersion,
                runtimeABI: DyLibPluginABI.current)
        }
        return try state.withLock { state in
            if let existing = state.loaded[manifest.id] {
                guard existing.path == location.path else {
                    throw PluginError.duplicatePlugin(manifest.id)
                }
                return existing.manifest
            }
            state.loaded[manifest.id] = LoadedPlugin(
                manifest: manifest,
                path: location.path,
                descriptor: entry.descriptor)
            return manifest
        }
    }

    @discardableResult
    public func discoverPlugins(in bundle: Bundle = .main) throws -> [PluginManifest] {
        guard let frameworksURL = bundle.privateFrameworksURL else { return [] }
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: frameworksURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { return [] }

        let contents = try fileManager
            .contentsOfDirectory(at: frameworksURL, includingPropertiesForKeys: nil)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var manifests = [PluginManifest]()
        for url in contents where url.pathExtension == "framework" {
            let name = url.deletingPathExtension().lastPathComponent
            let location: PluginLocation
            do {
                location = try PluginLocation.framework(name: name, in: bundle)
            } catch PluginError.frameworkNotFound {
                continue
            }
            do {
                manifests.append(try register(location))
            } catch PluginError.notAPlugin {
                // The host's own linked frameworks live here too; skip them.
                continue
            }
        }
        return manifests
    }

    public func activateAll() throws {
        let manifests = state.withLock { $0.loaded.values.map(\.manifest) }
        let order = try DependencyResolver.activationOrder(for: manifests)
        for id in order {
            let pending = state.withLock { (state: inout State) -> PluginDescriptor? in
                guard !state.activated.contains(id), let plugin = state.loaded[id] else { return nil }
                return plugin.descriptor
            }
            guard let descriptor = pending else { continue }
            do {
                try descriptor.activate(PluginContext(pluginID: id, resolver: self))
            } catch let error as PluginError {
                throw error
            } catch {
                throw PluginError.activationFailed(plugin: id, reason: String(describing: error))
            }
            state.withLock { _ = $0.activated.insert(id) }
        }
    }

    public func instance<C: PluginContract>(of contract: C.Type, from id: PluginID? = nil) throws -> C.Interface {
        let value = try resolveInstance(
            interfaceID: C.interfaceID,
            compatibilityHash: C.compatibilityHash,
            from: id)
        guard let typed = value as? C.Interface else {
            throw PluginError.typeMismatch(
                expected: String(reflecting: C.Interface.self),
                actual: String(reflecting: type(of: value)))
        }
        return typed
    }

    /// Runs the module's `willDeactivate` hook and removes the registration.
    /// The binary stays mapped (never dlclosed); re-registering the same path
    /// reuses the cached descriptor.
    public func deactivate(_ id: PluginID) throws {
        let descriptor = try state.withLock { (state: inout State) -> PluginDescriptor in
            guard let plugin = state.loaded[id] else {
                throw PluginError.pluginNotRegistered(id)
            }
            return plugin.descriptor
        }
        descriptor.willDeactivate(PluginContext(pluginID: id, resolver: self))
        state.withLock { state in
            state.loaded[id] = nil
            state.activated.remove(id)
        }
    }
}

extension PluginManager: PluginInstanceResolving {
    public func resolveInstance(
        interfaceID: InterfaceID,
        compatibilityHash: String,
        from id: PluginID?
    ) throws -> Any {
        let resolved = try state.withLock { (state: inout State) -> (id: PluginID, factory: @Sendable (PluginContext) -> Any) in
            let provider: LoadedPlugin
            if let id {
                guard let loaded = state.loaded[id] else {
                    throw PluginError.pluginNotRegistered(id)
                }
                provider = loaded
            } else {
                let candidates = state.loaded.values
                    .filter { plugin in plugin.manifest.exports.contains { $0.interfaceID == interfaceID } }
                    .sorted { $0.manifest.id.rawValue < $1.manifest.id.rawValue }
                guard let first = candidates.first else {
                    throw PluginError.interfaceNotExported(interfaceID)
                }
                provider = first
            }
            guard let export = provider.manifest.exports.first(where: { $0.interfaceID == interfaceID }) else {
                throw PluginError.interfaceNotExported(interfaceID)
            }
            guard export.compatibilityHash == compatibilityHash else {
                throw PluginError.interfaceIncompatible(
                    interfaceID: interfaceID,
                    hostHash: compatibilityHash,
                    pluginHash: export.compatibilityHash,
                    plugin: provider.manifest.id)
            }
            guard state.activated.contains(provider.manifest.id) else {
                throw PluginError.notActivated(provider.manifest.id)
            }
            guard let factory = provider.descriptor.factories[interfaceID] else {
                throw PluginError.interfaceNotExported(interfaceID)
            }
            return (provider.manifest.id, factory)
        }
        // Instances are intentionally not cached; factories own that policy.
        return resolved.factory(PluginContext(pluginID: resolved.id, resolver: self))
    }
}
