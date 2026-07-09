/// Pure dependency-graph logic, fully unit-testable without dlopen.
struct DependencyResolver {
    private enum Mark {
        case visiting
        case done
    }

    /// Returns all plugin ids ordered so that every dependency comes before
    /// its dependents. Deterministic: roots are visited sorted by id, and
    /// each node's dependencies are visited in declaration order.
    static func activationOrder(for manifests: [PluginManifest]) throws -> [PluginID] {
        var manifestsByID = [PluginID: PluginManifest](minimumCapacity: manifests.count)
        for manifest in manifests {
            manifestsByID[manifest.id] = manifest
        }

        let sortedManifests = manifests.sorted { $0.id.rawValue < $1.id.rawValue }

        for manifest in sortedManifests {
            for dependency in manifest.dependencies {
                guard let target = manifestsByID[dependency.id] else {
                    throw PluginError.missingDependency(required: dependency.id, requiredBy: manifest.id)
                }
                guard dependency.requirement.isSatisfied(by: target.version) else {
                    throw PluginError.versionUnsatisfied(
                        dependency: dependency.id,
                        requiredBy: manifest.id,
                        requirement: String(describing: dependency.requirement),
                        found: String(describing: target.version))
                }
            }
        }

        var marks = [PluginID: Mark]()
        var stack = [PluginID]()
        var order = [PluginID]()

        func visit(_ id: PluginID) throws {
            switch marks[id] {
            case .done:
                return
            case .visiting:
                let start = stack.firstIndex(of: id) ?? stack.startIndex
                throw PluginError.dependencyCycle(path: Array(stack[start...]) + [id])
            case nil:
                marks[id] = .visiting
                stack.append(id)
                for dependency in manifestsByID[id]?.dependencies ?? [] {
                    try visit(dependency.id)
                }
                stack.removeLast()
                marks[id] = .done
                order.append(id)
            }
        }

        for manifest in sortedManifests {
            try visit(manifest.id)
        }
        return order
    }
}
