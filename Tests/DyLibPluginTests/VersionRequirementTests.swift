import DyLibPlugin
import Testing

struct VersionRequirementTests {
    @Test func exactMatchesOnlyTheExactVersion() {
        let requirement = VersionRequirement.exact(SemanticVersion(1, 2, 3))
        #expect(requirement.isSatisfied(by: SemanticVersion(1, 2, 3)))
        #expect(!requirement.isSatisfied(by: SemanticVersion(1, 2, 2)))
        #expect(!requirement.isSatisfied(by: SemanticVersion(1, 2, 4)))
        #expect(!requirement.isSatisfied(by: SemanticVersion(2, 2, 3)))
    }

    @Test func fromMatchesUpToTheNextMajor() {
        let requirement = VersionRequirement.from(SemanticVersion(1, 2, 3))
        #expect(requirement.isSatisfied(by: SemanticVersion(1, 2, 3)))
        #expect(requirement.isSatisfied(by: SemanticVersion(1, 2, 4)))
        #expect(requirement.isSatisfied(by: SemanticVersion(1, 99, 0)))
        #expect(!requirement.isSatisfied(by: SemanticVersion(1, 2, 2)))
        #expect(!requirement.isSatisfied(by: SemanticVersion(0, 9, 9)))
        #expect(!requirement.isSatisfied(by: SemanticVersion(2, 0, 0)))
    }

    @Test func atLeastHasNoUpperBound() {
        let requirement = VersionRequirement.atLeast(SemanticVersion(1, 2, 3))
        #expect(requirement.isSatisfied(by: SemanticVersion(1, 2, 3)))
        #expect(requirement.isSatisfied(by: SemanticVersion(2, 0, 0)))
        #expect(requirement.isSatisfied(by: SemanticVersion(99, 0, 0)))
        #expect(!requirement.isSatisfied(by: SemanticVersion(1, 2, 2)))
        #expect(!requirement.isSatisfied(by: SemanticVersion(0, 0, 0)))
    }
}
