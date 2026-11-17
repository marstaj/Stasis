import Testing
@testable import StasisCore

@Suite struct ReleaseVersionTests {
    @Test func parsesPlainVersionsAndReleaseTags() {
        #expect(ReleaseVersion("1.2.3")?.description == "1.2.3")
        #expect(ReleaseVersion("v1.2.3")?.description == "1.2.3")
        #expect(ReleaseVersion("2")?.description == "2")
    }

    @Test(arguments: ["", "v", "abc", "1.x", "1..2", "1.2.", "-1.0", "1.2.0-beta", "vv1.0"])
    func rejectsAnythingButDottedNumbers(_ string: String) {
        #expect(ReleaseVersion(string) == nil)
    }

    @Test func comparesComponentsAsNumbers() throws {
        #expect(try #require(ReleaseVersion("1.10")) > #require(ReleaseVersion("1.9")))
        #expect(try #require(ReleaseVersion("2.0")) > #require(ReleaseVersion("1.99.99")))
        #expect(try #require(ReleaseVersion("1.0.1")) > #require(ReleaseVersion("1.0")))
    }

    @Test func missingComponentsCountAsZero() throws {
        let short = try #require(ReleaseVersion("1.0"))
        let long = try #require(ReleaseVersion("v1.0.0"))
        #expect(short == long)
        #expect(!(short < long) && !(long < short))
    }
}
