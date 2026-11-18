import AppKit

/// Decides what a click on the menu bar icon does. Pure, so the routing can be unit tested.
package enum StatusItemClickRouter {
    package enum Route: Equatable, Sendable {
        case showMenu, closePopover, openPopover, ignore
    }

    /// How long after the popover closes a left click on the icon is treated as the end of the
    /// click that closed it (the transient popover closes on mouse down), rather than a new click.
    package static let reopenGuard: TimeInterval = 1

    /// - Parameters:
    ///   - eventType: the event that sent the button's action (a mouse up).
    ///   - controlPressed: whether Control was held, which turns a left click into a menu click.
    ///   - popoverShown: whether the mixer popover is open.
    ///   - closedRecently: whether a press on the icon closed the popover within `reopenGuard`.
    package static func route(
        eventType: NSEvent.EventType?, controlPressed: Bool, popoverShown: Bool, closedRecently: Bool
    ) -> Route {
        if eventType == .rightMouseUp || (eventType == .leftMouseUp && controlPressed) { return .showMenu }
        if popoverShown { return .closePopover }
        return closedRecently ? .ignore : .openPopover
    }

    /// Whether a close at `closedAt` (system uptime, in seconds) is recent enough at `now` to
    /// swallow the next left click.
    package static func isRecent(closedAt: TimeInterval?, now: TimeInterval) -> Bool {
        guard let closedAt else { return false }
        return now - closedAt < reopenGuard
    }
}
