import SwiftUI
import FlycutCore

struct ImageThumbnailView: View {
    let metadata: ClipImage
    @ObservedObject var images: ImagePreviewModel
    var body: some View {
        Group {
            if let image = images.thumbnails[metadata.assetHash] { Image(nsImage: image).resizable().scaledToFit() }
            else { Image(systemName: "photo").foregroundStyle(.secondary) }
        }.frame(width: 44, height: 44).task(id: metadata.assetHash) { await images.loadThumbnail(hash: metadata.assetHash) }
    }
}
struct ImagePreviewView: View {
    let clip: Clip
    @ObservedObject var model: PaletteModel
    @ObservedObject var images: ImagePreviewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Button("Back") { model.closeImagePreview() }; Spacer(); Text("Image Preview").font(.headline) }
            if let file = clip.files?.first { Text(file.name).font(.headline).textSelection(.enabled) }
            else { Text("Filename unavailable").font(.caption).foregroundStyle(.secondary) }
            if let image = images.preview { Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if let error = images.error { Text(error) }
            else { ProgressView() }
            if let file = clip.files?.first { Text(file.path).font(.caption).textSelection(.enabled) }
            else { Text("No file path — copied directly from an app.").font(.caption).foregroundStyle(.secondary) }
            if let metadata = clip.image {
                Text("\(metadata.width) × \(metadata.height) · \(ByteCountFormatter.string(fromByteCount: Int64(metadata.byteCount), countStyle: .file))").font(.caption)
                if let text = metadata.recognizedText, !text.isEmpty {
                    ScrollView { Text(text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 130)
                    Button("Copy Extracted Text") { model.copyExtractedText(clip.id) }
                } else {
                    Text(metadata.recognitionState == .pending ? "Text recognition pending" : metadata.recognitionState == .noText ? "No text recognized" : "Text recognition unavailable").font(.caption)
                    Button("Recognize Text Again") { model.retryRecognition(clip.id) }
                }
            }
        }.padding(16).task(id: clip.image?.assetHash) { if let hash = clip.image?.assetHash { await images.load(hash: hash) } }
        .onExitCommand { model.closeImagePreview() }
    }
}
