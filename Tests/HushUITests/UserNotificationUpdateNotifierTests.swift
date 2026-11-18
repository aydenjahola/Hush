import Foundation
import HushCore
import Testing
import UserNotifications
@testable import HushUI

/// Only the pure parts: `UNUserNotificationCenter.current()` needs an app bundle, which tests don't have.
@MainActor
@Suite struct UserNotificationUpdateNotifierTests {
    private let update = AvailableUpdate(
        version: SemanticVersion("0.2.0")!,
        downloadURL: dmgURL("0.2.0"),
        releasePageURL: URL(string: "https://github.com/aydenjahola/Hush/releases/tag/v0.2.0")!)

    @Test func contentNamesTheVersionAndCarriesTheActionData() {
        let content = UserNotificationUpdateNotifier.content(for: update)
        #expect(content.title == "Hush 0.2.0 is available")
        #expect(content.categoryIdentifier == UserNotificationUpdateNotifier.categoryIdentifier)
        #expect(content.userInfo["version"] as? String == "0.2.0")
        #expect(content.userInfo["url"] as? String == dmgURL("0.2.0").absoluteString)
    }

    @Test func categoryOffersTheThreeActions() {
        let category = UserNotificationUpdateNotifier.category
        #expect(category.identifier == UserNotificationUpdateNotifier.categoryIdentifier)
        #expect(category.actions.map(\.title) == ["Download", "Later", "Skip This Version"])
        #expect(category.actions.map(\.identifier).compactMap(UserNotificationUpdateNotifier.action(for:)) ==
                [.download, .later, .skip])
    }

    @Test func clickingTheNotificationDownloads() {
        #expect(UserNotificationUpdateNotifier.action(for: UNNotificationDefaultActionIdentifier) == .download)
    }

    @Test func unknownAndDismissActionsMapToNothing() {
        #expect(UserNotificationUpdateNotifier.action(for: UNNotificationDismissActionIdentifier) == nil)
        #expect(UserNotificationUpdateNotifier.action(for: "something.else") == nil)
    }
}
