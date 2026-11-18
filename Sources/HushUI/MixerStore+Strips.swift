import HushAudio
import HushCore

extension MixerStore {
    /// Rebuilds `strips` and the frozen order through `StripListBuilder`.
    func rebuildStrips() {
        let builder = StripListBuilder(
            apps: apps,
            settings: settings,
            preferences: preferences,
            engineErrors: engineErrors,
            isPopoverVisible: isPopoverVisible,
            previousOrder: order)
        let result = builder.build(installedApp: cachedInstalledApp)
        order = result.order
        strips = result.strips
        meterBank.retain(only: Set(order))
    }

    private func cachedInstalledApp(_ id: String) -> InstalledAppInfo? {
        if let cached = installedAppCache[id] { return cached }
        let info = installedApp(id)
        installedAppCache[id] = info
        return info
    }
}
