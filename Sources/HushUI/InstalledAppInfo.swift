import AppKit

/// Name and icon of an installed app, used for strips of saved apps that aren't running.
package struct InstalledAppInfo {
    package var displayName: String
    package var icon: NSImage?

    package init(displayName: String, icon: NSImage?) {
        self.displayName = displayName
        self.icon = icon
    }

    /// Looks the app up by bundle ID through Launch Services. Returns nil when it isn't installed
    /// (or the ID is an executable name rather than a bundle ID).
    @MainActor
    package static func lookUp(bundleID: String) -> InstalledAppInfo? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let bundle = Bundle(url: url)
        let name =
            bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        return InstalledAppInfo(displayName: name, icon: NSWorkspace.shared.icon(forFile: url.path))
    }
}
