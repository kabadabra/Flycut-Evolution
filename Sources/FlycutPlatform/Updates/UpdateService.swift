import Foundation
import Combine
import Sparkle

@MainActor public struct UpdateClient {
    public var start: () throws -> Void
    public var setAutomaticChecks: (Bool) -> Void
    public var check: () -> Void
    public var canCheck: () -> Bool
    public init(start: @escaping () throws -> Void, setAutomaticChecks: @escaping (Bool) -> Void, check: @escaping () -> Void, canCheck: @escaping () -> Bool) {
        self.start = start; self.setAutomaticChecks = setAutomaticChecks; self.check = check; self.canCheck = canCheck
    }
}
@MainActor public final class UpdateService: ObservableObject {
    @Published public private(set) var message: String?
    private let client: UpdateClient
    private let configured: Bool
    private var started = false
    private var driver: SparkleUpdateDriver?
    public init(client: UpdateClient, configured: Bool) { self.client = client; self.configured = configured }
    public convenience init(bundle: Bundle = .main) {
        let driver = SparkleUpdateDriver()
        let key = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        let url = (bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String).flatMap(URL.init(string:))
        self.init(client: driver.client, configured: Data(base64Encoded: key)?.count == 32 && url?.scheme == "https")
        self.driver = driver
        driver.onMessage = { [weak self] in self?.message = $0 }
    }
    public func configure(automaticChecks: Bool) { client.setAutomaticChecks(configured && automaticChecks) }
    public func start() {
        guard configured, !started else { return }
        do { try client.start(); started = true }
        catch { reportFailure("Updates could not start. Check the update configuration.") }
    }
    public func checkForUpdates() {
        guard configured else { reportFailure("Updates are not configured in this build."); return }
        start()
        guard started, client.canCheck() else { reportFailure("An update check is already running or unavailable."); return }
        message = nil; client.check()
    }
    public func reportFailure(_ message: String) { self.message = message }
}
@MainActor final class SparkleUpdateDriver: NSObject, SPUUpdaterDelegate {
    var onMessage: (String?) -> Void = { _ in }
    private lazy var controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
    var client: UpdateClient {
        UpdateClient(start: { [self] in try controller.updater.start() }, setAutomaticChecks: { [self] enabled in
            controller.updater.automaticallyChecksForUpdates = enabled
            controller.updater.automaticallyDownloadsUpdates = false
        }, check: { [self] in controller.checkForUpdates(nil) }, canCheck: { [self] in controller.updater.canCheckForUpdates })
    }
    func updaterShouldPromptForPermissionToCheck(forUpdates updater: SPUUpdater) -> Bool { false }
    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        onMessage("Update check unavailable: \(error.localizedDescription)")
    }
}
