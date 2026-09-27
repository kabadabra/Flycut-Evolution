import AppKit

@main enum FlycutApp {
    @MainActor static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let coordinator = AppCoordinator()
        application.delegate = coordinator
        withExtendedLifetime(coordinator) { application.run() }
    }
}
