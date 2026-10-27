#if os(macOS)
import AppKit
import UserNotifications

/// "Converted to MP4" notifications for long jobs that finish while you're in another
/// app, with a "Show in Finder" button.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    private let category = "conversionDone"
    private let revealAction = "reveal"

    func setUp() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let reveal = UNNotificationAction(identifier: revealAction, title: "Show in Finder", options: [.foreground])
        center.setNotificationCategories([UNNotificationCategory(identifier: category, actions: [reveal], intentIdentifiers: [])])
    }

    func post(title: String, body: String, files: [URL]) {
        let center = UNUserNotificationCenter.current()
        let category = category
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.categoryIdentifier = category
            content.userInfo = ["paths": files.map(\.path)]
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let paths = response.notification.request.content.userInfo["paths"] as? [String] ?? []
        let urls = paths.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
        if !urls.isEmpty {
            DispatchQueue.main.async { NSWorkspace.shared.activateFileViewerSelecting(urls) }
        }
        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
#endif
