import XCTest
@testable import FlycutCore

final class ClipSearchTests: XCTestCase {
    private func clip(_ text: String, name: String? = nil) -> Clip {
        Clip(id: UUID(), text: text, pasteboardType: "text", sourceAppName: nil, sourceBundleURL: nil,
             capturedAt: nil, collection: .recent, order: 0, favoriteMetadata: name.map { .init(name: $0, rank: 0) })
    }
    func testContiguousMatchesPrecedeFuzzyAndTiesStayStable() {
        let fuzzy = clip("meeting"), exact = clip("mtg"), second = clip("mtg")
        XCTAssertEqual(ClipSearch.search("mtg", in: [fuzzy,exact,second]).map { $0.clip.id }, [exact.id,second.id,fuzzy.id])
        XCTAssertFalse(ClipSearch.search("mtg", in: [exact])[0].isFuzzy)
    }
    func testTyposMissingLettersAndNamesMatch() {
        let item = clip("meeting", name: "Office address")
        for query in ["mtg", "meetign", "meetin", "OFFICE"] { XCTAssertEqual(ClipSearch.search(query, in: [item]).first?.clip.id, item.id, query) }
        XCTAssertTrue(ClipSearch.search("z", in: [item]).isEmpty)
        XCTAssertTrue(ClipSearch.search("", in: [item]).count == 1)
    }
    func testRangesReferToOriginalGraphemeBoundaries() {
        let text = "🦋 Cafe\u{301} résumé"
        let item = clip(text)
        let result = ClipSearch.search("CAFE", in: [item])
        XCTAssertEqual(result.count, 1)
        let characters = Array(text)
        let matches = result[0].textRanges.map { String(characters[$0]) }.joined()
        XCTAssertEqual(matches, "Cafe\u{301}")
        let excerpt = ClipSearch.excerpt(text: text, ranges: result[0].textRanges, limit: 12)
        XCTAssertTrue(excerpt.text.contains("Cafe\u{301}"))
        XCTAssertTrue(excerpt.ranges.allSatisfy { $0.upperBound <= excerpt.text.count })
    }
    func testFullTextMatchAppearsInContextBeyondFuzzyLimit() {
        let text = String(repeating: "x", count: 6000) + " needle ending"
        let result = ClipSearch.search("needle", in: [clip(text)])
        XCTAssertEqual(result.count, 1)
        let excerpt = ClipSearch.excerpt(text: text, ranges: result[0].textRanges, limit: 40)
        XCTAssertTrue(excerpt.text.contains("needle"))
        XCTAssertLessThanOrEqual(excerpt.text.count, 42)
        XCTAssertEqual(ClipSearch.search("ndle", in: [clip(text)]).count, 0)
    }
    func testCloserExactAndTighterLaterFuzzyMatchesRankFirst() {
        let distant = clip(String(repeating: "x", count: 500) + "needle")
        let close = clip("x needle")
        XCTAssertEqual(ClipSearch.search("needle", in: [distant,close]).map { $0.clip.id }, [close.id,distant.id])
        let later = clip("a" + String(repeating: "x", count: 100) + "b" + String(repeating: "x", count: 100) + "c abxc")
        let scattered = clip("axxbxxc")
        let matches = ClipSearch.search("abc", in: [scattered,later])
        XCTAssertEqual(matches.map { $0.clip.id }, [later.id,scattered.id])
        XCTAssertEqual(matches.first?.textRanges, [204..<206, 207..<208])
    }

}
