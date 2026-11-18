import AppKit
import Testing

@testable import HushUI

@Suite struct StatusItemClickRouterTests {
    private func route(
        _ type: NSEvent.EventType?, control: Bool = false, shown: Bool = false, closedRecently: Bool = false
    ) -> StatusItemClickRouter.Route {
        StatusItemClickRouter.route(
            eventType: type, controlPressed: control, popoverShown: shown, closedRecently: closedRecently)
    }

    @Test func rightMouseUpShowsTheMenu() {
        #expect(route(.rightMouseUp) == .showMenu)
        #expect(route(.rightMouseUp, shown: true, closedRecently: true) == .showMenu)
    }

    @Test func controlLeftMouseUpShowsTheMenu() {
        #expect(route(.leftMouseUp, control: true) == .showMenu)
        #expect(route(.leftMouseUp, control: true, shown: true) == .showMenu)
    }

    @Test func leftMouseUpWhileShownClosesThePopover() {
        #expect(route(.leftMouseUp, shown: true) == .closePopover)
    }

    @Test func leftMouseUpJustAfterACloseIsIgnored() {
        #expect(route(.leftMouseUp, closedRecently: true) == .ignore)
    }

    @Test func plainLeftMouseUpOpensThePopover() {
        #expect(route(.leftMouseUp) == .openPopover)
        #expect(route(nil) == .openPopover, "no current event: treat as a plain click")
    }

    @Test func aCloseCountsAsRecentForOneSecond() {
        #expect(!StatusItemClickRouter.isRecent(closedAt: nil, now: 100))
        #expect(StatusItemClickRouter.isRecent(closedAt: 100, now: 100.5))
        #expect(!StatusItemClickRouter.isRecent(closedAt: 100, now: 101))
    }
}
