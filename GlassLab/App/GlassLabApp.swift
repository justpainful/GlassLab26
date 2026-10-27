import SwiftUI
import UserNotifications

@main
struct GlassLabApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            AppShell()
                .environment(model)
                .onChange(of: phase) { _, p in
                    if p == .background {
                        // Stop interactive work cleanly; partial sessions are already saved atomically.
                        model.engine.cancel()
                        Task { await model.capture.replay.stop() }
                    }
                    if p == .active { model.environment.refresh() }
                }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// Lets local notifications appear as banners while Glass Lab is in the foreground.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        await MainActor.run { NotificationLabState.shared.recordPresented(notification) }
        return [.banner, .list, .sound]
    }
}
