import DyLibPlugin
import Foundation
import Testing

struct SemanticVersionTests {
    @Test func parsesValidVersion() throws {
        let version = try #require(SemanticVersion(parsing: "1.2.3"))
        #expect(version.major == 1)
        #expect(version.minor == 2)
        #expect(version.patch == 3)
    }

    @Test(arguments: ["1.2", "a.b.c", "1.2.3.4", "-1.2.3", ""])
    func rejectsInvalidVersion(_ string: String) {
        #expect(SemanticVersion(parsing: string) == nil)
    }

    @Test func ordersComponentsNumerically() {
        #expect(SemanticVersion(1, 0, 0) < SemanticVersion(1, 0, 1))
        #expect(SemanticVersion(1, 0, 9) < SemanticVersion(1, 1, 0))
        #expect(SemanticVersion(1, 9, 9) < SemanticVersion(2, 0, 0))
        #expect(SemanticVersion(0, 10, 0) > SemanticVersion(0, 9, 9))
        #expect(!(SemanticVersion(1, 2, 3) < SemanticVersion(1, 2, 3)))
    }

    @Test func roundTripsThroughJSON() throws {
        let versions = [SemanticVersion(1, 2, 3), SemanticVersion(0, 0, 0), SemanticVersion(10, 20, 30)]
        let data = try JSONEncoder().encode(versions)
        let decoded = try JSONDecoder().decode([SemanticVersion].self, from: data)
        #expect(decoded == versions)
    }

    @Test func decodingRejectsInvalidString() {
        let data = Data(#"["1.2"]"#.utf8)
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode([SemanticVersion].self, from: data)
        }
    }

    @Test func describesAsDotSeparatedComponents() {
        #expect(SemanticVersion(1, 2, 3).description == "1.2.3")
        #expect("\(SemanticVersion(0, 0, 1))" == "0.0.1")
    }
}
