import XCTest
@testable import FlycutCore
final class ImageSafetyRegressionTests: XCTestCase {
    func image(_ hash: String, collection: CollectionKind = .recent) -> Clip {
        Clip(id: UUID(), text: "", pasteboardType: "public.png", sourceAppName: nil, sourceBundleURL: nil, capturedAt: nil, collection: collection, order: 0, image: .init(assetHash: hash, width: 1, height: 1, byteCount: 3))
    }
    func testImageAdmissionArchivesCapacityAndBudgetVictims() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let repo = try SQLiteHistoryRepository()
        let text = Clip(id: UUID(), text: "preserve me", pasteboardType: "text", sourceAppName: nil, sourceBundleURL: nil, capturedAt: nil, collection: .recent, order: 0)
        _ = try await repo.apply(.insert(text))
        _ = try await repo.applyImage(.init(hash: "a", png: Data([1,2,3])), clip: image("a"), budgetBytes: 3, recentCapacity: 1, archive: .init(directory: dir))
        _ = try await repo.applyImage(.init(hash: "b", png: Data([4,5,6])), clip: image("b"), budgetBytes: 3, recentCapacity: 1, archive: .init(directory: dir))
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(files.first { $0.pathExtension == "png" })), Data([1,2,3]))
        XCTAssertEqual(try String(contentsOf: XCTUnwrap(files.first { $0.pathExtension == "txt" }), encoding: .utf8), "preserve me")
        let before = try await repo.snapshot()
        let badDirectory = dir.appendingPathComponent("file")
        try Data().write(to: badDirectory)
        do {
            _ = try await repo.applyImage(.init(hash: "c", png: Data([7,8,9])), clip: image("c"), budgetBytes: 3, recentCapacity: 1, archive: .init(directory: badDirectory))
            XCTFail("An archive failure must preserve history")
        } catch {}
        let after = try await repo.snapshot()
        XCTAssertEqual(before, after)
        let asset = try await repo.imageData(for: "b")
        XCTAssertEqual(asset, Data([4,5,6]))
    }
    func testRemoteImportRejectsSmallerBudgetWithoutDeletingLocalHistory() async throws {
        let source = try SQLiteHistoryRepository(), target = try SQLiteHistoryRepository()
        let a = image("a", collection: .favorite), b = image("b")
        let assets = [ImageAsset(hash: "a", png: Data([1,2,3])), ImageAsset(hash: "b", png: Data([4,5,6]))]
        let merged = HistorySnapshot(recent: [b], favorites: [a])
        try await source.importSynced(merged, assets: assets, budgetBytes: 6)
        try await target.importSynced(.init(recent: [], favorites: [a]), assets: [assets[0]], budgetBytes: 3)
        let before = try await target.snapshot()
        do { try await target.importSynced(merged, assets: assets, budgetBytes: 3); XCTFail("Oversized remote collection must be rejected") } catch {}
        let after = try await target.snapshot(), incoming = try await target.imageData(for: "b")
        XCTAssertEqual(after, before); XCTAssertNil(incoming)
        try await target.importSynced(merged, assets: assets, budgetBytes: 6)
        let final = try await target.snapshot(); XCTAssertEqual(final.favorites.first?.id, a.id)
    }
    func testImageExportPreservesSinglePNGAndMixedCollectionAssets() throws {
        let a = image("a"), asset = ImageAsset(hash: "a", png: Data([1,2,3]))
        let single = try ClipExport.make([a], assets: [asset])
        XCTAssertEqual(single.filename, "Flycut.png"); XCTAssertEqual(single.data, asset.png)
        let text = Clip(id: UUID(), text: "text", pasteboardType: "text", sourceAppName: nil, sourceBundleURL: nil, capturedAt: nil, collection: .recent, order: 0)
        let mixed = try ClipExport.make([a, text], assets: [asset])
        XCTAssertEqual(mixed.filename, "Flycut.json")
        let restored = try JSONDecoder().decode(ClipExport.Collection.self, from: mixed.data)
        XCTAssertEqual(restored.clips, [a, text]); XCTAssertEqual(restored.imageAssets, [asset])
        XCTAssertThrowsError(try ClipExport.make([a], assets: []))
    }
    func testBudgetReductionArchivesImagesAndRollsBackOnExportFailure() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repo = try SQLiteHistoryRepository()
        _ = try await repo.applyImage(.init(hash: "a", png: Data([1,2,3])), clip: image("a"), budgetBytes: 6)
        _ = try await repo.applyImage(.init(hash: "b", png: Data([4,5,6])), clip: image("b"), budgetBytes: 6)
        _ = try await repo.trimImageBudget(to: 3, archive: .init(directory: directory))
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(files.first)), Data([1,2,3]))
        let blocked = directory.appendingPathComponent("blocked"); try Data().write(to: blocked)
        let before = try await repo.snapshot()
        do { _ = try await repo.trimImageBudget(to: 0, archive: .init(directory: blocked)); XCTFail("Export failure must abort budget eviction") } catch {}
        let after = try await repo.snapshot(), bytes = try await repo.imageData(for: "b")
        XCTAssertEqual(after, before); XCTAssertEqual(bytes, Data([4,5,6]))
    }

}
