import AppKit
import SwiftUI
import FlycutCore

enum ClippingPreviewContent {
    static func attributedText(for clip: Clip) -> NSAttributedString? {
        guard let rtf = clip.formattedRTF, !rtf.isEmpty, rtf.count <= 256 * 1024,
              let styled = try? NSAttributedString(data: rtf,
                                                   options: [.documentType: NSAttributedString.DocumentType.rtf],
                                                   documentAttributes: nil),
              normalizedLineEndings(styled.string) == normalizedLineEndings(clip.text) else { return nil }
        return styled
    }

    private static func normalizedLineEndings(_ value: String) -> String {
        value.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }
}

struct ClippingPreview: View {
    let clip: Clip

    var body: some View {
        let styled = ClippingPreviewContent.attributedText(for: clip)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Full clipping").font(.headline)
                Spacer()
                if styled != nil {
                    Text("Formatted").font(.caption).foregroundStyle(.secondary)
                }
            }
            Divider()
            ScrollView {
                Group {
                    if let styled {
                        Text(AttributedString(styled))
                    } else {
                        Text(clip.text)
                    }
                }
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 340, height: 320)
        }
        .padding(14)
        .frame(width: 368)
    }
}
