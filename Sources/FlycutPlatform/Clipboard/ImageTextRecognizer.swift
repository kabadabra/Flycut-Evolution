import Foundation
import Vision

public protocol ImageTextRecognizing: Sendable {
    func recognize(_ png: Data) async throws -> String
}
public struct ImageTextRecognizer: ImageTextRecognizing {
    public init() {}
    public func recognize(_ png: Data) async throws -> String {
        try await Task.detached(priority: .utility) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            try VNImageRequestHandler(data: png).perform([request])
            let observations = (request.results ?? []).sorted { a, b in
                if abs(a.boundingBox.midY - b.boundingBox.midY) > 0.02 { return a.boundingBox.midY > b.boundingBox.midY }
                return a.boundingBox.minX < b.boundingBox.minX
            }
            return String(observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n").prefix(512_000))
        }.value
    }
}
