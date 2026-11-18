---
title: Settings
description: Launch at login, maximum boost, showing idle apps, the keyboard shortcut, the mixer's layout and appearance, hidden apps, presets, resetting levels, update checks, and where Hush keeps its settings.
---

To open Settings, click the gear button in the bottom-right corner of the mixer. The Settings window comes to the front even if another app is active.

## General

### Launch at login

Turn this on to start Hush automatically when you log in. Hush registers itself as a login item, and it appears in **System Settings → General → Login Items**.

The switch reflects what macOS reports, and it updates when you come back to Hush after changing the setting in System Settings.

If macOS wants your approval, the switch stays on and a hint appears under it: "Allow Hush in System Settings → General → Login Items." Click **Open Login Items** to jump to that pane and turn Hush on there.

If Hush isn't running as an installed app (for example a bare binary), the switch is dimmed because macOS can't register it.

If macOS refuses, the reason appears in small text under the switch and the switch turns back off. Moving Hush into your Applications folder first usually helps. You can also check whether Hush is turned off in **Login Items**.

### Maximum boost

Choose how far the faders can go above an app's own volume: **100%**, **150%** or **200%**. The default is 200%.

- **100%** turns boosting off. Faders only turn apps down.
- Lowering the maximum also lowers any app saved above it. For example, an app at 180% drops to 150% when you choose 150%. Raising the maximum again doesn't bring back the old level.

### Show apps that aren't playing

Off by default. When it's on, the mixer also shows:

- running apps that have a Dock icon but aren't playing anything, so you can set their level before they make a sound;
- apps you've saved a level for, even if they're not running.

Background processes and system services aren't listed unless they're playing, or you've saved a level for them.

Strips for apps that aren't playing are dimmed. An app that isn't running is shown with its name and icon, but its controls are disabled until it runs.

### Keyboard shortcut

A key combination that opens the mixer from any app, as if you'd clicked the Hush icon. Press it again to close the mixer. There's none by default. It works in full-screen apps too, and does nothing only when the Hush icon is turned off in **System Settings → Menu Bar**.

- To set one, click **Record Shortcut**, then press the combination, such as **⌥⌘H**. It's saved straight away and shown with the standard key symbols.
- The combination must include **⌥** or **⌃** (with or without **⌘** and **⇧**). **⌘** or **⌘⇧** on their own aren't enough, because apps use those for their own commands, such as **⌘C** or **⌘⇧4**. For these, Hush shows **"That's a standard app shortcut. Add ⌥ or ⌃."** **⌥⌘Esc** (Force Quit) is left to macOS: Hush shows **"macOS uses that shortcut. Try another."** A function key (**F1** to **F20**) can be used on its own or with any modifiers.
- Press **Esc** while recording to cancel and keep the current shortcut.
- To remove the shortcut, click the **ⓧ** button next to it.

If Hush can tell the combination is already taken, it shows **"That shortcut is in use. Try another."** and keeps your previous shortcut. It can tell for macOS's own shortcuts (those turned on in **System Settings → Keyboard → Keyboard Shortcuts**) and for combinations another app has claimed exclusively. Most apps don't claim their shortcuts that way, so Hush can't always see them. If your shortcut also does something in another app, choose a different one. The same message appears if a saved shortcut has been taken since Hush last started.

The shortcut needs no extra permission. See [Keyboard and accessibility](/Hush/using/keyboard-accessibility/#opening-the-mixer-with-a-shortcut).

## Appearance

A small preview at the top of this section shows the chosen layout with sample apps, and changes as you change the options below. Changes apply to the mixer straight away.

### Layout

How the mixer lays out the apps. All three show the same information and work the same way: see [The mixer](/Hush/using/mixer/#layouts).

- **Channel strips** (the default): a vertical fader per app, side by side.
- **Classic rows:** one dense row per app with a horizontal slider, like Control Center.
- **Tiles:** one row per app that is itself the slider.

### Size

**Comfortable** (the default) or **Compact**, which uses tighter spacing and smaller icons so more apps fit.

### Show level meters

On by default. Turn it off to hide the level meters. With meters off, Hush doesn't tap apps you haven't adjusted when you open the mixer, because the meters were the only reason to. Apps you've muted, lowered or boosted are still processed while they play.

Under the switch, Hush explains the purple dot in the menu bar: it's macOS's audio-recording indicator, which appears while Hush is adjusting an app's volume and, with meters on, while the mixer is open. See [Troubleshooting](/Hush/help/troubleshooting/#why-is-there-a-purple-dot-in-my-menu-bar).

### Show percentages

On by default. Turn it off to hide each app's percentage. A muted app still reads **Muted**, and VoiceOver still reads the level.

### Sort apps

- **Playing & recently adjusted first** (the default): playing apps, then the apps you adjusted most recently, then the rest by name. The order stays put while the mixer is open.
- **Alphabetical:** by name, whether or not the app is playing.

### Accent colour

The colour of the normal part of each volume control: fader and slider fills up to 100%, and the fill of a tile.

- **Amber** (the default): the normal fill stays white (black in light mode).
- **System accent:** your accent colour from **System Settings → Appearance**. In light mode Hush darkens it, and darkens it further with **Increase contrast**, so pale accents such as yellow stay readable.

Boost (above 100%) is always amber, in every layout and with either choice: the boost part of faders and sliders, the boost fill on tiles, and boosted percentages. That keeps it from clashing with the red used for Muted when your accent is red.

### Menu bar icon

- **Speaker** (the default): a speaker that shows fewer sound waves while any app is muted or lowered.
- **Fader glyph:** three small faders, like the app icon. Their knobs drop lower while any app is muted or lowered.

Both follow the menu bar's light, dark or tinted appearance and show the update dot when a new version is available.

## Presets

The presets you've saved, each with its name and how many apps it holds. A checkmark marks the preset the current levels match. See [Presets](/Hush/using/presets/) for how they work.

- **Apply** sets every app in the preset to its saved level and puts every other app back at 100% and unmuted.
- The **…** button, or a right-click on the preset, offers **Rename…** and **Delete…**. Hush asks before deleting.
- **Save Current Levels as Preset…** asks for a name and saves the current levels. If the name is already used, Hush asks whether to replace that preset. You can keep up to 20 presets.

Apply and Save are greyed out until Hush has Audio Recording permission.

## Levels

### Remember levels for each output device

Off by default. When it's on, each output device keeps its own app levels and mute states. For example, you can keep your music quiet on the MacBook speakers and louder on your headphones.

- When the output changes to another device, Hush saves the current levels for the old device. If you've used the new device before, its levels come back. If you haven't, the current levels carry over as its starting point, so nothing sounds different until you change something.
- Changes you make, including applying a [preset](/Hush/using/presets/), **Mute All Playing Apps** and **Unmute All**, apply to the current device's levels.
- Switching back to a device brings back its levels.
- Hush tells devices apart by their unique ID, not their name, so a device that briefly disconnects or reappears after sleep keeps its levels.
- Turning it on saves the current levels for the current device.
- Turning it off keeps the current device's levels as the one set of levels for every device, as before. The other devices' saved levels stay in the settings file, so turning it on again brings them back.

While it's on, a list underneath shows every device with saved levels, by name. Click **Forget** to drop a device's saved levels. Forgetting the current device doesn't change what you hear: it only drops the saved copy, and Hush saves the current levels for it again the next time you change something or switch away. With no saved levels, the list reads **No devices have saved levels yet.**

### Hidden apps

Lists the apps you've [hidden from the mixer](/Hush/using/mixer/#hide-an-app), each with its icon (or a generic app icon if Hush can't find the app) and name. Click **Show** to put an app back in the mixer, at 100% and unmuted. With nothing hidden, the list reads **No hidden apps.**

### Reset All Levels…

Puts every app back to 100% and unmuted, and forgets all saved levels, including every output device's saved levels when [Remember levels for each output device](#remember-levels-for-each-output-device) has saved any. Hush asks you to confirm first: **"Reset all app levels?"** Hidden apps stay hidden.

## Updates

Hush tells you when a new version is available. It never downloads or installs anything by itself.

### Check for updates automatically

On by default. About 30 seconds after launch, and then once a day, Hush asks GitHub's public API for the latest release of Hush. If a newer version exists, you get:

- a banner at the top of the mixer;
- a dot on the menu bar icon;
- a macOS notification, once per version. macOS asks for permission to show notifications the first time. If you decline, the banner and dot still appear.

Each of these offers three choices:

| Choice | What it does |
|---|---|
| **Download** | Opens the release in your browser. Clicking the notification itself does the same. |
| **Later** | Hides the banner and dot for 24 hours. |
| **Skip This Version** | Hides them for good, until an even newer version comes out. |

If a check fails, for example because you're offline, Hush tries again after an hour, then after four hours, then daily.

Turn the switch off and Hush makes no network requests at all. To see exactly what the check sends, read the [privacy notes](/Hush/help/privacy/).

### Check Now

Runs a check straight away and shows the result next to the button: **Checking…**, then **Hush is up to date**, **Hush X.Y.Z is available** (with a **Download** link) or **Couldn't check for updates**. When no result is showing and Hush has checked before (the idle state after a previous check), the status reads **Last checked** followed by a relative time, such as "Last checked yesterday". It works even when automatic checks are off.

## About

Shows the version of Hush you're running and a link to the source code on GitHub. Hush is free software under the GNU General Public License v3.0, and comes with no warranty.

## Where settings are stored

Hush keeps everything in one file:

```text
~/Library/Application Support/Hush/settings.json
```

It looks like this:

```json
{
  "apps" : {
    "com.spotify.client" : {
      "isMuted" : false,
      "lastAdjusted" : "2026-11-17T21:04:11Z",
      "percent" : 62
    }
  },
  "preferences" : {
    "appearance" : {
      "accent" : "amber",
      "density" : "comfortable",
      "layout" : "strips",
      "menuBarIcon" : "speaker",
      "showLevelMeters" : true,
      "showPercentages" : true,
      "sortMode" : "activity"
    },
    "maxBoostPercent" : 200,
    "rememberLevelsPerDevice" : false,
    "showInactiveApps" : false
  },
  "updates" : {
    "automaticUpdateChecks" : true,
    "lastUpdateCheck" : "2026-11-17T21:00:02Z"
  },
  "version" : 1
}
```

- Each app is listed by its bundle ID, or by its executable name if it doesn't have one.
- `percent` is clamped to between 0 and your maximum boost when the file is read.
- The `appearance` section holds the [Appearance](#appearance) options. Every key is optional: a missing or unrecognised value uses its default, so files from older versions of Hush load unchanged. The reverse holds too: if a newer Hush wrote a value this version doesn't know, it falls back to the default after a downgrade, and the newer value is lost the next time settings are saved.
- `globalShortcut` appears only once you've set a [keyboard shortcut](#keyboard-shortcut), for example `{ "keyCode" : 4, "modifiers" : ["option", "command"] }`. `keyCode` is the macOS virtual key code (a physical key, so the shortcut survives a keyboard layout change). If it's missing or can't be read, there's no shortcut.
- The `presets` list holds your [presets](/Hush/using/presets/), in order: each has an `id`, a `name`, and an `apps` map with each app's `displayName`, `percent` and `isMuted`. It's missing when you have no presets. A preset that can't be read is skipped, and the rest of the file still loads.
- The `updates` section remembers the update checker's state: whether automatic checks are on, the version you skipped, when "Later" ends and when Hush last checked. It may be missing or partly filled in.
- `rememberLevelsPerDevice` in `preferences` is the [Remember levels for each output device](#remember-levels-for-each-output-device) setting. If it's missing, it's off.
- `deviceLevels` holds each output device's saved levels, keyed by the device's unique ID: each has the device's `name` and an `apps` map like the top-level one, such as `{ "BuiltInSpeakerDevice" : { "name" : "MacBook Pro Speakers", "apps" : { … } } }`. A device with an empty `apps` map plays every app at 100%. It's missing when no device has saved levels, and it stays when you turn the setting off. A device that can't be read is skipped, and the rest of the file still loads.
- `hiddenApps`, present only once you've [hidden an app](#hidden-apps), lists each hidden app's `bundleID` (or executable name) and `displayName`, such as `{ "bundleID" : "com.apple.Safari", "displayName" : "Safari" }`. If it can't be read, Hush ignores it and keeps the rest of the file.
- Hush rewrites the file after every change, so quit Hush before editing it by hand.
- If the file can't be read, for example because it isn't valid JSON or comes from a newer version of Hush, Hush moves it aside as `settings.corrupt-<number>.json` in the same folder and starts with default settings. Your old file isn't deleted.
