import Foundation
import HushCore
import UserNotifications

/// Posts "Hush X.Y.Z is available" through `UNUserNotificationCenter`, with Download, Later and
/// Skip This Version actions. Create it at launch, so the delegate is in place for a response
/// that relaunches Hush; creating it doesn't ask for authorization.
@MainActor
public final class UserNotificationUpdateNotifier: NSObject, UpdateNotifying, UNUserNotificationCenterDelegate {
    static let categoryIdentifier = "\(HushIdentity.bundleID).update"
    private static let actionPrefix = "\(HushIdentity.bundleID).update."

    static var category: UNNotificationCategory {
        let actions = [
            (UpdateAction.download, "Download"),
            (UpdateAction.later, "Later"),
            (UpdateAction.skip, "Skip This Version"),
        ].map { action, title in
            UNNotificationAction(identifier: actionPrefix + action.rawValue, title: title, options: [])
        }
        return UNNotificationCategory(identifier: categoryIdentifier, actions: actions, intentIdentifiers: [])
    }

    public var onAction: (@MainActor (UpdateAction, String, URL?) -> Void)?

    private let center: UNUserNotificationCenter

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        super.init()
        center.delegate = self
        center.setNotificationCategories([Self.category])
    }

    public func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    public func post(_ update: AvailableUpdate) async {
        let request = UNNotificationRequest(
            identifier: "\(Self.categoryIdentifier).\(update.version)",
            content: Self.content(for: update),
            trigger: nil)
        try? await center.add(request)
    }

    /// Update notifications are the only ones Hush posts, so this clears them all.
    public func removeDelivered() {
        center.removeAllDeliveredNotifications()
    }

    static func content(for update: AvailableUpdate) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Hush \(update.version) is available"
        content.body = "Download it from GitHub when you're ready."
        content.categoryIdentifier = categoryIdentifier
        content.userInfo = ["version": update.version.description, "url": update.downloadURL.absoluteString]
        return content
    }

    /// Clicking the notification itself counts as Download.
    static func action(for identifier: String) -> UpdateAction? {
        if identifier == UNNotificationDefaultActionIdentifier { return .download }
        guard identifier.hasPrefix(actionPrefix) else { return nil }
        return UpdateAction(rawValue: String(identifier.dropFirst(actionPrefix.count)))
    }

    // MARK: UNUserNotificationCenterDelegate

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let content = response.notification.request.content
        guard content.categoryIdentifier == Self.categoryIdentifier,
              let action = Self.action(for: response.actionIdentifier),
              let version = content.userInfo["version"] as? String
        else { return }
        let url = (content.userInfo["url"] as? String).flatMap(URL.init(string:))
        onAction?(action, version, url)
    }

    /// Hush is a menu bar app and often "active" while its popover is open; show the banner anyway.
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}
