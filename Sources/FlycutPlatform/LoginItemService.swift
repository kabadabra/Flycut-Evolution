import ServiceManagement

public enum LoginItemStatus: Equatable, Sendable {
    case registered, notRegistered, requiresApproval, notFound, error(String)
}

@MainActor public struct LoginItemClient {
    public var status: () -> LoginItemStatus
    public var register: () throws -> Void
    public var unregister: () async throws -> Void
    public init(status: @escaping () -> LoginItemStatus, register: @escaping () throws -> Void,
                unregister: @escaping () async throws -> Void) {
        self.status = status; self.register = register; self.unregister = unregister
    }
    public static var system: LoginItemClient {
        LoginItemClient(status: {
            switch SMAppService.mainApp.status {
            case .enabled: .registered
            case .notRegistered: .notRegistered
            case .requiresApproval: .requiresApproval
            case .notFound: .notFound
            @unknown default: .error("Unknown login item status")
            }
        }, register: { try SMAppService.mainApp.register() },
        unregister: { try await SMAppService.mainApp.unregister() })
    }
}

@MainActor public final class LoginItemService {
    private let client: LoginItemClient
    private var lastError: String?
    public init(client: LoginItemClient = .system) { self.client = client }
    public var status: LoginItemStatus { lastError.map(LoginItemStatus.error) ?? client.status() }
    @discardableResult public func setEnabled(_ enabled: Bool) async -> LoginItemStatus {
        do {
            if enabled { try client.register() } else { try await client.unregister() }
            lastError = nil
        } catch { lastError = error.localizedDescription }
        return status
    }
    public func refresh() { lastError = nil }
    public static func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}
