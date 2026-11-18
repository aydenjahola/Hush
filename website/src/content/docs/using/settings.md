---
title: Settings
description: Launch at login, maximum boost, showing idle apps, the keyboard shortcut, the mixer's layout and appearance, resetting levels, update checks, and where Hush keeps its settings.
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

## Levels

### Reset All Levels…

Puts every app back to 100% and unmuted, and forgets all saved levels. Hush asks you to confirm first: **"Reset all app levels?"**

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
- The `updates` section remembers the update checker's state: whether automatic checks are on, the version you skipped, when "Later" ends and when Hush last checked. It may be missing or partly filled in.
- Hush rewrites the file after every change, so quit Hush before editing it by hand.
- If the file can't be read, for example because it isn't valid JSON or comes from a newer version of Hush, Hush moves it aside as `settings.corrupt-<number>.json` in the same folder and starts with default settings. Your old file isn't deleted.
