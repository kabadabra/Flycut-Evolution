import Foundation
import Combine
import FlycutCore
import FlycutPlatform

@MainActor struct SetupPermissionClient {
    var status: () -> Bool
    var request: () -> Bool
    var open: () -> Void
    static var system: Self { .init(status: { AccessibilityService().isTrusted }, request: { AccessibilityService().requestPermission() }, open: { AccessibilityService().openSettings() }) }
}
@MainActor final class SetupModel: ObservableObject {
    @Published var value: FlycutSettings
    @Published private(set) var state = SetupState()
    @Published private(set) var trusted = false
    @Published private(set) var pasteSucceeded: Bool?
    @Published private(set) var sampleCopied = false
    private let permission: SetupPermissionClient
    private let copyAction: () -> Void
    private let save: (FlycutSettings, SetupState) -> Void
    init(settings: FlycutSettings, permission: SetupPermissionClient = .system, copySample: @escaping () -> Void = {}, save: @escaping (FlycutSettings, SetupState) -> Void) {
        value = settings; self.permission = permission; self.copyAction = copySample; self.save = save
        refreshPermission()
    }
    func next() { state.step = SetupStep(rawValue: min(4, state.step.rawValue + 1))!; save(value, state) }
    func back() { state.step = SetupStep(rawValue: max(0, state.step.rawValue - 1))! }
    func dismiss() { if !state.completed { state.dismissed = true }; save(value, state) }
    func finish() { state.completed = true; save(value, state) }
    func refreshPermission() { trusted = permission.status() }
    func requestPermission() { trusted = permission.request() }
    func openPermissionSettings() { permission.open() }
    func copySample() { copyAction(); sampleCopied = true }
    func confirmPaste(_ succeeded: Bool) { pasteSucceeded = succeeded }
}
