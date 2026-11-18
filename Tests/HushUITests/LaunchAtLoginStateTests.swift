import ServiceManagement
import Testing
@testable import HushUI

@Suite struct LaunchAtLoginStateTests {
    @Test func enabledShowsOnWithoutHint() {
        let state = LaunchAtLoginState(status: .enabled)
        #expect(state.isOn && !state.showsApprovalHint && state.isEnabled)
    }

    @Test func requiresApprovalShowsOnWithHint() {
        let state = LaunchAtLoginState(status: .requiresApproval)
        #expect(state.isOn && state.showsApprovalHint && state.isEnabled)
    }

    @Test func notRegisteredShowsOffAndStaysUsable() {
        let state = LaunchAtLoginState(status: .notRegistered)
        #expect(!state.isOn && !state.showsApprovalHint && state.isEnabled)
    }

    @Test func notFoundDisablesTheToggle() {
        let state = LaunchAtLoginState(status: .notFound)
        #expect(!state.isOn && !state.showsApprovalHint && !state.isEnabled)
    }
}
