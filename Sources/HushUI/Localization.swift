import Foundation

extension Bundle {
    /// HushUI's resource bundle (the en.lproj strings). In the packaged app SwiftPM's resource bundle
    /// is copied into `Contents/Resources`; its generated accessor only looks next to the app
    /// bundle, so look there first and fall back to `Bundle.module` (tests, `swift run`).
    nonisolated static let hushUI: Bundle = {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("Hush_HushUI.bundle"),
            let bundle = Bundle(url: url)
        {
            return bundle
        }
        return Bundle.module
    }()
}

/// Every user-facing string in Hush, as a `LocalizedStringResource` backed by
/// `Resources/en.lproj/Localizable.strings` (plurals in `Localizable.stringsdict`). SwiftUI views
/// take these directly; use `String(localized:)` where a plain string is required (notifications,
/// AppKit). Strings with arguments are whole sentences with format placeholders ("Mute %@"), so
/// translators can reorder them.
///
/// Classic .strings/.stringsdict rather than a String Catalog: SwiftPM's native build system
/// (the default up to Swift 6.3, i.e. Xcode 26) copies an .xcstrings file into the bundle verbatim
/// instead of compiling it, so every lookup fell back to the raw key. Only the Swift Build backend
/// (default from Swift 6.4, Xcode 27) compiles catalogs. These files work on both.
package enum L10n {
    private static func resource(_ key: String.LocalizationValue) -> LocalizedStringResource {
        LocalizedStringResource(key, bundle: .atURL(Bundle.hushUI.bundleURL))
    }

    // MARK: Brand and menu bar

    package static let appName = resource("Hush")
    package static func menuBarLabel(updateAvailable: Bool) -> LocalizedStringResource {
        updateAvailable ? resource("Hush, update available") : resource("Hush")
    }

    // MARK: Popover

    package static let noOutput = resource("No Output")
    package static func outputDevice(named name: String?) -> LocalizedStringResource {
        if let name { resource("Output: \(name)") } else { resource("Output: none") }
    }
    package static let soundSettings = resource("Sound Settings…")
    package static func outputSwitchFailed(_ device: String) -> LocalizedStringResource {
        resource("Couldn't switch to \(device)")
    }
    package static let nothingIsPlaying = resource("Nothing is playing")
    package static let settings = resource("Settings")
    package static let quit = resource("Quit Hush")
    package static func playingSummary(count: Int) -> LocalizedStringResource {
        count == 0 ? resource("No apps playing") : resource("\(count) apps playing")
    }

    // MARK: Strips

    package static let muted = resource("Muted")
    package static func percent(_ value: Int) -> LocalizedStringResource { resource("\(value)%") }
    package static func mute(_ app: String) -> LocalizedStringResource { resource("Mute \(app)") }
    package static func unmute(_ app: String) -> LocalizedStringResource { resource("Unmute \(app)") }
    package static func volumeLabel(_ app: String) -> LocalizedStringResource { resource("\(app) volume") }
    package static func volumeValue(_ percent: Int) -> LocalizedStringResource { resource("\(percent) percent") }
    package static func warning(_ detail: String) -> LocalizedStringResource { resource("Warning: \(detail)") }
    package static let clickToMute = resource("Click to mute")
    package static let clickToUnmute = resource("Click to unmute")

    // MARK: Banners

    package static let permissionNeeded = resource("Hush needs Audio Recording access to control app volumes.")
    package static let openSystemSettings = resource("Open System Settings")
    package static func updateAvailable(_ version: String) -> LocalizedStringResource {
        resource("Hush \(version) is available")
    }
    package static let download = resource("Download")
    package static let later = resource("Later")
    package static let skipThisVersion = resource("Skip This Version")
    package static let downloadHelp = resource("Open the download in your browser")
    package static let laterHelp = resource("Remind me tomorrow")

    // MARK: Settings

    package static let general = resource("General")
    package static let launchAtLogin = resource("Launch at login")
    package static let maximumBoost = resource("Maximum boost")
    package static let showInactiveApps = resource("Show apps that aren't playing")
    package static let levels = resource("Levels")
    package static let resetAllLevelsButton = resource("Reset All Levels…")
    package static let resetAllLevelsTitle = resource("Reset all app levels?")
    package static let resetAllLevels = resource("Reset All Levels")
    package static let resetAllLevelsMessage = resource("Every app goes back to 100% and unmuted.")
    package static let updates = resource("Updates")
    package static let checkAutomatically = resource("Check for updates automatically")
    package static let checkNow = resource("Check Now")
    package static let about = resource("About")
    package static let version = resource("Version")
    package static func localVersion(_ version: String, commit: String?) -> LocalizedStringResource {
        if let commit { resource("\(version) (local build, \(commit))") } else { resource("\(version) (local build)") }
    }
    package static let devBadge = resource("DEV")
    package static let localBuild = resource("Local build")
    package static func localBuildHelp(_ commit: String) -> LocalizedStringResource {
        resource("Local build from commit \(commit), not a downloaded release")
    }
    package static let localBuildHelpNoCommit = resource("Local build, not a downloaded release")
    package static let sourceCode = resource("Source code on GitHub")
    package static let licence = resource(
        "Hush is free software, released under the GNU General Public License v3.0. It comes with ABSOLUTELY NO WARRANTY."
    )
    package static func lastChecked(_ relativeDate: String) -> LocalizedStringResource {
        resource("Last checked \(relativeDate)")
    }
    package static let checking = resource("Checking…")
    package static let upToDate = resource("Hush is up to date")
    package static let checkFailed = resource("Couldn't check for updates")

    // MARK: Appearance

    package static let appearance = resource("Appearance")
    package static let layout = resource("Layout")
    package static let channelStrips = resource("Channel strips")
    package static let classicRows = resource("Classic rows")
    package static let tiles = resource("Tiles")
    package static let size = resource("Size")
    package static let comfortable = resource("Comfortable")
    package static let compact = resource("Compact")
    package static let showLevelMeters = resource("Show level meters")
    package static let recordingIndicatorNote = resource(
        "The purple dot in the menu bar is macOS's audio-recording indicator. It appears while Hush is adjusting an app's volume and, with meters on, while the mixer is open."
    )
    package static let showPercentages = resource("Show percentages")
    package static let sortApps = resource("Sort apps")
    package static let sortActivity = resource("Playing & recently adjusted first")
    package static let sortAlphabetical = resource("Alphabetical")
    package static let accentColour = resource("Accent colour")
    package static let amber = resource("Amber")
    package static let systemAccent = resource("System accent")
    package static let menuBarIcon = resource("Menu bar icon")
    package static let speaker = resource("Speaker")
    package static let faderGlyph = resource("Fader glyph")
    package static let previewChannelStrips = resource("Preview of the channel strips layout")
    package static let previewClassicRows = resource("Preview of the classic rows layout")
    package static let previewTiles = resource("Preview of the tiles layout")

    // MARK: Engine failures (strip warning tooltips)

    package static let controlFailed = resource("Hush couldn't control this app's audio, so it's playing normally.")
    package static let meterFailed = resource("Hush couldn't read this app's level.")
    package static func failureDetail(_ summary: String, _ error: String) -> LocalizedStringResource {
        resource("\(summary) (\(error))")
    }

    // MARK: Notifications

    package static let notificationBody = resource("Download it from GitHub when you're ready.")

    /// Every resource, with sample arguments for the parameterised ones; the localisation tests
    /// check that the catalog has a key for each.
    package static var all: [LocalizedStringResource] {
        [
            appName, menuBarLabel(updateAvailable: true), noOutput, outputDevice(named: "x"), outputDevice(named: nil),
            soundSettings, outputSwitchFailed("x"), nothingIsPlaying, settings, quit, playingSummary(count: 0),
            playingSummary(count: 2),
            muted, percent(50), mute("x"), unmute("x"), volumeLabel("x"), volumeValue(50), warning("x"),
            clickToMute, clickToUnmute, permissionNeeded, openSystemSettings, updateAvailable("x"), download, later,
            skipThisVersion, downloadHelp, laterHelp, general, launchAtLogin, maximumBoost, showInactiveApps, levels,
            resetAllLevelsButton, resetAllLevelsTitle, resetAllLevels, resetAllLevelsMessage, updates,
            checkAutomatically, checkNow, about, version, localVersion("x", commit: "y"),
            localVersion("x", commit: nil),
            devBadge, localBuild, localBuildHelp("x"), localBuildHelpNoCommit, sourceCode, licence, lastChecked("x"),
            checking, upToDate,
            checkFailed, appearance, layout, channelStrips, classicRows, tiles, size, comfortable, compact,
            showLevelMeters, recordingIndicatorNote, showPercentages, sortApps, sortActivity, sortAlphabetical,
            accentColour, amber, systemAccent, menuBarIcon, speaker, faderGlyph, previewChannelStrips,
            previewClassicRows, previewTiles, controlFailed, meterFailed, failureDetail("x", "y"), notificationBody,
        ]
    }
}
