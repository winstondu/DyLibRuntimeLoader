import Testing

@testable import DyLibPlugin

private func manifest(
    _ id: String,
    version: SemanticVersion = SemanticVersion(1, 0, 0),
    dependencies: [PluginDependency] = []
) -> PluginManifest {
    PluginManifest(
        id: PluginID(id),
        version: version,
        abiVersion: DyLibPluginABI.current,
        exports: [],
        dependencies: dependencies)
}

struct DependencyResolverTests {
    @Test func linearChainPutsDependenciesFirst() throws {
        let order = try DependencyResolver.activationOrder(for: [
            manifest("c", dependencies: [.plugin("b", .atLeast("1.0.0"))]),
            manifest("b", dependencies: [.plugin("a", .atLeast("1.0.0"))]),
            manifest("a"),
        ])
        #expect(order == [PluginID("a"), PluginID("b"), PluginID("c")])
    }

    @Test func diamondActivatesSharedDependencyFirst() throws {
        let order = try DependencyResolver.activationOrder(for: [
            manifest("a", dependencies: [.plugin("b", .atLeast("1.0.0")), .plugin("c", .atLeast("1.0.0"))]),
            manifest("b", dependencies: [.plugin("d", .atLeast("1.0.0"))]),
            manifest("c", dependencies: [.plugin("d", .atLeast("1.0.0"))]),
            manifest("d"),
        ])
        #expect(order == [PluginID("d"), PluginID("b"), PluginID("c"), PluginID("a")])
    }

    @Test func independentPluginsSortByID() throws {
        let order = try DependencyResolver.activationOrder(for: [
            manifest("b"),
            manifest("c"),
            manifest("a"),
        ])
        #expect(order == [PluginID("a"), PluginID("b"), PluginID("c")])
    }

    @Test func missingDependencyThrows() {
        #expect(throws: PluginError.missingDependency(required: PluginID("missing"), requiredBy: PluginID("a"))) {
            _ = try DependencyResolver.activationOrder(for: [
                manifest("a", dependencies: [.plugin("missing", .atLeast("1.0.0"))])
            ])
        }
    }

    @Test func exactRequirementSatisfiedResolves() throws {
        let order = try DependencyResolver.activationOrder(for: [
            manifest("a", version: "1.2.3"),
            manifest("b", dependencies: [.plugin("a", .exact("1.2.3"))]),
        ])
        #expect(order == [PluginID("a"), PluginID("b")])
    }

    @Test func exactRequirementViolatedThrows() {
        #expect(throws: PluginError.versionUnsatisfied(
            dependency: PluginID("a"),
            requiredBy: PluginID("b"),
            requirement: String(describing: VersionRequirement.exact("1.2.3")),
            found: "1.2.4")
        ) {
            _ = try DependencyResolver.activationOrder(for: [
                manifest("a", version: "1.2.4"),
                manifest("b", dependencies: [.plugin("a", .exact("1.2.3"))]),
            ])
        }
    }

    @Test func fromRequirementSatisfiedResolves() throws {
        let order = try DependencyResolver.activationOrder(for: [
            manifest("a", version: "1.9.0"),
            manifest("b", dependencies: [.plugin("a", .from("1.2.0"))]),
        ])
        #expect(order == [PluginID("a"), PluginID("b")])
    }

    @Test func fromRequirementViolatedAtMajorBoundaryThrows() {
        #expect(throws: PluginError.versionUnsatisfied(
            dependency: PluginID("a"),
            requiredBy: PluginID("b"),
            requirement: String(describing: VersionRequirement.from("1.2.0")),
            found: "2.0.0")
        ) {
            _ = try DependencyResolver.activationOrder(for: [
                manifest("a", version: "2.0.0"),
                manifest("b", dependencies: [.plugin("a", .from("1.2.0"))]),
            ])
        }
    }

    @Test func atLeastRequirementSatisfiedResolves() throws {
        let order = try DependencyResolver.activationOrder(for: [
            manifest("a", version: "9.0.0"),
            manifest("b", dependencies: [.plugin("a", .atLeast("1.2.0"))]),
        ])
        #expect(order == [PluginID("a"), PluginID("b")])
    }

    @Test func atLeastRequirementViolatedThrows() {
        #expect(throws: PluginError.versionUnsatisfied(
            dependency: PluginID("a"),
            requiredBy: PluginID("b"),
            requirement: String(describing: VersionRequirement.atLeast("1.2.0")),
            found: "1.1.9")
        ) {
            _ = try DependencyResolver.activationOrder(for: [
                manifest("a", version: "1.1.9"),
                manifest("b", dependencies: [.plugin("a", .atLeast("1.2.0"))]),
            ])
        }
    }

    @Test func twoNodeCycleThrowsWithClosedPath() {
        do {
            _ = try DependencyResolver.activationOrder(for: [
                manifest("a", dependencies: [.plugin("b", .atLeast("1.0.0"))]),
                manifest("b", dependencies: [.plugin("a", .atLeast("1.0.0"))]),
            ])
            Issue.record("Expected dependencyCycle")
        } catch PluginError.dependencyCycle(let path) {
            #expect(path.first == path.last)
            #expect(path == [PluginID("a"), PluginID("b"), PluginID("a")])
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func threeNodeCycleThrowsWithClosedPath() {
        do {
            _ = try DependencyResolver.activationOrder(for: [
                manifest("a", dependencies: [.plugin("b", .atLeast("1.0.0"))]),
                manifest("b", dependencies: [.plugin("c", .atLeast("1.0.0"))]),
                manifest("c", dependencies: [.plugin("a", .atLeast("1.0.0"))]),
            ])
            Issue.record("Expected dependencyCycle")
        } catch PluginError.dependencyCycle(let path) {
            #expect(path.first == path.last)
            #expect(path == [PluginID("a"), PluginID("b"), PluginID("c"), PluginID("a")])
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
