import Observation
import ServiceManagement

/// How the Launch at Login row should look for a given `SMAppService` status.
///
/// Kept free of `SMAppService` calls so the mapping can be unit tested.
package struct LaunchAtLoginState: Equatable {
    /// Whether the toggle shows as on. `.requiresApproval` counts as on: Hush is registered and only
    /// waiting for the user to allow it in System Settings.
    package let isOn: Bool
    /// Whether to show the hint and button that lead to System Settings → General → Login Items.
    package let showsApprovalHint: Bool
    /// False when registering can't work at all, such as a bare binary with no app bundle.
    package let isEnabled: Bool

    package init(status: SMAppService.Status) {
        switch status {
        case .enabled:
            (isOn, showsApprovalHint, isEnabled) = (true, false, true)
        case .requiresApproval:
            (isOn, showsApprovalHint, isEnabled) = (true, true, true)
        case .notFound:
            (isOn, showsApprovalHint, isEnabled) = (false, false, false)
        case .notRegistered:
            (isOn, showsApprovalHint, isEnabled) = (false, false, true)
        @unknown default:
            (isOn, showsApprovalHint, isEnabled) = (false, false, true)
        }
    }
}

/// Holds the Launch at Login state for the Settings window. It reads the real status when created,
/// so the toggle is right on the first frame, and again on `refresh()`.
@MainActor
@Observable
package final class LaunchAtLoginModel {
    package private(set) var state: LaunchAtLoginState
    package private(set) var errorMessage: String?

    @ObservationIgnored private let service: SMAppService

    package init(service: SMAppService = .mainApp) {
        self.service = service
        state = LaunchAtLoginState(status: service.status)
    }

    /// Re-reads the status; the user can change it in System Settings while Hush is running.
    package func refresh() {
        state = LaunchAtLoginState(status: service.status)
    }

    package func setEnabled(_ enabled: Bool) {
        guard enabled != state.isOn else { return }
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }

    package func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
