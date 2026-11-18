import AppKit
import HushCore
import HushUI
import Observation
import SwiftUI

/// Owns Hush's menu bar item. A left-click toggles the mixer popover; a right-click, two-finger
/// click or Control-click opens the quick menu.
final class StatusItemController: NSObject, NSPopoverDelegate, NSMenuDelegate {
    private let store: MixerStore
    private let updates: UpdateChecker
    private let settingsOpener = SettingsOpener()
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let menu = NSMenu()
    /// When a click on the icon closed the transient popover (on mouse down), the mouse up that
    /// follows must not reopen it.
    /// System uptime (seconds) at that close.
    private var closedByIconPress: TimeInterval?
    /// Watches clicks in other apps while the popover is open; see `startWatchingOutsideClicks`.
    private var outsideClickMonitor: Any?

    init(store: MixerStore, updates: UpdateChecker) {
        self.store = store
        self.updates = updates
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        let content = NSHostingController(rootView: MixerPopover(store: store, updates: updates))
        content.sizingOptions = .preferredContentSize
        popover.contentViewController = content
        popover.behavior = .transient
        popover.delegate = self

        menu.delegate = self

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(iconClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            // Always in a window, so SwiftUI runs the bridge and it can capture `openSettings`.
            let bridge = NSHostingView(rootView: SettingsOpenerBridge(opener: settingsOpener))
            bridge.frame = .zero
            bridge.setAccessibilityElement(false)
            button.addSubview(bridge)
        }
        observeIcon()
    }

    // MARK: Icon

    /// Updates the icon and its label now, and again whenever anything they read changes.
    private func observeIcon() {
        withObservationTracking {
            updateIcon()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeIcon() }
        }
    }

    private func updateIcon() {
        let badged = updates.hasPendingUpdate
        let image = MenuBarIcon.image(
            style: store.preferences.appearance.menuBarIcon,
            attenuated: store.isAnyAppAttenuated,
            badged: badged)
        guard let button = statusItem.button else { return }
        // MenuBarIcon caches its images, so an unchanged icon is the same object.
        if button.image !== image { button.image = image }
        let label = String(localized: L10n.menuBarLabel(updateAvailable: badged))
        if button.accessibilityLabel() != label { button.setAccessibilityLabel(label) }
    }

    // MARK: Clicks

    @objc private func iconClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let route = StatusItemClickRouter.route(
            eventType: event?.type,
            controlPressed: event?.modifierFlags.contains(.control) == true,
            popoverShown: popover.isShown,
            closedRecently: StatusItemClickRouter.isRecent(
                closedAt: closedByIconPress, now: ProcessInfo.processInfo.systemUptime))
        closedByIconPress = nil
        switch route {
        case .showMenu: showMenu()
        case .closePopover: popover.performClose(sender)
        case .openPopover: showPopover()
        case .ignore: break
        }
    }

    /// Opens or closes the mixer, as a left-click on the icon does; the global shortcut calls
    /// this. The popover hangs off the icon, so it doesn't open while the icon is turned off in
    /// System Settings → Menu Bar. While the menu bar itself is hidden (in a full-screen app, or
    /// set to hide automatically), it still opens, anchored where the icon sits at the top of
    /// the screen.
    func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if isIconOnScreen {
            showPopover()
        }
    }

    private var isIconOnScreen: Bool {
        // Not occlusionState: a hidden menu bar reports the icon as occluded, and the shortcut
        // must still work then.
        guard statusItem.isVisible, let window = statusItem.button?.window, window.isVisible else { return false }
        return NSScreen.screens.contains { $0.frame.intersects(window.frame) }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func showMenu() {
        if popover.isShown { popover.performClose(nil) }
        // Setting the menu just for this click gives the standard status-item menu (position,
        // highlighted icon) while left-clicks keep reaching `iconClicked`.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        QuickMenu.populate(menu, model: QuickMenuModel(store: store, updates: updates), actions: menuActions)
    }

    private var menuActions: QuickMenuActions {
        QuickMenuActions(
            selectOutput: { [store] in store.selectOutput($0) },
            openSoundSettings: { NSWorkspace.shared.open(QuickMenu.soundSettingsURL) },
            muteAllPlaying: { [store] in store.muteAllPlaying() },
            unmuteAll: { [store] in store.unmuteAll() },
            openSettings: { [settingsOpener] in settingsOpener.open() },
            checkForUpdates: { [updates] in Task { await updates.checkNow() } },
            quit: { NSApp.terminate(nil) })
    }

    // MARK: NSPopoverDelegate

    // MixerPopover also reports its visibility through window occlusion; both paths call the
    // store's idempotent lifecycle methods, so meters start on open and stop on close either way.

    func popoverDidShow(_ notification: Notification) {
        store.popoverDidAppear()
        updates.refresh()
        startWatchingOutsideClicks()
    }

    /// A transient popover only closes for clicks Hush receives. A click in another app, on the
    /// desktop or in another app's menu bar item goes to that app, so watch for those while the
    /// popover is open and close it. Mouse-only global monitors need no Accessibility or Input
    /// Monitoring permission, and they never see clicks in Hush's own windows or icon.
    private func startWatchingOutsideClicks() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.popover.isShown else { return }
                self.popover.performClose(nil)
            }
        }
    }

    private func stopWatchingOutsideClicks() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
    }

    func popoverWillClose(_ notification: Notification) {
        if let event = NSApp.currentEvent, event.type == .leftMouseDown || event.type == .rightMouseDown,
            let button = statusItem.button, event.window === button.window
        {
            closedByIconPress = ProcessInfo.processInfo.systemUptime
        }
    }

    func popoverDidClose(_ notification: Notification) {
        stopWatchingOutsideClicks()
        store.popoverDidDisappear()
    }
}
