import Foundation
import HushAudio
import os

extension MixerStore {
    /// Makes `device` the Mac's default output. Every app follows; Hush's adjusted apps move over
    /// through the usual output-change path once the source reports the new default, so the
    /// checkmark only moves when the system confirms. Choosing the current device does nothing.
    package func selectOutput(_ device: OutputDevice) {
        guard device.id != outputDevice?.id else { return }
        do {
            try outputSource.setDefaultOutput(device.id)
            clearOutputSelectionError()
        } catch {
            logger.error("Couldn't switch output to \(device.name): \(String(describing: error))")
            showOutputSelectionError(String(localized: L10n.outputSwitchFailed(device.name)))
        }
    }

    func outputDevicesDidChange(_ devices: [OutputDevice]) {
        guard devices != outputDevices else { return }
        outputDevices = devices
    }

    private func showOutputSelectionError(_ message: String) {
        outputErrorTask?.cancel()
        outputSelectionError = message
        let duration = outputErrorDuration
        outputErrorTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.outputSelectionError = nil
        }
    }

    private func clearOutputSelectionError() {
        outputErrorTask?.cancel()
        outputErrorTask = nil
        outputSelectionError = nil
    }
}
