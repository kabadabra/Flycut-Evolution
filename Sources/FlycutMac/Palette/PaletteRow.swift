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
    let onPastePlain: () -> Void
    let onHover: (Bool) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 2) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(clip.previewLine(limit: previewLength)).lineLimit(1).truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
                if clip.formattedRTF != nil {
                    Button(action: onPastePlain) { Image(systemName: "textformat") }
                        .buttonStyle(.borderless)
                        .help("Paste without formatting")
                        .accessibilityLabel("Paste clipping without formatting")
                        .padding(.trailing, 8)
                }
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
