import SwiftUI
import FlycutCore

struct PaletteRow: View {
    let clip: Clip
    let selected: Bool
    let hovered: Bool
    let showSource: Bool
    let showType: Bool
    let previewLength: Int
    let onClick: (Int) -> Void
    let onHover: (Bool) -> Void
    var shortcutNumber: Int? = nil
    var searchResult: ClipSearchResult? = nil
    var favoriteShortcutConflict = false
    var images: ImagePreviewModel? = nil
    private func highlighted(_ text: String, ranges: [Range<Int>]) -> AttributedString {
        var value = AttributedString(text)
        for range in ranges where range.lowerBound >= 0 && range.upperBound <= value.characters.count {
            let lower = value.characters.index(value.characters.startIndex, offsetBy: range.lowerBound)
            let upper = value.characters.index(value.characters.startIndex, offsetBy: range.upperBound)
            value[lower..<upper].foregroundColor = .accentColor
            value[lower..<upper].font = .body.bold()
        }
        return value
    }
    private var contentPreview: Text {
        if let result = searchResult {
            let excerpt = ClipSearch.excerpt(text: clip.searchableText, ranges: result.textRanges, limit: max(40, previewLength))
            return Text(highlighted(excerpt.text, ranges: excerpt.ranges))
        }
        return Text(clip.previewLine(limit: previewLength))
    }
    private func shortcutBadge(_ label: String, conflict: Bool = false) -> some View {
        Text(label)
            .font(.caption.monospaced())
            .foregroundStyle(conflict ? Color.orange : Color.secondary)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(conflict ? Color.orange.opacity(0.5) : Color.secondary.opacity(0.35), lineWidth: 1)
            }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 2) {
                if let metadata = clip.image, let images { ImageThumbnailView(metadata: metadata, images: images).padding(.leading, 5).onTapGesture { onClick(1) } }
                VStack(alignment: .leading, spacing: 2) {
                    if let name = clip.favoriteMetadata?.name, !name.isEmpty {
                        Text(highlighted(name, ranges: searchResult?.nameRanges ?? [])).font(.headline)
                            .lineLimit(1).truncationMode(.tail)
                    }
                    contentPreview.lineLimit(1).truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let image = clip.image { Text("\(image.width) × \(image.height)").font(.caption).foregroundStyle(.secondary) }
                    if showSource {
                        Text(clip.sourceAppName ?? "Unknown source")
                            .font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.tail)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .overlay { ImmediateRowClickSurface(onClick: onClick, onHover: onHover) }
                HStack(spacing: 6) {
                    if clip.collection == .favorite {
                        Image(systemName: "star.fill").font(.caption2).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .trailing, spacing: 3) {
                        if let shortcutNumber { shortcutBadge("⌘\(shortcutNumber)") }
                        if let slot = clip.favoriteMetadata?.shortcut {
                            shortcutBadge(favoriteShortcutConflict ? "Conflict" : "⌥⌘\(slot)", conflict: favoriteShortcutConflict)
                        }
                    }
                }.padding(.trailing, 8)

            }
            if showType {
                SelectableTypeLabel(text: "Type: \(clip.pasteboardType)", onClick: onClick)
                    .padding(.horizontal, 8).padding(.bottom, 5)
            }
        }
        .background(selected ? Color.accentColor.opacity(0.18) : hovered ? Color.accentColor.opacity(0.10) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
