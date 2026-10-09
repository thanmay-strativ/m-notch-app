import AppKit

public enum MNotchApp {
    @MainActor private static var coordinator: AppCoordinator?

    @MainActor
    public static func run() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let coordinator = AppCoordinator()
        Self.coordinator = coordinator
        application.delegate = coordinator
        application.run()
    }
}
