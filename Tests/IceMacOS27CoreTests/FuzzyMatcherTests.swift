import Testing
@testable import IceMacOS27Core

@Suite("FuzzyMatcher")
struct FuzzyMatcherTests {
    @Test("Exact and prefix matches outrank loose subsequence matches")
    func ranksExactAndPrefixHigher() throws {
        let exact = try #require(FuzzyMatcher.score(query: "wifi", candidate: "WiFi"))
        let prefix = try #require(FuzzyMatcher.score(query: "wifi", candidate: "WiFi Calling"))
        let loose = try #require(FuzzyMatcher.score(query: "wifi", candidate: "Window Finder"))

        #expect(exact > prefix)
        #expect(prefix > loose)
    }

    @Test("Matches camelCase and word boundaries")
    func matchesCamelCaseAndBoundaries() throws {
        let cc = try #require(FuzzyMatcher.score(query: "cc", candidate: "ControlCenter"))
        let boundary = try #require(FuzzyMatcher.score(query: "dd", candidate: "Docker Desktop"))
        #expect(cc > 0)
        #expect(boundary > 0)
    }

    @Test("Returns nil when characters are missing or out of order")
    func returnsNilOnMismatch() {
        #expect(FuzzyMatcher.score(query: "xyz", candidate: "ControlCenter") == nil)
        #expect(FuzzyMatcher.score(query: "fc", candidate: "Control") == nil)
    }
}
