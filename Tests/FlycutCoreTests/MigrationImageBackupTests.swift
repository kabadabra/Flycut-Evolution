import XCTest
@testable import FlycutCore

final class MigrationImageBackupTests: XCTestCase {
    func testReplaceImportBackupPreservesImageAssetBytes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = LegacySource(url: directory.appendingPathComponent("synthetic.plist"))
        let data = try PropertyListSerialization.data(fromPropertyList: ["savePreference": 1, "store": ["version": "0.7", "rememberNum": 1, "favoritesRememberNum": 1, "jcList": [["Contents": "Synthetic imported text", "Type": "NSStringPboardType"]], "favoritesList": []]], format: .xml, options: 0)
        try data.write(to: source.url)
        let repository = try SQLiteHistoryRepository()
        let clip = Clip(id: UUID(), text: "", pasteboardType: "public.png", sourceAppName: nil, sourceBundleURL: nil, capturedAt: nil, collection: .recent, order: 0, image: .init(assetHash: "synthetic", width: 1, height: 1, byteCount: 3))
        _ = try await repository.applyImage(.init(hash: "synthetic", png: Data([1,2,3])), clip: clip, budgetBytes: 3)
        let migration = MigrationCoordinator(destination: repository, backupDirectory: directory.appendingPathComponent("backup"))
        let report = try await migration.import(source: source, choice: .replace(confirmed: true))
        let backupData = try Data(contentsOf: XCTUnwrap(report.destinationBackup))
        let backup = try JSONDecoder().decode(HistorySnapshot.self, from: backupData)
        XCTAssertEqual(backup.recent.first?.image?.assetHash, "synthetic")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: backupData) as? [String: Any])
        XCTAssertNotNil(object["imageAssets"])
        let assets = try JSONDecoder().decode([ImageAsset].self, from: JSONSerialization.data(withJSONObject: XCTUnwrap(object["imageAssets"])))
        XCTAssertEqual(assets.first?.png, Data([1,2,3]))
        let lost = try await repository.imageData(for: "synthetic")
        XCTAssertNil(lost, "Removed assets must remain recoverable from the backup")
    }
}
