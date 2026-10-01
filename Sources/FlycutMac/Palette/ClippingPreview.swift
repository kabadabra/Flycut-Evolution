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
    @ObservedObject var images: ImagePreviewModel

    var body: some View {
        let styled = ClippingPreviewContent.attributedText(for: clip)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(clip.image != nil ? "Image" : clip.files != nil ? "File details" : "Full clipping").font(.headline)
                Spacer()
                if styled != nil {
                    Text("Formatted").font(.caption).foregroundStyle(.secondary)
                }
            }
            Divider()
            ScrollView {
                Group {
                    if clip.image != nil || clip.files != nil {
                        VStack(alignment: .leading, spacing: 12) {
                            if let files = clip.files, !files.isEmpty {
                                ForEach(Array(files.enumerated()), id: \.offset) { _, file in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Filename").font(.caption).foregroundStyle(.secondary)
                                        Text(file.name).textSelection(.enabled)
                                    }
                                }
                            } else {
                                Text("Filename unavailable").foregroundStyle(.secondary)
                            }
                            if let metadata = clip.image {
                                if let image = images.thumbnails[metadata.assetHash] {
                                    Image(nsImage: image).resizable().scaledToFit()
                                        .frame(maxWidth: .infinity, maxHeight: 190)
                                        .accessibilityLabel("Copied image preview")
                                } else {
                                    Label("Image preview unavailable", systemImage: "photo").foregroundStyle(.secondary)
                                }
                            } else {
                                Label("Preview unavailable", systemImage: "doc").foregroundStyle(.secondary)
                            }
                            if let files = clip.files, !files.isEmpty {
                                ForEach(Array(files.enumerated()), id: \.offset) { _, file in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(files.count == 1 ? "Full path" : "Full path · \(file.name)").font(.caption).foregroundStyle(.secondary)
                                        Text(file.path).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            } else {
                                Text("No file path — copied directly from an app.").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } else if let styled {
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
        .task(id: clip.image?.assetHash) { if let hash = clip.image?.assetHash { await images.loadThumbnail(hash: hash) } }
    }
}
