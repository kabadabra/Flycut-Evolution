import Foundation

public struct ClipSearchResult: Equatable, Sendable {
    public let clip: Clip
    public let nameRanges: [Range<Int>]
    public let textRanges: [Range<Int>]
    public let isFuzzy: Bool
}
public struct SearchExcerpt: Equatable, Sendable {
    public let text: String
    public let ranges: [Range<Int>]
}

public enum ClipSearch {
    private struct Score: Comparable {
        let category: Int
        let quality: Int
        let proximity: Int
        static func < (lhs: Score, rhs: Score) -> Bool {
            if lhs.category != rhs.category { return lhs.category < rhs.category }
            if lhs.quality != rhs.quality { return lhs.quality < rhs.quality }
            return lhs.proximity < rhs.proximity
        }
    }
    private struct Match { let ranges: [Range<Int>]; let score: Score; let fuzzy: Bool }
    public static func search(_ query: String, in clips: [Clip]) -> [ClipSearchResult] {
        guard !query.isEmpty else { return clips.map { .init(clip: $0, nameRanges: [], textRanges: [], isFuzzy: false) } }
        var found: [(Score, Int, ClipSearchResult)] = []
        for (index, clip) in clips.enumerated() {
            if Task.isCancelled { break }
            let name = match(query, in: clip.favoriteMetadata?.name ?? "")
            let text = match(query, in: clip.searchableText)
            guard let best = [name, text].compactMap({ $0 }).min(by: { $0.score < $1.score }) else { continue }
            found.append((best.score, index, .init(clip: clip, nameRanges: name?.ranges ?? [], textRanges: text?.ranges ?? [], isFuzzy: best.fuzzy)))
        }
        return found.sorted { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0 }.map { $0.2 }
    }

    private static func match(_ query: String, in text: String) -> Match? {
        guard !text.isEmpty else { return nil }
        if let range = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")) {
            let composed = (text as NSString).rangeOfComposedCharacterSequences(for: NSRange(range, in: text))
            guard let whole = Range(composed, in: text) else { return nil }
            let start = text.distance(from: text.startIndex, to: whole.lowerBound)
            let end = text.distance(from: text.startIndex, to: whole.upperBound)
            return Match(ranges: [start..<end], score: Score(category: 0, quality: 0, proximity: start), fuzzy: false)
        }
        guard query.count > 1, query.count <= 128 else { return nil }
        let pattern = Array(fold(query))
        var units: [Character] = [], positions: [Int] = []
        for (offset, character) in text.prefix(5000).enumerated() {
            for unit in fold(String(character)) { units.append(unit); positions.append(offset) }
        }
        guard !pattern.isEmpty else { return nil }
        // Retain the latest start for each partial subsequence. This finds
        // tighter later windows without repeatedly scanning the same suffix.
        var paths = [[Int]?](repeating: nil, count: pattern.count)
        var best: Match?
        for index in units.indices {
            if Task.isCancelled { return nil }
            for part in pattern.indices.reversed() where units[index] == pattern[part] {
                if part == 0 { paths[part] = [index] }
                else if let previous = paths[part-1] { paths[part] = previous + [index] }
                else { continue }
                if part == pattern.count-1, let path = paths[part] {
                    let matched = path.map { positions[$0] }
                    let score = Score(category: 1, quality: path.last! - path.first! + 1 - pattern.count, proximity: matched.first!)
                    if best == nil || score < best!.score { best = Match(ranges: coalesced(matched), score: score, fuzzy: true) }
                }
            }
        }
        if let best { return best }
        guard pattern.count >= 4, !pattern.contains(where: { $0.isWhitespace }) else { return nil }
        // Search words for a single insertion/deletion/substitution or transposition.
        var start = 0
        while start < units.count {
            while start < units.count && !units[start].isLetter && !units[start].isNumber { start += 1 }
            var end = start
            while end < units.count && (units[end].isLetter || units[end].isNumber) { end += 1 }
            if start < end, oneEdit(pattern, Array(units[start..<end])) {
                return Match(ranges: [positions[start]..<(positions[end-1] + 1)], score: Score(category: 1, quality: 100, proximity: positions[start]), fuzzy: true)
            }
            start = end + 1
        }
        return nil
    }
    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
    private static func oneEdit(_ a: [Character], _ b: [Character]) -> Bool {
        guard abs(a.count-b.count) <= 1 else { return false }
        if a.count == b.count {
            let different = a.indices.filter { a[$0] != b[$0] }
            if different.count <= 1 { return true }
            if different.count == 2 {
                let i = different[0], j = different[1]
                return j == i+1 && a[i] == b[j] && a[j] == b[i]
            }
            return false
        }
        let shorter = a.count < b.count ? a : b, longer = a.count < b.count ? b : a
        var i = 0, j = 0, skipped = false
        while i < shorter.count && j < longer.count {
            if shorter[i] == longer[j] { i += 1; j += 1 }
            else if skipped { return false }
            else { skipped = true; j += 1 }
        }
        return true
    }
    private static func coalesced(_ indices: [Int]) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        for index in indices {
            if let last = ranges.last, index <= last.upperBound { ranges[ranges.count-1] = last.lowerBound..<max(last.upperBound, index+1) }
            else { ranges.append(index..<(index+1)) }
        }
        return ranges
    }
    public static func excerpt(text: String, ranges: [Range<Int>], limit: Int) -> SearchExcerpt {
        let maximum = max(1, limit)
        // Avoid turning a long clip into a full array just to render one row.
        let first = ranges.first?.lowerBound ?? 0
        let startOffset = max(0, first - maximum/4)
        let start = text.index(text.startIndex, offsetBy: startOffset, limitedBy: text.endIndex) ?? text.endIndex
        let end = text.index(start, offsetBy: maximum, limitedBy: text.endIndex) ?? text.endIndex
        let endOffset = startOffset + text.distance(from: start, to: end)
        let prefix = start > text.startIndex ? "…" : ""
        let suffix = end < text.endIndex ? "…" : ""
        let adjusted = ranges.compactMap { range -> Range<Int>? in
            let lo = max(range.lowerBound, startOffset), hi = min(range.upperBound, endOffset)
            guard lo < hi else { return nil }
            return (lo-startOffset+prefix.count)..<(hi-startOffset+prefix.count)
        }
        return .init(text: prefix + String(text[start..<end].map { $0.isWhitespace ? Character(" ") : $0 }) + suffix, ranges: adjusted)
    }
}
