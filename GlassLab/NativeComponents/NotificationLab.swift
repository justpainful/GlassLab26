import SwiftUI
import UserNotifications
import QuartzCore
import Observation

/// Real local notifications through UNUserNotificationCenter. The app can request authorization and
/// schedule a notification; whether and how a banner appears is decided by iOS (Focus, settings, summary).
@MainActor
@Observable
final class NotificationLabState {
    static let shared = NotificationLabState()

    struct LogEntry: Identifiable, Hashable { var id = UUID(); var text: String; var mediaTime: Double; var date: Date }

    var authorization: String = "Unknown"
    var log: [LogEntry] = []
    var delay: Double = 3

    func refresh() async {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        switch s.authorizationStatus {
        case .authorized: authorization = "Authorized"
        case .denied: authorization = "Denied (enable in Settings › Notifications › Glass Lab)"
        case .notDetermined: authorization = "Not requested"
        case .provisional: authorization = "Provisional (delivered quietly)"
        case .ephemeral: authorization = "Ephemeral"
        @unknown default: authorization = "Unknown"
        }
        if s.authorizationStatus == .authorized {
            authorization += s.alertSetting == .enabled ? " · alerts on" : " · alerts off"
        }
    }

    func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        await refresh()
    }

    func schedule() async {
        let content = UNMutableNotificationContent()
        content.title = "Glass Lab"
        content.body = "Local notification scheduled \(Format.number(delay, digits: 2)) s earlier."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, delay), repeats: false)
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        do {
            try await UNUserNotificationCenter.current().add(req)
            log.insert(LogEntry(text: "Scheduled (+\(Format.number(delay, digits: 2)) s)", mediaTime: CACurrentMediaTime(), date: Date()), at: 0)
        } catch {
            log.insert(LogEntry(text: "Scheduling failed: \(error.localizedDescription)", mediaTime: CACurrentMediaTime(), date: Date()), at: 0)
        }
    }

    func recordPresented(_ n: UNNotification) {
        log.insert(LogEntry(text: "willPresent callback (foreground) for \(n.request.identifier.prefix(8))", mediaTime: CACurrentMediaTime(), date: Date()), at: 0)
    }
}

struct NotificationLabPanel: View {
    var state: NotificationLabState

    var body: some View {
        @Bindable var state = state
        VStack(alignment: .leading, spacing: 8) {
            KeyValueRow(key: "Authorization", value: state.authorization, provenance: .apiExposed)
            HStack {
                Button("Request permission") { Task { await state.requestAuthorization() } }.buttonStyle(.glass)
                Button("Schedule") { Task { await state.schedule() } }.buttonStyle(.glassProminent)
            }
            HStack {
                Text("Delay \(Format.number(state.delay, digits: 2)) s").font(.caption.monospacedDigit())
                Slider(value: $state.delay, in: 1...30, step: 1)
            }
            Text("Banners are system UI. The app cannot force a banner to appear at a given moment or read Notification Center. Timestamps below are app-side events on the media clock.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(state.log.prefix(8)) { e in
                HStack {
                    Text(e.text).font(.caption)
                    Spacer()
                    Text(Format.number(e.mediaTime, digits: 7) + " s").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
        .task { await state.refresh() }
    }
}
